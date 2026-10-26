# Radar de oportunidades — 2026-10-26 07:52 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0001 | okexp2p | 1,640.20 | +6.64 | **+6.63** |
| MEP (AL30) | 1,563.45 | xapo | 1.0001 | okexp2p | 1,640.20 | +4.91 | **+4.90** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1652.003, 'bid': 1637, 'variation': 0.44, 'timestamp': 1793001136}

A verificar antes de operar: cupo de dólares de tu banco, si la plataforma acepta tus dólares por transferencia y cuánto tarda, impuestos, y la normativa vigente (restricciones cruzadas).

### Costo de pasar dólares a stablecoin dentro de Argentina (la fricción que sostiene la brecha)

| plataforma | moneda | USD por unidad | prima % |
|---|---|---|---|
| xapo | USDT | 1.0001 | +0.01 |
| astropay | USDT | 1.0038 | +0.38 |
| banexcoin | USDT | 1.015 | +1.50 |
| binancep2p | USDT | 1.018 | +1.80 |
| banexcoin | USDC | 1.041 | +4.10 |
| binance | USDC | 1.0551 | +5.51 |
| decrypto | USDT | 1.0637 | +6.37 |
| nexo | USDT | 1.0649 | +6.49 |

Mejor rulo **dentro del país**: dólar oficial → USDT en xapo → pesos en okexp2p: **+6.63% por vuelta** (si alguna plataforma baja su prima a ~1-2%, este rulo se vuelve automatizable sin giros al exterior).

### Vuelta internacional (usa tus cuentas del exterior)

USD afuera → USDT en Kraken a 0.99856 (+0,26%) → vender en **okexp2p** a 1,640.20 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+6.52% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+2.12%** · 5,000 USD: **+5.32%** · 10,000 USD: **+5.72%**
Con dólar MEP (automatizable por API de un broker): bruto +4.79% · 1,000 USD: +0.39% · 5,000 USD: +3.59% · 10,000 USD: +3.99%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| eldoradop2p | 1,595.00 | 1,668.00 | +4.58 | +4.18 |
| bitgetp2p | 1,638.65 | 1,659.99 | +1.30 | +0.90 |
| bybitp2p | 1,634.11 | 1,649.00 | +0.91 | +0.51 |
| bingxp2p | 1,636.18 | 1,645.80 | +0.59 | +0.19 |
| mexcp2p | 1,636.00 | 1,644.99 | +0.55 | +0.15 |
| binancep2p | 1,636.01 | 1,642.00 | +0.37 | -0.03 |
| okexp2p | 1,640.20 | 1,643.00 | +0.17 | -0.23 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,595.00 | eluter | 1,639.38 | +2.58 |
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,668.00 | nexo | 1,652.00 | +0.77 |
| bitgetp2p | aviso de VENTA en P2P, compra en app | 1,659.99 | nexo | 1,652.00 | +0.28 |
| bybitp2p | aviso de COMPRA en P2P, venta en app | 1,634.11 | eluter | 1,639.38 | +0.12 |
| binancep2p | aviso de COMPRA en P2P, venta en app | 1,636.01 | eluter | 1,639.38 | +0.01 |
| mexcp2p | aviso de COMPRA en P2P, venta en app | 1,636.00 | eluter | 1,639.38 | +0.01 |
| bingxp2p | aviso de COMPRA en P2P, venta en app | 1,636.18 | eluter | 1,639.38 | -0.01 |
| lemoncashp2p | aviso de COMPRA en P2P, venta en app | 1,637.00 | eluter | 1,639.38 | -0.06 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 697, 'HTX': 393, 'OKX': 507, 'Gate': 1061, 'MEXC': 1079, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| SKDD | Bitget (57.7) | OKX (-177.1) | **234.8** | +0.20 · +11 · 57% (6.7 d) | 0.22 | 0.3 | sí |
| JCT | KuCoin (201.0) | Bitget (11.0) | **190.1** | +2.06 · +110 · 100% (6.8 d) | 0.24 | 0.5 | sí |
| ORDER | OKX (-108.1) | MEXC (-234.8) | **126.6** | -0.35 · -19 · 86% (6.8 d) | 0.14 | 0.4 | sí |
| CXMT | Bitget (107.5) | Gate (0.0) | **107.5** | +0.26 · +14 · 86% (6.7 d) | 0.22 | 0.7 | sí |
| CAP | MEXC (112.1) | KuCoin (28.0) | **84.1** | +0.44 · +24 · 86% (6.8 d) | 0.16 | 0.7 | sí |
| CRWV | OKX (0.0) | Bitget (-75.0) | **75.0** | +0.16 · +9 · 71% (6.7 d) | 0.22 | 1.1 | sí |
| COMP | Bitget (11.0) | OKX (-62.6) | **73.6** | +0.04 · +2 · 71% (6.7 d) | 0.22 | 1.1 | sí |
| USELESS | KuCoin (36.6) | Gate (-33.7) | **70.3** | +0.23 · +12 · 100% (6.8 d) | 0.22 | 1.1 | sí |
| FARTCOIN | KuCoin (11.0) | OKX (-58.5) | **69.4** | — | 0.22 | 1.2 | sí |
| SOXL | Bitget (60.2) | KuCoin (0.0) | **60.2** | — | 0.24 | 1.5 | sí |
| CT | Bitget (-42.0) | Gate (-101.8) | **59.8** | — | 0.22 | 1.3 | sí |
| BOME | Gate (2.4) | OKX (-47.7) | **50.1** | — | 0.2 | 1.5 | sí |
| LIGHT | KuCoin (59.3) | OKX (11.0) | **48.4** | — | 0.22 | 1.7 | sí |
| FOLKS | KuCoin (54.5) | Bitget (11.0) | **43.6** | — | 0.24 | 2.0 | sí |
| AGT | Gate (53.2) | KuCoin (11.0) | **42.3** | — | 0.22 | 1.9 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): UNITREE 1218.5% (Gate/MEXC), EWZ 1194.6% (OKX/Bitget), AXIS 646.5% (Gate/MEXC), T 519.0% (Bitget/KuCoin), BTW 276.9% (Gate/OKX), IRYS 251.4% (MEXC/KuCoin), ERA 246.2% (KuCoin/Gate), DOOD 101.6% (Bitget/OKX)

