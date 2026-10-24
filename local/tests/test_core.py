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


def test_ars_scanner_finds_and_rejects():
    from nexus.core.ars_scanner import scan
    q = {"A": {"totalAsk": 1600, "totalBid": 1590}, "B": {"totalAsk": 1650, "totalBid": 1640}}
    ops = scan(q, 160000, 1.0, 0.3)
    assert ops[0].buy_at == "A" and ops[0].sell_at == "B" and ops[0].executable
    assert not scan(q, 160000, 5.0, 0.3)[0].executable   # fee fijo alto la anula


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


# ---------------------------------------------------------------- riesgo (R-03, R-08, R-09, R-14, R-16)
RISK = {"max_position_eur": 40, "max_total_exposure_eur": 80, "daily_loss_limit_eur": 2,
        "weekly_loss_limit_eur": 4, "max_drawdown_eur": 8, "max_consecutive_stops": 3,
        "stops_cooldown_min": 60, "max_orders_per_minute": 30, "losing_days_window": 7}


class Clock:
    def __init__(self, t=1_800_000_000.0):
        self.t = t

    def __call__(self):
        return self.t


def _risk(tmp_path, clock=None):
    from nexus.agent.risk import RiskManager
    return RiskManager(RISK, tmp_path / "risk.json", tmp_path / "KILL", now=clock or Clock())


def test_regresion_defecto1_consultar_no_cuenta_como_orden(tmp_path):
    r = _risk(tmp_path)
    assert all(r.allow_entry(40) for _ in range(1000))


def test_limite_de_ordenes_por_minuto(tmp_path):
    r = _risk(tmp_path)
    for _ in range(30):
        r.record_order()
    assert not r.allow_entry(40) and "órdenes por minuto" in r.last_reason


def test_limites_de_posicion_y_exposicion(tmp_path):
    r = _risk(tmp_path)
    assert not r.allow_entry(41)
    assert not r.allow_entry(40, exposure_now=50)
    assert r.allow_entry(40, exposure_now=40)


def test_perdida_diaria_sobrevive_reinicio(tmp_path):
    clock = Clock()
    r = _risk(tmp_path, clock)
    r.on_close(-1.2, True)
    r.on_close(-0.9, True)
    r2 = _risk(tmp_path, clock)              # "reinicio": nuevo objeto, mismo archivo
    assert not r2.allow_entry(40) and "pérdida del día" in r2.last_reason
    clock.t += 86400                         # día siguiente: se puede volver a operar
    assert r2.allow_entry(40)


def test_stops_seguidos_y_enfriamiento(tmp_path):
    clock = Clock()
    r = _risk(tmp_path, clock)
    for _ in range(3):
        r.on_close(-0.1, True)
    assert not r.allow_entry(40)
    clock.t += 3601
    assert r.allow_entry(40)


def test_drawdown_total_es_permanente(tmp_path):
    clock = Clock()
    r = _risk(tmp_path, clock)
    for i in range(5):
        clock.t += 86400 * 2                 # repartido en días/semanas para no tocar otros límites
        r.on_close(-1.7, False)
    assert r.s["sticky_halt"] and not r.allow_entry(40)
    clock.t += 86400 * 30
    assert not _risk(tmp_path, clock).allow_entry(40)


def test_estrategia_perdedora_7_dias_se_apaga(tmp_path):
    clock = Clock()
    r = _risk(tmp_path, clock)
    for _ in range(8):
        r.on_close(-0.05, False)
        clock.t += 86400
    r.on_close(0.0, False)
    assert r.s["sticky_halt"] and "7 días" in r.s["sticky_halt"]


def test_interruptor_de_emergencia(tmp_path):
    r = _risk(tmp_path)
    (tmp_path / "KILL").touch()
    assert not r.allow_entry(40) and "emergencia" in r.last_reason


# ---------------------------------------------------------------- modelo de cola / estrategia
def test_cola_y_ganancia_real():
    from nexus.live_paper_maker import Book
    b = Book("X", notional=100, maker=0.0)
    b.on_book(10.0, 50, 10.1, 50)
    b.on_trade(10.0, 30, True)
    assert b.state == "flat"
    b.on_trade(10.0, 25, True)
    assert b.state == "long" and b.entry == 10.0
    b.on_trade(10.1, 60, False)
    assert b.state == "flat" and b.wins == 1 and b.mark()["pnl_eur"] > 0


def test_regresion_defecto2_no_vende_bajo_entrada_como_maker():
    from nexus.live_paper_maker import Book
    b = Book("X", notional=100, maker=0.0, stop_pct=1.0)
    b.on_book(10.00, 1, 10.01, 1)
    b.on_trade(10.00, 2, True)
    b.on_book(9.95, 1, 9.96, 1)              # cae 0.5%: el ask queda bajo la entrada
    assert b.px == 10.00                     # la venta se mantiene en el piso, no persigue
    b.on_trade(9.96, 5, False)
    assert b.state == "long" and b.rt == 0


