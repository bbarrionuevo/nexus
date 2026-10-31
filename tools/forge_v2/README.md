# Harness de Vault V2 con forge, en un proyecto reducido (PC)

`validate` compila el repo entero de Vault V2: MidnightAdapter, Morpho Blue, MetaMorpho y todos sus tests. En la PC
tarda ~11 minutos. Para iterar el harness y correr la batería de mutación alcanza con VaultV2, la factory, el
`ERC20Mock`, el `MorphoMarketV1AdapterV2` y, para la variante B, Morpho Blue y la IRM adaptativa (0.8.19, con la misma
restricción de compilación que el repo), forge-std y el harness. El proyecto reducido usa los mismos ajustes de
compilación que el `foundry.toml` del repo (via_ir, optimizer 100000, cancun; el solc de cada pragma), así que el
bytecode de VaultV2 es el mismo, y compila en ~1,5 min la primera vez y en ~30 s después.

En la PC no hay Node, así que esto reemplaza a `tools/edr` (que es para la nube). La referencia sigue siendo `validate`
sobre el repo entero: lo de acá sirve para iterar y para la prueba de no vacuidad, no para declarar un harness verificado.

Todo corre en local con FFI apagado (REGLAS R-2 y R-6): solo `forge build` y `forge test`, sobre un repo del catálogo.

```powershell
cd $env:USERPROFILE\nexus
$CLON = "$env:LOCALAPPDATA\nexus\work\morpho-org__vault-v2"   # el clon de validate, con submódulos
$RED  = "$env:LOCALAPPDATA\nexus\work\vault-v2-reducido"
.venv\Scripts\python tools\forge_v2\forge_v2.py armar  $CLON $RED
.venv\Scripts\python tools\forge_v2\forge_v2.py correr $RED 256 500 0x2a      # corridas, profundidad, semilla
.venv\Scripts\python tools\forge_v2\forge_v2.py mutar  $RED $CLON             # o solo algunas: ... mutar $RED $CLON V7 V12
```

`correr` copia el harness de `local/nexus/secresearch/harness/morpho-org__vault-v2/`, hace `forge build` (con un
filtro de tests, forge solo compila lo que esos tests importan, y Morpho Blue, que se despliega con `deployCode`, quedaría
afuera) y muestra el log de `afterInvariant` (cobertura y métricas del cazador). El `forge build` previo solo lo hacen
los perfiles con `"build"` (`vault-v2`, `vault-v3` y los tres de Bundles, los que despliegan artefactos por nombre; una
prueba lo ata al uso de `deployCode`): `forge test` no reusa su caché, y en los demás compilaba todo dos veces. Con
`"build": "once"` (los tres de Bundles, donde lo desplegado por nombre, Blue, la IRM, Vault V2 y su adapter, no se
muta), `mutar` compila entero una sola vez. `mutar` aplica cada entrada de
`mutaciones.json` (`[nombre, original, mutado]` sobre `src/VaultV2.sol`, o `[nombre, original, mutado, archivo]`, por
ejemplo sobre el adapter real) a una copia limpia de ese archivo del clon, corre todas las variantes sin achicar la
secuencia y lista, por variante, las leyes `V-...` que fallaron. El cazador informa todas las
leyes que fallan, no solo la primera, con `[leyes: ...]` al final del motivo. Por defecto corre 64×200 con la semilla
`0x2a`; `NEXUS_MUT_RUNS="256 500 0x3"` cambia la intensidad, y `NEXUS_MUT_MATCH="^NexusVaultV2Invariant"` corre solo
la variante A (la única con gobierno: para las mutaciones V36–V54 alcanza y ahorra la variante B). Una mutación que
ninguna variante detecta es un punto ciego del harness.

El mismo `mutaciones.json` sirve en la nube con `MUTATION='{"file":"src/VaultV2.sol","old":...,"new":...}' node
tools/edr/build_v2.js ...` (ver `tools/edr/README.md`).

## Perfil de EulerEarn

`NEXUS_PERFIL=euler-earn` hace lo mismo con `euler-xyz/euler-earn` (programa Euler v2): `armar` copia solo `src`,
OpenZeppelin, el EVC y forge-std con los ajustes del repo (solc 0.8.26, via_ir, 200 runs, cancun), `correr` usa el
harness de `harness/euler-xyz__euler-earn/` y el filtro `^NexusEulerEarn`, y `mutar` toma `mutaciones_euler_earn.json`
(por defecto sobre `src/EulerEarn.sol`). El clon tiene que estar en `a8cc099`, la versión desplegada (ver
[CAZADOR_EULER_EARN.md](../../docs/CAZADOR_EULER_EARN.md)). El build entero del repo no compila con forge 1.8.6
(forge-std duplicado entre el EVK y Permit2 en sus tests), así que este proyecto reducido es también la única forma de
iterar el harness; `validate` compila solo `src` y el harness con `"aislado": true` en el manifiesto.

