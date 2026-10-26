"""Investigación de seguridad DeFi: catálogo, cambios, triaje, invariantes y orquestador (sin red)."""
import json
from pathlib import Path

from nexus.secresearch import catalog, changes, invariants, run, triage

PKG = Path(__file__).resolve().parents[1] / "nexus" / "secresearch"

PATCH_4626 = """@@ -120,7 +120,7 @@ contract Vault is ERC4626 {
     function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
-        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
+        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, Math.Rounding.Ceil);
     }
"""
PATCH_DOCS = """@@ -1,3 +1,3 @@
-// SPDX-License-Identifier: MIT
+// SPDX-License-Identifier: MIT OR Apache-2.0
 pragma solidity ^0.8.20;
"""


def test_catalogo_solo_habilita_lo_que_el_dueno_verifico(tmp_path):
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


def _fake_github(commits):
    """commits: {sha: [(archivo, parche)]}. Cuenta las llamadas."""
    calls = []

    def get(url, params=None):
        calls.append(url)
        if url.endswith("/commits"):
            return [{"sha": s, "html_url": f"https://github.com/o/r/commit/{s}",
                     "commit": {"message": f"cambio {s}\ncuerpo", "committer": {"date": "2026-10-20T00:00:00Z"}}}
                    for s in commits]
        sha = url.rsplit("/", 1)[1]
        return {"files": [{"filename": f, "patch": p, "status": "modified"} for f, p in commits[sha]]}
    return get, calls


def test_cambios_filtra_alcance_deduplica_y_respeta_el_tope(tmp_path):
    get, _ = _fake_github({"a1": [("src/Vault.sol", PATCH_4626), ("README.md", "+x")],
                           "b2": [("test/Vault.t.sol", PATCH_4626)],              # fuera de las rutas
                           "c3": [("src/Lib.vy", PATCH_DOCS)]})
    recs, why = changes.recent("o/r", ["src/"], changes.Budget(10), set(), 10, get)
    assert why is None and [r["sha"] for r in recs] == ["a1", "c3"]
    assert [f["filename"] for f in recs[0]["files"]] == ["src/Vault.sol"]               # solo contratos
    recs, _ = changes.recent("o/r", ["src/"], changes.Budget(10), {"a1"}, 10, get)
    assert [r["sha"] for r in recs] == ["c3"]                                           # ya visto: no se repite
    recs, why = changes.recent("o/r", ["src/"], changes.Budget(2), set(), 10, get)
    assert len(recs) == 1 and "tope" in why                                             # 1 lista + 1 detalle


def test_cambios_por_git_con_repo_local_y_sin_red(tmp_path):
    """Fuente por defecto: git real contra un repo local (file://), sin red. Clona, filtra el alcance,
    descarta el borde del clon superficial y en la segunda corrida solo trae lo nuevo."""
    import subprocess
    src = tmp_path / "upstream"
    src.mkdir()
    g = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
    subprocess.run(["git", "init", "-q", "-b", "main", str(src)], check=True)

    def commit(name, text, msg):
        (src / name).parent.mkdir(parents=True, exist_ok=True)
        (src / name).write_text(text)
        subprocess.run(g + ["-C", str(src), "add", "-A"], check=True)
        subprocess.run(g + ["-C", str(src), "commit", "-qm", msg], check=True)

    commit("src/Vault.sol", "contract V { function totalAssets() public {} }\n", "inicial")
    commit("README.md", "docs\n", "solo docs")
    commit("src/Vault.sol", "contract V { function totalAssets() public { return a.mulDiv(b, c, Math.Rounding.Ceil); } }\n",
           "redondeo")
    budget, work = changes.Budget(5), tmp_path / "work"
    recs, why = changes.recent_git("o/v", ["src/"], budget, set(), 10, work, url=f"file://{src}")
    assert why is None and [r["message"] for r in recs] == ["redondeo", "inicial"]
    assert recs[0]["files"][0]["filename"] == "src/Vault.sol" and "Rounding.Ceil" in recs[0]["files"][0]["patch"]
    assert triage.score(recs[0]["files"][0]["patch"])["tier"] in ("media", "alta")
    commit("src/Vault.sol", "contract V { function totalAssets() public { return 0; } }\n", "nuevo")
    again, _ = changes.recent_git("o/v", ["src/"], budget, {r["sha"] for r in recs}, 10, work, url=f"file://{src}")
    assert [r["message"] for r in again] == ["nuevo"] and budget.used == 2       # 1 clon + 1 fetch


def test_triaje_puntua_contabilidad_del_vault_y_no_comentarios():
    hi, lo = triage.score(PATCH_4626), triage.score(PATCH_DOCS)
    assert hi["tier"] == "alta" and {"dirección de redondeo", "totalAssets/totalSupply", "decimales / escala"} \
        <= set(hi["signals"])
    assert lo["score"] == 0 and lo["tier"] == "baja"                                    # solo cambió un comentario
    ctx_only = "@@ -1 +1 @@\n function totalAssets() public view returns (uint256) {\n+    // nada\n"
    assert triage.score(ctx_only)["score"] == 0                                         # el contexto no cuenta


