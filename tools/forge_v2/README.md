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
afuera) y muestra el log de `afterInvariant` (cobertura y métricas del cazador). `mutar` aplica cada entrada de
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

## Filtro, versión fijada y panel

- `NEXUS_MATCH="^NexusTokenizedStrategyInvariantFeeTest$"` hace que `correr` corra una sola variante (sin eso, todas
  las del perfil).
- Los perfiles de EulerEarn y TokenizedStrategy fijan el commit desplegado (`a8cc099`, `8c8929f`): `armar` se niega a
  copiar un clon que esté en otro commit (lo puede haber movido `validate`).
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
- **`mutar`:** toma `mutaciones_midnight.json`, 37 mutaciones sobre `src/Midnight.sol`.
- **El clon:** tiene que estar en la etiqueta `2026-08-24` (`14e0b77`), la última idéntica al núcleo desplegado.
- **La batería:** cada mutación recompila con via_ir. Conviene `NEXUS_MUT_RUNS="32 200 0x2a"`.
