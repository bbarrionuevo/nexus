"""Panel local de nexus: forge en vivo, campañas y descargas, sin pasar por Claude.

  python -m nexus.secresearch.panel [--port N] [--no-browser]

- Muestra los procesos forge (CPU, memoria, desde cuándo) y cada campaña: estado, corridas, llamadas, reversiones,
  fallas con sus leyes, cobertura por variante y el log en vivo.
- Lanza campañas de `tools/forge_v2` (perfil, corridas, profundidad, semilla, filtro de contratos y fail_on_revert,
  todo validado) en un proyecto reducido propio en NEXUS_HOME/work/panel, y las frena por su PID.
- Lista y descarga lo que hay en NEXUS_HOME/secresearch: campañas, informes de validate, expedientes y etapa E.

Seguridad: atiende solo en 127.0.0.1 con un token aleatorio por arranque (va en la URL que abre; las acciones además
lo piden en el encabezado X-Nexus-Token, contra CSRF) y controla el encabezado Host (contra DNS rebinding). La página
no carga nada de afuera. No envía nada a ningún programa (R-3), los resultados quedan en NEXUS_HOME (R-4) y forge
corre solo con `forge test` y el FFI apagado (R-2, R-6). Cerrar el panel no frena las campañas.
"""
import ctypes
import datetime as dt
import hmac
import json
import os
import re
import secrets
import signal
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from nexus import paths

REPO = Path(__file__).resolve().parents[3]
FORGE_V2 = REPO / "tools" / "forge_v2" / "forge_v2.py"
# perfil de tools/forge_v2 -> clon en NEXUS_HOME/work y prefijo de los contratos del harness
PERFILES = {"vault-v2": ("morpho-org__vault-v2", "NexusVaultV2"),
            "euler-earn": ("euler-xyz__euler-earn", "NexusEulerEarn"),
            "tokenized-strategy": ("yearn__tokenized-strategy", "NexusTokenizedStrategy"),
            "vault-v3": ("yearn__yearn-vaults-v3", "NexusVaultV3"),
            "midnight": ("morpho-org__midnight", "NexusMidnight")}
LAW = re.compile(r"\b(?:YV|MN|[HVEY])-[A-Z]+(?:-\d+)?")
SEED = re.compile(r"^0x[0-9a-f]{1,16}$")
MATCH = re.compile(r"^\^?[A-Za-z0-9]+\$?$")
EXT = {".md", ".txt", ".json", ".html", ".csv"}
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
BREAKAWAY = getattr(subprocess, "CREATE_BREAKAWAY_FROM_JOB", 0)
BELOW_NORMAL = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)


def sec(home=None):
    return Path(home or paths.home()) / "secresearch"


def camp_dir(home=None):
    d = sec(home) / "campanas"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _local(ts=None):
    """Hora local con su zona."""
    t = dt.datetime.now(dt.timezone.utc) if ts is None else dt.datetime.fromtimestamp(ts, dt.timezone.utc)
    return t.astimezone()


def _stamp():
    return _local().isoformat(timespec="seconds")


# --- campañas ---------------------------------------------------------------------------------------------------

def validate_params(p):
    """Parámetros de una campaña nueva, validados: nada llega a un comando sin pasar por acá (ValueError si no)."""
    perfil = p.get("perfil")
    if perfil not in PERFILES:
        raise ValueError(f"perfil desconocido: {perfil!r} (opciones: {', '.join(PERFILES)})")
    try:
        runs, depth = int(p.get("runs", 256)), int(p.get("depth", 500))
    except (TypeError, ValueError):
        raise ValueError("corridas y profundidad tienen que ser números") from None
    if not (1 <= runs <= 4096 and 1 <= depth <= 20000):
        raise ValueError("corridas entre 1 y 4096, profundidad entre 1 y 20000")
    seed = str(p.get("seed") or "").strip().lower() or "0x" + secrets.token_hex(8)
    if not SEED.match(seed):
        raise ValueError("la semilla es hexadecimal: 0x y hasta 16 dígitos")
    match = str(p.get("match") or "").strip()
    if match and not (MATCH.match(match) and match.strip("^$").startswith(PERFILES[perfil][1])):
        raise ValueError(f"el filtro tiene que ser un contrato del harness ({PERFILES[perfil][1]}...)")
    return {"perfil": perfil, "runs": runs, "depth": depth, "seed": seed, "match": match,
            "fail_on_revert": bool(p.get("fail_on_revert"))}


