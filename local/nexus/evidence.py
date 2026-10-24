"""Evidencia para pasar a dinero real (R-15, criterios aprobados por el dueño el 24-oct-2026).

Lee el diario de vueltas cerradas en paper y calcula, para el total y por par:
  C1 duración ≥ 7 días · C2 ≥ 300 vueltas · C3 IC95% de la ganancia media > 0
  C4 positivo en ≥ 5 de los últimos 7 días · C5 sigue > 0 con +0,02% de comisión por lado
  C6 robustez a +200 ms de latencia (pendiente de medir: se informa como no cumplido)
Nivel de evidencia: paper (simulado con datos reales). La decisión de pasar a real es siempre del dueño.
"""
import json
import math
import time
from collections import defaultdict
from pathlib import Path

MIN_DAYS, MIN_TRADES, MIN_POS_DAYS, EXTRA_FEE_PCT = 7, 300, 5, 0.02
# Versión del modelo de llenado. 2 = ya no se llenan órdenes con operaciones previas a la orden
# (defecto 3, 24-oct-2026). Las vueltas de modelos anteriores quedan en el diario pero no cuentan.
FILL_MODEL = 2


def load(path, since=None, min_model=FILL_MODEL):
    p = Path(path)
    if not p.exists():
        return []
    out = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            t = json.loads(line)
        except ValueError:
            continue
        if (since is None or t.get("ts", 0) >= since) and t.get("model", 1) >= min_model:
            out.append(t)
    return out


def stats(pnls):
    n = len(pnls)
    if n == 0:
        return {"n": 0}
    mean = sum(pnls) / n
    var = sum((x - mean) ** 2 for x in pnls) / (n - 1) if n > 1 else 0.0
    sd = math.sqrt(var)
    gains, losses = sum(x for x in pnls if x > 0), -sum(x for x in pnls if x < 0)
    return {"n": n, "total": round(sum(pnls), 4), "mean": round(mean, 5), "sd": round(sd, 5),
            "ci95_low": round(mean - 1.96 * sd / math.sqrt(n), 5) if n > 1 else None,
            "profit_factor": round(gains / losses, 2) if losses > 0 else None,
            "win_rate": round(sum(x > 0 for x in pnls) / n, 3)}


def daily(trades):
    d = defaultdict(float)
    for t in trades:
        d[time.strftime("%Y-%m-%d", time.gmtime(t["ts"]))] += t["pnl"]
    return dict(sorted(d.items()))


def criteria(trades, now=None):
    now = now or time.time()
    if not trades:
        return [("C1 ≥7 días", False, "sin vueltas todavía")]
    st = stats([t["pnl"] for t in trades])
    days = (now - min(t["ts"] for t in trades)) / 86400
    last7 = list(daily(trades).values())[-7:]
    fee_cost = sum(2 * t.get("notional", 40) * EXTRA_FEE_PCT / 100 for t in trades) / len(trades)
    return [
        (f"C1 ≥{MIN_DAYS} días", days >= MIN_DAYS, f"{days:.1f} días"),
        (f"C2 ≥{MIN_TRADES} vueltas", st["n"] >= MIN_TRADES, f"{st['n']} vueltas"),
        ("C3 IC95% > 0", (st.get("ci95_low") or -1) > 0, f"media {st['mean']:+.4f} € · IC95 desde {st.get('ci95_low')}"),
        (f"C4 positivo ≥{MIN_POS_DAYS}/7 días", sum(x > 0 for x in last7) >= MIN_POS_DAYS and len(last7) >= 7,
         f"{sum(x > 0 for x in last7)}/{len(last7)} días positivos"),
        (f"C5 +{EXTRA_FEE_PCT}% comisión", st["mean"] - fee_cost > 0, f"media ajustada {st['mean'] - fee_cost:+.4f} €"),
        ("C6 +200 ms latencia", False, "pendiente de medir"),
    ]


def evaluate(path, now=None):
    trades = load(path)
    excluded = len(load(path, min_model=0)) - len(trades)
    by_sym = defaultdict(list)
    for t in trades:
        by_sym[t["sym"]].append(t)
    per_sym = {s: stats([t["pnl"] for t in ts]) | {"lab": any(t.get("lab") for t in ts)} for s, ts in by_sym.items()}
    crit = criteria(trades, now)
    return {"overall": stats([t["pnl"] for t in trades]), "daily": daily(trades), "per_symbol": per_sym,
            "criteria": [{"name": n, "ok": ok, "detail": d} for n, ok, d in crit],
            "criteria_met": sum(ok for _, ok, _ in crit), "criteria_total": len(crit),
            "excluded_old_model": excluded}


if __name__ == "__main__":
    import sys
    print(json.dumps(evaluate(sys.argv[1]), indent=1, ensure_ascii=False))
