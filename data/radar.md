# Radar de oportunidades — 2026-10-25 00:51 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0002 | okexp2p | 1,641.00 | +6.70 | **+6.68** |
| MEP (AL30) | 1,563.45 | xapo | 1.0002 | okexp2p | 1,641.00 | +4.96 | **+4.94** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1648.995, 'bid': 1637, 'variation': 0.26, 'timestamp': 1792889416}

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

USD afuera → USDT en Kraken a 0.99867 (+0,26%) → vender en **okexp2p** a 1,641.00 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+6.56% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+2.16%** · 5,000 USD: **+5.36%** · 10,000 USD: **+5.76%**
Con dólar MEP (automatizable por API de un broker): bruto +4.83% · 1,000 USD: +0.43% · 5,000 USD: +3.63% · 10,000 USD: +4.03%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| eldoradop2p | 1,630.00 | 1,658.50 | +1.75 | +1.35 |
| kucoinp2p | 1,636.00 | 1,646.00 | +0.61 | +0.21 |
| lemoncashp2p | 1,640.00 | 1,649.00 | +0.55 | +0.15 |
| bitgetp2p | 1,640.30 | 1,647.99 | +0.47 | +0.07 |
| binancep2p | 1,640.00 | 1,646.00 | +0.37 | -0.03 |
| bingxp2p | 1,639.69 | 1,643.20 | +0.21 | -0.19 |
| okexp2p | 1,641.00 | 1,644.00 | +0.18 | -0.22 |
| bybitp2p | 1,639.51 | 1,641.00 | +0.09 | -0.31 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,658.50 | bitsoalpha | 1,648.99 | +0.38 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,630.00 | fiwind | 1,637.00 | +0.23 |
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,636.00 | fiwind | 1,637.00 | -0.14 |
| lemoncashp2p | aviso de VENTA en P2P, compra en app | 1,649.00 | bitsoalpha | 1,648.99 | -0.20 |
| bitgetp2p | aviso de VENTA en P2P, compra en app | 1,647.99 | bitsoalpha | 1,648.99 | -0.26 |
| bybitp2p | aviso de COMPRA en P2P, venta en app | 1,639.51 | fiwind | 1,637.00 | -0.35 |
| bingxp2p | aviso de COMPRA en P2P, venta en app | 1,639.69 | fiwind | 1,637.00 | -0.36 |
| binancep2p | aviso de VENTA en P2P, compra en app | 1,646.00 | bitsoalpha | 1,648.99 | -0.38 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 696, 'HTX': 391, 'OKX': 507, 'Gate': 1061, 'MEXC': 1088, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| JCT | KuCoin (294.3) | Bitget (11.0) | **283.4** | +1.73 · +92 · 100% (6.8 d) | 0.24 | 0.3 | sí |
| BLEND | OKX (-120.9) | KuCoin (-259.7) | **138.8** | +0.12 · +7 · 43% (6.8 d) | 0.22 | 0.6 | sí |
| CT | OKX (-6.2) | KuCoin (-131.2) | **124.9** | -0.59 · -32 · 43% (6.8 d) | 0.22 | 0.6 | sí |
| DOOD | OKX (-22.7) | Gate (-128.8) | **106.1** | +0.42 · +23 · 71% (6.7 d) | 0.2 | 0.7 | sí |
| SOON | OKX (111.7) | Bitget (11.0) | **100.7** | +0.26 · +14 · 100% (6.8 d) | 0.22 | 0.8 | sí |
| PONS | Gate (103.1) | MEXC (5.5) | **97.7** | -0.21 · -11 · 43% (6.8 d) | 0.14 | 0.5 | no |
| AKE | KuCoin (99.2) | Bitget (11.0) | **88.3** | +0.27 · +14 · 57% (6.8 d) | 0.24 | 1.0 | sí |
| AAOI | OKX (77.0) | Bitget (2.4) | **74.6** | +0.13 · +7 · 57% (6.7 d) | 0.22 | 1.1 | sí |
| F | Bitget (11.0) | KuCoin (-60.2) | **71.2** | — | 0.24 | 1.2 | sí |
| AGT | Gate (195.6) | MEXC (126.4) | **69.2** | — | 0.14 | 0.7 | sí |
| ZORA | OKX (-145.7) | KuCoin (-206.5) | **60.8** | — | 0.22 | 1.3 | sí |
| BIGTIME | Bitget (11.0) | OKX (-48.6) | **59.6** | — | 0.22 | 1.3 | sí |
| CHIP | Bitget (11.0) | OKX (-45.7) | **56.6** | — | 0.22 | 1.4 | sí |
| XMR | Hyperliquid (62.6) | KuCoin (11.0) | **51.6** | — | 0.21 | 1.5 | sí |
| COIN | OKX (50.4) | Bitget (0.0) | **50.4** | — | 0.22 | 1.6 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): T 2856.9% (Bitget/Gate), ARK 669.3% (MEXC/Gate), IRYS 634.5% (OKX/KuCoin), ALT 597.2% (Bitget/Gate), BIRB 560.9% (Bitget/Gate), ORDER 528.4% (OKX/MEXC), AXIS 485.3% (MEXC/OKX), ANIME 455.7% (Gate/Bitget)

