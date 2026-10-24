# Mapa de oportunidades (actualizado 24-oct-2026)

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
| "Rulo" local dólar oficial → USDT | cerrado: pasar dólares a USDT dentro de Argentina cuesta ~6,5% |
| Cobertura MEXC→Binance con 100 € | positiva pero mínima: el inventario se agota de un lado |

## Candidatas vivas (ordenadas por potencial)
| # | estrategia | qué se gana | escala | automatizable | estado |
|---|---|---|---|---|---|
| 1 | **Diferencia de funding entre exchanges** (corto donde paga más, largo donde paga menos; delta neutral) | hoy IRYS MEXC/OKX: +128% APR **realmente cobrado** los últimos 7 días, todos los días positivos | alta: decenas de miles de USD por moneda líquida | sí, por API (OKX, KuCoin, Bitget, Gate, Hyperliquid) | paper con cobros reales desde 24-oct |
| 2 | **Vuelta internacional** USD/EUR afuera → USDT → pesos → dólar oficial → afuera | ~+6,5% bruto, ~+5,5% neto supuesto por vuelta | limitada por tus cupos (AR 50 M ARS/mes, UE 10.000 €) | parcial (transferencias manuales) | **hipótesis a verificar** (ver abajo) |
| 3 | **Carry de funding** (contado + corto perpetuo en el mismo exchange) | JCT: 36–120% APR según el día | media | parcial (MEXC no deja abrir futuros por API) | paper desde 24-oct |
| 4 | **Merchant P2P** (publicar avisos de compra y venta) | El Dorado: 1,8% bruto entre puntas; aviso de venta cubierto en Binance: ~+0,4% por llenado | media, limitada por cuentas bancarias y KYC | poco (los avisos y los pagos son manuales) | medición en el radar |
| 5 | **Préstamo de stablecoins** (Bitfinex margin funding) | ~9–11% APR, sin riesgo de precio | muy alta | sí (Bitfinex permite automatizar préstamos) | medición en el radar |
| 6 | **Launchpools y promociones** de exchanges | APR alto con cupo por usuario: ideal para capital chico | baja (cupos) | aviso automático; participación manual | radar de eventos (MEXC, Bitget) |

## Qué necesito que verifiques vos (no se puede desde acá)
1. **Vuelta internacional**: ¿podés comprar dólares oficiales en tu banco o fintech argentina sin
   restricción por haber vendido cripto? ¿Cuánto cuesta y cuánto tarda transferir dólares de tu cuenta
   argentina a tu cuenta del exterior (N26 o Kraken)? Con esos dos datos el radar calcula el neto real.
2. **Cuentas**: para la diferencia de funding hacen falta dos exchanges con futuros por API. Hoy tenés
   MEXC (futuros sin API de órdenes) y Binance. OKX, KuCoin o Bitget (con tu residencia argentina)
   abrirían las mejores combinaciones. No abras nada todavía: primero que el paper lo confirme.

## Cómo se decide pasar a dinero real
Igual que el resto del sistema: evidencia en paper que cumpla R-15, luego 20 € reales una semana,
luego más capital. El orden probable: (1) diferencia de funding, (5) préstamo, (2) si se verifica.
