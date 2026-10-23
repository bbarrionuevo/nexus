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
