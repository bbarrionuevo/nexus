import pytest
from decimal import Decimal as D
from nexus.core.fees import CostModel, net_profit, breakeven_spread_pct
from nexus.core.compliance import ComplianceGuard, ComplianceError
from nexus.exchanges.base import ReadOnlyViolation
from nexus.exchanges.binance import BinanceReadOnly

COST = CostModel(D("0.001"), D("0.001"), D("0.005"), D("1"), D("0"))
LIM = {"safety_margin": 0.6, "eu": {"cumulative_eur_cap": 10000, "max_tx_per_day": 10, "max_tx_per_hour": 3},
       "ar": {"monthly_ars_cap": 50000000, "per_tx_ars_cap": 2500000}}


def test_small_spread_loses_money():
    assert not net_profit(100, 1.00, 1.005, COST).executable


def test_breakeven_is_zero_roi():
    be = breakeven_spread_pct(100, COST)
    r = net_profit(100, 1, D(1) * (1 + be / 100), COST)
    assert abs(r.net_roi_pct) < D("0.0001")


def test_ar_per_tx_limit(tmp_path):
    g = ComplianceGuard(LIM, tmp_path / "l.json")
    with pytest.raises(ComplianceError):
        g.check("ARS", 2_000_000)  # > 60% de 2.5M


def test_eu_hourly_frequency(tmp_path):
    g = ComplianceGuard(LIM, tmp_path / "l.json")
    for _ in range(3):
        g.record("EUR", 10)
    with pytest.raises(ComplianceError):
        g.check("EUR", 10)


def test_readonly_blocks_orders():
    with pytest.raises(ReadOnlyViolation):
        BinanceReadOnly("k", "s")._get("/api/v3/order")
