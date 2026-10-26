# Reglas del motor de investigación (ARCHIVO PROTEGIDO)

Estas reglas solo las cambia el dueño. Un PR que toque este archivo, `local/nexus/secresearch/limits.py`,
`local/tests/test_limits.py`, `tools/protected_paths.py` o `.github/` deja en rojo el control de rutas
protegidas, y **Claude nunca fusiona un PR así**.

| # | Regla | Cómo se hace cumplir |
|---|---|---|
| R-1 | Solo programas de bug bounty **autorizados**, con el código y la actividad dentro del alcance publicado | El catálogo ignora un programa hasta que el dueño marca `in_scope` y `verified_by_owner` después de leer el reglamento vigente (`limits.program_problems`, test) |
| R-2 | **Nunca** se prueba nada contra contratos desplegados, testnets públicas, billeteras ajenas ni sistemas de terceros. La validación es en local; un fork local solo si el reglamento lo permite | El código no contiene envíos, firmas ni transmisión de transacciones (`limits.FORBIDDEN`, test) |
| R-3 | **Nada se envía automáticamente.** Cada informe lo revisa, decide y envía el dueño | Ídem (`limits.FORBIDDEN`) |
| R-4 | Los resultados son **privados**: quedan en la PC del dueño (`NEXUS_HOME`), nunca en el repo, que es público. Un posible hallazgo publicado sería divulgar una vulnerabilidad sin reportar | `limits.results_dir` se niega a escribir dentro del repo (test) |
| R-5 | Sin tráfico intensivo: topes de operaciones de red, commits y tiempo por corrida | `limits.MAX_*` (test que verifica el tope de red) |
| R-6 | Código de terceros = código no confiable: solo se compila y testea el de programas verificados, con FFI de Foundry siempre apagado, y nunca se corren scripts de despliegue de esos repos | `limits.repo_in_scope` y `limits.FOUNDRY_ENV` (FFI forzado en cada comando, test); `forge script`, `--broadcast` y `cast send` prohibidos en el código |
| R-7 | No se exageran impactos ni severidades. Un candidato es "confirmado" solo con un test local reproducible que muestre el efecto económico | Proceso (docs/INVESTIGACION_SEGURIDAD.md) |
| R-8 | Sin secretos, claves privadas ni datos personales en el repo ni en los informes | `.gitignore`; el motor no usa claves (GITHUB_TOKEN es opcional y solo de lectura) |
| R-9 | Ningún agente amplía el alcance, sube topes, cambia estas reglas ni se asigna permisos por su cuenta | Rutas protegidas + CODEOWNERS |
| R-10 | Solo cuenta como ingreso una recompensa **cobrada**; una estimada no | Métricas (docs/INVESTIGACION_SEGURIDAD.md) |
