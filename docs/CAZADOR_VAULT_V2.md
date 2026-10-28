# Cazador de vulnerabilidades para Morpho Vault V2

Modelo formal y leyes exactas para el harness de `morpho-org/vault-v2` (línea base `04e5f4a9`; hasta `6047e158` solo
cambió `MidnightAdapter`, fuera de alcance), al estilo del de MetaMorpho ([CAZADOR_METAMORPHO.md](CAZADOR_METAMORPHO.md)).
Estado: **variante A verificada con forge en la PC** (27-oct), con capital asignado de verdad en el adapter, las leyes
del precio por acción (V-INF-2), de realización de pérdidas (V-LOSS-1, V-LOSS-2), de `forceDeallocate` (V-FD-1) y de
los topes (V-CAP-1); y **variante B** (el adapter real sobre Morpho Blue, leyes V-ADP, y el Blue Public Allocator,
leyes V-PA, con el adapter de liquidez y forceDeallocate sobre Blue) escrita y verificada el mismo día, igual que el
**gobierno con timelock** (V-GOV-1, en la variante A). Falta la cota V-BOUND como ley. La etapa E (duplicados) está
hecha y vive, privada, en `NEXUS_HOME/secresearch/etapa_e/morpho-org__vault-v2/`.

**Harness (variante A).** `harness/morpho-org__vault-v2/`: `NexusVaultV2Hunter.sol` (contabilidad fantasma, leyes V-...
y `NexusAdapterMock`) y `NexusVaultV2Invariant.t.sol` (el handler y tres variantes: sin comisión, con comisión de
performance y de gestión, y activo de 6 decimales).

- El adapter es `NexusAdapterMock`, que cumple la especificación de adapters de V2 (§5): su `realAssets` es su saldo
  del token y la `allocation` del vault es su posición. El handler le acredita rendimiento o le quita tokens, así que
  el fantasma conoce los activos reales exacto y las pérdidas alcanzan al capital asignado, no solo al rendimiento.
- Topes: arrancan en absoluto `1e30` en `id-0` e `id-1`, relativo `0,9` en `id-0` e `id-1` sin tope relativo
  (`WAD`), y el handler los sube y los baja (`setCap`: el curador los baja sin demora; subirlos pasa por el timelock,
  que en el harness es 0). Asigna dentro del tope efectivo, justo en el borde (en el tope, uno más, uno menos) y
  depositando y asignando en una misma transacción; V-CAP-1 compara cada intento con la predicción.
- `forceDeallocate`: penalidad de 1 % sin comisión, 2 % (el máximo) con comisión y 0,37 % con 6 decimales. El handler
  fuerza a nombre propio y de otro actor con allowance finita, y fuerza y sale en una misma transacción.
- Gobierno (V-GOV-1): el handler propone, ejecuta y revoca cambios con demora (comisiones y sus receptores, la
  penalidad, timelocks, abdicaciones, subidas de topes, alta y baja de un segundo adapter vacío y el registro de
  adapters), con timelocks iniciales distintos de 0, y una copia fantasma predice cada resultado. Ejecuta un segundo
  antes de la fecha y justo en ella, intenta lo revocado y, tras una abdicación, vuelve a proponer la función abdicada.
- Las secuencias de una sola transacción las hace `NexusV2Macro` (§4): forge 1.8.6 corre con `isolate = true` y cada
  llamada del handler al vault es una transacción aparte.
- Los montos de cada acción los **deriva** el cazador del cambio de estado observado (activos: el cambio de lo ocioso;
  acciones: el cambio de balance), no de los argumentos del handler: así una acción acotada a 0 es un no-op consistente.
- El fantasma no usa las vistas con devengamiento del vault (`totalAssets`, `previewX`, `accrueInterestView`); solo
  estado crudo (`_totalAssets`, `totalSupply`, `lastUpdate`, `maxRate`, las comisiones, `balanceOf`) y los activos
  reales desde el token y el adapter.
- Ninguna ley revierte: con `fail_on_revert = false`, un cazador que revierte esconde la violación como una reversión
  más. El motivo de una falla termina con todas las leyes que fallaron, por ejemplo `[leyes: V-TA-1 V-LOSS-1]`.
- `afterInvariant` informa la cobertura de la corrida: pérdidas realizadas, bajas de precio sin pérdida (solo puede
  haberlas por la comisión de gestión), asignaciones, desasignaciones y transferencias con efecto, forceDeallocate con
  monto, salidas tras forzar, allocate rechazados por los topes y aceptados justo en el tope, cambios de topes,
  depósitos con allocate en la misma transacción, y del gobierno: propuestas, ejecuciones que pasaron, intentos un
  segundo antes de la fecha, intentos rechazados como predijo el modelo y revocaciones.

**Verificación en la nube (sin forge), commit `04e5f4a9`, solc 0.8.28 + EDR (27-oct, versión anterior del harness).**
Las 3 variantes pasaban 256×500 sin falsos positivos con las semillas `0x2a` y `0x3` y detectaban 5 mutaciones de
referencia.

**Primera corrida con forge en la PC (27-oct, forge 1.8.6, `091e12d0`).** 3 de 3 en verde (semilla
`0xb256ab959b7e797b`, 384.000 llamadas), pero las métricas por acción mostraron dos acciones del handler que no corrían:

- `allocate` revertía el 98 %: el harness nunca subía el tope relativo, que vale 0 por defecto, y el vault exige
  `allocation ≤ ⌊firstTotalAssets · 0/W⌋`. El adapter nunca recibía capital, `deallocate` no movía nada y las pérdidas
  solo se comían rendimiento informado por el adapter.
- `transfer` revertía el 94 %: el `vm.prank(from)` lo consumía la lectura `vault.balanceOf(from)` dentro del argumento,
  y la transferencia salía del handler, que no tiene acciones.

