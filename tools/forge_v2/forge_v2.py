"""Harness de Vault V2 con forge sobre un proyecto reducido: compila en ~30 s en vez de ~11 min (en la PC).

  python tools/forge_v2/forge_v2.py armar CLON DESTINO
  python tools/forge_v2/forge_v2.py correr DESTINO CORRIDAS PROFUNDIDAD SEMILLA
  python tools/forge_v2/forge_v2.py mutar DESTINO CLON [V1 V7 ...]

armar: copia de CLON (un clon de morpho-org/vault-v2 con submódulos, p. ej. el de validate en NEXUS_HOME/work) solo lo
que usa el harness: VaultV2, la factory, interfaces y librerías, el ERC20Mock, forge-std y el ERC20 de OpenZeppelin, con
los mismos ajustes de compilación del foundry.toml del repo (solc 0.8.28, via_ir, optimizer 100000, cancun): el
bytecode de VaultV2 es el mismo. correr: copia el harness de nexus y corre las tres variantes. mutar: la batería de
mutaciones.json; cada mutación tiene que hacer fallar al menos una ley V-... (el motivo trae "[leyes: ...]").

Todo en local con FFI apagado (REGLAS R-2 y R-6): solo forge build y forge test. La referencia sigue siendo
`python -m nexus.secresearch.validate morpho-org/vault-v2 --harness morpho-org__vault-v2`, sobre el repo entero.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
HARNESS = HERE.parents[1] / "local" / "nexus" / "secresearch" / "harness" / "morpho-org__vault-v2"
SOURCES = ("src/VaultV2.sol", "src/VaultV2Factory.sol", "test/mocks/ERC20Mock.sol",
           # variante B: el adapter real y los imports que hacen compilar Morpho Blue y la IRM (solc 0.8.19)
           "src/adapters/MorphoMarketV1AdapterV2.sol", "src/adapters/MorphoMarketV1AdapterV2Factory.sol",
           "src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol",
           "src/adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol",
           "src/imports/MorphoImport.sol", "src/imports/AdaptiveCurveIrmImport.sol")
TREES = ("src/interfaces", "src/libraries", "lib/forge-std", "lib/openzeppelin-contracts/contracts",
         "lib/morpho-blue/src", "lib/morpho-blue-irm/src", "lib/morpho-blue-irm/lib/morpho-blue/src")
# Sin solc_version: como en el repo, cada archivo usa el solc de su pragma (VaultV2 0.8.28, Morpho Blue 0.8.19).
FOUNDRY_TOML = """# Proyecto reducido de nexus para el harness de Vault V2: mismos ajustes que el foundry.toml del repo.
[profile.default]
src = "src"
test = "test"
libs = ["lib"]
via_ir = true
optimizer = true
optimizer_runs = 100000
bytecode_hash = "none"
evm_version = "cancun"
ffi = false
ignored_error_codes = ["transient-storage"]
ignored_warnings_from = ["lib"]

[[profile.default.compilation_restrictions]]
paths = "src/imports/MorphoImport.sol"
optimizer_runs = 999999
evm_version = "paris"

[[profile.default.additional_compiler_profiles]]
name = "999999-paris"
optimizer_runs = 999999
evm_version = "paris"