```powershell
$CLON = "$env:LOCALAPPDATA\nexus\work\euler-xyz__euler-earn"   # en a8cc099, con submódulos (core.longpaths)
$RED  = "$env:LOCALAPPDATA\nexus\work\euler-earn-reducido"
$env:NEXUS_PERFIL = "euler-earn"
.venv\Scripts\python tools\forge_v2\forge_v2.py armar  $CLON $RED
.venv\Scripts\python tools\forge_v2\forge_v2.py correr $RED 256 500 0x2a
.venv\Scripts\python tools\forge_v2\forge_v2.py mutar  $RED $CLON
```

## Perfil de TokenizedStrategy

`NEXUS_PERFIL=tokenized-strategy` hace lo mismo con `yearn/tokenized-strategy` (programa Yearn V3): `armar` copia
`TokenizedStrategy.sol`, `BaseStrategy.sol`, sus interfaces y la librería, OpenZeppelin 4.9.5 y forge-std 1.5.2 (sin
los tests del repo, que viven en `src/test`) con los ajustes del repo (solc 0.8.18, sin via_ir, 200 runs, paris),
`correr` usa el harness de `harness/yearn__tokenized-strategy/` y el filtro `^NexusTokenizedStrategy`, y `mutar` toma
`mutaciones_tokenized_strategy.json` (sobre `src/TokenizedStrategy.sol`). El clon tiene que estar en el tag `v3.1.0`
(`8c8929f`), la versión en alcance: su `BaseStrategy` apunta a la dirección desplegada, donde el harness copia la
implementación local (ver [CAZADOR_TOKENIZED_STRATEGY.md](../../docs/CAZADOR_TOKENIZED_STRATEGY.md)).

```powershell
$CLON = "$env:LOCALAPPDATA\nexus\work\yearn__tokenized-strategy"   # git checkout v3.1.0
$RED  = "$env:LOCALAPPDATA\nexus\work\ts-reducido"
$env:NEXUS_PERFIL = "tokenized-strategy"
.venv\Scripts\python tools\forge_v2\forge_v2.py armar  $CLON $RED
.venv\Scripts\python tools\forge_v2\forge_v2.py correr $RED 256 500 0x2a
.venv\Scripts\python tools\forge_v2\forge_v2.py mutar  $RED $CLON
```

## Fuzzing guiado por cobertura (corpus)

`correr` y `mutar` activan por defecto el corpus de forge (`FOUNDRY_INVARIANT_CORPUS_DIR=cache/invariant/corpus`):
forge guarda las secuencias que abren caminos nuevos y las muta, y cada pocos segundos escribe un evento `pulse` por
suite (transacciones, velocidad, caminos vistos, tamaño del corpus) que el panel usa para mostrar el avance y cuánto
falta. `mutar` borra `cache/invariant` entre mutaciones, así que cada una arranca de cero. El 30-oct, con el mismo
presupuesto (32×200, semillas `0x2a` y `0x3`), la suite con gates de Midnight detectó 4 de 6 mutaciones raras (M25,
M35, B3) con corpus y 1 de 6 sin él. `NEXUS_CORPUS=0` lo apaga; en el panel, la casilla "guiada por cobertura".

Las campañas del panel usan un corpus **acumulado**: `NEXUS_HOME/secresearch/corpus/<perfil>/<hash del harness>/`.
Cada campaña arranca de las secuencias que abrieron caminos en las anteriores del mismo harness y las sigue mutando;
si el harness cambia, el hash cambia y el corpus arranca de cero (las entradas llevan la dirección del handler y los
selectores). forge guarda cada entrada con un UUID y por suite (`corpus/<suite>/worker<n>/`), así que dos campañas
del mismo harness pueden compartirlo. `--resumen` dice cuántas secuencias tiene.

## Modo simbólico de forge (evaluado el 30-oct)

forge 1.8.6 trae ejecución simbólica (`forge test --symbolic`, compatible con Halmos) y puede intentar dar vuelta las
"fronteras" de rama que deja el fuzzing (`--symbolic-use-fuzz-frontiers`, con `FOUNDRY_INVARIANT_FRONTIER_DIR`). El
solver es z3: `z3-solver` 5.3.3 quedó instalado en el venv (`.venv\bin\z3.exe`, pasarlo con `--symbolic-solver`).

