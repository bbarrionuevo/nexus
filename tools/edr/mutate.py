"""Mutaciones de referencia: cada defecto inyectado tiene que romper al menos un test del harness.

  python mutate.py <clon> <artefactos.out.json> [M1 M8 B2 ...]   (los artefactos sin mutar, de build.js)

Cada entrada de mutations.json es [nombre, original, mutado] o [nombre, original, mutado, archivo]; sin archivo se muta
src/MetaMorpho.sol. Un archivo de lib/morpho-blue/ recompila Morpho Blue (unidad "morpho"). Los nombres opcionales
filtran qué mutaciones correr. NEXUS_MUT_RUNS="fuzz invRuns invDepth" cambia la intensidad (por defecto "256 64 100").

Si una mutación no rompe nada, el harness tiene un punto ciego: no sirve declararlo verificado. El resumen marca qué
mutaciones detecta NexusVulnerabilityHunter (motivos "H-...") además de las propiedades anteriores.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
DEFAULT_FILE = "src/MetaMorpho.sol"


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


def unit(path):
    """Unidad de build.js que compila `path`."""
    return "morpho" if path.startswith("lib/morpho-blue/") else "metamorpho"


def main(clone, base, only=()):
    runs = os.environ.get("NEXUS_MUT_RUNS", "256 64 100").split()
    missed, by_hunter = [], []
    for entry in json.loads((TOOLS / "mutations.json").read_text(encoding="utf-8")):
        name, old, new = entry[:3]
        path = entry[3] if len(entry) > 3 else DEFAULT_FILE
        if only and name.split()[0] not in only:
            continue
        out = str(TOOLS / "mutante.out.json")
        shutil.copy(base, out)
        env = {**os.environ, "MUTATION": json.dumps({"file": path, "old": old, "new": new})}
        b = subprocess.run(["node", "build.js", clone, out, unit(path)], cwd=TOOLS, env=env, capture_output=True,
                           text=True, timeout=900, check=False)
        if b.returncode:
            print(name, "NO COMPILA", b.stdout[-500:], flush=True)
            missed.append(name)
            continue
        r = subprocess.run(["node", "run_edr.js", clone, out, *runs], cwd=TOOLS, capture_output=True,
                           text=True, timeout=3000, check=False)
        total = [x for x in r.stdout.splitlines() if x.startswith("TOTAL")]
        suites = failures(r.stdout)
        print(f"\n### {name}: {total}", flush=True)
        for suite, tests in suites.items():
            print(f"  {suite}: {len(tests)}  {tests[0]}", flush=True)
        if not suites:
            missed.append(name)
        elif any("<- H-" in t for tests in suites.values() for t in tests):
            by_hunter.append(name.split()[0])
    print(f"\nDetectadas por el cazador (H-...): {', '.join(by_hunter) or 'ninguna'}")
    print("NO DETECTADAS: " + ", ".join(missed) if missed else "Todas las mutaciones detectadas.")
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], tuple(sys.argv[3:])))
