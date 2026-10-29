"""Expediente de un candidato: el documento para reclamar la recompensa, a partir de una falla de validate.

  python -m nexus.secresearch.expediente INFORME [--falla N]

INFORME es el nombre del informe de validate (el que figura en el dashboard y en history.jsonl) o la ruta a su .json.
Escribe NEXUS_HOME/secresearch/expedientes/AAAAMMDD-repo-ley.md con todo lo que el motor ya sabe (programa y sus
reglas, commit, semilla, ley que falló, contraejemplo, comando para reproducir) y las secciones que piden los
programas para pagar: causa raíz con archivo y línea, precondiciones, prueba de concepto, esperado contra
observado, impacto, severidad según su tabla, auditorías previas, corrección y límites.

Es privado (REGLAS R-4) y nadie lo envía por el dueño (R-3). Un expediente también sirve para descartar una falla
con su razón (estado: descartado): así el dashboard deja de mostrarla como pendiente.
"""
import json
import re
import sys
import time
from pathlib import Path

from .. import paths
from . import catalog
from .dashboard import failure_key
from .limits import results_dir

LAW = re.compile(r"\b(?:YV|[HVEY])-[A-Z]+(?:-\d+)?")  # H-, V-, E-, Y- y YV- (Yearn)
STATES = "borrador → confirmado → enviado → aceptado → cobrado (o descartado / rechazado)"


def _program(progs, repo):
    for p in progs:
        if any(r.get("repo") == repo for r in p.get("repos") or []):
            return p
    return {}


def _record(informe, sec):
    p = Path(informe)
    if p.suffix == ".md":
        p = p.with_suffix(".json")
    if not p.exists():
        p = sec / "validate" / f"{informe}.json"
    if not p.exists():
        raise SystemExit(f"No encuentro el informe {informe} (ni {p}).")
    return p, json.loads(p.read_text(encoding="utf-8"))


