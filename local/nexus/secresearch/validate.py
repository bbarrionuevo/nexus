"""Etapa D: validación local con Foundry sobre el código EN ALCANCE (corre en la PC del dueño).

  python -m nexus.secresearch.validate owner/repo [--ref SHA] [--match-path GLOB] [--out DIR]
  python -m nexus.secresearch.validate owner/repo --harness NOMBRE [--seed 0xHEX] [--fuzz-runs N]
                                       [--invariant-runs N] [--invariant-depth N] [--ref SHA]

1. El repo tiene que pertenecer a un programa que el dueño verificó (limits.repo_in_scope): compilar y
   testear es ejecutar código ajeno en la PC, así que nunca se hace sobre algo fuera del catálogo.
2. Clona el repo en NEXUS_HOME/work, fijado a un commit (por defecto el último), con sus submódulos.
3. forge build y forge test --json -vv, con FOUNDRY_FFI=false forzado y topes de tiempo.
4. Informe privado en NEXUS_HOME/secresearch/validate: tests pasados, fallados y contraejemplos, más
   una línea por corrida en history.jsonl para medir.
Todo es local: sin RPC ni forks, sin desplegar ni transmitir nada. La primera corrida de un repo es su
LÍNEA BASE (su propia suite): un test que falla ahí NO es una vulnerabilidad, es algo para mirar.

Con --harness, además copia los tests de propiedades e invariantes de nexus (harness/NOMBRE/*.sol) a
test/nexus/ del clon y corre solo esos, con una semilla nueva en cada corrida (queda en el informe para
reproducir) y la intensidad de fuzzing del manifiesto harness.json. El harness solo puede fijar variables de
intensidad y semilla de Foundry (FUZZ_ENV): nunca FFI ni permisos de archivos, y FOUNDRY_ENV se aplica al final.
Sin --harness, test/nexus/ se borra: la línea base corre siempre sin código de nexus.
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

from .. import paths
from . import catalog, dashboard
from .changes import NO_WINDOW, _git
from .limits import FOUNDRY_ENV, MAX_BUILD_SECONDS, MAX_TEST_SECONDS, repo_in_scope, results_dir

TAIL = 40
MAX_LOGS = 20
HARNESS_DIR = Path(__file__).resolve().parent / "harness"
HARNESS_DEST = Path("test") / "nexus"
FUZZ_ENV = ("FOUNDRY_FUZZ_RUNS", "FOUNDRY_FUZZ_SEED", "FOUNDRY_FUZZ_MAX_TEST_REJECTS", "FOUNDRY_INVARIANT_RUNS",
            "FOUNDRY_INVARIANT_DEPTH",
            "FOUNDRY_INVARIANT_SHOW_METRICS")   # solo salida: llamadas y reversiones por acción del handler


def say(msg):
    """Progreso en pantalla: compilar con via_ir tarda minutos y sin esto parece colgado."""
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def checkout(repo, workdir, ref=None, url=None):
    """Clon fijado a un commit, con submódulos. Devuelve (carpeta, sha)."""
    d = Path(workdir) / repo.replace("/", "__")
    if (d / ".git").exists():
        _git(["fetch", "--quiet", "origin"], cwd=d, timeout=900)
    else:
        d.parent.mkdir(parents=True, exist_ok=True)
        _git(["clone", "--quiet", url or f"https://github.com/{repo}.git", str(d)], timeout=900)
    _git(["checkout", "--quiet", "--force", ref or "origin/HEAD"], cwd=d)
    _git(["submodule", "update", "--init", "--recursive", "--quiet"], cwd=d, timeout=1800)
    return d, _git(["rev-parse", "HEAD"], cwd=d).strip()


def load_harness(name, base=None):
    """(manifiesto, archivos .sol) del harness NOMBRE. Rechaza variables de Foundry fuera de FUZZ_ENV."""
    d = Path(base or HARNESS_DIR) / name
    man = json.loads((d / "harness.json").read_text(encoding="utf-8"))
    bad = sorted(set(man.get("env") or {}) - set(FUZZ_ENV))
    if bad:
        raise ValueError(f"el harness {name} fija variables no permitidas: {', '.join(bad)}")
    return man, sorted(d.glob("*.sol"))


def install_harness(clone, files):
    """Vacía test/nexus/ del clon (restos de otra corrida) y copia `files`. Devuelve los nombres copiados."""
    dest = Path(clone) / HARNESS_DEST
    shutil.rmtree(dest, ignore_errors=True)
    if files:
        dest.mkdir(parents=True)
        for f in files:
            shutil.copy2(f, dest / f.name)
    return [f.name for f in files]


def forge_run(forge, args, cwd, timeout, env=None):
    """Un comando de Foundry con las variables de seguridad forzadas. (código, stdout, stderr, segundos)."""
    t0 = time.time()
    try:
        # UTF-8 y errors="replace": en Windows (cp1252) el indicador de progreso de forge (byte 0x81) mataba el
        # hilo lector, forge quedaba trabado sin poder escribir y la corrida parecía colgada (26-oct).
        r = subprocess.run([*forge, *args], cwd=cwd, env={**os.environ, **(env or {}), **FOUNDRY_ENV},
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout,
                           check=False, creationflags=NO_WINDOW)
        return r.returncode, r.stdout or "", r.stderr or "", round(time.time() - t0, 1)
    except subprocess.TimeoutExpired:
        return 124, "", f"tiempo agotado ({timeout} s)", float(timeout)


def parse(stdout):
    """El JSON de `forge test --json` (tolera líneas de compilación antes del objeto)."""
    for chunk in (stdout, *reversed(stdout.splitlines())):
        chunk = chunk.strip()
        if chunk.startswith("{"):
            try:
                return json.loads(chunk)
            except ValueError:
                continue
    return None


def _kind(t):
    """{"type": "Invariant", "runs", "calls", "reverts", "metrics"} desde el `kind` de forge ({"Invariant": {...}}).
    `metrics` son las métricas por acción del handler ({"Handler.deposit": {"calls", "reverts", "discards"}}); forge las
    incluye por defecto (invariant.show_metrics) y dicen qué acciones y macros corrió de verdad la campaña."""
    k = t.get("kind")
    if not isinstance(k, dict) or len(k) != 1:
        return None
    (name, v), = k.items()
    v = v if isinstance(v, dict) else {}
    metrics = v.get("metrics") if isinstance(v.get("metrics"), dict) else {}
    return {"type": name, **{x: v[x] for x in ("runs", "calls", "reverts") if x in v},
            **({"metrics": metrics} if metrics else {})}


def per_action(metrics, limit=40):
    """'deposit 120/2 · mint 98/0 · …' (llamadas/reversiones por acción, sin el nombre del contrato)."""
    return " · ".join(f"{name} {m.get('calls', 0)}/{m.get('reverts', 0)}"
                      for name, m in dashboard.action_rows(metrics)[:limit])


def _failure(t):
    """Motivo y contraejemplo de un test. forge 1.8 puede dejar `reason` en null en la falla de un invariante y poner el
    de cada invariante en `invariant_failures` ([{"name", "reason", "counterexample"}]): sin esto, el informe decía
    "Motivo: None" y el expediente no encontraba la ley que falló."""
    reason, ce = t.get("reason"), t.get("counterexample")
    inv = [f for f in (t.get("invariant_failures") or []) if isinstance(f, dict)]
    if not reason and inv:
        reason = " | ".join(str(f.get("reason")) if len(inv) == 1 else f"{f.get('name')}: {f.get('reason')}"
                            for f in inv)
    if not ce and inv:
        ce = inv[0].get("counterexample")
    return {"reason": reason, "counterexample": ce}


def summarize(results):
    rows = [{"suite": suite, "test": name, "status": t.get("status"), **_failure(t),
             "logs": (t.get("decoded_logs") or [])[:15], "kind": _kind(t)}
            for suite, data in (results or {}).items() for name, t in (data.get("test_results") or {}).items()]
    counts = {s: sum(r["status"] == s for r in rows) for s in ("Success", "Failure", "Skipped")}
    return counts, [r for r in rows if r["status"] == "Failure"]


def activity(results):
    """Invariantes: corridas, llamadas, reversiones (si casi todo revierte, la prueba pasa en vacío) y el log de
    afterInvariant, también cuando pasan: ahí van las métricas del cazador (cuánto del espacio de ataque se exploró)."""
    return [{"suite": suite, "test": name, **k, "logs": [str(x) for x in (t.get("decoded_logs") or [])][:MAX_LOGS]}
            for suite, data in (results or {}).items() for name, t in (data.get("test_results") or {}).items()
            if (k := _kind(t)) and k["type"] == "Invariant"]


def report(rec):
    lines = [f"# Validación local: {rec['repo']} @ {rec.get('sha', '?')[:10]}", "",
             f"Programa: {rec.get('program', '—')} · FFI apagado · {rec.get('when', '')}", ""]
    if rec.get("harness"):
        fz, seed = rec.get("fuzz") or {}, (rec.get("fuzz") or {}).get("FOUNDRY_FUZZ_SEED")
        files = ", ".join(rec.get("harness_files") or [])
        runs = (f"fuzz {fz.get('FOUNDRY_FUZZ_RUNS', '256')} corridas · invariantes "
                f"{fz.get('FOUNDRY_INVARIANT_RUNS', '256')}×{fz.get('FOUNDRY_INVARIANT_DEPTH', '500')}")
        again = (f"python -m nexus.secresearch.validate {rec['repo']} --ref {rec.get('sha', '?')} "
                 f"--harness {rec['harness']} --seed {seed}")
        lines += [f"Harness de nexus: `{rec['harness']}` ({files}) · semilla `{seed}` · {runs}", "",
                  f"Reproducir: `{again}`", ""]
    if rec.get("error"):
        return "\n".join(lines + [f"**No se pudo validar:** {rec['error']}", *rec.get("tail", [])]) + "\n"
    b, t = rec["build"], rec.get("test")
    lines.append(f"- Compilación: {'OK' if b['exit'] == 0 else 'FALLÓ'} ({b['seconds']} s)")
    if t:
        c = t["counts"]
        lines.append(f"- Tests: {c['Success']} pasan · {c['Failure']} fallan · {c['Skipped']} omitidos "
                     f"({t['seconds']} s){' · filtro ' + rec['match'] if rec.get('match') else ''}")
        for a in t.get("activity") or []:
            lines.append(f"- `{a['test']}` ({a['suite'].split(':')[-1]}): {a.get('runs')} corridas · "
                         f"{a.get('calls')} llamadas · {a.get('reverts')} reversiones")
            if a.get("calls") and (a.get("reverts") or 0) * 2 > a["calls"]:
                lines.append("  - **Más de la mitad de las llamadas revirtieron: puede estar pasando en vacío.**")
            if a.get("metrics"):
                lines.append("  - llamadas/reversiones por acción: " + per_action(a["metrics"]))
            if a.get("logs"):
                lines.append("  - " + " · ".join(a["logs"]))
        for f in t["failures"][:30]:
            lines += ["", f"### FALLA `{f['suite']}::{f['test']}`", f"Motivo: {f['reason']}"]
            if f["counterexample"]:
                lines.append(f"Contraejemplo: `{json.dumps(f['counterexample'], ensure_ascii=False)[:3000]}`")
            if f.get("logs"):
                lines += ["```", *f["logs"], "```"]
    if rec.get("tail"):
        lines += ["", "```", *rec["tail"], "```"]
    lines += ["", ("Un test que falla NO es una vulnerabilidad: puede ser el entorno o un test a medio "
                   "hacer. Solo cuenta un efecto económico reproducible, revisado contra auditorías previas.")]
    return "\n".join(lines) + "\n"


def validate(repo, ref=None, match=None, out=None, programs=None, forge=None, url=None, work=None, harness=None,
             seed=None, fuzz=None, harness_base=None):
    """`fuzz`: {variable de FUZZ_ENV: valor} que pisa al manifiesto del harness (p. ej. desde la línea de comandos)."""
    progs = catalog.load(paths.home() / "secresearch.yaml") if programs is None else programs
    prog = repo_in_scope(repo, progs)
    if not prog:
        return {"repo": repo, "ok": False, "error": f"{repo} no pertenece a ningún programa verificado del catálogo"}
    files, env, contract = [], {}, None
    if harness:
        man, files = load_harness(harness, harness_base)
        if man.get("repo") != repo:
            return {"repo": repo, "ok": False, "error": f"el harness {harness} es para {man.get('repo')}, no {repo}"}
        extra = dict(fuzz or {})
        if set(extra) - set(FUZZ_ENV):
            raise ValueError(f"variables no permitidas: {', '.join(sorted(set(extra) - set(FUZZ_ENV)))}")
        env = {**(man.get("env") or {}), **extra, "FOUNDRY_FUZZ_SEED": seed or "0x" + os.urandom(8).hex()}
        match = match or man.get("match_path")
        contract = man.get("match_contract")       # regex sobre el nombre: no depende de "/" o "\\" en Windows
    if forge is None:
        exe = shutil.which("forge")
        if not exe:
            return {"repo": repo, "ok": False, "error": "forge no está instalado (ver docs/INVESTIGACION_SEGURIDAD.md)"}
        forge = [exe]
    out = results_dir(out or paths.home() / "secresearch" / "validate")
    out.mkdir(parents=True, exist_ok=True)
    rec = {"repo": repo, "program": prog["name"], "when": time.strftime("%Y-%m-%d %H:%M"), "match": match or contract}
    if harness:
        rec.update(harness=harness, fuzz=env)
    say(f"{repo}: clonando con submódulos (programa {prog['name']})…")
    try:
        d, rec["sha"] = checkout(repo, results_dir(work or paths.home() / "work"), ref, url)
    except Exception as e:                                       # noqa: BLE001 (se informa)
        rec.update(ok=False, error=f"no se pudo clonar: {str(e)[:300]}")
        return _save(out, rec)
    rec["harness_files"] = install_harness(d, files)
    say(f"commit {rec['sha'][:10]} · compilando (la primera vez puede tardar varios minutos)…")
    code, so, se, secs = forge_run(forge, ["build"], d, MAX_BUILD_SECONDS)
    rec["build"] = {"exit": code, "seconds": secs}
    if code:
        rec.update(ok=False, tail=(so + se).strip().splitlines()[-TAIL:])
        return _save(out, rec)
    # -vv: sin eso, forge vacía los logs del JSON y el informe pierde el log de afterInvariant (verificaciones,
    # métricas del cazador). Solo cambia la salida; las trazas siguen apagadas (empiezan en -vvv).
    args = ["test", "--json", "-vv"] + (["--match-path", match] if match else []) + (
        ["--match-contract", contract] if contract else [])
    say(f"compiló en {secs} s · corriendo tests (puede tardar varios minutos)…")
    code, so, se, secs = forge_run(forge, args, d, MAX_TEST_SECONDS, env)
    say(f"tests terminados en {secs} s")
    data = parse(so)
    if data is None:
        rec.update(ok=False, test=None, tail=(so + se).strip().splitlines()[-TAIL:])
        return _save(out, rec)
    counts, failures = summarize(data)
    rec["test"] = {"exit": code, "seconds": secs, "counts": counts, "failures": failures, "activity": activity(data)}
    rec["ok"] = counts["Failure"] == 0
    return _save(out, rec)


def _save(out, rec):
    name = f"{rec['repo'].replace('/', '__')}@{rec.get('sha', 'sin-commit')[:10]}"
    if rec.get("harness"):                                   # una corrida por semilla: no pisa la línea base
        name += f"+{rec['harness']}@{(rec.get('fuzz') or {}).get('FOUNDRY_FUZZ_SEED', '')}"
    (out / f"{name}.json").write_text(json.dumps(rec, indent=1, ensure_ascii=False), encoding="utf-8")
    (out / f"{name}.md").write_text(report(rec), encoding="utf-8")
    t = rec.get("test") or {}
    with (out / "history.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps({"ts": time.time(), "repo": rec["repo"], "sha": rec.get("sha"), "ok": rec.get("ok"),
                            "report": name, "harness": rec.get("harness"),
                            "seed": (rec.get("fuzz") or {}).get("FOUNDRY_FUZZ_SEED"),
                            "build_s": (rec.get("build") or {}).get("seconds"), "test_s": t.get("seconds"),
                            "counts": t.get("counts"), "error": rec.get("error")}) + "\n")
    return rec


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    opts = {k: v for k, v in zip(argv[1::2], argv[2::2])}
    flags = {"--fuzz-runs": "FOUNDRY_FUZZ_RUNS", "--invariant-runs": "FOUNDRY_INVARIANT_RUNS",
             "--invariant-depth": "FOUNDRY_INVARIANT_DEPTH"}
    fuzz = {var: str(int(opts[f])) for f, var in flags.items() if f in opts}
    rec = validate(argv[0], ref=opts.get("--ref"), match=opts.get("--match-path"), out=opts.get("--out"),
                   harness=opts.get("--harness"), seed=opts.get("--seed"), fuzz=fuzz)
    print(report(rec))
    try:
        print(f"Dashboard: {dashboard.write()}")
    except Exception as e:                                       # noqa: BLE001 (el informe ya quedó)
        print(f"dashboard: {type(e).__name__}: {e}")
    return 0 if rec.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