Esas dos acciones explicaban el 15,8 % de reversiones (20.261 de 20.262 en la variante con comisión). Los depósitos no
revertían nunca: no había un tope de `uint128` en `_totalAssets`, como se suponía.

**Verificación con forge en la PC, harness corregido (27-oct).** En el proyecto reducido de
[tools/forge_v2](../tools/forge_v2/README.md): las 3 variantes pasan 256×500 sin falsos positivos con las semillas
`0x2a` y `0x3`, con **0 reversiones** en 384.000 llamadas por semilla. Por corrida de 500 llamadas hubo 11 a 25
pérdidas realizadas sobre capital asignado, 20 a 30 asignaciones, 30 a 34 desasignaciones y 28 a 34 transferencias con
efecto. En la variante con comisión, el precio bajó sin pérdida 14 y 27 veces (solo puede ser por la comisión de
gestión); en las otras dos, ninguna, como predice V-INF-2 (c). La referencia, con `validate` sobre el repo entero
(`6047e158`, semilla `0x8e4b379d1936e836`), también da 3 de 3 con 0 reversiones: 599 s de compilación y 677 s de tests.

**Mutaciones de referencia** ([tools/forge_v2/mutaciones.json](../tools/forge_v2/mutaciones.json); 64×200, semilla
`0x2a`, con forge sobre el proyecto reducido): las 13 se detectan, y cada ley nueva tiene al menos una que la dispara.
Se listan las leyes que fallaron en la primera llamada que rompió el invariante.

| Mutación | Variantes que la ven | Leyes |
|---|---|---|
| V1 `previewDeposit` al techo | las 3 | V-INF-1, V-INF-2 |
| V2 `previewMint` al piso | las 3 | V-INF-1, V-INF-2 |
| V3 `previewWithdraw` al piso | las 3 | V-INF-1, V-INF-2 |
| V4 `previewRedeem` al techo | las 3 | V-INF-1, V-INF-2 |
| V5 tope de tasa ignorado | las 3 | V-TA-1 (con comisión, también V-FEE-1 y V-LEDGER) |
| V6 performance sobre `newTotalAssets` | con comisión | V-FEE-1, V-INF-2, V-LEDGER |
| V7 pérdida diferida (`_TA` no baja a `R`) | las 3 | V-TA-1, **V-LOSS-1**, V-SOLV-1 |
| V8 pérdida exagerada (`TA' = 0,9·R`) | las 3 | V-TA-1, V-INF-2, **V-LOSS-1** |
| V9 gestión sobre el `_TA` previo | con comisión | V-FEE-1, V-INF-2, V-LEDGER |
| V10 acciones de performance al techo | con comisión | V-FEE-1, V-LEDGER |
| V11 acciones de performance sobre el total con comisiones | con comisión | V-FEE-1, V-LEDGER |
| V12 la pérdida quema una acción del receptor de comisión | con comisión | **V-LOSS-2**, V-LEDGER |
| V13 una acción de más al entrar | las 3 | V-INF-1, **V-INF-2** |

V10 y V11 mueven una acción por devengamiento: las ve V-FEE-1, que es bit a bit; V-INF-2 (a) tolera los dos pisos por
construcción, así que la ve solo cuando la primera llamada que falla acumula más de dos acciones de diferencia. Las que
solo ve la variante con comisión necesitan una comisión distinta de cero.

**V-FD-1 y V-CAP-1 (27-oct, con forge en el proyecto reducido).** Con `forceDeallocate`, los topes con su borde, los
cambios de topes y las secuencias de una transacción, las 3 variantes pasan 256×500 sin falsos positivos con las
semillas `0x2a` y `0x3`, con 0 reversiones. Por corrida de 500 llamadas hubo 30 a 38 forceDeallocate con monto, 26 a 30
salidas en la misma transacción, 62 a 68 allocate rechazados por los topes como predijo el modelo, 8 a 12 aceptados
justo en el tope, unos 25 cambios de topes, 27 a 41 depósitos con allocate en la misma transacción, 5 a 9 pérdidas
realizadas y 26 a 36 asignaciones. La referencia, con `validate` sobre el repo entero (`6047e158`, semilla
`0x2fef01ee4e27ce41`), da 3 de 3 con 1 reversión en 384.000 llamadas (un `mint` que costaba más que los fondos que el
handler le da al actor). Las 8 mutaciones nuevas se detectan, y la batería completa (21) también:

| Mutación | Variantes que la ven | Leyes |
|---|---|---|
| V14 penalidad de forceDeallocate al piso | las 3 | **V-FD-1** (con comisión y 6 decimales, también V-INF-2 y V-LEDGER) |
| V15 la penalidad sale del vault (hacia quien llama) | las 3 | **V-FD-1** |
| V16 la penalidad se cobra a quien llama y no a `onBehalf` | las 3 | **V-FD-1**, V-INF-2, V-LEDGER |
| V17 tope relativo contra el `_totalAssets` actual (se elude con un depósito de la misma transacción) | las 3 | **V-CAP-1** |
| V18 tope absoluto ignorado | las 3 | **V-CAP-1** |
| V19 tope relativo con desigualdad estricta (vivacidad) | las 3 | **V-CAP-1** |
| V20 la `allocation` suma los activos en vez del `change` | las 3 | **V-CAP-1** |
| V21 `firstTotalAssets` se pisa en cada devengamiento | las 3 | **V-CAP-1** |

V14 es el hallazgo Medium ya corregido de Spearbit 2025-05-19 (5.2.1, "rounding down in forceDeallocate"): V-FD-1 lo
vería si volviera.

Vault V2 es un ERC-4626 que delega el capital en *adapters*. Cada adapter reporta cuánto valen sus inversiones con
`realAssets()`; el vault devenga interés y realiza pérdidas a partir de esa suma. Es una contabilidad distinta a la de
MetaMorpho, así que el cazador necesita leyes nuevas.

