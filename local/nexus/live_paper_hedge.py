"""Paper EN VIVO de market making cubierto: maker en MEXC (0%) + cobertura taker en Binance.

Por cada par se cotiza el mejor bid y el mejor ask de MEXC, solo si al precio actual de Binance la
vuelta cubierta deja al menos `min_edge_pct`. Llenado con el mismo modelo de cola conservador que
el resto del sistema (hay que agotar la cola visible, o que se opere atravesando el precio).
La cobertura NO se hace al precio del momento: se usa el precio de Binance del SIGUIENTE sondeo
(~1-2 s después), para incluir la demora real y el movimiento adverso.
Supuesto: hay inventario en ambos exchanges (USDT y moneda); el costo de rebalancear con
transferencias se estima aparte. Resultado: llenados por hora y ganancia neta realizada.

python -m nexus.live_paper_hedge OUT.jsonl SYM1,SYM2 minutos [taker_binance_pct]
"""
import json
import sys
import time

import requests

MEXC = "https://api.mexc.com/api/v3"
BINANCE = "https://data-api.binance.vision/api/v3"


class Side:
    """Una orden maker en MEXC (compra en el bid o venta en el ask) con modelo de cola."""

    def __init__(self, kind):
        self.kind, self.px, self.queue = kind, None, None

    def quote(self, px, queue):
        if px != self.px:
            self.px, self.queue = px, queue

    def cancel(self):
        self.px, self.queue = None, None

    def hit(self, price, qty, buyer_is_maker):
        """True si la operación pública llena esta orden."""
        if self.px is None:
            return False
        if self.kind == "buy" and buyer_is_maker:            # vendedor agresor golpea bids
            if price < self.px:
                return True
            if price == self.px:
                self.queue -= qty
                return self.queue < 0
        if self.kind == "sell" and not buyer_is_maker:       # comprador agresor levanta asks
            if price > self.px:
                return True
            if price == self.px:
                self.queue -= qty
                return self.queue < 0
        return False


class HedgedPair:
    def __init__(self, sym, notional=40.0, taker_b_pct=0.1, min_edge_pct=0.05):
        self.sym, self.notional, self.fb, self.min_edge = sym, notional, taker_b_pct / 100, min_edge_pct / 100
        self.buy, self.sell = Side("buy"), Side("sell")
        self.pending = []                                    # llenados esperando cobertura (próximo sondeo)
        self.fills, self.pnl, self.adverse = 0, 0.0, 0
        self.b_bid = self.b_ask = None

    def on_books(self, m_bid, m_bq, m_ask, m_aq, b_bid, b_ask):
        # 1) cubrir los llenados del ciclo anterior al precio de Binance de AHORA (demora real)
        for kind, px, edge_then in self.pending:
            if kind == "buy":                                # compré en MEXC: vendo en Binance al bid
                r = b_bid * (1 - self.fb) / px - 1
            else:                                            # vendí en MEXC: compro en Binance al ask
                r = px / (b_ask * (1 + self.fb)) - 1
            self.pnl += self.notional * r
            self.fills += 1
            self.adverse += r < edge_then
        self.pending = []
        self.b_bid, self.b_ask = b_bid, b_ask
        # 2) cotizar solo si la vuelta cubierta deja margen al precio actual
        if b_bid * (1 - self.fb) / m_bid - 1 >= self.min_edge:
            self.buy.quote(m_bid, m_bq)
        else:
            self.buy.cancel()
        if m_ask / (b_ask * (1 + self.fb)) - 1 >= self.min_edge:
            self.sell.quote(m_ask, m_aq)
        else:
            self.sell.cancel()

    def on_trade(self, price, qty, buyer_is_maker):
        for side in (self.buy, self.sell):
            if side.hit(price, qty, buyer_is_maker):
                if side.kind == "buy":
                    edge = self.b_bid * (1 - self.fb) / side.px - 1
                else:
                    edge = side.px / (self.b_ask * (1 + self.fb)) - 1
                self.pending.append((side.kind, side.px, edge))
                side.cancel()                                # se re-cotiza en el próximo ciclo

    def mark(self, minutes):
        return {"sym": self.sym, "fills": self.fills, "pnl_eur": round(self.pnl, 4),
                "per_fill_eur": round(self.pnl / self.fills, 4) if self.fills else None,
                "fills_per_hour": round(self.fills / max(minutes, 1e-9) * 60, 2), "adverse": self.adverse,
                "quoting": [s.kind for s in (self.buy, self.sell) if s.px is not None]}


def run(syms, minutes, out, taker_b_pct=0.1):
    s = requests.Session()
    pairs = {x: HedgedPair(x, taker_b_pct=taker_b_pct) for x in syms}
    seen = {x: set() for x in syms}
    t0, last_dump, errors = time.time(), time.time(), 0
    while time.time() - t0 < minutes * 60:
        for x, hp in pairs.items():
            try:
                m = s.get(f"{MEXC}/ticker/bookTicker", params={"symbol": x}, timeout=5).json()
                b = s.get(f"{BINANCE}/ticker/bookTicker", params={"symbol": x}, timeout=5).json()
                trades = s.get(f"{MEXC}/trades", params={"symbol": x, "limit": 100}, timeout=5).json()
                hp.on_books(float(m["bidPrice"]), float(m["bidQty"]), float(m["askPrice"]), float(m["askQty"]),
                            float(b["bidPrice"]), float(b["askPrice"]))
                for t in sorted(trades, key=lambda t: t["time"]):
                    k = (t["time"], t["price"], t["qty"], t["isBuyerMaker"])
                    if k not in seen[x]:
                        seen[x].add(k)
                        if time.time() - t0 > 5:             # ignora el historial previo al arranque
                            hp.on_trade(float(t["price"]), float(t["qty"]), t["isBuyerMaker"])
                if len(seen[x]) > 4000:
                    seen[x] = set(sorted(seen[x])[-1500:])
            except Exception:
                errors += 1
        time.sleep(0.5)
        if time.time() - last_dump >= 60:
            last_dump = time.time()
            mins = (time.time() - t0) / 60
            snap = {"ts": time.time(), "elapsed_min": round(mins, 1), "taker_b_pct": taker_b_pct,
                    "errors": errors, "pairs": [p.mark(mins) for p in pairs.values()]}
            with open(out, "a") as f:
                f.write(json.dumps(snap) + "\n")
            print(json.dumps(snap), flush=True)


if __name__ == "__main__":
    run(sys.argv[2].split(","), float(sys.argv[3]), sys.argv[1], *(float(a) for a in sys.argv[4:5]))
