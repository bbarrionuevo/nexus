"""Etapa B: triaje barato y determinista (SIN IA) de un cambio en un contrato.

Mira solo las líneas agregadas y quitadas del parche y suma señales de relevancia financiera, con foco
en la especialidad de esta iteración (contabilidad de vaults ERC-4626: shares/assets, redondeo y
precisión). Devuelve el puntaje y QUÉ señales lo justifican, para que una persona vea por qué.
Un puntaje alto NO es una vulnerabilidad: es "vale la pena mirarlo". Nada se marca como hallazgo sin
una prueba reproducible (etapa C/D).
"""
import re

# (nombre, peso, expresión). Pesos fijados de antemano; se recalibran solo con resultados medidos.
SIGNALS = (
    ("conversión shares/assets", 5, r"\b_?convertTo(Shares|Assets)\b|\bpreview(Deposit|Mint|Withdraw|Redeem)\b"),
    ("totalAssets/totalSupply", 4, r"\btotal(Assets|Supply)\b"),
    ("dirección de redondeo", 5, r"\bRounding\.(Up|Down|Floor|Ceil)\b|\bmulDiv(Up|Down)?\b|\bceilDiv\b"),
    ("división entera", 2, r"[^/]/[^/*=]"),
    ("decimales / escala", 3, r"\bdecimals\b|\b10\s*\*\*\s*\w+|\b1e(18|27|36)\b|_decimalsOffset"),
    ("emisión o quema de shares", 3, r"\b_(mint|burn)\s*\("),
    ("control de acceso", 4, r"\bonly(Owner|Role|Admin)\b|\b_checkRole\b|require\s*\(\s*msg\.sender|\bmodifier\b"),
    ("oráculo / precio", 4, r"\blatestRoundData\b|\blatestAnswer\b|\bgetPrice\b|\boracle\b"),
    ("llamada externa / reentrada", 3, r"\.(call|delegatecall)\s*[({]|\bnonReentrant\b|\bsafeTransfer(From)?\b"),
    ("unchecked", 3, r"\bunchecked\s*\{"),
)
_RX = [(n, w, re.compile(x)) for n, w, x in SIGNALS]


def changed_lines(patch):
    """Líneas agregadas o quitadas de un parche unificado (sin los encabezados +++/---)."""
    out = []
    for line in (patch or "").splitlines():
        if line[:1] in "+-" and not line.startswith(("+++", "---")):
            code = line[1:].split("//")[0].strip()
            if code:
                out.append(code)
    return out


def score(patch):
    lines = changed_lines(patch)
    hits = {}
    for name, w, rx in _RX:
        n = sum(1 for ln in lines if rx.search(ln))
        if n:
            hits[name] = {"weight": w, "lines": n}
    total = sum(h["weight"] * min(h["lines"], 3) for h in hits.values())    # cada señal suma hasta 3 veces
    tier = "alta" if total >= 20 else "media" if total >= 8 else "baja"
    return {"score": total, "tier": tier, "signals": hits, "changed_lines": len(lines)}


def rank(changes):
    """Ordena cambios por puntaje del archivo más relevante de cada commit."""
    rows = []
    for c in changes:
        for f in c["files"]:
            rows.append({"repo": c["repo"], "sha": c["sha"], "url": c.get("url"), "date": c.get("date"),
                         "message": c.get("message"), "file": f["filename"], **score(f.get("patch"))})
    return sorted(rows, key=lambda r: -r["score"])
