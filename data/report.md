# Informe nexus — últimas 24 h, 76 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 36 | 36 | 62 | 2.721 |
| hedge_mexc_binance_bnb | 36 | 36 | 62 | 2.747 |
| funding | 36 | 36 | 54 | 3.504 |
| maker_kraken | 76 | 76 | 53 | 149849.500 |
| maker_binance | 76 | 76 | 49 | 4.030 |
| peg_kraken | 76 | 76 | 2 | 0.563 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 76 | 0 | 0 | -0.098 |
| bin_tri_BTC | 76 | 0 | 0 | -0.162 |
| bin_tri_ARS | 76 | 0 | 0 | -0.119 |
| bin_tri_EUR | 76 | 0 | 0 | -0.170 |
| tri_EUR | 76 | 1 | 1 | 0.166 |
| tri_USDC | 76 | 0 | 0 | -0.775 |
| cross_eur | 76 | 0 | 0 | -0.744 |
| eurc_arb | 76 | 0 | 0 | -0.380 |
| ars_USDT | 76 | 0 | 0 | -0.956 |
| ars_USDC | 76 | 0 | 0 | -0.967 |
| ars_BTC | 76 | 0 | 0 | -2.582 |
| ars_ETH | 76 | 0 | 0 | -2.062 |

Triangular EUR: ineficiencia bruta máx 1.377% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (36 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC JCT_USDT | 100% | 118.1 | 51.4 |
| MEXC AGT_USDT | 100% | 29.8 | 15.5 |
| MEXC BTR_USDT | 100% | 26.0 | 16.6 |
| MEXC INJ_USDT | 100% | 22.5 | 16.6 |
| MEXC XMR_USDT | 100% | 11.0 | 11.0 |
| Gate JCT_USDT (sin contado) | 89% | 113.6 | 65.4 |
| Gate LIGHT_USDT | 89% | 19.9 | 11.0 |
| Gate BTR_USDT | 89% | 11.0 | 11.0 |
| Gate PIEVERSE_USDT | 89% | 11.0 | 11.0 |
| Gate MAGIC_USDT | 89% | 11.0 | 11.0 |
| Gate ARB_USDT | 89% | 11.0 | 11.0 |
| Gate AAVE_USDT | 89% | 10.7 | 9.7 |

### Cobertura MEXC→Binance persistente (36 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| ATMUSDT buy_A_sell_B | 100% | 0.902 | 0.655 |
| DCRUSDT buy_A_sell_B | 100% | 0.743 | 0.507 |
| BNBUSD1 buy_A_sell_B | 100% | 0.690 | 0.658 |
| HOMEUSDC buy_A_sell_B | 94% | 0.591 | 0.420 |
| MANTAUSDC buy_A_sell_B | 92% | 0.657 | 0.374 |
| TFUELUSDT buy_A_sell_B | 89% | 0.908 | 0.438 |
| MANTAUSDC sell_A_buy_B | 89% | 0.793 | 0.402 |
| EGLDUSDC buy_A_sell_B | 89% | 0.703 | 0.527 |
| PUNDIXUSDT buy_A_sell_B | 86% | 0.621 | 0.458 |
| ATUSDC buy_A_sell_B | 83% | 0.756 | 0.651 |
| ATUSDT buy_A_sell_B | 83% | 0.677 | 0.597 |
| IOSTUSDT sell_A_buy_B | 81% | 0.963 | 0.345 |