**Persistencia** (últimas 4 corridas, diferencia ≥ 20% APR): BLEND 4/4 (prom. 168.9%), DOOD 4/4 (prom. 109.4%), CT 4/4 (prom. 115.8%), SOON 4/4 (prom. 100.3%), AKE 4/4 (prom. 89.3%), ZORA 4/4 (prom. 74.3%), CHIP 4/4 (prom. 62.9%), AAOI 4/4 (prom. 70.9%), Q 3/4 (prom. 114.4%), SOXL 3/4 (prom. 80.5%), MUU 3/4 (prom. 66.1%), F 3/4 (prom. 65.0%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| KuCoin | JCT | 294.3 | 4.0 | 11,436,388 |
| KuCoin | READY | 267.4 | 4.0 | 1,828,344 |
| MEXC | JCT | 237.6 | 4.0 | 9,600,531 |
| Gate | AGT | 195.6 | 4.0 | 4,633,938 |
| KuCoin | AGT | 187.2 | 4.0 | 2,808,824 |
| Gate | JCT | 168.6 | 4.0 | 24,298,297 |
| MEXC | AGT | 126.4 | 4.0 | 6,357,813 |
| OKX | SOON | 111.7 | 4.0 | 5,853,782 |
| KuCoin | STAR | 106.2 | 4.0 | 1,629,982 |
| Gate | PONS | 103.1 | 4.0 | 1,471,229 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.97 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.43 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.49 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

### DeFi: stablecoins en protocolos grandes (sin pérdida impermanente, TVL ≥ 20 M USD)

APY base = intereses o comisiones reales; los premios en tokens van aparte (se pueden cortar). Riesgo: contratos y depeg. Sirve para la plata que no está trabajando.

| protocolo | red | pool | TVL M USD | APY base % | premios % | APY medio 30 d % |
|---|---|---|---|---|---|---|
| axis | Ethereum | SUSDX | 52.1 | 15.03 | 0.0 | 19.09 |
| apyx-protocol | Ethereum | APXUSD | 152.3 | 12.98 | 0.0 | 12.97 |
| saturn | Ethereum | SUSDAT | 45.7 | 12.9 | 0.0 | 12.74 |
| aave-v3 | Ethereum | USDC | 54.8 | 12.32 | 1.77 | 5.99 |
| re | Ethereum | REUSDE | 30.1 | 11.8 | 0.0 | 11.84 |
| unitas-usdu | BSC | SUSDU | 38.8 | 11.58 | 0.0 | 11.6 |
| tori-finance | Ethereum | STRUSD | 63.5 | 10.0 | 0.0 | 10.44 |
| midas-rwa | Ethereum | USDC | 29.0 | 8.17 | 0.0 | 7.58 |
| pareto-credit | Ethereum | USDC | 131.5 | 8.06 | 0.0 | 8.01 |
| bitway-earn | BSC | USDT | 22.0 | 8.0 | 0.0 | 8.0 |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 1 · cerradas 1 · **total -0.3800 €** (realizado -0.1400, abierto -0.2400)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| JCT:KuCoin/Bitget | 10-25 00:51 | 0.0 | 0 | +0.0000 | +0.0000 | 0.2400 | -0.2400 |
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

