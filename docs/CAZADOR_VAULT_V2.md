# Cazador de vulnerabilidades para Morpho Vault V2

Modelo formal y leyes exactas para el harness de `morpho-org/vault-v2` (línea base `04e5f4a9`; hasta `6047e158` solo
cambió `MidnightAdapter`, fuera de alcance), al estilo del de MetaMorpho ([CAZADOR_METAMORPHO.md](CAZADOR_METAMORPHO.md)).
Estado: **variante A verificada con forge en la PC** (27-oct), con capital asignado de verdad en el adapter y las leyes
del precio por acción (V-INF-2) y de realización de pérdidas (V-LOSS-1, V-LOSS-2). Faltan la variante B (adapter real),
`forceDeallocate`, los topes como ley (V-CAP-1) y el gobierno con timelock. La etapa E (duplicados) está hecha y vive,
privada, en `NEXUS_HOME/secresearch/etapa_e/morpho-org__vault-v2/`.

**Harness (variante A).** `harness/morpho-org__vault-v2/`: `NexusVaultV2Hunter.sol` (contabilidad fantasma, leyes V-...
y `NexusAdapterMock`) y `NexusVaultV2Invariant.t.sol` (el handler y tres variantes: sin comisión, con comisión de
performance y de gestión, y activo de 6 decimales).

- El adapter es `NexusAdapterMock`, que cumple la especificación de adapters de V2 (§5): su `realAssets` es su saldo
  del token y la `allocation` del vault es su posición. El handler le acredita rendimiento o le quita tokens, así que
  el fantasma conoce los activos reales exacto y las pérdidas alcanzan al capital asignado, no solo al rendimiento.
- Topes: absoluto `1e30` en `id-0` e `id-1`; relativo `0,9` en `id-0`, e `id-1` sin tope relativo (`WAD`). El handler
  asigna dentro del tope efectivo, calculado contra el `firstTotalAssets` que predice el modelo.
- Los montos de cada acción los **deriva** el cazador del cambio de estado observado (activos: el cambio de lo ocioso;
  acciones: el cambio de balance), no de los argumentos del handler: así una acción acotada a 0 es un no-op consistente.
- El fantasma no usa las vistas con devengamiento del vault (`totalAssets`, `previewX`, `accrueInterestView`); solo
  estado crudo (`_totalAssets`, `totalSupply`, `lastUpdate`, `maxRate`, las comisiones, `balanceOf`) y los activos
  reales desde el token y el adapter.
- Ninguna ley revierte: con `fail_on_revert = false`, un cazador que revierte esconde la violación como una reversión
  más. El motivo de una falla termina con todas las leyes que fallaron, por ejemplo `[leyes: V-TA-1 V-LOSS-1]`.
- `afterInvariant` informa la cobertura de la corrida: pérdidas realizadas, bajas de precio sin pérdida (solo puede
  haberlas por la comisión de gestión) y asignaciones, desasignaciones y transferencias con efecto.

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
construcción. Las que solo ve la variante con comisión necesitan una comisión distinta de cero.

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

Implementadas en la variante A: V-TA-1, V-INF-1, V-INF-2, V-FEE-1, V-LOSS-1, V-LOSS-2, V-LEDGER y V-SOLV-1. Las demás
son el plan.

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
| V-FD-1 | forceDeallocate: `penalty = ⌈assets·p/W⌉`, `TA` y `T` bajan por el `withdraw`, `R` no; quien fuerza no evita su pérdida ni la traslada | Evasión o traslado de pérdidas |
| V-CAP-1 | Allocate respeta `absoluteCap` y, si `relativeCap ≠ WAD`, `allocation ≤ ⌊firstTotalAssets·relativeCap/W⌋` | Topes ignorados |
| V-GOV-1..n | Cada acción con timelock (addAdapter, caps, fees, registry, penalty) se compara con la predicción: éxito/reversión, efecto y `executableAt` | Timelocks que vencen antes, cambios sin esperar |
| V-LEDGER | `T = Σ saldos` (incluidas las shares de fee); `T` = el esperado tras cada acción; sin pérdida, fuera de quien opera ningún saldo cambia y los de comisión solo suben | Shares creadas o destruidas por fuera |
| V-SOLV-1 | `⌊T⁺(TA+1)/(T⁺+v)⌋ ≤ R`: lo reclamable está respaldado por los activos reales | Insolvencia |
| V-BOUND | Las macros exigen `TA, T < ~10³⁵` antes de operar (el `mulDiv` de una palabra puede desbordar) | Falsos positivos por `Panic(0x11)` |

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

## 5. Harness previsto

1. **Variante A — adapter controlable.** VaultV2 + `NexusAdapterMock`, un adapter de nexus que cumple la
   especificación de adapters de V2: `realAssets` es su saldo del token (todo lo informado está respaldado) y cada
   allocate/deallocate informa `change` = posición nueva − anterior, así que la `allocation` del vault es la posición.
   El handler le acredita rendimiento o le quita tokens (pérdida) y prueba toda la capa de contabilidad de V2 (tope de
   tasa, dos comisiones, forceDeallocate, caps, realización de pérdida) de forma exacta y barata. Es la que más señal
   da por llamada. El `AdapterMock` del repo no sirve con capital asignado: suma `interest − loss` en cada llamada, la
   allocation se desvía y, tras una pérdida, una desasignación puede dejar `realAssets()` en underflow.
2. **Variante B — adapter real.** VaultV2 + `MorphoMarketV1AdapterV2` sobre Morpho Blue, reutilizando el fantasma de
   Morpho del cazador de MetaMorpho (`expectedMarketBalances`/`toAssetsDown`). Más cara, valida que el adapter real
   respeta el modelo.
3. **Tres sub-variantes** cada una, como en MetaMorpho: sin comisión, con comisión, y activo de 6 decimales.
4. **Mutaciones de referencia** en [tools/forge_v2/mutaciones.json](../tools/forge_v2/mutaciones.json): redondeo de
   cada conversión, tope de tasa ignorado, bases y redondeos de las comisiones, pérdida diferida y exagerada, pérdida
   repartida en saldos y dilución al entrar (resultados arriba). Cada una tiene que disparar una ley `V-...`. Faltan las
   de las leyes que vienen: penalidad de forceDeallocate hacia abajo y tope ignorado.

Build: `src/` de V2 es solc 0.8.28, `via_ir`, `cancun`. forge 1.8.6 compila el repo entero, `MidnightAdapter` (osaka)
incluido, en ~11 min en la PC. Para iterar alcanza con VaultV2, la factory, el `ERC20Mock`, forge-std y el harness:
[tools/forge_v2](../tools/forge_v2/README.md) arma ese proyecto reducido con los mismos ajustes y compila en ~30 s.

## 6. Qué NO cubre (igual que MetaMorpho)

Tokens no estándar (aunque V2 soporta sin-return en transfer), reentrada vía adapter malicioso, `permit`/`multicall`,
préstamos flash, el Public Allocator (merece su propio modelo; está en alcance como contrato desplegado) y el
MidnightAdapter (fuera de alcance: no está desplegado).
