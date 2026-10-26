# Informe nexus — últimas 24 h, 70 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 70 | 70 | 92 | 3.942 |
| hedge_mexc_binance_bnb | 70 | 70 | 92 | 3.968 |
| funding | 70 | 70 | 76 | 3.677 |
| maker_kraken | 70 | 70 | 53 | 4.407 |
| maker_binance | 70 | 70 | 45 | 2.775 |
| peg_kraken | 70 | 70 | 2 | 0.563 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 70 | 0 | 0 | -0.055 |
| bin_tri_BTC | 70 | 0 | 0 | -0.127 |
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
| MEXC INJ_USDT | 100% | 22.7 | 11.5 |
| MEXC XMR_USDT | 100% | 13.9 | 11.0 |
| MEXC XRP_USDT | 100% | 11.0 | 11.0 |
| MEXC DOGE_USD (sin contado) | 100% | 10.7 | 9.5 |
| MEXC XRP_USD (sin contado) | 100% | 10.2 | 8.1 |
| Gate FET_USDT | 93% | 11.0 | 11.0 |
| Gate JCT_USDT (sin contado) | 89% | 54.3 | 18.8 |
| MEXC JCT_USDT | 86% | 67.7 | 25.3 |
| MEXC APR_USDT | 86% | 38.8 | 15.0 |
| Gate AGT_USDT (sin contado) | 86% | 35.2 | 7.1 |
| MEXC AGT_USDT | 81% | 26.6 | 5.9 |
| MEXC XRP_USDC (sin contado) | 81% | 8.6 | 7.1 |

### Cobertura MEXC→Binance persistente (70 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| ATUSDC buy_A_sell_B | 100% | 0.708 | 0.481 |
| BNBUSD1 buy_A_sell_B | 100% | 0.708 | 0.648 |
| ATUSDT buy_A_sell_B | 100% | 0.637 | 0.429 |
| EGLDUSDC buy_A_sell_B | 94% | 0.669 | 0.426 |
| HOMEUSDC buy_A_sell_B | 93% | 0.552 | 0.327 |
| TFUELUSDT buy_A_sell_B | 86% | 1.284 | 0.947 |
| MANTAUSDC sell_A_buy_B | 86% | 1.148 | 0.661 |
| ATMUSDT buy_A_sell_B | 86% | 0.727 | 0.488 |
| STXUSDC buy_A_sell_B | 80% | 0.593 | 0.362 |
| MAGICUSDT buy_A_sell_B | 79% | 0.516 | 0.313 |
| XVGUSDC buy_A_sell_B | 76% | 0.627 | 0.316 |
| INITUSDT buy_A_sell_B | 74% | 0.484 | 0.316 |
