# Cazador de Morpho Midnight

Estado: **variantes A y B escritas y verificadas con forge en la PC** (29 y 30-oct). Con el harness final pasan las
seis suites, cuatro de la A y dos de la B, sin falsos positivos ni reversiones: 32×300 con las semillas `0x2a` y
`0x3`, y `validate` sobre el repo entero a 64×300. Las 47 mutaciones de referencia se detectan. La campaña profunda
de la A (1536×500) pasó sin leyes rotas; las reversiones que tuvo con 6 decimales eran del cazador y están arregladas
(sección 6). **No hay hallazgos.**

## 1. Qué versión y qué alcance

- **Programa:** Morpho en Cantina (en el catálogo).
  - El dueño delegó la lectura del reglamento y autorizó el 29-oct-2026.
  - El reglamento pone los contratos de Midnight en el grupo "Morpho Midnight and Vault V2" y declara que la página
    de direcciones de Morpho es la fuente de verdad del alcance.
  - Esa página lista el núcleo `Midnight` en Ethereum (`0x4716…045f`) y su periferia: ratifiers, autorizador,
    `Mempool`, la fábrica de `BlueBuyCallback`, `BlueFallbackRolling` y la fábrica de `WhitelistEnterGate`.
- **Versión probada: la etiqueta `2026-08-24` (`14e0b77843`).**
  - El núcleo desplegado tiene coincidencia completa en Sourcify (solc 0.8.34, `osaka`, via_ir, 466 runs).
  - Sus 13 archivos son idénticos, por hash de blob de git, a los de las etiquetas `2026-07-02` a `2026-08-24`. Es el
    commit que auditaron Blackthorn, Spearbit y TrustSec el 2-jul.
  - En `main` el núcleo solo cambió formato y comentarios.
- **Qué no es nuevo:** el repo trae 15 auditorías y una verificación formal amplia con Certora (`certora/README.md`)
  y Rocq. Lo que Certora demuestra queda como contexto: unidades totales, solvencia, factor de pérdida monótono,
  salud y liquidaciones. Sus supuestos dejan lugar a un modelo concreto:
  - `mulDiv` como axiomas;
  - bucles acotados;
  - `multicall` quitado;
  - sin reentrada salvo en las reglas de callbacks.

## 2. Modelo

Midnight presta a tasa fija con unidades que son bonos cupón cero.

- **`take`:**
  - crea o cancela crédito y deuda entre comprador y vendedor al precio del tick de la oferta;
  - cobra la comisión de liquidación como la diferencia entre lo que paga el comprador y lo que recibe el vendedor;
  - redondea los activos a favor del maker.
- **Deuda y retiros:**
  - `repay` y `liquidate` llevan la deuda a `withdrawable`;
  - los prestamistas retiran crédito 1:1 desde ahí.
- **Deuda incobrable:**
  - se realiza en `liquidate` cuando el colateral, valuado con `maxLif`, no cubre la deuda;
  - sube el factor de pérdida y escala `continuousFeeCredit`;
  - el crédito de cada prestamista se recorta de forma perezosa en su próxima interacción.
- **Comisión continua:** se fija al comprar crédito (`pendingFee`) y se devenga linealmente hasta el vencimiento hacia
  `continuousFeeCredit`.

El fantasma replica cada fórmula de la etiqueta con su redondeo:
- `updatePositionView`;
- `take`;
- `withdraw` y `repay`;
- depósito y retiro de colateral;
- `liquidate`, con deuda incobrable, factor de pérdida, LIF post-vencimiento, embargo y repago, y la condición RCF;
- `isHealthy`;
- `settlementFee` interpolada;
- los cobros de comisiones.

Precio del tick: usa `TickLib.tickToPrice`, que Certora demuestra. `maxLif` y los máximos de comisión están escritos
de nuevo.

## 3. Leyes (exactas, contra los getters)

