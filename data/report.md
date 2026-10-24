# Informe nexus — últimas 24 h, 76 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 26 | 26 | 57 | 2.721 |
| hedge_mexc_binance_bnb | 26 | 26 | 57 | 2.747 |
| funding | 26 | 26 | 38 | 3.504 |
| maker_kraken | 76 | 76 | 51 | 149849.500 |
| maker_binance | 76 | 76 | 50 | 4.030 |
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
| ars_USDT | 76 | 0 | 0 | -1.006 |
| ars_USDC | 76 | 0 | 0 | -0.967 |
| ars_BTC | 76 | 0 | 0 | -2.582 |
| ars_ETH | 76 | 0 | 0 | -2.062 |

Triangular EUR: ineficiencia bruta máx 1.377% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (26 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC JCT_USDT | 100% | 121.1 | 51.4 |
| MEXC AGT_USDT | 100% | 34.5 | 15.5 |
| MEXC INJ_USDT | 100% | 24.7 | 20.6 |
| MEXC BTR_USDT | 100% | 24.0 | 16.6 |
| MEXC XMR_USDT | 100% | 11.0 | 11.0 |
| MEXC STX_USDT | 100% | 11.0 | 11.0 |
| MEXC BAT_USDT | 100% | 8.3 | 6.7 |
| Gate JCT_USDT (sin contado) | 85% | 131.5 | 106.9 |
| Gate AGT_USDT (sin contado) | 85% | 38.4 | 22.3 |
| Gate LIGHT_USDT | 85% | 23.9 | 11.0 |
| Gate BTR_USDT | 85% | 11.0 | 11.0 |
| Gate PIEVERSE_USDT | 85% | 11.0 | 11.0 |

### Cobertura MEXC→Binance persistente (26 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| IOSTUSDT sell_A_buy_B | 100% | 1.032 | 0.539 |
| ATMUSDT buy_A_sell_B | 100% | 0.916 | 0.818 |
| ATMUSDT sell_A_buy_B | 100% | 0.894 | 0.799 |
| BNBUSD1 buy_A_sell_B | 100% | 0.695 | 0.677 |
| DCRUSDT buy_A_sell_B | 100% | 0.651 | 0.507 |
| MANTAUSDC buy_A_sell_B | 96% | 0.733 | 0.561 |
| HOMEUSDC buy_A_sell_B | 92% | 0.618 | 0.420 |
| MANTAUSDC sell_A_buy_B | 85% | 0.887 | 0.402 |
| TFUELUSDT buy_A_sell_B | 85% | 0.866 | 0.438 |
| EGLDUSDC buy_A_sell_B | 85% | 0.709 | 0.527 |
| AMPUSDT buy_A_sell_B | 85% | 0.676 | 0.454 |
| PUNDIXUSDT buy_A_sell_B | 81% | 0.530 | 0.458 |
