# Traspaso: estado de nexus y cómo continuar

Documento de entrega para retomar el proyecto desde cualquier conversación nueva con Claude. Actualizado el
27-oct-2026. Si algo de acá contradice al código, manda el código; si contradice a [REGLAS.md](REGLAS.md), mandan
las reglas.

Para arrancar una sesión que trabaje directo en la PC del dueño, con acceso a GitHub, el prompt de arranque está en
[PROMPT_SESION_PC.md](PROMPT_SESION_PC.md).

## 1. Qué es nexus

Un motor de **investigación de seguridad DeFi** para programas de bug bounty **autorizados**. Corre en la PC del
dueño (Windows), busca errores en vaults ERC-4626 con tests locales y prepara el informe para reclamar la
recompensa. **Nunca envía nada ni prueba contra contratos desplegados.** Hasta el 26-oct-2026 el repo era un bot de
trading; ese código quedó en el historial de git.

Antes de tocar nada, leer en este orden:

1. [REGLAS.md](REGLAS.md): reglas R-1 a R-10. Es un archivo protegido.
2. Este documento.
3. [INVESTIGACION_SEGURIDAD.md](INVESTIGACION_SEGURIDAD.md): el pipeline, el estado por etapa y la iteración PC ↔ Claude.
4. [CAZADOR_METAMORPHO.md](CAZADOR_METAMORPHO.md): el modelo formal, las leyes, la verificación y cómo leer el informe.

Las reglas que más pesan al trabajar:

- **R-4:** los resultados son privados y quedan en la PC (`NEXUS_HOME`). Nunca van al repo, que es público: un
  hallazgo publicado sería divulgar una vulnerabilidad sin reportar. `limits.results_dir` lo hace cumplir.
- **R-3:** nada se envía solo; cada informe lo revisa y lo envía el dueño.
- **R-2 y R-6:** todo en local, con FFI de Foundry siempre apagado, sin `forge script`, `--broadcast` ni `cast send`.
- **R-7:** sin exagerar. Un candidato es "confirmado" solo con un test reproducible que muestre el efecto económico.
- **R-9:** ningún agente amplía el alcance, sube topes, cambia las reglas ni se da permisos.

## 2. Cómo se trabaja

### Roles y flujo

- **El dueño** corre todo en su PC, decide el alcance (el catálogo), fusiona los PR y envía los informes.
- **Claude en la nube** no llega a la PC. Escribe código en una rama `claude/...`, lo verifica sin forge (abajo) y
  abre un PR a `main`. **Nunca fusiona.** Un PR que toque rutas protegidas (`.github/`, `tools/protected_paths.py`,
  `local/nexus/secresearch/limits.py`, `local/tests/test_limits.py`, `docs/REGLAS.md`) queda en rojo en CI y solo
  lo aprueba el dueño.
- **La iteración:** el dueño hace `git pull` en `main`, corre `validate` o deja correr el ciclo diario, y le pega a
  Claude la salida de la consola o `%LOCALAPPDATA%\nexus\secresearch\para_claude.md`. Claude analiza, mejora el
  harness y abre otro PR. Alternativa: abrir Claude Code en la PC (app de escritorio o `claude remote-control`),
  que lee los informes directo y tiene forge.

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

El Explorador oculta `AppData`: `explorer $env:LOCALAPPDATA\nexus\secresearch`.

### Verificar sin forge, en la nube

En la nube no se puede instalar Foundry (los hosts de descarga están bloqueados). Se usa `tools/edr`: solc-js y EDR,
el motor de tests Solidity de Hardhat 3, con cheatcodes compatibles con forge. Ver [tools/edr/README.md](../tools/edr/README.md).

```bash
cd tools/edr && npm install
node build.js $CLON salida.out.json                       # via_ir: el harness tarda de 6 a 13 minutos
node run_edr.js $CLON salida.out.json 64 256 500 invariant 0x2a   # fuzz, corridas, profundidad, filtro, semilla
python3 mutate.py $CLON salida.out.json                   # las 21 mutaciones de referencia (~15 minutos)
```

Lo que conviene saber:

- Sacar `NexusMetaMorphoERC4626.t.sol` del clon acelera la compilación; es independiente del resto.
- EDR no devuelve los logs de `afterInvariant`. Forge sí, pero solo con `-vv`: por eso `validate` lo usa.
- Con via_ir, `block.timestamp` puede quedar cacheado después de `vm.warp`. El cazador lee la hora con `NexusClock`.
- Los tests de Python prohíben ciertas cadenas en los `.py` del motor (`limits.FORBIDDEN`: `forge script`,
  `.post(`, `private_key`, etc.).
- Antes de cada PR, lo mismo que CI: `ruff check --line-length 120 nexus tests`, `python -m pytest -q`,
  `python -m nexus.secresearch.run --selfcheck` (desde `local`) y `python tools/protected_paths.py --self-test`.

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

## 3. Estado por etapa (27-oct-2026)

