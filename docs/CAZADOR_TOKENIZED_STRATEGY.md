# Cazador de TokenizedStrategy (Yearn V3)

Estado: **escrito y verificado con forge en la PC** (28-oct; arreglado el 30-oct). Pasa 256×500 sin falsos positivos
ni reversiones en sus cuatro variantes (con las semillas `0x2a` y `0x3` y con `validate` sobre el repo entero), y las
39 mutaciones de referencia se detectan. La campaña profunda (512×1500) pasó sin leyes violadas. Sus 11 reversiones
del handler venían de acciones infladas hasta desbordar, en el modelo y en TokenizedStrategy, y están arregladas
(sección 6). **No hay hallazgos.**

## 1. Qué versión y qué alcance

- **Programa:** Yearn Finance en Immunefi (en el catálogo, `in_scope` y `verified_by_owner`). La página de alcance
  (actualizada el 25-jul-2026) lista **Tokenized Strategy V3.1.0** en `0x310f5Db015E9d6E542fd41bd4542640790791e76`
  (desde el 23-jun-2026) y la 3.0.4 en `0xD377919FA87120584B21279a491F82D5265A139c`. La 3.1.1, que la documentación
  de Yearn da como la última, no figura en el alcance; su `TokenizedStrategy.sol` difiere de la 3.1.0 solo en
  `API_VERSION`.
- **Versión probada: `v3.1.0` (`8c8929f`).** El `src/TokenizedStrategy.sol` verificado en Etherscan para
  `0x310f…1e76` tiene el mismo SHA-256 que el del tag. El `BaseStrategy` del tag apunta a esa dirección; el harness
  despliega la implementación localmente y copia su código ahí (`vm.etch`), con una fábrica de prueba.
- **Por qué esta versión:** la 3.1.0 reescribió la contabilidad (650 líneas de `TokenizedStrategy.sol`) y las
  auditorías del repo son anteriores (v3.0.x). Lo nuevo es exactamente lo que el cazador modela: el devengamiento en
  vivo ("constant accrual"), el pestillo por bloque, el piso de 1e3 acciones y la quema de acciones bloqueadas ante
  una pérdida en vivo.

## 2. Modelo

Estado crudo (leído con `vm.load` del slot `yearn.base.strategy.storage`, no de las vistas): `L` = `lastTotalAssets`,
`LA` = `lastAccrual`, `S` = `totalSupply` crudo, `B` = saldo de la propia estrategia (el **buffer** de acciones
bloqueadas), `R` = `profitUnlockingRate`, `D` = `fullProfitUnlockDate`, `LR` = `lastReport`, comisión φ (bps),
`T` = `profitMaxUnlockTime`, pausa y apagado.

- **Desbloqueo:** `u = R·(t − LR)/10¹²` si `D > t`; `u = B` si `0 < D ≤ t`; si no, 0. Suministro efectivo `s = S − u`.
- **Dos modos.** Por defecto `strategyTotalAssets()` devuelve `L` (contabilidad por reporte, como la v3.0.4). Si la
  estrategia la sobreescribe con una estimación en vivo `A` (solo lectura), toda escritura **devenga** antes
  (`_accrue`), una vez por bloque (`LA = t`):
  - ganancia `P = A − L`: con `s < 1e3` se acuña a `0x…dEaD` (`⌈P·s/L⌉`, o `A` si `L = 0`) y no hay comisión; si no,
    la comisión `f = ⌊P·φ/10⁴⌋` se acuña al **PPS nuevo**, `⌊f·s/(A − f)⌋` acciones, y el protocolo se lleva su
    parte de esas acciones. La ganancia en vivo no se bloquea;
  - pérdida `ℓ = L − A`: se queman las desbloqueadas y `min(B − u, ⌊ℓ·s/L⌋)` bloqueadas, y el cronograma se re-siembra
    (`LR = t`, `R = B'·10¹²/(D − t)`).
- **Vistas:** `_simulatedTotals` simula ese devengamiento sin escribir; con el bloque ya sincronizado o durante un
  callback (`entered`) devuelve `(s, L)`. Todas las conversiones, previews y max* salen de ahí; `totalSupply()` es
  `s` (sin la comisión simulada).
