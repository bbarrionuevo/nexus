"""Panel local: parseo de campañas, validación de lo que se lanza, rutas y seguridad del servidor."""
import http.client
import json
import sys
import threading

import pytest

from nexus.secresearch import panel

LOG = """INICIO mie. 28/10/2026 12:25:14,57 perfil tokenized-strategy semilla 0x1
Ran 4 tests for test/nexus/X.t.sol:NexusTokenizedStrategyEdgeTest
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 38ms
Ran 1 test for test/nexus/X.t.sol:NexusTokenizedStrategyInvariantFeeTest
[PASS] invariant_tokenizedStrategy() (runs: 512, calls: 768000, reverts: 11)
| Contract                      | Selector     | Calls | Reverts | Discards |
+===========================================================================+
| NexusTokenizedStrategyHandler | deposit      | 27000 | 0       | 0        |
|-------------------------------+--------------+-------+---------+----------|
| NexusTokenizedStrategyHandler | lockThenLose | 27449 | 6       | 0        |
|-------------------------------+--------------+-------+---------+----------|
| NexusTokenizedStrategyHandler | report       | 27502 | 5       | 0        |
  cazador: leyes evaluadas: 21601
  cobertura: reportes con ganancia: 26
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 32622.10s
Ran 1 test for test/nexus/X.t.sol:NexusTokenizedStrategyInvariantTest
[FAIL: Y-INF-2: el precio bajo [leyes: Y-INF-2 Y-VIEW-1]] invariant_tokenizedStrategy() (runs: 3, calls: 900, reverts: 0)
Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 10s
FIN mie. 28/10/2026 21:35:10,61 salida 1
"""


@pytest.fixture
def home(tmp_path, monkeypatch):
    monkeypatch.setenv("NEXUS_HOME", str(tmp_path))
    return tmp_path


def test_el_log_de_una_campana_da_su_estado():
    st = panel.parse_log(LOG)
    assert (st["suites_ok"], st["suites_fail"], st["exit"]) == (2, 1, 1)
    fee = next(t for t in st["tests"] if t["suite"] == "NexusTokenizedStrategyInvariantFeeTest")
    assert (fee["runs"], fee["calls"], fee["reverts"], fee["ok"]) == (512, 768000, 11, True)
    assert st["laws"] == ["Y-INF-2", "Y-VIEW-1"]
    assert st["metrics"]["NexusTokenizedStrategyInvariantFeeTest"]["reportes con ganancia"] == 26
    # solo las acciones con reversiones, por variante
    assert st["reverts_by_action"] == {"NexusTokenizedStrategyInvariantFeeTest": {"lockThenLose": 6, "report": 5}}


def test_una_campana_que_pasa_con_reversiones_del_handler_no_queda_como_pasa(home):
    """30-oct: los bordes de dominio de Midnight, el Vault V3 y TokenizedStrategy aparecieron como reversiones del
    handler en campañas que pasaban: el estado tiene que decirlo, y el resumen, cómo investigarlas."""
    sin_falla = LOG.replace(LOG[LOG.index("Ran 1 test for test/nexus/X.t.sol:NexusTokenizedStrategyInvariantTest"):],
                            "FIN mie. 28/10/2026 21:35:10,61 salida 0\n")
    st = panel.parse_log(sin_falla)
    assert panel._estado({"id": "c"}, st) == "pasó con reversiones del handler (revisar)"
    limpio = sin_falla.replace("reverts: 11", "reverts: 0").replace("| 6       |", "| 0       |")
    limpio = limpio.replace("| 5       |", "| 0       |")
    assert panel._estado({"id": "c"}, panel.parse_log(limpio)) == "pasó"
    d = panel.camp_dir(home)
    (d / "c1.txt").write_text(sin_falla, encoding="utf-8")
    texto = panel.resumen("c1", home)
    assert "pasó con reversiones" in texto and "lockThenLose 6, report 5" in texto
    assert "fail_on_revert" in texto
    with pytest.raises(ValueError):
        panel.resumen("../c1", home)


