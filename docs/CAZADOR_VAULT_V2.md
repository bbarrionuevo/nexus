# Cazador de vulnerabilidades para Morpho Vault V2

Modelo formal y leyes exactas para el harness de `morpho-org/vault-v2` (commit de la línea base `04e5f4a9`), al
estilo del de MetaMorpho ([CAZADOR_METAMORPHO.md](CAZADOR_METAMORPHO.md)). Estado: **modelo derivado, harness por
escribir**. La etapa E (duplicados) está hecha y vive, privada, en `NEXUS_HOME/secresearch/etapa_e/morpho-org__vault-v2/`.

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

**Activos reales.** `R = balance(asset, vault) + Σ_a realAssets_a`. En el harness con `AdapterMock`,
`realAssets_a = deposit_a + interes_a − perdida_a`, que el fantasma conoce exacto.

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

## 3. Leyes (borrador, exactas y de 512 bits salvo donde el código no lo es)

| Código | Ley | Caza |
|---|---|---|
| V-TA-1 | `TA' = min(R, _TA + ⌊_TA·Δt·maxRate/W⌋)`, bit a bit | Tope de tasa mal aplicado, interés inventado |
| V-TA-2 | El exceso `R − TA'` no se pierde: con `Δt` suficiente y `R` fijo, `TA` converge a `R` sin pasarse | Yield que se crea o se pierde |
| V-INF-1 | Las cuatro fórmulas de conversión del §2, en desigualdades justas y ajustadas | Redondeo invertido, dilución |
| V-INF-2 | Entre acciones el precio `ρ = (TA+1)/(T+v)` solo baja por pérdida realizada o por `F^g` exacto | Dilución fuera de la comisión de gestión |
| V-INF-3 | Una donación directa (subir `R`) sube `TA` a lo sumo `⌊_TA·Δt·maxRate/W⌋` por devengamiento | Inflación por donación |
| V-FEE-1 | `σ^p`, `σ^g` acuñadas = las del fantasma; `F^p` solo si `I>0`, `F^g` solo si `Δt>0` y receptor válido | Comisión sobre base equivocada |
| V-FEE-2 | `σ^p` nace solo del interés devengado; `σ^g` es la única que puede existir con `I = 0` | Comisión de performance sobre no-interés |
| V-LOSS-1 | Si `R < _TA`, entonces `TA' = R` y `I = 0`: la pérdida se realiza entera y ya | Pérdida diferida u ocultada |
| V-LOSS-2 | Realizar una pérdida no cambia ningún saldo de shares; el precio baja la fracción exacta | Pérdida mal repartida |
| V-FD-1 | forceDeallocate: `penalty = ⌈assets·p/W⌉`, `TA` y `T` bajan por el `withdraw`, `R` no; quien fuerza no evita su pérdida ni la traslada | Evasión o traslado de pérdidas |
| V-CAP-1 | Allocate respeta `absoluteCap` y, si `relativeCap ≠ WAD`, `allocation ≤ ⌊firstTotalAssets·relativeCap/W⌋` | Topes ignorados |
| V-GOV-1..n | Cada acción con timelock (addAdapter, caps, fees, registry, penalty) se compara con la predicción: éxito/reversión, efecto y `executableAt` | Timelocks que vencen antes, cambios sin esperar |
| V-LEDGER | `T = Σ saldos` (incluidas las shares de fee); cada saldo = acuñadas − quemadas ± transferidas | Shares creadas o destruidas por fuera |
| V-SOLV-1 | `⌊T⁺(TA+1)/(T⁺+v)⌋ ≤ R`: lo reclamable está respaldado por los activos reales | Insolvencia |
| V-BOUND | Las macros exigen `TA, T < ~10³⁵` antes de operar (el `mulDiv` de una palabra puede desbordar) | Falsos positivos por `Panic(0x11)` |

## 4. Harness previsto

1. **Variante A — adapter controlable.** VaultV2 + `AdapterMock` (el del repo): `realAssets = deposit + interes −
   perdida`. Con `setInterest`/`setLoss` el handler maneja el devengamiento y las pérdidas a voluntad y prueba toda
   la capa de contabilidad de V2 (tope de tasa, dos comisiones, forceDeallocate, caps, realización de pérdida) de
   forma exacta y barata. Es la que más señal da por llamada.
2. **Variante B — adapter real.** VaultV2 + `MorphoMarketV1AdapterV2` sobre Morpho Blue, reutilizando el fantasma de
   Morpho del cazador de MetaMorpho (`expectedMarketBalances`/`toAssetsDown`). Más cara, valida que el adapter real
   respeta el modelo.
3. **Tres sub-variantes** cada una, como en MetaMorpho: sin comisión, con comisión, y activo de 6 decimales.
4. **Mutaciones de referencia**: redondeo de cada conversión, tope de tasa ignorado, `F^p` sobre no-interés, pérdida
   no realizada, penalidad de forceDeallocate hacia abajo, cap ignorado. Cada una tiene que disparar una ley `V-...`.

Build: `src/` de V2 es solc 0.8.28, `via_ir`, `cancun`. **No** arrastrar `MidnightAdapter` ni sus ratifiers (exigen
`evm_version = osaka`, que forge 1.8.6 quizá no compile). El harness solo toca VaultV2, los dos adapters en alcance,
Morpho Blue y `forge-std`.

## 5. Qué NO cubre (igual que MetaMorpho)

Tokens no estándar (aunque V2 soporta sin-return en transfer), reentrada vía adapter malicioso, `permit`/`multicall`,
préstamos flash, el Public Allocator (merece su propio modelo; está en alcance como contrato desplegado) y el
MidnightAdapter (fuera de alcance: no está desplegado).
