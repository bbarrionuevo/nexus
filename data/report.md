# Informe nexus — últimas 24 h, 70 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 70 | 70 | 91 | 3.942 |
| hedge_mexc_binance_bnb | 70 | 70 | 91 | 3.968 |
| funding | 70 | 70 | 82 | 3.677 |
| maker_kraken | 70 | 70 | 58 | 4.262 |
| maker_binance | 70 | 70 | 42 | 2.628 |
| peg_kraken | 70 | 70 | 2 | 0.563 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 70 | 0 | 0 | -0.055 |
| bin_tri_BTC | 70 | 0 | 0 | -0.127 |
| bin_tri_ARS | 70 | 0 | 0 | -0.171 |
| bin_tri_EUR | 70 | 0 | 0 | -0.166 |
| tri_EUR | 70 | 0 | 0 | -0.614 |
| tri_USDC | 70 | 0 | 0 | -0.769 |
| cross_eur | 70 | 0 | 0 | -0.763 |
| eurc_arb | 70 | 0 | 0 | -0.380 |
| ars_USDT | 69 | 0 | 0 | -0.667 |
| ars_USDC | 69 | 0 | 0 | -1.116 |
| ars_BTC | 68 | 0 | 0 | -2.634 |
| ars_ETH | 68 | 0 | 0 | -1.844 |

Triangular EUR: ineficiencia bruta máx 0.237% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (70 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC INJ_USDT | 100% | 24.0 | 19.9 |
| MEXC XMR_USDT | 100% | 13.9 | 11.0 |
| MEXC XRP_USDT | 100% | 11.0 | 11.0 |
| MEXC DOGE_USD (sin contado) | 100% | 10.7 | 9.5 |
| MEXC XRP_USD (sin contado) | 100% | 10.2 | 8.1 |
| Gate FET_USDT | 91% | 11.0 | 11.0 |
| Gate JCT_USDT (sin contado) | 89% | 51.6 | 18.8 |
| Gate CAP_USDT (sin contado) | 87% | 56.3 | 7.9 |
| MEXC CAP_USDT | 86% | 78.9 | 42.2 |
| MEXC JCT_USDT | 86% | 56.0 | 25.3 |
| MEXC APR_USDT | 86% | 38.8 | 15.0 |
| Gate AGT_USDT (sin contado) | 86% | 35.6 | 7.1 |

### Cobertura MEXC→Binance persistente (70 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| BNBUSD1 buy_A_sell_B | 100% | 0.709 | 0.648 |
| ATUSDT buy_A_sell_B | 100% | 0.608 | 0.323 |
| EGLDUSDC buy_A_sell_B | 94% | 0.638 | 0.426 |
| STXUSDC buy_A_sell_B | 94% | 0.601 | 0.362 |
| HOMEUSDC buy_A_sell_B | 91% | 0.509 | 0.327 |
| TFUELUSDT buy_A_sell_B | 86% | 1.294 | 1.067 |
| MANTAUSDC sell_A_buy_B | 86% | 1.112 | 0.362 |
| ATMUSDT buy_A_sell_B | 86% | 0.779 | 0.634 |
| ATUSDC buy_A_sell_B | 86% | 0.711 | 0.493 |
| RUNEUSDC buy_A_sell_B | 81% | 0.494 | 0.315 |
| XVGUSDC buy_A_sell_B | 76% | 0.604 | 0.316 |
| IMXUSDT buy_A_sell_B | 76% | 0.410 | 0.357 |
