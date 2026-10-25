# Radar de oportunidades — 2026-10-25 20:56 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0002 | bybitp2p | 1,642.00 | +6.76 | **+6.74** |
| MEP (AL30) | 1,563.45 | xapo | 1.0002 | bybitp2p | 1,642.00 | +5.02 | **+5.00** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1646.509, 'bid': 1637, 'variation': 0.11, 'timestamp': 1792961781}

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

Mejor rulo **dentro del país**: dólar oficial → USDT en xapo → pesos en bybitp2p: **+6.74% por vuelta** (si alguna plataforma baja su prima a ~1-2%, este rulo se vuelve automatizable sin giros al exterior).

### Vuelta internacional (usa tus cuentas del exterior)

USD afuera → USDT en Kraken a 0.99868 (+0,26%) → vender en **bybitp2p** a 1,642.00 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+6.63% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+2.23%** · 5,000 USD: **+5.43%** · 10,000 USD: **+5.83%**
Con dólar MEP (automatizable por API de un broker): bruto +4.89% · 1,000 USD: +0.49% · 5,000 USD: +3.69% · 10,000 USD: +4.09%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| eldoradop2p | 1,631.50 | 1,661.53 | +1.84 | +1.44 |
| kucoinp2p | 1,636.00 | 1,650.00 | +0.86 | +0.46 |
| lemoncashp2p | 1,640.00 | 1,652.90 | +0.79 | +0.39 |
| binancep2p | 1,636.50 | 1,643.00 | +0.40 | -0.00 |
| mexcp2p | 1,636.15 | 1,642.00 | +0.36 | -0.04 |
| bingxp2p | 1,639.81 | 1,644.07 | +0.26 | -0.14 |
| bitgetp2p | 1,640.15 | 1,644.00 | +0.23 | -0.17 |
| okexp2p | 1,640.50 | 1,643.69 | +0.19 | -0.21 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,661.53 | satoshitango | 1,646.51 | +0.71 |
| lemoncashp2p | aviso de VENTA en P2P, compra en app | 1,652.90 | satoshitango | 1,646.51 | +0.19 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,631.50 | fiwind | 1,637.00 | +0.14 |
| kucoinp2p | aviso de VENTA en P2P, compra en app | 1,650.00 | satoshitango | 1,646.51 | +0.01 |
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,636.00 | fiwind | 1,637.00 | -0.14 |
| mexcp2p | aviso de COMPRA en P2P, venta en app | 1,636.15 | fiwind | 1,637.00 | -0.15 |
| binancep2p | aviso de COMPRA en P2P, venta en app | 1,636.50 | fiwind | 1,637.00 | -0.17 |
| bingxp2p | aviso de VENTA en P2P, compra en app | 1,644.07 | satoshitango | 1,646.51 | -0.35 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 696, 'HTX': 391, 'OKX': 507, 'Gate': 1061, 'MEXC': 1079, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| CAP | MEXC (203.5) | KuCoin (40.1) | **163.4** | +0.33 · +18 · 86% (6.8 d) | 0.16 | 0.4 | sí |
| IRYS | MEXC (-34.2) | KuCoin (-185.7) | **151.5** | +1.11 · +59 · 29% (6.8 d) | 0.16 | 0.4 | sí |
| F | OKX (11.0) | KuCoin (-102.3) | **113.2** | +0.28 · +15 · 86% (6.8 d) | 0.22 | 0.7 | sí |
| CT | MEXC (-29.3) | Gate (-137.1) | **107.7** | +0.69 · +37 · 71% (6.8 d) | 0.14 | 0.5 | no |
| IN | Bitget (-112.1) | Gate (-194.5) | **82.3** | +0.50 · +27 · 86% (6.8 d) | 0.22 | 1.0 | sí |
| XMR | Hyperliquid (91.6) | KuCoin (11.0) | **80.6** | — | 0.21 | 1.0 | sí |
| JCT | KuCoin (87.4) | Bitget (11.0) | **76.4** | +2.00 · +106 · 100% (6.8 d) | 0.24 | 1.1 | sí |
| Q | MEXC (54.8) | Gate (-9.2) | **63.9** | +0.17 · +9 · 57% (6.8 d) | 0.14 | 0.8 | sí |
| SOXL | OKX (60.8) | Gate (0.0) | **60.8** | — | 0.2 | 1.2 | sí |
| ZBT | OKX (11.0) | KuCoin (-49.5) | **60.4** | — | 0.22 | 1.3 | sí |
| ZORA | OKX (-19.4) | KuCoin (-79.7) | **60.4** | — | 0.22 | 1.3 | sí |
| SNXX | MEXC (89.4) | Gate (34.8) | **54.5** | — | 0.14 | 0.9 | no |
| EIGEN | MEXC (2.1) | OKX (-50.9) | **53.0** | — | 0.14 | 1.0 | no |
| RAVE | OKX (11.0) | KuCoin (-40.1) | **51.0** | — | 0.22 | 1.6 | sí |
| SNDK | OKX (50.5) | KuCoin (0.0) | **50.5** | — | 0.22 | 1.6 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): T 432.3% (KuCoin/Gate), BTW 288.9% (Bitget/OKX), ORDER 241.8% (Bitget/Gate), AXIS 223.4% (Bitget/Gate), IOST 215.5% (Gate/Bitget), BIRB 178.9% (KuCoin/Gate), ANIME 175.0% (Bitget/Hyperliquid), BABY 136.5% (Bitget/OKX)