| Ley | Qué exige |
|---|---|
| MN-POS | crédito, comisión pendiente, último factor de pérdida, último devengo, deuda, bitmap y colateral de cada posición, y `consumed` de cada grupo, exactos |
| MN-MKT | `totalUnits`, `lossFactor`, `withdrawable`, `continuousFeeCredit`, comisiones, spacing y comisión reclamable exactos; lo que devuelven `take` y `liquidate` |
| MN-UNITS | `totalUnits = Σ deuda + withdrawable`; ninguna posición con crédito y deuda; comisión pendiente ≤ crédito |
| MN-CLAIM | `Σ crédito al día + continuousFeeCredit ≤ totalUnits`: los reclamos nunca superan el respaldo |
| MN-FUNDS | saldos de Midnight, de los actores, del liquidador y del receptor de comisiones exactos; el activo en Midnight es `withdrawable +` comisión reclamable y el colateral es la suma de las posiciones |
| MN-VIEW | `updatePositionView`, `isHealthy` y `settlementFee` iguales al modelo |
| MN-FAIR | tras una deuda incobrable, el crédito al día de cada prestamista baja en la proporción del factor, salvo una unidad |
| MN-LIVE | cada operación pasa si y solo si el modelo dice que pasa |

**MN-CLAIM vale con números exactos.** Sea `S = Σ c_i·(M−LF)/(M−l_i) + CFC`, con los créditos guardados `c_i` sin
redondear. Entonces `S ≤ T` se conserva en cada operación:
- `take`, `withdraw` y `claimContinuousFee` mueven `S` y `T` lo mismo.
- El devengo pasa de un crédito a `CFC` sin cambiar `S`.
- La deuda incobrable multiplica `S` por `(M−LF')/(M−LF) ≤ (T−b)/T`, porque `LF'` se redondea hacia arriba.

El crédito al día que devuelve la vista es el piso de cada término, así que la suma real queda por debajo de `S`.

## 4. Harness (variante A)

`local/nexus/secresearch/harness/morpho-org__midnight/`:

- **`NexusMidnightHunter.sol`:**
  - token, oráculo con precio ajustable, ratifier que ratifica todo y reloj;
  - el núcleo desplegado con `new Midnight()` y sus roles;
  - un mercado de dos colaterales con vencimiento a 30 días;
  - el modelo y las leyes.
- **`NexusMidnightInvariant.t.sol`:** el handler y cuatro variantes:
  - comisiones al 50 % del máximo;
  - comisiones al máximo;
  - activo prestado de 6 decimales;
  - LLTV = 1 en el segundo colateral, sin comisión continua.
- **Acciones:**
  - depositar y retirar colateral;
  - `take` de ofertas de compra y de venta con tope por unidades o por activos, a veces `reduceOnly` o con tope de
    comisión continua;
  - cancelar un grupo;
  - repagar, retirar y `updatePosition`;
  - liquidar, en modo normal o post-vencimiento, por embargo, por repago o solo para realizar deuda incobrable;
  - mover precios;
  - saltar el reloj, también más allá del vencimiento;
  - fijar comisiones y spacing, y cobrar comisiones.
- **Secuencias:** préstamo completo, deuda incobrable y vencimiento con repagos, liquidaciones y retiros de todos.

Para iterar: `NEXUS_PERFIL=midnight` en [tools/forge_v2](../tools/forge_v2/README.md). El perfil arma un proyecto
reducido con el núcleo, sus librerías e interfaces y forge-std, y deja afuera la periferia. Exige el clon en
`14e0b77`. La referencia es `validate` sobre el repo entero con `"aislado": true`.

**Verificación de la variante A sola (29-oct, forge 1.8.6 en la PC).** La del harness final, con las dos variantes,
está en la sección 6.

- **Proyecto reducido:** las 4 variantes pasaron 32×300 sin falsos positivos y con 0 reversiones, con las semillas
  `0x2a` y `0x3`.
- **Referencia:** `validate` sobre el repo entero (etiqueta `2026-08-24`, compilación aislada, 64×300, semilla
  `0xf447dc803a8a69c4`) dio 4 de 4 con 0 reversiones: 101 s de compilación y 286 s de tests. La primera compilación
  de `src` entero, con la periferia, llevó unos 40 minutos con la PC cargada; después forge usa su caché.
