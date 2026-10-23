# Backtest trading (fuera de muestra, comisión 0.075%/lado)

| símbolo | intervalo | estrategia | params | OOS % | trades | buy&hold % | ¿le gana? |
|---|---|---|---|---|---|---|---|
| BTCUSDT | 15m | sma_cross | (20, 50) | -0.76 | 6 | -0.2 | no |
| BTCUSDT | 15m | rsi_revert | (7, 20, 75) | -2.4 | 4 | -0.2 | no |
| BTCUSDT | 15m | breakout | (100,) | -0.95 | 2 | -0.2 | no |
| BTCUSDT | 1h | sma_cross | (20, 100) | -4.58 | 6 | -1.56 | no |
| BTCUSDT | 1h | rsi_revert | (7, 20, 75) | -0.99 | 3 | -1.56 | no |
| BTCUSDT | 1h | breakout | (10,) | -3.69 | 13 | -1.56 | no |
| BTCUSDT | 4h | sma_cross | (10, 200) | -0.6 | 2 | 0.22 | no |
| BTCUSDT | 4h | rsi_revert | (7, 30, 65) | 2.35 | 11 | 0.22 | SÍ |
| BTCUSDT | 4h | breakout | (100,) | -0.53 | 2 | 0.22 | no |
| ETHUSDT | 15m | sma_cross | (50, 200) | -1.59 | 2 | 0.06 | no |
| ETHUSDT | 15m | rsi_revert | (14, 20, 75) | 2.61 | 3 | 0.06 | SÍ |
| ETHUSDT | 15m | breakout | (50,) | -1.19 | 2 | 0.06 | no |
| ETHUSDT | 1h | sma_cross | (10, 100) | -7.23 | 8 | -3.92 | no |
| ETHUSDT | 1h | rsi_revert | (14, 25, 75) | 4.46 | 4 | -3.92 | SÍ |
| ETHUSDT | 1h | breakout | (10,) | -5.62 | 15 | -3.92 | no |
| ETHUSDT | 4h | sma_cross | (5, 200) | 2.01 | 2 | -4.57 | SÍ |
| ETHUSDT | 4h | rsi_revert | (14, 20, 75) | -1.47 | 1 | -4.57 | no |
| ETHUSDT | 4h | breakout | (100,) | 2.32 | 2 | -4.57 | SÍ |
| SOLUSDT | 15m | sma_cross | (10, 200) | 0.84 | 2 | -0.23 | SÍ |
| SOLUSDT | 15m | rsi_revert | (7, 30, 65) | -2.09 | 6 | -0.23 | no |
| SOLUSDT | 15m | breakout | (100,) | 0.66 | 2 | -0.23 | SÍ |
| SOLUSDT | 1h | sma_cross | (20, 100) | -6.04 | 4 | -4.34 | no |
| SOLUSDT | 1h | rsi_revert | (14, 30, 75) | -4.41 | 1 | -4.34 | no |
| SOLUSDT | 1h | breakout | (100,) | -3.18 | 1 | -4.34 | no |
| SOLUSDT | 4h | sma_cross | (5, 200) | 4.07 | 2 | -0.71 | SÍ |
| SOLUSDT | 4h | rsi_revert | (14, 30, 75) | 3.72 | 3 | -0.71 | SÍ |
| SOLUSDT | 4h | breakout | (50,) | -4.02 | 4 | -0.71 | no |
| BNBUSDT | 15m | sma_cross | (5, 200) | 1.52 | 3 | 2.19 | no |
| BNBUSDT | 15m | rsi_revert | (14, 25, 65) | -0.73 | 2 | 2.19 | no |
| BNBUSDT | 15m | breakout | (50,) | 2.41 | 3 | 2.19 | SÍ |
| BNBUSDT | 1h | sma_cross | (20, 100) | -3.56 | 5 | 0.41 | no |
| BNBUSDT | 1h | rsi_revert | (14, 25, 75) | 0.33 | 1 | 0.41 | no |
| BNBUSDT | 1h | breakout | (50,) | -1.52 | 4 | 0.41 | no |
| BNBUSDT | 4h | sma_cross | (50, 200) | 1.86 | 2 | 2.85 | no |
| BNBUSDT | 4h | rsi_revert | (14, 30, 75) | 2.23 | 1 | 2.85 | no |
| BNBUSDT | 4h | breakout | (100,) | 0.38 | 2 | 2.85 | no |
| XRPUSDT | 15m | sma_cross | (50, 200) | 1.89 | 2 | 0.37 | SÍ |
| XRPUSDT | 15m | rsi_revert | (14, 25, 65) | -2.32 | 2 | 0.37 | no |
| XRPUSDT | 15m | breakout | (100,) | -0.47 | 2 | 0.37 | no |
| XRPUSDT | 1h | sma_cross | (50, 200) | -5.41 | 1 | -5.93 | no |
| XRPUSDT | 1h | rsi_revert | (14, 30, 75) | -4.3 | 3 | -5.93 | no |
| XRPUSDT | 1h | breakout | (10,) | -0.65 | 9 | -5.93 | no |
| XRPUSDT | 4h | sma_cross | (5, 50) | -18.22 | 12 | -10.77 | no |
| XRPUSDT | 4h | rsi_revert | (14, 25, 75) | -6.56 | 1 | -10.77 | no |
| XRPUSDT | 4h | breakout | (100,) | -22.68 | 4 | -10.77 | no |
