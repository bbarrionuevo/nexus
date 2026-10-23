"""Arbitraje triangular dentro de un exchange (sin tocar bancos ni redes).

Entrada: libro top-of-book {par: (base, quote, bid, ask, fee_pct)}.
Recorre ciclos A->B->C->A empezando en `start` y devuelve el rendimiento neto de cada uno.
"""
from itertools import permutations


def _edges(book):
    """Arista (desde, hacia) -> (tasa, fee, par). Vender base da bid; comprar base cuesta ask."""
    e = {}
    for pair, (base, quote, bid, ask, fee) in book.items():
        if bid > 0:
            e[(base, quote)] = (bid, fee, pair)
        if ask > 0:
            e[(quote, base)] = (1 / ask, fee, pair)
    return e


def cycles(book, start="EUR", fee_override=None):
    e = _edges(book)
    nodes = {a for a, _ in e} | {b for _, b in e}
    out = []
    for b, c in permutations(nodes - {start}, 2):
        legs = [(start, b), (b, c), (c, start)]
        if not all(l in e for l in legs):
            continue
        gross = net = 1.0
        for l in legs:
            rate, fee, _ = e[l]
            fee = fee if fee_override is None else fee_override
            gross *= rate
            net *= rate * (1 - fee / 100)
        out.append({"path": f"{start}>{b}>{c}>{start}", "gross_pct": (gross - 1) * 100,
                    "net_pct": (net - 1) * 100, "pairs": [e[l][2] for l in legs]})
    return sorted(out, key=lambda x: x["net_pct"], reverse=True)