- **Lo que se corrigió en el camino (ninguna fue una falla de Midnight):**
  - El modelo de la liquidación escribía el repago calculado en la estructura de entrada, y el handler mandaba
    embargo y repago a la vez.
  - La cota de MN-FAIR era de una unidad. El crédito al día acumula tres pisos (recorte, comisión pendiente y
    devengo), así que la cota correcta es `|c1·a − c0·b| < 3a`.
  - Una corrida que cruzaba el vencimiento en sus primeras llamadas no prestaba nada. Ahora el vencimiento no se
    cruza antes de 50 operaciones.

## 5. Variante B: callbacks, multicall, préstamo flash y gates

`NexusMidnightCallbacks.t.sol` hereda todas las acciones de la variante A y suma:

- **El contrato de callbacks del cazador:** en cada gancho ejecuta una lista de operaciones anidadas sobre Midnight,
  con `msg.sender` = el callback, que todos los actores autorizan. Si una revierte, queda registrada y la lista sigue.
  - Las operaciones son colateral (depositar y retirar), repago, retiro, `updatePosition`, la liquidación de
    cualquier posición y un `take` anidado sin callbacks.
  - También es el pagador cuando es el callback del comprador, del repago o de la liquidación.
  - Una de cada dieciséis veces devuelve otra respuesta, para probar que el núcleo la rechaza.
- **Acciones:**
  - `take` con el callback del comprador, del vendedor o de los dos (el receptor de lo del vendedor puede ser el
    callback);
  - `repay` y `liquidate` con callback;
  - préstamo flash del activo prestado o de un colateral;
  - `multicall` de dos operaciones propias de un actor;
  - en la variante con gates, los interruptores del gate de entrada (crédito y deuda) y del de liquidadores.
- **La secuencia del bloqueo:** el vendedor toma deuda sin colateral nuevo. En `onBuy` alguien intenta realizarle la
  deuda incobrable, y el bloqueo de liquidación lo tiene que impedir. En `onSell` el callback le pone el colateral que
  lo deja sano. Sin el bloqueo, esa liquidación pasaría.
- **El modelo, en fases y en el orden del núcleo:**
  - en `take`: efectos, `onBuy`, pagos, `onSell` y salud final. Mientras corren los callbacks, el vendedor está
    bloqueado: una liquidación suya revierte, y un `take` anidado con el mismo vendedor no controla su salud ni lo
    desbloquea;
  - en `repay`: efectos, `onRepay` y cobro;
  - en `liquidate`: efectos y embargo, `onLiquidate` y cobro;
  - en el préstamo flash: préstamo, `onFlashLoan` y cobro;
  - en `multicall`: todo o nada.

  Cada operación anidada se predice sobre el estado intermedio. Lo que registró el callback tiene que coincidir con
  la predicción, y eso entra en MN-LIVE. Las demás leyes valen igual al terminar cada operación.
- **Los saldos:** el modelo lleva los de siete tenedores (los cuatro actores, el callback, el liquidador y el receptor
  de comisiones). En la variante A el resultado es el mismo que antes.

## 6. Verificación del harness final (30-oct, forge 1.8.6 en la PC)

**La campaña profunda de la A y el arreglo de `liqCycle`.** La campaña del 29-oct (panel, 1536×500, 768.000
llamadas por variante, semilla `0xd965aa70462df72e`) pasó en las cuatro variantes sin ninguna ley rota. La de 6
decimales tuvo 14 reversiones del handler, todas en `liqCycle`, así que esas secuencias quedaron sin verificar. Eran
del cazador, no de Midnight:
- los desplomes de `badDebtCycle` llevan el precio de un colateral hasta 1, sin piso;
- `liqCycle` lo baja de 3 a 15 %, y 1 pasa a 0;
- el siguiente `liqCycle` sobre ese colateral dividía por cero al calcular el colateral necesario.

