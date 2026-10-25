"""Dashboard local en tiempo real (solo lectura): http://localhost:8765

Muestra lo que hace el agente en la PC (estado, riesgo, evidencia de la estrategia vigente frente al
grupo de control, resultado por clima, curva de ganancias, laboratorio, últimas vueltas) y las
oportunidades del radar (rama `data` del repositorio público, refrescada cada 5 minutos).

Seguridad: escucha SOLO en 127.0.0.1 (no es accesible desde otra máquina), solo responde GET, no
tiene botones ni endpoints que cambien nada, no lee .env y oculta en los logs cualquier cadena con
forma de clave. Si cambia la versión instalada, se cierra para que su lanzador lo reinicie con el
código nuevo.
python -m nexus.dashboard [puerto]
"""
import json
import re
import subprocess
import sys
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import evidence, paths

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
RAW = "https://raw.githubusercontent.com/bbarrionuevo/nexus/data/data/"
RESEARCH_FILES = ("radar.json", "paper_xfunding.json", "paper_carry.json", "stable_mm.json")
SECRET_LIKE = re.compile(r"[A-Za-z0-9+/=_-]{28,}")
RESEARCH = {"ts": 0, "data": {}, "error": None}


def _read_json(name, default=None):
    return paths.read_json(paths.state(name), default)


def _tail_lines(path, max_bytes=2_000_000):
    if not path.exists():
        return []
    with open(path, "rb") as f:
        f.seek(0, 2)
        start = max(0, f.tell() - max_bytes)
        f.seek(start)
        lines = f.read().decode("utf-8", errors="replace").splitlines()
    return lines[1:] if start else lines


TRADES = {"path": None, "offset": 0, "rest": b"", "curves": {}, "last": deque(maxlen=25)}
LOCK = threading.Lock()


def _load_trades():
    """Lee el diario completo una vez y después solo lo agregado: la curva arranca en cero, igual que
    el total de la evidencia, sin releer todo cada 5 segundos. Guarda solo la curva por versión."""
    path = paths.state("trades.jsonl")
    if TRADES["path"] != path or not path.exists() or path.stat().st_size < TRADES["offset"]:
        TRADES.update(path=path, offset=0, rest=b"", curves={}, last=deque(maxlen=25))
    if not path.exists():
        return
    with open(path, "rb") as f:
        f.seek(TRADES["offset"])
        chunk = f.read()
    TRADES["offset"] += len(chunk)
    *lines, TRADES["rest"] = (TRADES["rest"] + chunk).split(b"\n")
    for line in lines:
        try:
            t = json.loads(line)
            if t.get("model", 1) < evidence.FILL_MODEL:
                continue
            ts, pnl = float(t["ts"]), float(t["pnl"])
        except (ValueError, TypeError, KeyError, AttributeError):
            continue
        pts = TRADES["curves"].setdefault(t.get("strategy"), [])
        pts.append([round(ts), round((pts[-1][1] if pts else 0.0) + pnl, 4)])
        TRADES["last"].append({"ts": round(ts), "sym": t.get("sym"), "pnl": pnl, "kind": t.get("kind"),
                               "hold_s": t.get("hold_s"), "strategy": t.get("strategy"),
                               "lab": bool(t.get("lab")), "vol": t.get("vol_1m_pct")})