**Persistencia** (últimas 10 corridas, diferencia ≥ 20% APR): CT 10/10 (prom. 114.9%), ZORA 8/10 (prom. 73.4%), JCT 7/10 (prom. 149.4%), Q 6/10 (prom. 103.6%), SOXL 6/10 (prom. 70.5%), F 6/10 (prom. 88.4%), SOON 5/10 (prom. 103.4%), AAOI 5/10 (prom. 74.4%), XMR 5/10 (prom. 68.1%), BLEND 4/10 (prom. 168.9%), DOOD 4/10 (prom. 109.4%), AKE 4/10 (prom. 89.3%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| KuCoin | JCT | 201.0 | 4.0 | 7,891,434 |
| KuCoin | COAI | 179.8 | 4.0 | 1,212,821 |
| Bitget | CSOPSK2LHKD | 145.6 | 8? | 2,258,949 |
| Bitget | USDBRL | 127.5 | 8? | 14,930,008 |
| MEXC | JCT | 115.6 | 4.0 | 12,306,922 |
| MEXC | CAP | 112.1 | 4.0 | 6,626,819 |
| Bitget | CXMT | 107.5 | 8.0 | 1,714,753 |
| Gate | CAP | 107.1 | 4.0 | 22,135,277 |
| Bitget | CAP | 102.1 | 4.0 | 36,945,090 |
| Bitget | CSOPSS2LHKD | 101.1 | 8? | 1,229,684 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.91 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.11 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.63 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

### DeFi: stablecoins en protocolos grandes (sin pérdida impermanente, TVL ≥ 20 M USD)

APY base = intereses o comisiones reales; los premios en tokens van aparte (se pueden cortar). Riesgo: contratos y depeg. Sirve para la plata que no está trabajando.

| protocolo | tipo | red | pool | TVL M USD | APY base % | premios % | APY medio 30 d % |
|---|---|---|---|---|---|---|---|
| kamino-lend | consolidado | Solana | USDC | 53.7 | 7.66 | 0.0 | 7.91 |
| morpho-blue | consolidado | Ethereum | ROXCUSDC | 36.1 | 6.56 | 1.46 | 11.15 |
| sky-lending | consolidado | Ethereum | STUSDS | 176.4 | 6.51 | 0.0 | 5.44 |
| fluid-lending | consolidado | Ethereum | USDC | 138.5 | 6.12 | 0.0 | 5.64 |
| morpho-blue | consolidado | Ethereum | STEAKUSDT | 66.2 | 6.07 | 0.0 | 3.05 |
| morpho-blue | consolidado | Ethereum | PENDLEUSDCHY | 32.3 | 6.05 | 0.46 | 15.95 |
| axis | nuevo / sintético | Ethereum | SUSDX | 52.2 | 15.72 | 0.0 | 18.91 |
| apyx-protocol | nuevo / sintético | Ethereum | APXUSD | 153.0 | 12.98 | 0.0 | 12.96 |
| saturn | nuevo / sintético | Ethereum | SUSDAT | 45.6 | 12.9 | 0.0 | 12.68 |
| re | nuevo / sintético | Ethereum | REUSDE | 30.1 | 11.8 | 0.0 | 11.83 |
| unitas-usdu | nuevo / sintético | BSC | SUSDU | 38.9 | 11.59 | 0.0 | 11.6 |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 3 · cerradas 1 · **total -0.3102 €** (realizado -0.1400, abierto -0.1702)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| JCT:KuCoin/Bitget | 10-25 00:51 | 1.3 | 14 | +0.1696 | +0.1138 | 0.2400 | +0.0434 |
| JCT:MEXC/Bitget | 10-25 11:41 | 0.8 | 10 | +0.0794 | +0.0000 | 0.1600 | -0.0806 |
| CT:MEXC/Gate | 10-25 16:31 | 0.6 | 6 | +0.0484 | -0.0414 | 0.1400 | -0.1330 |
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