def _rec_path(cid, home=None):
    if not re.fullmatch(r"[\w.-]+", cid or ""):
        raise ValueError("campaña desconocida")
    return camp_dir(home) / f"{cid}.json"


def _save(rec, home=None):
    _rec_path(rec["id"], home).write_text(json.dumps(rec, indent=1, ensure_ascii=False), encoding="utf-8")


def _load(cid, home=None):
    p = _rec_path(cid, home)
    if not p.is_file():
        raise ValueError("campaña desconocida")
    return json.loads(p.read_text(encoding="utf-8"))


def launch(params, home=None):
    """Registra la campaña y la arranca en un proceso aparte (sigue aunque se cierre el panel)."""
    p = validate_params(params)
    home = Path(home or paths.home())
    now = _local()
    cid = f"{now:%Y%m%d-%H%M%S}_{p['perfil']}_{p['runs']}x{p['depth']}_{p['seed']}"
    rec = {**p, "id": cid, "dest": str(home / "work" / "panel" / cid), "log": str(camp_dir(home) / f"{cid}.txt"),
           "started": now.isoformat(timespec="seconds")}
    _save(rec, home)
    # prioridad por debajo de lo normal (la heredan forge_v2 y forge): la campaña usa todo el CPU libre y le cede el
    # paso a lo corto (una verificación, el uso de la PC)
    flags = (subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP | BELOW_NORMAL) if os.name == "nt" else 0
    kw = {"cwd": REPO / "local", "env": {**os.environ, "NEXUS_HOME": str(home)}, "stdin": subprocess.DEVNULL,
          "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL, "start_new_session": os.name != "nt"}
    cmd = [sys.executable, "-m", "nexus.secresearch.panel", "--run", cid]
    # 29-oct: tres campañas lanzadas desde una sesión de Claude Code murieron sin terminar cuando la sesión se reinició:
    # quedaban dentro del job de quien las lanzó. Separada del job, la campaña sigue; si el job no lo permite, queda
    # atada a él como antes.
    try:
        proc = subprocess.Popen(cmd, creationflags=flags | BREAKAWAY, **kw)
    except OSError:
        proc = subprocess.Popen(cmd, creationflags=flags, **kw)
    rec["pid"] = proc.pid
    _save(rec, home)
    return rec


def run_campaign(cid, home=None):
    """Lo que corre el proceso de la campaña: arma el proyecto reducido y corre forge_v2, todo al log."""
    rec = _load(cid, home)
    env = {**os.environ, "NEXUS_PERFIL": rec["perfil"], "FOUNDRY_FFI": "false", "PYTHONUTF8": "1",
           "PATH": os.pathsep.join([str(Path.home() / ".foundry" / "bin"), str(Path(sys.executable).parent),
                                    os.environ.get("PATH", "")])}
    if rec.get("match"):
        env["NEXUS_MATCH"] = rec["match"]
    if rec.get("fail_on_revert"):
        env["FOUNDRY_INVARIANT_FAIL_ON_REVERT"] = "true"
    clone = Path(home or paths.home()) / "work" / PERFILES[rec["perfil"]][0]
    code = 0
    with open(rec["log"], "a", encoding="utf-8") as out:
        out.write(f"INICIO {_stamp()} {cid}\n")
        out.flush()
        for args in (["armar", str(clone), rec["dest"]],
                     ["correr", rec["dest"], str(rec["runs"]), str(rec["depth"]), rec["seed"]]):
            code = subprocess.run([sys.executable, str(FORGE_V2), *args], cwd=REPO, env=env, stdout=out,
                                  stderr=subprocess.STDOUT, creationflags=NO_WINDOW, check=False).returncode
            if code:
                break
        out.write(f"FIN {_stamp()} salida {code}\n")
    rec.update(finished=_stamp(), exit=code)
    _save(rec, home)
    return code


def _proc_started(pid):
    """Hora de creación del proceso (None si no existe o ya terminó)."""
    if os.name != "nt":
        try:
            os.kill(pid, 0)
        except OSError:
            return None
        return 0.0
    k = ctypes.windll.kernel32
    k.OpenProcess.restype = ctypes.c_void_p
    k.GetExitCodeProcess.argtypes = (ctypes.c_void_p, ctypes.c_void_p)
    k.GetProcessTimes.argtypes = (ctypes.c_void_p,) + (ctypes.c_void_p,) * 4
    k.CloseHandle.argtypes = (ctypes.c_void_p,)
    h = k.OpenProcess(0x1000, False, int(pid))                     # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return None
    try:
        code, times = ctypes.c_ulong(), [ctypes.c_ulonglong() for _ in range(4)]
        if not k.GetExitCodeProcess(h, ctypes.byref(code)) or code.value != 259:      # STILL_ACTIVE
            return None
        if not k.GetProcessTimes(h, *(ctypes.byref(t) for t in times)):
            return None
        return times[0].value / 1e7 - 11644473600                                     # FILETIME -> epoch
    finally:
        k.CloseHandle(h)


def _ours(rec):
    """¿Sigue vivo el proceso de la campaña? Además del PID compara la hora de arranque: un PID reciclado por otro
    programa no cuenta (y no se frena)."""
    pid = rec.get("pid")
    started = _proc_started(pid) if pid else None
    if started is None:
        return False
    if os.name != "nt":
        return True
    t0 = dt.datetime.fromisoformat(rec["started"]).timestamp()
    return t0 - 30 <= started <= t0 + 120


def stop(cid, home=None):
    rec = _load(cid, home)
    if not _ours(rec):
        raise ValueError("la campaña no está corriendo")
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(rec["pid"]), "/T", "/F"], capture_output=True,
                       creationflags=NO_WINDOW, check=False)
    else:
        os.killpg(rec["pid"], signal.SIGTERM)
    with open(rec["log"], "a", encoding="utf-8") as out:
        out.write(f"FRENADA {_stamp()} desde el panel\n")
    rec["stopped"] = _stamp()
    _save(rec, home)
    return rec