- **Reporte** (keeper): devenga, cosecha (`harvestAndReport`), y con ganancia `P` bloquea `⌊P·s/L⌋` acciones menos
  las de comisión (al PPS viejo si `T ≠ 0`), neteando las desbloqueadas; con pérdida quema como arriba. El nuevo
  período es el promedio ponderado `(D − t)·(B − bloqueadas nuevas) + bloqueadas nuevas·T` sobre `B`, y
  `R = B·10¹²/período`.
- **Usuarios:** deposit `⌊a·s/L⌋`, mint `⌈x·L/s⌉`, withdraw `⌈a·s/L⌉`, redeem `⌊x·L/s⌋` (1:1 con `s = 0`); si
  `_freeFunds` no libera todo, la diferencia es una pérdida del que retira (con su `maxLoss`) y `L` baja lo pedido.

## 3. Leyes (exactas, en 512 bits, contra el estado crudo)

| Ley | Qué exige |
|---|---|
| Y-TA-1 | `lastTotalAssets` y `lastAccrual` exactos después de cada operación, y lo que devuelve `report()` |
| Y-SUP-1 | `totalSupply` crudo y cada saldo exactos, acciones muertas del piso incluidas |
| Y-LOCK-1 | buffer, `profitUnlockingRate`, `fullProfitUnlockDate` y `lastReport` exactos; lo desbloqueado nunca pasa al buffer |
| Y-FEE-1 | acciones de comisión de desempeño y del protocolo exactas (en vivo y en el reporte) |
| Y-INF-1 | conversiones de los usuarios exactas: acciones acuñadas y quemadas, activos cobrados y pagados, pérdida del retiro |
| Y-INF-2 | el precio simulado no baja (exacto, `a'·s ≥ a·s'`) con ninguna operación ni con el paso del tiempo, salvo una pérdida o el redondeo del piso; cuando entra ganancia en vivo, a lo sumo por el piso de las acciones de comisión (`a'·(s + 1) ≥ a·s'`); el sándwich del reporte en un bloque no gana más que una acción |
| Y-VIEW-1 | vistas exactas contra el modelo (totales, conversiones, previews, max*, getters) y **cada preview es la ejecución** |
| Y-REENT-1 | durante los callbacks (`deployFunds`, `freeFunds`, cosecha, `tend`, retiro de emergencia) las vistas quedan congeladas en el estado previo |
| Y-FUNDS | movimiento exacto del activo: ociosos, fuente, cosecha |
| Y-LIVE | cada operación pasa si y solo si el modelo dice que pasa (pausa, apagado, max*, cero acciones, maxLoss, roles) |
| Y-LEDGER | Σ saldos crudos = `totalSupply` crudo; sin fecha de desbloqueo no hay buffer |

## 4. Demostraciones

**Las vistas son la ejecución.** En el mismo bloque, `_accrue` deja `(s, L)` igual a lo que simula
`_simulatedTotals`: usa las mismas funciones con los mismos argumentos, y en la rama de pérdida quema `u` más las
bloqueadas y re-siembra con `LR = t`, así que lo desbloqueado vuelve a 0 (si `D > t`) o el buffer queda vacío (si
`D ≤ t` se quemó entero). Por eso Y-VIEW-1 exige igualdad, no una cota.

**Y-INF-2 para los usuarios (sin excepciones).** Con los totales sincronizados `(s, L)`, `s > 0`:
deposit `(L + a)/(s + ⌊a·s/L⌋) ≥ L/s`; mint cobra `⌈x·L/s⌉ ≥ x·L/s`; withdraw deja `(L − a)/(s − ⌈a·s/L⌉) ≥ L/s`
(con pérdida del retiro `L` baja igual lo pedido); redeem deja `(L − ⌊x·L/s⌋)/(s − x) ≥ L/s`. El devengamiento previo
solo realiza lo que la simulación ya mostraba.

