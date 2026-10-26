# Arbitraje estadístico: backtest fuera de muestra (45 días, velas de 15 min)

Universo (25): BTC, ETH, ZEC, SOL, XRP, NEAR, BNB, ENA, SUI, QNT, WLD, PEPE, UNI, XAUT, DOGE, TRX, BMT, SOXLB, SNDKB, ERA, HYPE, LINK, PUMP, ADA, TAO.
Forma 14 días, opera los 3 siguientes; entra con |z| ≥ 2, sale en 0, stop 4. Costos por lado y pata: contado 0.12%, neutral 0.07%.

| Versión | Vueltas | Ganadoras | Media/vuelta | Cota inferior | Capital total | Por día | Ventanas + |
|---|---|---|---|---|---|---|---|
| neutral | 632 | 25% | -0.096% | -0.130% | -12.17% | -0.271% | 4/15 |
| contado | 632 | 24% | -0.176% | -0.239% | -22.23% | -0.494% | 3/15 |

Neutral necesita margen o futuros (hoy no habilitado). Contado = solo comprar la barata.

## Ventanas

- PEPEUSDT/SOLUSDT, SOXLBUSDT/TAOUSDT, NEARUSDT/ZECUSDT: 27 vueltas · neutral -0.15% · contado -1.16%
- ERAUSDT/PEPEUSDT: 0 vueltas · neutral +0.00% · contado +0.00%
- BMTUSDT/XAUTUSDT: 2 vueltas · neutral -0.46% · contado -0.09%
- BMTUSDT/UNIUSDT, ADAUSDT/SNDKBUSDT: 55 vueltas · neutral -2.49% · contado -3.27%
- BMTUSDT/UNIUSDT, DOGEUSDT/TAOUSDT, ADAUSDT/LINKUSDT: 68 vueltas · neutral +0.24% · contado +3.12%
- ADAUSDT/ERAUSDT, BMTUSDT/SNDKBUSDT, DOGEUSDT/TAOUSDT: 4 vueltas · neutral -0.12% · contado -0.80%
- BMTUSDT/SNDKBUSDT, ERAUSDT/TAOUSDT: 6 vueltas · neutral +0.24% · contado +0.59%
- ADAUSDT/ERAUSDT, UNIUSDT/XRPUSDT, NEARUSDT/SUIUSDT: 6 vueltas · neutral +0.38% · contado -0.33%
- BMTUSDT/XAUTUSDT, ETHUSDT/PEPEUSDT, ADAUSDT/TAOUSDT, DOGEUSDT/XRPUSDT, NEARUSDT/QNTUSDT: 108 vueltas · neutral -2.89% · contado -5.82%
- BMTUSDT/XAUTUSDT, BTCUSDT/SOXLBUSDT, PEPEUSDT/SNDKBUSDT, SOLUSDT/SUIUSDT, ENAUSDT/TAOUSDT: 128 vueltas · neutral -2.86% · contado -4.62%
- BMTUSDT/XAUTUSDT, QNTUSDT/TRXUSDT, DOGEUSDT/XRPUSDT, ERAUSDT/NEARUSDT: 30 vueltas · neutral +1.70% · contado -0.54%
- BMTUSDT/ERAUSDT, LINKUSDT/UNIUSDT, ENAUSDT/ZECUSDT, DOGEUSDT/XRPUSDT: 32 vueltas · neutral -0.15% · contado +0.40%
- BMTUSDT/QNTUSDT, ETHUSDT/LINKUSDT, TAOUSDT/ZECUSDT: 26 vueltas · neutral -1.06% · contado -2.09%
- ADAUSDT/SUIUSDT, PUMPUSDT/SOXLBUSDT, TAOUSDT/ZECUSDT, QNTUSDT/SNDKBUSDT: 90 vueltas · neutral -3.32% · contado -4.56%
- SNDKBUSDT/SOLUSDT, BNBUSDT/BTCUSDT, ENAUSDT/ETHUSDT, DOGEUSDT/SOXLBUSDT, PUMPUSDT/XRPUSDT: 50 vueltas · neutral -1.23% · contado -3.07%
