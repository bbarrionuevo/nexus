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


def test_roundtrip_no_edge_loses():
    from nexus.core.strategy import roundtrip
    o = roundtrip(100, 0.92, 0.91, 1400, 1410, COST)
    assert not o.executable and o.net_roi_pct < 0


def test_roundtrip_with_edge_profits():
    from nexus.core.strategy import roundtrip
    o = roundtrip(100, 0.92, 0.92, 1500, 1400, COST)
    assert o.executable


def test_paper_wallet_and_backtest(tmp_path):
    from nexus.core.strategy import roundtrip
    from nexus.core.paper import PaperWallet
    from nexus.backtest import summarize
    w = PaperWallet(100, tmp_path / "w.json", tmp_path / "j.jsonl")
    w.execute(roundtrip(100, 0.92, 0.92, 1500, 1400, COST))
    assert w.eur > 100
    assert summarize(tmp_path / "j.jsonl")["executed"] == 1


def test_ars_scanner_finds_and_rejects():
    from nexus.core.ars_scanner import scan
    q = {"A": {"totalAsk": 1600, "totalBid": 1590}, "B": {"totalAsk": 1650, "totalBid": 1640}}
    ops = scan(q, 160000, 1.0, 0.3)
    assert ops[0].buy_at == "A" and ops[0].sell_at == "B" and ops[0].executable
    assert not scan(q, 160000, 5.0, 0.3)[0].executable   # fee fijo alto la anula


def test_opportunities_rank_small_capital():
    from nexus.core.opportunities import DEFAULTS, rank
    top = rank(DEFAULTS, 100)
    assert top[0][1] < 5          # con 100 EUR, ninguna estrategia pasa de unos pocos EUR/año


def test_scanner_discards_outlier():
    from nexus.core.ars_scanner import scan
    q = {"A": {"totalAsk": 1640, "totalBid": 1636}, "B": {"totalAsk": 1642, "totalBid": 1638},
         "C": {"totalAsk": 1641, "totalBid": 1637}, "X": {"totalAsk": 1650, "totalBid": 1800}}
    assert all(o.sell_at != "X" and o.buy_at != "X" for o in scan(q, 160000, 1.0))


def test_triangular_detects_mispricing():
    from nexus.discovery.triangular import cycles
    book = {"BTC/EUR": ("BTC", "EUR", 100, 100, 0), "ETH/EUR": ("ETH", "EUR", 10, 10, 0),
            "ETH/BTC": ("ETH", "BTC", 0.11, 0.11, 0)}  # ETH caro en BTC
    best = cycles(book, "EUR")[0]
    assert best["path"] == "EUR>ETH>BTC>EUR" and abs(best["gross_pct"] - 10) < 1e-9


def test_cross_exchange():
    from nexus.discovery.cross import cross
    r = cross({"a": {"X/EUR": (99, 100)}, "b": {"X/EUR": (102, 103)}}, {"a": 0.4, "b": 0.4})[0]
    assert r["buy"] == "a" and r["sell"] == "b" and 1 < r["net_pct"] < 2


def test_backtester_runs_on_synthetic():
    import math
    from nexus.backtest_trading import evaluate
    k = [(i, 0, 100 + 10 * math.sin(i / 20) + 1, 100 + 10 * math.sin(i / 20) - 1,
          100 + 10 * math.sin(i / 20), 1) for i in range(600)]
    res, bh = evaluate(k, folds=3)
    assert len(res) == 3 and all("oos_pct" in r for r in res)


def test_peg_scanner_finds_premium_bid():
    from nexus.discovery.peg import scan_peg
    book = {"EUR/USD": ("EUR", "USD", 1.12, 1.12, 0.2, 1e6, 1e6, 1e9),
            "EURQ/USD": ("EURQ", "USD", 1.155, 1.16, 0.2, 50, 50, 1000)}
    top = scan_peg(book)[0]
    assert top["pair"] == "EURQ/USD" and top["side"] == "sell" and top["net_pct"] > 2.5


def test_peg_ignores_depegged_and_maker_scan():
    from nexus.discovery.peg import scan_peg
    from nexus.discovery.maker import scan_maker
    book = {"EUR/USD": ("EUR", "USD", 1.12, 1.12, 0.2, 1e6, 1e6, 1e9),
            "EURR/EUR": ("EURR", "EUR", 0.6, 0.67, 0.2, 50, 50, 1000)}
    assert scan_peg(book) == []
    m = scan_maker([("X/EUR", 100, 101, 50000), ("Y/EUR", 100, 100.1, 50000)], 0.25)
    assert [r["pair"] for r in m] == ["X/EUR"]


def test_live_maker_queue_model():
    from nexus.live_paper_maker import Book
    b = Book("X", notional=100, maker=0.0)
    b.on_book(10.0, 50, 10.1, 50)             # nos unimos al bid con 50 delante
    b.on_trade(10.0, 30, True)                # se consumen 30: aún no llenados
    assert b.state == "flat"
    b.on_trade(10.0, 25, True)                # se agota la cola: llenado
    assert b.state == "long" and b.entry == 10.0
    b.on_trade(10.1, 60, False)               # cola del ask (50) consumida: vendemos
    assert b.state == "flat" and b.rt == 1 and b.mark()["pnl_eur"] > 0


def test_risk_manager_halts(tmp_path):
    from nexus.agent.risk import RiskManager, RiskHalt
    r = RiskManager({"max_notional_eur": 100, "daily_loss_limit_eur": 3, "max_consecutive_stops": 2,
                     "max_orders_per_minute": 100}, tmp_path / "KILL")
    r.check(100)
    with pytest.raises(RiskHalt):
        r.check(150)
    r.on_close(-1, True); r.on_close(-1, True)
    with pytest.raises(RiskHalt):
        r.check(50)
    (tmp_path / "KILL").touch()
    r2 = RiskManager({"max_notional_eur": 100, "daily_loss_limit_eur": 3, "max_consecutive_stops": 9,
                      "max_orders_per_minute": 100}, tmp_path / "KILL")
    with pytest.raises(RiskHalt):
        r2.check(10)
