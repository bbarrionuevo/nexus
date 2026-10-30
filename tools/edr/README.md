# Verificación de harness sin forge (solc-js + EDR)

**Histórico.** Desde el 30-oct-2026 Claude trabaja en nexus solo en la PC del dueño, con forge (docs/REGLAS.md, R-12):
esta herramienta ya no se usa, y queda por si algún día no hay forge.

En la nube de Claude no se puede instalar Foundry: los hosts de descarga de foundry y solc están bloqueados.
npm sí funciona, y desde ahí se instalan:

- `solc` (el compilador en WebAssembly);
- `@nomicfoundation/edr`, el motor de tests Solidity de Hardhat 3, con cheatcodes compatibles con forge.

Con eso se compila y se ejecuta un harness **antes** de pedirle al dueño una corrida en la PC. La referencia
sigue siendo forge en la PC.

Todo corre en la EVM local: FFI apagado, sin RPC, sin forks y sin transacciones reales. Los resultados de
esta verificación no son hallazgos, y si lo fueran serían privados (REGLAS R-4). Nunca se suben al repo.

```bash
cd tools/edr && npm install                      # versiones fijadas en package.json
CLON=~/clones/morpho-org__metamorpho             # un clon con submódulos, p. ej. el de validate.checkout
mkdir -p $CLON/test/nexus && cp ../../local/nexus/secresearch/harness/morpho-org__metamorpho/*.sol $CLON/test/nexus/
node build.js $CLON base.out.json                # Morpho 0.8.19 · MetaMorpho 0.8.21 · harness 0.8.26 (via_ir)
node run_edr.js $CLON base.out.json 2000 256 500 - 0x2a        # fuzz, invariantes runs×depth, filtro, semilla
python3 mutate.py $CLON base.out.json            # cada mutación de mutations.json tiene que romper algo
python3 mutate.py $CLON base.out.json M12 B1     # solo esas; NEXUS_MUT_RUNS="256 64 100" fija la intensidad
```

`mutations.json` tiene entradas `[nombre, original, mutado]` (se muta `src/MetaMorpho.sol`) o
`[nombre, original, mutado, archivo]`. Con un archivo de `lib/morpho-blue/` se recompila Morpho Blue: así se prueba que
el cazador también ve errores en la dependencia. El resumen marca qué mutaciones detecta el cazador (motivos `H-...`).

Con via_ir, `forge` y `build.js` tardan varios minutos en compilar el harness. Para iterar conviene sacar
temporalmente del clon `NexusMetaMorphoERC4626.t.sol`, que es independiente, y volver a ponerlo para la corrida final.

Si una invariante falla, `run_edr.js` imprime la secuencia reducida y la guarda en `seq_<Suite>.json`, para
reproducirla paso a paso. Así se encontró y se corrigió el falso positivo del redondeo de las acciones de
comisión: ver docs/INVESTIGACION_SEGURIDAD.md, etapa D'.

`build.js` está armado para el layout de MetaMorpho (tres versiones de solc: Morpho Blue 0.8.19, MetaMorpho 0.8.21,
harness 0.8.26). Para otro repo hay que cambiar las unidades: qué archivos compila cada versión de solc, según los
pragmas y lo que el test despliega con `deployCode`.

`build_v2.js` es la versión para Morpho Vault V2: una sola unidad con solc 0.8.28, via_ir, optimizer 100000 y evm
cancun (su `foundry.toml`), sobre VaultV2, los mocks y el harness. `run_edr.js` sirve para los dos: aplana los grupos
del `.out.json`.

```bash
node build_v2.js $CLON_V2 v2.out.json                 # ~60 s
node run_edr.js  $CLON_V2 v2.out.json 64 256 500 invariant 0x2a
MUTATION='{"file":"src/VaultV2.sol","old":"...","new":"..."}' node build_v2.js $CLON_V2 v2mut.out.json  # inyecta un defecto
```
