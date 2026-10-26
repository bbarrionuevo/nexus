# Radar de oportunidades — 2026-10-26 00:26 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0002 | okexp2p | 1,640.20 | +6.64 | **+6.62** |
| MEP (AL30) | 1,563.45 | xapo | 1.0002 | okexp2p | 1,640.20 | +4.91 | **+4.89** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1645.91, 'bid': 1638.903, 'variation': 0.07, 'timestamp': 1792974376}

A verificar antes de operar: cupo de dólares de tu banco, si la plataforma acepta tus dólares por transferencia y cuánto tarda, impuestos, y la normativa vigente (restricciones cruzadas).

### Costo de pasar dólares a stablecoin dentro de Argentina (la fricción que sostiene la brecha)

| plataforma | moneda | USD por unidad | prima % |
|---|---|---|---|
| xapo | USDT | 1.0002 | +0.02 |
| astropay | USDT | 1.0038 | +0.38 |
| banexcoin | USDT | 1.015 | +1.50 |
| binancep2p | USDT | 1.018 | +1.80 |
| banexcoin | USDC | 1.041 | +4.10 |
| binance | USDC | 1.0554 | +5.54 |
| decrypto | USDT | 1.0637 | +6.37 |
| fiwind | USDT | 1.065 | +6.50 |

Mejor rulo **dentro del país**: dólar oficial → USDT en xapo → pesos en okexp2p: **+6.62% por vuelta** (si alguna plataforma baja su prima a ~1-2%, este rulo se vuelve automatizable sin giros al exterior).

### Vuelta internacional (usa tus cuentas del exterior)

USD afuera → USDT en Kraken a 0.9987 (+0,26%) → vender en **okexp2p** a 1,640.20 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+6.51% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+2.11%** · 5,000 USD: **+5.31%** · 10,000 USD: **+5.71%**
Con dólar MEP (automatizable por API de un broker): bruto +4.77% · 1,000 USD: +0.37% · 5,000 USD: +3.57% · 10,000 USD: +3.97%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| eldoradop2p | 1,631.51 | 1,657.01 | +1.56 | +1.16 |
| kucoinp2p | 1,636.00 | 1,650.00 | +0.86 | +0.46 |
| lemoncashp2p | 1,639.00 | 1,651.00 | +0.73 | +0.33 |
| binancep2p | 1,637.00 | 1,643.90 | +0.42 | +0.02 |
| mexcp2p | 1,636.16 | 1,642.00 | +0.36 | -0.04 |
| bingxp2p | 1,639.00 | 1,644.00 | +0.30 | -0.10 |
| bitgetp2p | 1,640.04 | 1,644.00 | +0.24 | -0.16 |
| bybitp2p | 1,638.53 | 1,640.79 | +0.14 | -0.26 |
| okexp2p | 1,640.20 | 1,642.00 | +0.11 | -0.29 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,657.01 | satoshitango | 1,645.91 | +0.47 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,631.51 | binance | 1,638.90 | +0.25 |
| lemoncashp2p | aviso de VENTA en P2P, compra en app | 1,651.00 | satoshitango | 1,645.91 | +0.11 |
| kucoinp2p | aviso de VENTA en P2P, compra en app | 1,650.00 | satoshitango | 1,645.91 | +0.05 |
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,636.00 | binance | 1,638.90 | -0.02 |
| mexcp2p | aviso de COMPRA en P2P, venta en app | 1,636.16 | binance | 1,638.90 | -0.03 |
| binancep2p | aviso de COMPRA en P2P, venta en app | 1,637.00 | binance | 1,638.90 | -0.08 |
| bybitp2p | aviso de COMPRA en P2P, venta en app | 1,638.53 | binance | 1,638.90 | -0.18 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 696, 'HTX': 391, 'OKX': 507, 'Gate': 1061, 'MEXC': 1079, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| CAP | MEXC (153.5) | KuCoin (13.1) | **140.4** | +0.40 · +21 · 86% (6.8 d) | 0.16 | 0.4 | sí |
| SKDD | OKX (-5.2) | Bitget (-112.9) | **107.7** | -0.20 · -11 · 43% (6.7 d) | 0.22 | 0.7 | sí |
| F | OKX (11.0) | KuCoin (-94.6) | **105.6** | +0.33 · +18 · 86% (6.8 d) | 0.22 | 0.8 | sí |
| CXMT | Gate (69.2) | OKX (-9.6) | **78.8** | -0.11 · -6 · 43% (6.7 d) | 0.2 | 0.9 | sí |
| LA | OKX (-50.8) | Gate (-127.7) | **76.8** | +0.08 · +4 · 86% (6.8 d) | 0.2 | 0.9 | sí |
| CT | Bitget (11.0) | Gate (-61.1) | **72.1** | +0.54 · +29 · 100% (6.8 d) | 0.22 | 1.1 | sí |
| GRAM | Bitget (11.0) | Hyperliquid (-58.5) | **69.4** | +0.39 · +21 · 100% (6.8 d) | 0.21 | 1.1 | sí |
| BZ | OKX (0.0) | Bitget (-56.7) | **56.7** | +0.02 · +1 · 29% (6.8 d) | 0.22 | 1.4 | sí |
| APR | Gate (64.8) | Bitget (11.0) | **53.9** | — | 0.22 | 1.5 | sí |
| ETC | Bitget (11.0) | Gate (-41.0) | **51.9** | — | 0.22 | 1.5 | sí |
| NIL | Bitget (11.0) | Gate (-40.5) | **51.5** | — | 0.22 | 1.6 | sí |
| INJ | MEXC (24.5) | Gate (-26.0) | **50.5** | — | 0.14 | 1.0 | sí |
| BR | Bitget (11.0) | Gate (-36.8) | **47.7** | — | 0.22 | 1.7 | sí |
| USELESS | KuCoin (58.7) | Hyperliquid (11.0) | **47.7** | — | 0.21 | 1.6 | sí |
| JCT | Gate (58.5) | Bitget (11.0) | **47.5** | — | 0.22 | 1.7 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): EWZ 1492.4% (Gate/MEXC), AXIS 854.8% (Bitget/MEXC), T 737.8% (KuCoin/MEXC), IRYS 493.2% (MEXC/KuCoin), ORDER 252.1% (OKX/Gate), ERA 199.7% (Bitget/Gate), BIRB 152.4% (KuCoin/Bitget), BTW 131.3% (KuCoin/OKX)

