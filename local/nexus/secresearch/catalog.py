"""Catálogo de programas de bug bounty AUTORIZADOS, mantenido por el dueño en un YAML.

Un programa solo es "accionable" (el pipeline lo mira) si el dueño lo marcó explícitamente:
  in_scope: true            -> el componente está dentro del alcance publicado
  verified_by_owner: true   -> el dueño leyó el reglamento vigente (alcance, exclusiones, requisitos de PoC)
Sin las dos marcas, el programa queda en el catálogo pero el pipeline lo ignora. El catálogo NO afirma
recompensas ni alcance por su cuenta: eso lo transcribe una persona desde la página oficial del programa.

Formato (secresearch.yaml):
  programs:
    - name: Ejemplo
      platform: Immunefi
      rules_url: https://...                # página oficial del programa (fuente de verdad)
      in_scope: false
      verified_by_owner: false
      specialty: erc4626                    # especialidad de esta iteración
      repos:
        - repo: owner/name                  # repo público del código EN ALCANCE
          paths: ["src/", "contracts/"]     # solo cambios bajo estas rutas
"""
from pathlib import Path

import yaml

from .limits import program_problems as problems  # la regla vive en el archivo protegido


def load(path):
    p = Path(path)
    if not p.exists():
        return []
    data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    return list(data.get("programs") or [])


def actionable(programs):
    """Solo los programas que el dueño habilitó y verificó."""
    return [p for p in programs if not problems(p)]
