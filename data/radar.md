# Radar de oportunidades — 2026-10-25 04:51 UTC

Datos públicos en vivo. Cada oportunidad es **a verificar** (comisiones reales, cupos, tiempos y normativa) antes de poner dinero. La columna clave es la *persistencia*: lo que se repite.

## 1. Argentina: pesos → dólares → USDT → pesos ("rulo")

| compra de dólares | ARS por USD | pasa a USDT en | USD por USDT | vende USDT en | ARS por USDT | bruto % | neto % |
|---|---|---|---|---|---|---|---|
| oficial (prex) | 1,538.00 | xapo | 1.0002 | okexp2p | 1,640.00 | +6.63 | **+6.61** |
| MEP (AL30) | 1,563.45 | xapo | 1.0002 | okexp2p | 1,640.00 | +4.90 | **+4.88** |

Referencias: oficial 1550 · blue (compra) 1545 · MEP 1563.45 · cripto USDT {'ask': 1651, 'bid': 1637, 'variation': 0.38, 'timestamp': 1792903875}

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

Mejor rulo **dentro del país**: dólar oficial → USDT en xapo → pesos en okexp2p: **+6.61% por vuelta** (si alguna plataforma baja su prima a ~1-2%, este rulo se vuelve automatizable sin giros al exterior).

### Vuelta internacional (usa tus cuentas del exterior)

USD afuera → USDT en Kraken a 0.99869 (+0,26%) → vender en **okexp2p** a 1,640.00 ARS → dólar oficial en **prex** a 1,538.00 → giro al exterior: **+6.50% bruto por vuelta**.
Neto por vuelta según el monto (giro supuesto: 40 USD fijos + 0.3%): 1,000 USD: **+2.09%** · 5,000 USD: **+5.29%** · 10,000 USD: **+5.69%**
Con dólar MEP (automatizable por API de un broker): bruto +4.76% · 1,000 USD: +0.36% · 5,000 USD: +3.56% · 10,000 USD: +3.96%

Automatizable: comprar USDT en Kraken, enviarlo y venderlo por pesos (APIs). Manual: comprar los dólares (salvo MEP por broker) y el giro al exterior; conviene juntarlo en pocas vueltas grandes. A verificar: costo real del giro de tu banco y de la acreditación en Kraken, y tus límites (UE < 10.000 € acumulados, AR < 50 M ARS/mes, 2,5 M ARS por operación).

## 2. P2P: margen del que publica avisos (merchant)

| plataforma | mejor compra (bid) | mejor venta (ask) | bruto % | neto % (2 x 0,2% comisión) |
|---|---|---|---|---|
| kucoinp2p | 1,618.25 | 1,657.50 | +2.42 | +2.02 |
| eldoradop2p | 1,629.90 | 1,660.00 | +1.85 | +1.45 |
| mexcp2p | 1,634.00 | 1,648.99 | +0.92 | +0.52 |
| lemoncashp2p | 1,638.50 | 1,647.99 | +0.58 | +0.18 |
| bybitp2p | 1,635.12 | 1,642.90 | +0.48 | +0.08 |
| binancep2p | 1,637.00 | 1,644.68 | +0.47 | +0.07 |
| bingxp2p | 1,638.71 | 1,645.55 | +0.42 | +0.02 |
| bitgetp2p | 1,639.10 | 1,643.80 | +0.29 | -0.11 |
| okexp2p | 1,640.00 | 1,644.00 | +0.24 | -0.16 |

### Aviso P2P cubierto al instante en una app (por llenado)

| plataforma | estrategia | precio del aviso | cubre en | precio | neto % |
|---|---|---|---|---|---|
| kucoinp2p | aviso de COMPRA en P2P, venta en app | 1,618.25 | fiwind | 1,637.00 | +0.96 |
| eldoradop2p | aviso de VENTA en P2P, compra en app | 1,660.00 | fiwind | 1,651.00 | +0.34 |
| eldoradop2p | aviso de COMPRA en P2P, venta en app | 1,629.90 | fiwind | 1,637.00 | +0.24 |
| kucoinp2p | aviso de VENTA en P2P, compra en app | 1,657.50 | fiwind | 1,651.00 | +0.19 |
| mexcp2p | aviso de COMPRA en P2P, venta en app | 1,634.00 | fiwind | 1,637.00 | -0.02 |
| bybitp2p | aviso de COMPRA en P2P, venta en app | 1,635.12 | fiwind | 1,637.00 | -0.09 |
| binancep2p | aviso de COMPRA en P2P, venta en app | 1,637.00 | fiwind | 1,637.00 | -0.20 |
| lemoncashp2p | aviso de COMPRA en P2P, venta en app | 1,638.50 | fiwind | 1,637.00 | -0.29 |