**El reporte no baja el precio con ganancia.** Con `T ≠ 0` las acciones nuevas en total (comisión más bloqueadas) son
`⌊P·s/L⌋` y las desbloqueadas que se queman ya estaban fuera de `s`: `(L + P)/(s + ⌊P·s/L⌋) ≥ L/s`. Con `T = 0` solo
se acuña la comisión al PPS nuevo. **La comisión en vivo tampoco:** `A/(s + ⌊f·s/(A − f)⌋) ≥ (A − f)/s ≥ L/s` porque
`f ≤ P/2`. Las excepciones son las pérdidas (que el buffer cubre solo hasta lo bloqueado) y el piso, que redondea
hacia arriba las acciones muertas y puede bajar el precio menos que el valor de una acción.

**Cuando entra ganancia en vivo, el piso de la comisión.** Entre dos estimaciones `A ≤ A'` del mismo bloque (sin
operación de por medio), el precio simulado `p(A) = A/(s + ⌊f·s/(A − f)⌋)` no es monótono al wei: cuando la comisión
`f = ⌊(A − L)·φ/10⁴⌋` sube 1 wei, el piso puede saltar una acción entera, que vale más que 1 wei si el PPS pasa de 1.
Pero `p(A) ≥ (A − f)/s`, y `A − f` no baja (`f` sube a lo sumo 1 por wei con `φ ≤ 50 %`), así que
`p(A') ≥ (A − f)/s > A/(s + ⌊f·s/(A − f)⌋ + 1)`: con `(s_b, a_b)` y `(s_a, a_a)` los totales simulados antes y
después, `a_a·(s_b + 1) ≥ a_b·s_a`. El piso siempre deja al receptor de la comisión por debajo de lo que le
corresponde; lo que baja el precio es que esa diferencia a favor de los tenedores se achica, en menos de una acción. No
es un hallazgo: es redondeo acotado y a favor del vault. La primera campaña completa lo encontró con la ley estricta
(una ganancia de 2 wei con comisión activa); por eso esa ley vale con la cota para estas acciones y estricta para todo
lo demás.

**El período del reporte nunca es 0.** Sea `B'` el buffer después del reporte y `b` lo bloqueado en él (0 con
pérdida). Si `D > t`, el numerador es `(D − t)(B' − b) + b·T ≥ B'` (con `b > 0` es `T ≥ 1`: con `T = 0` no se bloquea y
el buffer está vacío). Si `0 < D ≤ t`, todo el buffer estaba desbloqueado y se quemó (neto), así que `B' = b` y el
período es `T`. Si `D = 0`, el buffer es 0 (solo crece en un reporte, que fija `D`, y `D` vuelve a 0 solo con el
buffer vacío), y otra vez `B' = b`. La división por el período no falla: el DoS del reporte que Statemind encontró en
el VaultV3 de 2024 no aplica acá. Y-LEDGER verifica la premisa (`D = 0 ⇒ B = 0`) y Y-LIVE que el reporte pase.

**Sándwich del reporte en un bloque.** Depósito, reporte con ganancia y canje en el mismo bloque, con `T ≠ 0`: la
ganancia queda bloqueada y el que entra y sale cobra a lo sumo lo que valían sus acciones apenas entró, más el valor
de una acción (el piso de `⌊P·s/L⌋` puede subir el PPS menos que eso). Se mide desde ahí y no desde lo depositado:
con suministro 0 el depósito es 1:1 (como dice el código) y se queda con lo que haya en la estrategia, y eso no viene
del reporte. Con `T = 0` la ganancia es inmediata por diseño (la SPECIFICATION lo advierte).

## 5. Harness

`local/nexus/secresearch/harness/yearn__tokenized-strategy/`:

- **`NexusTokenizedStrategyHunter.sol`**: la estrategia de prueba sobre `BaseStrategy` v3.1.0 (con `live` sobreescribe
  `_strategyTotalAssets()` con ociosos + fuente; sin `live` usa la de `BaseStrategy`), la fuente de rendimiento
  (estimación que cuenta la pérdida pendiente y no las recompensas pendientes, retiro hasta lo líquido, y en cada
  depósito, retiro o cosecha lee las vistas de la estrategia), la fábrica de prueba, el modelo y las leyes.
