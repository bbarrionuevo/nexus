"""Motor de investigación de seguridad DeFi para programas de bug bounty AUTORIZADOS.

  A. descubrimiento  -> catalog.py (programas autorizados) + changes.py (cambios recientes, solo lectura)
  B. triaje barato y determinista (sin IA) -> triage.py
  C. método de validación por invariantes ERC-4626 -> invariants.py
  orquestación con topes -> run.py · límites de seguridad -> limits.py (archivo protegido)

Reglas completas en docs/REGLAS.md. Lo esencial: nada se envía automáticamente; nada se prueba contra
contratos desplegados, testnets públicas ni sistemas de terceros; solo se lee historial público; los
resultados quedan en la PC del dueño, nunca en el repo público.
"""
