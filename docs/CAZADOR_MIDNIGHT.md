# Cazador de Morpho Midnight

Estado: **variante A escrita y verificada con forge en la PC** (29-oct). Pasa sin falsos positivos ni reversiones
en sus cuatro variantes (32×300 con las semillas `0x2a` y `0x3`, y `validate` sobre el repo entero a 64×300), y
las 37 mutaciones de referencia se detectan. **No hay hallazgos.**

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

**Verificación (29-oct, forge 1.8.6 en la PC).**

- **Proyecto reducido:** con el harness final, las 4 variantes pasan 32×300 sin falsos positivos y con 0 reversiones,
  con las semillas `0x2a` y `0x3` (9.600 llamadas por variante y semilla).
- **Referencia:** `validate` sobre el repo entero (etiqueta `2026-08-24`, compilación aislada, 64×300, semilla
  `0xf447dc803a8a69c4`) da 4 de 4 con 0 reversiones: 101 s de compilación y 286 s de tests. La primera compilación
  de `src` entero, con la periferia, llevó unos 40 minutos con la PC cargada; después forge usa su caché.
- **Cobertura en la última corrida de cada variante, con las dos semillas:**
  - de 33.000 a 36.000 leyes evaluadas;
  - de 11 a 19 `take`: de 5 a 13 en que el vendedor vendió crédito y de 1 a 9 en que el comprador canceló deuda;
  - de 2 a 5 realizaciones de deuda incobrable;
  - de 2 a 6 liquidaciones con embargo o repago, y de 0 a 2 en modo post-vencimiento;
  - de 3 a 8 retiros;
  - de 133 a 155 rechazos predichos por el modelo.
- **Lo que el cazador recorre poco:**
  - las liquidaciones post-vencimiento;
  - las llamadas sueltas a `updatePosition` que devengan comisión o recortan crédito (0 a 2). Los devengos y los
    recortes que ocurren dentro de `take` y `withdraw` no se cuentan aparte.
- **Lo que se corrigió en el camino (ninguna fue una falla de Midnight):**
  - El modelo de la liquidación escribía el repago calculado en la estructura de entrada, y el handler mandaba
    embargo y repago a la vez.
  - La cota de MN-FAIR era de una unidad. El crédito al día acumula tres pisos (recorte, comisión pendiente y
    devengo), así que la cota correcta es `|c1·a − c0·b| < 3a`.
  - Una corrida que cruzaba el vencimiento en sus primeras llamadas no prestaba nada. Ahora el vencimiento no se
    cruza antes de 50 operaciones.

**Mutaciones de referencia** ([tools/forge_v2/mutaciones_midnight.json](../tools/forge_v2/mutaciones_midnight.json);
32×200, semilla `0x2a`, con `NEXUS_PERFIL=midnight`): las 37 se detectan. Las ven las cuatro variantes, salvo M25,
que la variante de comisiones al máximo no vio en esa corrida. La ley económica MN-CLAIM también detecta dos de
ellas, además de las leyes exactas:
- M3: vender crédito sin recortarlo primero deja reclamos por encima de `totalUnits`.
- M21: no escalar `continuousFeeCredit` con la pérdida produce el mismo efecto.

