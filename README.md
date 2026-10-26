# nexus

Motor de **investigación de seguridad DeFi** para programas de bug bounty **autorizados**. Corre en la
PC del dueño: detecta cambios recientes en el código en alcance de cada programa, los prioriza sin IA y
valida hipótesis con tests locales. **No envía nada ni prueba nada contra contratos desplegados.** Hasta
el 26-oct-2026 este repo era un bot de trading, que el dueño suspendió; ese código queda en el historial
de git.

Reglas: [docs/REGLAS.md](docs/REGLAS.md). Plan, estado y métricas: [docs/INVESTIGACION_SEGURIDAD.md](docs/INVESTIGACION_SEGURIDAD.md).

## Estado

| Etapa | Qué hace | Estado |
|---|---|---|
| A. Catálogo | Programas autorizados (Morpho, Yearn V3, Euler v2), cargados por el dueño en `NEXUS_HOME/secresearch.yaml` | Funciona |
| A. Cambios | Commits nuevos que tocan contratos en alcance, por git (solo lectura); excluye tests, mocks y scripts | Funciona |
| B. Triaje | Puntaje determinista sin IA, con señales de contabilidad de vaults ERC-4626 | Funciona |
| C. Método de invariantes | Propiedades P0–P6 de un vault ERC-4626, verificadas contra implementaciones de referencia | Funciona |
| D. Validación con Foundry | Las propiedades como tests de invariantes contra el código en alcance, en local | Pendiente: próximo paso |

## Estructura

```
local/nexus/secresearch/   el motor: catalog, changes, triage, invariants, run, limits (protegido)
local/nexus/devcheck.py    verificación local: sintaxis, lint, tests, rutas protegidas, método
local/nexus/paths.py       carpeta privada NEXUS_HOME (fuera del repo)
local/tests/               tests (test_limits.py está protegido)
tools/protected_paths.py   control de rutas protegidas (CI)
docs/                      REGLAS (protegido) e INVESTIGACION_SEGURIDAD
```

## Uso en la PC (PowerShell, desde `%USERPROFILE%\nexus\local`)

```powershell
..\.venv\Scripts\python -m nexus.devcheck                    # verificación completa
..\.venv\Scripts\python -m nexus.secresearch.run --selfcheck  # el método atrapa los defectos de referencia
..\.venv\Scripts\python -m nexus.secresearch.run              # corrida real con el catálogo
```

El informe queda en `%LOCALAPPDATA%\nexus\secresearch\secresearch.md`.
