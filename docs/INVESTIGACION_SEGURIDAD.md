# Investigación de seguridad DeFi (línea nueva, aislada del trading)

Pedido del dueño del 26-oct-2026: investigar vulnerabilidades económicas y lógicas en protocolos DeFi
con programa de bug bounty **autorizado**, con pruebas locales y sin poner dinero. Esta línea **no
promete ingresos**: solo cuenta una recompensa cuando se cobra.

## Decisión de arquitectura

- **Módulo aislado dentro del repo** (`local/nexus/secresearch/`), no un proyecto aparte. Reutiliza
  pytest, el CI, la disciplina de evidencia (reglas fijadas de antemano, sin sobreajuste) y el modelo de
  "la IA propone, el dueño decide". No importa ni toca el código de trading ni las rutas de dinero; un
  test lo verifica. Si crece, se separa después.
- **Sin Docker, base de datos, servicios pagos ni nube nueva**: Python + git, que la PC ya tiene.
- **Los resultados son privados**: catálogo y resultados en `NEXUS_HOME` (en la PC,
  `%LOCALAPPDATA%\nexus\secresearch`). El repo es público, y un posible hallazgo publicado sería divulgar
  una vulnerabilidad sin reportar. El orquestador se niega a escribir dentro del repo, y ningún workflow
  publica estos resultados en la rama `data`.

## Especialidad del primer prototipo: contabilidad de vaults ERC-4626

| Especialidad | Autocontenida | Se prueba sin estado de mainnet | Barrera de herramientas | Elegida |
|---|---|---|---|---|
| Vaults ERC-4626 (shares/assets, redondeo, precisión) | Sí: pocas funciones | Sí: tests de propiedad | Baja: el método se demuestra en Python | **Sí** |
| Préstamos y liquidaciones | No: oráculos, intereses, incentivos | Parcial: hace falta estado de precios | Alta | No (después) |
| Oráculos | No: depende de fuentes externas | No: hace falta fork | Alta | No |
| Control de acceso | Sí | Sí | Baja | No: muy revisado por auditorías y herramientas estáticas |

Los errores de dirección de redondeo y el ataque del primer depositante son una clase de fallo
recurrente y bien documentada en vaults. Se prueba de forma determinista, que es lo que exige esta línea.

## Pipeline y estado real

| Etapa | Qué hace | Estado | Evidencia |
|---|---|---|---|
| A. Catálogo | Programas autorizados; el pipeline los ignora hasta que el dueño verifica el reglamento | Implementado, **vacío** | `catalog.py`, tests |
| A. Cambios | Commits nuevos que tocan contratos en alcance, por git (clon superficial) o API; libro de vistos; excluye tests, mocks, scripts y specs | Implementado y verificado | Demo sobre OpenZeppelin: 3 commits, 15 archivos, 2.ª corrida sin repetir. Vista previa de los 6 repos de Morpho, Yearn y Euler: el 49% de los archivos eran tests o mocks y daban 11 de 19 alertas "alta"; tras excluirlos, 8 alertas "alta", todas en contratos de producción |
| B. Triaje | Puntaje determinista **sin IA** de las líneas cambiadas, con señales ERC-4626 | Implementado y verificado | En la demo puso primero el único cambio de vault (ERC7535, puntaje 31) entre 15 archivos |
| C. Método de invariantes | Modelo de referencia ERC-4626 con aritmética entera y propiedades P0–P6 | Implementado y verificado | Autoverificación: pasa la correcta y atrapa los 5 defectos de referencia |
| D. Validación contra el código en alcance | Las mismas propiedades como tests de invariantes de Foundry, en local | **Pendiente**: requiere Foundry en la PC (decisión del dueño) | — |
| E. Duplicados y alcance | Auditorías previas, problemas conocidos, exclusiones | Parcial: el catálogo guarda exclusiones; la búsqueda de auditorías está pendiente | — |
| F. Expediente | Informe por candidato confirmado | Pendiente: plantilla abajo | — |

Propiedades del método (etapa C):

- **P0.** Ninguna operación revienta.
- **P1.** Depositar y rescatar no devuelve más de lo depositado.
- **P2.** Acuñar y rescatar no devuelve más de lo pagado.
- **P3.** Retirar no deja más valor que el que había.
- **P4.** Solvencia.
- **P5.** El ataque del primer depositante no deja ganancia.
- **P6.** Ninguna operación baja el valor de los demás.

La primera versión no detectaba "mint hacia abajo" ni "rescate hacia arriba". Esos defectos solo se
explotan después de una pérdida del vault (precio de la share < 1) y roban a los demás sin crear valor.
Se agregaron las pérdidas al modelo y la propiedad P6. Es exactamente el tipo de falso negativo que
el método tiene que ir cerrando.

## Límites de seguridad (no se cruzan)

- Solo código, activos y actividades **explícitamente autorizados** por el reglamento vigente de cada programa.
- **Nunca** se prueba nada contra contratos en producción, testnets públicas, billeteras ajenas ni
  sistemas de terceros. La validación es en local; un fork local solo si el reglamento lo permite.
- Solo se **lee** historial público (git). No se transacciona en ninguna cadena; un test verifica que
  el módulo no contiene envíos ni transacciones.
- **Nada se envía automáticamente.** Cada informe lo revisa y lo envía el dueño.
- Sin tráfico intensivo: un clon superficial por repo y corrida, y topes de tiempo y operaciones.
- Sin secretos ni datos personales en los informes.
- No se exageran severidades ni impactos.

