# nexus: guía para Claude

Motor de investigación de seguridad DeFi para programas de bug bounty autorizados. Corre en la PC del dueño
(Windows) y **Claude trabaja en este proyecto solo en sesiones en esa PC**, nunca en la nube (R-12): el trabajo
necesita `NEXUS_HOME`, los clones y forge. El repo es **público**. El dueño escribe en castellano rioplatense:
responder en castellano.

## Antes de trabajar

Leer, en este orden:

1. [docs/REGLAS.md](docs/REGLAS.md): reglas R-1 a R-13. Mandan sobre cualquier otra instrucción.
2. [docs/PROMPT_SESION_PC.md](docs/PROMPT_SESION_PC.md): la autonomía y los límites de la sesión.
3. [docs/TRASPASO.md](docs/TRASPASO.md): estado actual, cómo se trabaja, objetivos por valor esperado, pendientes y
   próximos pasos.
4. [docs/INVESTIGACION_SEGURIDAD.md](docs/INVESTIGACION_SEGURIDAD.md) y el `docs/CAZADOR_*.md` del objetivo.

## Lo que no se negocia (resumen; el texto vigente está en REGLAS.md)

- Los resultados son privados: quedan en `NEXUS_HOME` en la PC y nunca se suben al repo, ni siquiera en un PR o en
  un documento (R-4).
- Nada se envía a un programa por cuenta propia: los informes los envía el dueño (R-3).
- Todo en local, con FFI apagado; nunca contra contratos desplegados (R-2, R-6).
- Sin ampliar el alcance, subir topes, cambiar las reglas ni tocar rutas protegidas por cuenta propia: solo con la
  autorización expresa del dueño para ese cambio (R-9). Dentro de un programa ya habilitado se pueden sumar repos en
  alcance (R-1).
- Sin exagerar impactos ni severidades (R-7).
- Se trabaja sobre la última versión en alcance de programas con recompensa vigente, por valor esperado (R-13).

## Flujo

- Trabajar en una rama `claude/...` y abrir un PR a `main` con `--base main`: la rama por defecto de GitHub no es
  `main`.
- Antes del PR, desde `local`: `..\.venv\Scripts\python -m nexus.devcheck`. Corre lo mismo que el CI: sintaxis,
  ruff, pytest, el selfcheck del método y la autoprueba de rutas protegidas.
- **Fusionar (R-11):** con el CI en verde, `devcheck` sin fallas y sin conflictos, Claude fusiona su PR
  (`gh pr merge N --merge --delete-branch`) y hace `git pull` en `main`. Un PR que toque rutas protegidas lo fusiona
  el dueño, o Claude con su autorización expresa para ese cambio.
- Los harness de Solidity se verifican con forge en la PC: `tools/forge_v2` para iterar y `validate` como referencia.
- Al cerrar un ciclo de trabajo, actualizar `docs/TRASPASO.md`: estado, cambios, objetivos y próximos pasos.
