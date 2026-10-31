# Investigación de seguridad DeFi

Pedido del dueño del 26-oct-2026: investigar vulnerabilidades económicas y lógicas en protocolos DeFi
con programa de bug bounty **autorizado**, con pruebas locales y sin poner dinero. Ese mismo día el dueño
suspendió el bot de trading y dedicó el repo entero a esta línea. **No promete ingresos**: solo cuenta
una recompensa cuando se cobra. Las reglas están en [REGLAS.md](REGLAS.md).

## Decisiones de arquitectura

- **Python y git**, que la PC ya tiene, más Foundry y Vyper para la etapa D. Sin Docker, base de datos,
  servicios pagos ni nube nueva.
- **Límites en un archivo protegido** (`limits.py`): topes, verificación del alcance, carpeta de
  resultados y prohibiciones. Solo los cambia el dueño (R-9).
- **Los resultados son privados**: catálogo, clones y resultados en `NEXUS_HOME` (en la PC,
  `%LOCALAPPDATA%\nexus`). El repo es público, y un posible hallazgo publicado sería divulgar una
  vulnerabilidad sin reportar. El orquestador se niega a escribir dentro del repo (R-4).
- Se conserva del proyecto anterior la disciplina de evidencia: reglas fijadas de antemano, medir antes
  de afirmar, "la IA propone, el dueño decide" y rutas protegidas.

## Especialidad del primer prototipo: contabilidad de vaults ERC-4626

| Especialidad | Autocontenida | Se prueba sin estado de mainnet | Barrera de herramientas | Elegida |
|---|---|---|---|---|
| Vaults ERC-4626 (shares/assets, redondeo, precisión) | Sí: pocas funciones | Sí: tests de propiedad | Baja: el método se demuestra en Python | **Sí** |
| Préstamos y liquidaciones | No: oráculos, intereses, incentivos | Parcial: hace falta estado de precios | Alta | No (después) |
| Oráculos | No: depende de fuentes externas | No: hace falta fork | Alta | No |
| Control de acceso | Sí | Sí | Baja | No: muy revisado por auditorías y herramientas estáticas |

Los errores de dirección de redondeo y el ataque del primer depositante son una clase de fallo
recurrente y bien documentada en vaults. Se prueba de forma determinista, que es lo que exige esta línea.

## Pipeline y estado real