| Mutación | Variantes que la ven | Leyes |
|---|---|---|
| M1 `take`: lo que paga el comprador de una oferta de compra redondea hacia arriba | las 4 | MN-MKT, MN-FUNDS |
| M2 `take`: lo que recibe el vendedor de una oferta de venta redondea hacia abajo | las 4 | MN-POS, MN-MKT, MN-FUNDS |
| M3 `take`: no se actualiza al vendedor con crédito | las 4 | MN-POS, MN-MKT, MN-CLAIM |
| M4 `take`: el crédito del comprador no descuenta su deuda | las 4 | MN-POS, MN-MKT, MN-UNITS |
| M5 `take`: el vendedor no usa su crédito | las 4 | MN-LIVE, MN-POS, MN-MKT, MN-UNITS |
| M6 `take`: la comisión pendiente del comprador redondea hacia arriba | las 4 | MN-POS |
| M7 `take`: la comisión pendiente que pierde el vendedor redondea hacia abajo | las 4 | MN-POS |
| M8 `take`: entra deuda después del vencimiento | las 4 | MN-LIVE |
| M9 `take`: `totalUnits` no descuenta el crédito vendido | las 4 | MN-MKT, MN-UNITS |
| M10 `take`: la comisión de liquidación suma una unidad de más | las 4 | MN-MKT, MN-FUNDS |
| M11 `take`: el vendedor puede quedar insano | las 4 | MN-LIVE |
| M12 `withdraw`: no actualiza la posición antes de retirar | las 4 | MN-POS |
| M13 `withdraw`: la comisión pendiente baja redondeando hacia abajo | las 4 | MN-POS |
| M14 `withdraw`: `withdrawable` no baja | las 4 | MN-MKT, MN-UNITS, MN-FUNDS |
| M15 `repay`: `withdrawable` no sube | las 4 | MN-MKT, MN-UNITS, MN-FUNDS |
| M16 `supplyCollateral`: no activa el colateral | las 4 | MN-POS |
| M17 `withdrawCollateral`: sin el control de salud | las 4 | MN-LIVE |
| M18 `liquidate`: la deuda incobrable valúa el colateral redondeando hacia abajo | las 4 | MN-LIVE |
| M19 `liquidate`: el factor de pérdida redondea hacia abajo | las 4 | MN-MKT |
| M20 `liquidate`: `totalUnits` no baja con la deuda incobrable | las 4 | MN-MKT, MN-UNITS |
| M21 `liquidate`: `continuousFeeCredit` no se escala con la pérdida | las 4 | MN-MKT, MN-CLAIM |
| M22 `liquidate`: el LIF post-vencimiento es el máximo desde el vencimiento | las 4 | MN-POS, MN-MKT, MN-FUNDS |
| M23 `liquidate`: el repago por embargo redondea hacia abajo | las 4 | MN-POS, MN-MKT, MN-FUNDS |
| M24 `liquidate`: el embargo por repago redondea hacia arriba | las 4 | MN-POS, MN-MKT, MN-FUNDS |
| M25 `liquidate`: sin el tope RCF | comisiones al 50 %, 6 decimales, LLTV = 1 | MN-LIVE |
| M26 `liquidate`: `withdrawable` no sube con el repago | las 4 | MN-MKT, MN-UNITS, MN-FUNDS |
| M27 `updatePositionView`: el recorte redondea hacia arriba | las 4 | MN-VIEW |
| M28 `updatePositionView`: la comisión pendiente del recorte redondea hacia abajo | las 4 | MN-VIEW |
| M29 `updatePositionView`: el devengo no se corta en el vencimiento | las 4 | MN-VIEW, MN-POS, MN-MKT |
| M30 `updatePositionView`: el devengo redondea hacia arriba | las 4 | MN-VIEW |
| M31 `_updatePosition`: no guarda el factor de pérdida | las 4 | MN-POS |
| M32 `_updatePosition`: no guarda el último devengo | las 4 | MN-POS |
| M33 `_updatePosition`: `continuousFeeCredit` no suma lo devengado | las 4 | MN-MKT |
| M34 `claimContinuousFee`: `withdrawable` no baja | las 4 | MN-LIVE, MN-MKT, MN-UNITS, MN-FUNDS |
| M35 `isHealthy`: el LLTV redondea hacia arriba | las 4 | MN-VIEW |
| M36 `settlementFee`: el tramo de 7 a 30 días parte del punto de 30 | las 4 | MN-VIEW |
| M37 `liquidate`: el colateral embargado no sale del bitmap | las 4 | MN-POS |

Las leyes de más en algunas filas son el efecto en cadena de la mutación.

## 5. Qué NO cubre

- **Periferia:** ratifiers reales (`EcrecoverRatifier`, `SetterRatifier`, `RateRatifierV1`, `PriceRatifierV1`),
  `EcrecoverAuthorizer`, `BlueBuyCallback`, `BlueFallbackRolling` y `WhitelistEnterGate`.
- **Callbacks:** `onBuy`, `onSell`, `onRepay` y `onLiquidate`, el préstamo flash, `multicall` y los gates.
- **Otros:** varios mercados, más de dos colaterales, tokens no estándar y autorizaciones delegadas.
