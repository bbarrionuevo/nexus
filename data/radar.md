# Radar de oportunidades — 2026-10-25 00:13 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0002 | okexp2p | 1,641.00 | +6.70 | **+6.68** |
| MEP (AL30) | 1,563.45 | xapo | 1.0002 | okexp2p | 1,641.00 | +4.96 | **+4.94** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1648.946, 'bid': 1637, 'variation': 0.26, 'timestamp': 1792887136}

A verificar antes de operar: cupo de dólares de tu banco, si la plataforma acepta tus dólares por transferencia y cuánto tarda, impuestos, y la normativa vigente (restricciones cruzadas).

### Costo de pasar dólares a stablecoin dentro de Argentina (la fricción que sostiene la brecha)

| plataforma | moneda | USD por unidad | prima % |
|---|---|---|---|
| xapo | USDT | 1.0002 | +0.02 |
| astropay | USDT | 1.0038 | +0.38 |
| banexcoin | USDT | 1.015 | +1.50 |
| binancep2p | USDT | 1.018 | +1.80 |
| banexcoin | USDC | 1.041 | +4.10 |
| binance | USDC | 1.0555 | +5.55 |
| decrypto | USDT | 1.0637 | +6.37 |
| fiwind | USDT | 1.065 | +6.50 |

Mejor rulo **dentro del país**: dólar oficial → USDT en xapo → pesos en okexp2p: **+6.68% por vuelta** (si alguna plataforma baja su prima a ~1-2%, este rulo se vuelve automatizable sin giros al exterior).

### Vuelta internacional (usa tus cuentas del exterior)