## 3. Diferencia de funding entre exchanges (delta neutral, sin contado)

Fuentes: {'Bitget': 857, 'KuCoin': 696, 'HTX': 391, 'OKX': 507, 'Gate': 1061, 'MEXC': 1088, 'Hyperliquid': 178}. Volumen 24 h ≥ 1 M USD en ambas patas. Neto a 7 días tras 4 ejecuciones tomadoras.

| moneda | corto en (APR) | largo en (APR) | diferencia APR % ahora | REAL últimos días: total % · APR % · días + | costo % | días para cubrir costo | intervalos conocidos |
|---|---|---|---|---|---|---|---|
| DATA | OKX (11.0) | KuCoin (-282.3) | **293.2** | +0.20 · +11 · 71% (6.8 d) | 0.22 | 0.3 | sí |
| JCT | KuCoin (177.4) | Bitget (11.0) | **166.4** | +1.79 · +96 · 100% (6.8 d) | 0.24 | 0.5 | sí |
| CT | Bitget (-17.7) | KuCoin (-170.6) | **152.9** | +0.08 · +4 · 57% (6.8 d) | 0.24 | 0.6 | sí |
| PONS | KuCoin (22.6) | Gate (-104.2) | **126.8** | +0.21 · +11 · 71% (6.8 d) | 0.22 | 0.6 | sí |
| LA | Bitget (-132.7) | OKX (-255.1) | **122.4** | +0.27 · +14 · 100% (6.8 d) | 0.22 | 0.7 | sí |
| LIGHT | MEXC (76.0) | KuCoin (-42.3) | **118.3** | -0.43 · -23 · 29% (6.8 d) | 0.16 | 0.5 | sí |
| SOON | OKX (126.7) | Bitget (11.0) | **115.7** | +0.32 · +17 · 100% (6.8 d) | 0.22 | 0.7 | sí |
| ZORA | OKX (-35.3) | KuCoin (-131.6) | **96.4** | -0.02 · -1 · 14% (6.8 d) | 0.22 | 0.8 | sí |
| SNXX | MEXC (90.1) | Gate (0.0) | **90.1** | — | 0.14 | 0.6 | no |
| AGT | KuCoin (120.7) | Gate (33.1) | **87.6** | — | 0.22 | 0.9 | sí |
| XMR | Hyperliquid (97.7) | KuCoin (11.0) | **86.8** | — | 0.21 | 0.9 | sí |
| H | OKX (90.1) | KuCoin (11.0) | **79.2** | — | 0.22 | 1.0 | sí |
| Q | Bitget (11.0) | Gate (-67.5) | **78.4** | — | 0.22 | 1.0 | sí |
| APR | Gate (87.4) | Bitget (11.0) | **76.4** | — | 0.22 | 1.1 | sí |
| KORU | OKX (74.1) | Gate (0.0) | **74.1** | — | 0.2 | 1.0 | sí |

**Extremos** (alguna pata > 300% APR: tokens nuevos o squeezes; pueden darse vuelta en horas, alto riesgo): IRYS 1141.4% (MEXC/KuCoin), BIRB 1007.8% (KuCoin/Gate), T 648.7% (Gate/KuCoin), ANIME 508.7% (KuCoin/Gate), ORDER 483.6% (Bitget/Gate), ERA 318.0% (Bitget/KuCoin), BMT 291.7% (KuCoin/Gate), IOST 282.5% (OKX/Bitget)

**Persistencia** (últimas 5 corridas, diferencia ≥ 20% APR): CT 5/5 (prom. 123.2%), SOON 5/5 (prom. 103.4%), ZORA 5/5 (prom. 78.7%), BLEND 4/5 (prom. 168.9%), Q 4/5 (prom. 105.4%), DOOD 4/5 (prom. 109.4%), AKE 4/5 (prom. 89.3%), CHIP 4/5 (prom. 62.9%), AAOI 4/5 (prom. 70.9%), SOXL 3/5 (prom. 80.5%), MUU 3/5 (prom. 66.1%), XMR 3/5 (prom. 67.5%)

