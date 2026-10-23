"""Arbitraje de ciclo completo EUR -> USDT -> ARS -> USDT -> EUR (todo en Decimal)."""
from dataclasses import dataclass
from decimal import Decimal as D

from .fees import CostModel


@dataclass(frozen=True)
class Opportunity:
    eur_in: D
    eur_out: D
    net_profit: D
    net_roi_pct: D
    ars_notional: D
    executable: bool
    reason: str


def roundtrip(cap_eur, eu_ask, eu_bid, ar_bid, ar_ask, cost: CostModel,
              min_net_roi_pct=0.0, usdt_transfers=2) -> Opportunity:
    """eu_ask/eu_bid: EUR por USDT en exchange EU. ar_bid/ar_ask: ARS por USDT en P2P.

    El spread P2P ya está en bid/ask, por eso no se descuenta p2p_spread_pct acá.
    Cada traspaso de USDT entre plataformas paga comisión de red (usdt_transfers).
    """
    cap, ea, eb, ab, aa = (D(str(x)) for x in (cap_eur, eu_ask, eu_bid, ar_bid, ar_ask))
    if min(cap, ea, eb, ab, aa) <= 0:
        raise ValueError("valores deben ser > 0")
    usdt = cap * (1 - cost.buy_fee_pct) / ea
    usdt -= cost.network_fee_eur / ea                      # red EU -> P2P
    ars = usdt * ab
    usdt_back = ars / aa - cost.network_fee_eur / ea       # P2P -> EU
    eur = usdt_back * eb * (1 - cost.sell_fee_pct) - cost.bank_transfer_eur
    profit = eur - cap
    roi = profit / cap * 100
    ok = roi > D(str(min_net_roi_pct))
    return Opportunity(cap, eur, profit, roi, ars, ok,
                       "ok" if ok else f"ROI neto {roi:.3f}% <= mínimo {min_net_roi_pct}%")
