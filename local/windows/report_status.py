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


def build():
    return {"ts": time.time(), "status": paths.read_json(paths.state("status.json"), {}),
            "update": paths.read_json(paths.state("update.json"), {}), "log_tail": log_tail(),
            "kill_switch": paths.kill_file().exists()}


def git(d, *a):
    return subprocess.run(["git", "-C", str(d), *a], capture_output=True, text=True)


def main():
    d = paths.home() / "status-repo"
    d.mkdir(exist_ok=True)
    if not (d / ".git").exists():
        git(d, "init", "-q")
        git(d, "remote", "add", "origin", git(REPO, "remote", "get-url", "origin").stdout.strip())
    (d / "pc_status.json").write_text(json.dumps(build(), indent=1, default=str))
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
