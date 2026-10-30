"""Harness de Vault V2 con forge sobre un proyecto reducido: compila en ~30 s en vez de ~11 min (en la PC).

  python tools/forge_v2/forge_v2.py armar CLON DESTINO
  python tools/forge_v2/forge_v2.py correr DESTINO CORRIDAS PROFUNDIDAD SEMILLA
  python tools/forge_v2/forge_v2.py mutar DESTINO CLON [V1 V7 ...]

armar: copia de CLON (un clon de morpho-org/vault-v2 con submódulos, p. ej. el de validate en NEXUS_HOME/work) solo lo
que usa el harness: VaultV2, la factory, interfaces y librerías, el ERC20Mock, forge-std y el ERC20 de OpenZeppelin, con
los mismos ajustes de compilación del foundry.toml del repo (solc 0.8.28, via_ir, optimizer 100000, cancun): el
bytecode de VaultV2 es el mismo. correr: copia el harness de nexus y corre las tres variantes. mutar: la batería de
mutaciones.json; cada mutación tiene que hacer fallar al menos una ley V-... (el motivo trae "[leyes: ...]").

NEXUS_PERFIL=euler-earn hace lo mismo con EulerEarn (su harness, sus fuentes y mutaciones_euler_earn.json), y
NEXUS_PERFIL=tokenized-strategy con TokenizedStrategy de Yearn V3 (mutaciones_tokenized_strategy.json).

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
           "src/imports/MorphoImport.sol", "src/imports/AdaptiveCurveIrmImport.sol",
           # el Blue Public Allocator (periferia en alcance), sobre la misma infraestructura de la variante B
           "src/periphery/blue-public-allocator/BluePublicAllocator.sol",
           "src/periphery/blue-public-allocator/interfaces/IBluePublicAllocator.sol")
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


# Perfil de EulerEarn (euler-xyz/euler-earn @ a8cc099, lo desplegado): solo src, OpenZeppelin, el EVC y forge-std. El
# repo entero no compila con forge 1.8.6 (forge-std duplicado entre EVK y permit2 en sus tests), y el harness no los usa.
EE_FOUNDRY_TOML = """# Proyecto reducido de nexus para el harness de EulerEarn: mismos ajustes que el foundry.toml del repo.
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.26"
via_ir = true
optimizer = true
optimizer_runs = 200
evm_version = "cancun"
ffi = false
remappings = ["ethereum-vault-connector/=lib/ethereum-vault-connector/src/"]

[lint]
lint_on_build = false
"""
# Perfil de TokenizedStrategy (yearn/tokenized-strategy @ v3.1.0, lo desplegado en 0x310f…1e76): TokenizedStrategy,
# BaseStrategy, sus interfaces y la librería, OpenZeppelin 4.9.5 y forge-std 1.5.2, sin los tests del repo (viven en
# src/test), con los ajustes del foundry.toml del repo (solc 0.8.18, sin via_ir, 200 runs, paris).
TS_FOUNDRY_TOML = """# Proyecto reducido de nexus para el harness de TokenizedStrategy: mismos ajustes que el foundry.toml del repo.
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.18"
evm_version = "paris"
optimizer = true
optimizer_runs = 200
ffi = false
remappings = [
    "forge-std/=lib/forge-std/src/",
    "ds-test/=lib/forge-std/lib/ds-test/src/",
    "@openzeppelin/=lib/openzeppelin-contracts/",
]

[lint]
lint_on_build = false
"""
# Perfil del Vault V3 de Yearn (yearn/yearn-vaults-v3 @ v3.1.0, lo desplegado en 0xdD3F…7824): VaultV3.vy y
# VaultFactory.vy (Vyper 0.3.10, compilados por forge con el vyper del venv), OpenZeppelin 4.9.5 y forge-std, con los
# ajustes del repo (solc 0.8.18, paris, vyper optimize codesize).
YV_FOUNDRY_TOML = """# Proyecto reducido de nexus para el harness del Vault V3: mismos ajustes que el foundry.toml del repo.
[profile.default]
src = "contracts"
out = "out"
libs = ["lib"]
solc = "0.8.18"
evm_version = "paris"
ffi = false
remappings = [
    "forge-std/=lib/forge-std/src/",
    "ds-test/=lib/forge-std/lib/ds-test/src/",
    "@openzeppelin/=lib/openzeppelin-contracts/",
]

