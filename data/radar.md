# Radar de oportunidades — 2026-10-26 12:33 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 0.9999 | mexcp2p | 1,700.00 | +10.53 | **+10.54** |
| MEP (AL30) | 1,563.45 | xapo | 0.9999 | mexcp2p | 1,700.00 | +8.73 | **+8.74** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1652.705, 'bid': 1639.932, 'variation': 0.48, 'timestamp': 1793017936}

A verificar antes de operar: cupo de dólares de tu banco, si la plataforma acepta tus dólares por transferencia y cuánto tarda, impuestos, y la normativa vigente (restricciones cruzadas).

### Costo de pasar dólares a stablecoin dentro de Argentina (la fricción que sostiene la brecha)

| plataforma | moneda | USD por unidad | prima % |
|---|---|---|---|
| xapo | USDT | 0.9999 | -0.01 |
| astropay | USDT | 1.0036 | +0.36 |
| banexcoin | USDT | 1.015 | +1.50 |
| binancep2p | USDT | 1.04 | +4.00 |
| banexcoin | USDC | 1.041 | +4.10 |
| binance | USDC | 1.0553 | +5.53 |
| decrypto | USDT | 1.0637 | +6.37 |
| fiwind | USDT | 1.065 | +6.50 |

Mejor rulo **dentro del país**: dólar oficial → USDT en xapo → pesos en mexcp2p: **+10.54% por vuelta** (si alguna plataforma baja su prima a ~1-2%, este rulo se vuelve automatizable sin giros al exterior).

### Vuelta internacional (usa tus cuentas del exterior)

USD afuera → USDT en Kraken a 0.99843 (+0,26%) → vender en **mexcp2p** a 1,700.00 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+10.42% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+6.02%** · 5,000 USD: **+9.22%** · 10,000 USD: **+9.62%**
Con dólar MEP (automatizable por API de un broker): bruto +8.62% · 1,000 USD: +4.22% · 5,000 USD: +7.42% · 10,000 USD: +7.82%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| eldoradop2p | 1,633.30 | 1,664.80 | +1.93 | +1.53 |
| kucoinp2p | 1,633.00 | 1,649.50 | +1.01 | +0.61 |
| bingxp2p | 1,637.53 | 1,644.90 | +0.45 | +0.05 |
| bitgetp2p | 1,639.21 | 1,646.55 | +0.45 | +0.05 |
| binancep2p | 1,636.65 | 1,643.00 | +0.39 | -0.01 |
| bybitp2p | 1,636.60 | 1,641.90 | +0.32 | -0.08 |
| lemoncashp2p | 1,636.02 | 1,640.00 | +0.24 | -0.16 |
| okexp2p | 1,640.20 | 1,642.98 | +0.17 | -0.23 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,664.80 | bitsoalpha | 1,652.19 | +0.56 |
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,633.00 | nexo | 1,639.93 | +0.23 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,633.30 | nexo | 1,639.93 | +0.21 |
| lemoncashp2p | aviso de COMPRA en P2P, venta en app | 1,636.02 | nexo | 1,639.93 | +0.04 |
| bybitp2p | aviso de COMPRA en P2P, venta en app | 1,636.60 | nexo | 1,639.93 | +0.00 |
| binancep2p | aviso de COMPRA en P2P, venta en app | 1,636.65 | nexo | 1,639.93 | +0.00 |
| bingxp2p | aviso de COMPRA en P2P, venta en app | 1,637.53 | nexo | 1,639.93 | -0.05 |
| bitgetp2p | aviso de COMPRA en P2P, venta en app | 1,639.21 | nexo | 1,639.93 | -0.16 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 860, 'KuCoin': 697, 'HTX': 393, 'OKX': 507, 'Gate': 1061, 'MEXC': 1082, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| SOON | Gate (265.2) | Bitget (11.0) | **254.3** | +0.01 · +0 · 100% (6.8 d) | 0.22 | 0.3 | sí |
| JCT | Gate (212.9) | Bitget (11.0) | **201.9** | +1.00 · +54 · 100% (6.8 d) | 0.22 | 0.4 | sí |
| AXIS | Gate (11.0) | MEXC (-158.3) | **169.3** | +1.41 · +106 · 60% (4.8 d) | 0.14 | 0.3 | sí |
| LIGHT | KuCoin (158.8) | OKX (11.0) | **147.8** | +0.39 · +21 · 71% (6.8 d) | 0.22 | 0.5 | sí |
| NIL | Bitget (11.0) | Hyperliquid (-76.4) | **87.3** | +0.21 · +11 · 100% (6.8 d) | 0.21 | 0.9 | sí |
| EWZ | OKX (84.5) | Bitget (0.0) | **84.5** | +1.27 · +70 · 86% (6.7 d) | 0.22 | 1.0 | sí |
| ORDER | Bitget (-9.6) | Gate (-92.0) | **82.3** | +0.91 · +49 · 86% (6.8 d) | 0.22 | 1.0 | sí |
| SKHYNIX | OKX (82.3) | Gate (0.0) | **82.3** | +0.13 · +7 · 43% (6.7 d) | 0.2 | 0.9 | sí |
| NG | OKX (78.4) | Gate (0.0) | **78.4** | — | 0.2 | 0.9 | sí |
| MSTU | Bitget (70.4) | KuCoin (0.0) | **70.4** | — | 0.24 | 1.2 | sí |
| SAMSUNG | OKX (95.3) | Gate (27.4) | **67.9** | — | 0.2 | 1.1 | sí |
| PONS | Gate (74.7) | Bitget (11.0) | **63.7** | — | 0.22 | 1.3 | sí |
| BABY | Bitget (-187.9) | OKX (-250.9) | **63.0** | — | 0.22 | 1.3 | sí |
| AAOI | KuCoin (70.7) | Gate (11.7) | **59.0** | — | 0.22 | 1.4 | sí |
| SKDD | KuCoin (-74.2) | OKX (-130.3) | **56.1** | — | 0.22 | 1.4 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): BTW 1343.3% (Bitget/Gate), USDBRL 867.8% (Bitget/Gate), UNITREE 533.9% (Bitget/OKX), ERA 395.1% (KuCoin/Gate), IRYS 250.5% (Bitget/KuCoin), DOOD 238.9% (KuCoin/Gate), T 228.9% (KuCoin/Bitget), BMT 118.3% (KuCoin/Gate)

