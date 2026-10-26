"""Carpeta privada del motor, FUERA del repositorio (que es público): catálogo, resultados y clones.

NEXUS_HOME manda; si no está, Windows usa %LOCALAPPDATA%\\nexus y el resto ~/.nexus.
"""
import os
from pathlib import Path


def home() -> Path:
    env = os.environ.get("NEXUS_HOME")
    if env:
        base = Path(env)
    elif os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "nexus"
    else:
        base = Path.home() / ".nexus"
    base.mkdir(parents=True, exist_ok=True)
    return base
