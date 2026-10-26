"""Investigación de seguridad DeFi (línea nueva, AISLADA del trading).

Pipeline SOLO de investigación, sin dinero y sin interactuar con ningún sistema en producción:
  A. descubrimiento  -> catalog.py (programas autorizados) + changes.py (cambios recientes, read-only)
  B. análisis diferencial / triaje barato y determinista (sin IA) -> triage.py
  C. método de validación por invariantes, demostrado en Python -> invariants.py
  (orquestación con topes) -> run.py

Límites duros que este módulo NUNCA cruza (ver docs/INVESTIGACION_SEGURIDAD.md):
- No envía informes: ninguna función manda nada a ningún programa. El envío lo decide y lo hace una persona.
- No prueba exploits contra contratos en producción, testnets públicas ni sistemas de terceros.
- Solo LEE historial público de repos autorizados; nunca escribe ni transacciona en ninguna cadena.
- Un programa no se considera "en alcance" hasta que el dueño lo marca verificado tras leer su reglamento.
- No reutiliza ni toca el código de trading ni las rutas de dinero del bot.
"""
