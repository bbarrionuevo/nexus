"""Evalúa la estrategia del PDF (vender USDT en P2P como maker y recomprar en Fiwind) con datos reales.

R% = P_venta_P2P*(1-maker) / (P_compra_Fiwind*(1+taker)) - 1
P_venta_P2P: para vender hay que competir con los avisos de venta más baratos del P2P (ask de P2P).
"""
import json
import sys


def edge(q, p2p="binancep2p", local="fiwind", maker=0.0, taker=0.0):
    sell = q[p2p]["ask"] * (1 - maker)     # precio competitivo como vendedor en P2P
    buy = q[local]["ask"] * (1 + taker)    # recompra spot (taker) en plataforma local
    return (sell / buy - 1) * 100


if __name__ == "__main__":
    rows = [json.loads(l) for l in open(sys.argv[1])]
    vals = [edge(r["USDT"]) for r in rows if "USDT" in r and "fiwind" in r["USDT"]]
    print(f"muestras={len(vals)} edge% min={min(vals):.2f} medio={sum(vals)/len(vals):.2f} max={max(vals):.2f}"
          f" | muestras >1.5%: {sum(v > 1.5 for v in vals)}")
