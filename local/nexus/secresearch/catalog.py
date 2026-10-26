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

REQUIRED = ("name", "rules_url", "repos")


def load(path):
    p = Path(path)
    if not p.exists():
        return []
    data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    return list(data.get("programs") or [])


def problems(prog):
    """Qué le falta a un programa para ser accionable (lista vacía = listo)."""
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


def actionable(programs):
    """Solo los programas que el dueño habilitó y verificó."""
    return [p for p in programs if not problems(p)]
