# Informe nexus — últimas 24 h, 76 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 76 | 76 | 82 | 3.942 |
| hedge_mexc_binance_bnb | 76 | 76 | 82 | 3.968 |
| funding | 76 | 76 | 69 | 3.677 |
| maker_kraken | 76 | 76 | 56 | 4.493 |
| maker_binance | 76 | 76 | 51 | 2.775 |
| peg_kraken | 76 | 76 | 2 | 0.563 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 76 | 0 | 0 | -0.071 |
| bin_tri_BTC | 76 | 0 | 0 | -0.158 |
| bin_tri_ARS | 76 | 0 | 0 | -0.096 |
| bin_tri_EUR | 76 | 0 | 0 | -0.190 |
| tri_EUR | 76 | 0 | 0 | -0.668 |
| tri_USDC | 76 | 0 | 0 | -0.769 |
| cross_eur | 76 | 0 | 0 | -0.744 |
| eurc_arb | 76 | 0 | 0 | -0.370 |
| ars_USDT | 76 | 0 | 0 | -0.667 |
| ars_USDC | 76 | 0 | 0 | -0.967 |
| ars_BTC | 76 | 0 | 0 | -2.876 |
| ars_ETH | 76 | 0 | 0 | -2.014 |

Triangular EUR: ineficiencia bruta máx 0.196% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (76 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC JCT_USDT | 100% | 106.4 | 51.4 |
| MEXC AGT_USDT | 100% | 33.9 | 15.5 |
| MEXC INJ_USDT | 100% | 21.1 | 11.5 |
| MEXC XMR_USDT | 100% | 13.7 | 11.0 |
| Gate ARB_USDT | 95% | 11.0 | 11.0 |
| Gate JCT_USDT (sin contado) | 92% | 84.1 | 19.3 |
| Gate MAGIC_USDT | 83% | 11.0 | 11.0 |
| Gate AGT_USDT (sin contado) | 82% | 41.7 | 9.4 |
| Gate LIGHT_USDT | 82% | 15.6 | 11.0 |
| Gate BEAT_USDT | 79% | 11.0 | 11.0 |
| Gate XMR_USDT (sin contado) | 79% | 11.0 | 11.0 |
| MEXC DOGE_USD (sin contado) | 79% | 10.2 | 7.6 |

### Cobertura MEXC→Binance persistente (76 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| ATMUSDT buy_A_sell_B | 100% | 0.789 | 0.488 |
| BNBUSD1 buy_A_sell_B | 100% | 0.707 | 0.648 |
| HOMEUSDC buy_A_sell_B | 97% | 0.606 | 0.420 |
| MANTAUSDC sell_A_buy_B | 95% | 0.873 | 0.402 |
| EGLDUSDC buy_A_sell_B | 95% | 0.708 | 0.461 |
| ATUSDC buy_A_sell_B | 92% | 0.722 | 0.481 |
| ATUSDT buy_A_sell_B | 92% | 0.634 | 0.429 |
| DCRUSDT buy_A_sell_B | 87% | 0.763 | 0.507 |
| AWEUSDT buy_A_sell_B | 86% | 0.614 | 0.437 |
| PUNDIXUSDT buy_A_sell_B | 83% | 0.681 | 0.388 |
| TFUELUSDT buy_A_sell_B | 82% | 1.058 | 0.438 |
| AWEUSDT sell_A_buy_B | 80% | 0.620 | 0.391 |
