"""Motor de investigación: cambios, triaje, invariantes, orquestador y circuito local (sin red)."""
import json
import os
from pathlib import Path

from nexus.secresearch import changes, invariants, run, triage

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


def test_salida_de_git_con_bytes_indecodificables_no_rompe(tmp_path):
    """26-oct, PC con Windows: la salida de un subproceso con el byte 0x81 (cp1252 no lo decodifica) mataba
    el hilo lector. Un git simulado que escribe bytes inválidos reproduce esa clase de falla en cualquier SO."""
    import sys
    fake = tmp_path / "git.py"
    fake.write_text("import sys\nsys.stdout.buffer.write(b'progreso \\x81\\xff listo')\n")
    out = changes._git(["log"], exe=(sys.executable, str(fake)))
    assert out.startswith("progreso") and out.endswith("listo")


def test_tests_mocks_y_scripts_no_estan_en_alcance():
    ok = ["src/TokenizedStrategy.sol", "contracts/VaultV3.vy", "src/EVault/modules/Vault.sol",
          "src/libraries/TokenizedStrategyLib.sol"]
    ruido = ["src/test/Accounting.t.sol", "src/test/handlers/ConstantAccrualHandler.sol", "src/test/mocks/MockStrategy.sol",
             "src/mocks/ERC20Mock.sol", "script/Deploy.s.sol", "certora/specs/Vault.sol", "foundry_tests/tests/A.sol",
             "src/MockOracle.sol", "test/Vault.sol"]
    assert all(changes._in_scope(f, ["src/", "contracts/"]) for f in ok)
    assert not any(changes._in_scope(f, []) for f in ruido)


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
    assert plan["rutas protegidas"][1] == devcheck.REPO                                # rutas relativas a la raíz
    assert "-p" not in plan["tests"][0]                                                # --lf necesita el caché


def test_circuito_local_usa_el_ruff_del_venv_sin_activarlo(tmp_path, monkeypatch):
    from nexus import devcheck
    exe = tmp_path / ("ruff.exe" if os.name == "nt" else "ruff")                      # junto al python del venv
    exe.write_text("")
    exe.chmod(0o755)
    monkeypatch.setenv("PATH", "")
    lint = {name: cmd for name, cmd, _ in devcheck.steps(str(tmp_path / "python"))}["lint"]
    assert lint and Path(lint[0]).parent == tmp_path and lint[1:] == ["check", "--line-length", "120", "nexus", "tests"]


FAKE_FORGE = r'''
import json, os, sys
log = os.environ["FAKE_LOG"]
nexus = os.path.join(os.getcwd(), "test", "nexus")
with open(log, "a") as f:
    f.write(json.dumps({"argv": sys.argv[1:], "ffi": os.environ.get("FOUNDRY_FFI"), "cwd": os.getcwd(),
                        "fuzz": {k: v for k, v in os.environ.items() if k.startswith(("FOUNDRY_FUZZ", "FOUNDRY_INV"))},
                        "harness": sorted(os.listdir(nexus)) if os.path.isdir(nexus) else None}) + "\n")
if sys.argv[1] == "build":
    print("Compiling 42 files")
    sys.exit(int(os.environ.get("FAKE_BUILD_EXIT", "0")))
# Indicador de progreso como el de forge en Windows (26-oct): bytes que cp1252 no decodifica (0x81) y que
# tampoco son UTF-8 válido. Antes mataban el hilo lector de subprocess y forge quedaba trabado.
sys.stderr.buffer.write(b"\xe2\xa0\x81 compilando \x81\xff\n" * 2000)
sys.stderr.flush()
print("Compiling... (ruido antes del JSON)")
print(json.dumps({"test/V.t.sol:VaultTest": {"test_results": {
    "testDepositRedeem(uint256)": {"status": "Success", "reason": None, "counterexample": None},
    "testNoDilution(uint256)": {"status": "Failure", "reason": "assertion failed: 7 < 8",
                                "counterexample": {"calldata": "0xabc", "args": "2"}},
    "testSkip()": {"status": "Skipped", "reason": None, "counterexample": None},
    "invariant_x()": {"status": "Success", "kind": {"Invariant": {"runs": 4, "calls": 40, "reverts": 30, "metrics": {
                          "H.deposit": {"calls": 25, "reverts": 1, "discards": 0},
                          "H.huntInflation": {"calls": 15, "reverts": 29, "discards": 0}}}},
                      "decoded_logs": ["cazador: leyes evaluadas: 99", "cazador: depositos con 0 acciones: 3"]}}}}))
sys.exit(1)
'''


