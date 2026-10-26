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
| D. Validación local con Foundry | `forge build` + `forge test` sobre repos de programas verificados, fijado a un commit, FFI apagado | Funciona (MetaMorpho: 148 pasan · 0 fallan) |
| D'. Propiedades del vault en Foundry | Suite ERC-4626 de a16z + invariantes con handler para MetaMorpho (`validate --harness`) | Verificado en la nube sin forge (81/81, 7 de 7 mutaciones); falta la primera corrida en la PC |
| Ciclo desatendido | Una vez por día: A–C, harness con semilla nueva y líneas base; resumen para Claude | Lo registra el dueño (`tools/windows/registrar_ciclo.ps1`) |

## Estructura

```
local/nexus/secresearch/   el motor: catalog, changes, triage, invariants, run, validate, cycle, limits (protegido)
local/nexus/secresearch/harness/   tests de propiedades e invariantes de nexus por repo (Solidity)
local/nexus/devcheck.py    verificación local: sintaxis, lint, tests, rutas protegidas, método
local/nexus/paths.py       carpeta privada NEXUS_HOME (fuera del repo)
local/tests/               tests (test_limits.py está protegido)
tools/protected_paths.py   control de rutas protegidas (CI)
tools/edr/                 verificación de harness sin forge (solc-js + EDR), para la nube
tools/windows/             registro del ciclo desatendido en el Programador de tareas
docs/                      REGLAS (protegido) e INVESTIGACION_SEGURIDAD
```

## Uso en la PC (PowerShell, desde `%USERPROFILE%\nexus\local`)

```powershell
..\.venv\Scripts\python -m nexus.devcheck                    # verificación completa
..\.venv\Scripts\python -m nexus.secresearch.run --selfcheck  # el método atrapa los defectos de referencia
..\.venv\Scripts\python -m nexus.secresearch.run              # corrida real con el catálogo
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho   # Foundry, en local
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho
..\.venv\Scripts\python -m nexus.secresearch.cycle                          # el ciclo completo, una vez
```

El informe queda en `%LOCALAPPDATA%\nexus\secresearch\secresearch.md`.
