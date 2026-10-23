"""Comparador de estrategias: ganancia esperada anual neta (EUR) para un capital dado.

Todos los parámetros son supuestos editables; las tasas salen de fuentes secundarias (ver README).
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Strategy:
    name: str
    gross_apy_pct: float        # rendimiento bruto anual esperado
    fixed_cost_eur: float       # costos únicos de entrada/salida (comisiones, red)
    tax_pct: float              # impuesto sobre la ganancia
    risk: str                   # bajo / medio / alto
    notes: str = ""


def annual_net(s: Strategy, capital_eur: float, years: float = 1.0) -> float:
    gain = capital_eur * s.gross_apy_pct / 100 * years
    gain *= 1 - s.tax_pct / 100
    return gain - s.fixed_cost_eur


def rank(strategies, capital_eur):
    rows = [(s, annual_net(s, capital_eur)) for s in strategies]
    return sorted(rows, key=lambda r: r[1], reverse=True)


DEFAULTS = [
    Strategy("USDC en Aave/Kraken DeFi Earn", 3.5, 0.8, 26, "medio", "riesgo smart-contract; 26% solo EMT"),
    Strategy("EURC en Aave", 3.0, 0.8, 26, "medio", "EMT en euro: tributa 26%"),
    Strategy("Carry ARS (billetera ~20% TNA, sin FX)", 0.0, 3.0, 26, "alto",
             "ganancia en ARS; la devaluación puede borrarla. Ver 'carry_usd'"),
    Strategy("sUSDe delta-neutral", 7.0, 1.5, 33, "alto", "depeg/funding negativo; no apto EEE"),
    Strategy("Arbitraje solo-ARS (escáner)", 0.0, 0.0, 33, "medio", "depende de spreads en vivo"),
]