- **`NexusTokenizedStrategyInvariant.t.sol`**: el handler y cuatro variantes: en vivo con comisión de desempeño 10 %;
  en vivo con 20 % y protocolo 10 %; por reporte con 10 % y protocolo 5 %; 6 decimales en vivo sin comisión (para que
  el suministro baje del piso). Acciones: deposit, deposit de todo el saldo, mint, withdraw y redeem con las dos
  firmas y maxLoss 0, 1, 100 y 10.000 bps, transferencias; ganancia y pérdida en vivo, recompensa y pérdida
  pendientes, donación a la estrategia, liquidez y perillas; report y tend; comisión, receptor, tiempo de desbloqueo (0,
  recortado a uint32 y normal), pausa por cada rol, apagado, retiro de emergencia, comisión del protocolo; saltos de
  reloj (justo en la fecha de desbloqueo o un segundo antes); y las secuencias bloqueo-y-pérdida, vaciado total y
  sándwich del reporte. Más cuatro escenarios deterministas: el piso con una donación grande, la pérdida en vivo
  cubierta por el buffer, la recuperación tras una pérdida total con suministro chico y el sándwich.
- Montos de hasta un millón de unidades del activo por acción, escalados por sus decimales, y un cuarto de las veces
  polvo (1 a 1e4).
- Compila sin `via_ir`, con los ajustes del repo (solc 0.8.18, 200 runs, paris).

Para iterar: `NEXUS_PERFIL=tokenized-strategy` en [tools/forge_v2](../tools/forge_v2/README.md) arma el proyecto
reducido (TokenizedStrategy, BaseStrategy, interfaces, la librería, OpenZeppelin 4.9.5 y forge-std 1.5.2). La
referencia es `validate` sobre el repo entero con `"aislado": true` (los tests del repo viven en `src/test` y se
compilan con `src`; el aislado evita los scripts).

**Verificación del harness original (28-oct, forge 1.8.6 en la PC; la del arreglado está en la sección 6).** En el
proyecto reducido, las 4 variantes pasan 256×500 sin falsos
positivos con las semillas `0x2a` y `0x3`, con 0 reversiones (128.000 llamadas por variante y semilla), y los 4
escenarios pasan. La referencia, con `validate` sobre el repo entero (`v3.1.0`, compilación aislada, semilla
`0xdf5a04a2c65ea82a`), da 8 de 8 con 0 reversiones (112 s de compilación y 2.280 s de tests). En la última corrida de
cada variante (las dos semillas y `validate`): de 18.000 a 23.000 leyes evaluadas en vivo y de 14.000 a 16.500 por
reporte; 3 a 7 devengamientos en vivo con comisión, 21 a 26 con pérdida y hasta 13 que quemaron acciones bloqueadas;
21 a 27 reportes con ganancia y 10 a 15 con pérdida (6 a 9 y 5 a 12 en la variante por reporte); hasta 53 operaciones
en un bloque ya sincronizado con un cambio pendiente; 69 a 133 rechazos predichos; 44 a 195 callbacks con las vistas
verificadas; hasta 11 sándwiches del reporte. El piso de acciones muertas aparece hasta 3 veces por corrida, y los
retiros con pérdida para el usuario solo 0 a 2: hace falta iliquidez sin el límite de retiro, y el cazador los
recorre poco.

En el camino, el cazador se corrigió dos veces, y ninguna de las dos fue una falla de TokenizedStrategy. Primero, la
ley del precio era estricta también cuando entra ganancia en vivo, y el piso de las acciones de comisión la rompe por
menos de una acción (§4). Segundo, el sándwich se medía desde lo depositado, y con suministro 0 el depósito se queda
con lo que haya en la estrategia (§4).

**Mutaciones de referencia** ([tools/forge_v2/mutaciones_tokenized_strategy.json](../tools/forge_v2/mutaciones_tokenized_strategy.json);
64×200, semilla `0x2a`, con `NEXUS_PERFIL=tokenized-strategy`; la tabla es la de la batería del 30-oct, con el
harness arreglado de la sección 6): las 39 se detectan. T28 la detecta solo el escenario
de la recuperación tras una pérdida total, que se sumó para eso: con suministro 0 la mutación da las mismas
conversiones, y el fuzzer casi no llega a una pérdida total con suministro chico.

