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
`0x2a`; `NEXUS_MUT_RUNS="256 500 0x3"` cambia la intensidad. Una mutación que ninguna variante detecta es un punto ciego
del harness.

El mismo `mutaciones.json` sirve en la nube con `MUTATION='{"file":"src/VaultV2.sol","old":...,"new":...}' node
tools/edr/build_v2.js ...` (ver `tools/edr/README.md`).