def test_lo_que_se_lanza_esta_validado():
    p = panel.validate_params({"perfil": "euler-earn", "runs": "64", "depth": 200})
    assert (p["runs"], p["depth"], p["match"], p["fail_on_revert"]) == (64, 200, "", False)
    assert panel.SEED.match(p["seed"])
    ok = panel.validate_params({"perfil": "tokenized-strategy", "seed": "0xABC",
                                "match": "^NexusTokenizedStrategyInvariantFeeTest$", "fail_on_revert": 1})
    assert ok["seed"] == "0xabc" and ok["fail_on_revert"] is True
    for bad in ({"perfil": "otro"}, {"perfil": "vault-v2", "runs": 0}, {"perfil": "vault-v2", "depth": 10**6},
                {"perfil": "vault-v2", "seed": "12; calc"}, {"perfil": "vault-v2", "match": "^NexusVaultV2 & calc"},
                {"perfil": "vault-v2", "match": "^NexusEulerEarn"}, {"perfil": "vault-v2", "runs": "x"}):
        with pytest.raises(ValueError):
            panel.validate_params(bad)


def _forge_v2():
    import importlib.util
    spec = importlib.util.spec_from_file_location("forge_v2", panel.FORGE_V2)
    fv2 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fv2)
    return fv2


def test_el_panel_conoce_todos_los_perfiles_de_forge_v2():
    """29-oct: el perfil vault-v3 estaba en tools/forge_v2 y no en el panel."""
    fv2 = _forge_v2()
    assert set(panel.PERFILES) == set(fv2.PERFILES)
    for nombre, (_, prefijo) in panel.PERFILES.items():
        assert fv2.PERFILES[nombre]["match"] == "^" + prefijo, nombre


def test_forge_v2_frena_si_un_submodulo_que_copia_no_esta_en_el_commit_fijado():
    """30-oct: el ciclo movió el EVC de EulerEarn al último commit y armar lo copiaba sin avisar."""
    fv2 = _forge_v2()
    status = (" 232ff9ba lib/erc4626-tests (v0.1.1)\n"
              "+4e5b8c56 lib/ethereum-vault-connector (v1.0.1-9-g4e5b8c5)\n"
              "-77041d2c lib/forge-std\n"
              " e4f70216 lib/openzeppelin-contracts (v4.8.0)\n"
              "+5b98b420 lib/euler-vault-kit (v1.0.1)\n")
    rels = ("src", "lib/forge-std", "lib/openzeppelin-contracts/contracts", "lib/ethereum-vault-connector/src")
    # euler-vault-kit también está movido, pero el perfil no copia nada de ahí
    assert fv2._submodulos_fuera(status, rels) == ["lib/ethereum-vault-connector", "lib/forge-std"]
    en_orden = status.replace("+4e5b", " 4e5b").replace("-7704", " 7704")
    assert fv2._submodulos_fuera(en_orden, rels) == []


def test_solo_se_sirven_archivos_de_secresearch(home):
    (home / "secresearch.yaml").write_text("catalogo", encoding="utf-8")
    (home / "secresearch" / "campanas").mkdir(parents=True)
    (home / "secresearch" / "campanas" / "a.txt").write_text("log", encoding="utf-8")
    (home / "secresearch" / "campanas" / "a.exe").write_bytes(b"MZ")
    assert panel.safe_file("campanas/a.txt", home).name == "a.txt"
    for rel in ("../secresearch.yaml", "campanas/a.exe", "campanas/../../secresearch.yaml", "no/existe.md"):
        assert panel.safe_file(rel, home) is None


