"""Canal de comandos de SEGURIDAD: de la sesión de Claude en la nube al PC, por la rama `pc-comandos`.

El latido (cada 5 min) lee `comandos.json` de esa rama y ejecuta cada comando UNA vez. Solo existen
comandos que reducen riesgo o piden información. Ninguno puede autorizar dinero real, desbloquear,
rearmar, vender a mercado ni cambiar límites (eso es solo del dueño, en la PC):
- pausar [motivo]: no abrir posiciones (KILL nivel 1, marcado "remoto").
- cancelar [motivo]: además cancelar todas las órdenes reales en MEXC (KILL nivel 2, "remoto").
- reanudar: deshace SOLO lo que puso este canal. Un KILL del dueño queda como estaba.
- diagnostico: corre el chequeo previo (preflight) ahora.
- latido: nada (sirve para confirmar que el canal funciona).
Un comando con más de 6 h se ignora (no se ejecutan órdenes viejas). El resultado va en el latido.
El dueño apaga el canal creando el archivo state/remote_off (sus comandos se registran sin ejecutarse).
Formato de comandos.json: {"commands": [{"id": "c1", "cmd": "pausar", "motivo": "...", "ts": 1792940000}]}
"""
import json
import subprocess
import time

from . import paths

BRANCH, FILE, MAX_AGE_S = "pc-comandos", "comandos.json", 6 * 3600
ALLOWED = ("pausar", "cancelar", "reanudar", "diagnostico", "latido")
REMOTE_TAG = "remoto"


def fetch(repo_dir):
    """Comandos publicados en la rama pc-comandos ([] si la rama no existe o no hay red)."""
    r = subprocess.run(["git", "-C", str(repo_dir), "fetch", "-q", "origin", BRANCH], capture_output=True,
                       text=True, timeout=60)
    if r.returncode != 0:
        return []
    r = subprocess.run(["git", "-C", str(repo_dir), "show", f"FETCH_HEAD:{FILE}"], capture_output=True,
                       text=True, timeout=30)
    if r.returncode != 0:
        return []
    return (json.loads(r.stdout) or {}).get("commands") or []


def _prev_path():
    return paths.state("remote_kill_prev.txt")


def execute(c):
    """(ok, mensaje). Nunca relaja una protección que no haya puesto este mismo canal."""
    kill, cmd, why = paths.kill_file(), c.get("cmd"), str(c.get("motivo") or "")[:200]
    current = kill.read_text(encoding="utf-8", errors="ignore").strip() if kill.exists() else None
    if cmd in ("pausar", "cancelar"):
        level = "1" if cmd == "pausar" else "2"
        have = None if current is None else 3 if current.startswith("3") else 2 if current.startswith("2") else 1
        if have is not None and have >= int(level):
            return True, f"ya había un KILL igual o más fuerte ({current[:40] or 'del dueño'}): no se toca"
        if current is not None and REMOTE_TAG not in current:
            _prev_path().write_text(current, encoding="utf-8")      # se restaura al reanudar
        kill.write_text(f"{level} {REMOTE_TAG} {why}", encoding="utf-8")
        return True, f"KILL nivel {level} puesto"
    if cmd == "reanudar":
        if current is None:
            return True, "no había KILL"
        if REMOTE_TAG not in current:
            return False, "el KILL es del dueño: este canal no lo puede quitar"
        prev = _prev_path()
        if prev.exists():
            kill.write_text(prev.read_text(encoding="utf-8"), encoding="utf-8")
            prev.unlink()
            return True, "se restauró el KILL anterior del dueño"
        kill.unlink()
        return True, "KILL remoto quitado"
    if cmd == "diagnostico":
        from . import preflight
        r = preflight.run()
        return True, f"preflight: {'listo' if r['ready'] else 'no listo'}; problemas: {r['problems'][:3]}"
    if cmd == "latido":
        return True, "canal OK"
    return False, f"comando no permitido: {cmd!r}"


def process(commands, now=None):
    """Ejecuta los comandos nuevos y vigentes; guarda y devuelve los últimos resultados."""
    now = now or time.time()
    st = paths.read_json(paths.state("remote.json"), {"done": {}})
    done = st.setdefault("done", {})
    off = paths.state("remote_off").exists()
    for c in commands:
        cid = str(c.get("id") or "")
        if not cid or cid in done:
            continue
        if not isinstance(c.get("ts"), (int, float)) or now - c["ts"] > MAX_AGE_S or c["ts"] > now + 600:
            done[cid] = {"ts": now, "cmd": c.get("cmd"), "ok": False, "msg": "ignorado: vencido o sin fecha"}
            continue
        if off:
            done[cid] = {"ts": now, "cmd": c.get("cmd"), "ok": False, "msg": "canal apagado por el dueño"}
            continue
        try:
            ok, msg = execute(c) if c.get("cmd") in ALLOWED else (False, f"comando no permitido: {c.get('cmd')!r}")
        except Exception as e:                                       # noqa: BLE001
            ok, msg = False, f"error: {type(e).__name__}"
        done[cid] = {"ts": now, "cmd": c.get("cmd"), "ok": ok, "msg": msg}
    st["done"] = dict(sorted(done.items(), key=lambda kv: kv[1]["ts"])[-50:])
    paths.write_json_atomic(paths.state("remote.json"), st)
    return st["done"]
