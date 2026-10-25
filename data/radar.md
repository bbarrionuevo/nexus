# Radar de oportunidades — 2026-10-25 16:30 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0002 | okexp2p | 1,641.00 | +6.70 | **+6.68** |
| MEP (AL30) | 1,563.45 | xapo | 1.0002 | okexp2p | 1,641.00 | +4.96 | **+4.94** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1644.771, 'bid': 1637, 'variation': 0, 'timestamp': 1792945817}

A verificar antes de operar: cupo de dólares de tu banco, si la plataforma acepta tus dólares por transferencia y cuánto tarda, impuestos, y la normativa vigente (restricciones cruzadas).

### Costo de pasar dólares a stablecoin dentro de Argentina (la fricción que sostiene la brecha)

| plataforma | moneda | USD por unidad | prima % |
|---|---|---|---|
| xapo | USDT | 1.0002 | +0.02 |
| astropay | USDT | 1.0038 | +0.38 |
| banexcoin | USDT | 1.015 | +1.50 |
| binancep2p | USDT | 1.04 | +4.00 |
| banexcoin | USDC | 1.041 | +4.10 |
| binance | USDC | 1.0555 | +5.55 |
| decrypto | USDT | 1.0637 | +6.37 |
| fiwind | USDT | 1.065 | +6.50 |

Mejor rulo **dentro del país**: dólar oficial → USDT en xapo → pesos en okexp2p: **+6.68% por vuelta** (si alguna plataforma baja su prima a ~1-2%, este rulo se vuelve automatizable sin giros al exterior).

### Vuelta internacional (usa tus cuentas del exterior)

USD afuera → USDT en Kraken a 0.99869 (+0,26%) → vender en **okexp2p** a 1,641.00 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+6.56% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+2.16%** · 5,000 USD: **+5.36%** · 10,000 USD: **+5.76%**
Con dólar MEP (automatizable por API de un broker): bruto +4.83% · 1,000 USD: +0.43% · 5,000 USD: +3.63% · 10,000 USD: +4.03%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| eldoradop2p | 1,630.11 | 1,659.00 | +1.77 | +1.37 |
| kucoinp2p | 1,636.00 | 1,650.00 | +0.86 | +0.46 |
| lemoncashp2p | 1,638.56 | 1,645.00 | +0.39 | -0.01 |
| bingxp2p | 1,638.52 | 1,644.50 | +0.36 | -0.04 |
| binancep2p | 1,640.00 | 1,644.99 | +0.30 | -0.10 |
| bitgetp2p | 1,639.00 | 1,643.90 | +0.30 | -0.10 |
| okexp2p | 1,641.00 | 1,643.80 | +0.17 | -0.23 |
| bybitp2p | 1,639.20 | 1,640.00 | +0.05 | -0.35 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,659.00 | satoshitango | 1,644.77 | +0.67 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,630.11 | fiwind | 1,637.00 | +0.22 |
| kucoinp2p | aviso de VENTA en P2P, compra en app | 1,650.00 | satoshitango | 1,644.77 | +0.12 |
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,636.00 | fiwind | 1,637.00 | -0.14 |
| lemoncashp2p | aviso de VENTA en P2P, compra en app | 1,645.00 | satoshitango | 1,644.77 | -0.19 |
| binancep2p | aviso de VENTA en P2P, compra en app | 1,644.99 | satoshitango | 1,644.77 | -0.19 |
| bingxp2p | aviso de VENTA en P2P, compra en app | 1,644.50 | satoshitango | 1,644.77 | -0.22 |
| bitgetp2p | aviso de VENTA en P2P, compra en app | 1,643.90 | satoshitango | 1,644.77 | -0.25 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 696, 'HTX': 391, 'OKX': 507, 'Gate': 1061, 'MEXC': 1079, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| DNA | OKX (-1.0) | Gate (-200.4) | **199.3** | +0.29 · +15 · 71% (6.8 d) | 0.2 | 0.4 | sí |
| CAP | MEXC (167.3) | KuCoin (11.0) | **156.4** | +0.24 · +13 · 86% (6.8 d) | 0.16 | 0.4 | sí |
| JCT | Gate (157.0) | Bitget (11.0) | **146.1** | +0.91 · +48 · 100% (6.8 d) | 0.22 | 0.5 | sí |
| CT | MEXC (-84.2) | Gate (-220.1) | **135.9** | +0.67 · +36 · 86% (6.8 d) | 0.14 | 0.4 | no |
| RAVE | OKX (11.0) | KuCoin (-107.5) | **118.5** | -0.14 · -7 · 29% (6.8 d) | 0.22 | 0.7 | sí |
| LA | OKX (-93.8) | Gate (-184.4) | **90.6** | +0.06 · +3 · 100% (6.8 d) | 0.2 | 0.8 | sí |
| AAOI | OKX (97.8) | Gate (9.5) | **88.3** | +0.21 · +12 · 100% (6.7 d) | 0.2 | 0.8 | sí |
| UNITREE | Bitget (33.5) | Gate (-49.3) | **82.8** | -1.56 · -83 · 29% (6.8 d) | 0.22 | 1.0 | sí |
| APR | MEXC (86.3) | Bitget (11.0) | **75.3** | — | 0.16 | 0.8 | sí |
| ZORA | OKX (-12.9) | KuCoin (-83.0) | **70.1** | — | 0.22 | 1.1 | sí |
| ZHIPU | OKX (125.1) | Gate (56.0) | **69.2** | — | 0.2 | 1.1 | sí |
| SNXX | MEXC (94.5) | Gate (30.0) | **64.5** | — | 0.14 | 0.8 | no |
| SOXL | OKX (60.6) | Gate (0.0) | **60.6** | — | 0.2 | 1.2 | sí |
| KORU | OKX (57.8) | Gate (0.0) | **57.8** | — | 0.2 | 1.3 | sí |
| XMR | Hyperliquid (68.4) | KuCoin (11.0) | **57.5** | — | 0.21 | 1.3 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): HOOKED 2127.4% (MEXC/Gate), AXIS 586.9% (Gate/MEXC), BTW 576.0% (Gate/MEXC), T 465.8% (Bitget/KuCoin), ANIME 283.2% (Bitget/Gate), ORDER 247.0% (MEXC/Gate), BIRB 241.1% (KuCoin/Bitget), IRYS 224.9% (Gate/KuCoin)