**Persistencia** (últimas 9 corridas, diferencia ≥ 20% APR): CT 9/9 (prom. 121.0%), ZORA 8/9 (prom. 73.4%), Q 6/9 (prom. 103.6%), F 6/9 (prom. 88.4%), JCT 6/9 (prom. 142.6%), SOON 5/9 (prom. 103.4%), SOXL 5/9 (prom. 72.6%), AAOI 5/9 (prom. 74.4%), XMR 5/9 (prom. 68.1%), BLEND 4/9 (prom. 168.9%), DOOD 4/9 (prom. 109.4%), AKE 4/9 (prom. 89.3%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| Bitget | USDBRL | 181.3 | 8? | 4,573,883 |
| MEXC | CAP | 153.5 | 4.0 | 5,062,851 |
| Bitget | CSOPSK2LHKD | 150.6 | 8? | 1,936,169 |
| Bitget | CAP | 138.0 | 4.0 | 23,598,947 |
| KuCoin | READY | 124.0 | 4.0 | 1,789,074 |
| OKX | CAP | 96.5 | 4.0 | 137,347,932 |
| Bitget | SKUU | 81.5 | 8? | 2,114,254 |
| Gate | CAP | 72.7 | 4.0 | 15,246,732 |
| Gate | CXMT | 69.2 | 1.0 | 3,041,848 |
| Gate | APR | 64.8 | 4.0 | 26,346,427 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.96 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.11 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.57 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

### DeFi: stablecoins en protocolos grandes (sin pérdida impermanente, TVL ≥ 20 M USD)

APY base = intereses o comisiones reales; los premios en tokens van aparte (se pueden cortar). Riesgo: contratos y depeg. Sirve para la plata que no está trabajando.

| protocolo | tipo | red | pool | TVL M USD | APY base % | premios % | APY medio 30 d % |
|---|---|---|---|---|---|---|---|
| aave-v3 | consolidado | Ethereum | USDC | 55.0 | 11.51 | 1.77 | 5.99 |
| aave-v3 | consolidado | Ethereum | USDC | 21.6 | 11.51 | 0.0 | 4.36 |
| morpho-blue | consolidado | Ethereum | FCUSDT | 43.7 | 9.33 | 5.96 | 12.48 |
| kamino-lend | consolidado | Solana | USDC | 53.1 | 7.78 | 0.0 | 7.91 |
| sky-lending | consolidado | Ethereum | STUSDS | 176.2 | 6.51 | 0.0 | 5.42 |
| morpho-blue | consolidado | Ethereum | ROXCUSDC | 36.1 | 6.46 | 1.55 | 11.18 |
| axis | nuevo / sintético | Ethereum | SUSDX | 52.2 | 15.42 | 0.0 | 18.98 |
| apyx-protocol | nuevo / sintético | Ethereum | APXUSD | 152.1 | 12.98 | 0.0 | 12.97 |
| saturn | nuevo / sintético | Ethereum | SUSDAT | 45.7 | 12.9 | 0.0 | 12.69 |
| re | nuevo / sintético | Ethereum | REUSDE | 30.1 | 11.8 | 0.0 | 11.83 |
| unitas-usdu | nuevo / sintético | BSC | SUSDU | 38.8 | 11.61 | 0.0 | 11.6 |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 3 · cerradas 1 · **total -0.3253 €** (realizado -0.1400, abierto -0.1853)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| JCT:KuCoin/Bitget | 10-25 00:51 | 1.0 | 12 | +0.1475 | +0.1479 | 0.2400 | +0.0554 |
| JCT:MEXC/Bitget | 10-25 11:41 | 0.5 | 8 | +0.0716 | +0.0000 | 0.1600 | -0.0884 |
| CT:MEXC/Gate | 10-25 16:31 | 0.3 | 4 | +0.0291 | -0.0414 | 0.1400 | -0.1523 |
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

