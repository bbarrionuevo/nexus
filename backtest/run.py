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
agent = yaml.safe_load(open("local/config/agent.yaml"))
if agent.get("live") is not False: errs.append("agent.live debe ser false hasta aprobación manual")
if agent["risk"]["daily_loss_limit_eur"] > 5: errs.append("límite de pérdida diaria > 5 EUR")
if agent["risk"]["max_notional_eur"] > cfg["capital_eur"]: errs.append("nocional del agente > capital")
print("\n".join(errs) or "gate OK"); sys.exit(1 if errs else 0)
