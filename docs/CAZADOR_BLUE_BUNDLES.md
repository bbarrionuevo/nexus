# Cazador de BlueBundlesV1 (Morpho Bundles)

Estado (31-oct): **variante B1 (las cinco entradas sin reasignaciones públicas) verificada con forge en la PC, ahora
con interés en Blue**: hasta el 30-oct los mercados no tenían IRM y la relación de acciones quedaba en 1e6 por activo,
así que ningún redondeo de acciones se ejercitaba. Con interés, comisión de Blue, colateral barato y `maxLtv` en su
borde exacto, pasa sin falsos positivos ni reversiones del handler con dos semillas y se detectan las 18 mutaciones,
incluidas cuatro del control de `maxLtv` que antes eran invisibles. **No hay hallazgos.**

## 1. Qué versión y qué alcance

- **Programa:** Morpho en Cantina. El grupo "Morpho Blue and Vault V1 (MetaMorpho), including bundlers" (Critical de
  USD 250.000 a 2.500.000) incluye los bundlers; la página de direcciones de Morpho lista `BlueBundlesV1` entre los
  "Bundles".
- **Versión probada:** lo desplegado en Ethereum (`0x38B0…22e6AD`) es la etiqueta `2026-08-25` del repo
  `morpho-org/bundles`. Hasta la `2026-10-06` (`2ed954e`, el clon que comparte con el cazador de MidnightBundlesV2)
  `BlueBundlesV1.sol` solo sumó dos comentarios de lint: la misma lógica.
- **Qué no es nuevo:** auditorías de Blackthorn y Trustsec (25-ago) y las especificaciones de Certora que prueban que
  los bundles toman fondos solo de quien llama. La revisión manual del 30-oct (operaciones en nombre de otro,
  callbacks, firmas, transitorios) no dejó candidatos.

## 2. Qué hace el bundle

Cinco entradas sobre Morpho Blue, todas a nombre de `msg.sender` (que tiene que autorizar al bundle en Blue para
pedir prestado y retirar):

| Entrada | Qué hace | Comisión de referido |
|---|---|---|
| `SupplyCollateralAndBorrow` | aporta colateral y pide prestado; con `maxLtv`, controla el LTV final | `⌊(borrow − penalidades)·pct/WAD⌋`, descontada de lo que recibe |
| `RepayAndWithdrawCollateral` | repaga (por activos, por acciones o todo con `max`) y retira colateral; devuelve lo que sobra de `maxRepayAssets` | `⌊repagado·pct/(WAD − pct)⌋`, encima de lo repagado |
| `Supply` | deposita como prestamista | `⌊assets·pct/WAD⌋`, descontada de lo depositado |
| `Withdraw` | retira (por activos o por acciones) | `⌊(retirado − penalidades)·pct/WAD⌋`, descontada |
| `MigrateBorrowPosition` | mueve toda la posición (colateral y deuda) a otro mercado de los mismos tokens, con un callback de repago | `⌊repagado·pct/(WAD − pct)⌋`, pedida en destino |

Las penalidades son las del Blue Public Allocator, cuando se piden reasignaciones públicas (se adelantan con un
préstamo flash). La variante B1 no las usa.

## 3. Leyes (exactas, contra el estado de Blue)

En cada llamada que pasa:

- **BB-FUNDS:** el bundle termina sin saldo; lo que paga o cobra el usuario es exactamente lo documentado.
- **BB-FEE:** la comisión que recibe el referido es exactamente la documentada, sobre lo que de verdad se pidió,
  repagó o retiró.
- **BB-POS:** la posición del usuario en Blue cambia exactamente: colateral, y acciones de oferta y de deuda con el
  redondeo de Blue (`toSharesUp` al pedir, `toSharesDown` al depositar y al repagar por activos, etc.). En la
  migración, el origen queda en cero y el destino suma el colateral y lo repagado más la comisión.
