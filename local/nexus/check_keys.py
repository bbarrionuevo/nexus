"""Verifica la clave de MEXC sin mostrarla: permisos de la cuenta, saldos y comisiones reales.

python -m nexus.check_keys            (lee NEXUS_HOME/.env)
Sale con código 2 si la cuenta permite retiros por API (regla R-01) y con 1 si falla la consulta.
"""
import sys

import yaml

from . import paths
from .agent.maker_agent import CFG
from .exchanges.mexc import MexcReadOnly, parse_fee


def main():
    paths.load_env()
    c = MexcReadOnly()
    if not c.has_keys:
        print(f"No hay MEXC_API_KEY/MEXC_SECRET_KEY en {paths.home() / '.env'}")
        return 1
    try:
        acc = c.account()
    except Exception as e:
        print(f"Error consultando la cuenta: {type(e).__name__}")
        return 1
    bal = {b["asset"]: b["free"] for b in acc.get("balances", []) if float(b.get("free", 0)) > 0}
    print(f"canTrade={acc.get('canTrade')} canWithdraw={acc.get('canWithdraw')} "
          f"permissions={acc.get('permissions')} saldos={bal}")
    for sym in yaml.safe_load(CFG.read_text())["symbols"]:
        try:
            print(sym, "comisión maker/taker %:", parse_fee(c.trade_fee(sym)))
        except Exception as e:
            print(sym, "sin dato de comisión:", type(e).__name__)
    if acc.get("canWithdraw"):
        print("ADVERTENCIA R-01: la cuenta reporta retiros habilitados. Para operar real, la clave "
              "debe crearse SIN permiso de retiro y con lista blanca de IP.")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