def parse_log(text):
    """Estado de una campaña desde su log: corridas, llamadas, reversiones, fallas, leyes y cobertura por variante."""
    st = {"suites_ok": 0, "suites_fail": 0, "tests": [], "fails": [], "laws": [], "metrics": {}, "exit": None,
          "stopped": False, "started": None, "reverts_by_action": {}}
    suite = None
    for line in text.splitlines():
        s = line.strip()
        m = re.search(r"Ran \d+ tests? for \S+:(\w+)", s)
        if m:
            suite = m.group(1)
        if s.startswith("Suite result: ok"):
            st["suites_ok"] += 1
        elif s.startswith("Suite result: FAILED"):
            st["suites_fail"] += 1
        m = re.match(r"\[(PASS|FAIL)[^\]]*\]\s+(\w+)\(\)\s*\(runs: (\d+), calls: (\d+), reverts: (\d+)\)", s)
        if m:
            st["tests"].append({"suite": suite, "test": m.group(2), "ok": m.group(1) == "PASS", "runs": int(m.group(3)),
                                "calls": int(m.group(4)), "reverts": int(m.group(5))})
        if s.startswith(("[FAIL", "Error: ")):
            st["fails"].append(s[:400])
            st["laws"].extend(x for x in LAW.findall(s) if x not in st["laws"])
        m = re.match(r"(cobertura|cazador|cota): (.+): (\d+)$", s)
        if m and suite:
            st["metrics"].setdefault(suite, {})[m.group(2)] = int(m.group(3))
        # la tabla de métricas de forge: | contrato | acción | llamadas | reversiones | descartes |
        m = re.match(r"\|\s*\w+\s*\|\s*(\w+)\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*\d+\s*\|$", s)
        if m and suite and int(m.group(2)):
            st["reverts_by_action"].setdefault(suite, {})[m.group(1)] = int(m.group(2))
        m = re.match(r"FIN .* salida (-?\d+)", s)
        if m:
            st["exit"] = int(m.group(1))
        if s.startswith("FRENADA"):
            st["stopped"] = True
        if s.startswith("INICIO") and st["started"] is None:
            st["started"] = s[7:60]
    return st