| Etapa | Qué hace | Estado | Evidencia |
|---|---|---|---|
| A. Catálogo | Programas autorizados; el pipeline los ignora hasta que el dueño verifica el reglamento | Implementado, **vacío** | `catalog.py`, tests |
| A. Cambios | Commits nuevos que tocan contratos en alcance, por git (clon superficial) o API; libro de vistos; excluye tests, mocks, scripts y specs | Implementado y verificado | Demo sobre OpenZeppelin: 3 commits, 15 archivos, 2.ª corrida sin repetir. Vista previa de los 6 repos de Morpho, Yearn y Euler: el 49% de los archivos eran tests o mocks y daban 11 de 19 alertas "alta"; tras excluirlos, 8 alertas "alta", todas en contratos de producción |
| B. Triaje | Puntaje determinista **sin IA** de las líneas cambiadas, con señales ERC-4626 | Implementado y verificado | En la demo puso primero el único cambio de vault (ERC7535, puntaje 31) entre 15 archivos |
| C. Método de invariantes | Modelo de referencia ERC-4626 con aritmética entera y propiedades P0–P6 | Implementado y verificado | Autoverificación: pasa la correcta y atrapa los 5 defectos de referencia |
| D. Validación local con Foundry | `validate.py`: solo repos de programas verificados; clona fijado a un commit con submódulos; `forge build` + `forge test --json` con FFI apagado forzado y topes de tiempo; informe privado e historial | Implementado y verificado en la PC (26-oct) | Línea base de MetaMorpho `ded84e5`: compila en 350,7 s; 148 pasan · 0 fallan · 0 omitidos (354,2 s) |
| D'. Propiedades del vault en Foundry | `harness/morpho-org__metamorpho/`: la suite ERC-4626 de a16z y un test de invariantes con handler, en 3 variantes; `validate --harness` los copia al clon y los corre con una semilla nueva. Desde el 27-oct, con el cazador (`NexusVulnerabilityHunter.sol`) y una suite multi-mercado con gobierno | Implementado. Verificado en la nube **sin forge** (solc-js + EDR, el motor de tests de Hardhat 3) y en la PC con forge (26-oct: 84 pasan, 0 fallan) | 81/81 pasan en `ded84e5` con 4 semillas; detecta 7 de 7 mutaciones de referencia (abajo). Con el cazador: sin falsos positivos en 1,5 M de llamadas; detecta 21 de 21 mutaciones, también en Morpho Blue, contra 11 de 21 del harness original ([detalle](CAZADOR_METAMORPHO.md#verificación)) |
| Ciclo desatendido | `cycle.py`: una vez por disparo del Programador de tareas, con candado y tope de tiempo. Hace A–C, los harness con semilla nueva y hasta 2 líneas base vencidas, y escribe `ciclo.md` y `para_claude.md`. Este último trae las fallas y, desde el 27-oct, la cobertura de la última corrida: llamadas y reversiones por acción del handler, que forge reporta, y el log de `afterInvariant` (verificaciones y métricas del cazador; por eso `validate` corre forge con `-vv`) | Implementado; lo registra el dueño con `tools/windows/registrar_ciclo.ps1` | Tests con reloj y validador simulados |
| E. Duplicados y alcance | Auditorías previas, problemas conocidos, exclusiones | Parcial: el catálogo guarda exclusiones; la búsqueda de auditorías está pendiente | — |
| F. Expediente | Informe por candidato confirmado: `python -m nexus.secresearch.expediente INFORME` arma el borrador privado en `NEXUS_HOME/secresearch/expedientes/` con el programa y sus reglas, el commit, la semilla, la ley que falló, el contraejemplo y el comando para reproducir, más las secciones del punto 5 de "Qué falta para un primer informe válido". También sirve para descartar una falla con su razón (`estado: descartado`) | Implementado (27-oct); lo completa, firma y envía el dueño | Tests: arma todas las secciones, no pisa uno existente y no escribe en el repo |
| Dashboard | `python -m nexus.secresearch.dashboard`: una página local (`NEXUS_HOME/secresearch/dashboard.html`), sin nada de internet, con las fallas para revisar, la cobertura por acción, las métricas del cazador, las corridas, los programas, los cambios pendientes, los ciclos y los expedientes. La regeneran el ciclo y `validate` | Implementado (27-oct) | Tests: escapa el texto de los informes y no carga recursos externos |

Propiedades del método (etapa C):

- **P0.** Ninguna operación revienta.
- **P1.** Depositar y rescatar no devuelve más de lo depositado.
- **P2.** Acuñar y rescatar no devuelve más de lo pagado.
- **P3.** Retirar no deja más valor que el que había.
- **P4.** Solvencia.
- **P5.** El ataque del primer depositante no deja ganancia.
- **P6.** Ninguna operación baja el valor de los demás.

La primera versión no detectaba "mint hacia abajo" ni "rescate hacia arriba". Esos defectos solo se
explotan después de una pérdida del vault (precio de la share < 1) y roban a los demás sin crear valor.
Se agregaron las pérdidas al modelo y la propiedad P6. Es exactamente el tipo de falso negativo que
el método tiene que ir cerrando.

## Etapa D': propiedades e invariantes de MetaMorpho

Dos archivos de tests que `validate --harness morpho-org__metamorpho` copia a `test/nexus/` del clon, sobre
un entorno propio: Morpho Blue, un mercado con préstamos (LLTV 80 %), un mercado idle y el vault. Se corren
en tres variantes:

- sin comisión;
- con comisión del 25 %;
- con un activo de 6 decimales, es decir `DECIMALS_OFFSET` = 12.

1. **Propiedades de a16z** (`NexusMetaMorphoERC4626.t.sol`): las 26 de la suite `erc4626-tests`, que ya trae
   el repo, con `_delta_ = 0`. La suite original simula el rendimiento acuñando tokens en el contrato del
   vault, y eso en MetaMorpho no mueve `totalAssets`. Por eso la ganancia y la pérdida se hacen como pasarían
   de verdad:
   - ganancia: depósito en Morpho a nombre del vault, más interés pendiente (préstamo y paso del tiempo);
   - pérdida: deuda incobrable (el oráculo cae a 0 y se liquida sin repagar).
