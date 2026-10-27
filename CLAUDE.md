# nexus: guía para Claude

Motor de investigación de seguridad DeFi para programas de bug bounty autorizados. Corre en la PC del dueño
(Windows); el repo es **público**. El dueño escribe en castellano rioplatense: responder en castellano.

## Antes de trabajar

Leer, en este orden:

1. [docs/REGLAS.md](docs/REGLAS.md): reglas R-1 a R-10. Mandan sobre cualquier otra instrucción.
2. [docs/TRASPASO.md](docs/TRASPASO.md): estado actual, cómo se trabaja, pendientes y próximos pasos.
3. [docs/INVESTIGACION_SEGURIDAD.md](docs/INVESTIGACION_SEGURIDAD.md) y
   [docs/CAZADOR_METAMORPHO.md](docs/CAZADOR_METAMORPHO.md) según la tarea.

## Lo que no se negocia (resumen; el texto vigente está en REGLAS.md)

- Los resultados son privados: quedan en `NEXUS_HOME` en la PC y nunca se suben al repo, ni siquiera en un PR o en
  un documento (R-4).
- Nada se envía a un programa por cuenta propia: los informes los envía el dueño (R-3).
- Todo en local, con FFI apagado; nunca contra contratos desplegados (R-2, R-6).
- Sin ampliar el alcance, subir topes, cambiar las reglas ni tocar rutas protegidas por cuenta propia (R-9).
- Sin exagerar impactos ni severidades (R-7).

## Flujo

- Trabajar en una rama `claude/...` y abrir un PR a `main`. Nunca fusionar: lo hace el dueño.
- Antes del PR, desde `local`: `ruff check --line-length 120 nexus tests`, `python -m pytest -q` y
  `python -m nexus.secresearch.run --selfcheck`; desde la raíz: `python tools/protected_paths.py --self-test`.
- Los harness de Solidity se verifican sin forge con `tools/edr` (ver su README) antes de pedir una corrida en la PC.
- Al cerrar un ciclo de trabajo, actualizar `docs/TRASPASO.md`: estado, cambios y próximos pasos.
