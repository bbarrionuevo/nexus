"""Dashboard local y expedientes: se generan desde NEXUS_HOME, escapan todo y nunca escriben dentro del repo."""
import json
from pathlib import Path

import pytest

from nexus.secresearch import cycle, dashboard, expediente

REPO = Path(__file__).resolve().parents[2]
SUITE = "test/nexus/NexusMetaMorphoHunter.t.sol:NexusMetaMorphoHunterTest"
CATALOG = """programs:
  - name: Morpho
    platform: Cantina
    rules_url: https://example.org/morpho
    in_scope: true
    verified_by_owner: true
    rewards_note: "crítico hasta X (leído el 26-oct)"
    poc_required: "test reproducible en local"
    exclusions: "problemas conocidos y auditorías previas"
    repos:
      - repo: morpho-org/metamorpho
        paths: ["src/"]
  - name: Pendiente
    rules_url: https://example.org/otro
    repos:
      - repo: o/r
"""


def _home(tmp_path):
    sec = tmp_path / "secresearch"
    (sec / "validate").mkdir(parents=True)
    (tmp_path / "secresearch.yaml").write_text(CATALOG, encoding="utf-8")
    base = {"repo": "morpho-org/metamorpho", "sha": "ded84e59668155b34d3c", "harness": "morpho-org__metamorpho",
            "build_s": 410.1, "test_s": 1070.8}
    activity = [{"suite": SUITE, "test": "invariant_hunter()", "type": "Invariant", "runs": 256, "calls": 128000,
                 "reverts": 1035,
                 "metrics": {"NexusMetaMorphoHunterHandler.reallocate": {"calls": 3744, "reverts": 2899},
                             "NexusMetaMorphoHunterHandler.deposit": {"calls": 3564, "reverts": 31}},
                 "logs": ["verificaciones: 149", "cazador: leyes evaluadas: 9638",
                          "cazador: comision devengada: 28525965442873341979263062291",
                          "cazador: gobierno con efecto: submitCap 28, acceptCap 16"]}]
    hist = [{**base, "ts": 1000, "ok": True, "report": "r1", "seed": "0x1",
             "counts": {"Success": 84, "Failure": 0, "Skipped": 0}},
            {**base, "ts": 2000, "ok": False, "report": "r2", "seed": "0x2",
             "counts": {"Success": 83, "Failure": 1, "Skipped": 0}}]
    (sec / "validate" / "history.jsonl").write_text("".join(json.dumps(h) + "\n" for h in hist), encoding="utf-8")
    for h, failures in ((hist[0], []), (hist[1], [{"suite": SUITE, "test": "invariant_hunter()",
                                                    "reason": "H-FEE-5: <script>alert(1)</script> revirtio",
                                                    "counterexample": {"sequence": [{"signature": "deposit"}]},
                                                    "logs": ["paso 1"]}])):
        rec = {**base, "when": "2026-10-27 02:28", "fuzz": {"FOUNDRY_FUZZ_SEED": h["seed"]},
               "test": {"counts": h["counts"], "failures": failures, "activity": activity}}
        (sec / "validate" / f"{h['report']}.json").write_text(json.dumps(rec), encoding="utf-8")
    (sec / "ciclo.jsonl").write_text(json.dumps({"ts": 3000, "minutes": 26.5, "ok": True, "steps": [
        {"step": "harness morpho-org__metamorpho", "ok": True, "detail": "84 pasan"}]}) + "\n", encoding="utf-8")
    (sec / "secresearch.json").write_text(json.dumps({"pending": [
        {"tier": "alta", "score": 9, "repo": "morpho-org/metamorpho", "sha": "abcdef123", "file": "src/MetaMorpho.sol",
         "url": "https://github.com/morpho-org/metamorpho/commit/abcdef123", "signals": {"redondeo": {"lines": 2}}}]}),
        encoding="utf-8")
    return sec


def test_dashboard_desde_nexus_home_escapa_y_no_carga_nada_de_afuera(tmp_path):
    sec = _home(tmp_path)
    path = dashboard.write(home=tmp_path)
    assert path == sec / "dashboard.html"
    page = path.read_text(encoding="utf-8")
    assert "Nexus · investigación de seguridad" in page and "Morpho" in page and "Cantina" in page
    assert "reallocate" in page and "77,4 %" in page                         # 2899 / 3744: marcada sobre el umbral
    assert "verificaciones" in page and "2,85e28" in page                    # métricas del cazador, compactas
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in page and "<script>alert" not in page
    assert "src=" not in page and "http://" not in page                     # nada externo: ni scripts ni imágenes
    assert "--seed 0x2" in page and "validate/r2.md" in page                 # cómo reproducir y el informe
    assert "inactivo" in page and "in_scope" in page                         # el programa sin las marcas del dueño
    d = dashboard.collect(tmp_path)
    assert len(d["failures"]) == 1 and not d["failures"][0]["expediente"]


def test_expediente_completo_y_el_dashboard_lo_reconoce(tmp_path):
    _home(tmp_path)
    dest = expediente.create("r2", home=tmp_path, today="2026-10-27")
    assert dest.name == "20261027-morpho-org__metamorpho-H-FEE-5.md"
    text = dest.read_text(encoding="utf-8")
    meta = dashboard.front_matter(text)
    assert meta["estado"] == "borrador" and meta["programa"] == "Morpho (Cantina)" and meta["severidad"]
    for must in ("--ref ded84e59668155b34d3c --harness morpho-org__metamorpho --seed 0x2", "H-FEE-5",
                 "https://example.org/morpho", "test reproducible en local", "Causa raíz", "Precondiciones",
                 "Prueba de concepto", "Esperado", "Impacto", "Severidad", "Auditorías previas", "Corrección",
                 "Antes de enviar", "R-3", "\"signature\": \"deposit\""):
        assert must in text, must
    assert expediente.create("r2", home=tmp_path, today="2026-10-27").name.endswith("-H-FEE-5-2.md")  # no pisa
    d = dashboard.collect(tmp_path)
    assert d["failures"][0]["expediente"] and len(d["expedientes"]) == 2
    with pytest.raises(SystemExit, match="no tiene fallas"):
        expediente.create("r1", home=tmp_path)


def test_el_expediente_reconoce_las_leyes_de_metamorpho_y_de_vault_v2():
    for reason, law in (("H-FEE-5: revirtio", "H-FEE-5"),
                        ("V-LOSS-1: la perdida no se realizo entera [leyes: V-TA-1 V-LOSS-1]: 1 != 0", "V-LOSS-1"),
                        ("V-LEDGER: la suma de los saldos no es totalSupply: 3, 4", "V-LEDGER")):   # sin número
        assert expediente.LAW.search(reason).group(0) == law


def test_ni_el_dashboard_ni_los_expedientes_escriben_en_el_repo():
    with pytest.raises(SystemExit, match="repo público"):
        dashboard.write(home=REPO)
    with pytest.raises(SystemExit, match="repo público"):
        expediente.create("r2", home=REPO)


def test_el_ciclo_regenera_el_dashboard(tmp_path):
    rep = cycle.cycle(max_minutes=1, baselines=0, programs=[], home=tmp_path)
    assert not rep.get("skipped") and (tmp_path / "secresearch" / "dashboard.html").exists()
