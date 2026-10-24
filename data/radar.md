# Radar de oportunidades — 2026-10-24 23:01 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0002 | okexp2p | 1,641.00 | +6.70 | **+6.68** |
| MEP (AL30) | 1,563.45 | xapo | 1.0002 | okexp2p | 1,641.00 | +4.96 | **+4.94** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1649.043, 'bid': 1637, 'variation': 0.26, 'timestamp': 1792882877}

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

USD afuera → USDT en Kraken a 0.9987 (+0,26%) → vender en **okexp2p** a 1,641.00 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+6.56% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+2.16%** · 5,000 USD: **+5.36%** · 10,000 USD: **+5.76%**
Con dólar MEP (automatizable por API de un broker): bruto +4.82% · 1,000 USD: +0.42% · 5,000 USD: +3.62% · 10,000 USD: +4.02%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| eldoradop2p | 1,629.85 | 1,660.00 | +1.85 | +1.45 |
| kucoinp2p | 1,636.00 | 1,647.00 | +0.67 | +0.27 |
| lemoncashp2p | 1,637.15 | 1,647.99 | +0.66 | +0.26 |
| binancep2p | 1,637.80 | 1,645.30 | +0.46 | +0.06 |
| bitgetp2p | 1,639.10 | 1,645.00 | +0.36 | -0.04 |
| bingxp2p | 1,639.00 | 1,643.40 | +0.27 | -0.13 |
| okexp2p | 1,641.00 | 1,644.35 | +0.20 | -0.20 |
| bybitp2p | 1,638.72 | 1,642.00 | +0.20 | -0.20 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,660.00 | bitsoalpha | 1,649.04 | +0.47 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,629.85 | fiwind | 1,637.00 | +0.24 |
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,636.00 | fiwind | 1,637.00 | -0.14 |
| lemoncashp2p | aviso de COMPRA en P2P, venta en app | 1,637.15 | fiwind | 1,637.00 | -0.21 |
| binancep2p | aviso de COMPRA en P2P, venta en app | 1,637.80 | fiwind | 1,637.00 | -0.25 |
| lemoncashp2p | aviso de VENTA en P2P, compra en app | 1,647.99 | bitsoalpha | 1,649.04 | -0.26 |
| bybitp2p | aviso de COMPRA en P2P, venta en app | 1,638.72 | fiwind | 1,637.00 | -0.30 |
| bingxp2p | aviso de COMPRA en P2P, venta en app | 1,639.00 | fiwind | 1,637.00 | -0.32 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 696, 'HTX': 391, 'OKX': 507, 'Gate': 1061, 'MEXC': 1088, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| BLEND | OKX (-50.6) | KuCoin (-246.8) | **196.2** | +0.08 · +4 · 29% (6.8 d) | 0.22 | 0.4 | sí |
| IRYS | MEXC (10.5) | KuCoin (-178.7) | **189.2** | -0.28 · -15 · 29% (7.0 d) | 0.16 | 0.3 | sí |
| PROS | KuCoin (196.4) | OKX (11.0) | **185.5** | +0.10 · +5 · 71% (6.8 d) | 0.22 | 0.4 | sí |
| Q | Bitget (11.0) | KuCoin (-121.1) | **132.1** | -0.36 · -20 · 14% (6.8 d) | 0.24 | 0.7 | sí |
| DOOD | OKX (-26.4) | Gate (-151.8) | **125.4** | +0.38 · +20 · 71% (6.8 d) | 0.2 | 0.6 | sí |
| CT | MEXC (2.6) | KuCoin (-113.9) | **116.5** | +0.32 · +17 · 86% (6.8 d) | 0.16 | 0.5 | no |
| SOON | OKX (111.9) | Bitget (11.0) | **101.0** | +0.22 · +12 · 100% (6.8 d) | 0.22 | 0.8 | sí |
| AKE | KuCoin (105.6) | Bitget (11.0) | **94.6** | +0.20 · +11 · 43% (6.8 d) | 0.24 | 0.9 | sí |
| SOXL | OKX (91.4) | Gate (3.4) | **88.0** | — | 0.2 | 0.8 | sí |
| ZORA | OKX (-141.9) | KuCoin (-221.6) | **79.8** | — | 0.22 | 1.0 | sí |
| SOXS | Gate (-4.9) | MEXC (-82.3) | **77.4** | — | 0.14 | 0.7 | sí |
| CHIP | Bitget (11.0) | OKX (-59.8) | **70.8** | — | 0.22 | 1.1 | sí |
| MUU | MEXC (70.7) | Gate (0.0) | **70.7** | — | 0.14 | 0.7 | no |
| AAOI | OKX (77.8) | Bitget (7.7) | **70.1** | — | 0.22 | 1.1 | sí |
| F | Bitget (11.0) | KuCoin (-48.6) | **59.6** | — | 0.24 | 1.5 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): AXIS 1458.3% (KuCoin/OKX), ORDER 1446.3% (MEXC/Gate), ANIME 1232.5% (OKX/Hyperliquid), BMT 969.7% (MEXC/Gate), BTW 490.8% (KuCoin/OKX), ARK 387.2% (KuCoin/Gate), JCT 357.8% (KuCoin/Bitget), BIRB 347.1% (KuCoin/Bitget)

**Persistencia** (últimas 2 corridas, diferencia ≥ 20% APR): PROS 2/2 (prom. 197.6%), BLEND 2/2 (prom. 194.9%), IRYS 2/2 (prom. 173.5%), Q 2/2 (prom. 137.1%), DOOD 2/2 (prom. 125.3%), CT 2/2 (prom. 113.8%), SOON 2/2 (prom. 100.1%), SOXL 2/2 (prom. 91.2%), AKE 2/2 (prom. 92.7%), ZORA 2/2 (prom. 82.9%), SOXS 2/2 (prom. 80.0%), MUU 2/2 (prom. 72.6%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| KuCoin | JCT | 368.8 | 4.0 | 10,381,380 |
| MEXC | JCT | 244.6 | 4.0 | 9,111,558 |
| KuCoin | PROS | 196.4 | 4.0 | 2,118,939 |
| KuCoin | READY | 193.6 | 4.0 | 1,839,155 |
| OKX | UP | 183.4 | 4.0 | 1,114,610 |
| OKX | SOON | 111.9 | 4.0 | 5,948,997 |
| KuCoin | AKE | 105.6 | 4.0 | 2,017,805 |
| OKX | SOXL | 91.4 | 8.0 | 83,814,338 |
| Gate | JCT | 89.4 | 4.0 | 22,775,954 |
| OKX | AAOI | 77.8 | 8.0 | 2,968,417 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.97 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.43 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.45 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 0 · cerradas 1 · **total -0.1400 €** (realizado -0.1400, abierto +0.0000)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

