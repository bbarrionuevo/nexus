# Informe nexus — últimas 24 h, 76 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 46 | 46 | 66 | 2.721 |
| hedge_mexc_binance_bnb | 46 | 46 | 66 | 2.747 |
| funding | 46 | 46 | 59 | 3.504 |
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

### Funding persistente (46 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC JCT_USDT | 100% | 118.7 | 51.4 |
| MEXC AGT_USDT | 100% | 30.9 | 15.5 |
| MEXC BTR_USDT | 100% | 27.7 | 16.6 |
| MEXC INJ_USDT | 100% | 20.6 | 13.7 |
| MEXC XMR_USDT | 100% | 11.0 | 11.0 |
| Gate JCT_USDT (sin contado) | 91% | 95.6 | 37.7 |
| Gate LIGHT_USDT | 91% | 17.8 | 11.0 |
| Gate BTR_USDT | 91% | 11.0 | 11.0 |
| Gate MAGIC_USDT | 91% | 11.0 | 11.0 |
| Gate ARB_USDT | 91% | 11.0 | 11.0 |
| Gate AAVE_USDT | 91% | 10.4 | 9.4 |
| MEXC MAGMA_USDT | 83% | 10.0 | 5.5 |

### Cobertura MEXC→Binance persistente (46 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| ATMUSDT buy_A_sell_B | 100% | 0.897 | 0.655 |
| DCRUSDT buy_A_sell_B | 100% | 0.762 | 0.507 |
| BNBUSD1 buy_A_sell_B | 100% | 0.685 | 0.655 |
| HOMEUSDC buy_A_sell_B | 96% | 0.581 | 0.420 |
| MANTAUSDC buy_A_sell_B | 93% | 0.769 | 0.374 |
| TFUELUSDT buy_A_sell_B | 91% | 0.960 | 0.438 |
| MANTAUSDC sell_A_buy_B | 91% | 0.749 | 0.402 |
| EGLDUSDC buy_A_sell_B | 91% | 0.736 | 0.527 |
| PUNDIXUSDT buy_A_sell_B | 89% | 0.644 | 0.458 |
| ATUSDC buy_A_sell_B | 87% | 0.743 | 0.495 |
| ATUSDT buy_A_sell_B | 87% | 0.660 | 0.573 |
| IOSTUSDT sell_A_buy_B | 85% | 1.013 | 0.345 |