Con 6 decimales el precio inicial es 1e24 en vez de 1e36, y por eso llegaba antes. Ahora `liqCycle` calcula el
colateral con la misma función que las demás acciones, que con el precio en 0 no pone nada. La prueba
`test_liqCycleConPrecioCero` repite el caso en las cuatro variantes: con el harness viejo revierte por la división, y
con el arreglado pasa con las leyes en verde. Con `fail_on_revert`, la variante de 6 decimales pasó además seis
corridas de 128×500 con semillas distintas (384.000 llamadas) sin reversiones ni leyes rotas. Los números de abajo
son del harness arreglado.

- **Proyecto reducido:** las seis suites pasan 32×300 sin falsos positivos y con 0 reversiones, con las semillas
  `0x2a` y `0x3` (9.600 llamadas por suite y semilla). `test_liqCycleConPrecioCero` pasa en las cuatro variantes de
  la A: 10 de 10 pruebas con cada semilla.
- **Referencia:** `validate` sobre el repo entero (etiqueta `2026-08-24`, compilación aislada, 64×300, semilla
  `0x7dea4e2c53b47e39`) da 10 de 10 (las seis suites y las cuatro pruebas de regresión) con 0 reversiones en las
  115.200 llamadas: 82 s de compilación y 294 s de tests.
- **Cobertura de la B en la última corrida de cada suite, con las dos semillas:**
  - de 29.900 a 33.000 leyes evaluadas;
  - de 3 a 25 `take`, de 2 a 5 realizaciones de deuda incobrable y de 3 a 5 liquidaciones con embargo o repago. La
    suite con gates hace menos `take` (3 y 11), porque los gates cerrados rechazan muchos;
  - de 6 a 11 operaciones con callback;
  - de 12 a 23 operaciones anidadas, de las que pasaron de 7 a 13;
  - de 1 a 3 intentos de liquidar al vendedor bloqueado desde un callback, todos rechazados como predice el modelo;
  - de 7 a 10 préstamos flash y de 7 a 14 `multicall`.

  En `validate`, la última corrida de cada suite de la B llegó a 33 y 18 operaciones anidadas y a 6 y 1 intentos
  sobre el vendedor bloqueado.
- **Cobertura de la A en la última corrida de cada variante, con las dos semillas:**
  - de 34.800 a 36.900 leyes evaluadas;
  - de 8 a 39 `take`: de 2 a 22 en que el vendedor vendió crédito y de 1 a 14 en que el comprador canceló deuda;
  - de 2 a 10 realizaciones de deuda incobrable;
  - de 2 a 12 liquidaciones con embargo o repago, y de 1 a 7 en modo post-vencimiento;
  - de 2 a 11 retiros;
  - de 110 a 166 rechazos predichos por el modelo.

  La semilla pesa: con `0x2a` cada variante hace de 30 a 39 `take`, y con `0x3`, de 8 a 9 y más rechazos. Con las
  mismas semillas, los números no son los del 29-oct: el fuzzer arma valores también con el código y el estado
  desplegados, y los dos cambiaron con la B y con el arreglo.
- **Lo que el cazador recorre poco:**
  - las liquidaciones post-vencimiento (de 1 a 7 por corrida);
  - las llamadas sueltas a `updatePosition` que devengan comisión (0 o 1) o recortan crédito (de 0 a 4). Los devengos
    y los recortes que ocurren dentro de `take` y `withdraw` no se cuentan aparte;
  - los intentos sobre el vendedor bloqueado (de 1 a 3 por corrida a 32×300). Las mutaciones B1 y B10 muestran que el
    cazador llega al caso en que solo el bloqueo frena la liquidación.

## 7. Mutaciones de referencia

[tools/forge_v2/mutaciones_midnight.json](../tools/forge_v2/mutaciones_midnight.json), sobre el harness final con
`NEXUS_PERFIL=midnight` (32×200, semilla `0x2a`): **las 47 se detectan.**

- **M1 a M37, el núcleo contable:** las ven las seis suites, salvo dos que en esta batería se le escaparon a una
  suite de la B: M25 (sin el tope RCF) a la suite con gates y M35 (el LLTV en `isHealthy`) a la de callbacks sin
  gates.
