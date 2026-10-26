# Informe nexus — últimas 24 h, 70 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 70 | 70 | 90 | 3.942 |
| hedge_mexc_binance_bnb | 70 | 70 | 90 | 3.968 |
| funding | 70 | 70 | 98 | 3.677 |
| maker_kraken | 70 | 70 | 61 | 4.262 |
| maker_binance | 70 | 70 | 44 | 2.628 |
| peg_kraken | 70 | 70 | 2 | 0.563 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 70 | 0 | 0 | -0.055 |
| bin_tri_BTC | 70 | 0 | 0 | -0.127 |
| bin_tri_ARS | 70 | 0 | 0 | -0.171 |
| bin_tri_EUR | 70 | 0 | 0 | -0.166 |
| tri_EUR | 70 | 0 | 0 | -0.614 |
| tri_USDC | 70 | 0 | 0 | -0.802 |
| cross_eur | 70 | 0 | 0 | -0.762 |
| eurc_arb | 70 | 0 | 0 | -0.388 |
| ars_USDT | 69 | 0 | 0 | -0.965 |
| ars_USDC | 69 | 0 | 0 | -1.242 |
| ars_BTC | 68 | 0 | 0 | -2.634 |
| ars_ETH | 68 | 0 | 0 | -1.844 |

Triangular EUR: ineficiencia bruta máx 0.237% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (70 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC INJ_USDT | 100% | 22.9 | 15.9 |
| MEXC XMR_USDT | 100% | 11.0 | 11.0 |
| MEXC XRP_USDT | 100% | 11.0 | 11.0 |
| MEXC XRP_USD (sin contado) | 100% | 10.2 | 8.1 |
| Gate JCT_USDT (sin contado) | 89% | 47.8 | 18.8 |
| MEXC CAP_USDT | 86% | 78.9 | 42.2 |
| MEXC JCT_USDT | 86% | 46.5 | 24.2 |
| MEXC DOGE_USD (sin contado) | 86% | 10.7 | 9.5 |
| Gate FET_USDT | 77% | 11.0 | 11.0 |
| MEXC CRV_USDT | 77% | 9.9 | 6.4 |
| Gate CAP_USDT (sin contado) | 76% | 63.5 | 23.3 |
| Gate LIGHT_USDT | 73% | 14.9 | 9.6 |

### Cobertura MEXC→Binance persistente (70 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| TFUELUSDT buy_A_sell_B | 100% | 1.265 | 0.886 |
| BNBUSD1 buy_A_sell_B | 100% | 0.711 | 0.648 |
| ATUSDT buy_A_sell_B | 100% | 0.622 | 0.323 |
| STXUSDC buy_A_sell_B | 96% | 0.621 | 0.362 |
| EGLDUSDC buy_A_sell_B | 94% | 0.628 | 0.426 |
| HOMEUSDC buy_A_sell_B | 91% | 0.522 | 0.327 |
| XVGUSDC buy_A_sell_B | 90% | 0.586 | 0.316 |
| MANTAUSDC buy_A_sell_B | 87% | 1.186 | 0.338 |
| MANTAUSDC sell_A_buy_B | 86% | 1.031 | 0.362 |
| ATMUSDT buy_A_sell_B | 86% | 0.788 | 0.634 |
| ATUSDC buy_A_sell_B | 86% | 0.719 | 0.493 |
| IMXUSDT buy_A_sell_B | 77% | 0.410 | 0.357 |
