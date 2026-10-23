"""Gate de seguridad: falla si se relajan límites o se desactiva paper trading."""
import sys
import yaml

cfg = yaml.safe_load(open("local/config/settings.yaml"))
errs = []
if cfg["limits"]["safety_margin"] > 0.8: errs.append("safety_margin > 0.8")
if cfg["limits"]["eu"]["cumulative_eur_cap"] > 10000: errs.append("tope EUR > 10000")
if cfg["limits"]["ar"]["monthly_ars_cap"] > 50_000_000: errs.append("tope ARS mensual > 50M")
if cfg["limits"]["ar"]["per_tx_ars_cap"] > 2_500_000: errs.append("tope ARS por tx > 2.5M")
if cfg["paper_trading"] is not True: errs.append("paper_trading debe seguir en true hasta aprobación manual")
print("\n".join(errs) or "gate OK"); sys.exit(1 if errs else 0)
