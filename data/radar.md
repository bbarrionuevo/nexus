# Radar de oportunidades — 2026-10-25 11:41 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0003 | okexp2p | 1,639.15 | +6.58 | **+6.54** |
| MEP (AL30) | 1,563.45 | xapo | 1.0003 | okexp2p | 1,639.15 | +4.84 | **+4.81** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1646.267, 'bid': 1637, 'variation': 0.09, 'timestamp': 1792928477}

A verificar antes de operar: cupo de dólares de tu banco, si la plataforma acepta tus dólares por transferencia y cuánto tarda, impuestos, y la normativa vigente (restricciones cruzadas).

### Costo de pasar dólares a stablecoin dentro de Argentina (la fricción que sostiene la brecha)

| plataforma | moneda | USD por unidad | prima % |
|---|---|---|---|
| xapo | USDT | 1.0003 | +0.03 |
| astropay | USDT | 1.0039 | +0.39 |
| banexcoin | USDT | 1.015 | +1.50 |
| banexcoin | USDC | 1.041 | +4.10 |
| binance | USDC | 1.0554 | +5.54 |
| binancep2p | USDT | 1.062 | +6.20 |
| decrypto | USDT | 1.0637 | +6.37 |
| fiwind | USDT | 1.065 | +6.50 |

Mejor rulo **dentro del país**: dólar oficial → USDT en xapo → pesos en okexp2p: **+6.54% por vuelta** (si alguna plataforma baja su prima a ~1-2%, este rulo se vuelve automatizable sin giros al exterior).

### Vuelta internacional (usa tus cuentas del exterior)

USD afuera → USDT en Kraken a 0.99882 (+0,26%) → vender en **okexp2p** a 1,639.15 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+6.43% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+2.03%** · 5,000 USD: **+5.23%** · 10,000 USD: **+5.63%**
Con dólar MEP (automatizable por API de un broker): bruto +4.69% · 1,000 USD: +0.29% · 5,000 USD: +3.49% · 10,000 USD: +3.89%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| kucoinp2p | 1,620.00 | 1,659.00 | +2.41 | +2.01 |
| eldoradop2p | 1,630.09 | 1,659.00 | +1.77 | +1.37 |
| bitgetp2p | 1,636.15 | 1,648.50 | +0.76 | +0.35 |
| bingxp2p | 1,638.51 | 1,648.00 | +0.58 | +0.18 |
| binancep2p | 1,637.02 | 1,645.69 | +0.53 | +0.13 |
| bybitp2p | 1,639.00 | 1,644.20 | +0.32 | -0.08 |
| okexp2p | 1,639.15 | 1,644.00 | +0.30 | -0.10 |
| lemoncashp2p | 1,638.50 | 1,640.00 | +0.09 | -0.31 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,620.00 | fiwind | 1,637.00 | +0.85 |
| kucoinp2p | aviso de VENTA en P2P, compra en app | 1,659.00 | satoshitango | 1,646.27 | +0.57 |
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,659.00 | satoshitango | 1,646.27 | +0.57 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,630.09 | fiwind | 1,637.00 | +0.22 |
| bitgetp2p | aviso de VENTA en P2P, compra en app | 1,648.50 | satoshitango | 1,646.27 | -0.06 |
| bingxp2p | aviso de VENTA en P2P, compra en app | 1,648.00 | satoshitango | 1,646.27 | -0.10 |
| bitgetp2p | aviso de COMPRA en P2P, venta en app | 1,636.15 | fiwind | 1,637.00 | -0.15 |
| binancep2p | aviso de COMPRA en P2P, venta en app | 1,637.02 | fiwind | 1,637.00 | -0.20 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 696, 'HTX': 391, 'OKX': 507, 'Gate': 1061, 'MEXC': 1080, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| CT | MEXC (-122.2) | KuCoin (-279.4) | **157.2** | +0.39 · +21 · 71% (6.8 d) | 0.16 | 0.4 | no |
| Q | Bitget (-28.7) | Gate (-164.5) | **135.8** | +0.31 · +17 · 71% (6.8 d) | 0.22 | 0.6 | sí |
| JCT | MEXC (146.7) | Bitget (11.0) | **135.8** | +1.11 · +59 · 100% (6.8 d) | 0.16 | 0.4 | sí |
| LIGHT | OKX (11.0) | KuCoin (-112.6) | **123.5** | -0.50 · -27 · 14% (6.8 d) | 0.22 | 0.7 | sí |
| F | Bitget (9.2) | KuCoin (-107.1) | **116.3** | +0.20 · +10 · 57% (6.8 d) | 0.24 | 0.8 | sí |
| LA | Bitget (-64.6) | Gate (-161.8) | **97.2** | +0.37 · +20 · 100% (6.8 d) | 0.22 | 0.8 | sí |
| DATA | OKX (11.0) | KuCoin (-70.5) | **81.5** | +0.35 · +18 · 71% (6.8 d) | 0.22 | 1.0 | sí |
| MRNA | Bitget (-105.8) | KuCoin (-184.2) | **78.4** | +0.21 · +12 · 43% (6.7 d) | 0.24 | 1.1 | sí |
| SAHARA | Bitget (11.0) | OKX (-60.6) | **71.6** | — | 0.22 | 1.1 | sí |
| ZBT | Bitget (11.0) | KuCoin (-53.2) | **64.2** | — | 0.24 | 1.4 | sí |
| ZORA | Hyperliquid (-58.3) | KuCoin (-121.1) | **62.8** | — | 0.21 | 1.2 | sí |
| BILL | KuCoin (73.6) | OKX (11.0) | **62.6** | — | 0.22 | 1.3 | sí |
| RAVE | OKX (11.0) | KuCoin (-49.7) | **60.7** | — | 0.22 | 1.3 | sí |
| MORPHO | Hyperliquid (11.0) | OKX (-49.3) | **60.3** | — | 0.19 | 1.2 | sí |
| APR | MEXC (58.3) | Bitget (11.0) | **47.3** | — | 0.16 | 1.2 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): T 723.6% (Gate/KuCoin), BTW 556.6% (OKX/Bitget), AXIS 554.4% (OKX/MEXC), IRYS 436.2% (Bitget/KuCoin), ORDER 431.9% (KuCoin/Gate), IOST 299.4% (Bitget/OKX), ERA 244.0% (Bitget/Gate), ANIME 146.5% (Bitget/Hyperliquid)

