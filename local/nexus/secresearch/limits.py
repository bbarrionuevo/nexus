"""Límites de seguridad de la investigación. ARCHIVO PROTEGIDO: lo cambia el dueño, o Claude con su autorización
expresa para ese cambio.

Un PR que toque este archivo (o su test, tests/test_limits.py) deja en rojo el control de rutas
protegidas (tools/protected_paths.py): Claude no lo fusiona sin esa autorización (docs/REGLAS.md, R-11). Ningún
agente puede ampliar el alcance, subir los topes ni habilitar envíos o transacciones por su cuenta.
"""
from pathlib import Path

# Topes por corrida (nunca tráfico intensivo contra servicios de terceros).
MAX_NETWORK_OPS = 40          # git: 1 por repo; API: 1 por lista + 1 por commit
MAX_COMMITS = 10              # commits nuevos por repo
MAX_SECONDS = 300             # duración máxima de una corrida

# Validación local con Foundry (etapa D): tiempos máximos por paso; los repos compilan con via_ir (lento).
MAX_BUILD_SECONDS = 2400
MAX_TEST_SECONDS = 3600
# Variables que se fuerzan en CADA comando de Foundry, sin importar lo que diga el foundry.toml del repo:
# FFI apagado (si no, los tests de un repo ajeno pueden ejecutar comandos en la PC; Yearn lo trae prendido).
FOUNDRY_ENV = {"FOUNDRY_FFI": "false"}

REPO = Path(__file__).resolve().parents[3]

# Lo que el código de investigación NUNCA contiene: enviar informes o datos a terceros, firmar o
# transmitir transacciones, manejar claves privadas. tests/test_limits.py lo verifica en todo el paquete.
FORBIDDEN = ("requests.post", ".post(", "requests.put", "requests.patch", "eth_sendRawTransaction",
             "sendTransaction", "private_key", "PRIVATE_KEY", "--broadcast", "cast send", "forge script")

REQUIRED = ("name", "rules_url", "repos")


def program_problems(prog):
    """Qué le falta a un programa del catálogo para que el pipeline lo analice (vacío = listo).
    Sin las dos marcas del dueño (alcance publicado y reglamento leído) no se analiza nada."""
    out = [f"falta '{k}'" for k in REQUIRED if not prog.get(k)]
    if not str(prog.get("rules_url", "")).startswith("https://"):
        out.append("rules_url debe ser la página oficial (https)")
    if prog.get("in_scope") is not True:
        out.append("in_scope no está en true (confirmar el alcance publicado)")
    if prog.get("verified_by_owner") is not True:
        out.append("verified_by_owner no está en true (el dueño debe leer el reglamento vigente)")
    for r in prog.get("repos") or []:
        if "/" not in str(r.get("repo", "")):
            out.append(f"repo inválido: {r.get('repo')!r} (formato owner/name)")
    return out


def repo_in_scope(repo, programs):
    """Programa verificado al que pertenece `repo`, o None. La etapa D (que compila y ejecuta código
    ajeno en la PC) solo corre sobre repos de programas que el dueño verificó."""
    for prog in programs:
        if not program_problems(prog) and any(r.get("repo") == repo for r in prog.get("repos") or []):
            return prog
    return None


def results_dir(path):
    """Los resultados nunca quedan dentro del repo, que es PÚBLICO: un posible hallazgo publicado sería
    divulgar una vulnerabilidad sin reportar."""
    out = Path(path)
    if out.resolve().is_relative_to(REPO):
        raise SystemExit(f"Los resultados no pueden quedar dentro del repo público ({REPO}): usá otra carpeta.")
    return out