**Persistencia** (últimas 7 corridas, diferencia ≥ 20% APR): CT 7/7 (prom. 129.9%), ZORA 7/7 (prom. 75.2%), Q 5/7 (prom. 111.5%), SOON 5/7 (prom. 103.4%), AAOI 5/7 (prom. 74.4%), BLEND 4/7 (prom. 168.9%), DOOD 4/7 (prom. 109.4%), SOXL 4/7 (prom. 75.5%), AKE 4/7 (prom. 89.3%), CHIP 4/7 (prom. 62.9%), XMR 4/7 (prom. 65.0%), F 4/7 (prom. 77.8%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| KuCoin | STAR | 236.3 | 4.0 | 1,784,320 |
| OKX | UP | 175.2 | 4.0 | 5,630,692 |
| MEXC | CAP | 167.3 | 4.0 | 3,703,437 |
| KuCoin | PRL | 157.9 | 4.0 | 1,858,288 |
| Gate | JCT | 157.0 | 4.0 | 31,630,520 |
| KuCoin | READY | 150.0 | 4.0 | 1,782,030 |
| KuCoin | JCT | 147.8 | 4.0 | 11,663,957 |
| KuCoin | NEX | 136.7 | 4.0 | 1,383,045 |
| KuCoin | KCS | 130.5 | 8.0 | 20,617,129 |
| MEXC | JCT | 130.3 | 4.0 | 11,988,016 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.96 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.2 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.49 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

### DeFi: stablecoins en protocolos grandes (sin pérdida impermanente, TVL ≥ 20 M USD)

APY base = intereses o comisiones reales; los premios en tokens van aparte (se pueden cortar). Riesgo: contratos y depeg. Sirve para la plata que no está trabajando.

| protocolo | tipo | red | pool | TVL M USD | APY base % | premios % | APY medio 30 d % |
|---|---|---|---|---|---|---|---|
| morpho-blue | consolidado | Ethereum | FCUSDT | 43.7 | 9.77 | 6.19 | 12.45 |
| kamino-lend | consolidado | Solana | USDC | 53.0 | 7.76 | 0.0 | 7.92 |
| morpho-blue | consolidado | Ethereum | PENDLEUSDCHY | 33.9 | 6.24 | 0.44 | 16.48 |
| fluid-lending | consolidado | Ethereum | USDC | 137.1 | 6.06 | 0.0 | 5.61 |
| morpho-blue | consolidado | Ethereum | STEAKCUSDC | 32.3 | 6.0 | 0.0 | 7.15 |
| morpho-blue | consolidado | Ethereum | ROXUSDCY | 23.2 | 5.86 | 1.28 | 7.36 |
| axis | nuevo / sintético | Ethereum | SUSDX | 52.2 | 15.07 | 0.0 | 19.03 |
| apyx-protocol | nuevo / sintético | Ethereum | APXUSD | 152.6 | 12.98 | 0.0 | 12.97 |
| saturn | nuevo / sintético | Ethereum | SUSDAT | 45.7 | 12.9 | 0.0 | 12.71 |
| re | nuevo / sintético | Ethereum | REUSDE | 30.1 | 11.8 | 0.0 | 11.83 |
| unitas-usdu | nuevo / sintético | BSC | SUSDU | 38.8 | 11.61 | 0.0 | 11.6 |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 3 · cerradas 1 · **total -0.2659 €** (realizado -0.1400, abierto -0.1259)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| JCT:KuCoin/Bitget | 10-25 00:51 | 0.7 | 8 | +0.1147 | +0.2446 | 0.2400 | +0.1194 |
| JCT:MEXC/Bitget | 10-25 11:41 | 0.2 | 4 | +0.0547 | +0.0000 | 0.1600 | -0.1053 |
| CT:MEXC/Gate | 10-25 16:31 | 0.0 | 0 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