- **BB-LTV:** con `maxLtv`, la deuda (redondeada hacia arriba, devengada) no supera colateral·precio·`maxLtv`.
- **BB-ISO:** ninguna otra posición ni saldo cambia.
- **BB-LIVE**, en las dos direcciones (desde el 31-oct): con el plazo vencido, `pct ≥ WAD` o tokens distintos entre
  origen y destino de la migración, revierte; y no revierte por una de esas validaciones, ni por `maxLtv`, cuando no
  corresponde. `maxLtv` se prueba en su borde exacto: el mínimo que pasa (sale de una corrida en seco sin control,
  que se revierte, con la deuda y el valor del colateral que deja la llamada) tiene que pasar, y uno menos, revertir.

## 4. Harness (`local/nexus/secresearch/harness/morpho-org__bundles/NexusBlueBundles.t.sol`)

- **Entorno:** Morpho Blue real (solc 0.8.19, por `deployCode` desde `NexusBlueImport.sol`), cuatro mercados: dos
  con un colateral y dos con otro, con LLTV de 86 % y 94,5 % (cada par es una migración posible; entre familias,
  `InconsistentTokens`). Un prestamista aparte pone liquidez inicial.
- **Interés y precio no redondo (desde el 31-oct):** hasta el 30-oct los mercados no tenían IRM (`address(0)`), Blue
  no devengaba y la relación quedaba clavada en 1e6 acciones por activo: ningún redondeo de acciones se ejercitaba.
  Ahora una IRM de prueba fija una tasa por mercado (alrededor de 9,5 % y 38 % anual), un prestatario aparte toma la
  mitad de cada mercado desde el principio y Blue cobra comisión en dos mercados (10 % y 25 %). Las leyes usan los
  totales devengados (`expectedMarketBalances`): los guardados quedan viejos.
- **Colateral barato:** la segunda familia tiene precio de oráculo 1e30 (como un colateral con más decimales que el
  activo prestado). Con colateral caro, un punto de `maxLtv` mueve la deuda máxima en un millón de wei y el borde de
  `maxLtv` no es exacto en la deuda; con el barato, en alrededor de 1 wei.
- **Actores:** cuatro usuarios que autorizan al bundle en Blue y dos referidos.
- **Parámetros:** préstamos dentro de lo sano casi siempre (y a veces cualquiera); repagos por activos, por acciones o
  todo, a veces de más o los dos a la vez (Blue revierte); retiros de colateral dentro de lo libre; comisiones de
  referido 0, 1 wei, 0,3 %, 50 %, `WAD − 1` y `WAD`; `maxLtv` de 50 %, 80 %, 0, sin control o en el borde exacto;
  plazos vencidos.
- **Entre llamadas:** depósitos directos en Blue, cambios de precio y saltos de reloj.
- **Montos:** 1 de cada 4 veces la semilla cruda, las demás uniformes en todo el rango.
- **Métricas:** por entrada, llamadas que pasaron; comisiones, controles de `maxLtv`, migraciones; reversiones por
  motivo.

Al armarlo apareció un falso positivo del cazador: en Solidity, `P memory q = p` copia la referencia, y cambiar el
mercado de la copia cambiaba el del original (las leyes "del origen" de la migración miraban el destino).

## 5. Verificación

### Con interés (31-oct, forge 1.8.6 en la PC)

En el proyecto reducido de `tools/forge_v2` (`NEXUS_PERFIL=blue-bundles`), con el fuzzing guiado por cobertura:

- pasa 64×200 con `0x2a` y `0x3` (12.800 llamadas cada una), sin falsos positivos ni reversiones del handler; en la
  última corrida pasaron las cinco entradas (14 y 16 préstamos, 23 y 21 repagos, 18 y 16 depósitos, 14 y 8 retiros,
  7 y 3 migraciones), con 15 y 21 controles de `maxLtv` y 12 y 20 llamadas con `maxLtv` en el borde exacto. Al final,
  1e24 acciones de oferta del mercado 0 valían 1,0055e18 y 1,0068e18 activos, y las de deuda del mercado 3, 1,045e18 y
  1,056e18 (de partida, 1e18);
