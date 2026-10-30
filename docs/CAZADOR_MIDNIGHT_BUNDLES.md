# Cazador de MidnightBundlesV2 (Morpho Bundles)

Estado (30-oct):
- **Fase 1, las cuatro entradas de quien toma ofertas: verificada con forge en la PC.** Las dos variantes pasan sin
  falsos positivos ni reversiones del handler, las 24 mutaciones de referencia se detectan y la campaña profunda
  (512×500, 256.000 llamadas por variante) pasó sin leyes rotas ni reversiones.
- **Fase 2, crear y cancelar ofertas con `CancelAndMake` sobre Morpho Blue, `BlueBuyCallback` y `PriceRatifierV1`
  reales, y las ventas tomando esas ofertas: verificada con forge en la PC.** Las cuatro suites (dos de cada fase)
  pasan sin falsos positivos ni reversiones del handler y las 34 mutaciones de referencia se detectan.

**No hay hallazgos.**

## 1. Qué versión y qué alcance

- **Programa:** Morpho en Cantina (en el catálogo). La página de direcciones de Morpho, que el reglamento declara
  fuente de verdad del alcance, lista los "Bundles": `VaultBundlesV1`, `VaultExitBundlesV1`, `BlueBundlesV1`,
  `MidnightBundlesV1` y `MidnightBundlesV2`. El grupo "Morpho Blue and Vault V1" dice "including bundlers".
- **Versión probada: la etiqueta `2026-10-06` (`2ed954e`)**, que es lo desplegado en Ethereum
  (`0x78ed…bDbA4`, coincidencia completa en Sourcify, solc 0.8.34). `main` ya tiene cambios posteriores: se prueba
  siempre lo desplegado.
- **Núcleo:** el bundle compila con su submódulo `lib/midnight` (`4603969`), que difiere del núcleo desplegado
  (`14e0b77`) solo en formato, comentarios y la interfaz `IBuyerAssetsBound`: la misma lógica que prueba el cazador de
  Midnight ([CAZADOR_MIDNIGHT.md](CAZADOR_MIDNIGHT.md)).
- **Qué no es nuevo:** dos auditorías de esta versión (Sherlock y Spearbit, 6-oct) y especificaciones de Certora que
  prueban que los bundles toman fondos solo de quien llama. Lo conocido queda fuera de alcance.

## 2. Qué hace el bundle (lado de quien toma)

Cuatro entradas, todas con el usuario como `msg.sender`, que tiene que autorizar al bundle en Midnight:

| Entrada | Objetivo | Garantía documentada | Comisión de referido |
|---|---|---|---|
| `BuyWithUnitsTargetAndWithdrawCollateral` | `targetUnits` exactos (`max`: toda la deuda) | paga a lo sumo `maxBuyerAssets` | `⌊llenado·pct/(WAD − pct)⌋` |
| `SupplyCollateralAndSellWithUnitsTarget` | `targetUnits` exactos (`max`: todo el crédito) | cobra al menos `minSellerAssets` | `⌊llenado·pct/WAD⌋` |
| `BuyWithAssetsTargetAndWithdrawCollateral` | paga exactamente `targetBuyerAssets` | gana al menos `minUnits` | `⌊objetivo·pct/WAD⌋` |
| `SupplyCollateralAndSellWithAssetsTarget` | cobra exactamente `targetSellerAssets` | pierde a lo sumo `maxUnits` | `⌊objetivo·pct/(WAD − pct)⌋` |

- Las compras toman ofertas de venta en orden, saltean las que revierten (`try take`) y, con `repayEnabled`, repagan
  la deuda con lo que falte; después retiran colateral hacia el receptor elegido.
- Las ventas aportan colateral, retiran primero todo el crédito posible (hasta `withdrawable`) y después toman ofertas
  de compra; lo cobrado va al receptor elegido.
- Validaciones: plazo, `pct < WAD`, lado y mercado de cada oferta tocada, comisión continua máxima (compras),
  `reduceOnly` del usuario.