- **Funciona en propiedades chicas** (funciones `check_` o `prove_`): una fórmula de comisión falsa a propósito dio su
  contraejemplo en 81 ms. Una verdadera con multiplicación y división de 128×64 bits terminó en `unknown` por tiempo:
  z3 no prueba aritmética no lineal de 256 bits, solo encuentra contraejemplos.
- **No sirve con los cazadores de invariantes**: con la fase 1 de MidnightBundlesV2 y sus fronteras (una secuencia por
  comparación sin dar vuelta, hasta 256) corrió 30 minutos sin terminar ni escribir nada. Los cazadores deciden con
  hashes de las semillas, que un solver no puede invertir, y cada frontera agota el tiempo del solver.
- **Uso:** chequeos puntuales de fórmulas (redondeos, comisiones, conversiones) que el fuzzing ve poco, como
  complemento; no como reemplazo de las campañas.

## Filtro, versión fijada y panel

- `NEXUS_MATCH="^NexusTokenizedStrategyInvariantFeeTest$"` hace que `correr` corra una sola variante (sin eso, todas
  las del perfil).
- Los perfiles con commit desplegado fijado (EulerEarn `a8cc099`, TokenizedStrategy `8c8929f`, Vault V3 `5b698f9`,
  Midnight `14e0b77`): `armar` y `mutar` se niegan a usar un clon que esté en otro commit, o con un submódulo del que
  copian algo en otro commit que el que fija ese. El ciclo desatendido comparte los clones y los mueve al último commit
  para sus líneas base, y volver al commit fijado no mueve los submódulos (30-oct: el EVC de EulerEarn). El mensaje
  dice el `git checkout` o el `git submodule update --init` que hace falta.
- El panel local (`python -m nexus.secresearch.panel`, desde `local`) lanza `armar` + `correr` con estos mismos
  parámetros en un proyecto propio dentro de `NEXUS_HOME/work/panel/` y deja el log en `secresearch/campanas/`.

## Perfil del Vault V3 de Yearn

`NEXUS_PERFIL=vault-v3` hace lo mismo con `yearn/yearn-vaults-v3` (programa Yearn V3): `armar` copia `VaultV3.vy` y
`VaultFactory.vy`, OpenZeppelin 4.9.5 y forge-std con los ajustes del repo (solc 0.8.18, paris, vyper `optimize =
"codesize"`), y `mutar` toma `mutaciones_vault_v3.json` (sobre `contracts/VaultV3.vy`). El clon tiene que estar en el
tag `v3.1.0` (`5b698f9`). Forge compila Vyper con el `vyper` 0.3.10 del venv: `forge_v2` lo pone en el PATH (si se
corre forge a mano, agregar `.venv\Scripts` al PATH).

## Perfil de Morpho Midnight

`NEXUS_PERFIL=midnight` hace lo mismo con `morpho-org/midnight` (programa Morpho):
- **`armar`:** copia el núcleo (`src/Midnight.sol`, sus librerías e interfaces) y forge-std con los ajustes del repo
  (solc 0.8.34, `osaka`, via_ir, 466 runs). La periferia queda afuera: con via_ir, compilar `src` entero llevó unos 40
  minutos con la PC cargada, y el proyecto reducido compila en unos 3.
- **`mutar`:** toma `mutaciones_midnight.json`, 47 mutaciones sobre `src/Midnight.sol`. M1 a M37 son de la
  contabilidad; B1 a B10 son del bloqueo de liquidación, de quién paga con callbacks, del préstamo flash y de los
  gates, y las ve la variante B (`NexusMidnightCallbacks…`).
- **El clon:** tiene que estar en la etiqueta `2026-08-24` (`14e0b77`), la última idéntica al núcleo desplegado.
- **La batería:** cada mutación recompila con via_ir. Conviene `NEXUS_MUT_RUNS="32 200 0x2a"`.

## Perfil de MidnightBundlesV2 (Morpho Bundles)

`NEXUS_PERFIL=midnight-bundles` hace lo mismo con `morpho-org/bundles` (programa Morpho):
- **`armar`:** copia `MidnightBundlesV2` con sus interfaces y `TokenLib`, el núcleo de Midnight de su submódulo
  (`lib/midnight`, misma lógica que el desplegado), las interfaces de Blue y Permit2 que importa, y forge-std, con los
  ajustes del repo salvo `optimizer_runs` (200 en vez de 4294967295, para compilar rápido; no cambia la semántica).
