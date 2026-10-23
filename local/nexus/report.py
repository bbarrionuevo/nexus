"""Resumen de data/quotes.jsonl: python -m nexus.report data/quotes.jsonl [fee_coin] [capital_ars]"""
import json
import sys
from decimal import Decimal as D

from .core.ars_scanner import scan


def main(path, fee=1.0, cap=160000):
    rows = [json.loads(l) for l in open(path)]
    for coin in ("USDT", "USDC"):
        best = []
        for r in rows:
            q = {k: {"totalAsk": v["ask"], "totalBid": v["bid"]} for k, v in r.get(coin, {}).items()}
            ops = scan(q, cap, fee, 0.3)
            if ops:
                best.append((ops[0].net_pct, ops[0].buy_at, ops[0].sell_at, ops[0].gross_pct))
        pos = [b for b in best if b[0] > D("0.3")]
        print(f"{coin}: muestras={len(best)} rentables(>0.3% neto)={len(pos)} "
              f"mejor={max(best, default=None)}")


if __name__ == "__main__":
    main(sys.argv[1], *map(float, sys.argv[2:]))