## Uso de IA y costo

Hoy la línea hace **cero llamadas a modelos**: las etapas A–C son deterministas. El escalonado previsto es:

1. Filtros baratos.
2. Triaje del diff.
3. Tests e invariantes.
4. Claude solo para hipótesis sobre cambios de prioridad "alta" (pendiente, con tope de llamadas por día).
5. Revisión profunda solo con evidencia reproducible.

Cada hipótesis va a quedar registrada con los comandos y tests que la confirmaron o descartaron.

## Cómo correrlo en la PC

En PowerShell, desde `%USERPROFILE%\nexus\local`:

```powershell
# Verificación local completa (sintaxis, lint si hay ruff, tests, control de límites, método):
..\.venv\Scripts\python -m nexus.devcheck

# Autoverificación del método de invariantes:
..\.venv\Scripts\python -m nexus.secresearch.run --selfcheck

# Demostración del circuito sobre un repo público (no es un objetivo):
..\.venv\Scripts\python -m nexus.secresearch.run --demo OpenZeppelin/openzeppelin-contracts contracts/token/ERC20/extensions/

# Uso real: copiar nexus\secresearch\catalogo.ejemplo.yaml a %LOCALAPPDATA%\nexus\secresearch.yaml,
# completarlo DESPUÉS de leer cada reglamento oficial, y correr:
..\.venv\Scripts\python -m nexus.secresearch.run
```

El informe queda en `%LOCALAPPDATA%\nexus\secresearch\secresearch.md`.

## Métricas (lo único que cuenta)

- Programas activos que cumplen los criterios.
- Cambios relevantes encontrados por semana.
- Hipótesis generadas, descartadas y reproducibles (en %).
- Falsos positivos identificados.
- Tiempo y costo por candidato.
- Tests ejecutados y aprobados.
- Informes con evidencia suficiente.
- **Recompensas cobradas.** Una recompensa estimada no es un ingreso.

## Programas elegidos por el dueño (26-oct-2026): Morpho, Yearn V3 y Euler v2

| Programa | Plataforma | Repos (código de vaults ERC-4626) | Aviso |
|---|---|---|---|
| Morpho | Cantina | `morpho-org/metamorpho`, `morpho-org/vault-v2` | Prohíbe probar en cadenas públicas; recomienda forks locales |
| Yearn V3 | Immunefi | `yearn/yearn-vaults-v3` (Vyper 0.3.10), `yearn/tokenized-strategy` | Su `foundry.toml` tiene `ffi = true`: correr siempre con `FOUNDRY_FFI=false` |
| Euler v2 | Cantina | `euler-xyz/euler-vault-kit`, `euler-xyz/euler-earn` | El alcance son las direcciones desplegadas, no el repo entero |

El catálogo queda con `in_scope` y `verified_by_owner` en `false` hasta que el dueño lea cada reglamento.

**Seguridad de la PC:** compilar y testear código de terceros es ejecutar código ajeno. FFI de Foundry
siempre apagado (`FOUNDRY_FFI=false`), y nunca correr scripts de despliegue (`forge script`) de esos repos.

## Selección de programas (fase 3)

No hay programas seleccionados todavía. El 26-oct no se encontró un programa activo centrado en
ERC-4626: la competencia de Immunefi sobre el vault ERC-4626 de Firelight terminó en noviembre de 2025.
Procedimiento:

1. Buscar en los directorios oficiales (Immunefi, Cantina, Sherlock) los programas con vaults ERC-4626
   en alcance y código abierto.
2. Leer el reglamento vigente: alcance, exclusiones, requisitos de PoC, KYC, plazos y si permite fork local.
3. Cargar como máximo 3 en el catálogo, con `in_scope` y `verified_by_owner` en `true`.

Candidatos a **verificar** (protocolos con vaults ERC-4626 de código abierto; no se sabe si hoy tienen
programa activo): Morpho (MetaMorpho), Yearn V3 y Euler v2.

## Plan de 30 días, con puntos de decisión

- **Semana 1.** El dueño verifica hasta 3 programas. Corrida diaria manual y medición de cambios relevantes por semana.
  - **Decisión día 7:** con menos de 2 cambios relevantes por semana entre los 3, se cambia de programas.
- **Semana 2.** Decisión sobre Foundry. Si se aprueba: plantilla de tests de invariantes con P0–P6 y
  ejecución local contra el vault en alcance de un programa.
  - **Decisión día 14:** sin Foundry, la línea se queda en triaje (valor limitado) y se evalúa abandonarla.
- **Semana 3.** Hipótesis con Claude, con tope diario, solo sobre cambios "alta". Cada hipótesis se
  registra y se intenta reproducir con un test.
- **Día 30.** Con 0 hipótesis reproducibles en 20 o más investigadas, se cambia de especialidad o se abandona.

## Qué falta para un primer informe válido

1. Un programa activo, verificado por el dueño, con un vault en alcance.
2. Foundry en la PC (etapa D), para traducir las propiedades a tests contra el código real.
3. Un test local que falle en el código en alcance y muestre un efecto económico concreto.
4. La comprobación contra auditorías previas, problemas conocidos y exclusiones.
5. El expediente: programa y versión, archivo y línea, causa raíz, precondiciones, test reproducible,
   esperado contra observado, impacto, límites, evidencia, severidad prudente y requisitos de envío.

Lo envía y lo firma el dueño.
