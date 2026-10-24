"""Informe diario automático: qué clases de oportunidad dieron ROI neto positivo (nivel: observado).

No suma "euros posibles": una misma oportunidad persistente aparece en muchas muestras y
sumarlas la contaría varias veces (hallazgo F-12). Se informan muestras y oportunidades distintas.

python -m nexus.daily_report data/discovery.jsonl > data/report.md
"""
import json
import sys
import time


def _net(x):
    return float(x.get("net_pct", x.get("edge_pct")))


def _label(x):
    return x.get("path") or x.get("pair") or x.get("venue") or f"{x.get('buy_at')}>{x.get('sell_at')}"


def best(rec, key):
    v = rec.get(key) or []
    return max((_net(x) for x in v), default=None)


def main(path, hours=24):
    since = time.time() - hours * 3600
    rows = [r for r in map(json.loads, open(path)) if r["ts"] >= since]
    keys = ["maker_kraken", "maker_binance", "peg_kraken", "peg_binance", "bin_tri_USDT", "bin_tri_BTC", "bin_tri_ARS", "bin_tri_EUR", "tri_EUR", "tri_USDC", "cross_eur", "eurc_arb", "ars_USDT", "ars_USDC", "ars_BTC", "ars_ETH"]
    print(f"# Informe nexus — últimas {hours} h, {len(rows)} muestras\n")
    print("| clase | muestras | muestras con neto>0 | oportunidades distintas >0 | mejor neto % |")
    print("|---|---|---|---|---|")
    for k in keys:
        vals = [b for b in (best(r, k) for r in rows) if b is not None]
        distinct = {_label(x) for r in rows for x in (r.get(k) or []) if _net(x) > 0}
        print(f"| {k} | {len(vals)} | {sum(v > 0 for v in vals)} | {len(distinct)} | "
              f"{max(vals, default=float('nan')):.3f} |")
    tri = [r.get("tri_EUR_maxgross") for r in rows if r.get("tri_EUR_maxgross")]
    if tri:
        print(f"\nTriangular EUR: ineficiencia bruta máx {max(tri):.3f}% "
              "(si una ruta sin comisión la supera, el cuello de botella es el fee).")
    errs = {}
    for r in rows:
        for k in r.get("errors", {}):
            errs[k] = errs.get(k, 0) + 1
    if errs:
        print(f"\nErrores de fuente: {errs}")


if __name__ == "__main__":
    main(sys.argv[1], *map(float, sys.argv[2:]))