def _foundry_repo(tmp_path):
    import subprocess
    src = tmp_path / "upstream"
    src.mkdir()
    g = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
    subprocess.run(["git", "init", "-q", "-b", "main", str(src)], check=True)
    (src / "foundry.toml").write_text("[profile.default]\nffi = true\n")
    (src / "src").mkdir()
    (src / "src" / "V.sol").write_text("contract V {}\n")
    subprocess.run(g + ["-C", str(src), "add", "-A"], check=True)
    subprocess.run(g + ["-C", str(src), "commit", "-qm", "v1"], check=True)
    return src


def test_validador_compila_testea_e_informa(tmp_path, monkeypatch):
    import sys

    from nexus.secresearch import validate
    src = _foundry_repo(tmp_path)
    fake = tmp_path / "forge.py"
    fake.write_text(FAKE_FORGE)
    log = tmp_path / "forge.log"
    monkeypatch.setenv("FAKE_LOG", str(log))
    monkeypatch.setenv("FOUNDRY_FFI", "true")                                         # aunque el entorno diga true
    progs = [{"name": "Prog", "rules_url": "https://example.org", "in_scope": True, "verified_by_owner": True,
              "repos": [{"repo": "o/v"}]}]
    rec = validate.validate("o/v", match="test/V.t.sol", out=tmp_path / "out", programs=progs,
                            forge=[sys.executable, str(fake)], url=f"file://{src}", work=tmp_path / "work")
    calls = [json.loads(x) for x in log.read_text().splitlines()]
    assert [c["argv"][0] for c in calls] == ["build", "test"] and all(c["ffi"] == "false" for c in calls)
    assert calls[1]["argv"] == ["test", "--json", "-vv", "--match-path", "test/V.t.sol"]
    assert not rec["ok"] and rec["test"]["counts"] == {"Success": 2, "Failure": 1, "Skipped": 1}
    assert rec["test"]["failures"][0]["counterexample"]["args"] == "2" and len(rec["sha"]) == 40
    md = (tmp_path / "out" / f"o__v@{rec['sha'][:10]}.md").read_text()
    assert "2 pasan · 1 fallan" in md and "testNoDilution" in md and "NO es una vulnerabilidad" in md
    hist = [json.loads(x) for x in (tmp_path / "out" / "history.jsonl").read_text().splitlines()]
    assert hist[-1]["counts"]["Failure"] == 1 and hist[-1]["sha"] == rec["sha"]
    monkeypatch.setenv("FAKE_BUILD_EXIT", "1")                                         # no compila: no testea
    log.write_text("")
    rec = validate.validate("o/v", out=tmp_path / "out", programs=progs, forge=[sys.executable, str(fake)],
                            url=f"file://{src}", work=tmp_path / "work")
    assert not rec["ok"] and rec["build"]["exit"] == 1 and "test" not in rec
    assert [json.loads(x)["argv"][0] for x in log.read_text().splitlines()] == ["build"]
    assert "Compilación: FALLÓ" in validate.report(rec)