- **`mutar`:** toma `mutaciones_midnight_bundles.json`: U1 a U24 sobre las entradas de toma de
  `src/midnight/MidnightBundlesV2.sol` (comisiones de referido, garantías del usuario, exactitud del objetivo,
  validaciones, destinatarios y saldos que se queda el bundle), K1 a K6 sobre `CancelAndMake`, C1 y C2 sobre
  `BlueBuyCallback` y R1 y R2 sobre `PriceRatifierV1`. Las U las ven las suites de la fase 1
  (`NEXUS_MUT_MATCH='^NexusMidnightBundles(Fees)?Test$'`); las K, C y R, las de la fase 2
  (`NEXUS_MUT_MATCH='^NexusMidnightBundlesMake'`).
- **Fase 2:** Blue (solc 0.8.19) se despliega con `deployCode` desde `NexusBlueImport.sol`, que solo lo importa para
  que se compile; por eso el perfil lleva `"build": "once"`.
- **El clon:** tiene que estar en la etiqueta `2026-10-06` (`2ed954e`, lo desplegado en `0x78ed…bDbA4`).
- **El cazador:** [docs/CAZADOR_MIDNIGHT_BUNDLES.md](../../docs/CAZADOR_MIDNIGHT_BUNDLES.md).

## Perfil de BlueBundlesV1 (Morpho Bundles)

`NEXUS_PERFIL=blue-bundles` comparte el clon fijado de `midnight-bundles` (lo desplegado, la etiqueta `2026-08-25`,
difiere de `2ed954e` solo en dos comentarios):
- **`armar`:** copia `BlueBundlesV1` con sus interfaces y `TokenLib`, Morpho Blue de su submódulo y forge-std; Blue
  (0.8.19) se despliega con `deployCode` desde `NexusBlueImport.sol`, de ahí `"build": "once"`.
- **`mutar`:** toma `mutaciones_blue_bundles.json`: B1 a B18 sobre `src/blue/BlueBundlesV1.sol`. Las B15 a B18
  (el control de `maxLtv`: sin devengar, con la deuda o el máximo redondeados al revés, o estricto) solo se ven con
  interés en Blue y con el borde de `maxLtv` exacto al wei, desde el 31-oct.
- **El cazador:** [docs/CAZADOR_BLUE_BUNDLES.md](../../docs/CAZADOR_BLUE_BUNDLES.md).

## Perfil de los Bundles de vaults (Morpho Bundles)

`NEXUS_PERFIL=vault-bundles` comparte el mismo clon (lo desplegado son las etiquetas `2026-08-07` a `2026-08-24`;
hasta `2ed954e` solo cambiaron comentarios):
- **`armar`:** copia `VaultBundlesV1` y `VaultExitBundlesV1` con sus interfaces y `TokenLib`, y de los submódulos
  `lib/vault-v2` (Vault V2, su fábrica, el `MorphoMarketV1AdapterV2` con su fábrica y la IRM adaptativa) y
  `lib/metamorpho` (las interfaces de Vault V1). Hay tres compiladores: los bundles en 0.8.34, Vault V2 en 0.8.28
  (`NexusVaultImport0828.sol`) y Blue y la IRM en 0.8.19 (`NexusBlueImport.sol` y `NexusVaultImport0819.sol`); todo
  lo que no son los bundles se despliega con `deployCode`, de ahí `"build": "once"`.
- **Un solo `Morpho.sol`:** `validate` compila el harness entero junto, y con dos copias de Blue
  `deployCode("Morpho.sol")` sería ambiguo; por eso el perfil usa el `NexusBlueImport.sol` de los otros cazadores de
  Bundles, y una prueba lo controla.
- **`mutar`:** toma `mutaciones_vault_bundles.json`: W1 a W13 sobre `src/vault/VaultBundlesV1.sol` y X1 a X15 sobre
  `src/vault-exit/VaultExitBundlesV1.sol`, todas detectadas el 31-oct. Las W9 a W13 y X9 a X15 se sumaron con las
  mejoras del cazador: el precio por acción no redondo, el control de precio en su borde exacto (en las dos
  direcciones), la cota de acciones del retiro forzado y la penalidad variable.
- **El cazador:** [docs/CAZADOR_VAULT_BUNDLES.md](../../docs/CAZADOR_VAULT_BUNDLES.md).
