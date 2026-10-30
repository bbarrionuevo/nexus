# Traspaso: estado de nexus y cómo continuar

Documento de entrega para retomar el proyecto desde cualquier conversación nueva con Claude. Actualizado el
30-oct-2026. Si algo de acá contradice al código, manda el código; si contradice a [REGLAS.md](REGLAS.md), mandan
las reglas.

Para arrancar una sesión que trabaje directo en la PC del dueño, con acceso a GitHub, el prompt de arranque está en
[PROMPT_SESION_PC.md](PROMPT_SESION_PC.md).

## 1. Qué es nexus

Un motor de **investigación de seguridad DeFi** para programas de bug bounty **autorizados**. Corre en la PC del
dueño (Windows), busca errores en vaults ERC-4626 con tests locales y prepara el informe para reclamar la
recompensa. **Nunca envía nada ni prueba contra contratos desplegados.** Hasta el 26-oct-2026 el repo era un bot de
trading; ese código quedó en el historial de git.

Antes de tocar nada, leer en este orden:

1. [REGLAS.md](REGLAS.md): reglas R-1 a R-13. Es un archivo protegido.
2. Este documento.
3. [INVESTIGACION_SEGURIDAD.md](INVESTIGACION_SEGURIDAD.md): el pipeline y el estado por etapa.
4. El `CAZADOR_*.md` del objetivo: el modelo formal, las leyes, la verificación y cómo leer el informe.

Las reglas que más pesan al trabajar:

- **R-4:** los resultados son privados y quedan en la PC (`NEXUS_HOME`). Nunca van al repo, que es público: un
  hallazgo publicado sería divulgar una vulnerabilidad sin reportar. `limits.results_dir` lo hace cumplir.
- **R-3:** nada se envía solo; cada informe lo revisa y lo envía el dueño.
- **R-2 y R-6:** todo en local, con FFI de Foundry siempre apagado, sin `forge script`, `--broadcast` ni `cast send`.
- **R-7:** sin exagerar. Un candidato es "confirmado" solo con un test reproducible que muestre el efecto económico.
- **R-9:** ningún agente amplía el alcance, sube topes, cambia las reglas ni se da permisos sin la autorización
  expresa del dueño para ese cambio.
- **R-11 a R-13 (30-oct):** Claude fusiona sus PR con el CI en verde; trabaja solo en la PC; elige los objetivos por
  valor esperado, sobre la última versión en alcance de programas con recompensa vigente.

## 2. Cómo se trabaja

### Roles y flujo

- **El dueño** habilita los programas (el catálogo), envía los informes y autoriza los cambios de reglas.
- **Claude trabaja solo en la PC** (R-12), con Claude Code: lee los informes de `NEXUS_HOME`, corre forge, lanza
  campañas por el panel, escribe el código en una rama `claude/...` y abre el PR a `main`.
  - Antes del PR: `..\.venv\Scripts\python -m nexus.devcheck` desde `local`, que corre lo mismo que el CI.
  - Con el CI en verde y sin conflictos, Claude fusiona (`gh pr merge N --merge --delete-branch`) y hace `git pull`
    en `main` (R-11).
  - Un PR que toque rutas protegidas (`.github/`, `tools/protected_paths.py`, `local/nexus/secresearch/limits.py`,
    `local/tests/test_limits.py`, `docs/REGLAS.md`) queda en rojo en ese control del CI: lo fusiona el dueño, o
    Claude con su autorización expresa para ese cambio.
- **El ciclo programado** (`nexus-ciclo`) corre solo en la PC y deja `para_claude.md` y el dashboard: es lo primero
  que hay que mirar al arrancar una sesión.

### La PC del dueño