def _estado(rec, st):
    if rec.get("pid") and rec.get("started") and _ours(rec):
        return "corriendo"
    if st["stopped"]:
        return "frenada"
    if st["exit"] is None:
        return "sin FIN (cortada o corriendo fuera del panel)"
    if st["exit"] == 0 and not st["fails"] and not st["suites_fail"]:
        # 30-oct: una reversión del handler es una secuencia que quedó sin verificar (así aparecieron los bordes de
        # dominio de Midnight, el Vault V3 y TokenizedStrategy), aunque todas las leyes pasen
        return "pasó con reversiones del handler (revisar)" if any(t["reverts"] for t in st["tests"]) else "pasó"
    return "falló"


def campaigns(home=None):
    """Todas las campañas de NEXUS_HOME/secresearch/campanas, con o sin registro del panel."""
    d = camp_dir(home)
    out = []
    for log in sorted(d.glob("*.txt"), key=lambda p: p.stat().st_mtime, reverse=True)[:60]:
        rec_p = d / f"{log.stem}.json"
        rec = json.loads(rec_p.read_text(encoding="utf-8")) if rec_p.is_file() else {"id": log.stem}
        st = parse_log(log.read_text(encoding="utf-8", errors="replace"))
        out.append({**rec, **st, "estado": _estado(rec, st), "log_name": log.name, "size": log.stat().st_size,
                    "mtime": _local(log.stat().st_mtime).isoformat(timespec="seconds")})
    return out


def resumen(cid, home=None):
    """Una campaña en texto, para la terminal: el estado, cada variante, las reversiones del handler por acción, las
    leyes y las fallas. Con reversiones, aunque todo pase, dice cómo investigarlas."""
    rec_p = _rec_path(cid, home)
    log = camp_dir(home) / f"{cid}.txt"
    if not log.is_file():
        raise ValueError("campaña desconocida")
    rec = json.loads(rec_p.read_text(encoding="utf-8")) if rec_p.is_file() else {"id": cid}
    st = parse_log(log.read_text(encoding="utf-8", errors="replace"))
    out = [f"{cid}: {_estado(rec, st)}"]
    for t in st["tests"]:
        out.append(f"  {t['suite']}: {'pasa' if t['ok'] else 'FALLA'} · {t['runs']} corridas · {t['calls']} llamadas"
                   f" · {t['reverts']} reversiones")
        acc = st["reverts_by_action"].get(t["suite"])
        if acc:
            out.append("    reversiones por acción: "
                       + ", ".join(f"{a} {n}" for a, n in sorted(acc.items(), key=lambda x: -x[1])))
    if st["laws"]:
        out.append("  leyes: " + " ".join(st["laws"]))
    out.extend("  " + f for f in st["fails"][:5])
    if any(t["reverts"] for t in st["tests"]):
        out.append("  Hay reversiones del handler: son secuencias sin verificar. Reproducirlas con fail_on_revert y "
                   "varias semillas, y repetir la secuencia guardada con -vvvv (docs/INVESTIGACION_SEGURIDAD.md).")
    return "\n".join(out)