- se detectan las 18 mutaciones: las 14 de antes con las mismas leyes, y las cuatro nuevas del control de `maxLtv`,
  que con la relación redonda y sin borde exacto no se podían ver:

| Mutación | Ley que la ve |
|---|---|
| B15: la deuda redondeada hacia abajo | BB-LTV |
| B16: sin devengar el interés antes de medir la deuda (Blue no devenga al aportar colateral) | BB-LTV |
| B17: el control estricto (`<` en vez de `<=`) | BB-LIVE (revierte con el mínimo que pasa) |
| B18: la deuda máxima redondeada hacia arriba | BB-LTV |

Campaña profunda con interés (31-oct, de las 16:26 a las 17:04, 512×500 guiada por cobertura, 256.000 llamadas,
semilla `0x056d7f1e26ca6776`, `20261031-162639_blue-bundles_512x500_0x056d7f1e26ca6776`): **ninguna ley violada y 0
reversiones del handler**. En la última corrida pasaron 171 de 290 llamadas al bundle (30 préstamos, 41 repagos, 43
depósitos, 34 retiros y 23 migraciones), con 46 controles de `maxLtv`, 34 de ellos en el borde exacto; 1e24
acciones de deuda del mercado 3 terminaron valiendo 1,178e18 activos.

### Sin interés (30-oct, forge 1.8.6 en la PC)

En el proyecto reducido de `tools/forge_v2` (`NEXUS_PERFIL=blue-bundles`, que compila en menos de un minuto), con el
fuzzing guiado por cobertura:

- pasa 64×200 con `0x2a` y `0x3` (12.800 llamadas cada una), sin falsos positivos ni reversiones del handler; en la
  última corrida pasaron las cinco entradas (18 y 22 préstamos, 29 y 21 repagos, 22 y 28 depósitos, 13 y 21 retiros,
  13 y 4 migraciones), con 18 y 15 controles de `maxLtv`;
- las 14 mutaciones de `tools/forge_v2/mutaciones_blue_bundles.json` se detectan:

| Mutación | Ley que la ve |
|---|---|
| B1, B3, B7, B9, B11: fórmulas y redondeo de las comisiones de referido de las cinco entradas | BB-FEE (y BB-FUNDS, BB-POS) |
| B2, B6, B14: sin el control de `maxLtv` al pedir, al retirar colateral y al migrar | BB-LTV |
| B4: el colateral retirado queda en el bundle | BB-FUNDS |
| B5: repagar todo deja una acción de deuda | BB-POS, BB-FUNDS |
| B8: deposita a nombre del referido | BB-POS |
| B10, B13: sin el control de la comisión o del plazo | BB-LIVE |
| B12: en la migración aporta una unidad menos de colateral | BB-POS, BB-FUNDS |

Campaña profunda (30-oct, de las 18:00 a las 18:39, 512×500 con el corpus acumulado, 256.000 llamadas, semilla
`0x54a4b94f0009d8fb`): **ninguna ley violada y 0 reversiones del handler**. En la última corrida pasaron 207 de 301
llamadas al bundle: 39 préstamos, 44 repagos, 51 depósitos, 51 retiros y 22 migraciones, con 107 comisiones de
referido y 30 controles de `maxLtv`; las 94 que revirtieron se repartieron entre plazo o comisión (35), Blue (29:
salud, liquidez, entradas), pánico aritmético (15: comisiones extremas y repagos de más), `LtvExceeded` (10) e
`InconsistentTokens` (5).

## 6. Qué NO cubre

- Las reasignaciones públicas (Blue Public Allocator, Vault V2 y sus penalidades, el préstamo flash que las paga):
  la variante siguiente, sobre la infraestructura del cazador de Vault V2.
- Permisos y autorizaciones por firma (el test de coherencia no permite firmas) y el token nativo.
- Liquidaciones y deuda incobrable en Blue: el precio de las acciones solo sube.
