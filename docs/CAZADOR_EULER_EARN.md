# Cazador de vulnerabilidades para EulerEarn

Modelo exacto y leyes `E-...` para el harness de `euler-xyz/euler-earn` (programa Euler v2 en Cantina), al estilo de
los de MetaMorpho ([CAZADOR_METAMORPHO.md](CAZADOR_METAMORPHO.md)) y Vault V2 ([CAZADOR_VAULT_V2.md](CAZADOR_VAULT_V2.md)).
Estado: **variante A escrita y verificada con forge en la PC** (28-oct). VERIFICACION_RESUMEN

## 1. Qué versión y qué alcance

- **Versión desplegada:** el `EulerEarn.sol` del código verificado de la fábrica de Ethereum es, byte a byte, el del
  commit **`a8cc099`** (2025-08-12, el merge de las correcciones de Pashov); `SafeERC20Permit2Lib` es el de `b95775f`.
  Lo posterior (rutas de import de octubre de 2025 y los cambios de Permit2 del 23-oct-2026) no está desplegado en
  Ethereum. El harness prueba `a8cc099`; el ciclo diario lo corre además sobre la rama principal.
- **Alcance:** el reglamento de Euler cubre Euler Earn como categoría propia, evalúa contra la implementación desplegada
  y no paga Low ni informativos. La periferia del EVK, los hooks, las estrategias externas y los protocolos de terceros
  quedan afuera aunque EulerEarn dependa de ellos.
- **Etapa E:** las tres auditorías del repo (Certora, Pashov, Sigma Prime) están extraídas y resumidas en
  `NEXUS_HOME/secresearch/etapa_e/euler-xyz__euler-earn/` (privado, R-4). Además, el repo trae la suite de invariantes
  de Enigma Dark y la verificación formal de Certora: lo que agrega este cazador es el modelo exacto en 512 bits.

## 2. Modelo

EulerEarn es un fork de MetaMorpho V1.1 que invierte en estrategias ERC-4626 (EVK y otros EulerEarn) en vez de mercados
de Morpho Blue. Estado: `L = lastTotalAssets`, `P = lostAssets`, `T = totalSupply`, comisión `f`, y por estrategia `i`
el seguimiento interno `bᵢ = config[i].balance` (acciones, en `uint112`), su tope y las colas. `V = VIRTUAL_AMOUNT =
10^6`, en acciones **y** en activos.

- **Activos reales:** `RT = Σ previewRedeemᵢ(bᵢ)` por la withdrawQueue: cuenta el seguimiento interno, no el saldo real
  (las acciones donadas no cuentan).
- **Devengamiento:** si `RT < L − P`, `P' = L − RT`; si no, `P' = P`. `A = RT + P'` (nunca menor que `L`), interés
  `I = A − L`, comisión `F = ⌊I·f/W⌋` y acciones de comisión `σ = ⌊F·(T+V)/(A−F+V)⌋`. `L ← A`. **La pérdida no se
  realiza en el precio**: `lostAssets` la absorbe (y nunca baja; una recuperación cuenta como interés).
- **Conversiones** (con `L` y `T` ya devengados): deposit `⌊a(T+V)/(L+V)⌋` (revierte con 0 acciones), mint
  `⌈s(L+V)/(T+V)⌉`, withdraw `⌈a(T+V)/(L+V)⌉`, redeem `⌊s(L+V)/(T+V)⌋`. Deposit y mint suman `a` a `L`; withdraw y
  redeem lo restan (piso en 0).
- **Reparto:** un depósito recorre la supplyQueue (puede tener duplicados) y pone en cada estrategia `min(tope −
  previewRedeem(bᵢ), lo que falta)`; un retiro recorre la withdrawQueue sacando `min(maxWithdraw, previewRedeem(bᵢ),
  lo que falta)`. Ambos con `try/catch`: una estrategia que revierte se saltea; si algo queda sin colocar o sin
  retirar, revierte (`AllCapsReached`, `NotEnoughLiquidity`).
