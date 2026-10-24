# Radar de oportunidades — 2026-10-24 22:47 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0002 | okexp2p | 1,641.00 | +6.70 | **+6.68** |
| MEP (AL30) | 1,563.45 | xapo | 1.0002 | okexp2p | 1,641.00 | +4.96 | **+4.94** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1650.787, 'bid': 1637, 'variation': 0.37, 'timestamp': 1792881974}

A verificar antes de operar: cupo de dólares de tu banco, si la plataforma acepta tus dólares por transferencia y cuánto tarda, impuestos, y la normativa vigente (restricciones cruzadas).

### Vuelta internacional (usa tus cuentas del exterior)

USD afuera → USDT en Kraken a 0.99873 (+0,26% comisión) → vender en **okexp2p** a 1,641.00 ARS → dólar oficial en **prex** a 1,538.00 → transferir al exterior (supuesto 1.0%): **+6.56% bruto · +5.46% neto por vuelta**.

Es la hipótesis más grande del radar y la de más fricción: verificar que puedas comprar dólares oficiales sin restricción cruzada por vender cripto, el costo y la demora real de transferir dólares al exterior, y tus propios límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| eldoradop2p | 1,630.82 | 1,660.00 | +1.79 | +1.39 |
| kucoinp2p | 1,636.00 | 1,647.00 | +0.67 | +0.27 |
| lemoncashp2p | 1,637.15 | 1,646.00 | +0.54 | +0.14 |
| binancep2p | 1,637.11 | 1,644.14 | +0.43 | +0.03 |
| bitgetp2p | 1,639.05 | 1,645.00 | +0.36 | -0.04 |
| bingxp2p | 1,639.01 | 1,643.40 | +0.27 | -0.13 |
| okexp2p | 1,641.00 | 1,644.45 | +0.21 | -0.19 |
| bybitp2p | 1,639.66 | 1,642.00 | +0.14 | -0.26 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,660.00 | bitsoalpha | 1,650.71 | +0.36 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,630.82 | fiwind | 1,637.00 | +0.18 |
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,636.00 | fiwind | 1,637.00 | -0.14 |
| binancep2p | aviso de COMPRA en P2P, venta en app | 1,637.11 | fiwind | 1,637.00 | -0.21 |
| lemoncashp2p | aviso de COMPRA en P2P, venta en app | 1,637.15 | fiwind | 1,637.00 | -0.21 |
| bingxp2p | aviso de COMPRA en P2P, venta en app | 1,639.01 | fiwind | 1,637.00 | -0.32 |
| bitgetp2p | aviso de COMPRA en P2P, venta en app | 1,639.05 | fiwind | 1,637.00 | -0.33 |
| bybitp2p | aviso de COMPRA en P2P, venta en app | 1,639.66 | fiwind | 1,637.00 | -0.36 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 696, 'HTX': 391, 'OKX': 507, 'Gate': 1061, 'MEXC': 1088, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| PROS | KuCoin (220.5) | OKX (11.0) | **209.6** | +0.10 · +5 · 71% (6.8 d) | 0.22 | 0.4 | sí |
| BLEND | OKX (-46.8) | KuCoin (-240.5) | **193.6** | +0.08 · +4 · 29% (6.8 d) | 0.22 | 0.4 | sí |
| IRYS | MEXC (10.5) | OKX (-147.3) | **157.8** | +2.39 · +128 · 100% (6.8 d) | 0.14 | 0.3 | sí |
| Q | Bitget (11.0) | KuCoin (-131.2) | **142.1** | -0.36 · -20 · 14% (6.8 d) | 0.24 | 0.6 | sí |
| DOOD | OKX (-21.6) | Gate (-146.9) | **125.3** | +0.38 · +20 · 71% (6.8 d) | 0.2 | 0.6 | sí |
| CT | MEXC (3.8) | KuCoin (-107.3) | **111.1** | +0.32 · +17 · 86% (6.8 d) | 0.16 | 0.5 | no |
| SOON | OKX (110.1) | Bitget (11.0) | **99.2** | +0.22 · +12 · 100% (6.8 d) | 0.22 | 0.8 | sí |
| SOXL | OKX (100.5) | Gate (6.1) | **94.4** | +0.48 · +26 · 86% (6.7 d) | 0.2 | 0.8 | sí |
| AKE | KuCoin (101.6) | Bitget (11.0) | **90.7** | — | 0.24 | 1.0 | sí |
| ZORA | OKX (-137.7) | Hyperliquid (-223.8) | **86.1** | — | 0.19 | 0.8 | sí |
| SOXS | Gate (-7.8) | MEXC (-90.3) | **82.6** | — | 0.14 | 0.6 | sí |
| MUU | MEXC (74.4) | Gate (0.0) | **74.4** | — | 0.14 | 0.7 | no |
| CHIP | Bitget (11.0) | OKX (-57.6) | **68.6** | — | 0.22 | 1.2 | sí |
| AAOI | OKX (75.7) | Bitget (7.2) | **68.5** | — | 0.22 | 1.2 | sí |
| XMR | Hyperliquid (75.2) | KuCoin (11.0) | **64.2** | — | 0.21 | 1.2 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): AXIS 1353.9% (KuCoin/OKX), ANIME 1259.0% (OKX/Hyperliquid), BTW 597.2% (KuCoin/OKX), ORDER 426.0% (OKX/Gate), BIRB 360.9% (KuCoin/Gate), JCT 358.7% (KuCoin/Bitget), LA 324.3% (Bitget/Gate), BMT 275.9% (MEXC/Gate)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| KuCoin | JCT | 369.7 | 4.0 | 10,363,585 |
| MEXC | JCT | 246.2 | 4.0 | 9,133,952 |
| KuCoin | PROS | 220.5 | 4.0 | 2,122,937 |
| KuCoin | READY | 175.2 | 4.0 | 1,839,586 |
| OKX | UP | 173.4 | 4.0 | 1,128,909 |
| OKX | SOON | 110.1 | 4.0 | 6,071,146 |
| KuCoin | AKE | 101.6 | 4.0 | 2,084,829 |
| OKX | SOXL | 100.5 | 8.0 | 87,510,058 |
| Gate | JCT | 92.2 | 4.0 | 22,680,546 |
| MEXC | SOXL | 79.9 | 8.0 | 19,281,262 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.97 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.46 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.45 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 1 · cerradas 0 · **total -0.1400 €** (realizado +0.0000, abierto -0.1400)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| IRYS:MEXC/OKX | 10-24 22:47 | 0.0 | 0 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

