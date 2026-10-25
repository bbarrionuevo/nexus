# Informe nexus — últimas 24 h, 76 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 56 | 56 | 74 | 2.721 |
| hedge_mexc_binance_bnb | 56 | 56 | 74 | 2.747 |
| funding | 56 | 56 | 60 | 3.504 |
| maker_kraken | 76 | 76 | 57 | 149849.500 |
| maker_binance | 76 | 76 | 51 | 2.775 |
| peg_kraken | 76 | 76 | 2 | 0.563 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 76 | 0 | 0 | -0.096 |
| bin_tri_BTC | 76 | 0 | 0 | -0.162 |
| bin_tri_ARS | 76 | 0 | 0 | -0.096 |
| bin_tri_EUR | 76 | 0 | 0 | -0.189 |
| tri_EUR | 76 | 1 | 1 | 0.166 |
| tri_USDC | 76 | 0 | 0 | -0.778 |
| cross_eur | 76 | 0 | 0 | -0.744 |
| eurc_arb | 76 | 0 | 0 | -0.370 |
| ars_USDT | 76 | 0 | 0 | -0.956 |
| ars_USDC | 76 | 0 | 0 | -0.967 |
| ars_BTC | 76 | 0 | 0 | -2.582 |
| ars_ETH | 76 | 0 | 0 | -2.062 |

Triangular EUR: ineficiencia bruta máx 1.377% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (56 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC JCT_USDT | 100% | 117.8 | 51.4 |
| MEXC AGT_USDT | 100% | 37.2 | 15.5 |
| MEXC INJ_USDT | 100% | 19.0 | 11.5 |
| MEXC XMR_USDT | 100% | 11.0 | 11.0 |
| Gate JCT_USDT (sin contado) | 93% | 95.6 | 37.7 |
| Gate LIGHT_USDT | 93% | 16.5 | 11.0 |
| Gate BTR_USDT | 93% | 11.0 | 11.0 |
| Gate MAGIC_USDT | 93% | 11.0 | 11.0 |
| Gate ARB_USDT | 93% | 11.0 | 11.0 |
| MEXC BTR_USDT | 82% | 27.7 | 16.6 |
| Gate AGT_USDT (sin contado) | 75% | 40.5 | 22.3 |
| Gate AAVE_USDT | 75% | 10.4 | 9.4 |

### Cobertura MEXC→Binance persistente (56 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| ATMUSDT buy_A_sell_B | 100% | 0.826 | 0.488 |
| DCRUSDT buy_A_sell_B | 100% | 0.732 | 0.507 |
| BNBUSD1 buy_A_sell_B | 100% | 0.682 | 0.654 |
| HOMEUSDC buy_A_sell_B | 96% | 0.604 | 0.420 |
| MANTAUSDC buy_A_sell_B | 95% | 0.809 | 0.374 |
| TFUELUSDT buy_A_sell_B | 93% | 0.995 | 0.438 |
| MANTAUSDC sell_A_buy_B | 93% | 0.752 | 0.402 |
| EGLDUSDC buy_A_sell_B | 93% | 0.735 | 0.527 |
| PUNDIXUSDT buy_A_sell_B | 91% | 0.649 | 0.458 |
| ATUSDC buy_A_sell_B | 89% | 0.733 | 0.481 |
| ATUSDT buy_A_sell_B | 89% | 0.651 | 0.429 |
| INITUSDT buy_A_sell_B | 86% | 0.517 | 0.316 |