def test_validador_con_harness_copia_antes_de_compilar_y_fija_la_semilla(tmp_path, monkeypatch):
    import sys

    import pytest

    from nexus.secresearch import validate
    src = _foundry_repo(tmp_path)
    fake = tmp_path / "forge.py"
    fake.write_text(FAKE_FORGE)
    log = tmp_path / "forge.log"
    monkeypatch.setenv("FAKE_LOG", str(log))
    hb = tmp_path / "harness"
    for name, man in (("h", {"repo": "o/v", "match_contract": "^Nexus", "env": {"FOUNDRY_FUZZ_RUNS": "7"}}),
                      ("ffi", {"repo": "o/v", "env": {"FOUNDRY_FFI": "true"}}), ("otro", {"repo": "o/otro"})):
        (hb / name).mkdir(parents=True)
        (hb / name / "harness.json").write_text(json.dumps(man))
    (hb / "h" / "P.t.sol").write_text("contract P {}\n")
    progs = [{"name": "Prog", "rules_url": "https://example.org", "in_scope": True, "verified_by_owner": True,
              "repos": [{"repo": "o/v"}]}]
    kw = {"out": tmp_path / "out", "programs": progs, "forge": [sys.executable, str(fake)], "url": f"file://{src}",
          "work": tmp_path / "work", "harness_base": hb}

    rec = validate.validate("o/v", harness="h", seed="0x2a", fuzz={"FOUNDRY_INVARIANT_DEPTH": "9"}, **kw)
    build, test = (json.loads(x) for x in log.read_text().splitlines())
    assert build["harness"] == ["P.t.sol"]                                   # copiado antes de compilar
    assert test["argv"] == ["test", "--json", "-vv", "--match-contract", "^Nexus"] and test["ffi"] == "false"
    assert test["fuzz"] == {"FOUNDRY_FUZZ_RUNS": "7", "FOUNDRY_INVARIANT_DEPTH": "9", "FOUNDRY_FUZZ_SEED": "0x2a"}
    assert rec["harness_files"] == ["P.t.sol"] and rec["test"]["activity"][0]["reverts"] == 30
    assert rec["test"]["activity"][0]["logs"][0] == "cazador: leyes evaluadas: 99"  # el log aunque la prueba pase
    md = (tmp_path / "out" / f"o__v@{rec['sha'][:10]}+h@0x2a.md").read_text()
    assert "--harness h --seed 0x2a" in md and "en vacío" in md                # 30 de 40 llamadas revirtieron
    assert "cazador: leyes evaluadas: 99 · cazador: depositos con 0 acciones: 3" in md
    assert "por acción: deposit 25/1 · huntInflation 15/29" in md            # métricas por acción de forge

    log.write_text("")                                                       # línea base: sin código de nexus
    validate.validate("o/v", **kw)
    assert all(json.loads(x)["harness"] is None and not json.loads(x)["fuzz"] for x in log.read_text().splitlines())
    seeds = {validate.validate("o/v", harness="h", **kw)["fuzz"]["FOUNDRY_FUZZ_SEED"] for _ in range(2)}
    assert len(seeds) == 2                                                   # semilla nueva en cada corrida

    log.write_text("")
    with pytest.raises(ValueError, match="FOUNDRY_FFI"):
        validate.validate("o/v", harness="ffi", **kw)
    with pytest.raises(ValueError, match="FOUNDRY_FS_PERMISSIONS"):
        validate.validate("o/v", harness="h", fuzz={"FOUNDRY_FS_PERMISSIONS": "[]"}, **kw)
    assert "es para o/otro" in validate.validate("o/v", harness="otro", **kw)["error"]
    assert log.read_text() == ""                                             # ninguno llegó a forge


def test_metricas_por_accion_con_la_misma_funcion_en_dos_contratos():
    from nexus.secresearch import validate
    # La suite ESR de euler-vault-kit llama `transfer` del token y del vault: ordenar comparaba los diccionarios.
    metrics = {"src/ESR.sol:EulerSavingsRate.transfer": {"calls": 9, "reverts": 1},
               "test/lib/MockToken.sol:MockToken.transfer": {"calls": 7, "reverts": 0},
               "src/ESR.sol:EulerSavingsRate.gulp": {"calls": 3, "reverts": 0}}
    assert validate.per_action(metrics) == "EulerSavingsRate.transfer 9/1 · MockToken.transfer 7/0 · gulp 3/0"


