# Informe nexus — últimas 24 h, 70 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 70 | 70 | 90 | 3.942 |
| hedge_mexc_binance_bnb | 70 | 70 | 90 | 3.968 |
| funding | 70 | 70 | 66 | 3.677 |
| maker_kraken | 70 | 70 | 58 | 4.493 |
| maker_binance | 70 | 70 | 43 | 2.775 |
| peg_kraken | 70 | 70 | 2 | 0.563 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 70 | 0 | 0 | -0.055 |
| bin_tri_BTC | 70 | 0 | 0 | -0.158 |
| bin_tri_ARS | 70 | 0 | 0 | -0.096 |
| bin_tri_EUR | 70 | 0 | 0 | -0.166 |
| tri_EUR | 70 | 0 | 0 | -0.614 |
| tri_USDC | 70 | 0 | 0 | -0.769 |
| cross_eur | 70 | 0 | 0 | -0.759 |
| eurc_arb | 70 | 0 | 0 | -0.370 |
| ars_USDT | 69 | 0 | 0 | -0.667 |
| ars_USDC | 69 | 0 | 0 | -1.116 |
| ars_BTC | 68 | 0 | 0 | -2.964 |
| ars_ETH | 68 | 0 | 0 | -1.844 |

Triangular EUR: ineficiencia bruta máx 0.237% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (70 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC JCT_USDT | 100% | 75.3 | 25.3 |
| Gate AGT_USDT (sin contado) | 100% | 33.9 | 7.1 |
| MEXC INJ_USDT | 100% | 21.2 | 11.5 |
| MEXC XMR_USDT | 100% | 13.9 | 11.0 |
| MEXC XRP_USDT | 100% | 11.0 | 11.0 |
| MEXC DOGE_USD (sin contado) | 100% | 10.7 | 9.5 |
| MEXC XRP_USD (sin contado) | 100% | 10.2 | 8.1 |
| Gate JCT_USDT (sin contado) | 97% | 54.0 | 19.3 |
| MEXC AGT_USDT | 96% | 27.9 | 5.9 |
| Gate FET_USDT | 86% | 11.0 | 11.0 |
| Gate ARB_USDT | 83% | 10.9 | 7.6 |
| Gate LIGHT_USDT | 81% | 14.2 | 11.0 |

### Cobertura MEXC→Binance persistente (70 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| ATMUSDT buy_A_sell_B | 100% | 0.748 | 0.488 |
| BNBUSD1 buy_A_sell_B | 100% | 0.708 | 0.648 |
| ATUSDC buy_A_sell_B | 100% | 0.704 | 0.481 |
| ATUSDT buy_A_sell_B | 100% | 0.622 | 0.429 |
| HOMEUSDC buy_A_sell_B | 97% | 0.555 | 0.327 |
| EGLDUSDC buy_A_sell_B | 94% | 0.705 | 0.461 |
| TFUELUSDT buy_A_sell_B | 86% | 1.279 | 0.947 |
| MANTAUSDC sell_A_buy_B | 86% | 1.051 | 0.552 |
| XVGUSDC buy_A_sell_B | 84% | 0.673 | 0.316 |
| INITUSDT buy_A_sell_B | 81% | 0.487 | 0.316 |
| MAGICUSDT buy_A_sell_B | 76% | 0.501 | 0.313 |
| MANTAUSDC buy_A_sell_B | 73% | 1.259 | 0.338 |