| Mutación | Variantes que la ven | Leyes |
|---|---|---|
| T1 `deposit` redondea las acciones hacia arriba | las 4 y los escenarios | Y-SUP-1, Y-INF-1, Y-INF-2, Y-VIEW-1 |
| T2 `mint` redondea los activos hacia abajo | las 4 | Y-TA-1, Y-INF-1, Y-INF-2, Y-VIEW-1, Y-FUNDS |
| T3 `withdraw` redondea las acciones hacia abajo | las 4 | Y-SUP-1, Y-INF-1, Y-INF-2, Y-VIEW-1, Y-LIVE |
| T4 `redeem` redondea los activos hacia arriba | las 4 | Y-TA-1, Y-INF-1, Y-INF-2, Y-VIEW-1, Y-FUNDS |
| T5 la pérdida del retiro se socializa | las 4 | Y-TA-1 |
| T6 el depósito suma un activo de más | las 4 y los escenarios | Y-TA-1 |
| T7 las acciones muertas del piso redondean hacia abajo | en vivo, con protocolo, 6 decimales | Y-SUP-1, Y-REENT-1, Y-TA-1, Y-INF-1, Y-VIEW-1, Y-FUNDS |
| T8 el piso de suministro en el devengamiento es 1 y no 1e3 | en vivo, con protocolo, 6 decimales y los escenarios | Y-LIVE, Y-SUP-1, Y-INF-1, Y-VIEW-1, Y-REENT-1, Y-FEE-1 |
| T9 la comisión en vivo se cobra al PPS viejo | en vivo, con protocolo, 6 decimales | Y-SUP-1, Y-LOCK-1, Y-FEE-1, Y-INF-2, Y-REENT-1 |
| T10 la parte del protocolo suma una acción | las 4 | Y-FEE-1 |
| T11 las acciones de comisión redondean hacia arriba | las 4 | Y-SUP-1, Y-FEE-1, Y-LOCK-1 |
| T12 la pérdida en acciones redondea hacia arriba | las 4 y los escenarios | Y-SUP-1, Y-LOCK-1, Y-REENT-1, Y-VIEW-1 |
| T13 la pérdida no quema lo ya desbloqueado | las 4 y los escenarios | Y-SUP-1, Y-LOCK-1, Y-INF-1, Y-INF-2, Y-VIEW-1, Y-REENT-1 |
| T14 la re-siembra tras una pérdida no mueve `lastReport` | en vivo, con protocolo, 6 decimales y los escenarios | Y-SUP-1, Y-LOCK-1, Y-INF-1, Y-VIEW-1, Y-REENT-1 |
| T15 la re-siembra divide por un segundo de más | en vivo, con protocolo, 6 decimales y los escenarios | Y-LOCK-1 |
| T16 el devengamiento con pérdida no re-siembra el cronograma | en vivo, con protocolo, 6 decimales y los escenarios | Y-SUP-1, Y-LOCK-1, Y-INF-1, Y-VIEW-1, Y-REENT-1 |
| T17 el reporte bloquea acciones redondeando hacia arriba | las 4 | Y-SUP-1, Y-LOCK-1, Y-INF-2 |
| T18 el reporte con bloqueo cobra la comisión al PPS nuevo | las 4 y los escenarios | Y-LOCK-1, Y-FEE-1, Y-SUP-1 |
| T19 el reporte no descuenta lo desbloqueado de lo que bloquea | las 4 | Y-SUP-1, Y-LOCK-1, Y-INF-2 |
| T20 el período de desbloqueo dura un segundo de más | las 4 y los escenarios | Y-LOCK-1 |
| T21 el promedio ponderado cuenta lo recién bloqueado como previo | las 4 | Y-LOCK-1 |
| T22 el desbloqueo lineal divide por 1e12 + 1 | las 4 y los escenarios | Y-SUP-1, Y-LOCK-1, Y-INF-1, Y-INF-2, Y-VIEW-1, Y-REENT-1 |
| T23 vencida la fecha no se desbloquea nada | las 4 | Y-SUP-1, Y-LOCK-1, Y-VIEW-1, Y-REENT-1 |
| T24 las vistas ignoran el pestillo del bloque | en vivo, con protocolo, 6 decimales y los escenarios | Y-VIEW-1 |
| T25 las vistas ignoran el callback en curso | en vivo, con protocolo, 6 decimales | Y-REENT-1 |
| T26 la simulación cobra la comisión al PPS viejo | en vivo, con protocolo, 6 decimales | Y-VIEW-1 |
| T27 la simulación no descuenta la quema de bloqueadas | en vivo, con protocolo, 6 decimales y los escenarios | Y-VIEW-1 |
| T28 la simulación sin baseline no aplica el piso | los escenarios | Y-VIEW-1 |
| T29 `maxWithdraw` ignora el límite de la estrategia | las 4 | Y-VIEW-1 |
| T30 `maxDeposit` ignora la pausa | las 4 | Y-VIEW-1 |
| T31 el desbloqueo en 0 no quema el buffer | las 4 | Y-SUP-1, Y-LOCK-1, Y-LEDGER |
| T32 la comisión nueva es retroactiva | las 4 y los escenarios | Y-TA-1, Y-LOCK-1, Y-SUP-1 |
| T33 el depósito coloca solo lo depositado | las 4 y los escenarios | Y-FUNDS, Y-REENT-1 |
| T34 el reporte no mueve `lastReport` | las 4 y los escenarios | Y-LOCK-1, Y-INF-2 |
| T35 el reporte con pérdida no la cubre con el buffer | las 4 | Y-SUP-1, Y-LOCK-1, Y-LIVE |
| T36 se puede transferir a la estrategia | las 4 | Y-LIVE |
| T37 `balanceOf` de la estrategia no descuenta lo desbloqueado | las 4 y los escenarios | Y-VIEW-1 |
| T38 el devengamiento no mueve `lastAccrual` | las 4 y los escenarios | Y-TA-1 |
| T39 `maxLoss` solo se controla cuando es 0 | las 4 | Y-LIVE |

