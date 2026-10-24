# Informe nexus — últimas 24 h, 86 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 16 | 16 | 49 | 2.385 |
| hedge_mexc_binance_bnb | 16 | 16 | 49 | 2.411 |
| funding | 16 | 16 | 28 | 2.589 |
| maker_kraken | 69 | 69 | 48 | 149849.500 |
| maker_binance | 69 | 69 | 50 | 4.030 |
| peg_kraken | 75 | 75 | 7 | 48.654 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 86 | 0 | 0 | -0.098 |
| bin_tri_BTC | 86 | 0 | 0 | -0.162 |
| bin_tri_ARS | 86 | 0 | 0 | -0.119 |
| bin_tri_EUR | 86 | 0 | 0 | -0.170 |
| tri_EUR | 86 | 2 | 4 | 178.580 |
| tri_USDC | 86 | 0 | 0 | -0.775 |
| cross_eur | 86 | 0 | 0 | -0.744 |
| eurc_arb | 86 | 0 | 0 | -0.380 |
| ars_USDT | 86 | 0 | 0 | -1.054 |
| ars_USDC | 86 | 0 | 0 | -0.967 |
| ars_BTC | 86 | 0 | 0 | -2.582 |
| ars_ETH | 85 | 0 | 0 | -2.162 |

Triangular EUR: ineficiencia bruta máx 181.950% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (16 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| MEXC JCT_USDT | 100% | 76.6 | 51.4 |
| MEXC AGT_USDT | 100% | 46.1 | 34.8 |
| MEXC BTR_USDT | 100% | 23.1 | 16.6 |
| MEXC INJ_USDT | 100% | 22.2 | 20.6 |
| MEXC XMR_USDT | 100% | 11.0 | 11.0 |
| MEXC ICP_USDT | 100% | 11.0 | 11.0 |
| MEXC STX_USDT | 100% | 11.0 | 11.0 |
| MEXC FET_USDT | 100% | 9.2 | 8.0 |
| MEXC BAT_USDT | 100% | 9.0 | 7.6 |
| Gate JCT_USDT (sin contado) | 75% | 126.6 | 106.9 |
| Gate AGT_USDT (sin contado) | 75% | 32.5 | 22.3 |
| Gate BTR_USDT | 75% | 11.0 | 11.0 |

### Cobertura MEXC→Binance persistente (16 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| IOSTUSDT sell_A_buy_B | 100% | 1.239 | 0.998 |
| ATMUSDT buy_A_sell_B | 100% | 0.907 | 0.818 |
| ATMUSDT sell_A_buy_B | 100% | 0.863 | 0.799 |
| ATUSDC sell_A_buy_B | 100% | 0.705 | 0.520 |
| BNBUSD1 buy_A_sell_B | 100% | 0.694 | 0.677 |
| DCRUSDT buy_A_sell_B | 100% | 0.633 | 0.512 |
| MANTAUSDC buy_A_sell_B | 94% | 0.792 | 0.589 |
| ZECUSD1 sell_A_buy_B | 94% | 0.668 | 0.441 |
| HOMEUSDC buy_A_sell_B | 88% | 0.596 | 0.420 |
| BMTUSDT buy_A_sell_B | 81% | 1.223 | 0.599 |
| TFUELUSDT buy_A_sell_B | 75% | 0.754 | 0.438 |
| EGLDUSDC buy_A_sell_B | 75% | 0.717 | 0.527 |

Errores de fuente: {'ars_ETH': 1}