El lado de quien crea ofertas (fase 2) es `CancelAndMake`: cancela grupos del usuario (con un consumo máximo
aceptable por grupo), aporta colateral, estaciona activo en Blue a nombre del `BlueBuyCallback` del usuario (que la
fábrica crea con CREATE2 por usuario y sal) y, con una raíz nueva, autoriza al ratifier elegido, ratifica la raíz y
publica el payload en el log. Las ofertas de compra financiadas así llevan `callback` = ese `BlueBuyCallback`: al
tomarlas, Midnight le pide el pago y el callback lo saca de Blue (`onBuy` solo paga compras de su dueño).

## 3. Leyes (exactas, contra los saldos y las posiciones reales)

En cada llamada que pasa, sin modelo del núcleo:

- **BU-FUNDS:** el bundle termina sin saldo de ningún token; lo que paga el usuario es lo llenado más la comisión (o
  exactamente el objetivo); lo que cobra el receptor más la comisión es lo llenado; lo llenado se mide del otro lado,
  como lo que entró a los creadores de las ofertas y a Midnight.
- **BU-FEE:** la comisión que recibe el referido es exactamente la documentada, sobre lo que de verdad se llenó.
- **BU-CONS:** las unidades que gana o pierde el usuario las pierden o ganan los creadores de las ofertas tomadas,
  salvo el repago y el retiro de crédito, que mueven `withdrawable` en la misma cantidad (crédito leído con
  `updatePositionView`, con la comisión continua devengada).
- **BU-ISO:** nadie fuera de la llamada (usuario, creadores tocados, referido y receptor elegidos) cambia de saldo,
  colateral, crédito ni deuda.
- **BU-LIMIT:** el objetivo exacto de cada entrada, los mínimos y máximos, `reduceOnly` (sin crédito nuevo al comprar,
  sin deuda nueva al vender), y los retiros y aportes de colateral exactos (con `max`, todo).
- **BU-LIVE:** en las dos direcciones. Con el plazo vencido, `pct ≥ WAD`, una oferta del lado o del mercado
  equivocado que la llamada llega a tocar, o la comisión continua sobre el máximo del usuario, la llamada revierte;
  y no revierte por una de esas validaciones cuando no corresponde.

Fase 2, en cada `CancelAndMake` y en cada toma:

- **MK-CANCEL:** cada grupo cancelado queda con consumo máximo.
- **MK-PARK:** lo estacionado sale del usuario y entra exacto a Blue y a la posición del `BlueBuyCallback` de ese
  usuario y esa sal (sin interés ni deuda incobrable en Blue, el precio de las acciones no cambia y es exacto).
- **MK-RATIFY:** con una raíz nueva, el ratifier queda autorizado por el usuario y la raíz ratificada para él.
- **MK-COLL:** el colateral aportado entra exacto a la posición del usuario en Midnight.
- **MK-ISO:** nada de los demás cambia: autorizaciones del ratifier, raíces, consumos de sus grupos y posiciones en
  Blue de los callbacks ajenos; el bundle sin saldo.
- **MK-LIVE:** revierte si y solo si el plazo venció o algún grupo ya superaba su `maxConsumed` (con fondos y
  aprobaciones suficientes, nada más puede hacerlo revertir).
- **BU-CB:** en una toma, la posición en Blue de un callback solo baja si su dueño compró unidades en esa llamada,
  nunca sube, y el callback no se queda con saldo. Algunas ofertas usan el callback de otro usuario: no tienen que
  poder cobrarle.
- **BU-TAKE:** una oferta creada solo la toma su `allowedTaker` (si tiene) y solo mientras su raíz está ratificada.

## 4. Harness (`local/nexus/secresearch/harness/morpho-org__bundles/`)

- **Entorno:** el núcleo real de Midnight y el bundle real; tokens de prueba; dos colaterales con oráculos de precio
  variable; un ratifier de prueba que ratifica toda oferta (la autorización del creador la sigue exigiendo el núcleo);
  un mercado con comisiones de liquidación y otro con otro vencimiento (para las ofertas del mercado equivocado).
  Blue y la fábrica de `BlueBuyCallback` son stubs: las entradas de toma no los usan.