## 1. Diferencias con MetaMorpho (lo que cambia el modelo)

- **No hay VIC ni `realizeLoss()`.** Las auditorías tempranas (competencia de Cantina `5938a924`, Zellic, primer
  Spearbit) describen un diseño viejo con esas piezas. El código en alcance no las tiene: el interés lo acota
  `maxRate` y la pérdida se realiza dentro de `accrueInterest`. Verificado: `grep vic|realizeLoss src/VaultV2.sol` → 0.
- **Devengamiento una vez por transacción**, con `firstTotalAssets` en storage *transient* como guardia.
- **Tope de tasa (`maxRate`)**: aunque los adapters reporten mucho más, `totalAssets` no sube más que el tope por
  unidad de tiempo. Es la defensa de V2 contra la inflación por donación.
- **Dos comisiones**: performance sobre el interés y management sobre `totalAssets · tiempo`. La de gestión puede
  bajar el precio de la acción aunque no haya pérdidas.
- **`forceDeallocate`**: cualquiera puede sacar capital de un adapter pagando una penalidad, que vuelve al vault.
- **`MathLib` es de una sola palabra** (sin 512 bits): el contrato exige `totalAssets, totalSupply < ~10³⁵`.

## 2. Modelo

Constantes: `W = 1e18`, `v = 10^max(0, 18 − decimales)` (shares virtuales), 1 activo virtual. Tope de tasa
`maxRate ≤ MAX_MAX_RATE = 200%/365d`. Comisiones `f_p ≤ 50 %`, `f_g ≤ 5 %/365d`. Penalidad `≤ 2 %`.

**Activos reales.** `R = balance(asset, vault) + Σ_a realAssets_a`. En el harness, `NexusAdapterMock` informa su
saldo del token (lo asignado más el rendimiento menos las pérdidas que le aplica el handler), que el fantasma conoce
exacto.

**Devengamiento** (`accrueInterestView`, con `_TA = _totalAssets`, `Δt = now − lastUpdate`):

$$\widehat{TA} = \min\!\left(R,\ \_TA + \left\lfloor \tfrac{\_TA\,\Delta t\,\text{maxRate}}{W}\right\rfloor\right),\qquad I = \widehat{TA} \ominus \_TA\ \text{(piso 0)}$$

$$F^p = \mathbb{1}[I>0]\left\lfloor \tfrac{I\,f_p}{W}\right\rfloor,\qquad F^g = \mathbb{1}[\Delta t>0]\left\lfloor \tfrac{\widehat{TA}\,\Delta t\,f_g}{W}\right\rfloor\quad(\text{cada una, solo si el receptor puede recibir shares})$$

$$\text{sinFees} = \widehat{TA} - F^p - F^g,\qquad \sigma^{p} = \left\lfloor \tfrac{F^{p}\,(T+v)}{\text{sinFees}+1}\right\rfloor,\qquad \sigma^{g} = \left\lfloor \tfrac{F^{g}\,(T+v)}{\text{sinFees}+1}\right\rfloor$$

El estado pasa a `_totalAssets = TA = widehat{TA}`, `T += σ^p + σ^g`, `lastUpdate = now`, y `firstTotalAssets = TA`
la primera vez de la transacción.

**Conversiones** (con `T⁺ = T + σ^p + σ^g`, las fees ya acuñadas):

$$\text{deposit: } s = \left\lfloor \tfrac{a\,(T^{+}+v)}{TA+1}\right\rfloor,\quad \text{mint: } a = \left\lceil \tfrac{s\,(TA+1)}{T^{+}+v}\right\rceil,\quad \text{withdraw: } s = \left\lceil \tfrac{a\,(T^{+}+v)}{TA+1}\right\rceil,\quad \text{redeem: } a = \left\lfloor \tfrac{s\,(TA+1)}{T^{+}+v}\right\rfloor$$

**forceDeallocate.** `penaltyAssets = ⌈assets · penalty/W⌉`; se cobra con `withdraw(penaltyAssets, vault, onBehalf)`.
Baja `TA` y `T`, pero los activos quedan en el vault: el precio sube para el resto (salvo redondeo).

## 3. Leyes (exactas y de 512 bits salvo donde el código no lo es)

Implementadas en la variante A: V-TA-1, V-INF-1, V-INF-2, V-FEE-1, V-LOSS-1, V-LOSS-2, V-FD-1, V-CAP-1, V-GOV-1,
V-LEDGER y V-SOLV-1; en la variante B, además, V-ADP-1..5 y V-PA-1..4. Las demás son el plan.

