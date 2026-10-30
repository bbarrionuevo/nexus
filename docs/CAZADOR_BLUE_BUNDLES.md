# Cazador de BlueBundlesV1 (Morpho Bundles)

Estado (30-oct): **variante B1 (las cinco entradas sin reasignaciones públicas) escrita y verificada con forge en la
PC**: pasa sin falsos positivos ni reversiones del handler con dos semillas, las 14 mutaciones de referencia se
detectan y la campaña profunda (512×500, 256.000 llamadas) pasó sin leyes violadas ni reversiones. **No hay
hallazgos.**

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
- **BB-LTV:** con `maxLtv`, la deuda (redondeada hacia arriba) no supera colateral·precio·`maxLtv`.
- **BB-ISO:** ninguna otra posición ni saldo cambia.
- **BB-LIVE:** con el plazo vencido, `pct ≥ WAD` o tokens distintos entre origen y destino de la migración, revierte.

## 4. Harness (`local/nexus/secresearch/harness/morpho-org__bundles/NexusBlueBundles.t.sol`)

- **Entorno:** Morpho Blue real (solc 0.8.19, por `deployCode` desde `NexusBlueImport.sol`), sin interés (IRM en
  `address(0)`), cuatro mercados: dos con un colateral y dos con otro, con LLTV de 86 % y 94,5 % (cada par es una
  migración posible; entre familias, `InconsistentTokens`). Un prestamista aparte pone liquidez inicial.
- **Actores:** cuatro usuarios que autorizan al bundle en Blue y dos referidos.
- **Parámetros:** préstamos dentro de lo sano casi siempre (y a veces cualquiera); repagos por activos, por acciones o
  todo, a veces de más o los dos a la vez (Blue revierte); retiros de colateral dentro de lo libre; comisiones de
  referido 0, 1 wei, 0,3 %, 50 %, `WAD − 1` y `WAD`; `maxLtv` de 50 %, 80 % o sin control; plazos vencidos.
- **Entre llamadas:** depósitos directos en Blue, cambios de precio y saltos de reloj.
- **Montos:** 1 de cada 4 veces la semilla cruda, las demás uniformes en todo el rango.
- **Métricas:** por entrada, llamadas que pasaron; comisiones, controles de `maxLtv`, migraciones; reversiones por
  motivo.

Al armarlo apareció un falso positivo del cazador: en Solidity, `P memory q = p` copia la referencia, y cambiar el
mercado de la copia cambiaba el del original (las leyes "del origen" de la migración miraban el destino).

## 5. Verificación (30-oct, forge 1.8.6 en la PC)

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
- Interés (IRM en cero) y liquidaciones en Blue.
