"""Agente autónomo de market making — SOLO PAPER (no existe código que envíe órdenes).

- Datos públicos de MEXC (REST). Si hay claves en NEXUS_HOME/.env, verifica la comisión real al
  arrancar y usa la mayor entre la configurada y la real (nunca una menor).
- Toda entrada pasa por el veto del RiskManager (R-03); las salidas siempre se permiten.
- Datos viejos => se cancela la compra pendiente (R-07).
- Estado del paper, riesgo y latido en NEXUS_HOME/state (R-09); logs rotados en NEXUS_HOME/logs.
python -m nexus.agent.maker_agent
"""
import json
import logging
import os
import sys
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

import yaml

from .. import paths
from ..exchanges.mexc import MexcReadOnly, parse_fee
from ..live_paper_maker import Book
from .risk import RiskManager

CFG = Path(__file__).resolve().parents[2] / "config" / "agent.yaml"
log = logging.getLogger("nexus.agent")


class Gate:
    """Adaptador entre los libros (estrategia) y el RiskManager (veto)."""

    def __init__(self, risk):
        self.risk, self.books = risk, {}

    def allow_entry(self, notional, exposure):
        ok = self.risk.allow_entry(notional, exposure)
        return ok

    def exposure(self):
        return sum(b.exposure() for b in self.books.values())

    def record_order(self):
        self.risk.record_order()

    def on_close(self, pnl, was_stop):
        self.risk.on_close(pnl, was_stop)
        log.info(json.dumps({"event": "close", "pnl": round(pnl, 4), "stop": was_stop,
                             "day_pnl": round(self.risk.s["pnl_day"], 4)}))


def setup_logging():
    h = RotatingFileHandler(paths.logs("agent.log"), maxBytes=5_000_000, backupCount=5, encoding="utf-8")
    h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    handlers = [h] + ([logging.StreamHandler()] if sys.stderr and sys.stderr.isatty() else [])
    logging.basicConfig(level=logging.INFO, handlers=handlers)


def load_config():
    cfg = yaml.safe_load(CFG.read_text(encoding="utf-8"))
    if cfg.get("live") is not False:
        raise SystemExit("live debe ser false: el modo real no existe en esta versión (R-02).")
    return cfg


def verified_fees(client, cfg):
    maker, taker = cfg["maker_fee_pct"], cfg["taker_fee_pct"]
    if not client.has_keys:
        log.warning("sin claves MEXC: comisiones no verificadas, se usan las configuradas")
        return maker, taker
    for sym in cfg["symbols"]:
        try:
            f = parse_fee(client.trade_fee(sym))
        except Exception as e:
            log.warning("no se pudo verificar comisión de %s: %s", sym, type(e).__name__)
            continue
        if f:
            maker, taker = max(maker, f[0]), max(taker, f[1])
    log.info("comisiones en uso maker=%.4f%% taker=%.4f%%", maker, taker)
    return maker, taker


def main():
    paths.load_env()
    setup_logging()
    cfg = load_config()
    client = MexcReadOnly()
    maker, taker = verified_fees(client, cfg)
    risk = RiskManager(cfg["risk"])
    gate = Gate(risk)
    saved = paths.read_json(paths.state("paper_books.json"), {})
    for x in cfg["symbols"]:
        bk = Book(x, notional=cfg["risk"]["max_position_eur"], maker=maker, taker=taker, stop_pct=cfg["stop_pct"],
                  min_edge_pct=cfg["min_edge_pct"], max_hold_s=cfg["max_hold_min"] * 60, gate=gate)
        if x in saved:
            bk.load(saved[x])
        gate.books[x] = bk
    version = os.environ.get("NEXUS_VERSION", "desconocida")
    log.info("arranque version=%s simbolos=%s home=%s", version, cfg["symbols"], paths.home())
    seen = {x: set() for x in gate.books}
    last_ok = {x: 0.0 for x in gate.books}
    errors, last_status = [], 0.0
    while True:
        for x, bk in gate.books.items():
            try:
                bt = client.book_ticker(x)
                trades = client.trades(x)
                bk.on_book(float(bt["bidPrice"]), float(bt["bidQty"]), float(bt["askPrice"]), float(bt["askQty"]))
                for t in sorted(trades, key=lambda t: t["time"]):
                    k = (t["time"], t["price"], t["qty"], t["isBuyerMaker"])
                    if k not in seen[x]:
                        seen[x].add(k)
                        bk.on_trade(float(t["price"]), float(t["qty"]), t["isBuyerMaker"])
                if len(seen[x]) > 5000:
                    seen[x] = set(sorted(seen[x])[-2000:])
                last_ok[x] = time.time()
            except Exception as e:
                errors.append(time.time())
                log.warning("error de datos %s: %s", x, type(e).__name__)
            if time.time() - last_ok[x] > cfg["stale_data_s"] and bk.state == "flat" and bk.px is not None:
                bk.px, bk.queue = None, None
                log.warning("datos viejos en %s: se cancela la compra pendiente", x)
        restart = paths.state("RESTART")
        if restart.exists():                             # pedido del actualizador (R-13)
            paths.write_json_atomic(paths.state("paper_books.json"), {x: b.to_dict() for x, b in gate.books.items()})
            restart.unlink()
            log.info("reinicio controlado solicitado: estado guardado, saliendo")
            return
        if time.time() - last_status >= 30:
            last_status = time.time()
            errors = [e for e in errors if time.time() - e < 3600]
            paths.write_json_atomic(paths.state("paper_books.json"), {x: b.to_dict() for x, b in gate.books.items()})
            paths.write_json_atomic(paths.state("status.json"), {
                "ts": time.time(), "version": version, "mode": "paper", "fees": [maker, taker],
                "books": [b.mark() for b in gate.books.values()], "risk": risk.snapshot(),
                "risk_block": risk.last_reason, "errors_last_hour": len(errors),
                "data_age_s": {x: round(time.time() - t, 1) for x, t in last_ok.items()}})
        time.sleep(cfg["poll_seconds"])


if __name__ == "__main__":
    main()