[profile.default.vyper]
optimize = "codesize"

[lint]
lint_on_build = false
"""
# Perfil de Morpho Midnight (morpho-org/midnight @ la etiqueta 2026-08-24, el núcleo desplegado en 0x4716…045f): el
# núcleo (Midnight.sol, sus librerías e interfaces) y forge-std, con los ajustes del repo (solc 0.8.34, osaka, via_ir,
# 466 runs). La periferia queda afuera: compila aparte y con via_ir haría más lenta cada iteración.
MN_FOUNDRY_TOML = """# Proyecto reducido de nexus para el harness de Midnight: mismos ajustes que el foundry.toml del repo.
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.34"
evm_version = "osaka"
via_ir = true
optimizer = true
optimizer_runs = 466
bytecode_hash = "none"
ffi = false
remappings = [
    "forge-std/=lib/forge-std/src/",
]

[lint]
lint_on_build = false
"""
PERFILES = {
    "vault-v2": {"harness": HARNESS, "sources": SOURCES, "trees": TREES, "toml": FOUNDRY_TOML,
                 "match": "^NexusVaultV2", "mutaciones": HERE / "mutaciones.json", "archivo": "src/VaultV2.sol"},
    "euler-earn": {"harness": HARNESS.parent / "euler-xyz__euler-earn", "sources": (),
                   "trees": ("src", "lib/forge-std", "lib/openzeppelin-contracts/contracts",
                             "lib/ethereum-vault-connector/src"),
                   "toml": EE_FOUNDRY_TOML, "match": "^NexusEulerEarn",
                   "mutaciones": HERE / "mutaciones_euler_earn.json", "archivo": "src/EulerEarn.sol",
                   "ref": "a8cc099"},
    "tokenized-strategy": {"harness": HARNESS.parent / "yearn__tokenized-strategy",
                           "sources": ("src/TokenizedStrategy.sol", "src/BaseStrategy.sol"),
                           "trees": ("src/interfaces", "src/libraries", "lib/forge-std",
                                     "lib/openzeppelin-contracts/contracts"),
                           "toml": TS_FOUNDRY_TOML, "match": "^NexusTokenizedStrategy",
                           "mutaciones": HERE / "mutaciones_tokenized_strategy.json",
                           "archivo": "src/TokenizedStrategy.sol", "ref": "8c8929f"},
    "vault-v3": {"harness": HARNESS.parent / "yearn__yearn-vaults-v3",
                 "sources": ("contracts/VaultV3.vy", "contracts/VaultFactory.vy"),
                 "trees": ("lib/forge-std", "lib/openzeppelin-contracts/contracts"),
                 "toml": YV_FOUNDRY_TOML, "match": "^NexusVaultV3",
                 "mutaciones": HERE / "mutaciones_vault_v3.json", "archivo": "contracts/VaultV3.vy", "ref": "5b698f9"},
    "midnight": {"harness": HARNESS.parent / "morpho-org__midnight", "sources": ("src/Midnight.sol",),
                 "trees": ("src/libraries", "src/interfaces", "lib/forge-std"), "toml": MN_FOUNDRY_TOML,
                 "match": "^NexusMidnight", "mutaciones": HERE / "mutaciones_midnight.json",
                 "archivo": "src/Midnight.sol", "ref": "14e0b77"},
}


def _perfil():
    """NEXUS_PERFIL elige el repo: vault-v2 (por defecto), euler-earn, tokenized-strategy, vault-v3 o midnight."""
    nombre = os.environ.get("NEXUS_PERFIL", "vault-v2")
    if nombre not in PERFILES:
        raise SystemExit(f"NEXUS_PERFIL desconocido: {nombre} (opciones: {', '.join(PERFILES)})")
    return PERFILES[nombre]


def _submodulos_fuera(status, rels):
    """De la salida de `git submodule status`, los submódulos de los que se copia algo (`rels`) que no están en el
    commit que fija el repo ('+'), que no están iniciados ('-') o que tienen conflictos ('U')."""
    fuera = []
    for ln in status.splitlines():
        partes = ln.split()
        if len(partes) < 2 or ln[:1] not in "+-U":
            continue
        sub = partes[1]
        if any(rel == sub or rel.startswith(sub + "/") for rel in rels):
            fuera.append(sub)
    return fuera


def _clon_fijado(clone, perfil):
    """El clon tiene que estar en lo desplegado (`ref`), y sus submódulos en lo que ese commit fija: un proyecto
    armado o una mutación sobre otro commit probaría otra cosa. El ciclo desatendido comparte los clones de
    NEXUS_HOME/work y los mueve al último commit para sus líneas base (30-oct: Midnight, Vault V3, TokenizedStrategy
    y EulerEarn con su EVC); volver a `ref` no mueve los submódulos."""
    ref = perfil.get("ref")
    if not ref:
        return
    head = subprocess.run(["git", "-C", str(clone), "rev-parse", "HEAD"], capture_output=True, text=True,
                          check=False).stdout.strip()
    if not head.startswith(ref):
        raise SystemExit(f"el clon está en {head[:10] or '?'} y no en {ref} (lo desplegado): "
                         f"git -C {clone} checkout {ref}")
    status = subprocess.run(["git", "-C", str(clone), "submodule", "status"], capture_output=True, text=True,
                            encoding="utf-8", errors="replace", check=False).stdout
    fuera = _submodulos_fuera(status, (*perfil["sources"], *perfil["trees"]))
    if fuera:
        raise SystemExit(f"submódulos que no están en lo que fija {ref}: {', '.join(fuera)}: "
                         f"git -C {clone} submodule update --init {' '.join(fuera)}")


def armar(clone, dest):
    clone, dest = Path(clone), Path(dest)
    perfil = _perfil()
    _clon_fijado(clone, perfil)
    if dest.exists():
        shutil.rmtree(dest)
    for rel in perfil["sources"]:
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(clone / rel, dest / rel)
    for rel in perfil["trees"]:
        shutil.copytree(clone / rel, dest / rel)
    (dest / "test" / "nexus").mkdir(parents=True)
    (dest / "foundry.toml").write_text(perfil["toml"], encoding="utf-8")
    print(f"proyecto reducido en {dest}")


def _env(runs, depth, seed, **extra):
    # el vyper del venv (perfil vault-v3) tiene que estar en el PATH de forge
    path = os.pathsep.join([str(Path(sys.executable).parent), os.environ.get("PATH", "")])
    return {**os.environ, "PATH": path, "FOUNDRY_INVARIANT_RUNS": str(runs), "FOUNDRY_INVARIANT_DEPTH": str(depth),
            "FOUNDRY_FUZZ_SEED": seed, **extra, "FOUNDRY_FFI": "false"}


def _harness(dest):
    for f in _perfil()["harness"].glob("*.sol"):
        shutil.copy2(f, Path(dest) / "test" / "nexus" / f.name)


def correr(dest, runs, depth, seed):
    _harness(dest)
    env = _env(runs, depth, seed, FOUNDRY_INVARIANT_SHOW_METRICS="true")
    b = _build(dest, env)
    if b.returncode:
        print((b.stdout + b.stderr)[-2000:])
        return b.returncode
    match = os.environ.get("NEXUS_MATCH", _perfil()["match"])  # una variante sola, p. ej. desde el panel
    return subprocess.run([shutil.which("forge"), "test", "--match-contract", match, "-vv"], cwd=dest,
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
    semilla" (por defecto "64 200 0x2a"); NEXUS_MUT_MATCH, el filtro de contratos (por defecto "^NexusVaultV2": todas
    las variantes; "^NexusVaultV2Invariant" corre solo la variante A, que es la única con gobierno)."""
    dest = Path(dest)
    runs, depth, seed = os.environ.get("NEXUS_MUT_RUNS", "64 200 0x2a").split()
    perfil = _perfil()
    _clon_fijado(clone, perfil)  # la copia limpia de cada mutación sale del clon
    match = os.environ.get("NEXUS_MUT_MATCH", perfil["match"])
    env = _env(runs, depth, seed, FOUNDRY_INVARIANT_SHRINK_RUN_LIMIT="0")
    _harness(dest)
    touched = {}
    missed = []
    try:
        for entry in json.loads(perfil["mutaciones"].read_text(encoding="utf-8")):
            name, old, new = entry[:3]
            rel = entry[3] if len(entry) > 3 else perfil["archivo"]
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
            r = subprocess.run([shutil.which("forge"), "test", "--match-contract", match, "--json"], cwd=dest,
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