- **Actores:** cuatro, que crean ofertas y llaman al bundle; dos referidos y un receptor aparte.
- **Ofertas:** de 0 a 4 por llamada, de los otros actores, con grupos nuevos o compartidos, topes en unidades o en
  activos, `reduceOnly`, algunas vencidas. La mitad de los precios cerca de 1 y la otra mitad en cualquier punto;
  salvo 1 de cada 16, tomables (con una oferta no tomable `TakeAmountsLib` revierte, como documenta, y la llamada
  entera revierte). A veces la primera oferta es del lado o del mercado equivocado.
- **Parámetros:** objetivos `max`, una parte de la deuda o del crédito, o cualquiera; comisiones de referido 0, 1 wei,
  0,3 %, 50 %, `WAD − 1` y `WAD`; receptores propios o ajenos; plazos vencidos; comisión continua máxima en 0.
- **Entre llamadas:** posiciones directas entre actores (deuda para repagar, crédito para vender), repagos directos
  (liquidez retirable), saltos de reloj antes del vencimiento y cambios de precio.
- **Variantes:** comisiones de liquidación al 50 % del máximo y sin comisión continua, y todas las comisiones al
  máximo.
- **Semillas:** las decisiones salen de un hash de cada semilla. Los montos, 1 de cada 4 veces de la semilla cruda
  (el diccionario del fuzzer apunta a valores exactos) y las demás uniformes en todo el rango: forge saca de su
  diccionario el 80 % de los valores de una campaña de invariantes, y con montos crudos casi todo quedaba chico.
- **Métricas:** por entrada, llamadas y llamadas que pasaron; creadores tocados, repagos, retiros, comisiones; y las
  reversiones del bundle por motivo.

Fase 2 (`NexusMidnightBundlesMake.t.sol`, que hereda todo lo anterior):

- **Entorno:** Morpho Blue real (0.8.19, desplegado con `deployCode` desde `NexusBlueImport.sol`), sin interés, con
  un mercado del mismo activo prestado que Midnight; `BlueBuyCallbackFactory`, `PriceRatifierV1` y `Log` reales.
- **`make`:** `CancelAndMake` con 0 a 2 grupos a cancelar (de ofertas del usuario o nuevos, con `maxConsumed`
  máximo, igual o uno menos que el consumo), 0 o 1 aporte de colateral, estacionamiento en Blue con una de dos sales y
  0, 1 o 2 ofertas de compra nuevas en un árbol de Merkle de `PriceRatifierV1` (con su prueba). Las ofertas usan casi
  siempre un callback del creador que existe; a veces el de otro usuario (no tiene que pagar), a veces ninguno (paga
  el creador) y 1 de cada 16 cualquiera, exista o no.
- **Tomas:** las ventas de la fase 1 mezclan ofertas creadas con su prueba; `sellMade` vende solo contra ofertas
  creadas, con objetivos de 1e15 a 1e21 que entren en lo que tienen (las ventas exigen llenar el objetivo exacto).
- **Entre llamadas:** depósitos y préstamos de otros en Blue (a lo sumo un cuarto de la liquidez por préstamo) y
  raíces des-ratificadas directo en el ratifier.
- **Variantes:** las dos de la fase 1.

## 5. Verificación (30-oct, forge 1.8.6 en la PC)

En el proyecto reducido de `tools/forge_v2` (`NEXUS_PERFIL=midnight-bundles`), con el fuzzing guiado por cobertura:

- las dos variantes pasan 32×120 con `0x2a` y `0x3`, sin falsos positivos ni reversiones del handler;
- en la última corrida de cada suite pasan más o menos la mitad de las llamadas al bundle, con las cuatro entradas,
  repagos, retiros de crédito y comisiones de referido; las reversiones del bundle quedan clasificadas por motivo.

Fase 2 (30-oct): con la fase 1 ya cambiada (ganchos, montos mezclados y el arreglo de U16 de abajo), las cuatro
suites pasan 32×120 con `0x2a` y `0x3`, sin falsos positivos ni reversiones del handler, con tomas pagadas desde Blue
en casi todas las corridas finales.

