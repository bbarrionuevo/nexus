# Backtest trading (fuera de muestra, comisión 0.075%/lado)

| símbolo | intervalo | estrategia | params | OOS % | trades | tramos ganados | buy&hold % | ¿robusta? |
|---|---|---|---|---|---|---|---|---|
| BTCUSDT | 15m | sma_cross | (50, 100) | -6.73 | 21 | 1/5 | -3.3 | no |
| BTCUSDT | 15m | rsi_revert | (14, 25, 75) | -1.4 | 8 | 3/5 | -3.3 | no |
| BTCUSDT | 15m | breakout | (50,) | -6.04 | 18 | 1/5 | -3.3 | no |
| BTCUSDT | 1h | sma_cross | (50, 200) | -6.68 | 12 | 1/5 | 1.67 | no |
| BTCUSDT | 1h | rsi_revert | (7, 20, 65) | 2.76 | 25 | 3/5 | 1.67 | no |
| BTCUSDT | 1h | breakout | (100,) | -5.2 | 13 | 1/5 | 1.67 | no |
| BTCUSDT | 4h | sma_cross | (10, 100) | -2.89 | 27 | 2/5 | 19.21 | no |
| BTCUSDT | 4h | rsi_revert | (14, 25, 65) | -0.53 | 9 | 2/5 | 19.21 | no |
| BTCUSDT | 4h | breakout | (50,) | 11.85 | 17 | 2/5 | 19.21 | no |
| ETHUSDT | 15m | sma_cross | (20, 50) | -12.95 | 37 | 2/5 | -7.34 | no |
| ETHUSDT | 15m | rsi_revert | (14, 20, 75) | 3.55 | 10 | 4/5 | -7.34 | no |
| ETHUSDT | 15m | breakout | (50,) | -9.44 | 20 | 1/5 | -7.34 | no |
| ETHUSDT | 1h | sma_cross | (50, 200) | -13.82 | 17 | 2/5 | -6.24 | no |
| ETHUSDT | 1h | rsi_revert | (14, 30, 75) | 13.97 | 17 | 4/5 | -6.24 | no |
| ETHUSDT | 1h | breakout | (20,) | -24.99 | 27 | 2/5 | -6.24 | no |
| ETHUSDT | 4h | sma_cross | (5, 200) | 37.69 | 17 | 3/5 | 17.46 | no |
| ETHUSDT | 4h | rsi_revert | (14, 20, 55) | -3.43 | 4 | 3/5 | 17.46 | no |
| ETHUSDT | 4h | breakout | (100,) | 29.81 | 9 | 3/5 | 17.46 | no |
| SOLUSDT | 15m | sma_cross | (20, 50) | -18.48 | 40 | 1/5 | -8.26 | no |
| SOLUSDT | 15m | rsi_revert | (14, 25, 75) | -7.47 | 8 | 1/5 | -8.26 | no |
| SOLUSDT | 15m | breakout | (100,) | -4.43 | 7 | 3/5 | -8.26 | no |
| SOLUSDT | 1h | sma_cross | (50, 200) | -2.2 | 19 | 2/5 | 2.3 | no |
| SOLUSDT | 1h | rsi_revert | (14, 30, 75) | 6.54 | 25 | 2/5 | 2.3 | no |
| SOLUSDT | 1h | breakout | (20,) | -9.98 | 32 | 2/5 | 2.3 | no |
| SOLUSDT | 4h | sma_cross | (5, 200) | 9.95 | 22 | 2/5 | 22.21 | no |
| SOLUSDT | 4h | rsi_revert | (14, 25, 55) | -13.66 | 4 | 3/5 | 22.21 | no |
| SOLUSDT | 4h | breakout | (20,) | -13.33 | 27 | 2/5 | 22.21 | no |
| BNBUSDT | 15m | sma_cross | (10, 100) | -5.19 | 27 | 1/5 | -1.53 | no |
| BNBUSDT | 15m | rsi_revert | (14, 20, 65) | -0.57 | 4 | 2/5 | -1.53 | no |
| BNBUSDT | 15m | breakout | (50,) | 0.07 | 14 | 3/5 | -1.53 | no |
| BNBUSDT | 1h | sma_cross | (10, 50) | -5.04 | 48 | 1/5 | 4.99 | no |
| BNBUSDT | 1h | rsi_revert | (14, 30, 65) | 6.56 | 19 | 4/5 | 4.99 | no |
| BNBUSDT | 1h | breakout | (50,) | 7.4 | 15 | 4/5 | 4.99 | no |
| BNBUSDT | 4h | sma_cross | (50, 200) | 12.68 | 16 | 2/5 | 20.39 | no |
| BNBUSDT | 4h | rsi_revert | (14, 30, 55) | -0.56 | 6 | 2/5 | 20.39 | no |
| BNBUSDT | 4h | breakout | (100,) | 14.19 | 8 | 1/5 | 20.39 | no |
| XRPUSDT | 15m | sma_cross | (20, 100) | -10.6 | 22 | 2/5 | -8.38 | no |
| XRPUSDT | 15m | rsi_revert | (14, 20, 75) | -1.6 | 7 | 2/5 | -8.38 | no |
| XRPUSDT | 15m | breakout | (50,) | -8.08 | 18 | 3/5 | -8.38 | no |
| XRPUSDT | 1h | sma_cross | (5, 200) | -22.64 | 22 | 2/5 | -13.11 | no |
| XRPUSDT | 1h | rsi_revert | (14, 30, 65) | 11.49 | 21 | 5/5 | -13.11 | SÍ |
| XRPUSDT | 1h | breakout | (10,) | -23.98 | 37 | 2/5 | -13.11 | no |
| XRPUSDT | 4h | sma_cross | (20, 50) | -14.1 | 17 | 3/5 | -12.21 | no |
| XRPUSDT | 4h | rsi_revert | (14, 30, 75) | 12.2 | 9 | 4/5 | -12.21 | no |
| XRPUSDT | 4h | breakout | (10,) | -26.98 | 68 | 1/5 | -12.21 | no |
