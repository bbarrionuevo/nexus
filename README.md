# nexus

Bot de arbitraje cripto/fiat (EUR/N26 ↔ ARS/CVU). **Arranca en paper trading.**

- `local/` — Fase 1: ejecutor local (monitoreo, cálculo de rentabilidad neta, límites anti-bloqueo, PM2).
- `backtest/`, `.github/workflows/` — Fase 2: CI y gate de seguridad. El análisis de logs lo hace Claude en la sesión de trabajo (sin API).

## Secretos (GitHub → Settings → Secrets)
`BINANCE_API_KEY`, `BINANCE_SECRET_KEY`, `KRAKEN_API_KEY`, `KRAKEN_SECRET_KEY` (solo lectura).
Localmente: copiar `.env.example` a `.env`.

## Seguridad
- Clientes de exchange con lista blanca de endpoints (sin órdenes ni retiros).
- Límites en `local/config/settings.yaml` con margen del 60%; `backtest/run.py` bloquea PRs que los relajen o apaguen paper trading.
- Comisiones del YAML son estimaciones: verificar tablas oficiales antes de operar real.

## Uso
```
pip install -r local/requirements.txt
cd local && python -m nexus.main && pytest
```

## Hallazgos de investigación (oct-2026)
- MiCA: ningún exchange con licencia en el EEE ofrece USDT; Binance suspendió depósitos/órdenes spot del EEE desde 1-jul-2026. La pata europea usa **Kraken + USDC**.
- Con 100 EUR, el ciclo EUR→ARS→EUR necesita un spread bruto ≥ ~1.3–1.8% solo para empatar (comisiones 0.4%×2 + red 0.5–1 EUR). Mucho más realista: **arbitraje solo-ARS entre plataformas argentinas** (`core/ars_scanner.py`), sin rieles europeos.
- Verificar siempre fees reales en la pantalla de Kraken antes de operar.
