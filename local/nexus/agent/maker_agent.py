"""Agente autónomo de market making (paper por defecto).

Usa el mismo modelo de cola validado en investigación (live_paper_maker.Book) sobre datos reales.
Modo real deshabilitado hasta que (1) los informes diarios muestren ventaja sostenida y
(2) el usuario lo active explícitamente en config/agent.yaml (live: true) con un broker real.
python -m nexus.agent.maker_agent
"""
import json
import logging
import time
from pathlib import Path

import requests
import yaml

from ..live_paper_maker import Book
from .risk import RiskHalt, RiskManager

CFG = Path(__file__).resolve().parents[2] / "config" / "agent.yaml"
API = "https://api.mexc.com/api/v3"


def main():
    cfg = yaml.safe_load(CFG.read_text())
    if cfg.get("live"):
        raise SystemExit("Modo real no implementado: solo paper trading en esta fase.")
    Path("logs").mkdir(exist_ok=True)
    logging.basicConfig(filename=f"logs/agent_{time.strftime('%F')}.log", level=logging.INFO,
                        format="%(asctime)s %(message)s")
    risk = RiskManager(cfg["risk"])
    s = requests.Session()
    books = {x: Book(x, notional=cfg["notional_eur"], maker=cfg["maker_fee_pct"], taker=cfg["taker_fee_pct"],
                     stop_pct=cfg["stop_pct"]) for x in cfg["symbols"]}
    seen, last_rt = {x: set() for x in books}, {x: 0 for x in books}
    halted_until = 0
    while True:
        if time.time() < halted_until:
            time.sleep(5)
            continue
        for x, bk in books.items():
            try:
                bt = s.get(f"{API}/ticker/bookTicker", params={"symbol": x}, timeout=5).json()
                trades = s.get(f"{API}/trades", params={"symbol": x, "limit": 100}, timeout=5).json()
                if bk.state == "flat":
                    risk.check(cfg["notional_eur"])
                bk.on_book(float(bt["bidPrice"]), float(bt["bidQty"]), float(bt["askPrice"]), float(bt["askQty"]))
                for t in sorted(trades, key=lambda t: t["time"]):
                    k = (t["time"], t["price"], t["qty"], t["isBuyerMaker"])
                    if k not in seen[x]:
                        seen[x].add(k)
                        before = bk.eq
                        bk.on_trade(float(t["price"]), float(t["qty"]), t["isBuyerMaker"])
                        if bk.rt > last_rt[x]:
                            last_rt[x] = bk.rt
                            pnl = bk.eq - before
                            risk.on_close(pnl, pnl < 0)
                            logging.info(json.dumps({"event": "close", "sym": x, "pnl": round(pnl, 4),
                                                     "day_pnl": round(risk.pnl_day, 4)}))
                if len(seen[x]) > 5000:
                    seen[x] = set(list(seen[x])[-2000:])
            except RiskHalt as e:
                logging.warning("RIESGO: %s — pausa 30 min", e)
                halted_until = time.time() + 1800
                break
            except Exception:
                logging.exception("error de datos %s", x)
        time.sleep(cfg["poll_seconds"])


if __name__ == "__main__":
    main()
