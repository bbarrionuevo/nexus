# Investigación de seguridad DeFi

Pedido del dueño del 26-oct-2026: investigar vulnerabilidades económicas y lógicas en protocolos DeFi
con programa de bug bounty **autorizado**, con pruebas locales y sin poner dinero. Ese mismo día el dueño
suspendió el bot de trading y dedicó el repo entero a esta línea. **No promete ingresos**: solo cuenta
una recompensa cuando se cobra. Las reglas están en [REGLAS.md](REGLAS.md).

## Decisiones de arquitectura

- **Python y git**, que la PC ya tiene, más Foundry y Vyper para la etapa D. Sin Docker, base de datos,
  servicios pagos ni nube nueva.
- **Límites en un archivo protegido** (`limits.py`): topes, verificación del alcance, carpeta de
  resultados y prohibiciones. Solo los cambia el dueño (R-9).
- **Los resultados son privados**: catálogo, clones y resultados en `NEXUS_HOME` (en la PC,
  `%LOCALAPPDATA%\nexus`). El repo es público, y un posible hallazgo publicado sería divulgar una
  vulnerabilidad sin reportar. El orquestador se niega a escribir dentro del repo (R-4).
- Se conserva del proyecto anterior la disciplina de evidencia: reglas fijadas de antemano, medir antes
  de afirmar, "la IA propone, el dueño decide" y rutas protegidas.

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
| D. Validación local con Foundry | `validate.py`: solo repos de programas verificados; clona fijado a un commit con submódulos; `forge build` + `forge test --json` con FFI apagado forzado y topes de tiempo; informe privado e historial | Implementado y verificado en la PC (26-oct) | Línea base de MetaMorpho `ded84e5`: compila en 350,7 s; 148 pasan · 0 fallan · 0 omitidos (354,2 s) |
| D'. Propiedades del vault en Foundry | `harness/morpho-org__metamorpho/`: la suite ERC-4626 de a16z y un test de invariantes con handler, en 3 variantes; `validate --harness` los copia al clon y los corre con una semilla nueva. Desde el 27-oct, con el cazador (`NexusVulnerabilityHunter.sol`) y una suite multi-mercado con gobierno | Implementado. Verificado en la nube **sin forge** (solc-js + EDR, el motor de tests de Hardhat 3). **Falta la primera corrida con forge en la PC** | 81/81 pasan en `ded84e5` con 4 semillas; detecta 7 de 7 mutaciones de referencia (abajo). Con el cazador: sin falsos positivos en 1,5 M de llamadas; detecta 21 de 21 mutaciones, también en Morpho Blue, contra 11 de 21 del harness original ([detalle](CAZADOR_METAMORPHO.md#verificación)) |
| Ciclo desatendido | `cycle.py`: una vez por disparo del Programador de tareas, con candado y tope de tiempo. Hace A–C, los harness con semilla nueva y hasta 2 líneas base vencidas, y escribe `ciclo.md` y `para_claude.md`. Este último trae las fallas y, desde el 27-oct, la cobertura de la última corrida: llamadas y reversiones por acción del handler, que forge reporta, y las métricas del cazador si forge incluye el log de `afterInvariant` | Implementado; lo registra el dueño con `tools/windows/registrar_ciclo.ps1` | Tests con reloj y validador simulados |
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

## Etapa D': propiedades e invariantes de MetaMorpho

Dos archivos de tests que `validate --harness morpho-org__metamorpho` copia a `test/nexus/` del clon, sobre
un entorno propio: Morpho Blue, un mercado con préstamos (LLTV 80 %), un mercado idle y el vault. Se corren
en tres variantes:

- sin comisión;
- con comisión del 25 %;
- con un activo de 6 decimales, es decir `DECIMALS_OFFSET` = 12.

1. **Propiedades de a16z** (`NexusMetaMorphoERC4626.t.sol`): las 26 de la suite `erc4626-tests`, que ya trae
   el repo, con `_delta_ = 0`. La suite original simula el rendimiento acuñando tokens en el contrato del
   vault, y eso en MetaMorpho no mueve `totalAssets`. Por eso la ganancia y la pérdida se hacen como pasarían
   de verdad:
   - ganancia: depósito en Morpho a nombre del vault, más interés pendiente (préstamo y paso del tiempo);
   - pérdida: deuda incobrable (el oráculo cae a 0 y se liquida sin repagar).