def test_falla_de_invariante_con_el_motivo_en_invariant_failures():
    from nexus.secresearch import validate
    # forge 1.8.6 (27-oct): `reason` en null y el motivo en invariant_failures. Antes el informe decía "Motivo: None".
    ce = {"Sequence": [44, [{"func_name": "deposit", "raw_args": "1, 2"}]]}
    results = {"test/nexus/V.t.sol:VTest": {"test_results": {
        "invariant_vaultV2()": {"status": "Failure", "reason": None, "counterexample": None, "invariant_failures": [
            {"kind": "predicate", "name": "invariant_vaultV2", "counterexample": ce,
             "reason": "V-INF-1: deposit emitio mas (justas, emitidas): 1, 2 [leyes: V-INF-1 V-INF-2]: 132 != 0"}]},
        "test_viejo()": {"status": "Failure", "reason": "H-FEE-5: revirtio", "counterexample": None}}}}
    counts, fails = validate.summarize(results)
    assert counts["Failure"] == 2
    assert fails[0]["reason"].startswith("V-INF-1: deposit") and fails[0]["counterexample"] == ce
    assert fails[1]["reason"] == "H-FEE-5: revirtio"                         # la forma de siempre no cambia


def test_harness_de_metamorpho_es_coherente_y_no_sale_de_la_evm_local():
    from nexus.secresearch import limits, validate
    man, files = validate.load_harness("morpho-org__metamorpho")
    assert man["repo"] == "morpho-org/metamorpho" and man["match_contract"] == "^NexusMetaMorpho"
    assert {f.name for f in files} == {"NexusMetaMorphoBase.sol", "NexusMetaMorphoERC4626.t.sol",
                                       "NexusMetaMorphoInvariant.t.sol", "NexusVulnerabilityHunter.sol",
                                       "NexusMetaMorphoHunter.t.sol"}
    # Ni FFI, ni forks/RPC, ni archivos, ni transacciones: solo cheatcodes de la EVM local.
    banned = ("ffi(", "createFork", "createSelectFork", "selectFork", "rpc(", "rpcUrl", "broadcast", "readFile",
              "writeFile", "envOr", "envString", "setEnv", "sign(", *limits.FORBIDDEN)
    for f in files:
        text = f.read_text(encoding="utf-8")
        assert not [b for b in banned if b in text], f.name


def test_harness_de_vault_v2_es_coherente_y_no_sale_de_la_evm_local():
    from nexus.secresearch import limits, validate
    man, files = validate.load_harness("morpho-org__vault-v2")
    assert man["repo"] == "morpho-org/vault-v2" and man["match_contract"] == "^NexusVaultV2"
    assert {f.name for f in files} == {"NexusVaultV2Hunter.sol", "NexusVaultV2Invariant.t.sol"}
    banned = ("ffi(", "createFork", "createSelectFork", "selectFork", "rpc(", "rpcUrl", "broadcast", "readFile",
              "writeFile", "envOr", "envString", "setEnv", "sign(", *limits.FORBIDDEN)
    for f in files:
        text = f.read_text(encoding="utf-8")
        assert not [b for b in banned if b in text], f.name


