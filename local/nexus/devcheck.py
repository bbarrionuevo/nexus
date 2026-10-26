"""Circuito de verificación LOCAL: corre las pruebas del proyecto y deja un informe, sin depender de GitHub.

  python -m nexus.devcheck [OUT_DIR]         (desde la carpeta local/, con el Python del entorno de nexus;
                                             por defecto el informe queda en NEXUS_HOME/devcheck)

Pasos, en orden: sintaxis (compileall) · lint (ruff, solo si está instalado) · tests (pytest) ·
autoprueba del control de rutas protegidas · autoverificación del método de invariantes. De cada
paso registra código de salida, duración y el final del log. Si fallan tests, los vuelve a correr UNA
sola vez (solo los que fallaron) para separar un fallo intermitente de uno real; nunca entra en bucle.
No instala nada ni toca el sistema: usa el intérprete con el que se lo llama.
"""
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

LOCAL = Path(__file__).resolve().parents[1]
REPO = LOCAL.parent
TIMEOUT_S, TAIL, MAX_RETRIES = 900, 25, 1


def _run(cmd, cwd=LOCAL, timeout=TIMEOUT_S):
    t0 = time.time()
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False)
        code, log = r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        code, log = 124, f"tiempo agotado ({timeout} s)"
    except OSError as e:
        code, log = 127, f"no se pudo ejecutar: {e}"
    return {"cmd": " ".join(cmd), "exit": code, "seconds": round(time.time() - t0, 2),
            "tail": log.strip().splitlines()[-TAIL:]}


def steps(py=sys.executable):
    """(nombre, comando o None si falta la herramienta, carpeta). pytest guarda su caché: `--lf` lo necesita."""
    ruff = shutil.which("ruff")
    return [
        ("sintaxis", [py, "-m", "compileall", "-q", "nexus", "tests"], LOCAL),
        ("lint", [ruff, "check", "--line-length", "120", "nexus", "tests"] if ruff else None, LOCAL),
        ("tests", [py, "-m", "pytest", "-q"], LOCAL),
        ("rutas protegidas", [py, "tools/protected_paths.py", "--self-test"], REPO),
        ("método de invariantes", [py, "-m", "nexus.secresearch.run", "--selfcheck"], LOCAL),
    ]


def check(run=_run, plan=None):
    results = []
    for name, cmd, cwd in plan or steps():
        if cmd is None:
            results.append({"step": name, "exit": None, "seconds": 0, "tail": ["omitido: herramienta no instalada"]})
            continue
        r = {"step": name, **run(cmd, cwd)}
        if name == "tests" and r["exit"] not in (0, None):
            for i in range(MAX_RETRIES):                         # solo los que fallaron, una vez
                again = run(cmd + ["--lf"], cwd)
                r["retry"] = {"attempt": i + 1, **again}
                if again["exit"] == 0:
                    r["flaky"] = True
                    break
        results.append(r)
    ok = all(r["exit"] in (0, None) or r.get("flaky") for r in results)
    return {"ts": time.time(), "ok": ok, "python": sys.version.split()[0], "platform": sys.platform,
            "results": results}


def report(rep):
    lines = [f"# Verificación local · {'OK' if rep['ok'] else 'CON FALLOS'}", "",
             f"Python {rep['python']} · {rep['platform']} · {time.strftime('%Y-%m-%d %H:%M', time.localtime(rep['ts']))}",
             "", "| Paso | Resultado | Segundos | Comando |", "|---|---|---|---|"]
    for r in rep["results"]:
        res = ("omitido" if r["exit"] is None else "OK" if r["exit"] == 0
               else "intermitente (pasó al reintentar)" if r.get("flaky") else f"FALLÓ (código {r['exit']})")
        lines.append(f"| {r['step']} | {res} | {r['seconds']} | `{r.get('cmd', '—')}` |")
    for r in rep["results"]:
        if r["exit"] not in (0, None):
            lines += ["", f"## {r['step']}: final del log", "", "```", *r["tail"], "```"]
    return "\n".join(lines) + "\n"


def main(argv):
    from . import paths
    out = Path(argv[0]) if argv else paths.home() / "devcheck"     # fuera del repo: no ensucia el árbol del PC
    out.mkdir(parents=True, exist_ok=True)
    rep = check()
    (out / "devcheck.json").write_text(json.dumps(rep, indent=1, ensure_ascii=False), encoding="utf-8")
    (out / "devcheck.md").write_text(report(rep), encoding="utf-8")
    print(report(rep))
    return 0 if rep["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
