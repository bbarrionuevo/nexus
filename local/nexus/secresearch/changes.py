"""Etapa A: cambios recientes del código EN ALCANCE, solo lectura.

Por cada repo autorizado lista los commits recientes que tocan las rutas del alcance y los archivos de
contratos cambiados (con su parche). Dos fuentes con el mismo resultado:
- recent_git (por defecto): clon superficial con git. Sin límite de la API (sin token son 60 consultas
  por hora), reproducible por commit y funciona igual en la PC del dueño y en la nube.
- recent (API REST de GitHub): alternativa; GITHUB_TOKEN opcional solo para subir el límite.
Solo LEE historial público: no ejecuta el código del repo ni toca ninguna cadena. Un libro de "ya
vistos" (JSONL de SHA) evita reanalizar lo mismo tras reinicios. Topes: operaciones de red por corrida
y commits por repo (nunca tráfico intensivo).
"""
import json
import os
import re
import subprocess
from pathlib import Path

API = "https://api.github.com"
CONTRACT_EXT = (".sol", ".vy")
# Tests, mocks, scripts y specs de verificación formal nunca están en el alcance de un bug bounty. En la
# primera vista previa (26-oct, 6 repos de Morpho, Yearn y Euler) eran el 49% de los archivos y 11 de las
# 19 alertas de prioridad alta: puro ruido.
# Sin ventana de consola en Windows: el ciclo desatendido corre con pythonw y cada git/forge abriría una.
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
NOT_SCOPE = re.compile(r"(^|/)(tests?|mocks?|scripts?|certora|echidna|medusa|halmos|foundry_tests)/"
                       r"|\.t\.sol$|\.s\.sol$|(^|/)Mock\w*\.sol$", re.IGNORECASE)


class Budget:
    """Tope de llamadas a la API por corrida. Al agotarse, se corta y se informa (no se reintenta)."""

    def __init__(self, max_calls):
        self.max, self.used = max_calls, 0

    def take(self):
        if self.used >= self.max:
            return False
        self.used += 1
        return True


def _http_get(url, params=None):
    import requests
    h = {"Accept": "application/vnd.github+json", "User-Agent": "nexus-secresearch"}
    if os.environ.get("GITHUB_TOKEN"):
        h["Authorization"] = f"Bearer {os.environ['GITHUB_TOKEN']}"
    r = requests.get(url, params=params, headers=h, timeout=(5, 20))
    r.raise_for_status()
    return r.json()


def seen(ledger):
    p = Path(ledger)
    if not p.exists():
        return set()
    return {json.loads(x)["sha"] for x in p.read_text(encoding="utf-8").splitlines() if x.strip()}


def remember(ledger, rec):
    p = Path(ledger)
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"sha": rec["sha"], "repo": rec["repo"], "date": rec["date"]}) + "\n")


def _in_scope(filename, paths):
    return (filename.endswith(CONTRACT_EXT) and not NOT_SCOPE.search(filename)
            and (not paths or any(filename.startswith(x) for x in paths)))


def recent(repo, paths, budget, done=(), max_commits=10, get=_http_get):
    """Commits nuevos (no vistos) de `repo` que tocan contratos bajo `paths`, con sus parches."""
    out = []
    if not budget.take():
        return out, "tope de llamadas a la API alcanzado"
    commits = get(f"{API}/repos/{repo}/commits", {"per_page": max_commits})
    for c in commits[:max_commits]:
        sha = c["sha"]
        if sha in done:
            continue
        if not budget.take():
            return out, "tope de llamadas a la API alcanzado"
        detail = get(f"{API}/repos/{repo}/commits/{sha}")
        files = [{"filename": f["filename"], "patch": f.get("patch", ""), "status": f.get("status")}
                 for f in detail.get("files") or [] if _in_scope(f["filename"], paths)]
        if files:
            out.append({"repo": repo, "sha": sha, "url": c.get("html_url"),
                        "date": (c.get("commit") or {}).get("committer", {}).get("date"),
                        "message": ((c.get("commit") or {}).get("message") or "").splitlines()[0][:200],
                        "files": files})
    return out, None


GIT = ("git", "-c", "core.longpaths=true")


def _git(args, cwd=None, timeout=180, exe=GIT):
    # UTF-8 explícito y errors="replace": en Windows el texto por defecto es cp1252, que no decodifica bytes
    # como 0x81 (presentes en salidas UTF-8 válidas); una salida así rompía la lectura (26-oct).
    # core.longpaths: los submódulos anidados de euler-earn (EVK → EVC → OpenZeppelin) pasan los 260 caracteres
    # de ruta de Windows y el clon fallaba (28-oct); `-c` vale para esta llamada y sus hijos, sin tocar la
    # configuración global. Fuera de Windows git lo ignora.
    r = subprocess.run([*exe, *args], cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       timeout=timeout, check=False, creationflags=NO_WINDOW)
    if r.returncode:
        raise RuntimeError(f"git {args[0]}: {(r.stderr or r.stdout).strip()[:200]}")
    return r.stdout


def recent_git(repo, paths, budget, done=(), max_commits=10, workdir="repos", url=None):
    """Como recent(), con git: clona superficial la primera vez y después solo trae lo nuevo."""
    d = Path(workdir) / repo.replace("/", "__")
    if not budget.take():
        return [], "tope de operaciones de red alcanzado"
    depth = str(max_commits * 5)                        # los commits que tocan las rutas pueden estar más atrás
    if (d / "HEAD").exists() or (d / ".git").exists():
        _git(["fetch", "--quiet", "--depth", depth, "origin"], cwd=d)
    else:
        d.parent.mkdir(parents=True, exist_ok=True)
        _git(["clone", "--quiet", "--no-checkout", "--depth", depth, url or f"https://github.com/{repo}.git", str(d)])
    shallow = d / ".git" / "shallow"
    boundary = set(shallow.read_text().split()) if shallow.exists() else set()   # borde del clon: diff falso
    log = _git(["log", "--format=%H%x1f%cI%x1f%s", "-n", str(max_commits), "origin/HEAD", "--", *paths], cwd=d)
    out = []
    for line in log.splitlines():
        sha, date, msg = line.split("\x1f", 2)
        if sha in done or sha in boundary:
            continue
        names = _git(["show", "--format=", "--name-only", sha, "--", *paths], cwd=d).split()
        files = [{"filename": f, "status": "modified",
                  "patch": _git(["show", "--format=", sha, "--", f], cwd=d)}
                 for f in names if _in_scope(f, paths)]
        if files:
            out.append({"repo": repo, "sha": sha, "url": f"https://github.com/{repo}/commit/{sha}",
                        "date": date, "message": msg[:200], "files": files})
    return out, None
