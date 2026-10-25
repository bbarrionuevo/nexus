"""Supervisión determinista (sin IA): vigilante horario e informe diario, publicados como issues.

GitHub envía mail al dueño del repo por cada comentario del bot en un issue asignado a él.
  python -m nexus.monitor watchdog PC_STATUS.json      -> issue "nexus: alertas"
  python -m nexus.monitor digest PC_STATUS.json DATA_DIR -> issue "nexus: informe diario"
Variables: GITHUB_TOKEN, GITHUB_REPOSITORY, NEXUS_OWNER (usuario a asignar).
"""
import json
import os
import sys
import time
from pathlib import Path

ALERT_TITLE = "nexus: alertas"
DIGEST_TITLE = "nexus: informe diario"


# ------------------------------------------------------------------ lógica pura (testeable)
def alerts(pc, now=None, ci_conclusion=None):
    """Lista de alertas a partir del latido del PC. pc=None significa que nunca reportó."""
    now = now or time.time()
    a = []
    if ci_conclusion and ci_conclusion != "success":
        a.append(f"El CI de main está en '{ci_conclusion}': el PC no instalará versiones nuevas.")
    if not pc:
        return a + ["El PC todavía no publicó ningún latido (¿instalación pendiente o sin credenciales de git?)."]
    age_h = (now - pc.get("ts", 0)) / 3600
    if age_h > 2:
        a.append(f"El PC no reporta hace {age_h:.1f} h (¿apagado, sin internet o tarea detenida?).")
    st = pc.get("status") or {}
    if st and pc.get("ts", 0) - st.get("ts", 0) > 600:
        a.append("El agente no actualiza su estado hace más de 10 min (¿detenido o colgado?).")
    if not st:
        a.append("El agente nunca escribió su estado.")
    risk = st.get("risk") or {}
    if risk.get("sticky_halt"):
        a.append(f"HALT PERMANENTE: {risk['sticky_halt']}. Requiere tu revisión y rearme manual.")
    if st.get("errors_last_hour", 0) > 120:
        a.append(f"{st['errors_last_hour']} errores de datos en la última hora.")
    up = pc.get("update") or {}
    if str(up.get("result", "")).startswith("rollback"):
        a.append(f"Actualización revertida: {up['result']} (candidata {up.get('candidate')}).")
    for r in up.get("reasons", []):
        if "rutas protegidas" in r:
            a.append(f"Versión {up.get('candidate')} espera TU aprobación en el PC: {r}")
    if pc.get("kill_switch"):
        a.append("Interruptor de emergencia ACTIVO (no se abren posiciones).")
    return a


def digest(pc, research_md=None, now=None):
    now = now or time.time()
    L = [f"## Informe {time.strftime('%Y-%m-%d', time.gmtime(now))} (UTC)", ""]
    st = (pc or {}).get("status") or {}
    if not st:
        L.append("**PC:** sin datos del agente todavía.")
    else:
        risk = st.get("risk", {})
        L += [f"**Agente** versión `{st.get('version')}` · modo **{st.get('mode')}** · comisiones maker/taker "
              f"{st.get('fees')} · errores/h {st.get('errors_last_hour')}",
              f"**Riesgo:** PnL hoy {risk.get('pnl_day', 0):+.2f} € · semana {risk.get('pnl_week', 0):+.2f} € · "
              f"acumulado {risk.get('pnl_total', 0):+.2f} € · stops seguidos {risk.get('stops_row', 0)} · "
              f"halt: {risk.get('sticky_halt') or 'no'} · bloqueo actual: {st.get('risk_block') or 'ninguno'}", "",
              "| par | estado | PnL € (incl. abierta) | realizado € | vueltas | ganadoras | stops | timeouts |",
              "|---|---|---|---|---|---|---|---|"]
        for b in st.get("books", []):
            L.append(f"| {b['sym']} | {b['state']} | {b['pnl_eur']:+.4f} | {b.get('realized_eur', 0):+.4f} | "
                     f"{b['roundtrips']} | {b['wins']} | {b['stops']} | {b.get('timeouts', 0)} |")
        ev = st.get("evidence") or {}
        if ev.get("criteria"):
            L += ["", f"### Criterios para pasar a dinero real: {ev['criteria_met']}/{ev['criteria_total']}",
                  "| criterio | estado | detalle |", "|---|---|---|"]
            L += [f"| {c['name']} | {'✅' if c['ok'] else '⏳'} | {c['detail']} |" for c in ev["criteria"]]
        kinds = ev.get("by_kind") or {}
        if kinds:
            names = {"maker": "venta con ganancia (maker)", "stop": "stop", "timeout": "tiempo máximo"}
            L += ["", "**De dónde sale el resultado:** " + " · ".join(
                f"{names.get(k, k)} {v['n']} vueltas {v['total']:+.2f} €" for k, v in kinds.items())]
            if ev.get("excluded_old_model"):
                L.append(f"(Excluidas {ev['excluded_old_model']} vueltas del modelo de llenado anterior, con sesgo.)")
            prev = ev.get("previous") or {}
            if ev.get("strategy"):
                L.append(f"Estrategia vigente: **{ev['strategy']}** (los criterios se miden solo con ella). "
                         f"Versiones anteriores: {prev.get('n', 0)} vueltas, {prev.get('total', 0):+.2f} €.")
        per = ev.get("per_symbol") or {}
        if per:
            rows = sorted(per.items(), key=lambda kv: (kv[1].get("n", 0) >= 30, kv[1].get("mean") or -9),
                          reverse=True)[:12]
            L += ["", "### Pares (operados y laboratorio) — vueltas cerradas en paper",
                  "| par | tipo | vueltas | total € | media € | IC95 desde | ganadoras |", "|---|---|---|---|---|---|---|"]
            for sym, x in rows:
                L.append(f"| {sym} | {'lab' if x.get('lab') else 'operado'} | {x.get('n')} | {x.get('total')} | "
                         f"{x.get('mean')} | {x.get('ci95_low')} | {x.get('win_rate')} |")
            best_lab = [k for k, x in rows if x.get("lab") and x.get("n", 0) >= 30 and (x.get("ci95_low") or -1) > 0]
            if best_lab:
                L.append(f"\n**Candidatos del laboratorio con evidencia positiva:** {', '.join(best_lab)}")
        lab = st.get("lab") or []
        if lab:
            L.append(f"\nLaboratorio activo: {', '.join(b['sym'] for b in lab)}")
        L += ["", "Nivel de evidencia: **paper** (simulado con datos reales). Criterios aprobados el 24-oct: "
                  "≥7 días, ≥300 vueltas, IC95% > 0, ≥5/7 días positivos, robustez a +0,02% de comisión y "
                  "+200 ms; luego 20 € reales una semana antes de los 100 €."]
    up = (pc or {}).get("update") or {}
    if up:
        L += ["", f"**Actualización:** {up.get('result')} {up.get('version') or up.get('candidate') or ''} "
                  f"{'· ' + '; '.join(up.get('reasons', [])) if up.get('reasons') else ''}"]
    if research_md:
        L += ["", "<details><summary>Radar de oportunidades e investigación automática</summary>", "", research_md,
              "</details>"]
    return "\n".join(L)