[lint]
lint_on_build = false
"""


def armar(clone, dest):
    clone, dest = Path(clone), Path(dest)
    if dest.exists():
        shutil.rmtree(dest)
    for rel in SOURCES:
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(clone / rel, dest / rel)
    for rel in TREES:
        shutil.copytree(clone / rel, dest / rel)
    (dest / "test" / "nexus").mkdir(parents=True)
    (dest / "foundry.toml").write_text(FOUNDRY_TOML, encoding="utf-8")
    print(f"proyecto reducido en {dest}")


def _env(runs, depth, seed, **extra):
    return {**os.environ, "FOUNDRY_INVARIANT_RUNS": str(runs), "FOUNDRY_INVARIANT_DEPTH": str(depth),
            "FOUNDRY_FUZZ_SEED": seed, **extra, "FOUNDRY_FFI": "false"}


def _harness(dest):
    for f in HARNESS.glob("*.sol"):
        shutil.copy2(f, Path(dest) / "test" / "nexus" / f.name)


def correr(dest, runs, depth, seed):
    _harness(dest)
    env = _env(runs, depth, seed, FOUNDRY_INVARIANT_SHOW_METRICS="true")
    b = _build(dest, env)
    if b.returncode:
        print((b.stdout + b.stderr)[-2000:])
        return b.returncode
    return subprocess.run([shutil.which("forge"), "test", "--match-contract", "^NexusVaultV2", "-vv"], cwd=dest,
                          env=env, check=False).returncode


def _laws(res):
    """[(suite, leyes o motivo)] de las variantes que fallaron, desde la salida de forge test --json. forge 1.8 puede
    dejar `reason` en null y poner el motivo de cada invariante en `invariant_failures`."""
    hits = []
    for suite, data in res.items():
        for t in (data.get("test_results") or {}).values():
            if t.get("status") != "Failure":
                continue
            reasons = [t.get("reason") or ""] + [f.get("reason") or "" for f in t.get("invariant_failures") or []]
            reason = " | ".join(r for r in reasons if r)
            laws = dict.fromkeys(x for m in re.findall(r"\[leyes: ([^\]]*)\]", reason) for x in m.split())
            hits.append((suite.split(":")[-1], " ".join(laws) or reason[:160] or "(sin motivo)"))
    return hits


def _build(dest, env):
    """forge build del proyecto entero: con un filtro de tests, forge test solo compila lo que esos tests importan, y
    Morpho Blue y la IRM (que se despliegan con deployCode) quedarían sin compilar."""
    return subprocess.run([shutil.which("forge"), "build"], cwd=dest, env=env, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=3600, check=False)


def mutar(dest, clone, only=()):
    """Cada mutación de mutaciones.json ([nombre, original, mutado] sobre src/VaultV2.sol, o [nombre, original, mutado,
    archivo]) se aplica a una copia limpia de ese archivo tomada de CLON. NEXUS_MUT_RUNS="corridas profundidad
    semilla" (por defecto "64 200 0x2a")."""
    dest = Path(dest)
    runs, depth, seed = os.environ.get("NEXUS_MUT_RUNS", "64 200 0x2a").split()
    env = _env(runs, depth, seed, FOUNDRY_INVARIANT_SHRINK_RUN_LIMIT="0")
    _harness(dest)
    touched = {}
    missed = []
    try:
        for entry in json.loads((HERE / "mutaciones.json").read_text(encoding="utf-8")):
            name, old, new = entry[:3]
            rel = entry[3] if len(entry) > 3 else "src/VaultV2.sol"
            if only and name.split()[0] not in only:
                continue
            pristine = touched.setdefault(rel, (Path(clone) / rel).read_text(encoding="utf-8"))
            for other, text in touched.items():
                (dest / other).write_text(text, encoding="utf-8")
            if pristine.count(old) != 1:
                print(f"{name}: NO APLICA", flush=True)
                missed.append(name)
                continue
            (dest / rel).write_text(pristine.replace(old, new), encoding="utf-8")
            # forge guarda cada falla en cache/invariant y la reproduce primero en la corrida siguiente: sin borrarla,
            # una mutación heredaría el contraejemplo de la anterior.
            shutil.rmtree(dest / "cache" / "invariant", ignore_errors=True)
            b = _build(dest, env)
            if b.returncode:
                print(f"{name}: NO COMPILA {(b.stdout + b.stderr)[-600:]}", flush=True)
                missed.append(name)
                continue
            r = subprocess.run([shutil.which("forge"), "test", "--match-contract", "^NexusVaultV2", "--json"], cwd=dest,
                               env=env, capture_output=True, text=True, encoding="utf-8", errors="replace",
                               timeout=3600, check=False)
            start = r.stdout.find("{")
            if start < 0:
                print(f"{name}: NO COMPILA {(r.stdout + r.stderr)[-600:]}", flush=True)
                missed.append(name)
                continue
            hits = _laws(json.loads(r.stdout[start:]))
            print(f"{name}: " + ("; ".join(f"{s}: {laws}" for s, laws in hits) if hits else "NO DETECTADA"), flush=True)
            if not hits:
                missed.append(name)
    finally:
        for rel, text in touched.items():
            (dest / rel).write_text(text, encoding="utf-8")
        shutil.rmtree(dest / "cache" / "invariant", ignore_errors=True)
    print("NO DETECTADAS: " + ", ".join(missed) if missed else "Todas las mutaciones detectadas.")
    return 1 if missed else 0


def main(argv):
    if len(argv) >= 3 and argv[0] == "armar":
        return armar(argv[1], argv[2]) or 0
    if len(argv) == 5 and argv[0] == "correr":
        return correr(*argv[1:])
    if len(argv) >= 3 and argv[0] == "mutar":
        return mutar(argv[1], argv[2], tuple(argv[3:]))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
