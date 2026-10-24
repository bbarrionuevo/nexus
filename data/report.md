# Informe nexus — últimas 24 h, 76 muestras

| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |
|---|---|---|---|---|
| hedge_mexc_binance | 6 | 6 | 35 | 2.385 |
| hedge_mexc_binance_bnb | 6 | 6 | 35 | 2.411 |
| funding | 6 | 6 | 24 | 2.589 |
| maker_kraken | 59 | 59 | 45 | 149849.500 |
| maker_binance | 59 | 59 | 43 | 4.030 |
| peg_kraken | 65 | 65 | 7 | 48.654 |
| peg_binance | 0 | 0 | 0 | nan |
| bin_tri_USDT | 76 | 0 | 0 | -0.098 |
| bin_tri_BTC | 76 | 0 | 0 | -0.168 |
| bin_tri_ARS | 76 | 0 | 0 | -0.119 |
| bin_tri_EUR | 76 | 0 | 0 | -0.170 |
| tri_EUR | 76 | 2 | 4 | 178.580 |
| tri_USDC | 76 | 0 | 0 | -0.775 |
| cross_eur | 76 | 0 | 0 | -0.751 |
| eurc_arb | 76 | 0 | 0 | -0.380 |
| ars_USDT | 76 | 0 | 0 | -1.054 |
| ars_USDC | 76 | 0 | 0 | -1.028 |
| ars_BTC | 76 | 0 | 0 | -2.582 |
| ars_ETH | 75 | 0 | 0 | -2.162 |

Triangular EUR: ineficiencia bruta máx 181.950% (si una ruta sin comisión la supera, el cuello de botella es el fee).

### Funding persistente (6 muestras): aparece en ≥50% de las muestras
| exchange par | presencia | APR medio % | APR mínimo % |
|---|---|---|---|
| Gate IRYS_USDT | 100% | 65.9 | 60.7 |
| MEXC AGT_USDT | 100% | 63.1 | 62.4 |
| MEXC JCT_USDT | 100% | 51.6 | 51.4 |
| MEXC INJ_USDT | 100% | 24.8 | 24.7 |
| MEXC BTR_USDT | 100% | 17.4 | 16.6 |
| MEXC IRYS_USDT | 100% | 16.5 | 16.3 |
| MEXC XMR_USDT | 100% | 11.0 | 11.0 |
| MEXC FET_USDT | 100% | 11.0 | 11.0 |
| MEXC ICP_USDT | 100% | 11.0 | 11.0 |
| MEXC SHIB_USDT | 100% | 11.0 | 11.0 |
| MEXC BAT_USDT | 100% | 11.0 | 11.0 |
| MEXC STX_USDT | 100% | 11.0 | 11.0 |

### Cobertura MEXC→Binance persistente (6 muestras, taker 0,1%)
| par lado | presencia | margen medio % | margen mínimo % |
|---|---|---|---|
| IOSTUSDT sell_A_buy_B | 100% | 1.147 | 0.998 |
| TFUELUSDT buy_A_sell_B | 100% | 1.070 | 0.993 |
| ATMUSDT sell_A_buy_B | 100% | 0.968 | 0.961 |
| ATMUSDT buy_A_sell_B | 100% | 0.915 | 0.818 |
| QUICKUSDT sell_A_buy_B | 100% | 0.908 | 0.771 |
| MANTAUSDC buy_A_sell_B | 100% | 0.733 | 0.589 |
| BNBUSD1 buy_A_sell_B | 100% | 0.690 | 0.678 |
| ATUSDC sell_A_buy_B | 100% | 0.665 | 0.520 |
| DCRUSDT buy_A_sell_B | 100% | 0.646 | 0.551 |
| BMTUSDT buy_A_sell_B | 83% | 1.652 | 1.305 |
| ZECUSD1 sell_A_buy_B | 83% | 1.023 | 0.990 |
| SOLBTC sell_A_buy_B | 83% | 0.619 | 0.559 |

Errores de fuente: {'ars_ETH': 1}
