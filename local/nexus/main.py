"""Punto de entrada. Fase 1: solo lectura + simulación (paper trading)."""
import json
import logging
import os
from datetime import date
from pathlib import Path

import yaml

from .core.fees import CostModel, breakeven_spread_pct
from .exchanges.criptoya import CriptoYa


def load_config():
    cfg = yaml.safe_load((Path(__file__).parent.parent / "config/settings.yaml").read_text())
    env = os.environ.get("NEXUS_PAPER_TRADING")
    if env is not None:
        cfg["paper_trading"] = env.lower() != "false"
    return cfg


def main():
    cfg = load_config()
    Path("logs").mkdir(exist_ok=True)
    logging.basicConfig(filename=f"logs/{date.today()}.log", level=logging.INFO,
                        format="%(asctime)s %(message)s")
    if not cfg["paper_trading"]:
        raise SystemExit("Trading real deshabilitado: aún no implementado en esta fase.")
    cost = CostModel.from_config(cfg, "binance")
    be = breakeven_spread_pct(cfg["capital_eur"], cost)
    q = CriptoYa().quote("binancep2p", "USDT", "ARS", 100)
    logging.info(json.dumps({"mode": "paper", "breakeven_spread_pct": str(be), "criptoya": q}))
    print(f"[PAPER] spread de equilibrio con {cfg['capital_eur']} EUR: {be:.3f}%")


if __name__ == "__main__":
    main()
