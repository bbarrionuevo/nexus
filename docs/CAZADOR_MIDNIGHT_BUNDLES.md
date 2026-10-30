# Cazador de MidnightBundlesV2 (Morpho Bundles)

Estado: **fase 1 (las cuatro entradas de quien toma ofertas) escrita y verificada con forge en la PC** (30-oct): las
dos variantes pasan sin falsos positivos ni reversiones del handler y las 24 mutaciones de referencia se detectan. La
fase 2 (crear y cancelar ofertas con `CancelAndMake`, con Blue y `BlueBuyCallback` reales) está en curso. **No hay
hallazgos.**

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
- **Semillas:** las decisiones salen de un hash de cada semilla; los montos, de la semilla cruda (así el fuzzer puede
  apuntar a valores exactos de su diccionario).
- **Métricas:** por entrada, llamadas y llamadas que pasaron; creadores tocados, repagos, retiros, comisiones; y las
  reversiones del bundle por motivo.

## 5. Verificación (30-oct, forge 1.8.6 en la PC)

En el proyecto reducido de `tools/forge_v2` (`NEXUS_PERFIL=midnight-bundles`), con el fuzzing guiado por cobertura:

- las dos variantes pasan 32×120 con `0x2a` y `0x3`, sin falsos positivos ni reversiones del handler;
- en la última corrida de cada suite pasan más o menos la mitad de las llamadas al bundle, con las cuatro entradas,
  repagos, retiros de crédito y comisiones de referido; las reversiones del bundle quedan clasificadas por motivo.

Al armarlo aparecieron dos falsos positivos del cazador, corregidos antes de la verificación:
- con semillas chicas, que el fuzzer da a menudo, las decisiones caían siempre en la misma rama (casi todas las
  llamadas vencidas): las decisiones salen ahora de un hash de la semilla;
- con cero ofertas la llamada no controla lado, mercado ni comisión continua, y BU-LIVE esperaba la reversión.

Las ofertas que hacen revertir el cálculo previo a la toma (fuera del `try`) revierten la llamada entera: es una clase
de vivacidad que la auditoría de Spearbit del 6-oct (5.1.5) señaló y Morpho aceptó. El cazador las genera poco y las
cuenta aparte.

## 6. Mutaciones de referencia

`tools/forge_v2/mutaciones_midnight_bundles.json`, sobre `src/midnight/MidnightBundlesV2.sol`; **las 24 se
detectan**, la mayoría en las dos variantes:

| Grupo | Mutaciones | Ley que las ve |
|---|---|---|
| Comisiones de referido | U1-U4 | BU-FEE (y BU-FUNDS) |
| Garantías del usuario: `reduceOnly`, mínimos y máximos | U5-U9 | BU-LIMIT |
| Exactitud del objetivo | U10-U12 | BU-LIMIT, BU-FUNDS |
| Validaciones: plazo, comisión, lado, mercado, comisión continua | U13-U17 | BU-LIVE |
| A quién va cada cosa: el taker, el colateral, lo cobrado, la comisión | U18-U22 | BU-CONS, BU-LIMIT, BU-FUNDS, BU-FEE |
| Lo que el bundle se queda | U23-U24 | BU-FUNDS |

## 7. Qué NO cubre

- `CancelAndMake` (fase 2): cancelación de grupos con consumo máximo, aportes a Blue para `BlueBuyCallback`,
  ratifiers reales y la publicación en el log.
- Ofertas con callbacks del creador (reentrada al bundle desde un callback) y el token nativo (`msg.value`).
- La vivacidad con liquidez suficiente: una llamada que revierte sin romper una validación no es una violación.
- Después del vencimiento.
