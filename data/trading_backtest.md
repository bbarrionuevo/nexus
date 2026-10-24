# Backtest trading (fuera de muestra, comisión 0.075%/lado)

| símbolo | intervalo | estrategia | params | OOS % | trades | tramos ganados | buy&hold % | ¿robusta? |
|---|---|---|---|---|---|---|---|---|
| BTCUSDT | 15m | sma_cross | (50, 100) | -6.09 | 22 | 1/5 | -1.11 | no |
| BTCUSDT | 15m | rsi_revert | (14, 25, 75) | 0.91 | 7 | 1/5 | -1.11 | no |
| BTCUSDT | 15m | breakout | (50,) | -4.58 | 19 | 2/5 | -1.11 | no |
| BTCUSDT | 1h | sma_cross | (50, 200) | -4.02 | 11 | 2/5 | 4.91 | no |
| BTCUSDT | 1h | rsi_revert | (7, 20, 65) | 3.1 | 26 | 2/5 | 4.91 | no |
| BTCUSDT | 1h | breakout | (100,) | -2.49 | 12 | 1/5 | 4.91 | no |
| BTCUSDT | 4h | sma_cross | (10, 100) | -2.89 | 24 | 1/5 | 17.18 | no |
| BTCUSDT | 4h | rsi_revert | (14, 25, 65) | -2.54 | 8 | 3/5 | 17.18 | no |
| BTCUSDT | 4h | breakout | (50,) | 13.1 | 16 | 2/5 | 17.18 | no |
| ETHUSDT | 15m | sma_cross | (50, 100) | -11.64 | 26 | 2/5 | -3.45 | no |
| ETHUSDT | 15m | rsi_revert | (14, 20, 75) | 8.06 | 8 | 4/5 | -3.45 | no |
| ETHUSDT | 15m | breakout | (50,) | -7.03 | 14 | 2/5 | -3.45 | no |
| ETHUSDT | 1h | sma_cross | (50, 200) | -10.94 | 14 | 2/5 | -1.8 | no |
| ETHUSDT | 1h | rsi_revert | (14, 30, 75) | 15.78 | 17 | 4/5 | -1.8 | no |
| ETHUSDT | 1h | breakout | (20,) | -21.35 | 20 | 2/5 | -1.8 | no |
| ETHUSDT | 4h | sma_cross | (5, 200) | 29.88 | 15 | 3/5 | 19.64 | no |
| ETHUSDT | 4h | rsi_revert | (14, 20, 55) | -3.43 | 4 | 3/5 | 19.64 | no |
| ETHUSDT | 4h | breakout | (100,) | 29.9 | 8 | 2/5 | 19.64 | no |
| SOLUSDT | 15m | sma_cross | (50, 100) | -21.04 | 34 | 2/5 | -6.0 | no |
| SOLUSDT | 15m | rsi_revert | (14, 25, 75) | -5.12 | 7 | 2/5 | -6.0 | no |
| SOLUSDT | 15m | breakout | (100,) | -4.5 | 8 | 2/5 | -6.0 | no |
| SOLUSDT | 1h | sma_cross | (50, 200) | 1.85 | 22 | 3/5 | 9.38 | no |
| SOLUSDT | 1h | rsi_revert | (14, 30, 75) | -4.09 | 25 | 2/5 | 9.38 | no |
| SOLUSDT | 1h | breakout | (20,) | 4.47 | 33 | 2/5 | 9.38 | no |
| SOLUSDT | 4h | sma_cross | (5, 200) | 9.49 | 24 | 2/5 | 18.77 | no |
| SOLUSDT | 4h | rsi_revert | (14, 25, 55) | -13.66 | 4 | 1/5 | 18.77 | no |
| SOLUSDT | 4h | breakout | (20,) | -21.43 | 40 | 2/5 | 18.77 | no |
| BNBUSDT | 15m | sma_cross | (20, 100) | -4.21 | 22 | 3/5 | 0.58 | no |
| BNBUSDT | 15m | rsi_revert | (7, 20, 75) | -2.06 | 12 | 2/5 | 0.58 | no |
| BNBUSDT | 15m | breakout | (50,) | 1.18 | 12 | 2/5 | 0.58 | no |
| BNBUSDT | 1h | sma_cross | (10, 50) | -5.3 | 54 | 1/5 | 5.83 | no |
| BNBUSDT | 1h | rsi_revert | (14, 30, 65) | 4.27 | 18 | 3/5 | 5.83 | no |
| BNBUSDT | 1h | breakout | (50,) | 6.42 | 20 | 4/5 | 5.83 | SÍ |
| BNBUSDT | 4h | sma_cross | (50, 200) | 0.33 | 24 | 2/5 | 18.49 | no |
| BNBUSDT | 4h | rsi_revert | (14, 30, 55) | -1.99 | 5 | 1/5 | 18.49 | no |
| BNBUSDT | 4h | breakout | (100,) | 13.7 | 42 | 1/5 | 18.49 | no |
| XRPUSDT | 15m | sma_cross | (20, 100) | -11.42 | 22 | 3/5 | -6.13 | no |
| XRPUSDT | 15m | rsi_revert | (14, 25, 65) | -5.63 | 9 | 3/5 | -6.13 | no |
| XRPUSDT | 15m | breakout | (50,) | -9.0 | 18 | 3/5 | -6.13 | no |
| XRPUSDT | 1h | sma_cross | (50, 200) | -22.73 | 21 | 1/5 | -12.08 | no |
| XRPUSDT | 1h | rsi_revert | (14, 30, 65) | 7.39 | 23 | 4/5 | -12.08 | SÍ |
| XRPUSDT | 1h | breakout | (10,) | -17.71 | 38 | 1/5 | -12.08 | no |
| XRPUSDT | 4h | sma_cross | (20, 50) | -12.95 | 16 | 3/5 | -13.8 | no |
| XRPUSDT | 4h | rsi_revert | (14, 30, 75) | 9.93 | 9 | 3/5 | -13.8 | no |
| XRPUSDT | 4h | breakout | (10,) | -27.88 | 69 | 1/5 | -13.8 | no |