| Código | Ley | Caza |
|---|---|---|
| V-TA-1 | `TA' = min(R, _TA + ⌊_TA·Δt·maxRate/W⌋)`, bit a bit | Tope de tasa mal aplicado, interés inventado |
| V-TA-2 | El exceso `R − TA'` no se pierde: con `Δt` suficiente y `R` fijo, `TA` converge a `R` sin pasarse | Yield que se crea o se pierde |
| V-INF-1 | Las cuatro fórmulas de conversión del §2, en desigualdades justas y ajustadas | Redondeo invertido, dilución |
| V-INF-2 | **(a)** devengamiento: `q − 1 ≤ S + v ≤ q`, con `q = ⌊(A+1)(T+v)/(A − F^p − F^g + 1)⌋`; **(b)** operación: `(A'+1)(S+v) ≥ (A+1)(S'+v)`; **(c)** `(A+1)(T+v) ≥ (min(_TA, R) ⊖ F^g + 1)(S+v)`. Ver §4 | Dilución por una operación; comisiones que se llevan de más o de menos; precio que baja sin pérdida ni comisión de gestión |
| V-INF-3 | Una donación directa (subir `R`) sube `TA` a lo sumo `⌊_TA·Δt·maxRate/W⌋` por devengamiento | Inflación por donación |
| V-FEE-1 | `σ^p`, `σ^g` acuñadas = las del fantasma; `F^p` solo si `I>0`, `F^g` solo si `Δt>0` y receptor válido | Comisión sobre base equivocada |
| V-FEE-2 | `σ^p` nace solo del interés devengado; `σ^g` es la única que puede existir con `I = 0` | Comisión de performance sobre no-interés |
| V-LOSS-1 | Si `R < _TA` al empezar la transacción: `A = R` exacto y `σ^p = 0`. La pérdida se realiza entera en el primer devengamiento | Pérdida diferida, parcial u ocultada; comisión de performance sobre una pérdida |
| V-LOSS-2 | Con pérdida: fuera de quien opera ningún saldo cambia, los de comisión solo suben y `Σ saldos = T`; el precio baja según V-INF-2 (c) | Pérdida repartida en saldos (acciones quemadas o trasladadas) |
| V-FD-1 | forceDeallocate de `a` a nombre de `o`: `R' = R`, `TA' = A − pA` con `pA = ⌈a·p/W⌉`, a `o` se le queman `⌈pA(S+v)/(A+1)⌉` acciones (y la allowance baja eso), ningún tercero cambia; forzando y saliendo en la misma transacción, el retiro se paga al precio que dejó forceDeallocate. Ver §4 | Penalidad evadida, perdonada o cobrada a otro; pérdida evitada o trasladada |
| V-CAP-1 | `allocation = posición del adapter` en cada id; allocate pasa **si y solo si** `0 < absoluteCap`, `pos' ≤ absoluteCap` y, si `relativeCap ≠ WAD`, `pos' ≤ ⌊firstTotalAssets·relativeCap/W⌋`; `firstTotalAssets` es el primer total devengado no nulo de la transacción (un depósito de la misma transacción no lo agranda). Ver §4 | Topes ignorados o demasiado estrictos; tope relativo eludido en una transacción |
| V-GOV-1 | Gobierno con timelock (comisiones y receptores, penalidad, timelocks, abdicaciones, subidas de topes, alta y baja de adapters, registro de adapters), contra una copia fantasma: `submit` pasa **si y solo si** lo llama el curador y el dato no está pendiente, y fija `executableAt = t + timelock` (el de la función objetivo para `decreaseTimelock`); ejecutar pasa **si y solo si** está pendiente, llegó la fecha, la función no fue abdicada y se cumplen sus condiciones, y entonces el efecto es el valor propuesto y el pendiente se borra; `revoke` pasa si y solo si lo llama el curador o un centinela, y lo revocado no se ejecuta. Las comisiones y sus receptores devengan antes de cambiar (V-FEE-1 sobre la foto previa). Ver §4 | Timelocks que vencen antes o que miden la función equivocada, abdicaciones que no bloquean, propuestas o revocaciones sin rol, pendientes que se pisan o no se borran, comisiones retroactivas, topes de comisión, penalidad y topes ignorados, adapters fuera del registro |
| V-LEDGER | `T = Σ saldos` (incluidas las shares de fee); `T` = el esperado tras cada acción; sin pérdida, fuera de quien opera ningún saldo cambia y los de comisión solo suben | Shares creadas o destruidas por fuera |
| V-SOLV-1 | `⌊T⁺(TA+1)/(T⁺+v)⌋ ≤ R`: lo reclamable está respaldado por los activos reales | Insolvencia |
| V-BOUND | Las macros exigen `TA, T < ~10³⁵` antes de operar (el `mulDiv` de una palabra puede desbordar) | Falsos positivos por `Panic(0x11)` |
| V-ADP-1..5 | Variante B (adapter real sobre Blue): `realAssets` exacto contra Blue; allocations por mercado, adapter y colateral; acciones internas = posición en Blue; `marketIds` ⟺ allocation > 0; movimiento exacto en Blue con redondeo en `[−⌈p⌉, +1]`. Ver §4 | Adapter que informa de más o de menos, contabilidad de acciones o de allocations desviada, mercados olvidados |
| V-PA-1..4 | Blue Public Allocator: penalidad `⌈a·p/W⌉` exacta y al vault; flujo exacto en Blue; permisos y tope propio respetados; penalidad distinta o configuración sin rol revierten. Ver §4 | Penalidad evadida o desviada, reasignaciones sin permiso o por encima del tope |

## 4. Demostraciones: precio por acción (V-INF-2) y pérdidas (V-LOSS)

Notación, para cada acción del handler: `T` es `totalSupply` antes; `A` y `S` son `_totalAssets` y `totalSupply` justo
después del devengamiento, con las acciones de comisión ya acuñadas; `A'` y `S'`, después de la acción. El cazador los
**observa**: `A` es el `_totalAssets` final menos lo que entró por la acción (o más lo que salió) y `S` es el
`totalSupply` final sin las acciones del actor. `F^p` y `F^g` se evalúan sobre el `A` observado (§2) y
`N = A − F^p − F^g` es `newTotalAssetsWithoutFees`. El precio de una acción es `ρ = (A+1)/(S+v)`. Todas las
comparaciones son productos cruzados en 512 bits.

**V-INF-2 (b): ninguna operación baja el precio,** `(A'+1)(S+v) ≥ (A+1)(S'+v)`.

- deposit: `A' = A + a`, `S' = S + s` y `s = ⌊a(S+v)/(A+1)⌋`, así que `s(A+1) ≤ a(S+v)` y
  `(A'+1)(S+v) = (A+1)(S+v) + a(S+v) ≥ (A+1)(S+v) + s(A+1) = (A+1)(S'+v)`.
