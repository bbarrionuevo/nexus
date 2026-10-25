# Informe nexus — últimas 24 h, 76 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 66 | 66 | 76 | 2.721 |
| hedge_mexc_binance_bnb | 66 | 66 | 76 | 2.747 |
| funding | 66 | 66 | 65 | 3.504 |
| maker_kraken | 76 | 76 | 54 | 4.493 |
| maker_binance | 76 | 76 | 52 | 2.775 |
| peg_kraken | 76 | 76 | 2 | 0.563 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 76 | 0 | 0 | -0.071 |
| bin_tri_BTC | 76 | 0 | 0 | -0.162 |
| bin_tri_ARS | 76 | 0 | 0 | -0.096 |
| bin_tri_EUR | 76 | 0 | 0 | -0.190 |
| tri_EUR | 76 | 1 | 1 | 0.166 |
| tri_USDC | 76 | 0 | 0 | -0.769 |
| cross_eur | 76 | 0 | 0 | -0.744 |
| eurc_arb | 76 | 0 | 0 | -0.370 |
| ars_USDT | 76 | 0 | 0 | -0.667 |
| ars_USDC | 76 | 0 | 0 | -0.967 |
| ars_BTC | 76 | 0 | 0 | -2.771 |
| ars_ETH | 76 | 0 | 0 | -2.062 |

Triangular EUR: ineficiencia bruta máx 1.377% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (66 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC JCT_USDT | 100% | 112.3 | 51.4 |
| MEXC AGT_USDT | 100% | 36.6 | 15.5 |
| MEXC INJ_USDT | 100% | 19.7 | 11.5 |
| MEXC XMR_USDT | 100% | 14.1 | 11.0 |
| Gate JCT_USDT (sin contado) | 94% | 88.7 | 37.7 |
| Gate LIGHT_USDT | 94% | 15.6 | 11.0 |
| Gate MAGIC_USDT | 94% | 11.0 | 11.0 |
| Gate ARB_USDT | 94% | 11.0 | 11.0 |
| MEXC BTR_USDT | 85% | 25.5 | 14.7 |
| Gate AGT_USDT (sin contado) | 79% | 41.1 | 22.3 |
| Gate BTR_USDT | 79% | 11.0 | 11.0 |
| Gate BEAT_USDT | 76% | 11.0 | 11.0 |

### Cobertura MEXC→Binance persistente (66 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| ATMUSDT buy_A_sell_B | 100% | 0.811 | 0.488 |
| BNBUSD1 buy_A_sell_B | 100% | 0.683 | 0.654 |
| HOMEUSDC buy_A_sell_B | 97% | 0.616 | 0.420 |
| MANTAUSDC sell_A_buy_B | 94% | 0.815 | 0.402 |
| EGLDUSDC buy_A_sell_B | 94% | 0.732 | 0.527 |
| PUNDIXUSDT buy_A_sell_B | 92% | 0.690 | 0.458 |
| ATUSDC buy_A_sell_B | 91% | 0.712 | 0.481 |
| ATUSDT buy_A_sell_B | 91% | 0.629 | 0.429 |
| AWEUSDT buy_A_sell_B | 86% | 0.615 | 0.437 |
| INITUSDT buy_A_sell_B | 86% | 0.507 | 0.316 |
| IOSTUSDT sell_A_buy_B | 85% | 0.982 | 0.345 |
| DCRUSDT buy_A_sell_B | 85% | 0.732 | 0.507 |