2. **Invariantes con handler** (`NexusMetaMorphoInvariant.t.sol`). Forge encadena depósitos, acuñaciones,
   retiros, rescates, transferencias, donaciones, préstamos, repagos, paso del tiempo, deuda incobrable y
   reasignaciones del allocator. Después de cada llamada verifica:
   - que `max*` no prometa de más: depositar, acuñar, retirar o rescatar el máximo no revierte;
   - que `preview*` no mienta a favor del usuario;
   - que el precio por acción no baje sin una pérdida;
   - que `convertToAssets` no valga menos que el precio de la especificación;
   - solvencia, suma de saldos y que el vault no retenga tokens.

**Cómo se verificó sin forge.** Foundry no se puede instalar en la nube de Claude, porque los hosts están
bloqueados. Sí se puede instalar EDR desde npm: es el motor de tests Solidity de Hardhat 3 y usa los mismos
cheatcodes. `tools/edr/` compila como forge (Morpho con 0.8.19, MetaMorpho con 0.8.21 y el harness con
0.8.26, via_ir) y ejecuta. Resultados:

- 81/81 pasan con 4 semillas, con 2.000 corridas de fuzz y 256×500 llamadas por invariante;
- las invariantes terminan con menos del 0,4 % de reversiones, o sea que no pasan en vacío.

Las mutaciones de referencia, cada una inyectada en una copia de MetaMorpho, tienen que romper algo:

| Mutación | La detecta |
|---|---|
| M1 `deposit` redondea acciones hacia arriba | a16z (`RT_deposit_redeem`) e invariantes (precio) |
| M2 `maxWithdraw` ignora la liquidez | solo invariantes (retirar el máximo revierte) |
| M3 `deposit` no actualiza `lastTotalAssets` (comisión sobre depósitos) | invariantes, variante con comisión |
| M4 `mint` redondea el costo hacia abajo | a16z (`RT_mint_withdraw`) |
| M5 `totalAssets` ignora el mercado idle | invariantes (precio tras reasignar) |
| M6 `redeem` redondea activos hacia arriba | a16z (`RT_redeem_deposit`, `RT_redeem_mint`) |
| M7 comisión calculada de más | invariantes (`convertToAssets` por debajo del precio exacto) |

**Lecciones:**

- **Falso positivo propio, corregido.** La primera versión medía el precio con `convertToAssets` y fallaba
  en la variante con comisión. Las acciones de comisión pendientes se redondean hacia abajo. Cuando ese
  redondeo salta una acción entera, el precio "devuelve" valor al receptor de comisiones. Con pocas acciones
  en circulación eso parecía una caída de hasta 1,5 %. No era un defecto de MetaMorpho. Se reprodujo la
  secuencia de 179 llamadas paso a paso, y ahora se mide el precio de la especificación:
  (totalAssets − comisión × interés pendiente + 1) / (totalSupply + acciones virtuales).
- **Versión de solc.** Con via_ir, la suite de a16z da "stack too deep" en solc ≤ 0.8.24. Por eso el
  adaptador exige `^0.8.26`, y forge baja ese compilador solo para ese archivo.

### Cazador de vulnerabilidades: contabilidad fantasma y leyes exactas (27-oct)

`NexusVulnerabilityHunter.sol` se hereda en el handler (la API no cambia). Cada acción queda envuelta en
`hunted(...)`, que toma una foto antes y otra después y evalúa las leyes de esa operación contra un modelo
independiente de los `view` del vault: estado crudo de Morpho en un solo `extSloads`, aritmética propia, L, colas,
topes y timelocks fantasma, y libros por tenedor y de comisiones. Caza tres familias:

- inflación y redondeo;
- desincronización de comisiones;
- fugas por deuda incobrable o reasignación entre mercados.

`NexusMetaMorphoHunter.t.sol` agrega el entorno que faltaba:

- 4 mercados (uno sin habilitar) con topes que se alcanzan y colas en distinto orden;
- gobierno con timelock, comparado contra la predicción del cazador;
- saltos a la frontera exacta de cada timelock;
- macros de ataque: inflación, comisión relámpago, ciclo de reasignaciones, tokens sueltos y fronteras de tope y de
  remoción.

Modelo, ecuaciones, leyes, auditoría del handler anterior e integración: [CAZADOR_METAMORPHO.md](CAZADOR_METAMORPHO.md).

**Qué NO cubre todavía:**

- tokens no estándar (con comisión por transferencia o con callbacks);
- reentrada;
- `permit` y `multicall`;
- préstamos flash;
- una tasa de interés que cambie con el uso;
- el harness de Vault V2 (las ecuaciones de la adaptación están en CAZADOR_METAMORPHO.md).

Son los próximos frentes, en ese orden de valor.

## Límites de seguridad

Ver [REGLAS.md](REGLAS.md) (R-1 a R-10). Se hacen cumplir con `limits.py` y `tests/test_limits.py`
(protegidos).

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
# Verificación local completa (sintaxis, lint si hay ruff, tests, rutas protegidas, método):
..\.venv\Scripts\python -m nexus.devcheck

