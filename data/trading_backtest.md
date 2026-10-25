# Backtest trading (fuera de muestra, comisión 0.075%/lado)

| símbolo | intervalo | estrategia | params | OOS % | trades | tramos ganados | buy&hold % | ¿robusta? |
|---|---|---|---|---|---|---|---|---|
| BTCUSDT | 15m | sma_cross | (50, 100) | -6.75 | 23 | 1/5 | -2.61 | no |
| BTCUSDT | 15m | rsi_revert | (14, 25, 75) | -0.77 | 9 | 3/5 | -2.61 | no |
| BTCUSDT | 15m | breakout | (50,) | -5.5 | 20 | 2/5 | -2.61 | no |
| BTCUSDT | 1h | sma_cross | (50, 200) | -5.22 | 11 | 2/5 | 3.16 | no |
| BTCUSDT | 1h | rsi_revert | (7, 20, 65) | 1.82 | 25 | 2/5 | 3.16 | no |
| BTCUSDT | 1h | breakout | (100,) | -3.71 | 12 | 1/5 | 3.16 | no |
| BTCUSDT | 4h | sma_cross | (10, 100) | -3.31 | 26 | 2/5 | 18.33 | no |
| BTCUSDT | 4h | rsi_revert | (14, 25, 65) | -1.24 | 9 | 2/5 | 18.33 | no |
| BTCUSDT | 4h | breakout | (50,) | 11.85 | 17 | 2/5 | 18.33 | no |
| ETHUSDT | 15m | sma_cross | (20, 200) | -10.74 | 24 | 1/5 | -6.24 | no |
| ETHUSDT | 15m | rsi_revert | (14, 20, 75) | 4.85 | 9 | 5/5 | -6.24 | no |
| ETHUSDT | 15m | breakout | (20,) | -5.68 | 9 | 2/5 | -6.24 | no |
| ETHUSDT | 1h | sma_cross | (50, 200) | -13.26 | 15 | 2/5 | -5.71 | no |
| ETHUSDT | 1h | rsi_revert | (14, 30, 75) | 8.64 | 27 | 4/5 | -5.71 | SÍ |
| ETHUSDT | 1h | breakout | (50,) | -18.52 | 18 | 1/5 | -5.71 | no |
| ETHUSDT | 4h | sma_cross | (5, 200) | 37.69 | 17 | 3/5 | 18.31 | no |
| ETHUSDT | 4h | rsi_revert | (14, 20, 55) | -3.43 | 4 | 2/5 | 18.31 | no |
| ETHUSDT | 4h | breakout | (100,) | 29.81 | 9 | 3/5 | 18.31 | no |
| SOLUSDT | 15m | sma_cross | (5, 200) | -17.01 | 25 | 1/5 | -7.85 | no |
| SOLUSDT | 15m | rsi_revert | (14, 25, 75) | -7.06 | 8 | 1/5 | -7.85 | no |
| SOLUSDT | 15m | breakout | (100,) | -4.5 | 8 | 3/5 | -7.85 | no |
| SOLUSDT | 1h | sma_cross | (50, 200) | 1.61 | 17 | 2/5 | 5.81 | no |
| SOLUSDT | 1h | rsi_revert | (14, 30, 75) | -3.39 | 26 | 2/5 | 5.81 | no |
| SOLUSDT | 1h | breakout | (20,) | -5.34 | 32 | 2/5 | 5.81 | no |
| SOLUSDT | 4h | sma_cross | (5, 200) | 9.49 | 24 | 2/5 | 18.57 | no |
| SOLUSDT | 4h | rsi_revert | (14, 25, 55) | -13.66 | 4 | 2/5 | 18.57 | no |
| SOLUSDT | 4h | breakout | (20,) | -19.41 | 35 | 2/5 | 18.57 | no |
| BNBUSDT | 15m | sma_cross | (20, 100) | -4.23 | 23 | 0/5 | -0.37 | no |
| BNBUSDT | 15m | rsi_revert | (14, 20, 65) | -1.08 | 6 | 3/5 | -0.37 | no |
| BNBUSDT | 15m | breakout | (50,) | 1.88 | 13 | 4/5 | -0.37 | no |
| BNBUSDT | 1h | sma_cross | (10, 50) | -5.14 | 47 | 1/5 | 4.8 | no |
| BNBUSDT | 1h | rsi_revert | (14, 30, 65) | 6.56 | 19 | 3/5 | 4.8 | no |
| BNBUSDT | 1h | breakout | (50,) | 7.72 | 13 | 4/5 | 4.8 | no |
| BNBUSDT | 4h | sma_cross | (50, 200) | 4.18 | 25 | 2/5 | 19.19 | no |
| BNBUSDT | 4h | rsi_revert | (14, 30, 55) | 5.24 | 5 | 3/5 | 19.19 | no |
| BNBUSDT | 4h | breakout | (100,) | 14.19 | 8 | 1/5 | 19.19 | no |
| XRPUSDT | 15m | sma_cross | (20, 100) | -10.75 | 21 | 2/5 | -6.93 | no |
| XRPUSDT | 15m | rsi_revert | (14, 20, 65) | -3.76 | 11 | 3/5 | -6.93 | no |
| XRPUSDT | 15m | breakout | (50,) | -7.69 | 17 | 3/5 | -6.93 | no |
| XRPUSDT | 1h | sma_cross | (5, 200) | -25.07 | 21 | 2/5 | -15.29 | no |
| XRPUSDT | 1h | rsi_revert | (14, 30, 65) | 6.73 | 24 | 4/5 | -15.29 | SÍ |
| XRPUSDT | 1h | breakout | (10,) | -23.2 | 37 | 2/5 | -15.29 | no |
| XRPUSDT | 4h | sma_cross | (20, 50) | -14.1 | 17 | 4/5 | -11.02 | no |
| XRPUSDT | 4h | rsi_revert | (14, 30, 75) | 14.7 | 9 | 4/5 | -11.02 | no |
| XRPUSDT | 4h | breakout | (10,) | -26.27 | 68 | 1/5 | -11.02 | no |