2. **Invariantes con handler** (`NexusMetaMorphoInvariant.t.sol`). Forge encadena depósitos, acuñaciones,
   retiros, rescates, transferencias, donaciones, préstamos, repagos, paso del tiempo, deuda incobrable y
   reasignaciones del allocator. Después de cada llamada verifica:
   - que `max*` no prometa de más: depositar, acuñar, retirar o rescatar el máximo no revierte;
   - que `preview*` no mienta a favor del usuario;
   - que el precio por acción no baje sin una pérdida;
   - que `convertToAssets` no valga menos que el precio de la especificación;
   - solvencia, suma de saldos y que el vault no retenga tokens.

**Cómo se verificó sin forge.** Foundry no se puede instalar en la nube de Claude, porque los hosts están
bloqueados. Sí se puede instalar EDR desde npm: es el motor de tests Solidity de Hardhat 3 y usa los mismos
cheatcodes. `tools/edr/` compila como forge (Morpho con 0.8.19, MetaMorpho con 0.8.21 y el harness con
0.8.26, via_ir) y ejecuta. Resultados:

- 81/81 pasan con 4 semillas, con 2.000 corridas de fuzz y 256×500 llamadas por invariante;
- las invariantes terminan con menos del 0,4 % de reversiones, o sea que no pasan en vacío.

Las mutaciones de referencia, cada una inyectada en una copia de MetaMorpho, tienen que romper algo:

| Mutación | La detecta |
|---|---|
| M1 `deposit` redondea acciones hacia arriba | a16z (`RT_deposit_redeem`) e invariantes (precio) |
| M2 `maxWithdraw` ignora la liquidez | solo invariantes (retirar el máximo revierte) |
| M3 `deposit` no actualiza `lastTotalAssets` (comisión sobre depósitos) | invariantes, variante con comisión |
| M4 `mint` redondea el costo hacia abajo | a16z (`RT_mint_withdraw`) |
| M5 `totalAssets` ignora el mercado idle | invariantes (precio tras reasignar) |
| M6 `redeem` redondea activos hacia arriba | a16z (`RT_redeem_deposit`, `RT_redeem_mint`) |
| M7 comisión calculada de más | invariantes (`convertToAssets` por debajo del precio exacto) |

**Lecciones:**

- **Falso positivo propio, corregido.** La primera versión medía el precio con `convertToAssets` y fallaba
  en la variante con comisión. Las acciones de comisión pendientes se redondean hacia abajo. Cuando ese
  redondeo salta una acción entera, el precio "devuelve" valor al receptor de comisiones. Con pocas acciones
  en circulación eso parecía una caída de hasta 1,5 %. No era un defecto de MetaMorpho. Se reprodujo la
  secuencia de 179 llamadas paso a paso, y ahora se mide el precio de la especificación:
  (totalAssets − comisión × interés pendiente + 1) / (totalSupply + acciones virtuales).
- **Versión de solc.** Con via_ir, la suite de a16z da "stack too deep" en solc ≤ 0.8.24. Por eso el
  adaptador exige `^0.8.26`, y forge baja ese compilador solo para ese archivo.

### Cazador de vulnerabilidades: contabilidad fantasma y leyes exactas (27-oct)

`NexusVulnerabilityHunter.sol` se hereda en el handler (la API no cambia). Cada acción queda envuelta en
`hunted(...)`, que toma una foto antes y otra después y evalúa las leyes de esa operación contra un modelo
independiente de los `view` del vault: estado crudo de Morpho en un solo `extSloads`, aritmética propia, L, colas,
topes y timelocks fantasma, y libros por tenedor y de comisiones. Caza tres familias:

- inflación y redondeo;
- desincronización de comisiones;
- fugas por deuda incobrable o reasignación entre mercados.

`NexusMetaMorphoHunter.t.sol` agrega el entorno que faltaba:

- 4 mercados (uno sin habilitar) con topes que se alcanzan y colas en distinto orden;
- gobierno con timelock, comparado contra la predicción del cazador;
- saltos a la frontera exacta de cada timelock;
- macros de ataque: inflación, comisión relámpago, ciclo de reasignaciones, tokens sueltos y fronteras de tope y de
  remoción.

Modelo, ecuaciones, leyes, auditoría del handler anterior e integración: [CAZADOR_METAMORPHO.md](CAZADOR_METAMORPHO.md).

**Qué NO cubre todavía:**

- tokens no estándar (con comisión por transferencia o con callbacks);
- reentrada;
- `permit` y `multicall`;
- préstamos flash;
- una tasa de interés que cambie con el uso;
- el harness de Vault V2 (las ecuaciones de la adaptación están en CAZADOR_METAMORPHO.md).

Son los próximos frentes, en ese orden de valor.

