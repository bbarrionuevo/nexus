"""Motor de descubrimiento: toma muestras de todas las clases de oportunidad y las guarda en JSONL.

python -m nexus.discover OUT.jsonl [samples] [interval_s]
"""
import json
import sys
import time
from pathlib import Path

from .core.ars_scanner import scan
from .discovery import sources
from .discovery.cross import cross
from .discovery.triangular import cycles

TAKER = {"kraken": 0.40, "bitstamp": 0.40, "coinbase": 0.60}


def sample():
    rec, errs = {"ts": time.time()}, {}
    try:
        kb = sources.kraken_book()
        rec["kraken_pairs"] = len(kb)
        for start in ("EUR", "USDC"):
            cs = cycles(kb, start)
            rec[f"tri_{start}"] = cs[:5]
            rec[f"tri_{start}_maxgross"] = cs and max(c["gross_pct"] for c in cs)
        kraken_eur = {p: (v[2], v[3]) for p, v in kb.items() if v[1] == "EUR" and "(conv)" not in p}
        rec["eurc_peg"] = {p: {"bid": v[2], "ask": v[3], "fee": v[4]} for p, v in kb.items()
                           if v[0] == "EURC" and "(conv)" not in p}
    except Exception as e:
        errs["kraken"], kraken_eur = str(e)[:200], {}
    books = {"kraken": kraken_eur}
    for name, fn in (("bitstamp", sources.bitstamp_book), ("coinbase", sources.coinbase_book)):
        try:
            books[name] = fn()
        except Exception as e:
            errs[name] = str(e)[:200]
    books = {k: v for k, v in books.items() if v}
    # Paridad EURC: vender EURC por encima de 1 (o comprar debajo) y convertir 1:1 gratis en Kraken
    peg = []
    for ex, b in books.items():
        if "EURC/EUR" in b:
            bid, ask = b["EURC/EUR"]
            f = TAKER[ex] / 100
            peg.append({"venue": ex, "sell_net_pct": (bid * (1 - f) - 1) * 100,
                        "buy_net_pct": (1 / (ask * (1 + f)) - 1) * 100})
    rec["eurc_arb"] = [{"net_pct": max(x["sell_net_pct"], x["buy_net_pct"]), **x} for x in peg]
    if len(books) > 1:
        rec["cross_eur"] = cross(books, TAKER)[:5]
    for coin in ("USDT", "USDC", "BTC", "ETH"):
        try:
            q = sources.criptoya(coin)
            ops = scan(q, 160000, {"BTC": 0.00002, "ETH": 0.0005}.get(coin, 1.0), 0.0, now=time.time())
            rec[f"ars_{coin}"] = [{k: (str(v) if not isinstance(v, (str, bool)) else v)
                                   for k, v in vars(o).items()} for o in ops[:3]]
        except Exception as e:
            errs[f"ars_{coin}"] = str(e)[:200]
    rec["errors"] = errs
    return rec


def main(out="data/discovery.jsonl", samples=1, interval=30):
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    for i in range(int(samples)):
        rec = sample()
        with open(out, "a") as f:
            f.write(json.dumps(rec, default=str) + "\n")
        print(i, "errores:", rec["errors"] or "ninguno")
        if i < int(samples) - 1:
            time.sleep(float(interval))


if __name__ == "__main__":
    main(*sys.argv[1:4])
