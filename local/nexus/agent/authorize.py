"""Autorización LOCAL para operar con dinero real (R-02). Solo la puede dar una persona en esta PC.

  python -m nexus.agent.authorize --todo --dias 7 --pares BONKUSDT [--calibracion]
      (--todo: siempre TODO el capital de la subcuenta, hasta 100 €; las ganancias se reinvierten.
       --capital N fija un monto menor)
  python -m nexus.agent.authorize --todo --dias 7 --auto 2 --calibracion
      (modo automático: el agente opera hasta N pares PROMOVIDOS por el laboratorio, los de mejor cota
      inferior fuera de muestra; cambia de par solo sin posición; el capital se reparte entre ellos)
  python -m nexus.agent.authorize --estado
  python -m nexus.agent.authorize --revocar        (deja de abrir posiciones; las abiertas salen normal)
  python -m nexus.agent.authorize --desbloquear BONKUSDT   (tras revisar en MEXC un par bloqueado: lo que
      haya de esa moneda queda como residuo no gestionado y el par arranca de cero; si querés que no
      quede nada, vendelo a mano antes)

Topes: hasta 100 € (el capital del dueño) y 7 días por autorización. Sin --calibracion exige que la evidencia en
paper cumpla todos los criterios de R-15. Con --calibracion se permite antes, como medición de los
llenados reales (excepción de REGLAS.md): mismo gestor de riesgo y mismos límites.
Claude nunca ejecuta este comando: la frase la escribe el dueño.
"""
import argparse
import time

from .. import paths
from .live import AUTH_FILE, MAX_AUTO_PAIRS, MAX_CAPITAL_EUR, MAX_DAYS, UNBLOCK_FILE, authorization

PHRASE = "AUTORIZO OPERAR CON DINERO REAL"


def validate(capital, days, symbols, calibration, status, auto=0):
    """Lista de motivos por los que no se puede autorizar (vacía = se puede)."""
    errs = []
    if auto and not 1 <= auto <= MAX_AUTO_PAIRS:
        errs.append(f"--auto admite de 1 a {MAX_AUTO_PAIRS} pares")
    if auto and symbols:
        errs.append("usar --pares o --auto, no los dos")
    if not 0 < capital <= MAX_CAPITAL_EUR:
        errs.append(f"capital {capital} fuera de rango (máximo {MAX_CAPITAL_EUR:g} €)")
    if not 0 < days <= MAX_DAYS:
        errs.append(f"vigencia {days} días fuera de rango (máximo {MAX_DAYS})")
    if (not symbols and not auto) or any(not s.endswith("USDT") or not s.isalnum() or s != s.upper() for s in symbols):
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
    ap.add_argument("--todo", action="store_true")
    ap.add_argument("--dias", type=float, default=7)
    ap.add_argument("--pares", default="")
    ap.add_argument("--auto", type=int, default=0)
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
    if a.todo and a.capital is None:
        a.capital = MAX_CAPITAL_EUR                       # todo lo de la subcuenta, hasta el tope
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
    errs = validate(a.capital, a.dias, symbols, a.calibracion, paths.read_json(paths.state("status.json"), {}), a.auto)
    if errs:
        out("No se puede autorizar:\n- " + "\n- ".join(errs))
        return 2
    where = ', '.join(symbols) if symbols else f"los {a.auto} mejores pares promovidos (modo automático)"
    amount = f"TODO el capital de la subcuenta (hasta {a.capital:g} €)" if a.todo else f"hasta {a.capital:g} €"
    out(f"Vas a autorizar DINERO REAL: {amount} en {where} durante {a.dias:g} días"
        f"{' (calibración, antes de cumplir R-15)' if a.calibracion else ''}.")
    out("Límites que siguen valiendo: pérdida diaria 2 €, semanal 4 €, total 8 € (halt), KILL en cualquier momento.")
    if ask("¿La clave de MEXC tiene el RETIRO DESACTIVADO y está limitada a la IP de esta PC? (escribí SI): ").strip() != "SI":
        out("Sin confirmar la clave no se autoriza (R-01). No se cambió nada.")
        return 2
    if ask(f'Escribí exactamente "{PHRASE}": ').strip() != PHRASE:
        out("Frase incorrecta. No se cambió nada.")
        return 2
    paths.write_json_atomic(path, {"ts": now, "expires": now + a.dias * 86400, "capital_eur": a.capital,
                                   "symbols": symbols, "auto": a.auto, "todo": a.todo, "calibracion": a.calibracion,
                                   "sin_retiro_confirmado": True})
    out(f"Autorizado hasta {time.strftime('%Y-%m-%d %H:%M', time.localtime(now + a.dias * 86400))}. "
        "El agente lo toma solo en menos de un minuto: no hace falta reiniciarlo.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
