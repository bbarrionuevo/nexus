"""Etapa D: validación local con Foundry sobre el código EN ALCANCE (corre en la PC del dueño).

  python -m nexus.secresearch.validate owner/repo [--ref SHA] [--match-path GLOB] [--out DIR]

1. El repo tiene que pertenecer a un programa que el dueño verificó (limits.repo_in_scope): compilar y
   testear es ejecutar código ajeno en la PC, así que nunca se hace sobre algo fuera del catálogo.
2. Clona el repo en NEXUS_HOME/work, fijado a un commit (por defecto el último), con sus submódulos.
3. forge build y forge test --json, con FOUNDRY_FFI=false forzado y topes de tiempo.
4. Informe privado en NEXUS_HOME/secresearch/validate: tests pasados, fallados y contraejemplos, más
   una línea por corrida en history.jsonl para medir.
Todo es local: sin RPC ni forks, sin desplegar ni transmitir nada. La primera corrida de un repo es su
LÍNEA BASE (su propia suite): un test que falla ahí NO es una vulnerabilidad, es algo para mirar.
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

from .. import paths
from . import catalog
from .changes import _git
from .limits import FOUNDRY_ENV, MAX_BUILD_SECONDS, MAX_TEST_SECONDS, repo_in_scope, results_dir

TAIL = 40


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


def forge_run(forge, args, cwd, timeout):
    """Un comando de Foundry con las variables de seguridad forzadas. (código, stdout, stderr, segundos)."""
    t0 = time.time()
    try:
        r = subprocess.run([*forge, *args], cwd=cwd, env={**os.environ, **FOUNDRY_ENV}, capture_output=True,
                           text=True, timeout=timeout, check=False)
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


def summarize(results):
    rows = [{"suite": suite, "test": name, "status": t.get("status"), "reason": t.get("reason"),
             "counterexample": t.get("counterexample")}
            for suite, data in (results or {}).items() for name, t in (data.get("test_results") or {}).items()]
    counts = {s: sum(r["status"] == s for r in rows) for s in ("Success", "Failure", "Skipped")}
    return counts, [r for r in rows if r["status"] == "Failure"]


def report(rec):
    lines = [f"# Validación local: {rec['repo']} @ {rec.get('sha', '?')[:10]}", "",
             f"Programa: {rec.get('program', '—')} · FFI apagado · {rec.get('when', '')}", ""]
    if rec.get("error"):
        return "\n".join(lines + [f"**No se pudo validar:** {rec['error']}", *rec.get("tail", [])]) + "\n"
    b, t = rec["build"], rec.get("test")
    lines.append(f"- Compilación: {'OK' if b['exit'] == 0 else 'FALLÓ'} ({b['seconds']} s)")
    if t:
        c = t["counts"]
        lines.append(f"- Tests: {c['Success']} pasan · {c['Failure']} fallan · {c['Skipped']} omitidos "
                     f"({t['seconds']} s){' · filtro ' + rec['match'] if rec.get('match') else ''}")
        for f in t["failures"][:30]:
            lines += ["", f"### FALLA `{f['suite']}::{f['test']}`", f"Motivo: {f['reason']}"]
            if f["counterexample"]:
                lines.append(f"Contraejemplo: `{json.dumps(f['counterexample'], ensure_ascii=False)[:600]}`")
    if rec.get("tail"):
        lines += ["", "```", *rec["tail"], "```"]
    lines += ["", ("Un test que falla NO es una vulnerabilidad: puede ser el entorno o un test a medio "
                   "hacer. Solo cuenta un efecto económico reproducible, revisado contra auditorías previas.")]
    return "\n".join(lines) + "\n"


def validate(repo, ref=None, match=None, out=None, programs=None, forge=None, url=None, work=None):
    progs = catalog.load(paths.home() / "secresearch.yaml") if programs is None else programs
    prog = repo_in_scope(repo, progs)
    if not prog:
        return {"repo": repo, "ok": False, "error": f"{repo} no pertenece a ningún programa verificado del catálogo"}
    if forge is None:
        exe = shutil.which("forge")
        if not exe:
            return {"repo": repo, "ok": False, "error": "forge no está instalado (ver docs/INVESTIGACION_SEGURIDAD.md)"}
        forge = [exe]
    out = results_dir(out or paths.home() / "secresearch" / "validate")
    out.mkdir(parents=True, exist_ok=True)
    rec = {"repo": repo, "program": prog["name"], "when": time.strftime("%Y-%m-%d %H:%M"), "match": match}
    try:
        d, rec["sha"] = checkout(repo, results_dir(work or paths.home() / "work"), ref, url)
    except Exception as e:                                       # noqa: BLE001 (se informa)
        rec.update(ok=False, error=f"no se pudo clonar: {str(e)[:300]}")
        return _save(out, rec)
    code, so, se, secs = forge_run(forge, ["build"], d, MAX_BUILD_SECONDS)
    rec["build"] = {"exit": code, "seconds": secs}
    if code:
        rec.update(ok=False, tail=(so + se).strip().splitlines()[-TAIL:])
        return _save(out, rec)
    args = ["test", "--json"] + (["--match-path", match] if match else [])
    code, so, se, secs = forge_run(forge, args, d, MAX_TEST_SECONDS)
    data = parse(so)
    if data is None:
        rec.update(ok=False, test=None, tail=(so + se).strip().splitlines()[-TAIL:])
        return _save(out, rec)
    counts, failures = summarize(data)
    rec["test"] = {"exit": code, "seconds": secs, "counts": counts, "failures": failures}
    rec["ok"] = counts["Failure"] == 0
    return _save(out, rec)


def _save(out, rec):
    name = f"{rec['repo'].replace('/', '__')}@{rec.get('sha', 'sin-commit')[:10]}"
    (out / f"{name}.json").write_text(json.dumps(rec, indent=1, ensure_ascii=False), encoding="utf-8")
    (out / f"{name}.md").write_text(report(rec), encoding="utf-8")
    t = rec.get("test") or {}
    with (out / "history.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps({"ts": time.time(), "repo": rec["repo"], "sha": rec.get("sha"), "ok": rec.get("ok"),
                            "build_s": (rec.get("build") or {}).get("seconds"), "test_s": t.get("seconds"),
                            "counts": t.get("counts"), "error": rec.get("error")}) + "\n")
    return rec


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    opts = {k: v for k, v in zip(argv[1::2], argv[2::2])}
    rec = validate(argv[0], ref=opts.get("--ref"), match=opts.get("--match-path"), out=opts.get("--out"))
    print(report(rec))
    return 0 if rec.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
