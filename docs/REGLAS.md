# Reglas inquebrantables de nexus

Aprobadas por el dueño del proyecto el 24-oct-2026. Cambiar este archivo es **categoría C** (ruta
protegida: requiere aprobación humana explícita). Estado: ✅ implementada · 🟡 parcial · ⏳ pendiente
(obligatoria antes de la fase indicada).

**Límite honesto:** Claude actúa en GitHub con la identidad del dueño, así que GitHub no puede
distinguir entre ambos. Los controles que Claude no puede saltear viven fuera de su alcance: los
permisos de la clave en el exchange, los fondos depositados, la confirmación escrita en el PC
(`update.py --aprobar`, `risk --rearmar`) y la ausencia de código de órdenes reales.

| ID | Regla | Mecanismo | Verificación | Estado |
|---|---|---|---|---|
| R-01 | Capital acotado físicamente | Subcuenta o cuenta con solo el capital autorizado; clave **sin retiro** y con lista blanca de IP | `nexus.check_keys` sale con código 2 si la cuenta permite retiros; el modo real no arranca si la cuenta informa retiros y el dueño no confirmó en `authorize` que la clave no los tiene; ningún módulo contiene endpoints de retiro | `test_ordenes_solo_en_el_cliente_de_trading_y_retiros_en_ninguna_parte`, `test_agente_activa_el_modo_real_solo_con_autorizacion` | ✅ (la subcuenta y la IP las configura el dueño) |
| R-02 | Trading real solo con autorización humana explícita, acotada y con vencimiento | El repositorio nunca habilita el modo real (`live: false`, impuesto por el CI). Solo lo habilita `python -m nexus.agent.authorize`, que escribe el dueño **en la PC** con una frase exacta: capital ≤ 20 €, pares y vencimiento ≤ 7 días. Vencida o revocada, no abre posiciones (las abiertas salen normal). Las órdenes solo existen en `exchanges/mexc_trade.py` | `test_autorizacion_topes_frase_y_revocar`, `test_sin_autorizacion_no_entra_pero_sale`, `test_agente_rechaza_live` | ✅ |
| R-03 | El riesgo es independiente y tiene veto | Las estrategias (`Book`) piden permiso a `Gate` → `RiskManager`; no importan clientes de exchange | `test_estrategias_no_importan_clientes_de_exchange`, `test_veto_de_riesgo_cancela_compra` | ✅ |
| R-04 | Límites inmutables en ejecución y fuera del alcance de estrategias e IA | Límites en `agent.yaml`; el CI rechaza valores por encima de la línea base; las rutas protegidas ponen el PR en rojo; el PC no activa cambios protegidos sin `--aprobar` local | `test_gate.py`, `protected_paths.py`, `test_cambios_protegidos_requieren_aprobacion_local` | ✅ |
| R-05 | No operar con estado de orden desconocido | Error de red al enviar o cancelar ⇒ el par no envía nada hasta consultar la orden por su ID; al arrancar concilia la orden guardada, cancela órdenes propias huérfanas y compara el saldo; cada 10 min compara saldo y posición; si no coincide, el par queda bloqueado hasta revisión humana | `test_corte_de_red_al_enviar_bloquea_hasta_conciliar`, `test_al_arrancar_concilia_orden_guardada_huerfanas_y_saldo` | ✅ |
| R-06 | Idempotencia de órdenes | ID de orden propio determinista (`nx<secuencia><par>`), guardado antes de enviar | `test_id_propio_se_guarda_antes_de_enviar_y_requote_cancela` | ✅ |
| R-07 | Validación antes de operar | Datos con más de 20 s ⇒ se cancela la compra; comisiones verificadas por API (se usa la mayor) | `stale_data_s`, `verified_fees` | 🟡 faltan bandas de precio y saldo (Fase 6) |
| R-08 | Ante fallas críticas, cerrar el paso | Las entradas se bloquean y las salidas se permiten; sin liquidación a ciegas. En real: rechazo del exchange ⇒ no reintenta a ciegas y 5 seguidos bloquean el par; datos viejos ⇒ cancela la compra; estado desconocido ⇒ R-05; riesgo real con estado propio (`risk_real.json`) | tests de riesgo, `test_rechazos_seguidos_bloquean_el_par` | ✅ |
| R-09 | Persistencia y recuperación | Riesgo y estado del paper en `NEXUS_HOME/state` con escritura atómica; **un reinicio no borra la pérdida del día** | `test_perdida_diaria_sobrevive_reinicio`, `test_estado_del_libro_persiste` | ✅ (falta conciliar con el exchange: Fase 6) |
| R-10 | Registro íntegro | Diario de órdenes `orders.jsonl` con hash encadenado (alterar una línea rompe la cadena); PnL real calculado con lo ejecutado por el exchange (`real_trades.jsonl`), separado del paper | `test_diario_de_ordenes_detecta_alteraciones`, `test_vuelta_completa_con_llenados_del_exchange` | ✅ |
| R-11 | Credenciales | Claves solo en `%LOCALAPPDATA%\nexus\.env` (permisos solo del usuario); nada de claves en GitHub; el latido oculta cadenas que parecen secretos | `test_latido_oculta_cadenas_tipo_secreto`, `test_env_no_pisa_variables` | ✅ (el dueño borró los secretos de GitHub el 24-oct; claves solo de lectura y sin retiro) |
| R-12 | Ningún cambio llega al sistema activo sin validar | El PC solo instala `main` con CI en verde y vuelve a correr los tests localmente | `update.py`, `test_no_activa_sin_ci_verde` | ✅ |
| R-13 | Actualización segura | No actualiza con posiciones abiertas; reinicio controlado; chequeo de salud y vuelta atrás | `test_no_activa_con_posiciones_abiertas` | ✅ |
| R-14 | Prohibido relajar límites para salvar una estrategia | Línea base en `backtest/run.py`; bajar límites está permitido, subirlos no | `test_rechaza_relajar_cada_limite` | ✅ |
| R-15 | Evidencia mínima para promover de fase | Criterios fijados de antemano (abajo) | `evidence.py`, informe diario | ✅ (C6 latencia pendiente de medir) |
| R-16 | Parada controlada | Archivo `KILL` en `NEXUS_HOME`: vacío = no abre posiciones y cancela compras; con `2` = cancela todas las órdenes en el exchange; con `3` = cancela y vende las posiciones a mercado | `test_interruptor_de_emergencia`, `test_kill_2_cancela_y_kill_3_vende` | ✅ |
| R-17 | Configuración validada | Faltan claves o hay valores fuera de rango ⇒ el CI falla o el riesgo no arranca | `test_gate.py`, `REQUIRED` en `risk.py` | ✅ |
| R-18 | La IA no tiene autoridad de ejecución | Claude propone por PR; nunca fusiona un PR con `protected-paths` en rojo; no puede aprobar en el PC | política más los controles R-04 y R-12 | 🟡 (ver "límite honesto") |
| R-19 | Nivel de evidencia explícito | Los informes etiquetan teórico, simulado, paper o real; "ganadoras" = PnL > 0 | `test_regresion_defecto2_*` | ✅ |
| R-20 | Cumplimiento fiat | Topes de movimientos fiat al 60% del umbral regulatorio; sin fraccionar para evitar controles | `compliance.py`, tests | ✅ |
| R-21 | Cadena de suministro | Dependencias con versión fija; acciones fijadas por SHA; permisos mínimos por workflow | revisión del CI | 🟡 faltan hashes de dependencias |