- mint: `a = ⌈s(A+1)/(S+v)⌉` da `a(S+v) ≥ s(A+1)`, y sigue igual.
- withdraw: `A' = A − a`, `S' = S − s` y `s = ⌈a(S+v)/(A+1)⌉` da `s(A+1) ≥ a(S+v)`, así que
  `(A'+1)(S+v) = (A+1)(S+v) − a(S+v) ≥ (A+1)(S+v) − s(A+1) = (A+1)(S'+v)`.
- redeem: `a = ⌊s(A+1)/(S+v)⌋` da `a(S+v) ≤ s(A+1)`, y sigue igual.
- transfer, allocate y deallocate no cambian ni `A` ni `S`: vale con igualdad. ∎

**V-INF-2 (a): las comisiones se llevan lo suyo, ni más ni menos.** Con `y = (A+1)(T+v)/(N+1)` y `q = ⌊y⌋`:
`q − 1 ≤ S + v ≤ q`.

El vault acuña `σ^p = ⌊F^p(T+v)/(N+1)⌋` y `σ^g = ⌊F^g(T+v)/(N+1)⌋`, y cada piso pierde menos de una acción. Como
`T + v + (F^p+F^g)(T+v)/(N+1) = (T+v)(N+1+F^p+F^g)/(N+1) = y`, resulta `S + v = T + v + σ^p + σ^g ∈ (y − 2, y]`.
Siendo entero, `q − 1 ≤ S + v ≤ q`. ∎

La cota de arriba dice que las acciones de comisión no valen más que `F^p + F^g` (`ρ ≥ (N+1)/(T+v)`); la de abajo, que
valen más que `F^p + F^g` menos dos acciones. Es la versión económica de V-FEE-1, que fija `σ^p` y `σ^g` bit a bit con
la fórmula del modelo; V-INF-2 no usa esa fórmula, solo el valor.

**V-INF-2 (c): el precio solo baja por la pérdida realizada y por la comisión de gestión,**
`(A+1)(T+v) ≥ (min(_TA, R) ⊖ F^g + 1)(S+v)`.

Por (a), `(A+1)(T+v) ≥ (N+1)(S+v)`, así que alcanza con `N ≥ min(_TA, R) − F^g`:

- sin pérdida (`R ≥ _TA`): `A = min(R, maxTA) ≥ _TA` porque `maxTA ≥ _TA`; el interés es `I = A − _TA` y
  `F^p = ⌊I·f_p/W⌋ ≤ I` porque `f_p ≤ W/2`. Entonces `A − F^p ≥ _TA`.
- con pérdida (`R < _TA`): `A = R` y `F^p = 0` (V-LOSS-1). Entonces `A − F^p = R`.

O sea: tras devengar, el precio es al menos `(min(_TA, R) − F^g + 1)/(T+v)`, contra `(_TA+1)/(T+v)` antes. Baja a lo
sumo lo perdido (`_TA − R`) más `F^g`, repartido entre `T + v` acciones; sin pérdida y sin comisión de gestión, no
baja. Y por (a), baja exactamente eso, salvo dos acciones de redondeo. ∎

**V-LOSS-1: la pérdida se realiza entera y de inmediato.** Si `R < _TA` al empezar la transacción, `A = R` exacto y
`σ^p = 0`.

`maxTA = _TA + ⌊_TA·Δt·maxRate/W⌋ ≥ _TA > R`, así que `A = min(R, maxTA) = R`; el interés `A ⊖ _TA` es 0 y no hay
comisión de performance. "De inmediato": el vault devenga en la primera interacción de cada transacción
(`firstTotalAssets = 0`), y cada acción del handler es una transacción nueva cuya primera llamada al vault devenga.
Dentro de una misma transacción, tras el primer devengamiento, `_totalAssets` queda fijo: es el diseño (Blackthorn
H-1, reconocido) y queda fuera de esta ley. ∎

**V-LOSS-2: la pérdida va al precio, no a los saldos.** Si hubo pérdida, fuera de quien opera ningún saldo cambia y
los de comisión solo suben.

`accrueInterest` solo llama a `createShares` para los dos receptores de comisión, y con pérdida solo para el de gestión
(`σ^p = 0`). Ningún saldo de usuario se mueve: todas las acciones pierden valor en la misma proporción, de
`(_TA+1)/(T+v)` a `(R+1)/(S+v)`, y lo que puede reclamar cada tenedor escala por el mismo factor. El cazador lo verifica
cuenta por cuenta (los 4 actores y los 2 receptores de comisión) y además exige `Σ saldos = totalSupply`, para que
ninguna acción aparezca en una cuenta que no se sigue. Sin pérdida, la misma comprobación es V-LEDGER. ∎

**V-FD-1: forceDeallocate cobra la penalidad exacta, la deja en el vault y no traslada ni evita pérdidas.**

`forceDeallocate(adapter, data, a, o)` hace, en orden:

1. Desasigna sin devengar: el adapter informa su posición nueva y el vault le retira `a` tokens. `R` no cambia: el
   adapter baja `a` y lo ocioso sube `a`.
2. Calcula `pA = ⌈a·p/W⌉`, con `p = forceDeallocatePenalty[adapter] ≤ 2 %`.
3. Cobra con `withdraw(pA, vault, o)`. Ese `withdraw` devenga (es el primer devengamiento de la transacción, y como `R`
   no cambió, da el mismo `A` y las mismas comisiones que desde el estado inicial); quema
   `sP = ⌈pA(S+v)/(A+1)⌉` acciones de `o` (y baja la allowance de quien llama en `sP` si no es `o` ni es infinita); baja
   `_totalAssets` en `pA`, y transfiere `pA` del vault al vault.