Campaña profunda de la fase 1 (30-oct, de las 14:23 a las 15:33, 512×500 con corpus, 256.000 llamadas por variante,
semilla `0xefc007c341fac34b`): las dos variantes en verde, **ninguna ley violada y 0 reversiones del handler**. En la
última corrida de cada suite pasaron 115 y 127 llamadas al bundle de 232 y 256, con 90 y 108 creadores tocados, 37 y
34 retiros de crédito y 39 y 52 comisiones de referido; la guía por cobertura vio 89 y 96 caminos según la variante.

Al armarlo aparecieron dos falsos positivos del cazador, corregidos antes de la verificación:
- con semillas chicas, que el fuzzer da a menudo, las decisiones caían siempre en la misma rama (casi todas las
  llamadas vencidas): las decisiones salen ahora de un hash de la semilla;
- con cero ofertas la llamada no controla lado, mercado ni comisión continua, y BU-LIVE esperaba la reversión.

Las ofertas que hacen revertir el cálculo previo a la toma (fuera del `try`) revierten la llamada entera: es una clase
de vivacidad que la auditoría de Spearbit del 6-oct (5.1.5) señaló y Morpho aceptó. El cazador las genera poco y las
cuenta aparte.

## 6. Mutaciones de referencia

`tools/forge_v2/mutaciones_midnight_bundles.json`: U1-U24 sobre las entradas de toma de
`src/midnight/MidnightBundlesV2.sol` (las ven las suites de la fase 1) y K, C y R sobre `CancelAndMake`,
`BlueBuyCallback` y `PriceRatifierV1` (las ven las de la fase 2). **Las 34 se detectan.**

En la primera verificación de la fase 2 se escapó U16 (la venta no controla el mercado de la oferta): la oferta del
mercado equivocado no se podía tomar porque quien vendía no tenía colateral en ese mercado, la toma fallaba, se
salteaba y la venta revertía por otro motivo; antes la veía una suite de casualidad. Ahora el cazador le da colateral
en ese mercado a quien se endeuda, y BU-LIVE la ve.

| Grupo | Mutaciones | Ley que las ve |
|---|---|---|
| Comisiones de referido | U1-U4 | BU-FEE (y BU-FUNDS) |
| Garantías del usuario: `reduceOnly`, mínimos y máximos | U5-U9 | BU-LIMIT |
| Exactitud del objetivo | U10-U12 | BU-LIMIT, BU-FUNDS |
| Validaciones: plazo, comisión, lado, mercado, comisión continua | U13-U17 | BU-LIVE |
| A quién va cada cosa: el taker, el colateral, lo cobrado, la comisión | U18-U22 | BU-CONS, BU-LIMIT, BU-FUNDS, BU-FEE |
| Lo que el bundle se queda | U23-U24 | BU-FUNDS |
| `CancelAndMake`: sin `maxConsumed`, cancelación incompleta, estacionamiento a nombre equivocado o con otra sal, sin autorizar al ratifier, sin plazo | K1-K6 | MK-LIVE, MK-CANCEL, MK-PARK, MK-RATIFY |
| `BlueBuyCallback`: paga compras de cualquiera; saca de Blue una unidad de más | C1-C2 | BU-CB |
| `PriceRatifierV1`: sin `allowedTaker`; sin controlar que la raíz esté ratificada | R1-R2 | BU-TAKE |

Las leyes de la fase 2 se informan con el código de la familia de la fase 1 a la que pertenecen (`[leyes: ...]`):
MK-LIVE como BU-LIVE, MK-CANCEL, MK-RATIFY y MK-COLL como BU-LIMIT, MK-PARK y el saldo de los callbacks como
BU-FUNDS, MK-ISO, BU-CB (quién paga) y BU-TAKE como BU-ISO; el texto de la falla dice cuál fue.

## 7. Qué NO cubre

- La ratificación con firma (`setIsRootRatifiedWithSig`): el test de coherencia del harness no permite firmas.
- `RateRatifierV1` y `EcrecoverRatifier`; la fase 2 usa `PriceRatifierV1`.
- Callbacks de creadores que no sean `BlueBuyCallback` (reentrada al bundle desde un callback propio) y el token
  nativo (`msg.value`).
- La vivacidad con liquidez suficiente: una llamada que revierte sin romper una validación no es una violación.
- Después del vencimiento.