def test_ciclo_desatendido_una_vez_con_candado_topes_y_resumen(tmp_path):
    from nexus.secresearch import cycle
    home = tmp_path / "home"
    hb = tmp_path / "harness"
    for name, repo in (("h", "o/v"), ("ajeno", "x/y")):
        (hb / name).mkdir(parents=True)
        (hb / name / "harness.json").write_text(json.dumps({"repo": repo}))
    progs = [{"name": "P", "rules_url": "https://example.org", "in_scope": True, "verified_by_owner": True,
              "repos": [{"repo": "o/v"}, {"repo": "o/w"}, {"repo": "o/z"}]}]
    clock = {"t": 1_000_000.0}
    calls = []

    def scan(targets, out):
        calls.append(("scan", [r for _, r, _ in targets]))
        return {"new_commits": 2, "files": 3, "pending": 5}, []

    def check(repo, harness=None, out=None, **kw):
        calls.append((harness or "base", repo))
        clock["t"] += 60 * 50                                                # cada validación tarda 50 min
        rec = {"repo": repo, "sha": "a" * 40, "ok": harness is None, "build": {"seconds": 1},
               "test": {"seconds": 2, "counts": {"Success": 3, "Failure": int(harness is not None), "Skipped": 0},
                        "failures": [{"suite": "t.sol:T", "test": "invariant_x()", "reason": "precio bajo",
                                      "counterexample": {"args": "7"}, "logs": ["log 1"]}] if harness else [],
                        "activity": [{"suite": "t.sol:T", "test": "invariant_x()", "type": "Invariant", "runs": 4,
                                      "calls": 40, "reverts": 1, "logs": ["cazador: leyes evaluadas: 99"],
                                      "metrics": {"H.donate": {"calls": 40, "reverts": 1}}}]}}
        if harness:
            rec["fuzz"] = {"FOUNDRY_FUZZ_SEED": "0x2a"}
        name = f"{repo.replace('/', '__')}@aaaaaaaaaa" + (f"+{harness}@0x2a" if harness else "")
        out.mkdir(parents=True, exist_ok=True)
        (out / f"{name}.json").write_text(json.dumps(rec))
        with (out / "history.jsonl").open("a") as f:
            f.write(json.dumps({"ts": clock["t"], "repo": repo, "sha": rec["sha"], "harness": harness, "report": name,
                                "seed": "0x2a" if harness else None, "counts": rec["test"]["counts"]}) + "\n")
        return rec

    kw = {"programs": progs, "home": home, "now": lambda: clock["t"], "scan": scan, "check": check, "harness_base": hb}
    rep = cycle.cycle(max_minutes=120, baselines=5, **kw)
    # A–C, el harness del repo verificado (el ajeno no), y líneas base hasta agotar el tope de 120 min
    assert calls == [("scan", ["o/v", "o/w", "o/z"]), ("h", "o/v"), ("base", "o/v"), ("base", "o/w")]
    steps = {s["step"]: s for s in rep["steps"]}
    assert steps["harness ajeno"]["ok"] is None and "no está en un programa verificado" in steps["harness ajeno"]["detail"]
    assert steps["línea base o/z"]["detail"] == "tope de tiempo del ciclo" and not rep["ok"]
    out = home / "secresearch"
    assert "CON FALLAS" in (out / "ciclo.md").read_text() and not (out / "ciclo.lock").exists()
    digest = (out / "para_claude.md").read_text()
    assert "Fallas distintas: 1" in digest and "semilla 0x2a" in digest and '"args": "7"' in digest
    assert "Cobertura de la última corrida" in digest and "40 llamadas · 1 reversiones" in digest
    assert "cazador: leyes evaluadas: 99" in digest                          # métricas del cazador para Claude
    assert "por acción: donate 40/1" in digest
    assert "| o/v | aaaaaaaaaa | 3 pasan · 0 fallan" in digest

    calls.clear()                                                            # al otro día: falta solo o/z
    clock["t"] += 86400
    cycle.cycle(max_minutes=120, baselines=5, **kw)
    assert calls[-1] == ("base", "o/z") and ("base", "o/v") not in calls

    def roto(repo, harness=None, **kw):                                      # una corrida que revienta no corta el ciclo
        if harness:
            raise ValueError("manifiesto roto")
        return check(repo, **kw)
    clock["t"] += 8 * 86400
    rep = cycle.cycle(baselines=1, **{**kw, "check": roto})
    assert [s["ok"] for s in rep["steps"]] == [True, None, False, True] and "manifiesto roto" in rep["steps"][2]["detail"]

    calls.clear()                                                            # otro ciclo en curso: no corre nada
    (out / "ciclo.lock").write_text("{}")
    assert cycle.cycle(**kw)["skipped"] and calls == []
    os.utime(out / "ciclo.lock", (clock["t"] - 13 * 3600,) * 2)              # candado viejo (corte de luz): se toma
    assert not cycle.cycle(baselines=0, **kw).get("skipped") and not (out / "ciclo.lock").exists()