## Criterios para avanzar de fase (R-15)

Aprobados por el dueño el 24-oct-2026 ("dale"), en reemplazo de "≥4 semanas". Se evalúan solos
(`nexus/evidence.py`) y su avance aparece en el informe diario.

- **De paper (Fase 5) a real (Fase 6a, 20 € reales)**, todos a la vez:
  - ≥7 días y ≥300 vueltas cerradas, sumando los pares operados y los de laboratorio.
  - Ganancia media por vuelta con intervalo de confianza del 95% por encima de 0.
  - Positivo en ≥5 de los últimos 7 días.
  - Sigue positivo con +0,02% de comisión por lado y con 200 ms de latencia adicional.
  - Ningún halt permanente.
  - R-05, R-06, R-08, R-10 y R-16 implementadas.
  - **Autorización explícita del dueño** (clave de MEXC solo de trading, sin retiro, con IP fija).
- **Excepción de calibración (Fase 6a-c):** el dueño puede autorizar hasta 20 € reales ANTES de cumplir
  los criterios de paper (`authorize --calibracion`) para medir los llenados reales contra el modelo
  de paper en el mismo par. Mismos límites de riesgo (2 €/día, 4 €/semana, 8 € total), máximo 7
  días por autorización, renovable solo por el dueño. No promueve a 6b por sí sola: para pasar a
  100 € se exige lo de abajo. Incorporada al fusionar el PR de la Fase 6 (aprobación del dueño).
- **De 6a a 6b (100 €):** una semana con 20 € reales y PnL real, conciliado con el exchange, > 0.
- **Retroceso automático:** PnL neto de 7 días < 0 ⇒ halt de la estrategia (`losing_days_window`);
  drawdown de 8 € ⇒ halt total.

## Aprobaciones del dueño (registro)

| Fecha | Qué | Cómo |
|---|---|---|
| 24-oct-2026 | Reglas R-01 a R-21, Fase 2, límites para 100 € | "sí a todo" |
| 24-oct-2026 | Actualizador: un agente detenido no bloquea su arreglo (PR 11) | merge del dueño + APRUEBO en el PC |
| 24-oct-2026 | Criterios acelerados de R-15 y entrada gradual 20 € → 100 € | "dale" |

## Categorías de acciones

- **A, automáticas:** leer datos públicos, simular, generar informes, diagnosticar, proponer PR.
- **B, con validación técnica:** cambiar estrategias en paper, pares, dependencias o versiones. Pasan por PR y CI en verde, y el PC solo las instala si se cumple R-12/R-13.
- **C, solo con autorización humana explícita:** activar el modo real, subir límites, permisos de claves, desactivar protecciones, tocar rutas protegidas o hacer acciones irreversibles. El silencio, una buena simulación o una recomendación de la IA **no** son autorización.