- **B1 a B10, bloqueo, pagador, préstamo flash y gates:** solo las puede ver la B, porque la A no usa callbacks ni
  gates. Las ven sus dos suites, salvo las de gates (B7 a B9), que solo se pueden ver en la suite con gates, y B3, que
  en esta batería vio solo la suite sin gates.
- **Lo que se le escapa a una suite depende de la semilla; no es un punto ciego.** M25, M35 y B3 se corrieron aparte
  sobre las dos suites de la B con `0x3` y `0x7` (32×200), y cada suite vio cada una con alguna de las tres semillas:
  - con `0x7`, la suite con gates vio las tres y la sin gates vio M25 y M35;
  - con `0x3`, la sin gates vio las tres.

  Son casos a los que se llega poco: el tope RCF, el borde del LLTV y un `take` anidado con el mismo vendedor. A M25
  ya se le había escapado una variante de la A en la batería del 29-oct.
- **Cómo se ven las B:** por MN-LIVE, cuando pasa una operación que el modelo predice rechazada, o por MN-FUNDS,
  cuando el dinero sale de quien no corresponde.
- **MN-CLAIM:** la ley económica también detecta dos, además de las leyes exactas:
  - M3: vender crédito sin recortarlo primero deja reclamos por encima de `totalUnits`.
  - M21: no escalar `continuousFeeCredit` con la pérdida produce el mismo efecto.