Queda `R' = R`, `TA' = A − pA`, `T' = S − sP` y el saldo de `o` baja `sP`. Por el techo, `sP(A+1) ≥ pA(S+v)`, así que
`(A − pA + 1)(S+v) ≥ (A+1)(S − sP + v)`: el precio no baja para nadie (V-INF-2 b) y la penalidad queda como exceso
`R − TA`, que se devenga después bajo `maxRate`, como una donación. Quien fuerza no **evita** su parte de una pérdida:
el devengamiento del paso 3 la realiza antes de cobrar (`A = R` si `R < _TA`, V-LOSS-1), y dentro de la misma transacción
no hay otro devengamiento (`firstTotalAssets ≠ 0`), así que si `o` retira `w` enseguida, quema
`sW = ⌈w(S − sP + v)/(A − pA + 1)⌉`, al precio ya castigado. Y no la **traslada**: ningún otro saldo cambia y el precio
de los demás no baja. El cazador verifica las dos formas: forceDeallocate solo (propio y por allowance, con allowance
finita) y forzar y salir en una transacción, con `TA'' = A − pA − w`, `R'' = R − w` y `sP + sW` quemadas a `o`. ∎

**V-CAP-1: los topes, exactos y con su borde.**

- `allocation = posición`. El adapter informa en cada allocate y deallocate `change` = posición nueva − anterior y el
  vault lo suma a la `allocation` de cada id devuelto. Partiendo de 0, por inducción `allocation = Σ changes = posición`.
- `allocate(a)` pasa si y solo si `a ≤` lo ocioso y, para cada id, `absoluteCap > 0`, `pos' ≤ absoluteCap` y, si
  `relativeCap ≠ WAD`, `pos' ≤ ⌊ft·relativeCap/W⌋`, con `pos'` = saldo del adapter + `a` y `ft = firstTotalAssets` al
  medir. Las demás causas de reversión (rol de allocator, adapter dado de alta, desbordes) están descartadas en el
  harness, así que el predicado es exacto: pasar un tope es una falla de seguridad y revertir dentro de ellos, una de
  vivacidad. El handler prueba el borde: justo en el tope, uno más y uno menos.
- `firstTotalAssets` es el primer total devengado **no nulo** de la transacción (Spearbit 5.1.6): si la transacción
  empieza con `A ≠ 0`, queda `A` aunque después entre un depósito. Por eso, depositando `x` y asignando en la misma
  transacción, el tope relativo es `⌊A·rc/W⌋` y no `⌊(A+x)·rc/W⌋`: es la defensa contra préstamos flash. Si `A = 0`, el
  primer total no nulo es el del allocate, que ya incluye `x`. Entre dos transacciones el depósito sí cuenta: es el L-14
  de Blackthorn, reconocido, y no es una violación.

**Una sola transacción con forge 1.8.6.** forge corre con `isolate = true`: cada llamada que el handler hace al vault es
una transacción aparte y la memoria transitoria se borra entre ellas, así que `firstTotalAssets` se lee 0 desde el
handler. Las secuencias de una transacción (depositar y asignar, forzar y salir, asignar y leer `firstTotalAssets`) las
hace `NexusV2Macro`, allocator del vault con allowance de los actores, dentro de su propia llamada, y devuelve lo que lee
ahí. ∎

**V-GOV-1: el gobierno con timelock hace lo que promete, ni antes ni sin permiso.** Es una especificación, no una
cota: el handler lleva una copia fantasma (timelock por selector, abdicaciones y, por cada dato pendiente, su
`executableAt`) y compara cada intento con ella. Con `sel(d)` los primeros 4 bytes de `d` y `t` la hora:

- `submit(d)` pasa si y solo si lo llama el curador y `executableAt[d] = 0`; entonces `executableAt[d] = t +
  timelock[sel(d)]`, salvo para `decreaseTimelock(s, ·)`, que usa `timelock[s]` (bajar un timelock tarda lo que el
  timelock que baja). Un pendiente conserva su fecha aunque después cambie el timelock.
- Ejecutar `d` (cualquiera puede) pasa si y solo si `executableAt[d] ≠ 0`, `t ≥ executableAt[d]`, `sel(d)` no fue
  abdicado y se cumplen las condiciones de la función con el estado de ese momento: comisión de performance `≤ 0,5`,
  de gestión `≤ 0,05/año`, con receptor no nulo salvo que sea 0; receptor no nulo salvo con comisión 0; penalidad
  `≤ 2 %`; `increaseTimelock` sube y `decreaseTimelock` baja, y ninguno sobre `decreaseTimelock`; un tope absoluto
  sube y cabe en 128 bits, uno relativo sube sin pasar de `WAD`; `addAdapter` solo si no hay registro o el adapter
  está en él; un registro no nulo tiene que contener a todos los adapters vigentes; `removeAdapter` siempre. Si pasa,
  el efecto es el valor propuesto (para los adapters, `isAdapter` y el largo de la lista) y `executableAt[d] = 0`. El
  handler lo intenta un segundo antes de la fecha (tiene que fallar) y justo en la fecha.
- `revoke(d)` pasa si y solo si lo llama el curador o un centinela y `d` está pendiente; deja `executableAt[d] = 0`, y
  `d` ya no se ejecuta aunque llegue su fecha. Tras una abdicación, una propuesta nueva de esa función se acepta, pero
  no se ejecuta.
- Las comisiones y sus receptores llaman a `accrueInterest()` antes de cambiar, así que lo devengado hasta ese momento
  se cobra con la comisión vieja: el cazador aplica V-TA-1, V-FEE-1 y el resto de las leyes de devengamiento con la
  foto previa, y una comisión retroactiva rompe V-FEE-1. Lo demás (penalidad, timelocks, abdicaciones, propuestas y
  revocaciones) no devenga ni mueve `_totalAssets`, `totalSupply` ni los activos reales.

