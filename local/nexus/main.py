"""Punto de entrada. Solo paper trading: monitorea, evalúa y simula."""
import logging
import os
import time
from datetime import date
from pathlib import Path

import yaml

from .core.compliance import ComplianceError, ComplianceGuard
from .core.fees import CostModel
from .core.paper import PaperWallet
from .core.strategy import roundtrip
from .exchanges.binance import BinanceReadOnly
from .exchanges.criptoya import CriptoYa


def load_config():
    cfg = yaml.safe_load((Path(__file__).parent.parent / "config/settings.yaml").read_text())
    env = os.environ.get("NEXUS_PAPER_TRADING")
    if env is not None:
        cfg["paper_trading"] = env.lower() != "false"
    return cfg


def step(cfg, binance, cya, guard, wallet):
    cost = CostModel.from_config(cfg, "binance")
    bt = binance.book_ticker("EURUSDT")  # USDT por EUR
    eu_ask, eu_bid = 1 / float(bt["bidPrice"]), 1 / float(bt["askPrice"])  # EUR por USDT
    q = cya.quote("binancep2p", "USDT", "ARS", 100)
    cap = wallet.eur
    opp = roundtrip(cap, eu_ask, eu_bid, q["bid"], q["ask"], cost, cfg["min_net_roi_pct"])
    meta = {"eu_ask": eu_ask, "eu_bid": eu_bid, "ar_bid": q["bid"], "ar_ask": q["ask"]}
    if not opp.executable:
        wallet.log("skip", opp, meta)
        return opp
    try:
        guard.check("EUR", cap)
        guard.check("ARS", opp.ars_notional)
    except ComplianceError as e:
        wallet.log(f"blocked:{e}", opp, meta)
        return opp
    guard.record("EUR", cap)
    guard.record("ARS", opp.ars_notional)
    wallet.execute(opp, meta)
    return opp


def main():
    cfg = load_config()
    Path("logs").mkdir(exist_ok=True)
    logging.basicConfig(filename=f"logs/{date.today()}.log", level=logging.INFO,
                        format="%(asctime)s %(message)s")
    if not cfg["paper_trading"]:
        raise SystemExit("Trading real deshabilitado: no implementado.")
    binance, cya = BinanceReadOnly(), CriptoYa()
    guard, wallet = ComplianceGuard(cfg["limits"]), PaperWallet(cfg["capital_eur"])
    while True:
        try:
            opp = step(cfg, binance, cya, guard, wallet)
            logging.info("roi=%.3f%% %s wallet=%s", opp.net_roi_pct, opp.reason, wallet.eur)
        except Exception:
            logging.exception("error en ciclo")
        time.sleep(cfg.get("poll_seconds", 60))


if __name__ == "__main__":
    main()
