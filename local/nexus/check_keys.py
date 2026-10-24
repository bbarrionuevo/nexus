"""Verifica las claves de NEXUS_HOME/.env SIN mostrarlas: MEXC, Binance y Kraken.

python -m nexus.check_keys
Muestra si cada clave responde, permisos que informa la cuenta, cantidad de activos con saldo y,
para MEXC, la comisión real. CriptoYa no usa clave: su API es pública.
Código de salida: 0 todo bien · 1 alguna clave falla · 2 alguna cuenta informa retiros habilitados
(R-01: para operar real, la clave debe crearse SIN permiso de retiro y con lista blanca de IP).
"""
import os
import sys

import yaml

from . import paths
from .agent.maker_agent import CFG
from .exchanges.binance import BinanceReadOnly
from .exchanges.kraken import KrakenReadOnly
from .exchanges.mexc import MexcReadOnly, parse_fee


def _nonzero(balances, key_free="free"):
    return sum(1 for b in balances if float(b.get(key_free, 0) or 0) > 0)


def check_mexc(c):
    acc = c.account()
    fees = {}
    for sym in yaml.safe_load(CFG.read_text(encoding="utf-8"))["symbols"]:
        try:
            fees[sym] = parse_fee(c.trade_fee(sym))
        except Exception as e:
            fees[sym] = f"sin dato ({type(e).__name__})"
    return {"canTrade": acc.get("canTrade"), "canWithdraw": acc.get("canWithdraw"),
            "permissions": acc.get("permissions"), "activos_con_saldo": _nonzero(acc.get("balances", [])),
            "comision_maker_taker_pct": fees}


def check_binance(c):
    acc = c._get("/api/v3/account", signed=True)
    rates = acc.get("commissionRates") or {}
    return {"canTrade": acc.get("canTrade"), "canWithdraw": acc.get("canWithdraw"),
            "permissions": acc.get("permissions"), "activos_con_saldo": _nonzero(acc.get("balances", [])),
            "comision_maker_taker_pct": (float(rates["maker"]) * 100, float(rates["taker"]) * 100)
            if rates else None}


def check_kraken(c):
    bal = c.balances()
    return {"responde": True, "activos_con_saldo": sum(1 for v in bal.values() if float(v) > 0)}


EXCHANGES = (
    ("MEXC", "MEXC_API_KEY", "MEXC_SECRET_KEY", MexcReadOnly, check_mexc),
    ("Binance", "BINANCE_API_KEY", "BINANCE_SECRET_KEY", BinanceReadOnly, check_binance),
    ("Kraken", "KRAKEN_API_KEY", "KRAKEN_SECRET_KEY", KrakenReadOnly, check_kraken),
)


def run(exchanges=EXCHANGES, out=print):
    code = 0
    for name, k, s, cls, fn in exchanges:
        if not (os.environ.get(k) and os.environ.get(s)):
            out(f"{name}: sin clave en .env (se omite)")
            continue
        try:
            r = fn(cls())
        except Exception as e:
            out(f"{name}: ERROR al consultar ({type(e).__name__}) — revisá la clave o sus permisos de lectura")
            code = max(code, 1)
            continue
        out(f"{name}: OK {r}")
        if r.get("canWithdraw"):
            out(f"  ADVERTENCIA R-01 ({name}): la cuenta informa retiros habilitados. Puede ser un dato de la "
                "cuenta y no de la clave: confirmá en la web que la clave NO tenga permiso de retiro.")
            code = max(code, 2)
    out("CriptoYa: no usa clave (API pública).")
    return code


def main():
    paths.load_env()
    return run()


if __name__ == "__main__":
    sys.exit(main())