# ------------------------------------------------------------------ GitHub (efectos)
class Issues:
    def __init__(self):
        import requests
        self.r = requests.Session()
        self.r.headers.update({"Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
                               "Accept": "application/vnd.github+json"})
        self.base = f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}"
        self.owner = os.environ.get("NEXUS_OWNER")

    def find(self, title):
        for state in ("open", "closed"):
            for i in self.r.get(f"{self.base}/issues", params={"state": state, "per_page": 100}).json():
                if i.get("title") == title and "pull_request" not in i:
                    return i
        return None

    def ensure(self, title, body):
        i = self.find(title)
        if not i:
            data = {"title": title, "body": body}
            if self.owner:
                data["assignees"] = [self.owner]
            i = self.r.post(f"{self.base}/issues", json=data).json()
        return i

    def last_comment(self, number):
        c = self.r.get(f"{self.base}/issues/{number}/comments", params={"per_page": 100}).json()
        return c[-1]["body"] if c else ""

    def commented_on(self, number, day):
        """True si el issue ya tiene un comentario del día `day` (AAAA-MM-DD, UTC)."""
        c = self.r.get(f"{self.base}/issues/{number}/comments", params={"per_page": 100}).json()
        return any(str(x.get("created_at", "")).startswith(day) for x in c)

    def comment(self, number, body):
        self.r.post(f"{self.base}/issues/{number}/comments", json={"body": body})

    def set_state(self, number, state):
        self.r.patch(f"{self.base}/issues/{number}", json={"state": state})


def _load(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        return None


def run_watchdog(pc_path, ci_conclusion=None):
    found = alerts(_load(pc_path), ci_conclusion=ci_conclusion)
    gh = Issues()
    if not found and not gh.find(ALERT_TITLE):
        print("Todo en orden (sin issue de alertas).")
        return
    issue = gh.ensure(ALERT_TITLE, "Alertas automáticas del vigilante de nexus. Se cierra solo cuando todo está bien.")
    body = "### Alertas activas\n" + "\n".join(f"- {x}" for x in found) if found else "Todo en orden: alertas resueltas."
    if body != gh.last_comment(issue["number"]):
        if found or issue["state"] == "open":
            gh.comment(issue["number"], body)
    gh.set_state(issue["number"], "open" if found else "closed")
    print(body)


def run_digest(pc_path, research_path=None, once_per_day=False):
    """Publica el informe. once_per_day (corridas programadas): si ya hay uno de hoy, no repite; así
    puede haber una hora de respaldo por si GitHub saltea la primera (pasó el 25-oct)."""
    research = Path(research_path).read_text(encoding="utf-8") if research_path and Path(research_path).exists() else None
    text = digest(_load(pc_path), research)
    gh = Issues()
    issue = gh.ensure(DIGEST_TITLE, "Informe diario automático de nexus (un comentario por día).")
    import time as _t
    if once_per_day and gh.commented_on(issue["number"], _t.strftime("%Y-%m-%d", _t.gmtime())):
        print("Ya hay informe de hoy: no se repite.")
        return
    gh.comment(issue["number"], text)
    print(text)


if __name__ == "__main__":
    if sys.argv[1] == "watchdog":
        run_watchdog(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    elif sys.argv[1] == "digest":
        run_digest(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None,
                   once_per_day=os.environ.get("NEXUS_DIGEST_ONCE") == "1")
