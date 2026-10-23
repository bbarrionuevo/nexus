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

## Evaluación del PDF "Oportunidades Reales" (datos reales, 23-oct-2026, 20 muestras / 10 min)
- Tesis del PDF: vender USDT en Binance P2P 1,5–3,5% sobre el precio de recompra en Fiwind. Medido: precio competitivo P2P ≈ 1.642 ARS vs compra spot Fiwind ≈ 1.652 → **edge −0,63%** (rango −0,73 a −0,61%, 0/20 muestras sobre 1,5%).
- Spreads medidos (ask/bid): Binance P2P 0,16%, Bybit P2P −0,03%, Fiwind 0,80%, Belo 1,19%. Mercado ajustado: P2P ≈ bid de Fiwind.
- Mejor cruce solo-ARS: +0,18% bruto (USDT) / +0,01% (USDC); negativo tras costo de red.
- Verificado en el PDF: la pata EUR→USDT en Binance ya no existe para residentes EEE (jul-2026); la API para publicar anuncios P2P no está confirmada para cuentas retail; el endpoint de órdenes de Fiwind no está verificado.
- No se implementan funciones cuyo fin sea evadir la detección AML (p. ej. fraccionar para no ser marcado). Los límites de `compliance.py` mantienen la operatoria dentro de los umbrales legales, y todo debe declararse.

## Descubrimiento automático (23-oct-2026) — qué funciona y qué no, con datos reales
Workflows: `discover.yml` (cada 20 min), `research-maker.yml` (cada 6 h), `trading-backtest.yml` (diario). Datos en la rama `data`.

| Clase | Resultado | Veredicto |
|---|---|---|
| Triangular Binance (1.218 pares) | ineficiencia bruta máx 0,03% vs 0,225% de fees | ❌ mercado eficiente |
| Triangular Kraken (con filtro de liquidez) | todo negativo | ❌ |
| Cruce Kraken/Bitstamp/Coinbase EUR | −0,77% neto | ❌ |
| Paridad EURC (puente 1:1 gratis de Kraken) | −0,4% | ❌ |
| EURR/USDR "+3% / +49%" | depeg por hackeo StablR (may-2026), redención suspendida | ⚠️ trampa, excluidas |
| ARS entre plataformas (USDT/USDC/BTC/ETH) | −1% a −3% neto | ❌ |
| PDF: vender P2P / recomprar Fiwind | −0,63% | ❌ |
| Trading direccional RSI/SMA/breakout (20 monedas, walk-forward) | 1h: 5/20 positivas; 4h: azar | ❌ sin ventaja robusta |
| **Market making con maker 0%** (AI, BONK, ID; 1m, 3 días) | **+26% a +30%** con 160–209 vueltas | ✅ candidato — en validación |
| Market making con maker 0,1% | 2/30 positivas | ❌ la comisión mata el margen |

Conclusión: la única ventaja medible para "miles de operaciones de céntimos" es **proveer liquidez donde la comisión maker es 0%** (Binance: pares FDUSD, según fuentes secundarias). Requiere cuenta habilitada (p. ej., residente argentino; Binance es PSAV registrado ante la CNV).
