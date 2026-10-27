"""Dashboard local: una página HTML con el estado del motor, generada desde NEXUS_HOME.

  python -m nexus.secresearch.dashboard [--no-abrir]

Lee lo que ya guarda el motor en la PC (catálogo, historial de validate, informes, ciclos, cambios pendientes y
expedientes) y escribe NEXUS_HOME/secresearch/dashboard.html, que se abre en el navegador. El ciclo y validate lo
regeneran al terminar.

Es privado como el resto de los resultados (REGLAS R-4): se escribe fuera del repo y no carga nada de internet
(sin CDN ni fuentes externas). Todo el texto que viene de los informes (motivos de fallas, logs, nombres) se
escapa: sale de código de terceros.
"""
import html
import json
import sys
import time
import webbrowser
from pathlib import Path

from .. import paths
from . import catalog
from .limits import program_problems, results_dir

REVERT_ALERT = 5.0          # % de reversiones de una acción a partir del cual se marca: no explora nada
MAX_RUNS = 20               # corridas en la tabla de historial
MAX_PENDING = 15            # cambios pendientes que se listan


def action_rows(metrics):
    """[(acción, métricas)] de forge, ordenadas por acción y sin el nombre del contrato. Si dos contratos comparten
    la función (la suite de Euler llama `transfer` del token y del vault), queda `Contrato.función`: ordenar los pares
    repetidos comparaba los diccionarios y tumbaba el informe."""
    rows = [(str(k), m) for k, m in (metrics or {}).items() if isinstance(m, dict)]
    short = [k.rsplit(".", 1)[-1] for k, _ in rows]
    return sorted(((s if short.count(s) == 1 else k.rsplit(":", 1)[-1], m) for s, (k, m) in zip(short, rows)),
                  key=lambda r: r[0])


def _jsonl(path):
    p = Path(path)
    if not p.exists():
        return []
    out = []
    for line in p.read_text(encoding="utf-8").splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            continue                                   # una línea cortada (corte de luz) no tumba el dashboard
    return out


def _json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def parse_logs(logs):
    """Logs de afterInvariant ('cazador: leyes evaluadas: 9358') -> [(clave, valor)] en orden."""
    out = []
    for line in logs or []:
        k, sep, v = str(line).rpartition(": ")
        if sep:
            out.append((k.strip(), v.strip()))
    return out


def failure_key(repo, harness, suite, test, reason):
    """Identidad de una falla entre corridas (el expediente la guarda en 'falla:'): una sola línea."""
    return " ".join(f"{repo}|{harness or ''}|{suite}|{test}|{(reason or '')[:120]}".split())