# --- procesos forge y archivos ------------------------------------------------------------------------------------

_procs_cache = {"t": 0.0, "v": []}
_procs_lock = threading.Lock()


def forge_procs():
    """Procesos forge vivos (cacheado 4 s): PID, CPU, memoria, desde cuándo y el comando."""
    with _procs_lock:
        if time.time() - _procs_cache["t"] < 4:
            return _procs_cache["v"]
        out = []
        try:
            if os.name == "nt":
                ps = ("Get-CimInstance Win32_Process -Filter \"Name='forge.exe'\" | Select-Object ProcessId,"
                      "CreationDate,UserModeTime,KernelModeTime,WorkingSetSize,CommandLine | ConvertTo-Json -Compress")
                raw = subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True,
                                     timeout=20, creationflags=NO_WINDOW, check=False).stdout.strip()
                data = json.loads(raw) if raw else []
                for x in [data] if isinstance(data, dict) else data:
                    ms = re.search(r"\d+", str(x.get("CreationDate") or ""))
                    out.append({"pid": x["ProcessId"],
                                "cpu_h": round(((x.get("UserModeTime") or 0) + (x.get("KernelModeTime") or 0)) / 3.6e10, 2),
                                "mem_mb": round((x.get("WorkingSetSize") or 0) / 2**20),
                                "desde": _local(int(ms.group(0)) / 1000).isoformat(timespec="seconds")
                                if ms else "", "cmd": (x.get("CommandLine") or "")[-160:]})
            else:
                raw = subprocess.run(["ps", "-eo", "pid,etime,time,rss,args"], capture_output=True, text=True,
                                     timeout=20, check=False).stdout
                for line in raw.splitlines()[1:]:
                    f = line.split(None, 4)
                    if len(f) == 5 and "forge" in f[4].split()[0]:
                        out.append({"pid": int(f[0]), "desde": f[1], "cpu_h": f[2], "mem_mb": int(f[3]) // 1024,
                                    "cmd": f[4][-160:]})
        except (OSError, ValueError, subprocess.SubprocessError):
            out = []
        _procs_cache.update(t=time.time(), v=out)
        return out


def files(home=None):
    base = sec(home)
    out = []
    for sub in ("campanas", "validate", "expedientes", "etapa_e"):
        d = base / sub
        if not d.is_dir():
            continue
        found = [p for p in d.rglob("*") if p.is_file() and p.suffix in EXT]
        for p in sorted(found, key=lambda x: x.stat().st_mtime, reverse=True)[:200]:
            out.append({"path": p.relative_to(base).as_posix(), "size": p.stat().st_size,
                        "mtime": _local(p.stat().st_mtime).isoformat(timespec="seconds")})
    for name in ("dashboard.html", "para_claude.md", "secresearch.md"):
        p = base / name
        if p.is_file():
            out.append({"path": name, "size": p.stat().st_size,
                        "mtime": _local(p.stat().st_mtime).isoformat(timespec="seconds")})
    return out


def safe_file(rel, home=None):
    """Un archivo de NEXUS_HOME/secresearch por su ruta relativa; None si sale de ahí o no es de un tipo servible."""
    base = sec(home).resolve()
    try:
        p = (base / rel).resolve()
    except (OSError, ValueError):
        return None
    if not p.is_relative_to(base) or not p.is_file() or p.suffix not in EXT:
        return None
    return p


# --- servidor -------------------------------------------------------------------------------------------------------

class Panel(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, addr, token, home):
        super().__init__(addr, Handler)
        self.token, self.home = token, Path(home)