**Persistencia** (últimas 6 corridas, diferencia ≥ 20% APR): CT 6/6 (prom. 128.9%), ZORA 6/6 (prom. 76.1%), Q 5/6 (prom. 111.5%), SOON 5/6 (prom. 103.4%), BLEND 4/6 (prom. 168.9%), DOOD 4/6 (prom. 109.4%), AKE 4/6 (prom. 89.3%), CHIP 4/6 (prom. 62.9%), AAOI 4/6 (prom. 70.9%), F 4/6 (prom. 77.8%), SOXL 3/6 (prom. 80.5%), MUU 3/6 (prom. 66.1%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| KuCoin | STAR | 311.2 | 4.0 | 1,759,278 |
| KuCoin | READY | 150.2 | 4.0 | 1,796,397 |
| MEXC | JCT | 146.7 | 4.0 | 14,479,782 |
| KuCoin | JCT | 94.2 | 4.0 | 16,088,276 |
| Gate | JCT | 93.7 | 4.0 | 38,830,871 |
| KuCoin | HAJIMI | 87.6 | 4.0 | 1,782,923 |
| OKX | UP | 82.9 | 4.0 | 4,452,321 |
| KuCoin | BILL | 73.6 | 4.0 | 2,575,302 |
| OKX | TRUTH | 68.6 | 4.0 | 2,718,490 |
| Gate | AGT | 65.3 | 4.0 | 2,602,944 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.97 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.26 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.47 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

### DeFi: stablecoins en protocolos grandes (sin pérdida impermanente, TVL ≥ 20 M USD)

APY base = intereses o comisiones reales; los premios en tokens van aparte (se pueden cortar). Riesgo: contratos y depeg. Sirve para la plata que no está trabajando.

| protocolo | tipo | red | pool | TVL M USD | APY base % | premios % | APY medio 30 d % |
|---|---|---|---|---|---|---|---|
| kamino-lend | consolidado | Solana | USDC | 52.6 | 7.82 | 0.0 | 7.92 |
| morpho-blue | consolidado | Ethereum | ROXCUSDC | 35.5 | 6.52 | 1.49 | 11.23 |
| morpho-blue | consolidado | Ethereum | PENDLEUSDCHY | 33.9 | 6.28 | 0.44 | 16.67 |
| morpho-blue | consolidado | Ethereum | ROXUSDCY | 23.1 | 6.28 | 0.78 | 7.36 |
| fluid-lending | consolidado | Ethereum | USDC | 136.8 | 6.04 | 0.0 | 5.6 |
| morpho-blue | consolidado | Ethereum | STEAKCUSDC | 32.3 | 6.0 | 0.0 | 7.16 |
| axis | nuevo / sintético | Ethereum | SUSDX | 52.2 | 15.02 | 0.0 | 19.05 |
| apyx-protocol | nuevo / sintético | Ethereum | APXUSD | 152.5 | 12.98 | 0.0 | 12.97 |
| saturn | nuevo / sintético | Ethereum | SUSDAT | 45.7 | 12.9 | 0.0 | 12.72 |
| re | nuevo / sintético | Ethereum | REUSDE | 30.1 | 11.8 | 0.0 | 11.83 |
| unitas-usdu | nuevo / sintético | BSC | SUSDU | 38.8 | 11.61 | 0.0 | 11.6 |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 2 · cerradas 1 · **total -0.2250 €** (realizado -0.1400, abierto -0.0850)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| JCT:KuCoin/Bitget | 10-25 00:51 | 0.5 | 4 | +0.0704 | +0.2446 | 0.2400 | +0.0750 |
| JCT:MEXC/Bitget | 10-25 11:41 | 0.0 | 0 | +0.0000 | +0.0000 | 0.1600 | -0.1600 |
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

