# nexus

Motor de **investigación de seguridad DeFi** para programas de bug bounty **autorizados**. Corre en la
PC del dueño: detecta cambios recientes en el código en alcance de cada programa, los prioriza sin IA y
valida hipótesis con tests locales. **No envía nada ni prueba nada contra contratos desplegados.** Hasta
el 26-oct-2026 este repo era un bot de trading, que el dueño suspendió; ese código queda en el historial
de git.

Reglas: [docs/REGLAS.md](docs/REGLAS.md). Plan, estado y métricas: [docs/INVESTIGACION_SEGURIDAD.md](docs/INVESTIGACION_SEGURIDAD.md).
Para retomar el trabajo desde una conversación nueva: [docs/TRASPASO.md](docs/TRASPASO.md).

## Estado

| Etapa | Qué hace | Estado |
|---|---|---|
| A. Catálogo | Programas autorizados (Morpho, Yearn V3, Euler v2), cargados por el dueño en `NEXUS_HOME/secresearch.yaml` | Funciona |
| A. Cambios | Commits nuevos que tocan contratos en alcance, por git (solo lectura); excluye tests, mocks y scripts | Funciona |
| B. Triaje | Puntaje determinista sin IA, con señales de contabilidad de vaults ERC-4626 | Funciona |
| C. Método de invariantes | Propiedades P0–P6 de un vault ERC-4626, verificadas contra implementaciones de referencia | Funciona |
| D. Validación local con Foundry | `forge build` + `forge test` sobre repos de programas verificados, fijado a un commit, FFI apagado | Funciona (MetaMorpho: 148 pasan · 0 fallan) |
| D'. Propiedades del vault en Foundry | Suite ERC-4626 de a16z + invariantes con handler para MetaMorpho (`validate --harness`), con `NexusVulnerabilityHunter`: contabilidad fantasma y leyes exactas en cada acción, más un entorno multi-mercado con gobierno ([docs](docs/CAZADOR_METAMORPHO.md)) | Verificado en la nube sin forge (sin falsos positivos en 1,5 M de llamadas; 21 de 21 mutaciones, contra 11 del harness original) y en la PC con forge (84 pasan, 0 fallan) |
| D''. Cazadores con forge en la PC | Un cazador por objetivo, con leyes exactas contra el estado real y una batería de mutaciones que prueba que las ve: [Vault V2](docs/CAZADOR_VAULT_V2.md), [EulerEarn](docs/CAZADOR_EULER_EARN.md), [TokenizedStrategy](docs/CAZADOR_TOKENIZED_STRATEGY.md) y [Vault V3](docs/CAZADOR_VAULT_V3.md) de Yearn, [Midnight](docs/CAZADOR_MIDNIGHT.md), [MidnightBundlesV2](docs/CAZADOR_MIDNIGHT_BUNDLES.md) y [BlueBundlesV1](docs/CAZADOR_BLUE_BUNDLES.md) de Morpho. `tools/forge_v2` arma un proyecto reducido por objetivo y corre con el fuzzing guiado por cobertura de forge; el panel local lanza y sigue las campañas, con un corpus que se acumula entre campañas del mismo harness | Verificados en la PC: sin falsos positivos y todas sus mutaciones detectadas. Sin hallazgos |
| Ciclo desatendido | Una vez por día: A–C, harness con semilla nueva y líneas base; resumen para Claude con fallas y cobertura por acción; al terminar lanza la campaña rotativa (una profunda del cazador que hace más que no corre, si no hay otra corriendo) | Lo registra el dueño (`tools/windows/registrar_ciclo.ps1`) |
| Dashboard | Página local con el estado: fallas para revisar, cobertura por acción, métricas del cazador, corridas, programas, cambios pendientes, ciclos y expedientes. Se regenera al terminar cada ciclo y cada `validate` | Funciona |
| F. Expediente | Borrador del informe para reclamar la recompensa, armado desde una falla: programa y reglas, commit, semilla, contraejemplo, comando para reproducir y las secciones que piden los programas | Funciona; lo completa y envía el dueño |

## Estructura

```
local/nexus/secresearch/   el motor: catalog, changes, triage, invariants, run, validate, cycle, dashboard,
                           expediente, limits (protegido)
local/nexus/secresearch/harness/   tests de propiedades e invariantes de nexus por repo (Solidity)
local/nexus/devcheck.py    verificación local: sintaxis, lint, tests, rutas protegidas, método
local/nexus/paths.py       carpeta privada NEXUS_HOME (fuera del repo)
local/tests/               tests (test_limits.py está protegido)
tools/protected_paths.py   control de rutas protegidas (CI)
tools/edr/                 verificación de harness sin forge (solc-js + EDR); histórica: Claude trabaja solo en la PC
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
..\.venv\Scripts\python -m nexus.secresearch.dashboard                      # abre el dashboard en el navegador
..\.venv\Scripts\python -m nexus.secresearch.expediente INFORME              # expediente de una falla confirmada
```

Todo queda en `%LOCALAPPDATA%\nexus\secresearch\` (privado, fuera del repo): el dashboard en `dashboard.html`, los
informes de Foundry en `validate\`, los expedientes en `expedientes\` y el de cambios en `secresearch.md`. El
Explorador oculta `AppData`; se abre con `explorer $env:LOCALAPPDATA\nexus\secresearch`.