### Cómo escribir un cazador nuevo (lecciones hasta el 31-oct)

- **Leyes universales primero, modelo después.** En los Bundles alcanzó con leyes que no necesitan modelo del núcleo:
  el contrato intermediario no se queda con saldo, lo que paga una parte es lo que cobra la otra más las comisiones
  documentadas, nadie ajeno cambia, las garantías documentadas se cumplen, y la llamada revierte si y solo si una
  validación lo exige (BU-LIVE en las dos direcciones). El núcleo lo cubre su propio cazador.
- **Medir del otro lado.** Lo "llenado" se mide como lo que entró a las contrapartes y al protocolo, no como lo que
  dice el contrato bajo prueba.
- **Decisiones por hash, montos mezclados.** Con semillas chicas, que el fuzzer da a menudo, los bits altos son cero
  y una decisión por bits cae siempre en la misma rama: las decisiones salen de un hash de la semilla. Forge saca del
  diccionario el 80 % de los valores de una campaña de invariantes (`dictionary_weight = 80`), así que los montos
  crudos quedan chicos: 1 de cada 4 crudo (para apuntar a valores exactos) y el resto uniforme en el rango.
- **Una reversión que no rompe una validación no es violación,** pero la proporción importa: si la mitad de las
  llamadas revierte por lo mismo, el cazador gasta la campaña. Se cuentan por motivo (selector) en las métricas.
- **Solidity: `P memory q = p` copia la referencia.** Cambiar un campo de la copia cambia el original (falso
  positivo de BlueBundlesV1 del 30-oct). Pasar los parámetros sueltos.
- **Todo cálculo de la ley con signo.** Una resta que desborda dentro del handler lo hace revertir, y la reversión
  borra la violación que se acababa de registrar: los deltas van en `int256` y las leyes con división se saltean si
  ya se registró que la llamada no tenía que pasar.
- **El precio por acción no puede quedar redondo.** Con el precio clavado en un número redondo, cada conversión entre
  acciones y activos es exacta y ningún redondeo se ejercita: confundir acciones con activos, o redondear al revés,
  pasa inadvertido. Pasa solo con los valores por defecto: un Vault V2 con `maxRate` en 0 no reconoce interés ni
  donaciones (precio 1), y un mercado de Blue sin IRM deja la relación en 1e6 acciones por activo. El cazador tiene
  que mover el precio (interés, donaciones, comisiones, pérdidas) y loguear el precio final para mostrar que se movió.
- **Los parámetros de gobierno, variables.** Con una penalidad o una comisión fijas en el `setUp`, un contrato que
  use una constante en vez de leer la vigente pasa la batería. Una acción del handler las cambia entre llamadas.
- **Los controles de precio, en su borde exacto y en las dos direcciones.** Con el precio exacto que realiza la
  llamada tiene que pasar, y con uno peor, revertir. Si el precio no se puede predecir de las vistas, sale de una
  corrida en seco: una llamada externa del handler a sí mismo que ejecuta la operación, mide y revierte con el
  resultado (lo transitorio de EIP-1153 también se revierte).
- **Verificación antes de campaña:** línea base sin mutar con dos semillas, sin falsos positivos ni reversiones del
  handler, y una batería de mutaciones que pruebe que cada ley ve lo suyo. Después, la campaña profunda.

## Límites de seguridad

Ver [REGLAS.md](REGLAS.md) (R-1 a R-10). Se hacen cumplir con `limits.py` y `tests/test_limits.py`
(protegidos).

## Uso de IA y costo

Hoy la línea hace **cero llamadas a modelos**: las etapas A–C son deterministas. El escalonado previsto es:

1. Filtros baratos.
2. Triaje del diff.
3. Tests e invariantes.
4. Claude solo para hipótesis sobre cambios de prioridad "alta" (pendiente, con tope de llamadas por día).
5. Revisión profunda solo con evidencia reproducible.

Cada hipótesis va a quedar registrada con los comandos y tests que la confirmaron o descartaron.

## Cómo correrlo en la PC

En PowerShell, desde `%USERPROFILE%\nexus\local`:

```powershell
# Verificación local completa (sintaxis, lint si hay ruff, tests, rutas protegidas, método):
..\.venv\Scripts\python -m nexus.devcheck

# Autoverificación del método de invariantes:
..\.venv\Scripts\python -m nexus.secresearch.run --selfcheck

# Corrida real: usa %LOCALAPPDATA%\nexus\secresearch.yaml (programas verificados por el dueño):
..\.venv\Scripts\python -m nexus.secresearch.run
```

