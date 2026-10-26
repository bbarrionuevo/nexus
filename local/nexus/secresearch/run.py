"""Orquestador de la investigación de seguridad (sin IA, con topes, reanudable).

  python -m nexus.secresearch.run [catalogo.yaml] [OUT_DIR]        programas autorizados del catálogo
  python -m nexus.secresearch.run --demo owner/repo RUTA [OUT_DIR] demostración de las etapas A+B sobre un
                                                                   repo público (NO es un objetivo)
  python -m nexus.secresearch.run --selfcheck                      verifica que el método de invariantes
                                                                   detecta los defectos de referencia
Por defecto el catálogo y los resultados viven en NEXUS_HOME (en Windows %LOCALAPPDATA%\nexus): son
privados del dueño. El repo es PÚBLICO: un posible hallazgo publicado ahí sería divulgar una
vulnerabilidad sin reportar, así que el orquestador se niega a escribir resultados dentro del repo.

Cada corrida: (A) cambios nuevos en el código en alcance, (B) triaje determinista, informe en OUT_DIR
(secresearch.md y .json) y libro de commits ya vistos (seen.jsonl) para no repetir trabajo tras reiniciar.
Se detiene sola al agotar el tope de llamadas a la API o de tiempo. Nunca envía nada a ningún programa:
el informe es para que una persona decida qué mirar.
"""
import json
import sys
import time
from pathlib import Path

from .. import paths
from . import catalog, changes, invariants, triage
from .limits import MAX_COMMITS, MAX_NETWORK_OPS, MAX_SECONDS, results_dir

REFERENCE = {                                    # (implementación, propiedades que DEBEN fallar)
    "correcta": (lambda: invariants.Vault(), set()),
    "depósito hacia arriba": (lambda: invariants.Vault(deposit_up=True), {"P1", "P6"}),
    "retiro hacia abajo": (lambda: invariants.Vault(withdraw_up=False), {"P3", "P6"}),
    "mint hacia abajo": (lambda: invariants.Vault(mint_up=False), {"P6"}),
    "rescate hacia arriba": (lambda: invariants.Vault(redeem_up=True), {"P6"}),
    "sin shares virtuales": (lambda: invariants.Vault(virtual=False), {"P0", "P5"}),
}


def selfcheck():
    """El verificador tiene que pasar la correcta y atrapar cada defecto: si no, sus resultados no valen."""
    rows = []
    for name, (make, expected) in REFERENCE.items():
        got = {k for k, v in invariants.check(make).items() if v}
        rows.append({"variant": name, "expected": sorted(expected), "got": sorted(got), "ok": got == expected})
    return rows


