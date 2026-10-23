"""Recolección one-shot (para GitHub Actions): guarda cotizaciones y mejores rutas en JSONL."""
import json
import sys
import time
from pathlib import Path

from .core.ars_scanner import scan
from .exchanges.criptoya import CriptoYa
from .exchanges.kraken import KrakenReadOnly


def sample(out, capital_ars=160000):
    cya, now, rec = CriptoYa(), time.time(), {"ts": time.time()}
    for coin in ("USDT", "USDC"):
        try:
            q = cya.all_quotes(coin, "ARS", 100)
            rec[coin] = {k: {"ask": v.get("totalAsk"), "bid": v.get("totalBid")}
                         for k, v in q.items() if isinstance(v, dict)}
            rec[f"{coin}_best"] = [vars(o) | {k: str(v) for k, v in vars(o).items()}
                                   for o in scan(q, capital_ars, 1.0, 0.0, now=now)[:3]]
        except Exception as e:
            rec[f"{coin}_err"] = str(e)[:200]
    try:
        t = KrakenReadOnly().ticker("USDCEUR")["result"]
        t = next(iter(t.values()))
        rec["kraken_USDCEUR"] = {"ask": t["a"][0], "bid": t["b"][0]}
    except Exception as e:
        rec["kraken_err"] = str(e)[:200]
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    with open(out, "a") as f:
        f.write(json.dumps(rec, default=str) + "\n")
    print("ok", sorted(rec))


def main(out="data/quotes.jsonl", samples=1, interval=0):
    for i in range(int(samples)):
        sample(out)
        if i < int(samples) - 1:
            time.sleep(float(interval))


if __name__ == "__main__":
    main(*sys.argv[1:4])
