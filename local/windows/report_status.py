"""Latido del PC: publica un resumen del estado en la rama `pc-status` de GitHub.

El vigilante de GitHub Actions lo lee y te avisa por mail si el PC deja de reportar o hay
problemas. Nunca incluye secretos: solo status.json, update.json y advertencias del log, filtradas.
Si el push falla (sin credenciales de git), no rompe nada: queda registrado y sigue.
"""
import json
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "local"))
from nexus import paths  # noqa: E402

SECRET_LIKE = re.compile(r"[A-Za-z0-9+/=_-]{28,}")


def redact(line):
    return SECRET_LIKE.sub("[oculto]", line)


def log_tail(n=20):
    p = paths.logs("agent.log")
    if not p.exists():
        return []
    lines = p.read_text(encoding="utf-8", errors="replace").splitlines()[-500:]
    return [redact(x) for x in lines if " WARNING " in x or " ERROR " in x][-n:]


def file_tail(name, n):
    """Últimas n líneas de un log (con cadenas tipo secreto ocultas) para diagnosticar a distancia."""
    p = paths.logs(name)
    if not p.exists():
        return []
    data = p.read_bytes()[-20000:].decode("utf-8", errors="replace")
    return [redact(x) for x in data.splitlines()[-n:]]


def trades_tail(n=4000, max_bytes=1_500_000):
    """Últimas vueltas del modelo vigente, compactas, para analizar pérdidas desde la nube.
    Formato por vuelta: [ts, par, pnl, tipo, segundos, entrada, salida, lab, spread % y volatilidad
    %/min al entrar]. Sin secretos."""
    from nexus import evidence
    p = paths.state("trades.jsonl")
    if not p.exists():
        return []
    with open(p, "rb") as f:
        f.seek(0, 2)
        start = max(0, f.tell() - max_bytes)
        f.seek(start)
        lines = f.read().decode("utf-8", errors="replace").splitlines()[1 if start else 0:]   # 1ª puede venir cortada
    out = []
    for line in lines:
        try:
            t = json.loads(line)
        except ValueError:
            continue
        if t.get("model", 1) >= evidence.FILL_MODEL:
            out.append([round(t["ts"]), t["sym"], t["pnl"], t.get("kind"), t.get("hold_s"), t.get("entry"),
                        t.get("exit"), int(bool(t.get("lab"))), t.get("spread_pct"), t.get("vol_1m_pct")])
    return out[-n:]


def build():
    return {"ts": time.time(), "status": paths.read_json(paths.state("status.json"), {}),
            "update": paths.read_json(paths.state("update.json"), {}), "log_tail": log_tail(),
            "runner_tail": file_tail("runner.log", 10), "stderr_tail": file_tail("agent_stderr.log", 30),
            "kill_switch": paths.kill_file().exists(), "trades_tail": trades_tail()}


def git(d, *a):
    return subprocess.run(["git", "-C", str(d), *a], capture_output=True, text=True)


def main():
    d = paths.home() / "status-repo"
    d.mkdir(exist_ok=True)
    if not (d / ".git").exists():
        git(d, "init", "-q")
        git(d, "remote", "add", "origin", git(REPO, "remote", "get-url", "origin").stdout.strip())
    (d / "pc_status.json").write_text(json.dumps(build(), indent=1, default=str), encoding="utf-8")
    git(d, "checkout", "-q", "--orphan", f"tmp{int(time.time())}")
    git(d, "add", "pc_status.json")
    git(d, "-c", "user.name=nexus-pc", "-c", "user.email=nexus-pc@users.noreply.github.com",
        "commit", "-q", "-m", "latido del PC")
    r = git(d, "push", "-q", "-f", "origin", "HEAD:pc-status")
    print(time.strftime("%Y-%m-%d %H:%M:%S"), "latido publicado" if r.returncode == 0
          else f"no se pudo publicar el latido (¿credenciales de git?): {r.stderr.strip()[:200]}")
    for b in git(d, "branch", "--format=%(refname:short)").stdout.split():
        if b.startswith("tmp") and b != git(d, "branch", "--show-current").stdout.strip():
            git(d, "branch", "-q", "-D", b)


if __name__ == "__main__":
    main()