**Persistencia** (últimas 11 corridas, diferencia ≥ 20% APR): CT 10/11 (prom. 114.9%), ZORA 8/11 (prom. 73.4%), JCT 8/11 (prom. 155.9%), Q 6/11 (prom. 103.6%), SOON 6/11 (prom. 128.5%), SOXL 6/11 (prom. 70.5%), AAOI 6/11 (prom. 71.8%), F 6/11 (prom. 88.4%), XMR 5/11 (prom. 68.1%), BLEND 4/11 (prom. 168.9%), DOOD 4/11 (prom. 109.4%), AKE 4/11 (prom. 89.3%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| Bitget | USDBRL | 889.7 | 8.0 | 25,068,684 |
| Bitget | XP | 682.4 | 8? | 15,276,050 |
| KuCoin | READY | 295.0 | 4.0 | 1,834,275 |
| Gate | SOON | 265.2 | 4.0 | 5,366,684 |
| Bitget | VALE | 261.2 | 8? | 2,597,292 |
| Bitget | MELI | 223.3 | 8? | 3,162,022 |
| Gate | JCT | 212.9 | 4.0 | 21,678,914 |
| KuCoin | LIGHT | 158.8 | 4.0 | 35,234,002 |
| Bitget | CSOPSK2LHKD | 153.4 | 8? | 2,787,020 |
| Bitget | CSOPSS2LHKD | 147.1 | 8? | 1,537,338 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.9 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.09 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.65 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

### DeFi: stablecoins en protocolos grandes (sin pérdida impermanente, TVL ≥ 20 M USD)

APY base = intereses o comisiones reales; los premios en tokens van aparte (se pueden cortar). Riesgo: contratos y depeg. Sirve para la plata que no está trabajando.

| protocolo | tipo | red | pool | TVL M USD | APY base % | premios % | APY medio 30 d % |
|---|---|---|---|---|---|---|---|
| morpho-blue | consolidado | Ethereum | FCUSDT | 43.6 | 8.6 | 5.32 | 12.52 |
| morpho-blue | consolidado | Ethereum | ROXCUSDC | 35.1 | 7.99 | 1.49 | 11.13 |
| kamino-lend | consolidado | Solana | USDC | 53.7 | 7.66 | 0.0 | 7.9 |
| morpho-blue | consolidado | Ethereum | STEAKUSDT | 66.9 | 6.54 | 0.0 | 3.06 |
| sky-lending | consolidado | Ethereum | STUSDS | 176.6 | 6.51 | 0.0 | 5.45 |
| morpho-blue | consolidado | Ethereum | BBQUSDT | 20.2 | 6.26 | 0.0 | 3.79 |
| axis | nuevo / sintético | Ethereum | SUSDX | 52.6 | 15.93 | 0.0 | 18.84 |
| apyx-protocol | nuevo / sintético | Ethereum | APXUSD | 152.9 | 12.98 | 0.0 | 12.96 |
| saturn | nuevo / sintético | Ethereum | SUSDAT | 45.6 | 12.9 | 0.0 | 12.67 |
| re | nuevo / sintético | Ethereum | REUSDE | 30.1 | 11.8 | 0.0 | 11.82 |
| unitas-usdu | nuevo / sintético | BSC | SUSDU | 38.9 | 11.62 | 0.0 | 11.6 |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 3 · cerradas 1 · **total -0.1883 €** (realizado -0.1400, abierto -0.0483)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| JCT:KuCoin/Bitget | 10-25 00:51 | 1.5 | 18 | +0.2348 | +0.1138 | 0.2400 | +0.1087 |
| JCT:MEXC/Bitget | 10-25 11:41 | 1.0 | 14 | +0.1124 | +0.0000 | 0.1600 | -0.0476 |
| CT:MEXC/Gate | 10-25 16:31 | 0.8 | 10 | +0.0720 | -0.0414 | 0.1400 | -0.1094 |
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

