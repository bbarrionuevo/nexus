"""Ciclo desatendido para la PC del dueño: adelanta trabajo sin nadie mirando, una vez y con topes.

  python -m nexus.secresearch.cycle [--max-minutes 180] [--baselines 2]

1. Etapas A–C (run.scan): commits nuevos en el código en alcance, con triaje.
2. Etapa D': cada harness de nexus cuyo repo pertenece a un programa verificado, con una semilla NUEVA:
   cada corrida explora entradas distintas y la semilla queda en el informe para reproducir.
3. Etapa D: líneas base de hasta N repos del catálogo sin una en los últimos 7 días (primero los que nunca la
   tuvieron). Muestran qué compila y qué pasa antes de escribir un harness para cada repo.
4. Resumen del ciclo (ciclo.md, ciclo.jsonl) y un acumulado para pegarle a Claude (para_claude.md), todo en
   NEXUS_HOME/secresearch: privado, nunca en el repo.

Corre UNA vez y termina: el Programador de tareas de Windows decide cuándo vuelve a correr; el ciclo nunca se
reprograma ni se encadena solo. Un candado evita dos ciclos a la vez. No envía ni publica nada: el único
tráfico de red es git clone/fetch de los repos del catálogo y la descarga de compiladores que hace forge.
"""
import json
import os
import sys
import time
from pathlib import Path

from .. import paths
from . import catalog, run, validate
from .limits import repo_in_scope, results_dir

LOCK_STALE_S = 12 * 3600          # un candado más viejo es de un ciclo que murió (corte de luz, reinicio)
BASELINE_EVERY_S = 7 * 86400
MAX_LOG_BYTES = 2_000_000


def harnesses(base=None):
    """{nombre del harness: repo} de los harness de nexus."""
    d = Path(base or validate.HARNESS_DIR)
    return {p.name: json.loads((p / "harness.json").read_text(encoding="utf-8"))["repo"]
            for p in sorted(d.iterdir()) if (p / "harness.json").exists()}


def take_lock(path, now):
    for _ in range(2):
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            try:
                if now - path.stat().st_mtime < LOCK_STALE_S:
                    return False
            except FileNotFoundError:
                continue
            path.unlink(missing_ok=True)
            continue
        with os.fdopen(fd, "w") as f:
            f.write(json.dumps({"pid": os.getpid(), "ts": now}))
        return True
    return False


def history(path):
    p = Path(path)
    return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.exists() else []


def baselines_due(repos, hist, now, limit):
    """Repos sin línea base reciente, primero los que nunca la tuvieron y después los más viejos."""
    last = {}
    for h in hist:
        if not h.get("harness"):
            last[h["repo"]] = max(last.get(h["repo"], 0), h.get("ts") or 0)
    due = [r for r in repos if now - last.get(r, 0) > BASELINE_EVERY_S]
    return sorted(due, key=lambda r: last.get(r, 0))[:limit]


def _step(name, rec):
    if rec.get("error"):
        return {"step": name, "ok": False, "detail": rec["error"][:300]}
    t, b = rec.get("test") or {}, rec.get("build") or {}
    if not t:
        return {"step": name, "ok": False, "detail": f"no compiló ({b.get('seconds')} s)" if b else "sin resultado"}
    c = t["counts"]
    seed = (rec.get("fuzz") or {}).get("FOUNDRY_FUZZ_SEED")
    detail = (f"{rec.get('sha', '?')[:10]} · {c['Success']} pasan · {c['Failure']} fallan · {c['Skipped']} omitidos"
              f" · compilación {b.get('seconds')} s · tests {t.get('seconds')} s" + (f" · semilla {seed}" if seed else ""))
    return {"step": name, "ok": rec.get("ok"), "detail": detail,
            "failures": [f"{f['suite'].split(':')[-1]}::{f['test']}: {(f.get('reason') or '')[:200]}"
                         for f in t.get("failures", [])[:10]]}


def _guarded(name, fn):
    """Una corrida que revienta (un manifiesto roto, un disco lleno) queda como falla y el ciclo sigue."""
    try:
        return _step(name, fn())
    except Exception as e:                                       # noqa: BLE001 (se informa y se sigue)
        return {"step": name, "ok": False, "detail": f"{type(e).__name__}: {e}"[:300]}