| Mutación | Suites que la ven | Leyes |
|---|---|---|
| M1 `take`: lo que paga el comprador de una oferta de compra redondea hacia arriba | las 6 | MN-MKT, MN-FUNDS |
| M2 `take`: lo que recibe el vendedor de una oferta de venta redondea hacia abajo | las 6 | MN-POS, MN-MKT, MN-FUNDS |
| M3 `take`: no se actualiza al vendedor con crédito | las 6 | MN-POS, MN-MKT, MN-CLAIM |
| M4 `take`: el crédito del comprador no descuenta su deuda | las 6 | MN-POS, MN-MKT, MN-UNITS |
| M5 `take`: el vendedor no usa su crédito | las 6 | MN-POS, MN-MKT, MN-UNITS, MN-LIVE |
| M6 `take`: la comisión pendiente del comprador redondea hacia arriba | las 6 | MN-POS |
| M7 `take`: la comisión pendiente que pierde el vendedor redondea hacia abajo | las 6 | MN-POS |
| M8 `take`: entra deuda después del vencimiento | las 6 | MN-LIVE |
| M9 `take`: `totalUnits` no descuenta el crédito vendido | las 6 | MN-MKT, MN-UNITS |
| M10 `take`: la comisión de liquidación suma una unidad de más | las 6 | MN-MKT, MN-FUNDS |
| M11 `take`: el vendedor puede quedar insano | las 6 | MN-POS, MN-MKT, MN-FUNDS, MN-LIVE |
| M12 `withdraw`: no actualiza la posición antes de retirar | las 6 | MN-POS |
| M13 `withdraw`: la comisión pendiente baja redondeando hacia abajo | las 6 | MN-POS |
| M14 `withdraw`: `withdrawable` no baja | las 6 | MN-MKT, MN-UNITS, MN-FUNDS |
| M15 `repay`: `withdrawable` no sube | las 6 | MN-MKT, MN-UNITS, MN-FUNDS |
| M16 `supplyCollateral`: no activa el colateral | las 6 | MN-POS |
| M17 `withdrawCollateral`: sin el control de salud | las 6 | MN-LIVE |
| M18 `liquidate`: la deuda incobrable valúa el colateral redondeando hacia abajo | las 6 | MN-POS, MN-MKT, MN-LIVE |
| M19 `liquidate`: el factor de pérdida redondea hacia abajo | las 6 | MN-MKT |
| M20 `liquidate`: `totalUnits` no baja con la deuda incobrable | las 6 | MN-MKT, MN-UNITS |
| M21 `liquidate`: `continuousFeeCredit` no se escala con la pérdida | las 6 | MN-MKT, MN-CLAIM |
| M22 `liquidate`: el LIF post-vencimiento es el máximo desde el vencimiento | las 6 | MN-POS, MN-MKT, MN-FUNDS |
| M23 `liquidate`: el repago por embargo redondea hacia abajo | las 6 | MN-POS, MN-MKT, MN-FUNDS |
| M24 `liquidate`: el embargo por repago redondea hacia arriba | las 6 | MN-POS, MN-MKT, MN-FUNDS |
| M25 `liquidate`: sin el tope RCF | todas menos callbacks con gates | MN-LIVE |
| M26 `liquidate`: `withdrawable` no sube con el repago | las 6 | MN-MKT, MN-UNITS, MN-FUNDS |
| M27 `updatePositionView`: el recorte redondea hacia arriba | las 6 | MN-POS, MN-VIEW |
| M28 `updatePositionView`: la comisión pendiente del recorte redondea hacia abajo | las 6 | MN-VIEW |
| M29 `updatePositionView`: el devengo no se corta en el vencimiento | las 6 | MN-POS, MN-MKT, MN-VIEW |
| M30 `updatePositionView`: el devengo redondea hacia arriba | las 6 | MN-VIEW |
| M31 `_updatePosition`: no guarda el factor de pérdida | las 6 | MN-POS |
| M32 `_updatePosition`: no guarda el último devengo | las 6 | MN-POS |
| M33 `_updatePosition`: `continuousFeeCredit` no suma lo devengado | las 6 | MN-MKT |
| M34 `claimContinuousFee`: `withdrawable` no baja | las 6 | MN-MKT, MN-UNITS, MN-FUNDS, MN-LIVE |
| M35 `isHealthy`: el LLTV redondea hacia arriba | todas menos callbacks | MN-VIEW |
| M36 `settlementFee`: el tramo de 7 a 30 días parte del punto de 30 | las 6 | MN-VIEW |
| M37 `liquidate`: el colateral embargado no sale del bitmap | las 6 | MN-POS |
| B1 `take`: el vendedor no queda bloqueado durante los callbacks | las 2 de la B | MN-POS, MN-MKT, MN-LIVE |
| B2 `take`: paga el comprador aunque tenga callback | las 2 de la B | MN-FUNDS |
| B3 `take`: desbloquea al vendedor aunque lo haya bloqueado un `take` de afuera | callbacks | MN-LIVE |
| B4 `repay`: paga quien llama aunque haya callback | las 2 de la B | MN-FUNDS |
| B5 `liquidate`: paga quien llama aunque haya callback | las 2 de la B | MN-FUNDS |
| B6 `flashLoan`: no cobra de vuelta lo prestado | las 2 de la B | MN-FUNDS |
| B7 `take`: el gate de entrada no controla el crédito | callbacks con gates | MN-LIVE |
| B8 `take`: el gate de entrada no controla la deuda | callbacks con gates | MN-LIVE |
| B9 `liquidate`: el gate de liquidadores no controla | callbacks con gates | MN-LIVE |
| B10 `liquidate`: ignora el bloqueo del vendedor | las 2 de la B | MN-POS, MN-MKT, MN-LIVE |

Las leyes de más en algunas filas son el efecto en cadena de la mutación. Cuáles se rompen primero cambia de una
corrida a otra.

## 8. Qué NO cubre

- **Periferia:** ratifiers reales (`EcrecoverRatifier`, `SetterRatifier`, `RateRatifierV1`, `PriceRatifierV1`),
  `EcrecoverAuthorizer`, `BlueBuyCallback`, `BlueFallbackRolling` y `WhitelistEnterGate`. La periferia nueva se revisó
  a mano el 29-oct, sin candidatos (ver `docs/TRASPASO.md`).
- **Callbacks y gates:** más de un nivel de anidamiento (un `take` anidado con sus propios callbacks), `multicall`
  dentro de un callback y gates que distingan cuentas (el del cazador abre o cierra para todos).
- **Otros:** varios mercados, más de dos colaterales, tokens no estándar y autorizaciones delegadas parciales.
