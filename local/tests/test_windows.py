"""Tests del actualizador seguro y del latido (R-11, R-12, R-13)."""
import importlib.util
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]


def _load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "local" / "windows" / f"{name}.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


upd = _load("update")
rep = _load("report_status")


def test_no_activa_sin_ci_verde():
    assert upd.blockers(False, [], False, [])


def test_cambios_protegidos_requieren_aprobacion_local():
    assert upd.blockers(True, ["local/config/agent.yaml:risk"], False, [])
    assert upd.blockers(True, ["local/config/agent.yaml:risk"], True, []) == []


def test_no_activa_con_posiciones_abiertas():
    assert "posiciones abiertas" in upd.blockers(True, [], False, ["BONKUSDT"])[0]


def test_activa_si_todo_en_orden():
    assert upd.blockers(True, [], False, []) == []


def test_posiciones_abiertas_desde_estado(tmp_path, monkeypatch):
    from nexus import paths
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path))
    paths.write_json_atomic(paths.state("paper_books.json"), {"A": {"state": "long"}, "B": {"state": "flat"}})
    assert upd.open_positions() == ["A"]


def test_rutas_protegidas_en_repo_temporal(tmp_path):
    g = ["git", "-C", str(tmp_path)]
    ident = ["-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run(g + ["init", "-q"], check=True)
    (tmp_path / "local" / "nexus" / "agent").mkdir(parents=True)
    (tmp_path / "local" / "nexus" / "agent" / "risk.py").write_text("x=1\n")
    (tmp_path / "README.md").write_text("a\n")
    subprocess.run(g + ["add", "-A"], check=True)
    subprocess.run(g + ident + ["commit", "-qm", "a"], check=True)
    (tmp_path / "README.md").write_text("b\n")
    subprocess.run(g + ident + ["commit", "-qam", "b"], check=True)
    (tmp_path / "local" / "nexus" / "agent" / "risk.py").write_text("x=2\n")
    subprocess.run(g + ident + ["commit", "-qam", "c"], check=True)
    old = upd.REPO
    upd.REPO = tmp_path
    try:
        assert upd.protected_changes("HEAD~2", "HEAD~1") == []
        assert upd.protected_changes("HEAD~1", "HEAD") == ["local/nexus/agent/risk.py"]
    finally:
        upd.REPO = old


def test_latido_oculta_cadenas_tipo_secreto(tmp_path, monkeypatch):
    from nexus import paths
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path))
    paths.logs("agent.log").write_text(
        "2026 INFO ok\n2026 WARNING clave mx0vglABCDEFGHIJKLMNOPQRSTUVWXYZ123456 rechazada\n")
    tail = rep.log_tail()
    assert len(tail) == 1 and "mx0vgl" not in tail[0] and "[oculto]" in tail[0]
    b = rep.build()
    assert set(b) >= {"ts", "status", "update", "log_tail", "kill_switch"}


def test_humo_agente_completo_sin_red(tmp_path, monkeypatch):
    """El agente arranca, opera en paper con datos simulados, guarda estado y sale con RESTART."""
    import itertools
    import nexus.agent.maker_agent as ma
    from nexus import paths
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path))
    monkeypatch.setenv("NEXUS_VERSION", "abc1234")
    monkeypatch.delenv("MEXC_API_KEY", raising=False)
    calls = itertools.count()

    class FakeClient:
        has_keys = False

        def book_ticker(self, s):
            n = next(calls)
            if n == 40:
                paths.state("RESTART").touch()
            return {"bidPrice": "10.0", "bidQty": "1", "askPrice": "10.05", "askQty": "1"}

        def trades(self, s):
            n = next(calls)
            return [{"time": n, "price": "10.0", "qty": "5", "isBuyerMaker": True},
                    {"time": n, "price": "10.05", "qty": "5", "isBuyerMaker": False}]

    monkeypatch.setattr(ma, "MexcReadOnly", FakeClient)
    monkeypatch.setattr(ma.time, "sleep", lambda s: None)
    ma.main()
    books = paths.read_json(paths.state("paper_books.json"), {})
    assert set(books) == {"BONKUSDT", "AIUSDT"} and sum(b["rt"] for b in books.values()) > 0
    risk = paths.read_json(paths.state("risk.json"), {})
    assert risk["pnl_total"] > 0 and not paths.state("RESTART").exists()
    assert paths.logs("agent.log").exists()


