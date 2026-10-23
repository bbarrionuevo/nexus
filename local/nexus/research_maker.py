"""Simulador de market making long-only sobre velas reales (Binance), con llenado conservador.

Ciclo: sin posición -> orden límite de compra en mid*(1-h). Se llena solo si el mínimo de la vela
siguiente la ATRAVIESA (low < bid). Con posición -> orden de venta en entrada*(1+2h); se llena si
high > ask. Stop: si el precio cae `stop_pct` bajo la entrada, sale a mercado (taker).
h = media del spread observado. Comisiones maker/taker por lado.
python -m nexus.research_maker OUT.md SYM1,SYM2 [interval] [velas]
"""
import json
import sys

from .backtest_trading import history


def simulate(k, half_spread_pct, maker=0.1, taker=0.1, stop_pct=1.0, timeout=60):
    h, eq = half_spread_pct / 100, 1.0
    pos, entry, bid, wait, rt, wins, stops = False, 0.0, None, 0, 0, 0, 0
    for i in range(1, len(k)):
        _, o, hi, lo, c, _ = k[i]
        mid = k[i - 1][4]
        if not pos:
            bid = mid * (1 - h)
            if lo < bid:                                   # atravesó: llenado como maker
                pos, entry, wait = True, bid, 0
                eq *= 1 - maker / 100
            continue
        ask = entry * (1 + 2 * h)
        wait += 1
        if lo < entry * (1 - stop_pct / 100) or wait > timeout:   # stop o vencimiento: taker
            px = min(c, entry * (1 - stop_pct / 100)) if lo < entry * (1 - stop_pct / 100) else c
            eq *= px / entry * (1 - taker / 100)
            pos, rt, stops = False, rt + 1, stops + 1
        elif hi > ask:
            eq *= ask / entry * (1 - maker / 100)
            pos, rt, wins = False, rt + 1, wins + 1
    if pos:
        eq *= k[-1][4] / entry * (1 - taker / 100)
    return {"pnl_pct": round((eq - 1) * 100, 3), "roundtrips": rt, "wins": wins, "stops": stops}


def main(out, syms, interval="1m", candles=4320, spreads=None):
    spreads = spreads or {}
    L = [f"# Simulación market making ({interval}, {candles} velas, llenado conservador)\n",
         "| par | medio spread % | maker % | PnL % | vueltas | ganadoras | stops/timeout | PnL €/día con 100€ |",
         "|---|---|---|---|---|---|---|---|"]
    raw = []
    for s in syms:
        try:
            k = history(s, interval, int(candles))
        except Exception as e:
            L.append(f"| {s} | error {str(e)[:60]} |||||||")
            continue
        sec = {"1s": 1, "1m": 60, "5m": 300}[interval]
        days = len(k) * sec / 86400
        for hs in spreads.get(s, [0.15, 0.25, 0.4]):
            for mk in (0.1, 0.075, 0.0):
                r = simulate(k, hs, maker=mk, taker=max(mk, 0.075) if mk else 0.1)
                L.append(f"| {s} | {hs} | {mk} | {r['pnl_pct']} | {r['roundtrips']} | {r['wins']} | {r['stops']} | "
                         f"{r['pnl_pct'] / days:.3f} |")
                raw.append({"sym": s, "interval": interval, "half_spread": hs, "maker": mk, "days": days, **r})
    open(out, "w").write("\n".join(L) + "\n")
    open(out.replace(".md", ".json"), "w").write(json.dumps(raw))
    print("\n".join(L))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2].split(","), *sys.argv[3:5])
