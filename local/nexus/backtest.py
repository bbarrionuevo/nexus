"""Backtest sobre log de paper trading: python -m nexus.backtest logs/paper_trades.jsonl"""
import json
import sys
from decimal import Decimal as D


def summarize(path):
    recs = [json.loads(l) for l in open(path)]
    ex = [r for r in recs if r["action"] == "executed"]
    pnl = sum((D(r["profit"]) for r in ex), D(0))
    return {"decisions": len(recs), "executed": len(ex), "total_profit_eur": str(pnl),
            "skipped": sum(r["action"] == "skip" for r in recs),
            "blocked": sum(r["action"].startswith("blocked") for r in recs)}


if __name__ == "__main__":
    print(summarize(sys.argv[1]))
