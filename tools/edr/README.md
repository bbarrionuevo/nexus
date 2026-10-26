# Verificación de harness sin forge (solc-js + EDR)

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
```

Si una invariante falla, `run_edr.js` imprime la secuencia reducida y la guarda en `seq_<Suite>.json`, para
reproducirla paso a paso. Así se encontró y se corrigió el falso positivo del redondeo de las acciones de
comisión: ver docs/INVESTIGACION_SEGURIDAD.md, etapa D'.

`build.js` está armado para el layout de MetaMorpho. Para otro repo hay que cambiar las unidades: qué
archivos compila cada versión de solc, según los pragmas y lo que el test despliega con `deployCode`.