El predicado es exacto porque el harness descarta las demás causas de reversión (desbordes de `t + timelock`, con
timelocks de a lo sumo unos días). Timelocks iniciales: 3 días la comisión de performance, 1 día la de gestión, 12 h la
penalidad, 2 días el receptor de performance, 5 días `abdicate`, 4 días `addAdapter`, 1 día el registro, 1 h
`increaseTimelock`; el receptor de gestión, `removeAdapter` y `decreaseTimelock` quedan en 0 (el camino sin demora).
Los topes también: `setCap` los sube con submit y ejecución inmediata, y si el gobierno tiene pendiente el mismo dato,
lo ejecuta en vez de proponerlo de nuevo. El alta y la baja son de un segundo adapter siempre vacío, y el registro solo
contiene al principal: así cada caso del predicado (alta con y sin registro, registro con y sin el segundo adapter
dado de alta) se puede dar, y la contabilidad no cambia. ∎

### Variante B: el adapter real sobre Morpho Blue (V-ADP)

`NexusVaultV2Blue.t.sol`: VaultV2 + `MorphoMarketV1AdapterV2` (creado por su factory) sobre Morpho Blue con la IRM
adaptativa, dos mercados del mismo token con colaterales distintos (LLTV 80 % y 90 %), sembrados con un suministro
inicial (el adapter lo exige), prestatarios, cambios de precio del oráculo y liquidaciones que dejan deuda incobrable. Sin
adapter de liquidez: depositar y retirar no tocan Blue. Antes de cada foto el cazador llama a `morpho.accrueInterest`
en los dos mercados, así el estado crudo de Blue es el que el adapter calcula con `expectedMarketBalances`, y todo se
verifica contra ese estado crudo con la aritmética de Blue: `toAssetsDown(s) = ⌊s·(tsa+1)/(tss+10⁶)⌋`.

- **V-ADP-1:** `realAssets = Σ` sobre los mercados de `marketIds` de `toAssetsDown(supplyShares)` (las acciones
  internas del adapter).
- **V-ADP-2:** la allocation del id de cada mercado queda, tras cada allocate o deallocate en él, en el valor de sus
  acciones internas; la del id del adapter es la suma de los mercados y la de cada colateral, la de su mercado (el
  adapter devuelve los tres ids en cada llamada y el vault les suma el mismo `change` = nueva − anterior).
- **V-ADP-3:** las acciones internas del adapter son su posición en Blue (sin donaciones de acciones ni `burnShares`).
- **V-ADP-4:** un mercado está en `marketIds` (una sola vez) si y solo si su allocation es > 0: `updateList` lo agrega
  al pasar de 0 a > 0 y lo saca al volver a 0.
- **V-ADP-5:** un allocate de `a` suministra exactamente `a` en Blue y suma `⌊a·(tss+10⁶)/(tsa+1)⌋` acciones; un
  deallocate de `a` devuelve exactamente `a` y quema `⌈a·(tss+10⁶)/(tsa+1)⌉`; y `R = ocioso + realAssets` cambia solo
  por el redondeo, dentro de `[−⌈p⌉, +1]`, con `p = (tsa+1)/(tss+10⁶)` el precio de una acción de suministro.

Demostración de la cota de V-ADP-5 (suministro; el retiro es igual con `g = ⌈a/p⌉ − a/p`): con `x` acciones del
adapter, `sₐ = ⌊a/p⌋ = a/p − f` (`0 ≤ f < 1`) y `p' = (tsa+a+1)/(tss+sₐ+10⁶)`, resulta `p' − p = p·f/(tss+sₐ+10⁶)`, y el
cambio exacto del valor de la posición menos `a` es `(x+sₐ)p' − xp − a = −f·p·[1 − (x+sₐ)/(tss+sₐ+10⁶)] ∈ (−p, 0]`
(porque `x ≤ tss`). Los dos pisos de `toAssetsDown` mueven el resultado a lo sumo 1 hacia cada lado, así que el cambio
de `R` está en `[−⌈p⌉, +1]`: el vault puede ganar 1 wei (recupera la fracción que el piso descartaba en el valor
anterior). Con las 10⁶ acciones virtuales de Blue, `p ≪ 1` y el rango es `[−1, +1]`. ∎

Las leyes del vault que no dependen del adapter (V-TA-1 y V-LOSS-1 con `R = ocioso + realAssets`, V-SOLV-1 tras un
devengamiento) también se evalúan; una liquidación con deuda incobrable baja `realAssets` y el vault realiza la pérdida
entera en su próximo devengamiento.

**Adapter de liquidez.** El handler pone el adapter de liquidez en un mercado o lo saca. Con él, un depósito de `x` va
entero a Blue en ese mercado (lo ocioso no cambia, Blue suma exactamente `x` y el adapter `⌊x·(tss+10⁶)/(tsa+1)⌋`
acciones) y un retiro de `w` desasigna lo que falte de lo ocioso (Blue entrega exactamente `w − ocioso` y quema `⌈·⌉`
acciones); `R` cambia en `±x` más el redondeo de V-ADP-5. Los montos de depósito y retiro se miden en el saldo del
usuario, no en lo ocioso, para que V-TA-1 siga separando el devengamiento de la operación.

**forceDeallocate sobre Blue (V-FD-1).** Cualquiera saca `a` de un mercado a nombre de otro con allowance: Blue entrega
exactamente `a` (quema `⌈a·(tss+10⁶)/(tsa+1)⌉` acciones del adapter), el devengamiento del `withdraw` de la penalidad ve
`R' = R + δ` (δ, el redondeo de ese retiro, calculado con la aritmética de Blue), `_totalAssets = min(R', tope) − pA`
con `pA = ⌈a·p/W⌉`, a `onBehalf` se le queman `⌈pA·(T+v)/(A+1)⌉` acciones, lo ocioso sube `a` (la penalidad queda en el
vault) y quien llama no paga nada.