### Funding más alto (para carry con contado o como pata corta)

| exchange | moneda | APR % | intervalo h | volumen 24 h USD |
|---|---|---|---|---|
| KuCoin | 2U2 | 399.7 | 4.0 | 1,867,215 |
| KuCoin | READY | 331.6 | 4.0 | 1,799,244 |
| KuCoin | JCT | 177.4 | 4.0 | 12,227,052 |
| Gate | JCT | 174.5 | 4.0 | 29,649,366 |
| OKX | UP | 149.3 | 4.0 | 1,282,720 |
| MEXC | JCT | 145.4 | 4.0 | 10,929,264 |
| OKX | SOON | 126.7 | 4.0 | 5,607,059 |
| KuCoin | AGT | 120.7 | 4.0 | 2,314,755 |
| Hyperliquid | XMR | 97.7 | 1 | 34,546,998 |
| MEXC | SNXX | 90.1 | 8? | 3,249,225 |

## 4. Préstamo de stablecoins (sin riesgo de precio; riesgo del exchange)

| dónde | activo | APR % | nota |
|---|---|---|---|
| Bitfinex | USD | 10.97 | tasa FRR diaria x 365; varía cada hora |
| Bitfinex | USDT | 9.41 | tasa FRR diaria x 365; varía cada hora |
| Binance | USDT | 6.46 | Simple Earn flexible; el máximo suele ser solo para el primer tramo |
| OKX | USDT | 3.5 | préstamo simple, tasa estimada |

### DeFi: stablecoins en protocolos grandes (sin pérdida impermanente, TVL ≥ 20 M USD)

APY base = intereses o comisiones reales; los premios en tokens van aparte (se pueden cortar). Riesgo: contratos y depeg. Sirve para la plata que no está trabajando.

| protocolo | tipo | red | pool | TVL M USD | APY base % | premios % | APY medio 30 d % |
|---|---|---|---|---|---|---|---|
| kamino-lend | consolidado | Solana | USDC | 52.5 | 7.82 | 0.0 | 7.93 |
| morpho-blue | consolidado | Ethereum | PENDLEUSDCHY | 33.5 | 6.22 | 0.45 | 16.95 |
| fluid-lending | consolidado | Ethereum | USDC | 136.0 | 6.15 | 0.0 | 5.58 |
| morpho-blue | consolidado | Ethereum | STEAKCUSDC | 32.3 | 6.0 | 0.0 | 7.17 |
| morpho-blue | consolidado | Ethereum | ROXUSDCY | 23.2 | 5.87 | 1.11 | 7.35 |
| morpho-blue | consolidado | Ethereum | BBQUSDC | 47.1 | 5.69 | 0.0 | 5.77 |
| axis | nuevo / sintético | Ethereum | SUSDX | 52.1 | 15.02 | 0.0 | 19.07 |
| apyx-protocol | nuevo / sintético | Ethereum | APXUSD | 152.2 | 12.98 | 0.0 | 12.97 |
| saturn | nuevo / sintético | Ethereum | SUSDAT | 45.7 | 12.9 | 0.0 | 12.74 |
| re | nuevo / sintético | Ethereum | REUSDE | 30.1 | 11.8 | 0.0 | 11.84 |
| unitas-usdu | nuevo / sintético | BSC | SUSDU | 38.8 | 11.61 | 0.0 | 11.6 |

## 5. Eventos: launchpools y promociones

Sin launchpools activos de MEXC en este momento.
## 6. Paper de diferencias de funding (cobros reales desde la apertura simulada)

50 € por pata · abiertas 1 · cerradas 1 · **total -0.1012 €** (realizado -0.1400, abierto +0.0388)

| posición | abierta | días | cobros | funding € | base € | comisiones € | neto € |
|---|---|---|---|---|---|---|---|
| JCT:KuCoin/Bitget | 10-25 00:51 | 0.2 | 2 | +0.0341 | +0.2446 | 0.2400 | +0.0388 |
| IRYS (cerrada) | 10-24 22:47 | 0.0 | 1 | +0.0000 | +0.0000 | 0.1400 | -0.1400 |