USD afuera → USDT en Kraken a 0.99868 (+0,26%) → vender en **okexp2p** a 1,641.00 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+6.56% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+2.16%** · 5,000 USD: **+5.36%** · 10,000 USD: **+5.76%**
Con dólar MEP (automatizable por API de un broker): bruto +4.83% · 1,000 USD: +0.43% · 5,000 USD: +3.63% · 10,000 USD: +4.03%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| eldoradop2p | 1,630.00 | 1,659.30 | +1.80 | +1.40 |
| kucoinp2p | 1,636.00 | 1,646.00 | +0.61 | +0.21 |
| lemoncashp2p | 1,640.00 | 1,649.00 | +0.55 | +0.15 |
| bitgetp2p | 1,640.21 | 1,647.39 | +0.44 | +0.04 |
| binancep2p | 1,640.50 | 1,645.50 | +0.30 | -0.10 |
| bingxp2p | 1,639.51 | 1,643.20 | +0.23 | -0.17 |
| okexp2p | 1,641.00 | 1,644.00 | +0.18 | -0.22 |
| bybitp2p | 1,639.55 | 1,642.00 | +0.15 | -0.25 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,659.30 | bitsoalpha | 1,648.94 | +0.43 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,630.00 | fiwind | 1,637.00 | +0.23 |
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,636.00 | fiwind | 1,637.00 | -0.14 |
| lemoncashp2p | aviso de VENTA en P2P, compra en app | 1,649.00 | bitsoalpha | 1,648.94 | -0.20 |
| bitgetp2p | aviso de VENTA en P2P, compra en app | 1,647.39 | bitsoalpha | 1,648.94 | -0.29 |
| bingxp2p | aviso de COMPRA en P2P, venta en app | 1,639.51 | fiwind | 1,637.00 | -0.35 |
| bybitp2p | aviso de COMPRA en P2P, venta en app | 1,639.55 | fiwind | 1,637.00 | -0.36 |
| kucoinp2p | aviso de VENTA en P2P, compra en app | 1,646.00 | bitsoalpha | 1,648.94 | -0.38 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 696, 'HTX': 391, 'OKX': 507, 'Gate': 1061, 'MEXC': 1088, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| PONS | Gate (159.0) | MEXC (5.5) | **153.5** | -0.21 · -11 · 43% (6.8 d) | 0.14 | 0.3 | no |
| BLEND | OKX (-51.3) | KuCoin (-198.2) | **146.9** | +0.12 · +7 · 43% (6.8 d) | 0.22 | 0.5 | sí |
| CT | MEXC (-8.1) | KuCoin (-118.9) | **110.8** | +0.37 · +20 · 86% (6.8 d) | 0.16 | 0.5 | no |
| SOON | OKX (111.3) | Bitget (11.0) | **100.4** | +0.26 · +14 · 100% (6.8 d) | 0.22 | 0.8 | sí |
| DOS | Bitget (11.0) | Gate (-85.2) | **96.1** | -0.02 · -1 · 57% (6.8 d) | 0.22 | 0.8 | sí |
| AKE | KuCoin (94.6) | Bitget (11.0) | **83.7** | +0.27 · +14 · 57% (6.8 d) | 0.24 | 1.0 | sí |
| DOOD | OKX (-33.0) | Gate (-113.9) | **80.9** | +0.42 · +23 · 71% (6.7 d) | 0.2 | 0.9 | sí |
| ZORA | OKX (-134.5) | KuCoin (-205.0) | **70.5** | -0.08 · -4 · 14% (6.8 d) | 0.22 | 1.1 | sí |
| AAOI | OKX (75.9) | Gate (5.5) | **70.5** | — | 0.2 | 1.0 | sí |
| Q | Bitget (11.0) | KuCoin (-58.0) | **69.0** | — | 0.24 | 1.3 | sí |
| F | Bitget (11.0) | KuCoin (-53.2) | **64.2** | — | 0.24 | 1.4 | sí |
| SOXL | OKX (59.1) | Gate (0.0) | **59.1** | — | 0.2 | 1.2 | sí |
| CHIP | Bitget (11.0) | OKX (-44.7) | **55.7** | — | 0.22 | 1.4 | sí |
| MUU | MEXC (53.3) | Gate (0.0) | **53.3** | — | 0.14 | 1.0 | no |
| COIN | OKX (52.8) | Bitget (0.0) | **52.8** | — | 0.22 | 1.5 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): AXIS 2212.3% (Bitget/MEXC), BIRB 1889.5% (KuCoin/Gate), ANIME 1206.5% (KuCoin/Hyperliquid), LA 1158.9% (Bitget/Gate), IN 1092.6% (MEXC/Gate), ORDER 895.3% (MEXC/Gate), TREE 494.1% (Bitget/Gate), ALT 402.5% (Bitget/Gate)

**Persistencia** (últimas 3 corridas, diferencia ≥ 20% APR): BLEND 3/3 (prom. 178.9%), Q 3/3 (prom. 114.4%), DOOD 3/3 (prom. 110.5%), CT 3/3 (prom. 112.8%), SOON 3/3 (prom. 100.2%), SOXL 3/3 (prom. 80.5%), AKE 3/3 (prom. 89.7%), ZORA 3/3 (prom. 78.8%), MUU 3/3 (prom. 66.1%), CHIP 3/3 (prom. 65.0%), AAOI 3/3 (prom. 69.7%), PROS 2/3 (prom. 197.6%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| KuCoin | JCT | 324.1 | 4.0 | 11,199,958 |
| MEXC | JCT | 246.2 | 4.0 | 9,433,591 |
| KuCoin | READY | 186.6 | 4.0 | 1,828,342 |
| Gate | PONS | 159.0 | 4.0 | 1,462,617 |
| OKX | UP | 141.4 | 4.0 | 1,059,478 |
| KuCoin | AGT | 120.0 | 4.0 | 2,936,986 |
| KuCoin | STAR | 116.9 | 4.0 | 1,629,714 |
| OKX | SOON | 111.3 | 4.0 | 5,897,688 |
| MEXC | AGT | 110.6 | 4.0 | 6,229,470 |
| KuCoin | NES | 103.4 | 4.0 | 1,855,635 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.97 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.43 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.55 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 0 · cerradas 1 · **total -0.1400 €** (realizado -0.1400, abierto +0.0000)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