def render(rec, fail, prog, report_name, today):
    repo, sha = rec["repo"], rec.get("sha", "?")
    fuzz = rec.get("fuzz") or {}
    seed = fuzz.get("FOUNDRY_FUZZ_SEED")
    reason = fail.get("reason") or ""
    m = LAW.search(reason)
    law = m.group(0) if m else None
    suite = str(fail.get("suite", "")).split(":")[-1]
    again = (f"python -m nexus.secresearch.validate {repo} --ref {sha}"
             + (f" --harness {rec['harness']}" if rec.get("harness") else "") + (f" --seed {seed}" if seed else ""))
    key = failure_key(repo, rec.get("harness"), fail.get("suite"), fail.get("test"), reason[:300])
    platform = prog.get("platform") or "por completar"
    ce = fail.get("counterexample")
    logs = fail.get("logs") or []
    head = ["---", "estado: borrador", f"programa: {prog.get('name') or 'por completar'} ({platform})",
            f"repo: {repo}", f"commit: {sha}", "severidad: por definir", f"fecha: {today}", f"falla: {key}", "---", ""]
    body = [
        f"# Expediente: {law or 'falla'} en {repo} ({suite}::{fail.get('test')})",
        "",
        "> Borrador privado (REGLAS R-4): no se sube al repo ni se comparte. No se envía nada automáticamente "
        "(R-3): lo revisa, completa y envía el dueño por la plataforma oficial. Estados: " + STATES + ".",
        "",
        "## 1. Programa y alcance",
        "",
        f"- Programa: {prog.get('name') or 'por completar'} · plataforma: {platform}",
        f"- Reglamento vigente: {prog.get('rules_url') or 'por completar'}",
        f"- Recompensas según la página oficial: {prog.get('rewards_note') or 'por completar'}",
        f"- Requisitos de la prueba de concepto: {prog.get('poc_required') or 'por completar'}",
        f"- Exclusiones del programa: {prog.get('exclusions') or 'por completar'}",
        f"- Código: `{repo}` en el commit `{sha}`",
        "- Contratos afectados y, si el programa lo pide, sus direcciones desplegadas en alcance: **por completar**",
        "",
        "## 2. Resumen",
        "",
        "Una o dos frases: qué está mal, quién pierde y cuánto. **Por completar.**",
        "",
        "## 3. Cómo lo detectó el motor",
        "",
        f"- Harness `{rec.get('harness') or 'línea base'}`, suite `{suite}`, test `{fail.get('test')}`",
        f"- Ley que falló: `{law or 'sin código H-, V-, E- ni Y-'}`",
        f"- Motivo exacto: `{reason}`",
        f"- Semilla `{seed}` · informe `{report_name}` · {rec.get('when', '')}",
        "",
        "Reproducir en la PC, desde la carpeta `local`:",
        "",
        "```",
        again,
        "```",
        "",
    ]
    if ce:
        body += ["Contraejemplo (secuencia reducida por forge):", "", "```json",
                 json.dumps(ce, ensure_ascii=False, indent=1)[:20000], "```", ""]
    if logs:
        body += ["Logs del contraejemplo:", "", "```", *[str(x) for x in logs[:40]], "```", ""]
    body += [
        "## 4. Causa raíz",
        "",
        "- Archivo y líneas: **por completar** (`src/...sol#L..`)",
        "- Explicación: qué supuesto del código se rompe y por qué. **Por completar.**",
        "",
        "## 5. Precondiciones",
        "",
        ("Estado necesario (montos, colas, topes, tiempo), quién puede provocarlo y si hace falta un rol de confianza "
         "(curador, dueño, allocator). Si depende de un rol de confianza, decirlo: muchos programas lo excluyen. "
         "**Por completar.**"),
        "",
        "## 6. Prueba de concepto",
        "",
        ("Un test de Foundry independiente del harness: solo los contratos del repo y forge-std, en local (REGLAS R-2: "
         "nada contra contratos desplegados; un fork solo si el reglamento lo permite). Debe mostrar el efecto "
         "económico con números."),
        "",
        "```bash",
        "FOUNDRY_FFI=false forge test --match-test test_PoC -vvv",
        "```",
        "",
        "| | Esperado | Observado |",
        "|---|---|---|",
        "| por completar | | |",
        "",
        "## 7. Impacto",
        "",
        ("Quién pierde, cuánto en la prueba y en un escenario realista, si es permanente, fondos robados, congelados "
         "o rendimiento perdido. Sin exagerar (REGLAS R-7). **Por completar.**"),
        "",
        "## 8. Severidad propuesta",
        "",
        "Según la tabla del programa, citando el criterio aplicado. Si hay duda, la menor. **Por completar.**",
        "",
        "## 9. Auditorías previas y problemas conocidos",
        "",
        "- Auditorías revisadas (las del repo, p. ej. `audits/`, y las publicadas por el programa): **por completar**",
        "- Problemas conocidos e issues del repo: **por completar**",
        "- Por qué no es un duplicado ni cae en las exclusiones: **por completar**",
        "",
        "## 10. Corrección sugerida",
        "",
        "El cambio mínimo, idealmente como diff, y el test que lo verifica. **Por completar.**",
        "",
        "## 11. Límites",
        "",
        "Qué no se probó o qué supuestos usa la prueba. **Por completar.**",
        "",
        "## 12. Antes de enviar",
        "",
        "- [ ] La prueba de concepto pasa en un clon nuevo del commit indicado.",
        "- [ ] No es un duplicado de auditorías previas ni de problemas conocidos, y no cae en las exclusiones.",
        "- [ ] La severidad sigue la tabla del programa, sin exagerar.",
        "- [ ] Sin secretos ni datos personales más allá de los que pide la plataforma (REGLAS R-8).",
        "- [ ] El dueño lo envía por la plataforma oficial y anota abajo el número de envío (R-3).",
        "- [ ] El estado del encabezado está al día; solo `cobrado` cuenta como ingreso (R-10).",
        "",
        "## Seguimiento",
        "",
        "- Envío: plataforma, fecha, identificador",
        "- Respuestas del programa:",
        "- Pago:",
        "",
    ]
    return "\n".join(head + body)


def create(informe, falla=0, home=None, today=None):
    """Crea el expediente de la falla `falla` del informe y devuelve su ruta (nunca dentro del repo)."""
    base = Path(home or paths.home())
    sec = results_dir(base / "secresearch")
    path, rec = _record(informe, sec)
    fails = (rec.get("test") or {}).get("failures") or []
    if not fails:
        raise SystemExit(f"El informe {path.name} no tiene fallas.")
    if not 0 <= falla < len(fails):
        raise SystemExit(f"El informe tiene {len(fails)} fallas: --falla va de 0 a {len(fails) - 1}.")
    fail = fails[falla]
    prog = _program(catalog.load(base / "secresearch.yaml"), rec["repo"])
    today = today or time.strftime("%Y-%m-%d")
    law = LAW.search(fail.get("reason") or "")
    stem = f"{today.replace('-', '')}-{rec['repo'].replace('/', '__')}-{law.group(0) if law else 'falla'}"
    out = sec / "expedientes"
    out.mkdir(parents=True, exist_ok=True)
    dest, n = out / f"{stem}.md", 2
    while dest.exists():
        dest, n = out / f"{stem}-{n}.md", n + 1
    dest.write_text(render(rec, fail, prog, path.stem, today), encoding="utf-8")
    return dest


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    opts = {k: v for k, v in zip(argv[1::2], argv[2::2])}
    dest = create(argv[0], int(opts.get("--falla", 0)))
    print(f"Expediente: {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
