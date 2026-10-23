# Backtest trading (fuera de muestra, comisión 0.075%/lado)

| símbolo | intervalo | estrategia | params | OOS % | trades | tramos ganados | buy&hold % | ¿robusta? |
|---|---|---|---|---|---|---|---|---|
| BTCUSDT | 15m | sma_cross | (50, 100) | -5.8 | 20 | 1/5 | -2.27 | no |
| BTCUSDT | 15m | rsi_revert | (14, 25, 75) | -0.35 | 8 | 3/5 | -2.27 | no |
| BTCUSDT | 15m | breakout | (50,) | -4.44 | 17 | 2/5 | -2.27 | no |
| BTCUSDT | 1h | sma_cross | (50, 200) | -5.66 | 9 | 1/5 | 3.91 | no |
| BTCUSDT | 1h | rsi_revert | (7, 20, 65) | 4.1 | 27 | 2/5 | 3.91 | no |
| BTCUSDT | 1h | breakout | (100,) | -3.52 | 10 | 1/5 | 3.91 | no |
| BTCUSDT | 4h | sma_cross | (10, 100) | -5.14 | 24 | 1/5 | 17.91 | no |
| BTCUSDT | 4h | rsi_revert | (14, 25, 65) | -9.34 | 8 | 2/5 | 17.91 | no |
| BTCUSDT | 4h | breakout | (50,) | 14.28 | 16 | 2/5 | 17.91 | no |
| ETHUSDT | 15m | sma_cross | (50, 100) | -10.55 | 24 | 2/5 | -6.77 | no |
| ETHUSDT | 15m | rsi_revert | (14, 20, 75) | 4.19 | 10 | 4/5 | -6.77 | no |
| ETHUSDT | 15m | breakout | (50,) | -8.15 | 12 | 2/5 | -6.77 | no |
| ETHUSDT | 1h | sma_cross | (50, 200) | -14.97 | 13 | 1/5 | -4.52 | no |
| ETHUSDT | 1h | rsi_revert | (14, 30, 75) | 17.51 | 18 | 4/5 | -4.52 | no |
| ETHUSDT | 1h | breakout | (20,) | -22.76 | 32 | 2/5 | -4.52 | no |
| ETHUSDT | 4h | sma_cross | (5, 200) | 37.69 | 17 | 3/5 | 19.4 | no |
| ETHUSDT | 4h | rsi_revert | (14, 20, 55) | -3.43 | 4 | 3/5 | 19.4 | no |
| ETHUSDT | 4h | breakout | (100,) | 29.9 | 8 | 3/5 | 19.4 | no |
| SOLUSDT | 15m | sma_cross | (20, 100) | -17.91 | 28 | 1/5 | -10.3 | no |
| SOLUSDT | 15m | rsi_revert | (14, 25, 75) | -9.52 | 8 | 2/5 | -10.3 | no |
| SOLUSDT | 15m | breakout | (100,) | -4.43 | 7 | 3/5 | -10.3 | no |
| SOLUSDT | 1h | sma_cross | (50, 200) | -0.38 | 21 | 3/5 | 7.88 | no |
| SOLUSDT | 1h | rsi_revert | (14, 30, 75) | -1.44 | 26 | 2/5 | 7.88 | no |
| SOLUSDT | 1h | breakout | (20,) | -5.1 | 28 | 1/5 | 7.88 | no |
| SOLUSDT | 4h | sma_cross | (5, 200) | 9.49 | 24 | 2/5 | 19.49 | no |
| SOLUSDT | 4h | rsi_revert | (14, 25, 55) | -13.66 | 4 | 1/5 | 19.49 | no |
| SOLUSDT | 4h | breakout | (20,) | -18.33 | 48 | 2/5 | 19.49 | no |
| BNBUSDT | 15m | sma_cross | (20, 100) | -3.49 | 23 | 2/5 | -3.39 | no |
| BNBUSDT | 15m | rsi_revert | (14, 20, 65) | -4.93 | 4 | 2/5 | -3.39 | no |
| BNBUSDT | 15m | breakout | (50,) | -0.38 | 12 | 3/5 | -3.39 | no |
| BNBUSDT | 1h | sma_cross | (5, 50) | -4.15 | 55 | 2/5 | 4.16 | no |
| BNBUSDT | 1h | rsi_revert | (14, 30, 65) | 4.27 | 18 | 4/5 | 4.16 | no |
| BNBUSDT | 1h | breakout | (50,) | 5.49 | 13 | 3/5 | 4.16 | no |
| BNBUSDT | 4h | sma_cross | (50, 200) | 0.33 | 24 | 1/5 | 20.35 | no |
| BNBUSDT | 4h | rsi_revert | (14, 30, 55) | 4.7 | 5 | 1/5 | 20.35 | no |
| BNBUSDT | 4h | breakout | (100,) | 11.58 | 44 | 1/5 | 20.35 | no |
| XRPUSDT | 15m | sma_cross | (20, 100) | -11.36 | 21 | 2/5 | -8.06 | no |
| XRPUSDT | 15m | rsi_revert | (14, 25, 65) | -8.93 | 9 | 1/5 | -8.06 | no |
| XRPUSDT | 15m | breakout | (50,) | -7.51 | 16 | 2/5 | -8.06 | no |
| XRPUSDT | 1h | sma_cross | (50, 200) | -29.03 | 13 | 1/5 | -16.28 | no |
| XRPUSDT | 1h | rsi_revert | (14, 30, 65) | 10.86 | 25 | 4/5 | -16.28 | SÍ |
| XRPUSDT | 1h | breakout | (10,) | -21.39 | 36 | 1/5 | -16.28 | no |
| XRPUSDT | 4h | sma_cross | (20, 50) | -10.04 | 16 | 3/5 | -14.08 | no |
| XRPUSDT | 4h | rsi_revert | (14, 30, 75) | 11.23 | 9 | 4/5 | -14.08 | no |
| XRPUSDT | 4h | breakout | (10,) | -29.72 | 68 | 1/5 | -14.08 | no |
