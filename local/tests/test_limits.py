"""Límites de seguridad del motor (ARCHIVO PROTEGIDO). Si un cambio rompe uno de estos tests, el cambio está mal."""
from pathlib import Path

import pytest

from nexus.secresearch import catalog, changes, limits, run

PKG = Path(__file__).resolve().parents[1] / "nexus"


def test_solo_se_analiza_lo_que_el_dueno_verifico(tmp_path):
    y = tmp_path / "c.yaml"
    y.write_text("""programs:
  - {name: Sin verificar, rules_url: "https://example.org/a", in_scope: true, repos: [{repo: o/a}]}
  - {name: Fuera de alcance, rules_url: "https://example.org/b", in_scope: false, verified_by_owner: true,
     repos: [{repo: o/b}]}
  - {name: Mal URL, rules_url: "http://x", in_scope: true, verified_by_owner: true, repos: [{repo: o/c}]}
  - {name: Listo, rules_url: "https://example.org/d", in_scope: true, verified_by_owner: true,
     repos: [{repo: o/d, paths: [src/]}]}
""")
    progs = catalog.load(y)
    assert [p["name"] for p in catalog.actionable(progs)] == ["Listo"]
    assert any("verified_by_owner" in x for x in catalog.problems(progs[0]))
    assert any("in_scope" in x for x in catalog.problems(progs[1]))
    assert any("https" in x for x in catalog.problems(progs[2]))
    assert catalog.load(tmp_path / "no-existe.yaml") == []
    ejemplo = catalog.load(PKG / "secresearch" / "catalogo.ejemplo.yaml")
    assert ejemplo and catalog.actionable(ejemplo) == []                        # el ejemplo nunca se analiza


def test_resultados_nunca_dentro_del_repo_publico(tmp_path, monkeypatch):
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path / "home"))
    assert run.out_dir() == tmp_path / "home" / "secresearch"                  # privado, en la PC
    assert run.out_dir(str(tmp_path / "x")) == tmp_path / "x"
    for inside in (limits.REPO / "data", limits.REPO / "local" / "out", limits.REPO):
        with pytest.raises(SystemExit, match="repo público"):
            run.out_dir(str(inside))
    assert run.main([str(PKG / "secresearch" / "catalogo.ejemplo.yaml"), str(tmp_path / "o")]) == 0
    assert not (tmp_path / "o").exists()                                        # sin habilitados: no hace nada


def test_el_codigo_no_envia_informes_ni_transacciona():
    for p in PKG.rglob("*.py"):
        if p.name == "limits.py":
            continue
        src = p.read_text(encoding="utf-8")
        for forbidden in limits.FORBIDDEN:
            assert forbidden not in src, f"{p.relative_to(PKG)} contiene {forbidden!r}"


def test_cada_corrida_respeta_el_tope_de_red(tmp_path):
    def get(url, params=None):
        if url.endswith("/commits"):
            return [{"sha": f"s{i}", "commit": {"committer": {"date": "2026-10-20T00:00:00Z"}}} for i in range(5)]
        return {"files": [{"filename": "src/V.sol", "patch": "+x"}]}
    targets = [("P", f"o/r{i}", ["src/"]) for i in range(30)]                  # pediría 30 × 6 = 180
    s, _ = run.scan(targets, tmp_path, get=get, source="api")
    assert s["network_ops"] == limits.MAX_NETWORK_OPS and any("tope" in n for n in s["notes"])
    assert 0 < limits.MAX_NETWORK_OPS <= 100 and 0 < limits.MAX_COMMITS <= 50 and 0 < limits.MAX_SECONDS <= 1800
    assert isinstance(changes.Budget(limits.MAX_NETWORK_OPS), changes.Budget)


def test_validacion_solo_sobre_repos_de_programas_verificados_y_sin_ffi(tmp_path):
    from nexus.secresearch import validate
    ok = {"name": "P", "rules_url": "https://example.org", "in_scope": True, "verified_by_owner": True,
          "repos": [{"repo": "o/v"}]}
    sin_verificar = dict(ok, verified_by_owner=False, repos=[{"repo": "o/w"}])
    assert limits.repo_in_scope("o/v", [ok]) is ok
    assert limits.repo_in_scope("o/w", [ok, sin_verificar]) is None                 # programa sin verificar
    assert limits.repo_in_scope("x/y", [ok]) is None                                # fuera del catálogo
    nunca = ["/bin/false-forge-no-debe-correr"]
    for repo in ("o/w", "x/y"):
        rec = validate.validate(repo, out=tmp_path / "o", programs=[ok, sin_verificar], forge=nunca,
                                work=tmp_path / "w")
        assert not rec["ok"] and "no pertenece" in rec["error"] and not (tmp_path / "w").exists()
    assert limits.FOUNDRY_ENV == {"FOUNDRY_FFI": "false"}
    assert 0 < limits.MAX_BUILD_SECONDS <= 7200 and 0 < limits.MAX_TEST_SECONDS <= 7200
