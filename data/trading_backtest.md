# Backtest trading (fuera de muestra, comisión 0.075%/lado)

| símbolo | intervalo | estrategia | params | OOS % | trades | tramos ganados | buy&hold % | ¿robusta? |
|---|---|---|---|---|---|---|---|---|
| BTCUSDT | 15m | sma_cross | (50, 100) | -5.71 | 20 | 1/5 | -2.07 | no |
| BTCUSDT | 15m | rsi_revert | (14, 25, 75) | -0.14 | 8 | 3/5 | -2.07 | no |
| BTCUSDT | 15m | breakout | (50,) | -4.44 | 17 | 2/5 | -2.07 | no |
| BTCUSDT | 1h | sma_cross | (50, 200) | -5.57 | 9 | 1/5 | 4.01 | no |
| BTCUSDT | 1h | rsi_revert | (7, 20, 65) | 4.2 | 27 | 2/5 | 4.01 | no |
| BTCUSDT | 1h | breakout | (100,) | -3.42 | 10 | 1/5 | 4.01 | no |
| BTCUSDT | 4h | sma_cross | (10, 100) | -5.14 | 24 | 1/5 | 18.02 | no |
| BTCUSDT | 4h | rsi_revert | (14, 25, 65) | -9.34 | 8 | 2/5 | 18.02 | no |
| BTCUSDT | 4h | breakout | (50,) | 14.38 | 16 | 2/5 | 18.02 | no |
| ETHUSDT | 15m | sma_cross | (50, 100) | -10.49 | 24 | 2/5 | -6.57 | no |
| ETHUSDT | 15m | rsi_revert | (14, 20, 75) | 4.4 | 10 | 4/5 | -6.57 | no |
| ETHUSDT | 15m | breakout | (50,) | -8.22 | 14 | 2/5 | -6.57 | no |
| ETHUSDT | 1h | sma_cross | (50, 200) | -14.93 | 13 | 1/5 | -4.47 | no |
| ETHUSDT | 1h | rsi_revert | (14, 30, 75) | 17.57 | 18 | 4/5 | -4.47 | no |
| ETHUSDT | 1h | breakout | (20,) | -22.76 | 32 | 2/5 | -4.47 | no |
| ETHUSDT | 4h | sma_cross | (5, 200) | 37.69 | 17 | 3/5 | 19.46 | no |
| ETHUSDT | 4h | rsi_revert | (14, 20, 55) | -3.43 | 4 | 3/5 | 19.46 | no |
| ETHUSDT | 4h | breakout | (100,) | 29.9 | 8 | 3/5 | 19.46 | no |
| SOLUSDT | 15m | sma_cross | (20, 100) | -17.96 | 28 | 1/5 | -10.14 | no |
| SOLUSDT | 15m | rsi_revert | (14, 25, 75) | -9.37 | 8 | 2/5 | -10.14 | no |
| SOLUSDT | 15m | breakout | (100,) | -4.43 | 7 | 4/5 | -10.14 | no |
| SOLUSDT | 1h | sma_cross | (50, 200) | -0.37 | 21 | 3/5 | 7.89 | no |
| SOLUSDT | 1h | rsi_revert | (14, 30, 75) | -1.43 | 26 | 2/5 | 7.89 | no |
| SOLUSDT | 1h | breakout | (20,) | -5.09 | 28 | 1/5 | 7.89 | no |
| SOLUSDT | 4h | sma_cross | (5, 200) | 9.49 | 24 | 2/5 | 19.46 | no |
| SOLUSDT | 4h | rsi_revert | (14, 25, 55) | -13.66 | 4 | 1/5 | 19.46 | no |
| SOLUSDT | 4h | breakout | (20,) | -18.36 | 48 | 2/5 | 19.46 | no |
| BNBUSDT | 15m | sma_cross | (20, 100) | -3.23 | 22 | 2/5 | -3.2 | no |
| BNBUSDT | 15m | rsi_revert | (14, 20, 65) | -4.78 | 4 | 2/5 | -3.2 | no |
| BNBUSDT | 15m | breakout | (50,) | -0.18 | 12 | 3/5 | -3.2 | no |
| BNBUSDT | 1h | sma_cross | (5, 50) | -4.09 | 55 | 2/5 | 4.22 | no |
| BNBUSDT | 1h | rsi_revert | (14, 30, 65) | 4.27 | 18 | 4/5 | 4.22 | no |
| BNBUSDT | 1h | breakout | (50,) | 5.49 | 13 | 3/5 | 4.22 | no |
| BNBUSDT | 4h | sma_cross | (50, 200) | 0.33 | 24 | 1/5 | 20.42 | no |
| BNBUSDT | 4h | rsi_revert | (14, 30, 55) | 4.7 | 5 | 1/5 | 20.42 | no |
| BNBUSDT | 4h | breakout | (100,) | 11.58 | 44 | 1/5 | 20.42 | no |
| XRPUSDT | 15m | sma_cross | (20, 100) | -11.18 | 20 | 2/5 | -7.98 | no |
| XRPUSDT | 15m | rsi_revert | (7, 20, 55) | -10.72 | 9 | 1/5 | -7.98 | no |
| XRPUSDT | 15m | breakout | (50,) | -7.62 | 16 | 3/5 | -7.98 | no |
| XRPUSDT | 1h | sma_cross | (50, 200) | -29.12 | 13 | 1/5 | -16.38 | no |
| XRPUSDT | 1h | rsi_revert | (14, 30, 65) | 10.73 | 25 | 4/5 | -16.38 | SÍ |
| XRPUSDT | 1h | breakout | (10,) | -21.49 | 36 | 1/5 | -16.38 | no |
| XRPUSDT | 4h | sma_cross | (20, 50) | -10.15 | 16 | 3/5 | -14.18 | no |
| XRPUSDT | 4h | rsi_revert | (14, 30, 75) | 11.09 | 9 | 4/5 | -14.18 | no |
| XRPUSDT | 4h | breakout | (10,) | -29.72 | 68 | 1/5 | -14.18 | no |
