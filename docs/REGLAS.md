# Reglas del motor de investigación (ARCHIVO PROTEGIDO)

Estas reglas las cambia el dueño, o Claude con la autorización expresa del dueño en el chat para ese cambio puntual.
Así se hizo el 30-oct-2026: el dueño autorizó cambiar las reglas para automatizar el flujo (R-1, R-9 y las nuevas R-11
a R-13). Un PR que toque este archivo, `local/nexus/secresearch/limits.py`, `local/tests/test_limits.py`,
`tools/protected_paths.py` o `.github/` deja en rojo el control de rutas protegidas: lo fusiona el dueño, o Claude
solo con esa autorización expresa (R-11).

| # | Regla | Cómo se hace cumplir |
|---|---|---|
| R-1 | Solo programas de bug bounty **autorizados**, con el código y la actividad dentro del alcance publicado. Un programa nuevo lo habilita el dueño. Dentro de un programa ya habilitado, Claude puede sumar al catálogo un repo que el reglamento vigente incluya en el alcance, con la fuente (la página de direcciones o el listado del programa), y lo anota en el traspaso | El catálogo ignora un programa hasta que el dueño marca `in_scope` y `verified_by_owner` después de leer el reglamento vigente (`limits.program_problems`, test) |
| R-2 | **Nunca** se prueba nada contra contratos desplegados, testnets públicas, billeteras ajenas ni sistemas de terceros. La validación es en local; un fork local solo si el reglamento lo permite | El código no contiene envíos, firmas ni transmisión de transacciones (`limits.FORBIDDEN`, test) |
| R-3 | **Nada se envía automáticamente.** Cada informe lo revisa, decide y envía el dueño | Ídem (`limits.FORBIDDEN`) |
| R-4 | Los resultados son **privados**: quedan en la PC del dueño (`NEXUS_HOME`), nunca en el repo, que es público. Un posible hallazgo publicado sería divulgar una vulnerabilidad sin reportar | `limits.results_dir` se niega a escribir dentro del repo (test) |
| R-5 | Sin tráfico intensivo: topes de operaciones de red, commits y tiempo por corrida | `limits.MAX_*` (test que verifica el tope de red) |
| R-6 | Código de terceros = código no confiable: solo se compila y testea el de programas verificados, con FFI de Foundry siempre apagado, y nunca se corren scripts de despliegue de esos repos | `limits.repo_in_scope` y `limits.FOUNDRY_ENV` (FFI forzado en cada comando, test); `forge script`, `--broadcast` y `cast send` prohibidos en el código |
| R-7 | No se exageran impactos ni severidades. Un candidato es "confirmado" solo con un test local reproducible que muestre el efecto económico | Proceso (docs/INVESTIGACION_SEGURIDAD.md) |
| R-8 | Sin secretos, claves privadas ni datos personales en el repo ni en los informes | `.gitignore`; el motor no usa claves (GITHUB_TOKEN es opcional y solo de lectura) |
| R-9 | Ningún agente amplía el alcance, sube topes, cambia estas reglas ni se asigna permisos por su cuenta: solo con la autorización expresa del dueño en el chat para ese cambio puntual | Rutas protegidas + CODEOWNERS |
| R-10 | Solo cuenta como ingreso una recompensa **cobrada**; una estimada no | Métricas (docs/INVESTIGACION_SEGURIDAD.md) |
| R-11 | **Fusiones.** Claude fusiona sus propios PR a `main` cuando se cumplen tres cosas: el CI está en verde (los tests y el control de rutas protegidas), `nexus.devcheck` pasó sin fallas y el PR no tiene conflictos. Un PR que toque rutas protegidas lo fusiona el dueño, o Claude con su autorización expresa para ese cambio. Después de fusionar, `git pull` en `main` | Proceso (CLAUDE.md y PROMPT_SESION_PC.md) y CI. `main` no tiene protección de rama en GitHub: la regla la cumple el proceso |
| R-12 | **Solo en la PC.** Claude trabaja en este proyecto únicamente en sesiones en la PC del dueño, nunca en la nube. El trabajo necesita `NEXUS_HOME`, los clones, forge y el catálogo, que existen solo en la PC (R-4) | Proceso (CLAUDE.md) |
| R-13 | **Valor esperado.** Se trabaja sobre la última versión desplegada y en alcance de cada protocolo, en programas con recompensa vigente. El objetivo siguiente se elige por valor esperado: la recompensa del programa para ese código por la probabilidad de un hallazgo válido (código nuevo o poco auditado, contabilidad compleja, pocos duplicados posibles). Cuando un objetivo deja de rendir, se cambia | Proceso: el traspaso lleva la tabla de objetivos con ese criterio |
