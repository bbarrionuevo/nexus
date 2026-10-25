"""Autorización LOCAL para operar con dinero real (R-02). Solo la puede dar una persona en esta PC.

  python -m nexus.agent.authorize --capital 20 --dias 7 --pares BONKUSDT [--calibracion]
  python -m nexus.agent.authorize --estado
  python -m nexus.agent.authorize --revocar        (deja de abrir posiciones; las abiertas salen normal)
  python -m nexus.agent.authorize --desbloquear BONKUSDT   (tras revisar en MEXC un par bloqueado: lo que
      haya de esa moneda queda como residuo no gestionado y el par arranca de cero; si querés que no
      quede nada, vendelo a mano antes)

Topes de la Fase 6a: hasta 20 € y 7 días por autorización. Sin --calibracion exige que la evidencia en
paper cumpla todos los criterios de R-15. Con --calibracion se permite antes, como medición de los
llenados reales (excepción de REGLAS.md): mismo gestor de riesgo y mismos límites.
Claude nunca ejecuta este comando: la frase la escribe el dueño.
"""
import argparse
import time

from .. import paths
from .live import AUTH_FILE, CALIBRATION_MAX_EUR, MAX_DAYS, UNBLOCK_FILE, authorization

PHRASE = "AUTORIZO OPERAR CON DINERO REAL"


def validate(capital, days, symbols, calibration, status):
    """Lista de motivos por los que no se puede autorizar (vacía = se puede)."""
    errs = []
    if not 0 < capital <= CALIBRATION_MAX_EUR:
        errs.append(f"capital {capital} fuera de la Fase 6a (máximo {CALIBRATION_MAX_EUR:g} €)")
    if not 0 < days <= MAX_DAYS:
        errs.append(f"vigencia {days} días fuera de rango (máximo {MAX_DAYS})")
    if not symbols or any(not s.endswith("USDT") or not s.isalnum() or s != s.upper() for s in symbols):
        errs.append("pares inválidos: usar símbolos de MEXC como BONKUSDT")
    ev = (status or {}).get("evidence") or {}
    met, total = ev.get("criteria_met", 0), ev.get("criteria_total", 0)
    if not calibration and not (total and met == total):
        errs.append(f"la evidencia en paper cumple {met}/{total} criterios de R-15: sin --calibracion no se autoriza")
    if (status or {}).get("risk", {}).get("sticky_halt"):
        errs.append("hay un halt permanente activo en el paper")
    return errs


def main(argv=None, ask=input, out=print, now=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--capital", type=float)
    ap.add_argument("--dias", type=float, default=7)
    ap.add_argument("--pares", default="")
    ap.add_argument("--calibracion", action="store_true")
    ap.add_argument("--estado", action="store_true")
    ap.add_argument("--revocar", action="store_true")
    ap.add_argument("--desbloquear", default="")
    a = ap.parse_args(argv)
    now = now or time.time()
    path = paths.state(AUTH_FILE)
    if a.desbloquear:
        syms = [s.strip().upper() for s in a.desbloquear.split(",") if s.strip()]
        if ask(f"¿Revisaste en MEXC {', '.join(syms)} (órdenes y saldo)? Lo que haya quedará como residuo (escribí SI): "
               ).strip() != "SI":
            out("No se cambió nada.")
            return 2
        paths.write_json_atomic(paths.state(UNBLOCK_FILE), {"ts": now, "symbols": syms})
        out("Pedido registrado: el agente desbloquea en su próximo ciclo.")
        return 0
    if a.estado or (a.capital is None and not a.revocar):
        cur = authorization(now)
        out(f"Autorización vigente: {cur}" if cur else "No hay autorización vigente: el agente opera solo en paper.")
        return 0
    if a.revocar:
        cur = paths.read_json(path, None)
        if cur:
            paths.write_json_atomic(path, cur | {"expires": now, "revoked": now})
        out("Revocada: no se abren posiciones reales nuevas; las abiertas siguen su salida normal. "
            "Para cerrar todo ya: escribir 3 en el archivo KILL.")
        return 0
    symbols = [s.strip().upper() for s in a.pares.split(",") if s.strip()]
    errs = validate(a.capital, a.dias, symbols, a.calibracion, paths.read_json(paths.state("status.json"), {}))
    if errs:
        out("No se puede autorizar:\n- " + "\n- ".join(errs))
        return 2
    out(f"Vas a autorizar DINERO REAL: hasta {a.capital:g} € en {', '.join(symbols)} durante {a.dias:g} días"
        f"{' (calibración, antes de cumplir R-15)' if a.calibracion else ''}.")
    out("Límites que siguen valiendo: pérdida diaria 2 €, semanal 4 €, total 8 € (halt), KILL en cualquier momento.")
    if ask("¿La clave de MEXC tiene el RETIRO DESACTIVADO y está limitada a la IP de esta PC? (escribí SI): ").strip() != "SI":
        out("Sin confirmar la clave no se autoriza (R-01). No se cambió nada.")
        return 2
    if ask(f'Escribí exactamente "{PHRASE}": ').strip() != PHRASE:
        out("Frase incorrecta. No se cambió nada.")
        return 2
    paths.write_json_atomic(path, {"ts": now, "expires": now + a.dias * 86400, "capital_eur": a.capital,
                                   "symbols": symbols, "calibracion": a.calibracion, "sin_retiro_confirmado": True})
    out(f"Autorizado hasta {time.strftime('%Y-%m-%d %H:%M', time.localtime(now + a.dias * 86400))}. "
        "El agente lo toma en su próximo reinicio (Stop-ScheduledTask nexus-agente; Start-ScheduledTask nexus-agente).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