**Blue Public Allocator (V-PA).** `BluePublicAllocator` (periferia en alcance, desplegado) deja que cualquiera reasigne la
liquidez del vault entre mercados de Blue alcanzados por el `MorphoMarketV1AdapterV2`, dentro de los topes del vault y de
los suyos, pagando una penalidad proporcional que va al vault como donación. En el harness es allocator del vault y lo
configura el ALLOCATOR (adapter activo, tope propio por mercado, permiso de retirar de cada mercado y de lo ocioso,
penalidad); los actores llaman a `reallocate` y `allocateFromIdle`.

`reallocate(f → t, a, penalidad)` hace, en orden: cobra `pA = ⌈a·penalidad/W⌉` de quien llama al vault, controla
penalidad = la configurada, adapter activo, permiso de retirar de `f` y tope propio de `t` > 0, desasigna `a` de `f` (sin
devengar), asigna `a` en `t` (el vault devenga acá) y exige `allocation(t) ≤` su tope propio. Entonces, si pasa:

- **V-PA-1:** quien llama pagó exactamente `pA` y lo ocioso del vault subió `pA` (en `allocateFromIdle`, `pA − a`).
- **V-PA-2:** Blue entregó exactamente `a` desde `f` y recibió exactamente `a` en `t` (nada si `f = t`).
- **V-PA-3:** se cumplían los permisos y la allocation de `t` quedó dentro del tope propio.
- **V-PA-4:** con una penalidad distinta de la configurada revierte, y solo un allocator del vault puede configurarlo.
- **V-TA-1** en el devengamiento del `allocate`, que ve `R' = ocioso + pA + a + realAssets` con el valor del mercado `f`
  ya desasignado (aritmética de Blue): la penalidad entra como donación y, si `maxRate` no la acota, se devenga en el acto.

Los movimientos que no cumplen las condiciones revierten (y el handler los cuenta); las leyes V-ADP siguen valiendo
tras cada movimiento. Lo que las auditorías de agosto de 2026 ya señalaron (manipulación de tasas, deuda incobrable
empujada al vault, liquidez retirada) son ataques económicos conocidos; estas leyes son de exactitud contable.

## 5. Harness previsto

1. **Variante A — adapter controlable.** VaultV2 + `NexusAdapterMock`, un adapter de nexus que cumple la
   especificación de adapters de V2: `realAssets` es su saldo del token (todo lo informado está respaldado) y cada
   allocate/deallocate informa `change` = posición nueva − anterior, así que la `allocation` del vault es la posición.
   El handler le acredita rendimiento o le quita tokens (pérdida) y prueba toda la capa de contabilidad de V2 (tope de
   tasa, dos comisiones, forceDeallocate, caps, realización de pérdida) de forma exacta y barata. Es la que más señal
   da por llamada. El `AdapterMock` del repo no sirve con capital asignado: suma `interest − loss` en cada llamada, la
   allocation se desvía y, tras una pérdida, una desasignación puede dejar `realAssets()` en underflow.
2. **Variante B — adapter real.** VaultV2 + `MorphoMarketV1AdapterV2` sobre Morpho Blue (§4, "Variante B"): valida que
   el adapter real respeta el modelo, contra el estado crudo de Blue, con el Blue Public Allocator montado encima.
   Escrita el 27-oct (`NexusVaultV2Blue.t.sol`): 256×500 sin falsos positivos ni reversiones con `0x2a` y `0x3`, y las
   mutaciones V22–V33 (adapter y allocator) detectadas, cada ley V-ADP y V-PA por al menos una; con el adapter de
   liquidez y forceDeallocate sobre Blue (mutaciones V34–V35 del camino de liquidez del vault, y V14–V16 de la penalidad,
   que ahora también recorren Blue).
3. **Tres sub-variantes** cada una, como en MetaMorpho: sin comisión, con comisión, y activo de 6 decimales.
4. **Mutaciones de referencia** en [tools/forge_v2/mutaciones.json](../tools/forge_v2/mutaciones.json): redondeo de
   cada conversión, tope de tasa ignorado, bases y redondeos de las comisiones, pérdida diferida y exagerada, pérdida
   repartida en saldos, dilución al entrar, la penalidad de forceDeallocate (redondeo, destino y a quién se cobra) y
   los topes (absoluto, relativo contra el total actual, borde estricto, bookkeeping de la allocation y
   `firstTotalAssets`) y el gobierno con timelock (fecha, timelock de la función objetivo, abdicación, permisos de
   propuesta y revocación, pendientes que se pisan o no se borran, ejecución sin propuesta, comisiones retroactivas y
   las condiciones de comisiones, penalidad y timelocks). Resultados arriba. Cada una tiene que disparar una ley `V-...`.

Build: `src/` de V2 es solc 0.8.28, `via_ir`, `cancun`. forge 1.8.6 compila el repo entero, `MidnightAdapter` (osaka)
incluido, en ~11 min en la PC. Para iterar alcanza con VaultV2, la factory, el `ERC20Mock`, forge-std y el harness:
[tools/forge_v2](../tools/forge_v2/README.md) arma ese proyecto reducido con los mismos ajustes y compila en ~30 s.

## 6. Qué NO cubre (igual que MetaMorpho)

Tokens no estándar (aunque V2 soporta sin-return en transfer), reentrada vía adapter malicioso, `permit`/`multicall`,
préstamos flash, el Public Allocator (merece su propio modelo; está en alcance como contrato desplegado) y el
MidnightAdapter (fuera de alcance: no está desplegado).

Del gobierno, V-GOV-1 no prueba los gates, `setIsAllocator` ni las funciones del owner (`setCurator`,
`setIsSentinel`, `setOwner`); el alta y la baja son de un adapter vacío, así que no prueba sacar un adapter con
capital (sus activos dejarían de contarse y el vault realizaría una pérdida: es un poder del curador detrás del
timelock); y los receptores de comisión solo alternan entre el del harness y 0: un cambio de receptor con comisiones
en tránsito hacia otro receptor no se prueba (si no devengara antes, el receptor nuevo cobraría lo del viejo; no toca a
los depositantes).