El informe queda en `%LOCALAPPDATA%\nexus\secresearch\secresearch.md`.

Validación local con Foundry (etapa D), solo sobre repos de programas verificados:

```powershell
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --match-path test/ERC4626Test.sol
```

El informe queda en `%LOCALAPPDATA%\nexus\secresearch\validate\` y los clones en `%LOCALAPPDATA%\nexus\work\`.
La primera corrida de cada repo es su **línea base**: un test que falla ahí no es una vulnerabilidad.

Propiedades e invariantes de nexus (etapa D'). Cada corrida usa una semilla nueva, que queda en el informe
junto con el comando para reproducirla:

```powershell
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho
# más intensidad (por defecto: fuzz 1000, invariantes 256x500), o repetir una corrida exacta:
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho --fuzz-runs 5000 --invariant-depth 1000
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho --ref <commit> --seed <semilla>
```

Ciclo desatendido: corre todo lo anterior una vez por día, sin ventana y con topes. Se registra una sola
vez, desde `%USERPROFILE%\nexus`:

```powershell
powershell -ExecutionPolicy Bypass -File tools\windows\registrar_ciclo.ps1      # todos los días a las 03:17
Start-ScheduledTask nexus-ciclo                                                  # probarlo ahora
```

Los resultados quedan en `%LOCALAPPDATA%\nexus\secresearch\`:

- `ciclo.md`: el último ciclo;
- `para_claude.md`: líneas base, corridas y fallas distintas acumuladas, para pegarle a Claude;
- `ciclo.log`: el progreso.

Para quitarlo: `Unregister-ScheduledTask nexus-ciclo -Confirm:$false`.

### Iteración en la PC

Desde el 30-oct Claude trabaja solo en la PC (R-12), con Claude Code en la carpeta de nexus: lee los informes
directo, corre forge y lanza las campañas. Los resultados nunca van al repo, que es público (R-4). El ciclo de
mejora es:

1. **Partir de `main`.** Desde `%USERPROFILE%\nexus`: `git pull` en `main`. Para probar una rama sin fusionar,
   `git checkout <rama>`.
2. **Correr.**
   ```powershell
   ..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho
   ```
   Para iterar rápido, `tools/forge_v2` y el panel. Lo largo, en campañas del panel o en el ciclo programado.
3. **Leer `%LOCALAPPDATA%\nexus\secresearch\para_claude.md`** (y el log de cada campaña), que traen:
   - las fallas distintas, con su ley (`H-...`), el contraejemplo y la semilla;
   - la cobertura de la última corrida: llamadas y reversiones por cada acción y macro del handler (métricas de
     forge) y el log de `afterInvariant`: el contador de verificaciones (que la corrida no pasó en vacío) y las
     métricas del cazador. `validate` corre forge con `-vv` porque, sin eso, forge borra los logs del JSON.
4. **Qué hace Claude con eso.**
   - Una falla con código de ley se reproduce con la misma semilla y se clasifica: error del harness (se corrige) o
     candidato (se aísla en un test mínimo y se revisa contra auditorías previas, etapas E y F).
   - Una reversión del handler también se investiga, aunque el invariante pase: es una secuencia que quedó sin
     verificar. Se reproduce con `fail_on_revert` y varias semillas (con una sola puede no aparecer) y se repite la
     secuencia guardada con `-vvvv` (30-oct: así salieron los bordes de dominio de Midnight, el Vault V3 y
     TokenizedStrategy).
   - Sin fallas, las métricas dicen hacia dónde empujar: por ejemplo, si una macro casi nunca corrió o revierte
     siempre, si las reversiones pasan del 5 % o si nunca hubo depósitos con 0 acciones.
5. **Ver el estado sin pegar nada:** `python -m nexus.secresearch.dashboard` abre la página local con lo mismo que
   `para_claude.md`, más los programas, los cambios pendientes y los expedientes. Se regenera sola al terminar cada
   ciclo y cada `validate`.
6. **Si una falla se confirma como candidato:** `python -m nexus.secresearch.expediente INFORME` arma el expediente con
   todo lo que el motor ya sabe. Claude ayuda a completar la causa raíz, la prueba de concepto independiente del
   harness, el impacto y la revisión de auditorías previas; el dueño lo revisa y lo envía por la plataforma oficial.

## Métricas (lo único que cuenta)

- Programas activos que cumplen los criterios.
- Cambios relevantes encontrados por semana.
- Hipótesis generadas, descartadas y reproducibles (en %).
- Falsos positivos identificados.
- Tiempo y costo por candidato.
- Tests ejecutados y aprobados.
- Informes con evidencia suficiente.
- **Recompensas cobradas.** Una recompensa estimada no es un ingreso.

## Programas elegidos por el dueño (26-oct-2026): Morpho, Yearn V3 y Euler v2

| Programa | Plataforma | Repos (código de vaults ERC-4626) | Aviso |
|---|---|---|---|
| Morpho | Cantina | `morpho-org/metamorpho`, `morpho-org/vault-v2` | Prohíbe probar en cadenas públicas; recomienda forks locales |
| Yearn V3 | Immunefi | `yearn/yearn-vaults-v3` (Vyper 0.3.10), `yearn/tokenized-strategy` | Su `foundry.toml` tiene `ffi = true`: correr siempre con `FOUNDRY_FFI=false` |
| Euler v2 | Cantina | `euler-xyz/euler-vault-kit`, `euler-xyz/euler-earn` | El alcance son las direcciones desplegadas, no el repo entero |

El dueño leyó los reglamentos y marcó los 3 programas (`in_scope` y `verified_by_owner` en `true`) en su
catálogo privado, el 26-oct.

**Seguridad de la PC:** compilar y testear código de terceros es ejecutar código ajeno. FFI de Foundry
siempre apagado (`FOUNDRY_FFI=false`), y nunca correr scripts de despliegue (`forge script`) de esos repos.

## Selección de objetivos por valor esperado (R-13, desde el 30-oct)

Los tres programas del catálogo (Morpho, Yearn V3 y Euler v2) los habilitó el dueño. Dentro de ellos, el objetivo
siguiente se elige por valor esperado: la recompensa del programa para ese código por la probabilidad de un
hallazgo válido. Pesan:

- **La recompensa del grupo o componente:** los programas pagan distinto según el código (Morpho por grupo, Euler
  por componente).
- **Que sea la última versión desplegada y en alcance:** la página de direcciones del programa es la fuente de
  verdad, y el commit desplegado se compara con el del repo.
- **La probabilidad:** código nuevo o con poca auditoría, contabilidad compleja, interacciones (callbacks, adapters,
  vaults sobre vaults) y pocos duplicados posibles (auditorías, concursos y riesgos documentados).
- **El costo:** si nexus ya tiene un cazador parecido, el objetivo cuesta menos.

La tabla viva está en el traspaso (sección 5). Dentro de un programa habilitado, Claude puede sumar al catálogo un repo
en alcance (R-1). Un programa nuevo lo habilita el dueño, después de leer el reglamento vigente: alcance,
exclusiones, requisitos de PoC, KYC, plazos y si permite fork local.

## Plan de 30 días, con puntos de decisión

- **Semana 1.** El dueño verifica hasta 3 programas. Corrida diaria manual y medición de cambios relevantes por semana.
  - **Decisión día 7:** con menos de 2 cambios relevantes por semana entre los 3, se cambia de programas.
- **Semana 2.** Decisión sobre Foundry. Si se aprueba: plantilla de tests de invariantes con P0–P6 y
  ejecución local contra el vault en alcance de un programa.
  - **Decisión día 14:** sin Foundry, la línea se queda en triaje (valor limitado) y se evalúa abandonarla.
- **Semana 3.** Hipótesis con Claude, con tope diario, solo sobre cambios "alta". Cada hipótesis se
  registra y se intenta reproducir con un test.
- **Día 30.** Con 0 hipótesis reproducibles en 20 o más investigadas, se cambia de especialidad o se abandona.

## Qué falta para un primer informe válido

1. Un programa activo, verificado por el dueño, con un vault en alcance.
2. ~~Foundry en la PC~~ (hecho el 26-oct: línea base de MetaMorpho en verde). Propiedades e invariantes
   contra el código real (etapa D'): listas para MetaMorpho; faltan Morpho Vault V2, Yearn V3 y Euler v2.
3. Un test local que falle en el código en alcance y muestre un efecto económico concreto.
4. La comprobación contra auditorías previas, problemas conocidos y exclusiones.
5. El expediente: programa y versión, archivo y línea, causa raíz, precondiciones, test reproducible,
   esperado contra observado, impacto, límites, evidencia, severidad prudente y requisitos de envío.

Lo envía y lo firma el dueño.