"Las 4" son las variantes de invariantes; las mutaciones del devengamiento en vivo no aplican a la variante por
reporte. Las leyes de más en algunas filas son el efecto en cadena de la mutación.

## 6. La campaña profunda y el dominio del cazador (30-oct)

**La campaña.** 512×1500 (768.000 llamadas por variante, semilla `0x4a9cb1e5a489dc29`, 28-oct): las cuatro variantes
y los escenarios en verde, sin ninguna ley violada. Pero el handler revirtió 11 veces en la variante con protocolo
(`lockThenLose` 6 y `report` 5), y esas secuencias quedaron sin verificar. Con `fail_on_revert` y la misma semilla
no se reprodujeron.

**La causa: acciones infladas, no TokenizedStrategy.** Se reprodujo el 30-oct con `fail_on_revert` y otras semillas,
como las del Vault V3 ([CAZADOR_VAULT_V3.md](CAZADOR_VAULT_V3.md) §6): cuatro copias de la variante con protocolo a
64×1500. La de la semilla `0x404` revirtió con `panic 0x11` en un `report()`, en la llamada 361 de una corrida. La
secuencia, repetida con trazas, muestra:
- la estrategia con 1,1e45 acciones contra 2.159 wei de activo (`convertToShares(1e18)` daba 5,2e59);
- al reportar una ganancia grande, el modelo calcula la tasa de desbloqueo con el buffer × `MAX_BPS_EXTENDED`
  (unas 1,5e65 × 1e12), que pasa de 2^256.

TokenizedStrategy hace la misma cuenta (`totalLockedShares * MAX_BPS_EXTENDED`) con aritmética chequeada y también
revierte: **no es un hallazgo**. El mecanismo es el del vault. Una pérdida casi total en vivo deja el precio por acción
cerca de 0, y cada depósito siguiente multiplica el suministro.