def test_vigilante_alertas():
    from nexus.monitor import alerts
    now = 1_800_000_000
    assert "nunca" in alerts(None, now)[0] or "todavía" in alerts(None, now)[0]
    ok = {"ts": now, "status": {"ts": now - 30, "risk": {}, "errors_last_hour": 0}, "update": {"result": "al día"}}
    assert alerts(ok, now) == []
    assert any("no reporta" in a for a in alerts({**ok, "ts": now - 3 * 3600}, now))
    st = {**ok["status"], "risk": {"sticky_halt": "drawdown"}}
    assert any("HALT" in a for a in alerts({**ok, "status": st}, now))
    up = {"result": "pospuesta", "candidate": "abc", "reasons": ["toca rutas protegidas y no fue aprobada"]}
    assert any("aprobación" in a for a in alerts({**ok, "update": up}, now))
    assert any("CI" in a for a in alerts(ok, now, ci_conclusion="failure"))
    assert any("emergencia" in a for a in alerts({**ok, "kill_switch": True}, now))


def test_informe_diario_contiene_lo_esencial():
    from nexus.monitor import digest
    pc = {"status": {"version": "abc", "mode": "paper", "fees": [0, 0.05], "errors_last_hour": 0,
                     "risk": {"pnl_day": 0.1}, "risk_block": None,
                     "books": [{"sym": "BONKUSDT", "state": "flat", "pnl_eur": 0.5, "realized_eur": 0.5,
                                "roundtrips": 3, "wins": 2, "stops": 1, "timeouts": 0}]}}
    t = digest(pc, "tabla", now=1_800_000_000)
    assert "BONKUSDT" in t and "paper" in t and "tabla" in t
    assert "sin datos" in digest(None)


def test_maker_descarta_libros_rotos():
    from nexus.discovery.maker import scan_maker
    assert scan_maker([("ALTHEA/EUR", 0.001, 1.5, 40000)], 0.25) == []


def test_check_keys_no_muestra_secretos_y_detecta_retiros(monkeypatch):
    from nexus import check_keys as ck
    monkeypatch.setenv("FAKE_K", "clave-super-secreta-123")
    monkeypatch.setenv("FAKE_S", "secreto-super-secreto-456")
    monkeypatch.delenv("NADA_K", raising=False)

    class Ok:
        pass

    def ok(c):
        return {"canTrade": True, "canWithdraw": False}

    def retiros(c):
        return {"canWithdraw": True}

    def falla(c):
        raise RuntimeError("401")

    lines = []
    assert ck.run([("A", "FAKE_K", "FAKE_S", Ok, ok)], lines.append, check_clock=False) == 0
    assert ck.run([("B", "FAKE_K", "FAKE_S", Ok, retiros)], lines.append, check_clock=False) == 2
    assert ck.run([("C", "FAKE_K", "FAKE_S", Ok, falla)], lines.append, check_clock=False) == 1
    assert ck.run([("D", "NADA_K", "NADA_S", Ok, ok)], lines.append, check_clock=False) == 0
    texto = "\n".join(lines)
    assert "super-secret" not in texto and "R-01" in texto and "sin clave" in texto