| Qué | Dónde |
|---|---|
| Repo | `%USERPROFILE%\nexus` (PowerShell: `cd $env:USERPROFILE\nexus`) |
| Python | `%USERPROFILE%\nexus\.venv`; los comandos se corren desde `local` con `..\.venv\Scripts\python -m ...` |
| Datos privados (`NEXUS_HOME`) | `%LOCALAPPDATA%\nexus`: catálogo `secresearch.yaml`, resultados en `secresearch\` |
| Informes de Foundry | `%LOCALAPPDATA%\nexus\secresearch\validate\` |
| Dashboard | `%LOCALAPPDATA%\nexus\secresearch\dashboard.html` (`python -m nexus.secresearch.dashboard` lo abre) |
| Expedientes | `%LOCALAPPDATA%\nexus\secresearch\expedientes\` |
| Ciclo programado | tarea `nexus-ciclo`, registrada con `tools/windows/registrar_ciclo.ps1` |
| GitHub CLI | `C:\Program Files\GitHub CLI\gh.exe`, autenticada como `bbarrionuevo` (28-oct): la sesión abre los PR, lee el CI y fusiona con el CI en verde (R-11) con `gh`; si la shell no la ve en el PATH, con la ruta completa |
| Panel local | Desde `local`: `..\.venv\Scripts\python -m nexus.secresearch.panel` abre el navegador en `127.0.0.1` con un token: procesos forge en vivo, campañas (estado, leyes, cobertura, log en vivo), lanzar y frenar campañas de `tools/forge_v2`, y descargar todo lo de `NEXUS_HOME\secresearch`. Cerrarlo no frena las campañas. `--resumen <id>` muestra una campaña en la terminal: cada variante, las reversiones del handler por acción y, si las hay, cómo investigarlas. Una campaña que pasa con reversiones queda como "pasó con reversiones del handler (revisar)", en rojo en el panel |

El Explorador oculta `AppData`: `explorer $env:LOCALAPPDATA\nexus\secresearch`.

### `tools/edr` (histórico)

[tools/edr](../tools/edr/README.md) (solc-js y EDR, el motor de tests Solidity de Hardhat 3) servía para verificar
sin forge en las sesiones en la nube, donde Foundry no se podía instalar. Desde el 30-oct Claude trabaja solo en la
PC, con forge (R-12), así que no hace falta; queda en el repo por si algún día no hay forge.

Lo que sigue valiendo de esa época:

- Con via_ir, `block.timestamp` puede quedar cacheado después de `vm.warp`. El cazador lee la hora con `NexusClock`.
- Los tests de Python prohíben ciertas cadenas en los `.py` del motor (`limits.FORBIDDEN`: `forge script`,
  `.post(`, `private_key`, etc.).

### Iterar con forge en la PC

En la PC no hay Node (no corre `tools/edr`), pero hay forge 1.8.6. El repo entero de Vault V2 tarda ~11 min en compilar;
[tools/forge_v2](../tools/forge_v2/README.md) arma un proyecto reducido con los mismos ajustes de compilación (solo
VaultV2, la factory, el `ERC20Mock`, forge-std y el harness), que compila en ~30 s, y corre ahí el harness y la batería
de mutación (`armar`, `correr`, `mutar`). La referencia sigue siendo `validate`.

Lo que conviene saber de forge en un handler:

- Una llamada externa en los argumentos después de `vm.prank` consume el prank: `vm.prank(a); v.transfer(b,
  v.balanceOf(a))` transfiere desde el handler. Calcular los argumentos antes del prank.
- forge 1.8.6 puede dejar `reason` en `null` en la falla de un invariante y poner el motivo en `invariant_failures`.
  `validate.summarize` ya lo lee de ahí (antes el informe decía "Motivo: None").
- forge guarda cada falla de invariante en `cache/invariant` y la reproduce primero en la corrida siguiente.
  `forge_v2 mutar` la borra entre mutaciones.
- forge 1.8.6 corre con `isolate = true` (también en el repo de Vault V2): cada llamada que el handler hace a otro
  contrato es una transacción aparte y la memoria transitoria se borra entre ellas. Para probar algo que depende de
  una misma transacción (en V2, `firstTotalAssets`), las llamadas las tiene que hacer un contrato intermedio dentro de
  su propia llamada (`NexusV2Macro`).
- `tools/forge_v2` tiene perfiles: sin nada, Vault V2; con `NEXUS_PERFIL=euler-earn`, EulerEarn (su proyecto reducido,
  su harness y `mutaciones_euler_earn.json`); con `NEXUS_PERFIL=tokenized-strategy`, TokenizedStrategy de Yearn V3
  (el clon en el tag `v3.1.0`). Los submódulos anidados de euler-earn pasan los 260 caracteres de ruta de Windows:
  nexus clona con `-c core.longpaths=true`.

## 3. Estado por etapa (29-oct-2026)

| Etapa | Estado |
|---|---|
| A. Catálogo y cambios | Funciona. El catálogo real está en la PC; programas elegidos: Morpho (Cantina), Yearn V3 (Immunefi) y Euler v2 (Cantina) |
| B. Triaje | Funciona: puntaje determinista sin IA |
| C. Método de invariantes | Funciona: P0–P6 en Python, con autoverificación |
| D. Validación con Foundry | Funciona en la PC: `validate` clona fijado a un commit, FFI apagado, informe privado |
| D'. Harness de MetaMorpho | Funciona: suite a16z, handler original y `NexusVulnerabilityHunter` con una suite multi-mercado con gobierno |
| D''. Harness de Vault V2 | Funciona (28-oct): variante A con capital asignado de verdad y 12 leyes `V-...` (con `forceDeallocate`, los topes, el gobierno con timelock y la cota de dominio V-BOUND), variante B con el adapter real sobre Blue y el Public Allocator; verificadas con forge en la PC: las 35 mutaciones de referencia con el harness del #82 y las 20 del gobierno y de la cota (V36–V55) con el del #84 ([CAZADOR_VAULT_V2.md](CAZADOR_VAULT_V2.md)) |
| Ciclo desatendido | Funciona: corre A–C, los harness con semilla nueva y líneas base; escribe `para_claude.md` y el dashboard |
| Dashboard | Nuevo (27-oct): página local con fallas, cobertura, métricas, corridas, programas, cambios, ciclos y expedientes |
| Panel | Nuevo (28-oct): servidor local (`nexus.secresearch.panel`, solo biblioteca estándar) para monitorear forge, lanzar y frenar campañas y descargar informes sin pasar por Claude; solo `127.0.0.1`, token por arranque, control de `Host` y del encabezado de las acciones |
| D'''. Harness de EulerEarn | Nuevo (28-oct): variante A sobre `a8cc099` (lo desplegado), 8 leyes `E-...` exactas con estrategias ERC-4626 de prueba ([CAZADOR_EULER_EARN.md](CAZADOR_EULER_EARN.md)). Verificado con forge en la PC: 3 de 3 a 256×500 sin falsos positivos ni reversiones (`0x2a`, `0x3` y `validate` con compilación aislada) y las 22 mutaciones de referencia detectadas. Sin hallazgos |
| D''''. Harness de TokenizedStrategy | Nuevo (28-oct): Yearn V3, `v3.1.0` (lo desplegado en `0x310f…1e76` y en alcance), la contabilidad nueva ("constant accrual", pestillo por bloque, piso de 1e3 acciones, quema de bloqueadas por pérdida en vivo) y la de reporte, 11 leyes `Y-...` exactas contra el almacenamiento crudo ([CAZADOR_TOKENIZED_STRATEGY.md](CAZADOR_TOKENIZED_STRATEGY.md)). Verificado con forge en la PC: 4 de 4 a 256×500 sin falsos positivos ni reversiones (`0x2a`, `0x3` y `validate` con compilación aislada, 8 de 8 con los escenarios) y las 39 mutaciones de referencia detectadas. Sin hallazgos |
| D'''''. Harness del Vault V3 | Nuevo (29-oct): Yearn V3, `v3.1.0` (lo desplegado en `0xdD3F…7824`), el vault real por su fábrica compilado con el `vyper` del venv (sin FFI), tres estrategias ERC-4626 de prueba y un accountant; 10 leyes `YV-...` exactas contra el almacenamiento crudo ([CAZADOR_VAULT_V3.md](CAZADOR_VAULT_V3.md)). Verificado con forge en la PC: las 4 variantes sin falsos positivos ni reversiones (24×500 con `0x2a` y `0x3`; `validate` sobre el repo entero a 64×500, semilla `0x68a90a1321ee064a`, 4 de 4) y las 28 mutaciones de referencia detectadas. **Sin hallazgos** |
| D''''''. Harness de Midnight | Nuevo (29-oct; variante B el 30-oct): Morpho Midnight, el núcleo desplegado (etiqueta `2026-08-24`, coincidencia completa en Sourcify), un mercado de dos colaterales con ofertas entre cuatro actores, liquidaciones normales y post-vencimiento y deuda incobrable; 8 leyes `MN-...` exactas contra los getters. La variante B suma callbacks con operaciones anidadas, el bloqueo de liquidación del vendedor, los pagadores, el préstamo flash, `multicall` y los gates ([CAZADOR_MIDNIGHT.md](CAZADOR_MIDNIGHT.md)). Verificado con forge en la PC: las 6 suites (4 de la A y 2 de la B) sin falsos positivos ni reversiones (32×300 con `0x2a` y `0x3`; `validate` sobre el repo entero a 64×300, semilla `0x7dea4e2c53b47e39`, 10 de 10 con las pruebas de regresión) y las 47 mutaciones de referencia detectadas; la campaña profunda de la A (1536×500) sin leyes violadas. **Sin hallazgos** |
| E. Duplicados | Funciona: auditorías de Vault V2 (15), MetaMorpho (3), EulerEarn (3) y TokenizedStrategy (3, todas de la v3.0.x) resumidas en `NEXUS_HOME`, privadas |
| F. Expediente | Nuevo (27-oct): `python -m nexus.secresearch.expediente INFORME` arma el borrador para reclamar |

**Hallazgos:** ninguno. No hay candidatos ni expedientes abiertos.

### El cazador de MetaMorpho

`local/nexus/secresearch/harness/morpho-org__metamorpho/`:

- `NexusVulnerabilityHunter.sol`: contabilidad fantasma y leyes exactas (aritmética de 512 bits, sin tolerancias),
  evaluadas en cada acción del handler. Las familias son H-INF (inflación y redondeo), H-FEE (comisiones), H-SOLV
  (solvencia y fugas), H-DEBT, H-GOV y H-LEDGER.
- `NexusMetaMorphoInvariant.t.sol`: el handler original (PR #72) con el cazador integrado sin cambiar su API.
- `NexusMetaMorphoHunter.t.sol`: suite multi-mercado (3 mercados con préstamos más el idle) con gobierno en medio
  de la corrida: topes con timelock, remociones, colas, comisión y timelock. Suma seis macros de ataque.
- Cada suite corre en tres variantes: sin comisión, con 25 % de comisión y con un activo de 6 decimales.

Verificación:

- **En la nube:** los 6 invariantes pasan 256×500 sin falsos positivos, y el cazador detecta las 21 mutaciones de
  referencia (17 de MetaMorpho y 4 de Morpho Blue). El handler original solo detectaba 11.
- **En la PC, con forge:** tres corridas, todas en verde. Cada una dejó una mejora:

| Fecha | Resultado | Qué enseñó |
|---|---|---|
| 26-oct 15:03 | 81 de 81 (handler original) | Un solo mercado, sin gobierno, y el informe no mostraba las verificaciones |
| 26-oct 22:26 | 84 de 84 (con el cazador) | El `reallocate` heredado revertía en el 78 % de sus llamadas en las suites multi-mercado |
| 27-oct 02:28 | 84 de 84 | `reallocate` bajó a 0,1–0,3 %; `setSupplyQueue` solo cambiaba la cola 2 a 5 veces de unas 14 por corrida |

Comportamientos conocidos que **no** son hallazgos (detalle en CAZADOR_METAMORPHO.md, sección 6):

- Con activos de 18 decimales, `DECIMALS_OFFSET` es 0 y la protección contra la inflación es baja. MetaMorpho lo
  documenta en `IMetaMorpho.sol` y recomienda un depósito inicial. Por eso hay depósitos con 0 acciones y la
  comisión acuñada puede quedar muy por debajo de la devengada.
- Tras remociones forzadas que dejan `totalAssets` cerca de 0, los depósitos acuñan cantidades astronómicas de
  acciones y pueden desbordar `uint256`. Fue el octavo falso positivo, corregido con `_mintFits`.

## 4. Cambios recientes (PR a `main`)

| PR | Qué trajo |
|---|---|
| #68–#71 | Prototipo A–C, programas elegidos, fin del trading, validador con Foundry |
| #72 | Etapa D': suite a16z, invariantes con handler y ciclo desatendido |
| #74 | `NexusVulnerabilityHunter`, la suite multi-mercado, métricas por acción y `-vv` para que el informe muestre el log de `afterInvariant` |
| #75 | Con la primera corrida de la PC: `reallocate` respeta topes, `gobierno con efecto` y la guía para leer el informe |
| #76 | Con la segunda corrida: `setSupplyQueue` con efecto, el selector del error en las fallas de vivacidad, `_mintFits`, el dashboard, el expediente y este documento |
| #77 | El prompt de arranque de la sesión en la PC ([PROMPT_SESION_PC.md](PROMPT_SESION_PC.md)) |
| #79 | Primera sesión en la PC (el #78 se fusionó por error en la rama vieja `claude/nice-sagan-inp0u8`; el #79 lo lleva a `main`) y el harness de Vault V2 variante A: el ciclo ya no se cae con la línea base de Euler, `devcheck` usa el `ruff` del venv, el alcance quedó contrastado con la página de direcciones de Morpho, y el cazador de Vault V2 (leyes V-..., 3 variantes) pasa verificado en la nube |
| #80 | Vault V2 con forge en la PC: capital asignado de verdad (`NexusAdapterMock`, topes relativos, transferencias reales), las leyes V-INF-2, V-LOSS-1 y V-LOSS-2 con sus demostraciones, `tools/forge_v2` (proyecto reducido y batería de mutación con forge), y `validate`/`expediente` al día con forge 1.8.6 y las leyes `V-...` |
| #81 | Vault V2: `forceDeallocate` (V-FD-1) y los topes con su borde exacto (V-CAP-1), con `NexusV2Macro` para las secuencias de una transacción (forge corre con `isolate = true`); 21 mutaciones de referencia |
| #82 | Vault V2, variante B: el `MorphoMarketV1AdapterV2` real sobre Morpho Blue (V-ADP), el Blue Public Allocator (V-PA), el adapter de liquidez y forceDeallocate sobre Blue; `tools/forge_v2` con Blue y mutaciones sobre cualquier archivo; 35 mutaciones de referencia. Va sobre el #81 |
| #83 | Vault V2: el gobierno con timelock (V-GOV-1: comisiones y receptores, penalidad, timelocks, abdicaciones, topes, adapters y registro, con el borde exacto de la fecha); 19 mutaciones nuevas (V36–V54); y la etapa E de MetaMorpho (privada) |
| #84 | Vault V2: la cota de dominio V-BOUND como ley (el estado no sale del dominio de la aritmética de una palabra del vault; el handler no hace el depósito que lo sacaría) y sondas deterministas del registro y de los adapters para V-GOV-1; mutación V55. Va sobre el #83 |
| #85 | EulerEarn: el cazador de la variante A (leyes E-...) sobre la versión desplegada, el perfil `euler-earn` de `tools/forge_v2` con 22 mutaciones, y en nexus `core.longpaths` para clonar, la compilación aislada (`"aislado": true` en el manifiesto) y leyes `E-` en el expediente. Va sobre el #84 |
| #86 | Yearn V3: el cazador de TokenizedStrategy `v3.1.0` (leyes Y-...) en los dos modos de contabilidad, el perfil `tokenized-strategy` de `tools/forge_v2` con 39 mutaciones, leyes `Y-` en el expediente y `gh` en la PC |
| #87 | El panel local (`nexus.secresearch.panel`): forge en vivo, lanzar y frenar campañas y descargar informes sin pasar por Claude; `NEXUS_MATCH` y el commit desplegado fijado en `tools/forge_v2` |
| #88 | Yearn V3: el cazador del Vault V3 3.1.0 (leyes YV-...), el perfil `vault-v3` de `tools/forge_v2` con 28 mutaciones, el `vyper` del venv en el PATH de forge y `validate`, leyes `YV-` en el expediente y el panel, el perfil `vault-v3` en el panel, y `validate` ya no da por buena una corrida del harness en la que no corrió ningún test (el manifiesto puede fijar `match_path`) |
| #89 | Morpho Midnight: el cazador del núcleo desplegado (leyes MN-...), el perfil `midnight` de `tools/forge_v2` y del panel, el alcance de Midnight y MetaMorpho V1.1 resuelto con el reglamento vigente, y las campañas del panel separadas del job de quien las lanza |
| #90 | Morpho Midnight, variante B: callbacks con operaciones anidadas, el bloqueo de liquidación del vendedor, los pagadores, el préstamo flash, `multicall` y los gates (10 mutaciones nuevas, B1–B10); el arreglo de `liqCycle` con el precio en 0, que dejó ver la campaña profunda; trae también los dos commits del traspaso que quedaron afuera del #89 |
| #91 | Vault V3: el cazador a prueba de desbordes (el modelo de cada operación por llamada externa; si desborda, se espera que el vault revierta) y el dominio `total_supply` ≤ 2^128, tras las reversiones del handler de la campaña profunda; dos pruebas de regresión. Sale de la rama del #90 |
| #92 | TokenizedStrategy: el mismo arreglo que el #91 (el modelo de las entradas, las salidas, el reporte y el devengamiento de los setters por llamada externa, y el dominio `totalSupply` ≤ 2^128), tras reproducir las 11 reversiones del handler de su campaña con otras semillas; una prueba de regresión. Además, `tools/forge_v2` controla en `armar` y `mutar` el commit y los submódulos del clon. Sale de la rama del #91 |
| #93 | Reglas y flujo, con la autorización del dueño del 30-oct: Claude fusiona sus PR con el CI en verde (R-11), trabaja solo en la PC (R-12) y elige los objetivos por valor esperado (R-13); dentro de un programa habilitado puede sumar repos en alcance (R-1); `nexus.devcheck` como chequeo único antes del PR; la primera tabla de objetivos por valor esperado |
| #94 | Objetivos por valor esperado, con los programas releídos el 30-oct (Euler pasó a un presupuesto de 1,5M con tope del 10 % del impacto; Morpho publica los Bundles nuevos en su página de direcciones): los Bundles de Morpho, sumados al catálogo, son el objetivo siguiente |
| #95 | El panel automatiza la lección del 30-oct: lee las reversiones del handler por acción, marca en rojo una campaña que pasa con reversiones ("pasó con reversiones del handler (revisar)") y `--resumen <id>` la muestra en la terminal con cómo investigarlas |

## 5. Próximos pasos

### Objetivos por valor esperado (R-13; 30-oct)

Leído el 30-oct en Cantina (Morpho y Euler) y en la página de direcciones de Morpho, que el reglamento declara fuente
de verdad del alcance. Los montos de Yearn son del 26-oct. "A confirmar" es lo que falta leer antes de invertir en
ese objetivo.

| Objetivo | Programa y grupo | Critical | Código | Estado en nexus | Valor esperado |
|---|---|---|---|---|---|
| **Bundles de Morpho** (`morpho-org/bundles`: BlueBundlesV1, MidnightBundlesV2, VaultExitBundlesV1 y VaultBundlesV1) | Morpho. El grupo "Blue y Vault V1" dice "including bundlers" (250.000 a 2.500.000); si el triaje los pone con Midnight y Vault V2, 150.000 a 1.500.000 | hasta 2.500.000 | Muy nuevo: el repo es de mayo de 2026, la última etiqueta del 6-oct y tiene cambios hasta el 30-oct. Unos 90 KB en 4 contratos. Diez auditorías (Spearbit, Stermi, Blackthorn, Trustsec, Sherlock) y Certora. Reemplazan a Bundler3, que quedó deprecado | Sin cazador; al catálogo el 30-oct (R-1). MidnightBundlesV2 usa los callbacks de Midnight que el cazador ya modela | **El más alto:** la recompensa más alta, código nuevo con integraciones complejas, y se reusa el cazador de Midnight |
| Midnight: `Mempool` | Morpho, "Midnight y Vault V2" | 150.000 a 1.500.000 | Nuevo en la página de direcciones (`0xde2d…A8F7`). Según Sourcify es `periphery/Log.sol`: 443 bytes, un `fallback` que solo emite la calldata como evento, sin estado ni fondos | Revisado el 30-oct | Prácticamente nulo |
| Euler v2, núcleo (EVC, EVK sin Synths y Price Oracle) | Euler, "Core Components" | Hasta 1.500.000, pero como máximo el 10 % de la pérdida demostrable en producción | Grande y muy auditado | Del EVK, solo la línea base | Medio-bajo. El programa cambió: ya no son 7,5M sino un presupuesto total de 1,5M, por orden de llegada, con KYC |
| Midnight (lo que falta del núcleo) | Morpho, "Midnight y Vault V2" | 150.000 a 1.500.000 | — | Variantes A y B verificadas y campañas profundas sin leyes rotas | Medio: lo que no cubre (CAZADOR_MIDNIGHT.md §8) |
| Morpho Blue | Morpho, "Blue y Vault V1" | 250.000 a 2.500.000 | Chico, auditado muchas veces y verificado formalmente | Sin cazador; fuera del catálogo | Medio-bajo: la recompensa más alta, con la probabilidad más baja |
| Vault V2 (registros de la periferia) | Morpho, "Midnight y Vault V2" | 150.000 a 1.500.000 | Registros chicos, de 1 a 2 KB | Variantes A y B verificadas | Bajo |
| Euler Earn | Euler | Hasta 500.000 (10 % del impacto) | — | Verificado | Bajo |
| Yearn V3 | Yearn, Immunefi | Hasta 200.000 | La contabilidad de la 3.1.0 no tiene auditoría pública | TokenizedStrategy y Vault V3 verificados | Bajo: el tope es bajo |
| MetaMorpho V1.1 | Morpho, "Blue y Vault V1" | 250.000 a 2.500.000 | Cambios chicos sobre la V1.0; `lostAssets` ya cazado en EulerEarn | Evaluado el 29-oct | Bajo |

**Lo siguiente: el cazador de los Bundles de Morpho**, empezando por MidnightBundlesV2. Es el más nuevo (auditado el
6-oct) y opera sobre Midnight, que nexus ya modela con callbacks. Los pasos:
- la etapa E: las diez auditorías y las specs de Certora, en `NEXUS_HOME` (privado);
- la versión desplegada de cada contrato, contra las etiquetas del repo;
- el diseño del cazador.

### En orden de prioridad

1. **Dueño:** no queda nada por fusionar. Desde el 30-oct Claude fusiona sus PR con el CI en verde (R-11), y el #90,
   el #91 y el #92 ya están en `main`. El 30-oct, con el visto bueno del dueño, la rama por defecto de GitHub pasó a
   ser `main`; antes era `claude/nice-sagan-inp0u8`, un resto de las sesiones en la nube. Lo que pedía el #76 ya
   está probado: la corrida de MetaMorpho del 27-oct a las 10:18 pasó en verde y `colaSuministro` subió de 3–8 a
   18–19 por corrida. El ciclo del 28-oct tendría que terminar en verde también con la línea base de Euler (el
   `TypeError` del 27-oct se corrigió en el #79).
2. **Dueño, rendimiento de la PC (configuración del sistema: la hace el dueño):**
   - **Modo de energía:** Configuración > Sistema > Inicio/apagado y batería > Modo de energía > "Máximo rendimiento",
     enchufada. En una serie U es lo que más sube la frecuencia sostenida. Si es una Dell (tiene SupportAssist),
     revisar también el perfil térmico en Dell Power Manager u Optimizer ("Ultra rendimiento").
   - **Exclusiones de Defender** (PowerShell como administrador):
     `Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\nexus\work", "$env:USERPROFILE\.svm", "$env:USERPROFILE\.foundry"`.
     Acelera la compilación y el caché de forge. Contra: esas carpetas tienen código de terceros (de repos en alcance)
     que Defender deja de analizar.
   - **Memoria:** cerrar el navegador y otras aplicaciones pesadas durante las campañas (12 GB, a veces 4 libres).
3. **Dueño:** dar de baja la tarea vieja `nexus-latido`, que apunta a un script del trading que ya no existe. Ya está
   deshabilitada y no falla más, pero sigue registrada. La sesión de la PC no la pudo borrar porque el control de
   permisos de Claude Code bloquea las bajas: `Unregister-ScheduledTask -TaskName nexus-latido -Confirm:$false`.
4. **Alcance de Midnight y MetaMorpho V1.1: resuelto el 29-oct (R-1, R-9).** El dueño delegó en Claude la lectura del
   reglamento y autorizó en el chat. Releído ese día:
   - El reglamento de Morpho en Cantina agrupa los contratos en "Morpho Midnight and Vault V2" (Critical de USD 150.000
     a 1.500.000) y "Morpho Blue and Vault V1 (MetaMorpho), including bundlers" (de 250.000 a 2.500.000).
   - Declara fuente de verdad del alcance a la
     [página de direcciones](https://docs.morpho.org/developers/contracts/addresses/), que lista:
     - **Morpho Midnight** (`morpho-org/midnight`): el núcleo `0x4716…045f` y su periferia en Ethereum.
     - **MetaMorpho Factory V1.1** (`0x1897…5c24`, `morpho-org/metamorpho-v1.1`), además de la fábrica vieja.
   - Los dos quedan en alcance. El catálogo de la PC lo registra, con las recompensas y exclusiones vigentes.
   - El cazador de Midnight está en `main` desde el #89, y su variante B va en el #90 (punto 10).
   - MetaMorpho V1.1 sigue sin cazador propio: nexus prueba `morpho-org/metamorpho`, que corresponde a la fábrica
     vieja (commit `c5e758d`). Su `MetaMorpho.sol` difiere de `ded84e5` solo en formato y comentarios, así que lo
     probado vale para esos vaults; la V1.1 agrega la contabilidad de `lostAssets`, que el cazador de EulerEarn ya
     modela.
5. **Vault V2** (`morpho-org/vault-v2`, ya en el catálogo). Los nueve objetivos del plan quedaron cubiertos con el #84
   (la campaña profunda del 28-oct, al final de este punto). Alcance contrastado el 27-oct:
   - En Ethereum están desplegados `VaultV2Factory`, `MorphoVaultV1AdapterFactory`, `MorphoMarketV1AdapterV2Factory`,
     `MorphoRegistry` y el Blue Public Allocator.
   - Su código no cambió desde las auditorías: `VaultV2.sol` desde el tag `2025-09-15`, los adapters desde
     `2025-12-04` y el allocator desde `2026-08-13`, salvo imports y comentarios. Lo que se pruebe en `main` vale
     para lo desplegado.
   - El `MidnightAdapter` del repo y sus ratifiers no figuran desplegados en ninguna red: **fuera de alcance** hasta
     que aparezcan en la página.
   - **Etapa E hecha** (27-oct): las 15 auditorías extraídas a texto y resumidas en
     `NEXUS_HOME/secresearch/etapa_e/morpho-org__vault-v2/` (`indice.md` y `duplicados.md`, privados). Aviso clave:
     las auditorías tempranas son de una versión vieja con VIC y `realizeLoss()` que **ya no existe**; no perseguir
     esos hallazgos.
   - **Modelo derivado** en [CAZADOR_VAULT_V2.md](CAZADOR_VAULT_V2.md): contabilidad por adapters, tope de tasa
     (`maxRate`), dos comisiones, `forceDeallocate`, realización de pérdida, y las leyes `V-...`.
   - **Variante A** (`harness/morpho-org__vault-v2/`, 3 variantes; escrita en la nube en el PR #79). La primera corrida
     con forge en la PC (27-oct) pasó 3 de 3, pero las métricas por acción mostraron dos acciones muertas: `allocate`
     revertía el 98 % (el tope relativo nunca se subía y vale 0) y `transfer` el 94 % (el `prank` lo consumía el
     `balanceOf` del argumento). Eran el ~16 % de reversiones, no depósitos que topaban el `uint128`. El adapter nunca
     tenía capital y las pérdidas solo se comían rendimiento.
   - **Corregido y ampliado en el #80:** adapter propio que cumple la especificación
     (`NexusAdapterMock`), topes relativos, transferencias reales, y las leyes V-INF-2 (precio por acción),
     V-LOSS-1 y V-LOSS-2 (realización de pérdidas), demostradas en CAZADOR_VAULT_V2.md §4. Con forge en la PC: 3 de 3
     a 256×500 sin falsos positivos con `0x2a` y `0x3` en el proyecto reducido y con `0x8e4b379d1936e836` en
     `validate` sobre el repo entero (`6047e158`, que solo cambia comentarios de `MidnightAdapter`), siempre con 0
     reversiones. Las 13 mutaciones de referencia se detectan, cada ley nueva por al menos una.
   - **V-FD-1 y V-CAP-1, en el #81** (rama `claude/vault-v2-fd-topes`, sobre el #80):
     `forceDeallocate` con su penalidad exacta (propio, por allowance y forzando y saliendo en una transacción) y los
     topes con su borde exacto (si y solo si), cambios de topes y depósito y allocate en una misma transacción contra
     `firstTotalAssets`. Demostraciones en CAZADOR_VAULT_V2.md §4. Con forge en la PC: 3 de 3 a 256×500 sin falsos
     positivos con `0x2a` y `0x3` (proyecto reducido) y con `0x2fef01ee4e27ce41` (`validate`, repo entero), y las 21
     mutaciones de referencia detectadas (las 8 nuevas por V-FD-1 y V-CAP-1). En el camino apareció que forge 1.8.6
     corre con `isolate = true` (§2): por eso `NexusV2Macro`.
   - **Variante B, en el #82** (rama `claude/vault-v2-variante-b`, sobre la del #81; referencia con `validate` sobre el
     repo entero: 4 de 4, las tres variantes A y la B, semilla `0xa03dcb8635632b88`):
     `NexusVaultV2Blue.t.sol`, el `MorphoMarketV1AdapterV2` real sobre Morpho Blue con la IRM adaptativa, dos mercados,
     prestatarios, cambios de precio y liquidaciones con deuda incobrable. Leyes V-ADP-1 a 5 contra el estado crudo de
     Blue (`realAssets` exacto, allocations, acciones internas, `marketIds`, movimiento exacto con redondeo demostrado
     en `[−⌈p⌉, +1]`), más V-TA-1, V-LOSS-1 y V-SOLV-1. **Y el Blue Public Allocator** (periferia en alcance, el código
     más nuevo): `reallocate` y `allocateFromIdle` públicos y su configuración, con las leyes V-PA-1 a 4 (penalidad
     exacta al vault, flujo exacto en Blue, permisos y tope propio, guardas). **Y el adapter de liquidez y
     forceDeallocate sobre Blue** (V-FD-1 con el redondeo del retiro en Blue). Con forge en la PC: 256×500 sin falsos
     positivos ni reversiones con `0x2a` y `0x3`; las 14 mutaciones de la variante B (V22–V35) detectadas, cada ley por al
     menos una, y las de la penalidad (V14–V16) también las ve la variante B. `tools/forge_v2` ya arma el proyecto
     reducido con Blue, la IRM y el allocator y muta cualquier archivo.
   - **Gobierno con timelock (V-GOV-1), en el #83** (rama `claude/vault-v2-gobierno`): el handler de la variante A
     propone, ejecuta y revoca cambios con demora contra una copia fantasma (comisiones y sus receptores, penalidad,
     timelocks, abdicaciones, subidas de topes, alta y baja de un segundo adapter y el registro de adapters), con
     timelocks iniciales distintos de 0, el intento un segundo antes de la fecha y justo en ella, lo revocado y lo
     abdicado. Especificación en CAZADOR_VAULT_V2.md §4. Con forge en la PC: 4 de 4 a 256×500 sin falsos positivos con
     `0x2a` y `0x3` (proyecto reducido) y con `0x8f3701367e64ccea` (`validate`, repo entero), siempre con 0 reversiones;
     las 19 mutaciones nuevas (V36–V54) detectadas en la variante A: 17 por V-GOV-1 y las dos de comisión retroactiva
     por V-FEE-1. Las de registro y adapters (V50–V52) las veían una o dos variantes a 64×200; con las sondas del
     #84, las tres.
   - **V-BOUND, en el #84** (rama `claude/vault-v2-cota`, sobre la del #83): la cota de dominio como ley. Después de
     cada acción el estado queda en el dominio donde la acción siguiente no desborda la aritmética de una palabra del
     vault (`_totalAssets` en 128 bits, los productos de las conversiones y de las comisiones en 256, las comisiones
     acotadas); el handler no hace el depósito o mint que lo sacaría (el borde es depositar tras una pérdida total) y
     devenga antes de un salto de reloj que lo sacaría. Demostración en CAZADOR_VAULT_V2.md §4. Además, sondas
     deterministas de V-GOV-1 para el registro y los adapters. Con forge en la PC: 4 de 4 a 256×500 sin falsos
     positivos con `0x2a` y `0x3` (proyecto reducido) y 7 de 7 con `0x3b07c967b0bae4be` (`validate`, repo entero,
     con las 3 pruebas de `NexusVaultV2BoundTest`), siempre con 0 reversiones; margen mínimo del dominio de 60 a 62
     bits con 18 decimales y de 21 a 23 con 6, sin depósitos recortados; las 20 mutaciones V36–V55 detectadas (V55
     solo por V-BOUND, y V50–V52 ahora en las tres variantes).
   - **Con esto están los nueve objetivos del plan de Vault V2.** Lo que no cubre está en CAZADOR_VAULT_V2.md §6.
   - **Campaña profunda (28-oct), con el harness del #84:** 512 corridas × 1.500 llamadas (768.000 por variante, ~4 h
     en la PC), semilla `0xff36d931ca90abfb`: las 4 variantes y las 3 pruebas de la cota en verde, **ninguna ley
     violada**. Margen mínimo del dominio: 58 a 60 bits con 18 decimales y 16 con 6 (las secuencias largas lo acercan
     al borde y sigue adentro). Hubo 1 reversión en las 768.000 llamadas de la variante sin comisión: la tabla por
     acción no se guardó, así que no se sabe cuál fue (la única vista antes, el 27-oct, fue un `mint` que costaba más
     de lo que el handler le da al actor).
   - La línea base de V2 (los tests del repo) es cara: compila en ~11 min y los tests tardan ~35. El harness solo, con
     `validate`, tarda ~10 min de compilación y ~11 de tests; para iterar, `tools/forge_v2` (~30 s).
6. **Etapa E para MetaMorpho: hecha** (27-oct). Las tres auditorías de `audits/` (Cantina 2023-11, OpenZeppelin de la
   periferia 2023-11 y la competencia de Cantina 2024-01) están extraídas a texto y resumidas en
   `NEXUS_HOME/secresearch/etapa_e/morpho-org__metamorpho/` (`indice.md` y `duplicados.md`, privados), con el estado
   de cada hallazgo contra `ded84e5` y su relación con las leyes H-.... Aviso clave: la competencia publica solo sus 13
   hallazgos medios; los 113 bajos no están en el repo, así que un candidato de severidad baja puede ser duplicado sin
   que se pueda comprobar.
7. **EulerEarn (programa Euler v2), en el #85.** Cazador de la variante A sobre `a8cc099` (lo desplegado), con
   tres estrategias ERC-4626 de prueba, ocho leyes `E-...` exactas y el precio que nunca baja (E-INF-2); 3 de 3 a
   256×500 sin falsos positivos ni reversiones con `0x2a`, `0x3` y `validate` sobre el repo entero (`0x1254469e03f52bcc`,
   compilación aislada), y las 22 mutaciones detectadas. **Sin hallazgos:** los dos bordes del `uint112` (depositar
   tras la pérdida casi total de una estrategia que sigue en la supplyQueue; volver a dar de alta una estrategia con
   más de 2^112 acciones reales) son el dominio, no defectos explotables (ver CAZADOR_EULER_EARN.md §4).
   - Contexto: **EulerEarn** (`euler-xyz/euler-earn`): fork de MetaMorpho V1.1 con estrategias ERC-4626, `lostAssets`,
     `VIRTUAL_AMOUNT` en acciones y activos y seguimiento interno de las acciones de cada estrategia
     (`config[id].balance`, no el saldo real). El cazador sigue el patrón de los de MetaMorpho y Vault V2. Ya tiene la
     suite de invariantes de Enigma Dark y la verificación de Certora, con propiedades aproximadas; lo que agrega
     nexus es el modelo exacto de 512 bits (fantasma de `lostAssets`, del seguimiento interno y de las comisiones bit a
     bit). Las tres auditorías están extraídas y resumidas en `NEXUS_HOME/secresearch/etapa_e/euler-xyz__euler-earn/`
     (privado). El reglamento de Euler en Cantina cubre Euler Earn (hasta USD 500.000 Critical), evalúa contra la
     implementación **desplegada** y no paga Low ni informativos. Lo desplegado en Ethereum es `a8cc099` (comparado por
     SHA-256 contra el código verificado de la fábrica); los cambios del 23-oct-2026 en `SafeERC20Permit2Lib` no están
     desplegados.
   - **Campaña profunda (28-oct):** 512 corridas × 1.500 llamadas (768.000 por variante, ~6 h en la PC), semilla
     `0x416da32f22ae83af`: las 3 variantes y las 2 pruebas de la cota en verde, sin reversiones, **ninguna ley
     violada**. El 28-oct a la noche quedó corriendo otra de 128×6000 (secuencias largas), semilla
     `0xf204663f1abb7cbe`.
   - **Falta en EulerEarn:** la variante B con estrategias reales del EVK (crédito, IRM, deuda incobrable), el Public
     Allocator, el guardian y los timelocks distintos de 0.
8. **TokenizedStrategy de Yearn V3, en el #86** (rama `claude/yearn-tokenized-strategy`). Verificado con forge en la PC:
   las 4 variantes a 256×500 sin falsos positivos ni reversiones con `0x2a`, `0x3` y `validate` sobre el repo entero
   (`0xdf5a04a2c65ea82a`, compilación aislada, 8 de 8 con los escenarios), y las 39 mutaciones de referencia
   detectadas. **Sin hallazgos.** Lo que mostró la campaña y su evaluación (R-7) están en
   `NEXUS_HOME/secresearch/etapa_e/yearn__tokenized-strategy/analisis_reporte_y_piso.md` (privado).
   - Contexto: el alcance de Immunefi (página actualizada el 25-jul-2026) tiene **Tokenized Strategy V3.1.0**
     (`0x310f…1e76`, desde el 23-jun-2026) y la 3.0.4 (`0xD377…139c`); la 3.1.1 no figura. El código verificado de
     `0x310f…1e76` es byte a byte el del tag `v3.1.0`. La 3.1.0 reescribió la contabilidad ("constant accrual":
     devengamiento en vivo una vez por bloque, piso de 1e3 acciones contra la inflación, quema de acciones bloqueadas
     ante una pérdida en vivo, pausa) y las tres auditorías del repo son de la v3.0.x: lo nuevo no tiene auditoría
     pública. La etapa E está en `NEXUS_HOME/secresearch/etapa_e/yearn__tokenized-strategy/` (privado).
   - Por qué antes que lo que falta de EulerEarn: el núcleo de EulerEarn es un fork de MetaMorpho ya verificado
     formalmente (Certora), y su Public Allocator es casi literal el de Morpho; la contabilidad de la 3.1.0 es nueva.
   - **Vault V3 3.1.0, en el #88:** la variante A (estrategias ERC-4626 de prueba) está hecha y verificada; ver
     [CAZADOR_VAULT_V3.md](CAZADOR_VAULT_V3.md). **Falta en Yearn:** la variante B del vault con estrategias reales de
     TokenizedStrategy v3.1.0 en vivo (su `convertToAssets` incluye lo simulado, y `_update_debt` no mira las acciones
     que recibe al depositar), y la 3.0.4 de TokenizedStrategy (la contabilidad del modo por reporte, sin pestillo ni
     piso).
   - **Variante B del vault, evaluada el 29-oct:**
     - El repo del vault fija `lib/tokenized-strategy` en la **v3.0.3**, no en la 3.1.0. Una variante B con la 3.1.0
       necesita dos repos: `tools/forge_v2` puede armarla, pero `validate` trabaja con un solo clon.
     - Aporta poco frente a la variante A. El vault ve la estrategia solo por sus vistas, y el cazador de
       TokenizedStrategy ya demostró que esas vistas son la ejecución (Y-VIEW-1).
     - Lo que sí queda abierto es el punto 3 del análisis privado de TokenizedStrategy: el vault no controla las
       acciones que recibe en `update_debt`. Se puede medir con un escenario determinista privado, pero según R-7 hoy
       no es candidato.
   - **Campañas cortadas el 29-oct:** la profunda del vault (768×1000, semilla `0xe782c4dd280d82a0`, lanzada a las
     16:22) y las de 128×6000 de TokenizedStrategy y EulerEarn murieron sin resultados cuando se reinició la sesión de
     Claude Code que las había lanzado (entre las 17:35 y las 18:10). Quedaban dentro del job de esa sesión, y forge
     escribe la salida recién al terminar cada variante. Las de 128×6000 se relanzaron el 30-oct (ver la campaña
     profunda de TokenizedStrategy, más abajo en este punto).
   - **Campaña profunda del vault** (`20261029-181742_vault-v3_768x1000_0xe782c4dd280d82a0`, relanzada a las 18:17 y
     terminada el 30-oct a las 02:49): las 4 variantes en verde y **ninguna ley violada**. Pero hubo reversiones del
     handler en dos variantes, y esas secuencias no quedaron verificadas:
     - en la de comisiones, 43: `stressExit` 14, `idleFloor` 11, `updateDebt` 6, `cycle` 5, `redeem` 4, `deposit` 2
       y `withdraw` 1;
     - en la base, 31: `cycle` 15, `report` 8, `stressExit` 6, `idleFloor` 1 y `updateDebt` 1;
     - en la de sin bloqueo y en la de 6 decimales, 0.

     **Eran del cazador, no del vault.** Está arreglado en el #91, y el detalle está en
     [CAZADOR_VAULT_V3.md](CAZADOR_VAULT_V3.md) §6:
     - pérdidas casi totales seguidas de depósitos inflaban las acciones (en la reproducción, 1,2e56 contra 7,3e23 de
       activo) hasta que una cuenta del modelo desbordaba;
     - el vault hace la misma cuenta y también revierte, así que no es un hallazgo;
     - ahora el modelo de cada operación se llama a prueba de desbordes: si desborda, se espera que el vault revierta,
       y YV-LIVE lo controla;
     - el cazador no deja pasar `total_supply` de 2^128;
     - pruebas de regresión: `test_inflacionDeAcciones` y `test_desbordeEnElReporte`.

     Reverificado el 30-oct, todo en verde:
     - 24×500 con `0x2a` y `0x3` y `validate` (64×500, semilla `0x689e3107429f5a13`): 12 de 12 con las pruebas de
       regresión y 0 reversiones;
     - las 28 mutaciones detectadas en las cuatro variantes;
     - con `fail_on_revert`, 256.000 llamadas en las dos variantes que revertían, sin reversiones.
   - **Campaña profunda (28-oct):** 512×1500 (768.000 llamadas por variante, ~9 h), semilla `0x4a9cb1e5a489dc29`:
     las 4 variantes y los 4 escenarios en verde, **ninguna ley violada**, pero con 11 reversiones del handler en
     la variante con protocolo (en `report` y en `lockThenLose`, que lo llama): no es una falla de ley, y puede
     ser un borde de dominio del harness (una vista que revierte con suministros enormes tras una pérdida casi
     total). La misma variante y semilla con `fail_on_revert` (29-oct, ~13 h) pasó las 768.000 llamadas con **0
     reversiones**: no se reproducen (o no eran deterministas o la generación cambia con esa opción), y en ninguna
     corrida falló una ley. **El 30-oct se reprodujeron con otras semillas, como las del Vault V3:** eran acciones
     infladas hasta desbordar, en el modelo y en TokenizedStrategy, así que no es un hallazgo. Está arreglado en el
     #92 ([CAZADOR_TOKENIZED_STRATEGY.md](CAZADOR_TOKENIZED_STRATEGY.md) §6). Reverificado el 30-oct, todo en
     verde:
     - 256×500 con `0x2a` y `0x3` y `validate` (semilla `0x030681159d224858`): 9 de 9 con los escenarios y 0
       reversiones;
     - las 39 mutaciones detectadas, en las mismas variantes que antes;
     - con `fail_on_revert`, 384.000 llamadas en la variante con protocolo, sin reversiones.

     Las de 128×6000 murieron el 29-oct sin resultados y se relanzaron el 30-oct desde el panel, con las mismas
     semillas:
     - TokenizedStrategy, a las 08:19, con el harness del #92:
       `20261030-081941_tokenized-strategy_128x6000_0x558c16a948b3b745`;
     - EulerEarn, a las 08:21: `20261030-082114_euler-earn_128x6000_0xf204663f1abb7cbe`. El primer intento no
       arrancó porque el ciclo había movido el clon (abajo, «Los clones de `NEXUS_HOME/work`»).

     Al terminar, leer `FIN ... salida N` y las reversiones por acción, y anotar el resultado acá. Los resultados de las
     campañas están en
     `NEXUS_HOME\secresearch\campanas\` (privado) y se ven en el panel.
   - **Herramienta nueva:** `vyper` 0.3.10 quedó instalado en el venv (28-oct, `pip install vyper==0.3.10`; anda en
     Python 3.12 con avisos de deprecación y compila `VaultV3.vy` en ~6 s). Los tests de foundry de
     `yearn-vaults-v3` despliegan con `VyperDeployer`, que llama a `vyper` por FFI: con FFI apagado (R-2, R-6) no
     sirven. El harness del vault tiene que compilar Vyper con forge (nativo, con el `vyper` del venv en el PATH) y
     desplegar con `deployCode`. Probablemente eso explica la línea base del 26-oct que no compiló.
9. **Mejoras del cazador:**
   - una variante de 18 decimales con depósito inicial, como recomienda MetaMorpho, donde un depósito con 0 acciones
     sí sería una señal;
   - montos escalados por decimales: hoy el fuzzer usa hasta 1e28 unidades también con 6 decimales;
   - una métrica de cuánto pierde la víctima por cada unidad que gasta el atacante en la macro de inflación;
   - que `check()` informe también la primera violación del cazador. Hoy guarda solo la primera de todas, y por eso
     `mutate.py` dejó de atribuirle M7 y M15 a una ley `H-...`, aunque siguen detectadas;
   - que el fuzzer no llame `failed()`: los handlers de TokenizedStrategy y del Vault V3 heredan `Test` de forge-std,
     que la expone, y se lleva cerca del 4 % de las llamadas (27.474 de 768.000 en la campaña de TokenizedStrategy).
     Se arregla con `targetSelector` en el `setUp` o con un handler que no herede `Test`. Hay que volver a verificar
     cada harness que se toque (la distribución de llamadas cambia). Revisar también los demás harness;
   - revisar si EulerEarn, MetaMorpho y Vault V2 pueden caer en la misma inflación de acciones que el Vault V3 y
     TokenizedStrategy (#91 y #92). Sus campañas no tuvieron reversiones del handler, pero el mecanismo (una pérdida
     casi total y depósitos después) es genérico de los vaults con acciones.
10. **Morpho Midnight: la variante A está en `main` desde el #89, y la B va en el #90** (rama
    `claude/midnight-variante-b`). Ver [CAZADOR_MIDNIGHT.md](CAZADOR_MIDNIGHT.md).
   - **Variante B:**
     - los callbacks del comprador, del vendedor, del repago y de la liquidación operan sobre Midnight en medio de la
       operación: colateral, repago, retiro, `updatePosition`, liquidaciones y un `take` anidado;
     - el bloqueo de liquidación del vendedor, el pagador de cada operación, el préstamo flash, `multicall` y los
       gates de entrada y de liquidadores;
     - el modelo predice cada operación anidada sobre el estado intermedio (MN-LIVE) y lleva los saldos de siete
       tenedores;
     - dos suites: sin gates y con gates.
   - **Verificación del harness final (30-oct):**
     - las seis suites (cuatro de la A y dos de la B) pasan 32×300 con `0x2a` y `0x3`, sin falsos positivos ni
       reversiones;
     - `validate` sobre el repo entero a 64×300 (semilla `0x7dea4e2c53b47e39`) da 10 de 10, con las pruebas de
       regresión, y 0 reversiones;
     - las 47 mutaciones de referencia se detectan: M1–M37 del núcleo y B1–B10 de bloqueo, pagadores, préstamo flash y
       gates.

     **Sin hallazgos.**
   - **Campaña profunda de la A** (29-oct, 1536×500, 768.000 llamadas por variante, semilla `0xd965aa70462df72e`): las
     cuatro variantes en verde y ninguna ley violada. La de 6 decimales tuvo 14 reversiones del handler en `liqCycle`:
     - era una división por cero del cazador, no de Midnight;
     - los desplomes de `badDebtCycle` llevan el precio de un colateral a 1, y `liqCycle` lo baja a 0;
     - está arreglado en el #90, con la prueba `test_liqCycleConPrecioCero`;
     - después del arreglo, la variante de 6 decimales pasó seis corridas de 128×500 con `fail_on_revert` (384.000
       llamadas) sin reversiones.

     Lección: en cada campaña hay que mirar la columna de reversiones por acción, no solo el PASS.
   - **Campaña profunda de la B** (30-oct, de las 03:33 a las 06:58, 1536×500, 768.000 llamadas por suite, semilla
     `0xc14689c092fb170f`, `20261030-033259_midnight_1536x500_0xc14689c092fb170f`): las dos suites, sin gates y con
     gates, en verde. **Ninguna ley violada y 0 reversiones del handler.** En la última corrida de cada suite hubo:
     - unas 52.000 leyes evaluadas y 16 a 23 `take`;
     - 14 a 16 operaciones con callback y 32 anidadas, de las que pasaron 23 a 25;
     - un intento sobre el vendedor bloqueado;
     - 13 a 15 préstamos flash y 21 `multicall`.
   - La etapa E está en `NEXUS_HOME/secresearch/etapa_e/morpho-org__midnight/` (privado): el índice, las 15
     auditorías en texto, la versión desplegada de cada contrato y el diseño del cazador.
   - Contexto de verificación previa:
     - las auditorías del núcleo no tienen Critical ni High;
     - la competencia de Cantina de mayo dio 0 High y 0 Medium;
     - Certora verifica los invariantes centrales, con `mulDiv` como axiomas, bucles acotados y sin `multicall`.
     El cazador aporta la aritmética concreta en secuencias largas y la ley MN-CLAIM, que exige que los reclamos no
     superen el respaldo.
   - **La periferia nueva, revisada a mano el 29-oct:** `RateRatifierV1` y `PriceRatifierV1` (2026-09-24),
     `BlueFallbackRolling` (2026-09-02) y `BlueBuyCallback`. Sin candidatos, y lo de sus auditorías está aceptado o
     documentado. Un cazador de fuzzing aportaría poco: son contratos chicos, y el ratifier por firma necesitaría
     firmas en el harness, que el test de coherencia no permite. El detalle está en
     `etapa_e/morpho-org__midnight/revision_periferia.md` (privado).
   - **Falta:**
     - extender la B a lo que todavía no cubre (CAZADOR_MIDNIGHT.md §8): un `take` anidado con sus propios callbacks,
       `multicall` dentro de un callback y gates que distingan cuentas;
     - un cazador de MetaMorpho V1.1, evaluado el 29-oct con valor esperado bajo. Lo desplegado son los commits
       `8b578d3` a `b60364d`. Los cuatro cambios frente a la V1.0 son chicos, `lostAssets` tiene specs de Certora y ya
       se cazó en EulerEarn (fork), y las auditorías de la V1.1 no tienen Medium abiertos. Detalle en
       `etapa_e/morpho-org__metamorpho-v1.1/indice.md` (privado).

## 6. Pendientes y cuidados

- **Los clones de `NEXUS_HOME/work` son compartidos.** El ciclo desatendido los mueve al último commit para sus
  líneas base. `validate` vuelve al commit fijado; `tools/forge_v2`, no. El 30-oct el ciclo movió los de Midnight,
  Vault V3, TokenizedStrategy y EulerEarn, y en EulerEarn también el submódulo del EVC, que volver al commit fijado
  no restaura.
  - Desde el 30-oct, `armar` y `mutar` controlan el commit y los submódulos que copian, y frenan con el comando para
    volver.
  - Se revisó con el reflog: las verificaciones del 30-oct se hicieron con los clones en el commit fijado.
- **Campañas que sobreviven a la sesión:** desde el 29-oct `panel.launch` pide separarse del job de quien lanza
  (`CREATE_BREAKAWAY_FROM_JOB`) y, si Windows no lo permite, lanza como antes. Una campaña lanzada a mano desde una
  sesión de Claude Code, sin el panel, muere si la sesión se reinicia.
- **Prioridad de las campañas:** desde el 29-oct corren por debajo de lo normal (la heredan forge_v2 y forge). Usan
  todo el CPU libre y le ceden el paso a lo corto: una verificación, una batería de mutaciones o el uso de la PC.
- **La PC:** Intel i5-8265U (4 núcleos y 8 hilos, serie U de 15 W), 12 GB de RAM y SSD. Con dos trabajos de forge de 4
  variantes ya se usan los 8 hilos; un tercero en paralelo no suma rendimiento total.

- **El catálogo vive en la PC.** El repo trae solo un ejemplo (`catalogo.ejemplo.yaml`). En la PC hubo un
  `secresearch.yaml` suelto en la carpeta del repo; quedó en un `git stash` del dueño. No se usa, porque nexus lee el
  de `%LOCALAPPDATA%\nexus`, y no conviene devolverlo a la carpeta del repo: es público.
- **Ramas viejas del trading:** `pc-status`, `pc-sesion` y `data`. No se usan; borrarlas es decisión del dueño.
- **Tests en la PC:** `python -m pytest -q` corrido directo en Windows necesita `$env:PYTHONUTF8 = '1'`. Sin eso,
  tres tests fallan al leer archivos con acentos en la codificación de Windows. `devcheck` ya lo define.
- **Errores de nexus que no son fallas del objetivo:** el 27-oct la línea base de `euler-vault-kit` pasó entera
  (483 pasan, 3 omitidos), pero el informe se cayó con un `TypeError`. La suite ESR llama `transfer`, `approve` y
  `mint` del token y del vault; al quitar el nombre del contrato, ordenar los pares repetidos comparaba diccionarios.
  Ahora el nombre repetido queda como `Contrato.función`.
- **Si aparece una falla en la PC:**
  1. Reproducirla con la semilla del informe.
  2. Clasificarla. Si es un error del harness, se corrige. Si es un candidato, se aísla en un test mínimo, independiente
     del harness, y se revisa contra las auditorías.
  3. Abrir el expediente con `python -m nexus.secresearch.expediente INFORME` y completarlo con el dueño.
  4. Un falso positivo también lleva expediente, con `estado: descartado` y la razón.
  5. Nada de eso va al repo (R-4).
- **Cuidados con los números:** solo cuenta como ingreso una recompensa cobrada (R-10). Las severidades siguen la
  tabla del programa, sin exagerar (R-7).
