"""Paper trading de market making EN VIVO con modelo de cola (Binance, flujo público).

- Se une al mejor bid con 100 EUR equivalentes. Cola delante = cantidad en el bid al llegar.
- Cada operación agresora vendedora a ese precio consume la cola; al agotarla, nos llenan.
  Si se opera por debajo de nuestro precio, llenado total.
- Si el mejor bid se aleja, cancelamos y volvemos a entrar al final de la nueva cola.
- Con inventario: venta en el mejor ask con la misma lógica de cola; stop a mercado (taker).
python -m nexus.live_paper_maker OUT.jsonl SYM1,SYM2 minutos
"""
import json
import sys
import threading
import time

import websocket

WS = "wss://data-stream.binance.vision/stream?streams="


class Book:
    def __init__(self, sym, notional=100.0, maker=0.0, taker=0.1, stop_pct=1.0):
        self.sym, self.notional, self.maker, self.taker, self.stop = sym, notional, maker, taker, stop_pct
        self.bid = self.ask = self.bq = self.aq = None
        self.state, self.px, self.queue, self.qty = "flat", None, 0.0, 0.0
        self.entry, self.eq, self.rt, self.wins, self.stops, self.requotes = 0.0, 0.0, 0, 0, 0, 0

    def on_book(self, b, bq, a, aq):
        self.bid, self.bq, self.ask, self.aq = b, bq, a, aq
        if self.state == "flat":
            if self.px != b:                                  # (re)cotizar al final de la cola
                self.px, self.queue = b, bq
                self.requotes += 1
        elif self.state == "long":
            if b < self.entry * (1 - self.stop / 100):        # stop a mercado
                self._close(b, self.taker, win=False)
            elif self.px != a:
                self.px, self.queue = a, aq
                self.requotes += 1

    def on_trade(self, price, qty, buyer_is_maker):
        if self.px is None:
            return
        if self.state == "flat" and buyer_is_maker:           # vendedor agresor golpea bids
            if price < self.px or (price == self.px and self._consume(qty)):
                self.state, self.entry = "long", self.px
                self.qty = self.notional / self.px
                self.eq -= self.notional * self.maker / 100
                self.px, self.queue = self.ask, self.aq
        elif self.state == "long" and not buyer_is_maker:     # comprador agresor levanta asks
            if price > self.px or (price == self.px and self._consume(qty)):
                self._close(self.px, self.maker, win=True)

    def _consume(self, qty):
        self.queue -= qty
        return self.queue < 0

    def _close(self, px, fee, win):
        self.eq += self.qty * (px - self.entry) - self.qty * px * fee / 100
        self.rt += 1
        self.wins += win
        self.stops += not win
        self.state, self.px, self.queue = "flat", None, 0.0

    def mark(self):
        open_pnl = self.qty * (self.bid - self.entry) if self.state == "long" and self.bid else 0.0
        return {"sym": self.sym, "maker": self.maker, "pnl_eur": round(self.eq + open_pnl, 4),
                "roundtrips": self.rt, "wins": self.wins, "stops": self.stops, "requotes": self.requotes,
                "state": self.state}


def run(syms, minutes, out):
    books = {s: [Book(s, maker=0.0), Book(s, maker=0.1)] for s in syms}
    streams = "/".join(f"{s.lower()}@bookTicker/{s.lower()}@aggTrade" for s in syms)

    def on_msg(_, m):
        d = json.loads(m)["data"]
        s = d["s"]
        for bk in books.get(s, []):
            if "b" in d and "B" in d and "a" in d:
                bk.on_book(float(d["b"]), float(d["B"]), float(d["a"]), float(d["A"]))
            elif d.get("e") == "aggTrade":
                bk.on_trade(float(d["p"]), float(d["q"]), d["m"])

    ws = websocket.WebSocketApp(WS + streams, on_message=on_msg)
    t = threading.Thread(target=ws.run_forever, kwargs={"ping_interval": 20}, daemon=True)
    t.start()
    t0 = time.time()
    while time.time() - t0 < minutes * 60:
        time.sleep(60)
        snap = {"ts": time.time(), "elapsed_min": round((time.time() - t0) / 60, 1),
                "books": [bk.mark() for v in books.values() for bk in v]}
        with open(out, "a") as f:
            f.write(json.dumps(snap) + "\n")
        print(json.dumps(snap), flush=True)
    ws.close()


if __name__ == "__main__":
    run(sys.argv[2].split(","), float(sys.argv[3]), sys.argv[1])
