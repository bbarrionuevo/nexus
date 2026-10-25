"""Asignador de pares: puntaje con cota inferior, promociones y prueba fuera de muestra."""
import json

NOW = 1_800_000_000


def _t(sym, pnl, i=0, lab=True, strategy="v3", age_days=0.0):
    return {"ts": NOW - age_days * 86400 - 1000 + i, "sym": sym, "pnl": pnl, "lab": lab, "strategy": strategy}


def test_puntaje_castiga_pocas_vueltas_y_stops():
    from nexus.allocator import score
    assert score([0.05] * 10, min_n=20) is None                       # pocas vueltas: sin opinión
    assert score([0.05, 0.04] * 15, min_n=20) > 0                     # gana parejo
    assert score([0.05] * 25 + [-0.9] * 2, min_n=20) < 0              # 2 stops se comen 25 ganancias


def test_puntajes_solo_con_laboratorio_de_la_version_vigente_y_recientes():
    from nexus.allocator import scores
    tr = ([_t("A", 0.05 + (i % 3) * 0.01, i) for i in range(80)]
          + [_t("A", -5.0, i, age_days=8) for i in range(30)]         # viejo: fuera de la ventana de días
          + [_t("B", 0.05, i, strategy="control") for i in range(30)]  # control: otra estrategia
          + [_t("C", 0.05, i, lab=False) for i in range(30)])          # libro operado: no es laboratorio
    sc = scores(tr, "v3", NOW, window=60, min_n=20, days=7)
    assert set(sc) == {"A"} and sc["A"]["n"] == 60 and sc["A"]["score"] > 0


def test_promueve_descarta_y_conserva_los_mejores():
    from nexus.allocator import decide, status
    sc = {"A": {"score": 0.02, "n": 40}, "B": {"score": 0.05, "n": 40}, "C": {"score": -0.01, "n": 40},
          "D": {"score": None, "n": 5}, "E": {"score": 0.03, "n": 40}}
    st, keep = decide({}, sc, NOW, keep_max=2, exclude={"E"})
    assert keep == ["B", "A"]                                         # mejor puntaje primero; E pausado
    assert set(st["promoted"]) == {"A", "B", "E"} and status(st, "B") == "promovido" and status(st, "C") == "explorando"
    st2, keep2 = decide(st, {"A": {"score": -0.001, "n": 60}, "B": {"score": 0.04, "n": 60}}, NOW + 6 * 3600)
    assert keep2 == ["B"] and set(st2["promoted"]) == {"B"}           # A dejó de ganar; E sin vueltas recientes
    assert st2["promoted"]["B"] == NOW                                # conserva la fecha de promoción
    assert [h["event"] for h in st2["history"] if h["sym"] == "A"] == ["promovido", "descartado"]


def test_laboratorio_conserva_promovidos_y_marca_cada_vuelta(tmp_path, monkeypatch):
    from nexus import evidence, paths
    from nexus.agent.maker_agent import Lab
    from tests.test_windows import LAB, FakeMexc
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path))
    hist = [dict(_t("ZZZUSDT", 0.05 + (i % 2) * 0.01, i, strategy=None), ts=1e9 + i, model=evidence.FILL_MODEL)
            for i in range(30)]
    paths.state("trades.jsonl").write_text("\n".join(json.dumps(t) for t in hist) + "\n")
    cfg = {"symbols": ["BONKUSDT"], "lab": LAB | {"max_symbols": 2, "score_days": 1e6},
           "stop_pct": 1.0, "min_edge_pct": 0.0, "max_hold_min": 30, "risk": {"max_position_eur": 40}}
    lab = Lab(FakeMexc(), cfg, 0.0, 0.08)
    for _ in range(8):
        lab.step()
    assert list(lab.books) == ["ZZZUSDT", "AAAUSDT"]                  # 1 promovido + 1 explorando
    st = {b["sym"]: b for b in lab.status()}
    assert st["ZZZUSDT"]["sel"] == "promovido" and st["ZZZUSDT"]["score"] > 0 and st["AAAUSDT"]["sel"] == "explorando"
    new = [json.loads(x) for x in paths.state("trades.jsonl").read_text().splitlines()][30:]
    sels = {(t["sym"], t["sel"]) for t in new if t.get("strategy") is None}
    assert ("ZZZUSDT", "promovido") in sels and ("AAAUSDT", "explorando") in sels
    ev = evidence.evaluate(paths.state("trades.jsonl"))
    assert set(ev["selection"]) >= {"promovido", "explorando", "sin dato"}
    assert json.loads(paths.state("allocator.json").read_text())["promoted"] == {"ZZZUSDT": lab.alloc["ts"]}


def test_informe_muestra_la_seleccion_fuera_de_muestra():
    from nexus.monitor import digest
    ev = {"selection": {"explorando": {"n": 40, "total": -1.2, "mean": -0.03, "ci95_low": -0.06},
                        "promovido": {"n": 30, "total": 0.9, "mean": 0.03, "ci95_low": 0.01}}}
    md = digest({"status": {"evidence": ev, "books": []}}, None, now=NOW)
    assert "fuera de muestra" in md and "| promovido | 30 | +0.90 |" in md