| Etapa | Estado |
|---|---|
| A. Catálogo y cambios | Funciona. El catálogo real está en la PC; programas elegidos: Morpho (Cantina), Yearn V3 (Immunefi) y Euler v2 (Cantina) |
| B. Triaje | Funciona: puntaje determinista sin IA |
| C. Método de invariantes | Funciona: P0–P6 en Python, con autoverificación |
| D. Validación con Foundry | Funciona en la PC: `validate` clona fijado a un commit, FFI apagado, informe privado |
| D'. Harness de MetaMorpho | Funciona: suite a16z, handler original y `NexusVulnerabilityHunter` con una suite multi-mercado con gobierno |
| D''. Harness de Vault V2 | Funciona (27-oct): variante A con capital asignado de verdad, 8 leyes `V-...` verificadas con forge en la PC, 13 mutaciones de referencia detectadas ([CAZADOR_VAULT_V2.md](CAZADOR_VAULT_V2.md)) |
| Ciclo desatendido | Funciona: corre A–C, los harness con semilla nueva y líneas base; escribe `para_claude.md` y el dashboard |
| Dashboard | Nuevo (27-oct): página local con fallas, cobertura, métricas, corridas, programas, cambios, ciclos y expedientes |
| E. Duplicados | Parcial: falta revisar las auditorías previas de MetaMorpho |
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

## 5. Próximos pasos

En orden de prioridad:

1. **Dueño:** fusionar el #80 y hacer `git pull` en `main`. Lo que pedía el #76 ya está probado: la
   corrida de MetaMorpho del 27-oct a las 10:18 pasó en verde y `colaSuministro` subió de 3–8 a 18–19 por corrida. El
   ciclo del 28-oct tendría que terminar en verde también con la línea base de Euler (el `TypeError` del 27-oct se
   corrigió en el #79).
2. **Dueño:** dar de baja la tarea vieja `nexus-latido`, que apunta a un script del trading que ya no existe. Ya está
   deshabilitada y no falla más, pero sigue registrada. La sesión de la PC no la pudo borrar porque el control de
   permisos de Claude Code bloquea las bajas: `Unregister-ScheduledTask -TaskName nexus-latido -Confirm:$false`.
3. **Dueño, alcance (R-1, R-9):** el reglamento de Morpho en Cantina remite a la
   [página de direcciones](https://docs.morpho.org/developers/contracts/addresses/) como fuente de verdad del alcance.
   Ahí figuran dos cosas que no estaban en el catálogo; el 27-oct ya aparecen en el catálogo de la PC, bajo el
   programa Morpho. Que estén en alcance es decisión del dueño, después de leer el reglamento:
   - **Morpho Midnight** (`morpho-org/midnight`): préstamos a tasa fija, desplegado y en el alcance del programa.
   - **MetaMorpho V1.1** (`morpho-org/metamorpho-v1.1`, commit `5a0717b`): es la fábrica actual. nexus prueba
     `morpho-org/metamorpho`, que corresponde a la fábrica vieja (commit `c5e758d`, que también figura): su
     `MetaMorpho.sol` difiere de `ded84e5` solo en formato y comentarios, así que lo probado vale para esos vaults.
4. **Vault V2** (`morpho-org/vault-v2`, ya en el catálogo). Es el objetivo en curso. Alcance contrastado el 27-oct:
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
   - **Falta:** `forceDeallocate` (V-FD-1) y los topes como ley (V-CAP-1), que ya tienen capital asignado sobre el que
     correr; el gobierno con timelock; la variante B (adapter real sobre Morpho Blue); y la cota V-BOUND como ley.
   - La línea base de V2 (los tests del repo) es cara: compila en ~11 min y los tests tardan ~35. El harness solo, con
     `validate`, tarda ~10 min de compilación y ~11 de tests; para iterar, `tools/forge_v2` (~30 s).
5. **Etapa E para MetaMorpho:** revisar las auditorías que trae el repo de MetaMorpho en `audits/` (la revisión de
   Cantina de 2023-11, la de OpenZeppelin de la periferia de Morpho Blue de 2023-11 y la competencia de Cantina de
   2024-01) contra las leyes y los comportamientos conocidos, para que un candidato futuro no resulte un duplicado.
6. **Yearn V3 y Euler v2:** `yearn-vaults-v3` no compiló dentro del tope de 2400 s del 26-oct; hay que ver si falta
   `vyper` 0.3.10 en el venv. Después viene Euler v2.
7. **Mejoras del cazador:**
   - una variante de 18 decimales con depósito inicial, como recomienda MetaMorpho, donde un depósito con 0 acciones
     sí sería una señal;
   - montos escalados por decimales: hoy el fuzzer usa hasta 1e28 unidades también con 6 decimales;
   - una métrica de cuánto pierde la víctima por cada unidad que gasta el atacante en la macro de inflación;
   - que `check()` informe también la primera violación del cazador. Hoy guarda solo la primera de todas, y por eso
     `mutate.py` dejó de atribuirle M7 y M15 a una ley `H-...`, aunque siguen detectadas.

## 6. Pendientes y cuidados

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