def test_describe_error_es_util_y_no_filtra_claves():
    import requests
    from nexus.check_keys import describe_error
    r = requests.models.Response()
    r.status_code = 400
    r._content = b'{"code":700003,"msg":"Timestamp for this request is outside of the recvWindow. key=mx0vglABCDEFGHIJKLMNOPQRSTUVWXYZ12"}'
    msg = describe_error(requests.HTTPError(response=r))
    assert "HTTP 400" in msg and "700003" in msg and "sincronizá" in msg and "mx0vgl" not in msg
    assert "Query Funds" in describe_error(RuntimeError("['EGeneral:Permission denied']"))



def test_check_keys_detecta_prefijo_key(monkeypatch):
    from nexus import check_keys as ck
    monkeypatch.setenv("PK", "key: mx0vglSECRETO")
    monkeypatch.setenv("PS", "secreto-valido-sin-nada-raro")
    lines = []

    def nunca(c):
        raise AssertionError("no debe consultar con formato inválido")

    assert ck.run([("MEXC", "PK", "PS", object, nunca)], lines.append, check_clock=False) == 1
    texto = "\n".join(lines)
    assert "FORMATO INCORRECTO en PK" in texto and "key:" in texto and "SECRETO" not in texto


def test_vaciado_para_actualizar(tmp_path, monkeypatch):
    """Si la actualización se pospuso SOLO por posiciones abiertas, no se abren nuevas."""
    import time as _t
    from nexus import paths
    from nexus.agent.maker_agent import Gate, draining
    from nexus.agent.risk import RiskManager
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path))
    g = Gate(RiskManager({"max_position_eur": 40, "max_total_exposure_eur": 80, "daily_loss_limit_eur": 2,
                          "weekly_loss_limit_eur": 4, "max_drawdown_eur": 8, "max_consecutive_stops": 3,
                          "stops_cooldown_min": 60, "max_orders_per_minute": 30, "losing_days_window": 7}))
    assert not draining() and g.allow_entry(40, 0)
    paths.write_json_atomic(paths.state("update.json"),
                            {"ts": _t.time(), "result": "pospuesta", "reasons": ["hay posiciones abiertas: AIUSDT"]})
    assert draining() and not g.allow_entry(40, 0)
    paths.write_json_atomic(paths.state("update.json"), {"ts": _t.time(), "result": "pospuesta",
                            "reasons": ["el CI de ese commit no está en verde", "hay posiciones abiertas: X"]})
    assert not draining()                    # si hay otra causa, no tiene sentido vaciar
    paths.write_json_atomic(paths.state("update.json"),
                            {"ts": _t.time() - 3600, "result": "pospuesta", "reasons": ["hay posiciones abiertas: X"]})
    assert not draining()                    # informe viejo: no bloquea para siempre


def test_segundo_arranque_con_estado_y_posicion_abierta(tmp_path, monkeypatch):
    """Reproduce el caso del PC: el agente sale por RESTART con una posición abierta y vuelve a arrancar."""
    import itertools
    import json
    import nexus.agent.maker_agent as ma
    from nexus import paths
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path))
    monkeypatch.delenv("MEXC_API_KEY", raising=False)
    monkeypatch.setattr(ma.time, "sleep", lambda s: None)
    for run_n, restart_at in ((1, 6), (2, 30)):
        calls = itertools.count()

        class FakeClient:
            has_keys = False

            def book_ticker(self, s):
                n = next(calls)
                if n == restart_at:
                    paths.state("RESTART").touch()
                # el precio cae después de comprar: la posición queda abierta (sin tocar el stop)
                bid = 10.0 if n < 4 else 9.97
                return {"bidPrice": str(bid), "bidQty": "1", "askPrice": str(bid + 0.01), "askQty": "1"}

            def trades(self, s):
                n = next(calls)
                return [{"time": n, "price": "10.0", "qty": "5", "isBuyerMaker": True}] if n < 4 else []

        monkeypatch.setattr(ma, "MexcReadOnly", FakeClient)
        ma.main()
        books = json.loads(paths.state("paper_books.json").read_text())
        if run_n == 1:
            assert any(b["state"] == "long" for b in books.values())
    assert json.loads(paths.state("status.json").read_text())["books"]