**El arreglo**, el mismo que en el Vault V3:
- **El modelo a prueba de desbordes:** el handler llama con una llamada externa al modelo de las entradas, las
  salidas, el reporte y el devengamiento de los setters (`setPerformanceFee`, `setPerformanceFeeRecipient` y
  `setProfitMaxUnlockTime`). Si una cuenta desborda o divide por cero, la operación se espera rechazada y Y-LIVE
  controla que TokenizedStrategy revierta.
- **El dominio:** `totalSupply` crudo hasta 2^128; la operación que lo pasaría se saltea. Con la comisión de hasta
  50 %, el suministro simulado de las vistas a lo sumo se duplica, así que ninguna vista ni ley del cazador desborda.
- **Dos métricas nuevas:** las operaciones cuyo modelo desbordó y las salteadas por el dominio.

**Prueba de regresión:** `test_inflacion_de_acciones_no_tumba_al_cazador`, en los escenarios. Son seis vueltas de
depósito, una pérdida en vivo que deja 1 de activo en la fuente y otro bloque; después, una recompensa y el reporte.
Con el harness viejo revierte (el `mulDiv` del modelo desborda); con el arreglado pasa.

**Verificación del harness arreglado (30-oct, forge 1.8.6 en la PC).**

- **Proyecto reducido:** las cuatro variantes pasan 256×500 con `0x2a` y `0x3`, sin falsos positivos ni reversiones
  (128.000 llamadas por variante y semilla). Pasan también los cinco escenarios, el de la regresión incluido: 9 de 9
  con cada semilla.
- **Referencia:** `validate` sobre el repo entero (`v3.1.0`, compilación aislada, 256×500, semilla
  `0x030681159d224858`) da 9 de 9 con 0 reversiones en 512.000 llamadas: 103 s de compilación y 2.565 s de tests.
- **Mutaciones:** las 39 de referencia se detectan (64×200, `0x2a`), cada una en las mismas variantes que antes. T32
  y T33 las ven además los escenarios, por la prueba nueva, y en algunas filas cambian las leyes de más (el efecto en
  cadena). La tabla de la sección 5 es la de esta batería.
- **Confirmación con `fail_on_revert`:** la variante con protocolo, cuatro copias a 64×1500 con semillas nuevas
  (`0x501` a `0x504`), da 384.000 llamadas sin ninguna reversión ni ley violada. A la tasa de la campaña, con el
  harness viejo se esperaban unas 5 o 6.
- **Cobertura de la última corrida de cada variante:** parecida a la de la verificación original. Con `0x3` hubo de
  21.000 a 22.600 leyes evaluadas en vivo y 17.100 por reporte, 25 a 26 reportes con ganancia, 124 a 194 callbacks
  verificados y 5 a 12 sándwiches. Con `0x2a` y en `validate`, las últimas corridas fueron algo más pobres (de 13.600
  a 19.800 leyes y hasta 4 sándwiches).
- **El borde:** en la última corrida de estas suites no hubo operaciones desbordadas ni salteadas. Sí aparecieron en
  una corrida corta de 8×300, donde una variante salteó 4 operaciones por el dominio.

## 7. Qué NO cubre

- El Vault V3 (Vyper 0.3.10) que usa las estrategias: su `process_report` lee `convertToAssets` de la estrategia, y con
  contabilidad en vivo ese valor incluye lo simulado. Es el paso siguiente natural, con `vyper` en el venv.
- Estrategias reales: la estimación en vivo de una estrategia puede ser manipulable (precios al contado); eso es del
  estratega y está fuera del alcance de TokenizedStrategy.
- Tokens con comisión por transferencia, con ganchos (ERC-777) o rebasables; `permit`; el cambio de management en dos
  pasos; varias estrategias sobre la misma implementación.
- La 3.0.4 (también en alcance): su contabilidad es la del modo por reporte, sin el pestillo ni el piso.
- `totalSupply` por encima de 2^128 (sección 6): ahí TokenizedStrategy y el modelo desbordan en las mismas cuentas.
