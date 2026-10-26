"""Mutaciones de referencia: cada defecto inyectado en MetaMorpho tiene que romper al menos un test del harness.

  python mutate.py <clon> <artefactos.out.json>      (los artefactos sin mutar, de build.js)

Si una mutación no rompe nada, el harness tiene un punto ciego: no sirve declararlo verificado.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent


def failures(stdout):
    """{suite: [test <- motivo]} de las fallas que imprime run_edr.js."""
    suites, cur = {}, None
    for line in stdout.splitlines():
        if line.startswith("== "):
            cur = line[3:].split(" (")[0]
        elif line.strip().startswith("Failure"):
            test = line.strip().split()[1].split("(")[0]
            why = line.split("motivo: ")[1][:120] if "motivo: " in line else ""
            suites.setdefault(cur, []).append(f"{test}  <- {why}" if why else test)
    return suites


def main(clone, base):
    missed = []
    for name, old, new in json.loads((TOOLS / "mutations.json").read_text(encoding="utf-8")):
        out = str(TOOLS / "mutante.out.json")
        shutil.copy(base, out)
        env = {**os.environ, "MUTATION": json.dumps({"file": "src/MetaMorpho.sol", "old": old, "new": new})}
        b = subprocess.run(["node", "build.js", clone, out, "metamorpho"], cwd=TOOLS, env=env, capture_output=True,
                           text=True, timeout=900, check=False)
        if b.returncode:
            print(name, "NO COMPILA", b.stdout[-500:], flush=True)
            missed.append(name)
            continue
        r = subprocess.run(["node", "run_edr.js", clone, out, "256", "64", "100"], cwd=TOOLS, capture_output=True,
                           text=True, timeout=1500, check=False)
        total = [x for x in r.stdout.splitlines() if x.startswith("TOTAL")]
        suites = failures(r.stdout)
        print(f"\n### {name}: {total}", flush=True)
        for suite, tests in suites.items():
            print(f"  {suite}: {len(tests)}  {tests[0]}", flush=True)
        if not suites:
            missed.append(name)
    print("\nNO DETECTADAS: " + ", ".join(missed) if missed else "\nTodas las mutaciones detectadas.")
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
