# Traspaso: estado de nexus y cómo continuar

Documento de entrega para retomar el proyecto desde cualquier conversación nueva con Claude. Actualizado el
27-oct-2026. Si algo de acá contradice al código, manda el código; si contradice a [REGLAS.md](REGLAS.md), mandan
las reglas.

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

## 3. Estado por etapa (27-oct-2026)

| Etapa | Estado |
|---|---|
| A. Catálogo y cambios | Funciona. El catálogo real está en la PC; programas elegidos: Morpho (Cantina), Yearn V3 (Immunefi) y Euler v2 (Cantina) |
| B. Triaje | Funciona: puntaje determinista sin IA |
| C. Método de invariantes | Funciona: P0–P6 en Python, con autoverificación |
| D. Validación con Foundry | Funciona en la PC: `validate` clona fijado a un commit, FFI apagado, informe privado |
| D'. Harness de MetaMorpho | Funciona: suite a16z, handler original y `NexusVulnerabilityHunter` con una suite multi-mercado con gobierno |
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
| siguiente | Con la segunda corrida: `setSupplyQueue` con efecto, el selector del error en las fallas de vivacidad, `_mintFits`, el dashboard, el expediente y este documento |

## 5. Próximos pasos

En orden de prioridad:

1. **Dueño:** fusionar el PR pendiente, `git pull` en `main` y correr
   `..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho`.
   En el informe, `colaSuministro` dentro de `gobierno con efecto` tendría que subir. Después abrir el dashboard.
2. **Dueño:** dar de baja la tarea vieja `nexus-latido`, que falla cada 5 minutos porque apunta a un script del
   trading que ya no existe: `Unregister-ScheduledTask -TaskName nexus-latido -Confirm:$false`.
3. **Etapa E para MetaMorpho:** revisar las auditorías que trae el repo de MetaMorpho en `audits/` (la revisión de
   Cantina de 2023-11, la de OpenZeppelin de la periferia de Morpho Blue de 2023-11 y la competencia de Cantina de
   2024-01) contra las leyes y los comportamientos conocidos, para que un candidato futuro no resulte un duplicado.
4. **Siguiente objetivo:** `morpho-org/vault-v2`, que figura en el programa Morpho de la tabla de
   INVESTIGACION_SEGURIDAD.md. El modelo ya está derivado en CAZADOR_METAMORPHO.md ("Límites y próximos pasos").
   **Antes, confirmar con el dueño** que esté en su catálogo con `in_scope` y `verified_by_owner` en `true`: el motor
   no corre nada fuera del catálogo y ningún agente amplía el alcance (R-9). Después vienen Yearn V3, que es Vyper
   0.3.10 y necesita `vyper` en la PC, y Euler v2.
5. **Mejoras del cazador:**
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
- **Si aparece una falla en la PC:**
  1. Reproducirla con la semilla del informe.
  2. Clasificarla. Si es un error del harness, se corrige. Si es un candidato, se aísla en un test mínimo, independiente
     del harness, y se revisa contra las auditorías.
  3. Abrir el expediente con `python -m nexus.secresearch.expediente INFORME` y completarlo con el dueño.
  4. Un falso positivo también lleva expediente, con `estado: descartado` y la razón.
  5. Nada de eso va al repo (R-4).
- **Cuidados con los números:** solo cuenta como ingreso una recompensa cobrada (R-10). Las severidades siguen la
  tabla del programa, sin exagerar (R-7).
