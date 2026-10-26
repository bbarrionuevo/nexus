"""Rutas protegidas: un PR que las toque solo lo aprueba y fusiona el dueño (Claude nunca lo hace).

  python tools/protected_paths.py BASE HEAD     sale con 1 si el cambio toca algo protegido
  python tools/protected_paths.py --self-test   verifica la propia regla de coincidencia

Se protege lo que define los límites de seguridad del motor (docs/REGLAS.md): los límites y su test,
las reglas, el CI y este control. Así ningún agente puede subir topes, ampliar el alcance, habilitar
envíos o desactivar el control por su cuenta.
"""
import subprocess
import sys

PROTECTED = (
    ".github/",                                   # CI, CODEOWNERS y cualquier workflow
    "tools/protected_paths.py",                   # este control
    "local/nexus/secresearch/limits.py",          # topes, alcance verificado, carpeta de resultados, prohibiciones
    "local/tests/test_limits.py",                 # el test que hace cumplir los límites
    "docs/REGLAS.md",
)


def protected(path):
    return any(path == x or (x.endswith("/") and path.startswith(x)) for x in PROTECTED)


def changed(base, head):
    out = subprocess.run(["git", "diff", "--name-only", base, head], capture_output=True, text=True, check=True)
    return [p for p in out.stdout.splitlines() if p]


def self_test():
    assert protected(".github/workflows/nuevo.yml") and protected(".github/CODEOWNERS")
    assert protected("local/nexus/secresearch/limits.py") and protected("local/tests/test_limits.py")
    assert protected("docs/REGLAS.md") and protected("tools/protected_paths.py")
    assert not protected("local/nexus/secresearch/run.py") and not protected("docs/INVESTIGACION_SEGURIDAD.md")
    assert not protected("local/nexus/secresearch/limits.py.bak") and not protected("tools/otro.py")
    print("Autoprueba del control de rutas protegidas: OK")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        sys.exit(0)
    found = [p for p in changed(sys.argv[1], sys.argv[2]) if protected(p)]
    if found:
        print("Cambios en RUTAS PROTEGIDAS (solo los aprueba y fusiona el dueño):")
        print("\n".join(f"  - {x}" for x in found))
        sys.exit(1)
    print("Sin cambios en rutas protegidas.")
