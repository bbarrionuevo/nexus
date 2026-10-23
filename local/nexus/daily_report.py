"""Informe diario automático: qué clases de oportunidad dieron ROI neto positivo y cuánto.

python -m nexus.daily_report data/discovery.jsonl > data/report.md
"""
import json
import sys
import time


def best(rec, key):
    v = rec.get(key) or []
    return max((float(x["net_pct"]) for x in v), default=None)


def main(path, hours=24, capital_eur=100):
    since = time.time() - hours * 3600
    rows = [r for r in map(json.loads, open(path)) if r["ts"] >= since]
    keys = ["tri_EUR", "tri_USDC", "cross_eur", "ars_USDT", "ars_USDC", "ars_BTC", "ars_ETH"]
    print(f"# Informe nexus — últimas {hours} h, {len(rows)} muestras\n")
    print("| clase | muestras | con neto>0 | mejor neto % | € estimado si se ejecutara cada positivo |")
    print("|---|---|---|---|---|")
    for k in keys:
        vals = [b for b in (best(r, k) for r in rows) if b is not None]
        pos = [v for v in vals if v > 0]
        eur = sum(v / 100 * capital_eur for v in pos)
        print(f"| {k} | {len(vals)} | {len(pos)} | {max(vals, default=float('nan')):.3f} | {eur:.2f} |")
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