- **reallocate** mueve capital entre estrategias sin tocar `L` ni `T` (sin `try/catch`); la diferencia de redondeo
  aparece en el devengamiento siguiente.
- **Alta de una estrategia** (tope que pasa de 0 a positivo): adopta sus acciones **reales** y suma su valor a `L` sin
  comisión. **Baja** (sale de la withdrawQueue): sus acciones dejan de seguirse y su valor pasa a `P` en el devengamiento
  siguiente.

## 3. Leyes (exactas, en 512 bits, sin vistas de EulerEarn)

| Código | Ley | Caza |
|---|---|---|
| E-TA-1 | `L`, `P` y el interés del devengamiento, bit a bit; `P` nunca baja; el alta suma a `L` el valor de la estrategia y nada más | Pérdidas mal registradas, interés inventado, altas que cuentan de más |
| E-FEE-1 | Acciones de comisión = `σ` del modelo; la comisión nueva no es retroactiva | Comisión sobre la base equivocada, acciones de comisión perdidas |
| E-INF-1 | Las cuatro conversiones exactas, en acciones y en lo que el vault toma o paga | Redondeo invertido, cobros de más |
| E-INF-2 | **El precio `(L+V)/(T+V)` nunca baja**, en ninguna operación: `(L'+V)(T+V) ≥ (L+V)(T'+V)`. Ver §4 | Dilución, comisiones que se llevan de más, pérdidas que se realizan en el precio |
| E-ALLOC-1 | Cada estrategia queda como predice el reparto (activos y acciones), y EulerEarn no guarda activos ociosos | Topes ignorados, colas mal recorridas, fugas en reallocate |
| E-STRAT-1 | `bᵢ` = el modelo, y las acciones reales = seguidas + las que no sigue (donaciones, estrategias removidas) | Seguimiento interno desviado del real |
| E-LEDGER | `Σ saldos = T`, `T` = el esperado, ningún tercero cambia | Acciones creadas o destruidas por fuera |
| E-LIVE | Cada operación pasa **si y solo si** el modelo dice que pasa (topes, liquidez, pausas, 0 acciones, `uint112`, roles y condiciones de colas y topes) | Reversiones inesperadas o pasos indebidos |

## 4. Demostraciones

**E-INF-2: el precio no baja.** Basta con verlo en cada paso:

- *Devengamiento:* `A ≥ L` y `σ ≤ F(T+V)/(A−F+V)`, así que `T+σ+V ≤ (T+V)(A+V)/(A−F+V)` y
  `(A+V)/(T+σ+V) ≥ (A−F+V)/(T+V) ≥ (L+V)/(T+V)`, porque `A − F ≥ L` (`F ≤ I/2 ≤ I`).
- *Deposit:* `s ≤ a(T+V)/(L+V)`, así que `(L+a+V)(T+V) ≥ (L+V)(T+s+V)`. *Mint:* `a ≥ s(L+V)/(T+V)`, lo mismo.
- *Withdraw:* `s ≥ a(T+V)/(L+V)` y `L' = L − a`: `(L−a+V)(T+V) ≥ (L+V)(T−s+V)` ⟺ `s(L+V) ≥ a(T+V)`. *Redeem:* igual
  con `a ≤ s(L+V)/(T+V)`. (El piso en 0 de `L − a` no se alcanza: lo retirable está acotado por `RT ≤ L − P`.)
- *Alta:* `L` sube y `T` no cambia. *reallocate, baja, cambios de tope, transferencias y eventos de las estrategias:* no
  tocan `L` ni `T`. ∎