def _thin(pts, max_points):
    step = max(1, -(-len(pts) // max_points))
    return pts[::step] + ([pts[-1]] if pts and (len(pts) - 1) % step else [])


def trades(strategy_tag, max_points=1500):
    """Vueltas del modelo vigente: curva acumulada de la estrategia vigente y del control + últimas 25."""
    with LOCK:
        _load_trades()
        curves = {name: _thin(TRADES["curves"].get(tag, []), max_points)
                  for name, tag in (("vigente", strategy_tag), ("control", "control"))}
        return curves, list(TRADES["last"])[::-1]


WARN = {"ts": 0.0, "path": None, "lines": []}


def log_tail(n=12, every=30):
    """Últimos avisos del agente. Se lee cada 30 s como mucho: en Windows, tener el log abierto justo
    cuando el agente lo rota haría fallar esa rotación."""
    path = paths.logs("agent.log")
    if time.time() - WARN["ts"] >= every or WARN["path"] != path:
        lines = _tail_lines(path, 200_000)[-400:]
        WARN.update(ts=time.time(), path=path,
                    lines=[SECRET_LIKE.sub("[oculto]", x) for x in lines if " WARNING " in x or " ERROR " in x][-n:])
    return WARN["lines"]


def state_payload(now=None):
    now = now or time.time()
    st = _read_json("status.json", {})
    tag = (st.get("evidence") or {}).get("strategy")
    curves, last = trades(tag)
    return {"now": now, "status": st, "status_age_s": round(now - st["ts"], 1) if st.get("ts") else None,
            "update": _read_json("update.json", {}),
            "paused": {k: v for k, v in _read_json("lab_paused.json", {}).items() if v > now},
            "kill_switch": paths.kill_file().exists(), "curves": curves, "last_trades": last,
            "warnings": log_tail()}


def refresh_research(fetch=None):
    """Baja los JSON de investigación del repo público; si falla, conserva lo último."""
    import requests
    def get(name):
        r = requests.get(RAW + name, timeout=20)
        r.raise_for_status()
        return r.json()
    fetch = fetch or get
    data, errors = dict(RESEARCH["data"]), []
    for name in RESEARCH_FILES:
        try:
            data[name] = fetch(name)
        except Exception as e:                                          # noqa: BLE001 (se informa)
            errors.append(f"{name}: {type(e).__name__}")
    RESEARCH.update(ts=time.time(), data=data, error="; ".join(errors) or None)


def research_payload():
    d = RESEARCH["data"]
    radar = d.get("radar.json") or {}
    return {"ts": RESEARCH["ts"], "error": RESEARCH["error"],
            "rulo": radar.get("rulo"), "cross_border": radar.get("cross_border"),
            "p2p": (radar.get("p2p_spreads") or [])[:5], "hedged_ads": (radar.get("hedged_ads") or [])[:4],
            "cross_funding": (radar.get("cross_funding") or [])[:8], "lending": radar.get("lending") or [],
            "defi": [x for x in radar.get("defi") or [] if x.get("bluechip")][:4],
            "radar_ts": radar.get("ts"), "xfunding": (d.get("paper_xfunding.json") or {}),
            "carry": (d.get("paper_carry.json") or {}), "stable": (d.get("stable_mm.json") or {}).get("pairs", [])[:5]}


def installed_version():
    try:
        return subprocess.run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"], capture_output=True,
                              text=True, timeout=20).stdout.strip()
    except Exception:                                                   # noqa: BLE001
        return None


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype):
        raw = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self' 'unsafe-inline'; "
                                                    "script-src 'self' 'unsafe-inline'; img-src 'self' data:")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):                                                   # noqa: N802 (API de http.server)
        path = self.path.split("?")[0]
        try:
            if path == "/":
                self._send(200, (HERE / "dashboard.html").read_bytes(), "text/html; charset=utf-8")
            elif path == "/api/state":
                self._send(200, json.dumps(state_payload(), default=str), "application/json")
            elif path == "/api/research":
                self._send(200, json.dumps(research_payload(), default=str), "application/json")
            elif path == "/api/health":
                self._send(200, '{"ok": true}', "application/json")
            else:
                self._send(404, "no existe", "text/plain; charset=utf-8")
        except Exception as e:                                          # noqa: BLE001
            self._send(500, json.dumps({"error": type(e).__name__}), "application/json")

    def log_message(self, *args):                                       # sin ruido en consola
        pass


class Server(ThreadingHTTPServer):
    allow_reuse_address = False      # en Windows SO_REUSEADDR deja abrir un puerto ya usado por otro proceso
    daemon_threads = True


def _background(start_version, stop, every=30):
    last_research = 0.0
    while not stop.is_set():
        if time.time() - last_research > 300:
            last_research = time.time()
            try:
                refresh_research()
            except Exception:                                           # noqa: BLE001
                pass
        v = installed_version()
        if start_version and v and v != start_version:                  # versión nueva instalada: reiniciar
            stop.set()
            return
        stop.wait(every)


def main(port=8765, busy_wait=300):
    try:
        server = Server(("127.0.0.1", int(port)), Handler)
    except OSError as e:                                    # puerto ocupado: reintentar sin llenar el log
        print(f"No se pudo abrir el puerto {port}: {e}. Reintento en {busy_wait} s.", flush=True)
        time.sleep(busy_wait)
        return 1
    stop = threading.Event()
    threading.Thread(target=_background, args=(installed_version(), stop), daemon=True).start()
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"Dashboard en http://localhost:{port} (solo esta PC). Ctrl+C para salir.", flush=True)
    try:
        while not stop.wait(5):
            pass
    except KeyboardInterrupt:
        pass
    server.shutdown()


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:2]))
