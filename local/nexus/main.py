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
from .core.ars_scanner import scan
from .exchanges.kraken import KrakenReadOnly
from .exchanges.criptoya import CriptoYa


def load_config():
    cfg = yaml.safe_load((Path(__file__).parent.parent / "config/settings.yaml").read_text())
    env = os.environ.get("NEXUS_PAPER_TRADING")
    if env is not None:
        cfg["paper_trading"] = env.lower() != "false"
    return cfg


def step(cfg, binance, cya, guard, wallet):
    cost = CostModel.from_config(cfg, "kraken", withdrawal="USDC_SOL")
    t = next(iter(binance.ticker(cfg["eu_pair"])["result"].values()))  # Kraken: a=ask, b=bid (EUR/USDC)
    eu_ask, eu_bid = float(t["a"][0]), float(t["b"][0])
    q = cya.quote(cfg["ar_exchange"], "USDC", "ARS", 100)
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


def scan_ars(cfg, cya):
    """Escáner solo-ARS entre plataformas argentinas; registra las mejores rutas."""
    c = cfg["ars_scanner"]
    ops = scan(cya.all_quotes(c["coin"], "ARS", c["volume"]), c["capital_ars"],
               c["transfer_fee_coin"], c["min_net_pct"], now=time.time())
    for o in ops[:3]:
        logging.info("ARS-scan %s->%s bruto=%.2f%% neto=%.2f%% %s", o.buy_at, o.sell_at,
                     o.gross_pct, o.net_pct, "EJECUTABLE" if o.executable else "")


def main():
    cfg = load_config()
    Path("logs").mkdir(exist_ok=True)
    logging.basicConfig(filename=f"logs/{date.today()}.log", level=logging.INFO,
                        format="%(asctime)s %(message)s")
    if not cfg["paper_trading"]:
        raise SystemExit("Trading real deshabilitado: no implementado.")
    binance, cya = KrakenReadOnly(), CriptoYa()
    guard, wallet = ComplianceGuard(cfg["limits"]), PaperWallet(cfg["capital_eur"])
    while True:
        try:
            scan_ars(cfg, cya)
            opp = step(cfg, binance, cya, guard, wallet)
            logging.info("roi=%.3f%% %s wallet=%s", opp.net_roi_pct, opp.reason, wallet.eur)
        except Exception:
            logging.exception("error en ciclo")
        time.sleep(cfg.get("poll_seconds", 60))


if __name__ == "__main__":
    main()
