# Mapa de oportunidades (actualizado 24-oct-2026, noche)

Objetivo: hacer crecer el capital componiendo ganancias, con estrategias que **escalen** cuando el
capital crezca. Todo se mide primero con datos reales y en paper; nada pasa a dinero real sin cumplir
los criterios aprobados (docs/REGLAS.md, R-15) y sin autorización del dueño.

El informe vivo está en la rama `data`: `data/radar.md` (cada 2 h), `data/feasibility.md` (cada 6 h),
`data/live_paper_hedge.md` y el latido del PC en `pc-status`.

## Lo que ya se descartó con datos (y por qué)
| estrategia | resultado |
|---|---|
| Triangular (Binance, Kraken), cruce entre exchanges en EUR, peg de EURC | neto negativo tras comisiones |
| Comprar en una app argentina y vender en otra como tomador | −1% a −3% |
| Direccional (RSI, cruces de medias, rupturas) | sin ventaja en backtest |
| Market making simple en MEXC (0% maker) | con el modelo de llenado corregido, **negativo**: los stops se comen las ganancias; en mejora (pausa de pares tóxicos, sondeo en paralelo) |
| Cobertura MEXC→Binance con 100 € | positiva pero mínima: el inventario se agota de un lado |

## Candidatas vivas (ordenadas por potencial)
| # | estrategia | qué se gana | escala | automatizable | estado |
|---|---|---|---|---|---|
| 1 | **Diferencia de funding entre exchanges** (corto donde paga más, largo donde paga menos; delta neutral) | hoy IRYS MEXC/OKX: +128% APR **realmente cobrado** los últimos 7 días, todos los días positivos | alta: decenas de miles de USD por moneda líquida | sí, por API (OKX, KuCoin, Bitget, Gate, Hyperliquid) | paper con cobros reales desde 24-oct |
| 2 | **Rulo local**: pesos → dólar oficial (banco) → USDT pagando con dólares (Binance P2P en USD, AstroPay, Xapo) → pesos | 24-oct: +4,8% por vuelta vía Binance P2P (prima 1,8%), hasta +6,7% vía Xapo (prima 0,02%). Fiwind cobra 6,5% de prima: por esa vía no rinde | limitada por el cupo mensual de dólares de tu banco y tus límites AR | parcial: el radar avisa y las patas cripto van por API; comprar dólares y el P2P son manuales | **prueba chica manual pendiente** (ver abajo) |
| 2b | **Vuelta internacional** USD afuera → USDT → pesos → dólar oficial → giro al exterior | +6,6% bruto; con giro de 40 USD + 0,3%: +2,2% con 1.000 USD, +5,4% con 5.000 USD | alta, pero el costo fijo del giro exige montos grandes | parcial | a verificar costo del giro |
| 3 | **Carry de funding** (contado + corto perpetuo en el mismo exchange) | JCT: 36–120% APR según el día | media | parcial (MEXC no deja abrir futuros por API) | paper desde 24-oct |
| 4 | **Merchant P2P** (publicar avisos de compra y venta) | El Dorado: 1,8% bruto entre puntas; aviso de venta cubierto en Binance: ~+0,4% por llenado | media, limitada por cuentas bancarias y KYC | poco (los avisos y los pagos son manuales) | medición en el radar |
| 5 | **Préstamo de stablecoins** (Bitfinex margin funding) | ~9–11% APR, sin riesgo de precio | muy alta | sí (Bitfinex permite automatizar préstamos) | medición en el radar |
| 6 | **Launchpools y promociones** de exchanges | APR alto con cupo por usuario: ideal para capital chico | baja (cupos) | aviso automático; participación manual | radar de eventos (MEXC, Bitget) |

## Qué necesito que verifiques vos (no se puede desde acá)
1. **Rulo local** (el dueño confirmó el 24-oct que puede comprar dólares con pesos y tiene cuenta en
   dólares en un banco argentino):
   - ¿Hay **tope mensual** para comprar dólares en tu banco? ¿Alguna **restricción cruzada** por vender
     cripto o hacer MEP?
   - ¿Tu banco deja **transferir dólares a terceros** (necesario para pagar un USDT en Binance P2P en
     USD)? ¿AstroPay o Xapo aceptan cargar dólares desde tu cuenta argentina, a qué costo y en cuánto tiempo?
   - **Prueba chica manual** (p. ej. 100 USD): comprar dólares → comprar USDT pagando en dólares →
     vender el USDT por pesos (Binance USDT/ARS) → comparar los pesos finales con los iniciales.
     Si confirma ~4-5%, se automatiza lo automatizable: aviso de cuándo conviene, montos y las patas cripto.
   - Riesgos del P2P: usar contrapartes verificadas (riesgo de fondos de terceros y bloqueos bancarios).
2. **Vuelta internacional**: costo real del giro al exterior de tu banco y de la acreditación en Kraken.
2. **Cuentas**: para la diferencia de funding hacen falta dos exchanges con futuros por API. Hoy tenés
   MEXC (futuros sin API de órdenes) y Binance. OKX, KuCoin o Bitget (con tu residencia argentina)
   abrirían las mejores combinaciones. No abras nada todavía: primero que el paper lo confirme.

## Cómo se decide pasar a dinero real
Igual que el resto del sistema: evidencia en paper que cumpla R-15, luego 20 € reales una semana,
luego más capital. El orden probable: (1) diferencia de funding, (5) préstamo, (2) si se verifica.