**E-BOUND: el borde del dominio.** `bᵢ` es `uint112` y el cast está en el bloque de éxito del `try` de
`_supplyStrategy`, así que no lo atrapa: si una estrategia que sigue en la supplyQueue con lugar en su tope pierde casi
todos sus activos, su precio queda cerca de 0 y el depósito siguiente acuña más acciones de las que entran en `uint112`:
**todos los depósitos de EulerEarn revierten** hasta que el allocator la saca de la supplyQueue (o el curador baja su
tope). El mismo `uint112` aparece en el **alta**: `_setCap` adopta las acciones reales con `.toUint112()`, así que
una estrategia en la que EulerEarn tiene más de `2^112` acciones (las seguidas antes de una remoción más las que un
tercero compró a precio casi 0 tras una pérdida total y le donó) no se puede volver a dar de alta: `acceptCap` revierte
y el tope queda pendiente. El modelo predice los dos casos (E-LIVE) y `NexusEulerEarnBoundTest` los muestra. No son
hallazgos: hace falta una pérdida casi total de una estrategia; el primero lo deshace el allocator sin timelock y los
retiros siguen andando (el reglamento no considera permanente lo que un rol autorizado puede revertir), y el segundo
solo impide volver a agregar una estrategia muerta: nadie pierde nada. El harness acota los montos (`10^24` por acción,
offsets hasta 6) para no llegar ahí salvo por esa pérdida.

## 5. Harness (variante A)

`harness/euler-xyz__euler-earn/`: `NexusEulerEarnHunter.sol` (matemática de 512 bits, estrategias de prueba,
perspectiva, base y leyes) y `NexusEulerEarnInvariant.t.sol` (el handler, tres variantes y `NexusEulerEarnBoundTest`).

- **Estrategias:** tres ERC-4626 de OpenZeppelin 5.3 (el mismo que usa EulerEarn) con offsets 0, 3 y 6 y una pausa que
  hace revertir depósitos y retiros (las vistas no cambian), para recorrer los `try/catch`. Sus activos son su saldo:
  el handler les da rendimiento, les saca activos (pérdida), mete y saca a un tercero (cambia su redondeo) y le dona a
  EulerEarn acciones que no entran en el seguimiento interno.
- **EulerEarn real** desde su fábrica, con el EVC real, una perspectiva de prueba, Permit2 en 0 y timelock 0 (los topes
  se suben con submit y accept en el acto). La de offset 6 va primera en la supplyQueue con tope chico, para que los
  depósitos se repartan.
- **Acciones:** deposit, mint, withdraw (0 solo devenga), redeem, transfer; rendimiento, pérdida, tercero, donación y
  pausa de cada estrategia; comisión y receptor (el owner, en el acto); reallocate (retirar una parte o canjear todo y
  poner en otra); supplyQueue (con duplicados), withdrawQueue (rotar y sacar una), topes (subir, bajar, a 0) y remoción;
  y un ciclo de vida (tope 0, remoción, salida y vuelta) que recorre el L-09 reconocido de Pashov.
- **Variantes:** sin comisión, con comisión (20 %) y activo de 6 decimales.
- `afterInvariant` informa la cobertura: devengamientos con pérdida y con interés, depósitos repartidos, operaciones con
  una estrategia pausada, rechazos predichos, donaciones, reallocate, remociones y altas, y los depósitos que tocarían
  el `uint112`.

**Proyecto reducido.** El build entero del repo no compila con forge 1.8.6 (forge-std duplicado entre el EVK y Permit2
en sus tests), y el harness no los usa: `NEXUS_PERFIL=euler-earn python tools/forge_v2/forge_v2.py armar|correr|mutar`
arma un proyecto con `src`, OpenZeppelin, el EVC y forge-std y los mismos ajustes del repo (solc 0.8.26, via_ir, 200
runs, cancun). `validate` compila solo `src` y el harness con `"aislado": true` en el manifiesto (forge toma
`test/nexus/` como sus directorios de tests y de scripts: `forge test` compila el proyecto entero aunque se filtre).

VERIFICACION_DETALLE

## 6. Qué NO cubre

Las estrategias reales del EVK (variante B, pendiente: crédito, IRM, deuda incobrable de verdad), el Public Allocator de
EulerEarn, Permit2 (va en 0), las llamadas por el EVC (`callThroughEVC`, subcuentas), el guardian y los timelocks
distintos de 0, la reentrada (las estrategias de prueba no reentran), los tokens no estándar y las comisiones con un
receptor que es depositante.