class Handler(BaseHTTPRequestHandler):
    server_version = "nexus-panel"

    def log_message(self, *args):
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8", extra=None):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _host_ok(self):
        port = self.server.server_address[1]
        return self.headers.get("Host", "") in (f"127.0.0.1:{port}", f"localhost:{port}")

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if not self._host_ok() or not hmac.compare_digest(q.get("t", [""])[0], self.server.token):
            return self._send(403, {"error": "prohibido"})
        home = self.server.home
        if u.path == "/":
            csp = ("default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; "
                   "img-src 'self' data:; base-uri 'none'; form-action 'none'")
            return self._send(200, PAGE.encode("utf-8"), "text/html; charset=utf-8", {"Content-Security-Policy": csp})
        if u.path == "/api/state":
            return self._send(200, {"now": _stamp(), "campaigns": campaigns(home), "forge": forge_procs(),
                                    "files": files(home), "perfiles": list(PERFILES)})
        if u.path == "/api/log":
            try:
                rec_log = camp_dir(home) / f"{q.get('id', [''])[0]}.txt"
                start = max(0, int(q.get("from", ["0"])[0]))
            except ValueError:
                return self._send(400, {"error": "pedido inválido"})
            p = safe_file(f"campanas/{rec_log.name}", home)
            if not p:
                return self._send(404, {"error": "no existe"})
            size = p.stat().st_size
            start = start if start <= size else 0
            start = max(start, size - 65536)
            with open(p, "rb") as f:
                f.seek(start)
                chunk = f.read(65536)
            return self._send(200, {"from": start, "next": start + len(chunk),
                                    "text": chunk.decode("utf-8", errors="replace")})
        if u.path == "/api/file":
            p = safe_file(q.get("path", [""])[0], home)
            if not p:
                return self._send(404, {"error": "no existe"})
            return self._send(200, p.read_bytes(), "application/octet-stream",
                              {"Content-Disposition": f'attachment; filename="{p.name}"'})
        return self._send(404, {"error": "no existe"})

    def do_POST(self):
        u = urlparse(self.path)
        if not self._host_ok() or not hmac.compare_digest(self.headers.get("X-Nexus-Token", ""), self.server.token):
            return self._send(403, {"error": "prohibido"})
        n = int(self.headers.get("Content-Length") or 0)
        if n > 10_000:
            return self._send(413, {"error": "demasiado grande"})
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
            if u.path == "/api/launch":
                return self._send(200, launch(body, self.server.home))
            if u.path == "/api/stop":
                return self._send(200, stop(str(body.get("id", "")), self.server.home))
        except (ValueError, TypeError, AttributeError) as e:
            return self._send(400, {"error": str(e)[:300]})
        return self._send(404, {"error": "no existe"})