def cycle(max_minutes=180, baselines=2, programs=None, home=None, now=time.time, scan=run.scan,
          check=validate.validate, harness_base=None):
    base = Path(home or paths.home())
    out = results_dir(base / "secresearch")
    out.mkdir(parents=True, exist_ok=True)
    t0 = now()
    lock = out / "ciclo.lock"
    if not take_lock(lock, t0):
        return {"ts": t0, "ok": False, "steps": [], "skipped": "otro ciclo en curso (ciclo.lock)"}
    try:
        progs = catalog.load(base / "secresearch.yaml") if programs is None else programs
        ok = catalog.actionable(progs)
        targets = [(p["name"], r["repo"], r.get("paths") or []) for p in ok for r in p["repos"]]
        steps, vout = [], out / "validate"
        kw = {"programs": progs, "out": vout, "work": base / "work"}

        def late():
            return (now() - t0) / 60 > max_minutes

        if targets:
            try:
                s, _ = scan(targets, out)
                steps.append({"step": "cambios (A–C)", "ok": True,
                              "detail": f"{s['new_commits']} commits nuevos · {s['files']} archivos · "
                                        f"{s.get('pending', 0)} pendientes de revisar"})
            except Exception as e:                               # noqa: BLE001 (se informa y se sigue)
                steps.append({"step": "cambios (A–C)", "ok": False, "detail": f"{type(e).__name__}: {e}"[:300]})
        for name, repo in harnesses(harness_base).items():
            if not repo_in_scope(repo, progs):
                steps.append({"step": f"harness {name}", "ok": None, "detail": f"{repo} no está en un programa verificado"})
            elif late():
                steps.append({"step": f"harness {name}", "ok": None, "detail": "tope de tiempo del ciclo"})
            else:
                steps.append(_guarded(f"harness {name}",
                                      lambda r=repo, n=name: check(r, harness=n, harness_base=harness_base, **kw)))
        repos = list(dict.fromkeys(r for _, r, _ in targets))
        for repo in baselines_due(repos, history(vout / "history.jsonl"), now(), baselines):
            if late():
                steps.append({"step": f"línea base {repo}", "ok": None, "detail": "tope de tiempo del ciclo"})
                break
            steps.append(_guarded(f"línea base {repo}", lambda r=repo: check(r, **kw)))
        rep = {"ts": t0, "minutes": round((now() - t0) / 60, 1), "ok": all(s["ok"] is not False for s in steps),
               "steps": steps}
        (out / "ciclo.md").write_text(report(rep), encoding="utf-8")
        with (out / "ciclo.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps(rep, ensure_ascii=False) + "\n")
        try:
            (out / "para_claude.md").write_text(digest(out), encoding="utf-8")
        except Exception as e:                                   # noqa: BLE001 (el resumen del ciclo ya quedó)
            print(f"para_claude.md: {type(e).__name__}: {e}")
        return rep
    finally:
        lock.unlink(missing_ok=True)


def report(rep):
    when = time.strftime("%Y-%m-%d %H:%M", time.localtime(rep["ts"]))
    state = "sin fallas" if rep["ok"] else "CON FALLAS PARA REVISAR"
    lines = [f"# Ciclo desatendido · {when} · {rep['minutes']} min · {state}", "",
             "| Paso | Resultado | Detalle |", "|---|---|---|"]
    for s in rep["steps"]:
        res = "omitido" if s["ok"] is None else "OK" if s["ok"] else "FALLA"
        lines.append(f"| {s['step']} | {res} | {s['detail']} |")
    for s in rep["steps"]:
        for f in s.get("failures") or []:
            lines.append(f"- {s['step']}: `{f}`")
    lines += ["", ("Informes completos: secresearch.md (cambios) y validate/*.md (Foundry). Un test que falla NO es "
                   "una vulnerabilidad: es algo para revisar con el contraejemplo y la semilla del informe.")]
    return "\n".join(lines) + "\n"


def coverage(out, runs):
    """Última corrida de cada harness: actividad de cada invariante y su log de afterInvariant (métricas del cazador:
    leyes evaluadas, depósitos con 0 acciones, ventana de redondeo, polvo, comisiones). Sirve para decidir el próximo
    cambio aunque no haya fallas."""
    latest = {}
    for h in runs:
        latest[h["harness"]] = h
    lines = ["", "## Cobertura de la última corrida de cada harness", ""]
    for name, h in sorted(latest.items()):
        rec = Path(out) / "validate" / f"{h.get('report')}.json" if h.get("report") else None
        if not (rec and rec.exists()):
            continue
        acts = (json.loads(rec.read_text(encoding="utf-8")).get("test") or {}).get("activity") or []
        lines.append(f"### `{name}` · semilla {h.get('seed')} · {(h.get('sha') or '?')[:10]}")
        for a in acts:
            lines.append(f"- `{a['suite'].split(':')[-1]}::{a['test']}`: {a.get('runs')} corridas · {a.get('calls')} "
                         f"llamadas · {a.get('reverts')} reversiones")
            if a.get("metrics"):
                lines.append("  - llamadas/reversiones por acción: " + validate.per_action(a["metrics"]))
            if a.get("logs"):
                lines.append("  - " + " · ".join(a["logs"][:20]))
    return lines


def digest(out, last_cycles=10):
    """Lo acumulado en la PC, para pegarle a Claude al volver: líneas base, corridas de harness y fallas distintas."""
    out = Path(out)
    hist = history(out / "validate" / "history.jsonl")
    lines = ["# nexus: resumen acumulado para Claude", "",
             f"Generado {time.strftime('%Y-%m-%d %H:%M')}. Privado: pegarlo en la sesión con Claude, nunca en el repo.",
             "", "## Línea base por repo (última corrida)", "",
             "| Repo | Commit | Resultado | Compilación s | Tests s |", "|---|---|---|---|---|"]
    last = {}
    for h in hist:
        if not h.get("harness"):
            last[h["repo"]] = h
    for repo, h in sorted(last.items()):
        c = h.get("counts") or {}
        res = h.get("error") or (f"{c.get('Success')} pasan · {c.get('Failure')} fallan · {c.get('Skipped')} omitidos"
                                 if c else "no compiló")
        lines.append(f"| {repo} | {(h.get('sha') or '?')[:10]} | {str(res)[:120]} | {h.get('build_s')} | {h.get('test_s')} |")
    runs = [h for h in hist if h.get("harness")]
    lines += ["", f"## Harness: {len(runs)} corridas", ""]
    seen = {}
    for h in runs:
        c = h.get("counts") or {}
        key = (h["harness"], h.get("sha"))
        agg = seen.setdefault(key, {"runs": 0, "fail_runs": 0, "seeds": []})
        agg["runs"] += 1
        agg["fail_runs"] += bool(c.get("Failure")) or bool(h.get("error"))
        agg["seeds"].append(h.get("seed"))
    for (name, sha), a in seen.items():
        lines.append(f"- `{name}` @ {(sha or '?')[:10]}: {a['runs']} corridas, {a['fail_runs']} con fallas · "
                     f"semillas {', '.join(str(s) for s in a['seeds'][-5:])}")
    lines += coverage(out, runs)
    fails = {}
    for h in hist:
        rec = out / "validate" / f"{h.get('report')}.json" if h.get("report") else None
        if not (rec and rec.exists() and (h.get("counts") or {}).get("Failure")):
            continue
        for f in (json.loads(rec.read_text(encoding="utf-8")).get("test") or {}).get("failures", []):
            k = (h["repo"], h.get("harness"), f["suite"], f["test"], (f.get("reason") or "")[:160])
            fails.setdefault(k, {"n": 0, "seed": h.get("seed"), "sha": h.get("sha"), "report": h.get("report"),
                                 "counterexample": f.get("counterexample"), "logs": f.get("logs") or []})["n"] += 1
    lines += ["", f"## Fallas distintas: {len(fails)}", ""]
    for (repo, harness, suite, test, reason), v in list(fails.items())[:40]:
        lines += [f"### {repo} · {harness or 'línea base'} · `{suite.split(':')[-1]}::{test}` (×{v['n']})",
                  f"Motivo: {reason}", f"Commit {(v['sha'] or '?')[:10]} · semilla {v['seed']} · informe {v['report']}.md"]
        if v["counterexample"]:
            lines.append(f"Contraejemplo: `{json.dumps(v['counterexample'], ensure_ascii=False)[:2500]}`")
        if v["logs"]:
            lines += ["```", *v["logs"][:12], "```"]
    cycles = history(out / "ciclo.jsonl")[-last_cycles:]
    lines += ["", f"## Últimos {len(cycles)} ciclos", ""]
    for c in cycles:
        lines.append(f"- {time.strftime('%Y-%m-%d %H:%M', time.localtime(c['ts']))} · {c.get('minutes')} min · "
                     + " · ".join(f"{s['step']}: {'omitido' if s['ok'] is None else 'OK' if s['ok'] else 'FALLA'}"
                                  for s in c.get("steps", [])))
    return "\n".join(lines) + "\n"


class _Tee:
    """Copia la salida a ciclo.log: el Programador de tareas no la muestra en ningún lado."""

    def __init__(self, stream, path):
        self.stream, self.path = stream, Path(path)
        if self.path.exists() and self.path.stat().st_size > MAX_LOG_BYTES:
            self.path.replace(self.path.with_suffix(".log.1"))
        self.file = self.path.open("a", encoding="utf-8")

    def write(self, s):
        self.file.write(s)
        self.file.flush()
        if self.stream:
            self.stream.write(s)

    def flush(self):
        if self.stream:
            self.stream.flush()


def main(argv):
    opts = {k: v for k, v in zip(argv[0::2], argv[1::2])}
    log = results_dir(paths.home() / "secresearch")
    log.mkdir(parents=True, exist_ok=True)
    # Con pythonw (sin ventana) no hay stdout ni stderr: todo, errores incluidos, va a ciclo.log.
    sys.stdout = sys.stderr = _Tee(sys.stdout, log / "ciclo.log")
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] ciclo: inicio", flush=True)
    rep = cycle(max_minutes=float(opts.get("--max-minutes", 180)), baselines=int(opts.get("--baselines", 2)))
    print(rep["skipped"] if rep.get("skipped") else report(rep), flush=True)
    return 0 if rep.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