def test_lanzar_registra_la_campana_y_no_usa_shell(home, monkeypatch):
    seen = {}

    class FakeProc:
        pid = 4321

    def fake_popen(cmd, **kw):
        seen.update(cmd=cmd, kw=kw)
        return FakeProc()

    monkeypatch.setattr(panel.subprocess, "Popen", fake_popen)
    rec = panel.launch({"perfil": "vault-v2", "runs": 8, "depth": 50, "seed": "0x2a"}, home)
    assert seen["cmd"] == [sys.executable, "-m", "nexus.secresearch.panel", "--run", rec["id"]]
    assert not seen["kw"].get("shell")
    saved = json.loads((home / "secresearch" / "campanas" / f"{rec['id']}.json").read_text(encoding="utf-8"))
    assert saved["pid"] == 4321 and saved["seed"] == "0x2a" and saved["dest"].startswith(str(home))
    with pytest.raises(ValueError):                                   # un PID que no es el suyo no se frena
        panel.stop(rec["id"], home)


def test_la_campana_se_separa_del_job_de_quien_la_lanza(home, monkeypatch):
    """29-oct: las campañas lanzadas desde una sesión morían cuando la sesión se reiniciaba (el job de quien lanza).
    Se pide separarse del job; si no se permite (OSError), se lanza como antes."""
    calls = []

    class FakeProc:
        pid = 99

    def fake_popen(cmd, creationflags=0, **kw):
        calls.append(creationflags)
        if len(calls) == 1 and creationflags & 0x01000000:
            raise PermissionError("acceso denegado")
        return FakeProc()

    monkeypatch.setattr(panel, "BREAKAWAY", 0x01000000)
    monkeypatch.setattr(panel, "BELOW_NORMAL", 0x00004000)
    monkeypatch.setattr(panel.subprocess, "Popen", fake_popen)
    rec = panel.launch({"perfil": "midnight", "runs": 8, "depth": 50, "seed": "0x2a"}, home)
    assert rec["pid"] == 99 and len(calls) == 2
    assert calls[0] & 0x01000000 and not calls[1] & 0x01000000
    if panel.os.name == "nt":                     # prioridad por debajo de lo normal en los dos intentos
        assert all(c & 0x00004000 for c in calls)


@pytest.fixture
def server(home, monkeypatch):
    monkeypatch.setattr(panel, "forge_procs", list)
    srv = panel.Panel(("127.0.0.1", 0), "tok", home)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield srv
    srv.shutdown()


def _req(srv, method, path, headers=None, body=None):
    port = srv.server_address[1]
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    conn.request(method, path, body=body, headers={"Host": f"127.0.0.1:{port}", **(headers or {})})
    r = conn.getresponse()
    return r.status, dict(r.getheaders()), r.read()


def test_el_servidor_pide_token_host_y_encabezado_para_actuar(server):
    assert _req(server, "GET", "/")[0] == 403                                       # sin token
    status, headers, page = _req(server, "GET", "/?t=tok")
    assert status == 200 and "default-src 'none'" in headers["Content-Security-Policy"] and b"Panel de nexus" in page
    assert _req(server, "GET", "/?t=tok", {"Host": "evil.example:80"})[0] == 403   # DNS rebinding
    status, _, data = _req(server, "GET", "/api/state?t=tok")
    assert status == 200 and set(json.loads(data)) >= {"campaigns", "forge", "files", "perfiles"}
    assert _req(server, "GET", "/api/file?t=tok&path=../secresearch.yaml")[0] == 404
    body = json.dumps({"id": "no-existe"})
    assert _req(server, "POST", "/api/stop?t=tok", {"Content-Type": "application/json"}, body)[0] == 403  # CSRF
    status, _, data = _req(server, "POST", "/api/stop", {"X-Nexus-Token": "tok"}, body)
    assert status == 400 and "desconocida" in json.loads(data)["error"]
    status, _, data = _req(server, "POST", "/api/launch", {"X-Nexus-Token": "tok"}, json.dumps({"perfil": "x"}))
    assert status == 400