PAGE = r"""<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Panel de nexus</title><style>
:root{--bg:#fff;--fg:#1d1d1f;--mut:#6e6e73;--line:#d9d9de;--ok:#1a7f37;--bad:#c62828;--run:#0b63c5;--card:#f6f6f8}
@media (prefers-color-scheme:dark){:root{--bg:#141416;--fg:#ececf1;--mut:#9a9aa3;--line:#33333a;--card:#1e1e22;--ok:#4ac26b;--bad:#ff6b6b;--run:#58a6ff}}
body{margin:0;font:14px/1.45 system-ui,Segoe UI,sans-serif;background:var(--bg);color:var(--fg)}
header{padding:12px 16px;border-bottom:1px solid var(--line);display:flex;gap:16px;align-items:baseline;flex-wrap:wrap}
h1{font-size:17px;margin:0}h2{font-size:15px;margin:18px 0 8px}main{padding:0 16px 32px;max-width:1300px}
table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid var(--line);padding:5px 6px;text-align:left;vertical-align:top}
th{color:var(--mut);font-weight:600}.ok{color:var(--ok)}.bad{color:var(--bad)}.run{color:var(--run)}.mut{color:var(--mut)}
.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 12px;margin:8px 0}
button,input,select{font:inherit;padding:4px 8px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--fg)}
button{cursor:pointer}pre{white-space:pre-wrap;word-break:break-word;max-height:420px;overflow:auto;background:var(--card);padding:8px;border-radius:8px;border:1px solid var(--line);font-size:12px}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}a{color:var(--run)}.small{font-size:12px}
</style></head><body><header><h1>Panel de nexus</h1><span class="mut small" id="now"></span>
<span class="mut small">Local y privado: todo sale de NEXUS_HOME y no se envía nada.</span></header><main>
<h2>Procesos forge</h2><div id="forge" class="card mut">cargando…</div>
<h2>Campañas</h2><div id="camps"></div>
<h2>Lanzar una campaña</h2><div class="card"><div class="row">
<label>Perfil <select id="perfil"></select></label>
<label>Corridas <input id="runs" type="number" value="256" min="1" max="4096" style="width:80px"></label>
<label>Profundidad <input id="depth" type="number" value="500" min="1" max="20000" style="width:90px"></label>
<label>Semilla <input id="seed" placeholder="al azar" style="width:170px"></label>
<label>Contrato <input id="match" placeholder="todos" style="width:230px"></label>
<label><input id="for" type="checkbox"> frenar en la primera reversión</label>
<button id="go">Lanzar</button></div><div id="msg" class="small mut" style="margin-top:6px"></div></div>
<h2>Log en vivo <span id="logname" class="mut small"></span></h2><pre id="log" class="mut">Elegí una campaña.</pre>
<h2>Informes y archivos</h2><div class="row small"><input id="filt" placeholder="filtrar" style="width:240px"></div><div id="files"></div>
</main><script>
const T=new URLSearchParams(location.search).get('t');const $=id=>document.getElementById(id);
let sel=null,from=0,files=[];
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function get(u){const r=await fetch(u+(u.includes('?')?'&':'?')+'t='+encodeURIComponent(T));return r.json()}
async function act(u,b){const r=await fetch(u,{method:'POST',headers:{'Content-Type':'application/json','X-Nexus-Token':T},body:JSON.stringify(b)});const j=await r.json();if(!r.ok)throw new Error(j.error||r.status);return j}
function cls(e){return e==='pasó'?'ok':(e==='falló'||e.startsWith('pasó con'))?'bad':e==='corriendo'?'run':'mut'}
function fmt(n){return Number(n).toLocaleString('es-AR')}
async function refresh(){let s;try{s=await get('/api/state')}catch(e){$('now').textContent='sin conexión con el panel';return}
$('now').textContent='actualizado '+s.now;
if(!$('perfil').options.length)$('perfil').innerHTML=s.perfiles.map(p=>`<option>${esc(p)}</option>`).join('');
$('forge').innerHTML=s.forge.length?'<table><tr><th>PID</th><th>desde</th><th>CPU (h)</th><th>memoria (MB)</th><th>comando</th></tr>'+
s.forge.map(f=>`<tr><td>${f.pid}</td><td>${esc(f.desde)}</td><td>${esc(f.cpu_h)}</td><td>${fmt(f.mem_mb)}</td><td class="small">${esc(f.cmd)}</td></tr>`).join('')+'</table>':'No hay procesos forge corriendo.';
$('camps').innerHTML=s.campaigns.map(c=>{const tests=c.tests.map(t=>`<div class="small"><b>${esc(t.suite||t.test)}</b>: <span class="${t.ok?'ok':'bad'}">${t.ok?'pasa':'falla'}</span> · ${fmt(t.runs)} corridas · ${fmt(t.calls)} llamadas · ${fmt(t.reverts)} reversiones</div>`).join('');
const mets=Object.entries(c.metrics||{}).map(([s,m])=>`<details class="small"><summary>cobertura de ${esc(s)}</summary><table>${Object.entries(m).map(([k,v])=>`<tr><td>${esc(k)}</td><td>${fmt(v)}</td></tr>`).join('')}</table></details>`).join('');
const fails=c.fails.length?`<div class="bad small">${c.fails.slice(0,4).map(esc).join('<br>')}</div>`:'';
const laws=c.laws.length?` · leyes: <b class="bad">${esc(c.laws.join(' '))}</b>`:'';
const stopb=c.estado==='corriendo'?`<button data-stop="${esc(c.id)}">Frenar</button>`:'';
return `<div class="card"><div class="row"><b>${esc(c.id)}</b><span class="${cls(c.estado)}">${esc(c.estado)}</span>${laws}
<span class="mut small">suites ok ${c.suites_ok} · con falla ${c.suites_fail} · log ${fmt(c.size)} B · ${esc(c.mtime)}</span>
<button data-log="${esc(c.id)}">Ver log</button><a href="/api/file?path=${encodeURIComponent('campanas/'+c.log_name)}&t=${encodeURIComponent(T)}">descargar</a>${stopb}</div>${tests}${fails}${mets}</div>`}).join('')||'<div class="mut">Todavía no hay campañas.</div>';
files=s.files;drawFiles()}
function drawFiles(){const f=$('filt').value.toLowerCase();$('files').innerHTML='<table><tr><th>archivo</th><th>tamaño</th><th>modificado</th></tr>'+
files.filter(x=>x.path.toLowerCase().includes(f)).map(x=>`<tr><td><a href="/api/file?path=${encodeURIComponent(x.path)}&t=${encodeURIComponent(T)}">${esc(x.path)}</a></td><td>${fmt(x.size)}</td><td>${esc(x.mtime)}</td></tr>`).join('')+'</table>'}
async function tail(){if(!sel)return;try{const j=await get('/api/log?id='+encodeURIComponent(sel)+'&from='+from);
if(j.text){const pre=$('log');const atEnd=pre.scrollTop+pre.clientHeight>=pre.scrollHeight-20;pre.textContent=(from&&j.from===from?pre.textContent:'')+j.text;from=j.next;if(atEnd)pre.scrollTop=pre.scrollHeight}}catch(e){}}
document.addEventListener('click',async e=>{const l=e.target.dataset.log,s=e.target.dataset.stop;
if(l){sel=l;from=0;$('log').textContent='';$('log').classList.remove('mut');$('logname').textContent=l;tail()}
if(s&&confirm('¿Frenar '+s+'?')){try{await act('/api/stop',{id:s});refresh()}catch(err){alert(err.message)}}});
$('go').onclick=async()=>{$('msg').textContent='lanzando…';try{const r=await act('/api/launch',{perfil:$('perfil').value,runs:+$('runs').value,depth:+$('depth').value,seed:$('seed').value,match:$('match').value,fail_on_revert:$('for').checked});
$('msg').textContent='lanzada: '+r.id;sel=r.id;from=0;$('logname').textContent=r.id;refresh()}catch(err){$('msg').textContent='no se lanzó: '+err.message}};
$('filt').oninput=drawFiles;refresh();setInterval(refresh,5000);setInterval(tail,2000);
</script></body></html>"""


def main(argv):
    if argv[:1] == ["--run"] and len(argv) == 2:
        return run_campaign(argv[1])
    if argv[:1] == ["--resumen"] and len(argv) == 2:  # una campaña en la terminal, sin abrir el panel
        print(resumen(argv[1]))
        return 0
    port = 8765
    if "--port" in argv:
        port = int(argv[argv.index("--port") + 1])
    token = secrets.token_urlsafe(24)
    srv = Panel(("127.0.0.1", port), token, paths.home())
    url = f"http://127.0.0.1:{srv.server_address[1]}/?t={token}"
    print(f"Panel de nexus: {url}\nCtrl+C lo cierra; las campañas siguen corriendo.", flush=True)
    if "--no-browser" not in argv:
        webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