def test_piso_incluye_comisiones():
    from nexus.live_paper_maker import Book
    b = Book("X", notional=100, maker=0.1)
    b.on_book(10.0, 1, 10.01, 1)
    b.on_trade(10.0, 2, True)
    assert abs(b.px - 10.02) < 1e-9          # 10 * (1 + 0.2%) > ask 10.01


def test_stop_y_timeout_cuentan_como_perdida():
    from nexus.live_paper_maker import Book
    clock = Clock()
    b = Book("X", notional=100, maker=0.0, taker=0.1, stop_pct=1.0, max_hold_s=60, now=clock)
    b.on_book(10.0, 1, 10.01, 1); b.on_trade(10.0, 2, True)
    b.on_book(9.89, 1, 9.9, 1)
    assert b.stops == 1 and b.wins == 0 and b.mark()["pnl_eur"] < 0
    b.on_book(10.0, 1, 10.01, 1); b.on_trade(10.0, 2, True)
    clock.t += 61
    b.on_book(9.99, 1, 10.0, 1)
    assert b.timeouts == 1 and b.state == "flat"


def test_veto_de_riesgo_cancela_compra(tmp_path):
    from nexus.agent.maker_agent import Gate
    from nexus.live_paper_maker import Book
    r = _risk(tmp_path)
    g = Gate(r)
    b = Book("X", notional=40, gate=g)
    g.books["X"] = b
    b.on_book(10.0, 1, 10.01, 1)
    assert b.px == 10.0
    (tmp_path / "KILL").touch()
    b.on_book(10.0, 1, 10.01, 1)
    assert b.px is None


def test_estado_del_libro_persiste():
    from nexus.live_paper_maker import Book
    b = Book("X", notional=100)
    b.on_book(10.0, 1, 10.01, 1); b.on_trade(10.0, 2, True)
    b2 = Book("X", notional=100)
    b2.load(b.to_dict())
    assert b2.state == "long" and b2.entry == 10.0 and b2.px is None


# ---------------------------------------------------------------- configuración, rutas, credenciales
def test_agente_rechaza_live(tmp_path, monkeypatch):
    import nexus.agent.maker_agent as ma
    p = tmp_path / "agent.yaml"
    p.write_text("live: true\n")
    monkeypatch.setattr(ma, "CFG", p)
    with pytest.raises(SystemExit):
        ma.load_config()


def test_rutas_fuera_del_repo_y_escritura_atomica(tmp_path, monkeypatch):
    from nexus import paths
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path / "home"))
    assert paths.kill_file() == tmp_path / "home" / "KILL"
    paths.write_json_atomic(paths.state("x.json"), {"a": 1})
    assert paths.read_json(paths.state("x.json"), None) == {"a": 1}


def test_env_no_pisa_variables(tmp_path, monkeypatch):
    from nexus import paths
    (tmp_path / ".env").write_text("NEXUS_T1=archivo\nNEXUS_T2='dos'\n")
    monkeypatch.setenv("NEXUS_T1", "ya")
    monkeypatch.delenv("NEXUS_T2", raising=False)
    paths.load_env(tmp_path / ".env")
    import os
    assert os.environ["NEXUS_T1"] == "ya" and os.environ["NEXUS_T2"] == "dos"


def test_mexc_solo_lectura_y_comisiones():
    from nexus.exchanges.mexc import MexcReadOnly, parse_fee
    c = MexcReadOnly("k", "s")
    for path in ("/api/v3/order", "/api/v3/capital/withdraw", "/api/v3/order/test"):
        with pytest.raises(ReadOnlyViolation):
            c._get(path)
    assert parse_fee({"data": {"makerCommission": 0, "takerCommission": 0.0005}}) == (0.0, 0.05)
    assert parse_fee({"x": 1}) is None


def test_no_existe_codigo_de_ordenes_reales():
    """Hasta la Fase 6 autorizada, ningún módulo puede contener endpoints de órdenes o retiros."""
    import pathlib
    root = pathlib.Path(__file__).resolve().parents[1] / "nexus"
    banned = ("/api/v3/order\"", "/order'", "AddOrder", "capital/withdraw", "newOrder", "/0/private/Withdraw")
    hits = [f"{p.name}:{b}" for p in root.rglob("*.py") for b in banned if b in p.read_text(encoding="utf-8")]
    assert hits == []


def test_estrategias_no_importan_clientes_de_exchange():
    """R-03: la lógica de estrategia no puede tocar clientes autenticados."""
    import pathlib
    root = pathlib.Path(__file__).resolve().parents[1] / "nexus"
    for name in ("live_paper_maker.py", "research_maker.py", "backtest_trading.py"):
        assert "exchanges" not in (root / name).read_text(encoding="utf-8")