def test_metodo_de_invariantes_atrapa_los_defectos_de_referencia():
    rows = run.selfcheck()
    assert all(r["ok"] for r in rows), rows
    a = invariants.check(lambda: invariants.Vault(deposit_up=True))["P1"]
    b = invariants.check(lambda: invariants.Vault(deposit_up=True))["P1"]
    assert a == b and a["redeemed"] > a["deposited"]                                    # reproducible
    p5 = invariants.check(lambda: invariants.Vault(virtual=False))["P5"]
    assert p5["attacker_got"] > p5["attacker_spent"]                                    # primer depositante


def test_orquestador_informa_y_se_reanuda_sin_repetir(tmp_path):
    get, _ = _fake_github({"a1": [("src/Vault.sol", PATCH_4626)], "c3": [("src/Lib.sol", PATCH_DOCS)]})
    s, ranked = run.scan([("Prog", "o/r", ["src/"])], tmp_path, get=get, source="api")
    assert s["new_commits"] == 2 and ranked[0]["sha"] == "a1" and ranked[0]["tier"] == "alta"
    md = (tmp_path / "secresearch.md").read_text()
    assert "NO es una vulnerabilidad" in md and "a1"[:7] in md
    assert json.loads((tmp_path / "secresearch.json").read_text())["summary"]["network_ops"] == 3
    s2, ranked2 = run.scan([("Prog", "o/r", ["src/"])], tmp_path, get=get, source="api")  # tras reiniciar
    assert s2["new_commits"] == 0 and ranked2 == [] and s2["network_ops"] == 1
    assert "a1" in (tmp_path / "secresearch.md").read_text() and s2["pending"] == 2     # lo pendiente no se pierde
    bad = run.scan([("Prog", "o/x", [])], tmp_path / "e", get=lambda u, p=None: 1 / 0, source="api")[0]
    assert bad["notes"] and "ZeroDivisionError" in bad["notes"][0]                      # un error no lo tumba
    demo = run.report(s, ranked, [("DEMO (no es objetivo)", "o/r", [])])
    assert "No es un objetivo ni un hallazgo" in demo


def test_limites_no_envia_nada_ni_toca_el_trading():
    src = "\n".join(p.read_text(encoding="utf-8") for p in PKG.glob("*.py"))
    for forbidden in ("requests.post", ".post(", "requests.put", "eth_sendRawTransaction", "sendTransaction",
                      "private_key", "mexc_trade", "binance_trade", "agent.live", "hedge_live"):
        assert forbidden not in src, forbidden
    trading = Path(__file__).resolve().parents[1] / "nexus" / "agent"
    assert not any("secresearch" in p.read_text(encoding="utf-8") for p in trading.glob("*.py"))


def test_circuito_local_reintenta_una_sola_vez_y_marca_intermitentes():
    from nexus import devcheck
    calls = []

    def fake(cmd, cwd=None):
        calls.append(cmd)
        if cmd[0] == "tests":
            return {"cmd": " ".join(cmd), "exit": 0 if "--lf" in cmd and flaky else 1, "seconds": 0.1, "tail": ["x"]}
        return {"cmd": " ".join(cmd), "exit": 0, "seconds": 0.1, "tail": []}
    plan = [("sintaxis", ["compile"], None), ("lint (código nuevo)", None, None), ("tests", ["tests"], None)]
    flaky = True
    rep = devcheck.check(fake, plan)
    assert rep["ok"] and rep["results"][2]["flaky"] and rep["results"][1]["exit"] is None
    flaky, calls[:] = False, []
    rep = devcheck.check(fake, plan)
    assert not rep["ok"] and sum(1 for c in calls if c[0] == "tests") == 2              # 1 + 1 reintento, nunca más
    md = devcheck.report(rep)
    assert "FALLÓ" in md and "omitido" in md and "final del log" in md
    plan = {name: (cmd, cwd) for name, cmd, cwd in devcheck.steps("py")}
    assert plan["control de límites"][1] == devcheck.REPO                              # rutas relativas a la raíz
    assert "-p" not in plan["tests"][0]                                                # --lf necesita el caché


def test_resultados_nunca_dentro_del_repo_publico(tmp_path, monkeypatch):
    import pytest
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path / "home"))
    assert run.out_dir() == tmp_path / "home" / "secresearch"                           # privado, en la PC
    assert run.out_dir(str(tmp_path / "x")) == tmp_path / "x"
    with pytest.raises(SystemExit, match="repo público"):
        run.out_dir(str(run.REPO / "data"))
    ejemplo = catalog.load(PKG / "catalogo.ejemplo.yaml")
    assert ejemplo and catalog.actionable(ejemplo) == []                                 # el ejemplo nunca se analiza
    assert run.main([str(PKG / "catalogo.ejemplo.yaml"), str(tmp_path / "o")]) == 0
    assert not (tmp_path / "o").exists()                                                 # sin habilitados: no hace nada
