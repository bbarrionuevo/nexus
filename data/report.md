# Informe nexus — últimas 24 h, 70 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 70 | 70 | 84 | 3.942 |
| hedge_mexc_binance_bnb | 70 | 70 | 84 | 3.968 |
| funding | 70 | 70 | 68 | 3.677 |
| maker_kraken | 70 | 70 | 55 | 4.493 |
| maker_binance | 70 | 70 | 45 | 2.775 |
| peg_kraken | 70 | 70 | 2 | 0.563 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 70 | 0 | 0 | -0.071 |
| bin_tri_BTC | 70 | 0 | 0 | -0.158 |
| bin_tri_ARS | 70 | 0 | 0 | -0.096 |
| bin_tri_EUR | 70 | 0 | 0 | -0.190 |
| tri_EUR | 70 | 0 | 0 | -0.668 |
| tri_USDC | 70 | 0 | 0 | -0.769 |
| cross_eur | 70 | 0 | 0 | -0.759 |
| eurc_arb | 70 | 0 | 0 | -0.370 |
| ars_USDT | 70 | 0 | 0 | -0.667 |
| ars_USDC | 70 | 0 | 0 | -1.116 |
| ars_BTC | 70 | 0 | 0 | -2.876 |
| ars_ETH | 70 | 0 | 0 | -1.888 |

Triangular EUR: ineficiencia bruta máx 0.237% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (70 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC JCT_USDT | 100% | 107.6 | 66.7 |
| MEXC AGT_USDT | 100% | 29.6 | 15.5 |
| MEXC INJ_USDT | 100% | 20.7 | 11.5 |
| MEXC XMR_USDT | 100% | 13.9 | 11.0 |
| MEXC DOGE_USD (sin contado) | 100% | 10.2 | 7.6 |
| Gate JCT_USDT (sin contado) | 97% | 72.2 | 19.3 |
| Gate ARB_USDT | 97% | 10.9 | 7.6 |
| Gate AGT_USDT (sin contado) | 86% | 41.7 | 9.4 |
| Gate BEAT_USDT | 86% | 11.0 | 11.0 |
| Gate XMR_USDT (sin contado) | 86% | 11.0 | 11.0 |
| MEXC XRP_USD (sin contado) | 86% | 10.0 | 8.1 |
| Gate LIGHT_USDT | 81% | 19.1 | 11.0 |

### Cobertura MEXC→Binance persistente (70 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| ATMUSDT buy_A_sell_B | 100% | 0.790 | 0.488 |
| ATUSDC buy_A_sell_B | 100% | 0.726 | 0.481 |
| BNBUSD1 buy_A_sell_B | 100% | 0.707 | 0.648 |
| EGLDUSDC buy_A_sell_B | 100% | 0.703 | 0.461 |
| ATUSDT buy_A_sell_B | 100% | 0.633 | 0.429 |
| HOMEUSDC buy_A_sell_B | 100% | 0.598 | 0.384 |
| TFUELUSDT buy_A_sell_B | 86% | 1.227 | 0.865 |
| MANTAUSDC sell_A_buy_B | 86% | 0.904 | 0.512 |
| DCRUSDT buy_A_sell_B | 86% | 0.807 | 0.507 |
| AWEUSDT buy_A_sell_B | 86% | 0.622 | 0.336 |
| AWEUSDT sell_A_buy_B | 86% | 0.618 | 0.286 |
| PUNDIXUSDT buy_A_sell_B | 84% | 0.662 | 0.310 |