# Autoverificación del método de invariantes:
..\.venv\Scripts\python -m nexus.secresearch.run --selfcheck

# Corrida real: usa %LOCALAPPDATA%\nexus\secresearch.yaml (programas verificados por el dueño):
..\.venv\Scripts\python -m nexus.secresearch.run
```

El informe queda en `%LOCALAPPDATA%\nexus\secresearch\secresearch.md`.

Validación local con Foundry (etapa D), solo sobre repos de programas verificados:

```powershell
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --match-path test/ERC4626Test.sol
```

El informe queda en `%LOCALAPPDATA%\nexus\secresearch\validate\` y los clones en `%LOCALAPPDATA%\nexus\work\`.
La primera corrida de cada repo es su **línea base**: un test que falla ahí no es una vulnerabilidad.

Propiedades e invariantes de nexus (etapa D'). Cada corrida usa una semilla nueva, que queda en el informe
junto con el comando para reproducirla:

```powershell
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho
# más intensidad (por defecto: fuzz 1000, invariantes 256x500), o repetir una corrida exacta:
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho --fuzz-runs 5000 --invariant-depth 1000
..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho --ref <commit> --seed <semilla>
```

Ciclo desatendido: corre todo lo anterior una vez por día, sin ventana y con topes. Se registra una sola
vez, desde `%USERPROFILE%\nexus`:

```powershell
powershell -ExecutionPolicy Bypass -File tools\windows\registrar_ciclo.ps1      # todos los días a las 03:17
Start-ScheduledTask nexus-ciclo                                                  # probarlo ahora
```

Los resultados quedan en `%LOCALAPPDATA%\nexus\secresearch\`:

- `ciclo.md`: el último ciclo;
- `para_claude.md`: líneas base, corridas y fallas distintas acumuladas, para pegarle a Claude;
- `ciclo.log`: el progreso.

Para quitarlo: `Unregister-ScheduledTask nexus-ciclo -Confirm:$false`.

### Iteración PC ↔ Claude

La sesión de Claude en la nube no llega a la PC. Los resultados nunca van al repo, que es público (R-4). El ciclo
de mejora es:

1. **Traer el código a la PC.** Desde `%USERPROFILE%\nexus`: `git fetch` y `git checkout <rama>` para probar una rama
   sin fusionar, o `git pull` en `main` después de fusionar el PR.
2. **Correr.**
   ```powershell
   ..\.venv\Scripts\python -m nexus.secresearch.validate morpho-org/metamorpho --harness morpho-org__metamorpho
   ```
   La primera vez conviene a mano, para ver el tiempo de compilación. Después alcanza con el ciclo programado.
3. **Devolverle a Claude `%LOCALAPPDATA%\nexus\secresearch\para_claude.md`.** Se puede pegar en la sesión, o abrir
   Claude Code en la PC, en la carpeta de nexus (app de escritorio o `claude remote-control`), que lo lee directo y
   puede reproducir con forge. Trae:
   - las fallas distintas, con su ley (`H-...`), el contraejemplo y la semilla;
   - la cobertura de la última corrida: llamadas y reversiones por cada acción y macro del handler (métricas de
     forge) y, si la versión de forge incluye el log de `afterInvariant`, las métricas del cazador.
4. **Qué hace Claude con eso.**
   - Una falla con código `H-...` se reproduce con la misma semilla y se clasifica: error del harness (se corrige) o
     candidato (se aísla en un test mínimo y se revisa contra auditorías previas, etapas E y F).
   - Sin fallas, las métricas dicen hacia dónde empujar: por ejemplo, si una macro casi nunca corrió o revierte
     siempre, si las reversiones pasan del 5 % o si nunca hubo depósitos con 0 acciones.

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

El dueño leyó los reglamentos y marcó los 3 programas (`in_scope` y `verified_by_owner` en `true`) en su
catálogo privado, el 26-oct.

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
2. ~~Foundry en la PC~~ (hecho el 26-oct: línea base de MetaMorpho en verde). Propiedades e invariantes
   contra el código real (etapa D'): listas para MetaMorpho; faltan Morpho Vault V2, Yearn V3 y Euler v2.
3. Un test local que falle en el código en alcance y muestre un efecto económico concreto.
4. La comprobación contra auditorías previas, problemas conocidos y exclusiones.
5. El expediente: programa y versión, archivo y línea, causa raíz, precondiciones, test reproducible,
   esperado contra observado, impacto, límites, evidencia, severidad prudente y requisitos de envío.

Lo envía y lo firma el dueño.