def scan(targets, out_dir, get=changes._http_get, now=time.time, source="git"):
    """targets: [(etiqueta, repo, rutas)]. source: "git" (clon superficial) o "api". Escribe el informe."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    ledger = out / "seen.jsonl"
    done, budget, t0 = changes.seen(ledger), changes.Budget(MAX_NETWORK_OPS), now()
    found, notes = [], []
    for label, repo, scope in targets:
        if now() - t0 > MAX_SECONDS:
            notes.append(f"tope de tiempo alcanzado antes de {repo}")
            break
        try:
            if source == "git":
                recs, why = changes.recent_git(repo, scope, budget, done, MAX_COMMITS, out / "repos")
            else:
                recs, why = changes.recent(repo, scope, budget, done, MAX_COMMITS, get)
        except Exception as e:                                   # noqa: BLE001 (se informa y se sigue)
            notes.append(f"{repo}: {type(e).__name__}: {str(e)[:160]}")
            continue
        if why:
            notes.append(f"{repo}: {why}")
        for r in recs:
            r["label"] = label
            changes.remember(ledger, r)
        found += recs
    ranked = triage.rank(found)
    queue = out / "ranked.jsonl"                    # cola acumulada: una corrida vacía no borra lo pendiente
    with queue.open("a", encoding="utf-8") as f:
        for r in ranked:
            f.write(json.dumps(r) + "\n")
    pending = sorted((json.loads(x) for x in queue.read_text(encoding="utf-8").splitlines() if x.strip()),
                     key=lambda r: -r["score"])
    summary = {"ts": now(), "targets": len(targets), "new_commits": len(found), "files": len(ranked),
               "source": source, "network_ops": budget.used, "seconds": round(now() - t0, 1), "notes": notes,
               "by_tier": {t: sum(r["tier"] == t for r in ranked) for t in ("alta", "media", "baja")},
               "pending": len(pending)}
    (out / "secresearch.json").write_text(json.dumps({"summary": summary, "new": ranked, "pending": pending}, indent=1))
    (out / "secresearch.md").write_text(report(summary, pending, targets))
    return summary, ranked


def report(summary, ranked, targets):
    demo = any(lbl.startswith("DEMO") for lbl, _, _ in targets)
    lines = ["# Investigación de seguridad: cambios recientes en el código en alcance", ""]
    if demo:
        lines += ["> **Demostración del circuito sobre un repo público. No es un objetivo ni un hallazgo.**", ""]
    lines += [(f"Objetivos: {summary['targets']} · commits nuevos: {summary['new_commits']} · archivos: "
               f"{summary['files']} · operaciones de red ({summary['source']}): {summary['network_ops']} · "
               f"{summary['seconds']} s"), "",
              "Nuevos en esta corrida (triaje determinista, sin IA): " +
              " · ".join(f"{t} {n}" for t, n in summary["by_tier"].items()) +
              f" · pendientes de revisar en total: {summary.get('pending', len(ranked))}", "",
              "| Prioridad | Puntaje | Repo | Commit | Archivo | Señales |", "|---|---|---|---|---|---|"]
    for r in ranked[:25]:
        sig = ", ".join(f"{k} ×{v['lines']}" for k, v in r["signals"].items()) or "—"
        lines.append(f"| {r['tier']} | {r['score']} | {r['repo']} | [{r['sha'][:7]}]({r['url']}) | "
                     f"`{r['file']}` | {sig} |")
    if summary["notes"]:
        lines += ["", "Notas: " + " · ".join(summary["notes"])]
    lines += ["", ("Un puntaje alto NO es una vulnerabilidad: es un cambio que vale la pena revisar. Nada se "
                   "informa a un programa sin una prueba reproducible y la revisión del dueño.")]
    return "\n".join(lines) + "\n"


def out_dir(arg=None):
    """Carpeta de resultados: por defecto NEXUS_HOME/secresearch, nunca dentro del repo público."""
    return results_dir(arg or paths.home() / "secresearch")


def main(argv):
    if argv[:1] == ["--selfcheck"]:
        rows = selfcheck()
        for r in rows:
            print(f"{'OK ' if r['ok'] else 'MAL'} {r['variant']:24s} esperado {r['expected']} obtenido {r['got']}")
        return 0 if all(r["ok"] for r in rows) else 1
    if argv[:1] == ["--demo"]:
        repo, path = argv[1], argv[2]
        summary, _ = scan([("DEMO (no es objetivo)", repo, [path])], out_dir(argv[3] if len(argv) > 3 else None))
    else:
        progs = catalog.load(argv[0] if argv else paths.home() / "secresearch.yaml")
        ok = catalog.actionable(progs)
        for p in progs:
            if p not in ok:
                print(f"{p.get('name', '?')}: ignorado ({'; '.join(catalog.problems(p))})")
        targets = [(p["name"], r["repo"], r.get("paths") or []) for p in ok for r in p["repos"]]
        if not targets:
            print("Ningún programa habilitado: el catálogo está vacío o sin verificar (ver catalogo.ejemplo.yaml).")
            return 0
        summary, _ = scan(targets, out_dir(argv[1] if len(argv) > 1 else None))
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