**Persistencia** (últimas 8 corridas, diferencia ≥ 20% APR): CT 8/8 (prom. 127.1%), ZORA 8/8 (prom. 73.4%), Q 6/8 (prom. 103.6%), SOON 5/8 (prom. 103.4%), SOXL 5/8 (prom. 72.6%), AAOI 5/8 (prom. 74.4%), XMR 5/8 (prom. 68.1%), F 5/8 (prom. 84.9%), JCT 5/8 (prom. 161.6%), BLEND 4/8 (prom. 168.9%), DOOD 4/8 (prom. 109.4%), AKE 4/8 (prom. 89.3%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| MEXC | CAP | 203.5 | 4.0 | 4,781,970 |
| Bitget | CAP | 180.5 | 4.0 | 21,528,397 |
| Gate | CAP | 173.0 | 4.0 | 14,337,341 |
| OKX | CAP | 166.3 | 4.0 | 127,597,765 |
| KuCoin | READY | 112.6 | 4.0 | 1,779,966 |
| OKX | UP | 107.5 | 4.0 | 5,563,394 |
| Hyperliquid | XMR | 91.6 | 1 | 29,964,429 |
| MEXC | SNXX | 89.4 | 8? | 2,109,494 |
| KuCoin | JCT | 87.4 | 4.0 | 9,540,496 |
| KuCoin | KCS | 71.1 | 8.0 | 16,102,600 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.96 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.17 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.46 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

### DeFi: stablecoins en protocolos grandes (sin pérdida impermanente, TVL ≥ 20 M USD)

APY base = intereses o comisiones reales; los premios en tokens van aparte (se pueden cortar). Riesgo: contratos y depeg. Sirve para la plata que no está trabajando.

| protocolo | tipo | red | pool | TVL M USD | APY base % | premios % | APY medio 30 d % |
|---|---|---|---|---|---|---|---|
| kamino-lend | consolidado | Solana | USDC | 53.1 | 7.75 | 0.0 | 7.92 |
| morpho-blue | consolidado | Ethereum | ROXCUSDC | 36.1 | 6.53 | 1.49 | 11.19 |
| sky-lending | consolidado | Ethereum | STUSDS | 176.1 | 6.51 | 0.0 | 5.42 |
| morpho-blue | consolidado | Ethereum | PENDLEUSDCHY | 33.9 | 6.22 | 0.44 | 16.33 |
| morpho-blue | consolidado | Ethereum | STEAKCUSDC | 32.3 | 6.0 | 0.0 | 7.14 |
| fluid-lending | consolidado | Ethereum | USDC | 137.1 | 5.96 | 0.0 | 5.62 |
| axis | nuevo / sintético | Ethereum | SUSDX | 52.2 | 15.24 | 0.0 | 19.01 |
| apyx-protocol | nuevo / sintético | Ethereum | APXUSD | 153.1 | 12.98 | 0.0 | 12.97 |
| saturn | nuevo / sintético | Ethereum | SUSDAT | 45.7 | 12.9 | 0.0 | 12.7 |
| re | nuevo / sintético | Ethereum | REUSDE | 30.1 | 11.8 | 0.0 | 11.83 |
| unitas-usdu | nuevo / sintético | BSC | SUSDU | 38.8 | 11.61 | 0.0 | 11.6 |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 3 · cerradas 1 · **total -0.3534 €** (realizado -0.1400, abierto -0.2134)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| JCT:KuCoin/Bitget | 10-25 00:51 | 0.8 | 10 | +0.1350 | +0.1479 | 0.2400 | +0.0429 |
| JCT:MEXC/Bitget | 10-25 11:41 | 0.4 | 6 | +0.0716 | +0.0000 | 0.1600 | -0.0884 |
| CT:MEXC/Gate | 10-25 16:31 | 0.2 | 2 | +0.0135 | -0.0414 | 0.1400 | -0.1679 |
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