def front_matter(text):
    """Encabezado 'clave: valor' entre dos líneas '---' al principio de un expediente."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    meta = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        k, sep, v = line.partition(":")
        if sep:
            meta[k.strip()] = v.strip()
    return meta


def collect(home=None):
    """Todo lo que muestra el dashboard, desde los archivos de NEXUS_HOME. Sin red."""
    base = Path(home or paths.home())
    sec = base / "secresearch"
    progs = catalog.load(base / "secresearch.yaml")
    hist = _jsonl(sec / "validate" / "history.jsonl")
    harness_runs = [h for h in hist if h.get("harness")]
    latest = {}
    for h in harness_runs:
        latest[h["harness"]] = h
    coverage = []
    for name, h in sorted(latest.items()):
        rec = _json(sec / "validate" / f"{h.get('report')}.json") if h.get("report") else None
        acts = ((rec or {}).get("test") or {}).get("activity") or []
        coverage.append({"harness": name, "seed": h.get("seed"), "sha": h.get("sha"), "ts": h.get("ts"),
                         "report": h.get("report"), "activity": acts})
    expedientes = []
    edir = sec / "expedientes"
    if edir.is_dir():
        for p in sorted(edir.glob("*.md")):
            meta = front_matter(p.read_text(encoding="utf-8"))
            expedientes.append({"file": p.name, **meta})
    by_failure = {e.get("falla") for e in expedientes if e.get("falla")}
    fails = {}
    for h in hist:
        if not (h.get("counts") or {}).get("Failure") or not h.get("report"):
            continue
        rec = _json(sec / "validate" / f"{h['report']}.json") or {}
        for f in (rec.get("test") or {}).get("failures", []):
            reason = (f.get("reason") or "")[:300]
            key = failure_key(h["repo"], h.get("harness"), f.get("suite"), f.get("test"), reason)
            cur = fails.setdefault(key, {"repo": h["repo"], "harness": h.get("harness"), "suite": f.get("suite"),
                                         "test": f.get("test"), "reason": reason, "n": 0, "seed": h.get("seed"),
                                         "sha": h.get("sha"), "report": h.get("report"), "ts": h.get("ts")})
            cur["n"] += 1
    for k, f in fails.items():
        f["key"] = k
        f["expediente"] = k in by_failure
    pending = (_json(sec / "secresearch.json") or {}).get("pending") or []
    return {"generated": time.time(), "home": str(base), "programs": progs, "history": hist,
            "harness_runs": harness_runs, "coverage": coverage, "failures": list(fails.values()),
            "expedientes": expedientes, "cycles": _jsonl(sec / "ciclo.jsonl"), "pending": pending}


# --------------------------------------------------------------------------------------------- formato


def esc(x):
    return html.escape("" if x is None else str(x), quote=True)


def num(n):
    """1234567 -> '1.234.567' (como se escribe en castellano)."""
    try:
        return f"{int(n):,}".replace(",", ".")
    except (TypeError, ValueError):
        return esc(n)


def compact(n):
    """Montos del cazador (wei): enteros chicos tal cual; los enormes en notación científica corta."""
    try:
        v = int(str(n))
    except ValueError:
        return esc(n)
    return num(v) if v < 10 ** 9 else f"{v:.2e}".replace(".", ",").replace("e+", "e")


def pct(part, total):
    return 100.0 * part / total if total else 0.0


def fmt_pct(p):
    return f"{p:.1f}".replace(".", ",") + " %"


def when(ts):
    return time.strftime("%d-%m %H:%M", time.localtime(ts)) if ts else "—"


def chip(state, label):
    """Estado con ícono y texto: el color nunca va solo."""
    icon = {"good": "✓", "critical": "✕", "warning": "!", "neutral": "–"}[state]
    return f'<span class="chip {state}"><span class="dot" aria-hidden="true">{icon}</span>{esc(label)}</span>'


def run_state(h):
    c = h.get("counts") or {}
    if h.get("error"):
        return chip("critical", "error")
    if not c:
        return chip("critical", "no compiló")
    n = c.get("Failure")
    return chip("critical", f"{n} falla" if n == 1 else f"{n} fallan") if n else chip("good", "pasan todos")


# --------------------------------------------------------------------------------------------- secciones


def _tiles(d):
    progs = d["programs"]
    active = [p for p in progs if not program_problems(p)]
    open_fails = [f for f in d["failures"] if not f["expediente"]]
    calls = sum(a.get("calls") or 0 for c in d["coverage"] for a in c["activity"])
    last = d["cycles"][-1] if d["cycles"] else None
    hero_state = "critical" if open_fails else "good"
    hero_label = ("falla para revisar" if len(open_fails) == 1 else "fallas para revisar") if open_fails else \
        "sin fallas abiertas"
    tiles = [
        ("Programas activos", f"{len(active)} de {len(progs)}", "con alcance y reglamento verificados"),
        ("Corridas de harness", num(len(d["harness_runs"])), f"{num(len(d['history']))} validaciones en total"),
        ("Llamadas en la última corrida", num(calls), "suma de las suites de invariantes"),
        ("Expedientes", num(len(d["expedientes"])), "candidatos documentados"),
        ("Cambios para revisar", num(len(d["pending"])), "commits en alcance, por prioridad"),
        ("Último ciclo", when(last["ts"]) if last else "—",
         ("sin fallas" if last.get("ok") else "con fallas") if last else "todavía no corrió"),
    ]
    out = ['<section class="status">',
           (f'<div class="hero"><div class="hero-num">{len(open_fails)}</div>'
            f'<div class="hero-label">{chip(hero_state, hero_label)}</div>'
            '<p class="note">Una falla no es una vulnerabilidad: es algo para reproducir con la semilla y '
            'clasificar. Solo cuenta un efecto económico reproducible, revisado contra auditorías previas.</p></div>'),
           '<div class="tiles">']
    for label, value, sub in tiles:
        out.append(f'<div class="tile"><div class="t-label">{esc(label)}</div><div class="t-value">{esc(value)}'
                   f'</div><div class="t-sub">{esc(sub)}</div></div>')
    out += ["</div></section>"]
    return "\n".join(out)


def _programs(d):
    rows = []
    for p in d["programs"]:
        probs = program_problems(p)
        state = chip("good", "activo") if not probs else chip("warning", "inactivo")
        url = str(p.get("rules_url") or "")
        link = f'<a href="{esc(url)}" rel="noreferrer">reglamento</a>' if url.startswith("https://") else "—"
        repos = ", ".join(esc(r.get("repo")) for r in p.get("repos") or [])
        rows.append(f"<tr><td>{esc(p.get('name'))}</td><td>{esc(p.get('platform'))}</td><td>{state}</td>"
                    f"<td>{repos}</td><td>{link}</td><td class='muted'>{esc('; '.join(probs))}</td></tr>")
    if not rows:
        return _empty("Programas", "El catálogo está vacío: se carga en %LOCALAPPDATA%\\nexus\\secresearch.yaml.")
    return (_section("Programas", "<table><thead><tr><th>Programa</th><th>Plataforma</th><th>Estado</th><th>Repos</th>"
                     "<th>Reglas</th><th>Qué falta</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>"))


def _runs(d):
    rows = []
    for h in reversed(d["history"][-MAX_RUNS:]):
        c = h.get("counts") or {}
        link = f'<a href="validate/{esc(h.get("report"))}.md">informe</a>' if h.get("report") else "—"
        rows.append(f"<tr><td>{esc(when(h.get('ts')))}</td><td>{esc(h.get('repo'))}</td>"
                    f"<td>{esc(h.get('harness') or 'línea base')}</td><td class='mono'>{esc(h.get('seed') or '—')}</td>"
                    f"<td>{run_state(h)}</td><td class='num'>{num(c.get('Success', 0))}</td>"
                    f"<td class='num'>{esc(h.get('build_s'))}</td><td class='num'>{esc(h.get('test_s'))}</td>"
                    f"<td>{link}</td></tr>")
    if not rows:
        return _empty("Corridas", "Todavía no hay corridas de validate.")
    return _section("Últimas corridas", "<table><thead><tr><th>Fecha</th><th>Repo</th><th>Harness</th><th>Semilla</th>"
                    "<th>Resultado</th><th class='num'>Pasan</th><th class='num'>Compilación s</th>"
                    "<th class='num'>Tests s</th><th></th></tr></thead>"
                    "<tbody>" + "".join(rows) + "</tbody></table>")


def bars(rows, title):
    """Barras horizontales de % de reversiones por acción (forma de énfasis): en el acento las que pasan el umbral,
    en gris el resto. Cada barra tiene su tooltip y la tabla de abajo trae los mismos números."""
    rows = sorted(rows, key=lambda r: -r[1])
    if not rows:
        return ""
    w, lab, bh, gap = 560, 150, 14, 8
    top = max(max(r[1] for r in rows), REVERT_ALERT * 1.2)
    plot = w - lab - 70
    h = len(rows) * (bh + gap) + 24
    x_alert = lab + plot * REVERT_ALERT / top
    parts = [f'<svg class="bars" viewBox="0 0 {w} {h}" role="img" aria-label="{esc(title)}">',
             f'<line class="grid" x1="{x_alert:.1f}" x2="{x_alert:.1f}" y1="0" y2="{h - 18}"/>',
             f'<text class="axis" x="{x_alert:.1f}" y="{h - 4}" text-anchor="middle">{fmt_pct(REVERT_ALERT)}</text>',
             f'<line class="base" x1="{lab}" x2="{lab}" y1="0" y2="{h - 18}"/>']
    for i, (name, p, calls, reverts) in enumerate(rows):
        y = i * (bh + gap) + 4
        bw = max(plot * p / top, 1.5)
        r = min(4, bw / 2)
        cls = "mark alert" if p >= REVERT_ALERT else "mark"
        path = (f"M{lab},{y} h{bw - r:.1f} a{r},{r} 0 0 1 {r},{r} v{bh - 2 * r} a{r},{r} 0 0 1 -{r},{r} "
                f"h-{bw - r:.1f} z")
        tip = f"{name}: {num(reverts)} de {num(calls)} llamadas revierten ({fmt_pct(p)})"
        parts.append(f'<g class="hit" tabindex="0" data-tip="{esc(tip)}"><title>{esc(tip)}</title>'
                     f'<rect x="0" y="{y - gap / 2}" width="{w}" height="{bh + gap}" fill="transparent"/>'
                     f'<text class="label" x="{lab - 8}" y="{y + bh - 3}" text-anchor="end">{esc(name)}</text>'
                     f'<path class="{cls}" d="{path}"/>'
                     f'<text class="value" x="{lab + bw + 6:.1f}" y="{y + bh - 3}">{fmt_pct(p)}</text></g>')
    parts.append("</svg>")
    return "".join(parts)


def _coverage(d):
    if not d["coverage"]:
        return _empty("Cobertura", "Todavía no hay corridas de harness.")
    out = []
    for c in d["coverage"]:
        out.append(f"<h3>{esc(c['harness'])} <span class='muted'>· semilla <span class='mono'>{esc(c['seed'])}</span>"
                   f" · {esc((c.get('sha') or '?')[:10])} · {esc(when(c.get('ts')))}</span></h3>")
        if not c["activity"]:
            out.append("<p class='muted'>El informe de esta corrida no trae actividad de invariantes.</p>")
        for a in c["activity"]:
            suite = str(a.get("suite", "")).split(":")[-1]
            calls, reverts = a.get("calls") or 0, a.get("reverts") or 0
            metrics = a.get("metrics") or {}
            rows = [(n, pct(m.get("reverts", 0), m.get("calls", 0)), m.get("calls", 0), m.get("reverts", 0))
                    for n, m in action_rows(metrics)]
            kv = parse_logs(a.get("logs"))
            alerts = [r for r in rows if r[1] >= REVERT_ALERT]
            many = "acción" if len(alerts) == 1 else "acciones"
            state = chip("warning", f"{len(alerts)} {many} sobre {fmt_pct(REVERT_ALERT)}") if alerts else \
                chip("good", "reversiones bajo control")
            out.append(f"<div class='card'><div class='card-head'><strong>{esc(suite)}::{esc(a.get('test'))}</strong>"
                       f"<span>{state}</span></div>"
                       f"<p class='muted'>{num(a.get('runs'))} corridas · {num(calls)} llamadas · {num(reverts)} "
                       f"reversiones ({fmt_pct(pct(reverts, calls))})</p>")
            if rows:
                out.append("<h4>Reversiones por acción</h4>" + bars(rows, f"Reversiones por acción en {suite}"))
                body = "".join(f"<tr><td>{esc(n)}</td><td class='num'>{num(cl)}</td><td class='num'>{num(rv)}</td>"
                               f"<td class='num'>{fmt_pct(p)}</td></tr>" for n, p, cl, rv in sorted(rows))
                out.append("<details><summary>Ver la tabla</summary><table><thead><tr><th>Acción</th><th class='num'>"
                           "Llamadas</th><th class='num'>Reversiones</th><th class='num'>%</th></tr></thead><tbody>"
                           + body + "</tbody></table>"
                           "</details>")
            if kv:
                body = "".join(f"<tr><td>{esc(k)}</td><td class='num'>{compact(v) if v.isdigit() else esc(v)}</td></tr>"
                               for k, v in kv)
                out.append("<h4>Métricas de la última corrida (afterInvariant)</h4><table class='kv'><tbody>" + body +
                           "</tbody></table>")
            out.append("</div>")
    return _section("Cobertura de la última corrida de cada harness", "\n".join(out),
                    "Cómo leer cada métrica: docs/CAZADOR_METAMORPHO.md, sección 6.")


def _failures(d):
    if not d["failures"]:
        return _section("Fallas para revisar", "<p>" + chip("good", "Ninguna") + "</p>")
    items = []
    for f in sorted(d["failures"], key=lambda f: (f["expediente"], -(f.get("ts") or 0))):
        state = chip("neutral", "con expediente") if f["expediente"] else chip("critical", "sin clasificar")
        again = (f"python -m nexus.secresearch.validate {f['repo']} --ref {f.get('sha')}"
                 + (f" --harness {f['harness']}" if f.get("harness") else "") + f" --seed {f.get('seed')}")
        new = f"python -m nexus.secresearch.expediente {f.get('report')}"
        items.append(f"<div class='card'><div class='card-head'><strong>{esc(f['repo'])} · "
                     f"{esc(str(f.get('suite', '')).split(':')[-1])}::{esc(f.get('test'))}</strong>{state}</div>"
                     f"<p class='reason'>{esc(f['reason'])}</p>"
                     f"<p class='muted'>×{f['n']} · commit {esc((f.get('sha') or '?')[:10])} · semilla "
                     f"<span class='mono'>{esc(f.get('seed'))}</span> · "
                     f"<a href='validate/{esc(f.get('report'))}.md'>informe</a></p>"
                     f"<p class='muted'>Reproducir:</p><pre>{esc(again)}</pre>"
                     f"<p class='muted'>Si se confirma, abrir el expediente:</p><pre>{esc(new)}</pre></div>")
    return _section("Fallas para revisar", "\n".join(items))


def _expedientes(d):
    if not d["expedientes"]:
        return _section("Expedientes", "<p class='muted'>Ninguno. Se abren con "
                        "<code>python -m nexus.secresearch.expediente &lt;informe&gt;</code> cuando una falla se "
                        "confirma como candidato.</p>")
    states = {"borrador": "warning", "confirmado": "warning", "enviado": "neutral", "aceptado": "good",
              "cobrado": "good", "descartado": "neutral", "rechazado": "critical"}
    rows = "".join(f"<tr><td><a href='expedientes/{esc(e['file'])}'>{esc(e['file'])}</a></td>"
                   f"<td>{chip(states.get(e.get('estado', ''), 'neutral'), e.get('estado') or 'sin estado')}</td>"
                   f"<td>{esc(e.get('programa'))}</td><td>{esc(e.get('severidad'))}</td><td>{esc(e.get('fecha'))}</td>"
                   f"</tr>" for e in d["expedientes"])
    return _section("Expedientes", "<table><thead><tr><th>Archivo</th><th>Estado</th><th>Programa</th><th>Severidad</th>"
                    "<th>Fecha</th></tr></thead><tbody>" + rows + "</tbody></table>",
                    "Solo cuenta como ingreso una recompensa cobrada (REGLAS R-10).")


def _pending(d):
    if not d["pending"]:
        return _section("Cambios para revisar", "<p class='muted'>No hay commits pendientes.</p>")
    rows = []
    for r in d["pending"][:MAX_PENDING]:
        url = str(r.get("url") or "")
        sha = esc(str(r.get("sha") or "")[:7])
        commit = f'<a href="{esc(url)}" rel="noreferrer">{sha}</a>' if url.startswith("https://") else sha
        sig = ", ".join(f"{esc(k)} ×{esc(v.get('lines'))}" for k, v in (r.get("signals") or {}).items()) or "—"
        rows.append(f"<tr><td>{esc(r.get('tier'))}</td><td class='num'>{esc(r.get('score'))}</td><td>{esc(r.get('repo'))}"
                    f"</td><td class='mono'>{commit}</td><td class='mono'>{esc(r.get('file'))}</td><td>{sig}</td></tr>")
    return _section(f"Cambios para revisar ({num(len(d['pending']))})",
                    "<table><thead><tr><th>Prioridad</th><th class='num'>Puntaje</th><th>Repo</th><th>Commit</th><th>Archivo</th>"
                    "<th>Señales</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>",
                    "Un puntaje alto no es una vulnerabilidad: es un cambio que vale la pena leer.")


def _cycles(d):
    if not d["cycles"]:
        return _empty("Ciclos", "El ciclo programado (nexus-ciclo) todavía no corrió.")
    rows = []
    for c in reversed(d["cycles"][-10:]):
        steps = " ".join(chip("neutral" if s.get("ok") is None else "good" if s.get("ok") else "critical",
                              s.get("step")) for s in c.get("steps") or [])
        rows.append(f"<tr><td>{esc(when(c.get('ts')))}</td><td class='num'>{esc(c.get('minutes'))}</td>"
                    f"<td>{steps or esc(c.get('skipped'))}</td></tr>")
    return _section("Últimos ciclos", "<table><thead><tr><th>Fecha</th><th class='num'>Minutos</th><th>Pasos</th></tr></thead>"
                    "<tbody>" + "".join(rows) + "</tbody></table>")


def _section(title, body, note=""):
    note = f"<p class='note'>{esc(note)}</p>" if note else ""
    return f"<section><h2>{esc(title)}</h2>{note}{body}</section>"


def _empty(title, text):
    return _section(title, f"<p class='muted'>{esc(text)}</p>")


CSS = """
:root{color-scheme:light;--page:#f9f9f7;--surface:#fcfcfb;--ink:#0b0b0b;--ink2:#52514e;--muted:#6f6e69;
--grid:#e1e0d9;--base:#c3c2b7;--ring:rgba(11,11,11,.10);--accent:#2a78d6;--quiet:#8f8e88;
--good:#0ca30c;--warning:#fab219;--critical:#d03b3b;--neutral:#898781}
@media (prefers-color-scheme:dark){:root:where(:not([data-theme="light"])){color-scheme:dark;--page:#0d0d0d;
--surface:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;--muted:#a5a49c;--grid:#2c2c2a;--base:#383835;
--ring:rgba(255,255,255,.10);--accent:#3987e5;--quiet:#6b6a65}}
:root[data-theme="dark"]{color-scheme:dark;--page:#0d0d0d;--surface:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;
--muted:#a5a49c;--grid:#2c2c2a;--base:#383835;--ring:rgba(255,255,255,.10);--accent:#3987e5;--quiet:#6b6a65}
*{box-sizing:border-box}
body{margin:0;background:var(--page);color:var(--ink);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 64px}
header{display:flex;flex-wrap:wrap;align-items:baseline;justify-content:space-between;gap:8px}
h1{font-size:22px;margin:0}h2{font-size:18px;margin:0 0 12px}h3{font-size:16px;margin:20px 0 8px}
h4{font-size:13px;margin:14px 0 6px;color:var(--ink2);font-weight:600}
section{background:var(--surface);border:1px solid var(--ring);border-radius:10px;padding:18px;margin-top:16px}
.status{display:grid;grid-template-columns:minmax(220px,1fr) 3fr;gap:16px}
@media (max-width:760px){.status{grid-template-columns:1fr}}
.hero-num{font-size:56px;font-weight:600;line-height:1}.hero-label{margin:8px 0}
.tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:10px}
.tile{border:1px solid var(--ring);border-radius:8px;padding:10px 12px}
.t-label{color:var(--ink2);font-size:13px}.t-value{font-size:22px;font-weight:600;margin:2px 0}
.t-sub{color:var(--muted);font-size:12px}
.note,.muted{color:var(--muted)}.note{font-size:13px;margin:0 0 10px}
.tw{overflow-x:auto;max-width:100%}table{border-collapse:collapse;width:100%;font-size:13px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--grid);vertical-align:top}
th{color:var(--ink2);font-weight:600}td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
.kv td:first-child{color:var(--ink2)}
.mono,pre,code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12px}
pre{background:var(--page);border:1px solid var(--grid);border-radius:6px;padding:8px;overflow-x:auto;
white-space:pre-wrap;word-break:break-all}
.chip{display:inline-flex;align-items:center;gap:6px;margin:2px 6px 2px 0;white-space:nowrap;color:var(--ink)}
.chip .dot{display:inline-grid;place-items:center;width:16px;height:16px;border-radius:50%;font-size:11px;
font-weight:700;color:#fff}
.chip.good .dot{background:var(--good)}.chip.critical .dot{background:var(--critical)}
.chip.warning .dot{background:var(--warning);color:#0b0b0b}.chip.neutral .dot{background:var(--neutral)}
.card{border:1px solid var(--ring);border-radius:8px;padding:12px;margin:10px 0}
.card-head{display:flex;flex-wrap:wrap;justify-content:space-between;gap:8px}
.card-head strong,h3{overflow-wrap:anywhere;min-width:0}
.reason{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12px;word-break:break-word}
svg.bars{width:100%;max-width:640px;height:auto;display:block}
svg .mark{fill:var(--quiet)}svg .mark.alert{fill:var(--accent)}
svg .label,svg .axis{fill:var(--muted);font-size:11px}svg .value{fill:var(--ink);font-size:11px}
svg .grid{stroke:var(--grid);stroke-width:1}svg .base{stroke:var(--base);stroke-width:1}
svg .hit:hover .mark,svg .hit:focus .mark{opacity:.8}svg .hit:focus{outline:none}
details{margin-top:6px}summary{cursor:pointer;color:var(--ink2);font-size:13px}
a{color:var(--accent)}
#tip{position:fixed;pointer-events:none;background:var(--surface);color:var(--ink);border:1px solid var(--ring);
border-radius:6px;padding:6px 8px;font-size:12px;box-shadow:0 2px 8px rgba(0,0,0,.15);display:none;max-width:320px}
.theme{background:none;border:1px solid var(--ring);color:var(--ink2);border-radius:6px;padding:4px 10px;cursor:pointer}
"""

JS = """
(function(){
  var tip=document.getElementById('tip');
  function show(e){var t=e.currentTarget.getAttribute('data-tip');if(!t)return;tip.textContent=t;
    tip.style.display='block';var r=e.currentTarget.getBoundingClientRect();
    var x=(e.clientX||r.left+r.width/2)+12,y=(e.clientY||r.top)+12;
    tip.style.left=Math.min(x,window.innerWidth-330)+'px';tip.style.top=y+'px';}
  function hide(){tip.style.display='none';}
  document.querySelectorAll('[data-tip]').forEach(function(g){g.addEventListener('pointermove',show);
    g.addEventListener('focus',show);g.addEventListener('pointerleave',hide);g.addEventListener('blur',hide);});
  var b=document.getElementById('theme');var root=document.documentElement;
  try{var s=localStorage.getItem('nexus-theme');if(s)root.setAttribute('data-theme',s);}catch(e){}
  b.addEventListener('click',function(){var dark=root.getAttribute('data-theme')==='dark'||
    (!root.getAttribute('data-theme')&&matchMedia('(prefers-color-scheme: dark)').matches);
    var n=dark?'light':'dark';root.setAttribute('data-theme',n);try{localStorage.setItem('nexus-theme',n);}catch(e){}});
})();
"""


def render(d):
    body = [_tiles(d), _failures(d), _coverage(d), _runs(d), _expedientes(d), _programs(d), _pending(d), _cycles(d)]
    body = [b.replace("<table", "<div class='tw'><table").replace("</table>", "</table></div>") for b in body]
    gen = time.strftime("%Y-%m-%d %H:%M", time.localtime(d["generated"]))
    return ("<!doctype html><html lang='es'><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'; "
            "script-src 'unsafe-inline'; img-src data:\">"
            f"<title>Nexus · investigación</title><style>{CSS}</style></head><body><main>"
            f"<header><h1>Nexus · investigación de seguridad</h1><div class='muted'>Generado {esc(gen)} · "
            f"privado, en esta PC · <button id='theme' class='theme' type='button'>Tema</button></div></header>"
            + "\n".join(body) +
            f"</main><div id='tip' role='status'></div><script>{JS}</script></body></html>")


def write(home=None, open_browser=False):
    """Genera el dashboard en NEXUS_HOME/secresearch/dashboard.html (nunca dentro del repo) y lo devuelve."""
    base = Path(home or paths.home())
    out = results_dir(base / "secresearch")
    out.mkdir(parents=True, exist_ok=True)
    path = out / "dashboard.html"
    path.write_text(render(collect(base)), encoding="utf-8")
    if open_browser:
        webbrowser.open(path.resolve().as_uri())
    return path


def main(argv):
    path = write(open_browser="--no-abrir" not in argv)
    print(f"Dashboard: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
