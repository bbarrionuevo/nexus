# Cazador de VaultBundlesV1 y VaultExitBundlesV1 (Morpho Bundles)

Estado (31-oct): **variante VB1 (con Vault V2) escrita y verificada con forge en la PC**: pasa sin falsos positivos
ni reversiones del handler con dos semillas, con el precio por acción moviéndose, y se detectan las 28 mutaciones de
referencia. **No hay hallazgos.**

## 1. Qué versión y qué alcance

- **Programa:** Morpho en Cantina, grupo "Morpho Blue and Vault V1 (MetaMorpho), including bundlers" (Critical de USD
  250.000 a 2.500.000). La página de direcciones de Morpho lista `VaultBundlesV1` (`0x0291…650B`) y
  `VaultExitBundlesV1` (`0xaf85…9B02`) entre los "Bundles".
- **Versión probada:** lo desplegado son las etiquetas `2026-08-07` a `2026-08-24` del repo `morpho-org/bundles`;
  hasta la `2026-10-06` (`2ed954e`, el clon que comparten los cazadores de Bundles) solo cambiaron comentarios, y los
  submódulos (`lib/vault-v2` en `2b13900`, `lib/metamorpho` en `ae73225`) son los mismos.
- **Revisión manual del 30-oct:** sin candidatos (guarda de reentrada con `initiator`, callbacks solo desde Blue,
  siempre sobre las acciones de `msg.sender`; ver la nota privada de la etapa E).

## 2. Qué hacen los bundles

**VaultBundlesV1** (cualquier vault ERC-4626: Vault V1 o Vault V2):
- `Deposit`: cobra `assets`, la comisión `⌊assets·pct/WAD⌋` al referido y deposita el resto a nombre del usuario;
  con `maxSharePriceE27`, el precio por acción no puede superarlo.
- `Withdraw`: por activos o por acciones (exactamente uno), y le paga al usuario lo retirado menos `⌊retirado·pct/WAD⌋`.
- `Migrate`: retira de un vault y deposita en otro del mismo activo, con la comisión en el medio y el control de
  precio en destino.

**VaultExitBundlesV1** (salidas de un Vault V2 con un solo adapter, el `MorphoMarketV1AdapterV2`):
- `InKindRedemptionVaultV2`: le da al usuario lo ocioso del vault y, por cada mercado de la lista, una posición de
  oferta en Blue: aporta en Blue a nombre del usuario y, en el callback, el vault desasigna eso de ese mercado con
  `forceDeallocate` (la penalidad sale de las acciones del usuario) y le retira lo aportado. Lo desasignado es
  `⌊(exitAssets − ocioso)·WAD/(WAD + penalidad)⌋`; lo retirado del vault suma a lo sumo `exitAssets + N`.
- `ForceWithdrawVaultV2`: retira lo que el vault paga sin penalidad (ocioso más la liquidez del adapter de liquidez)
  y desasigna el resto con penalidad, mercado por mercado; con `minSharePriceE27`, el precio de salida no puede quedar
  por debajo; comisión de referido sobre lo retirado.
- `InKindRedemptionVaultV1` (MetaMorpho) queda para la variante con Vault V1.

## 3. Leyes (exactas, contra los saldos, las acciones y Blue)

En cada llamada que pasa:

- **VB-FUNDS:** los dos bundles terminan sin activo ni acciones; lo que paga o cobra el usuario es exactamente lo
  documentado.
- **VB-FEE:** la comisión de referido es exactamente la documentada.
- **VB-SHARES:** las acciones del usuario cambian exactamente como dicen las vistas del vault (`previewDeposit`,
  `previewWithdraw`, `previewRedeem`). En la redención en especie y en el retiro forzado, donde la penalidad se cobra
  en retiros intermedios, se queman a lo sumo las acciones de `exitAssets + N` más una por retiro: el bundle documenta
  que los retiros suman a lo sumo `exitAssets + N`, y el precio por acción no baja entre uno y otro.
- **VB-KIND:** en la redención en especie, el usuario recibe exactamente lo ocioso que le toca, y en cada mercado la
  posición en Blue que le corresponde con el redondeo de Blue (`toSharesDown` de lo que el adapter tenía, en orden).
- **VB-ISO:** ningún otro usuario cambia de saldo, acciones ni posición en Blue.
- **VB-LIVE**, en las dos direcciones:
  - con el plazo vencido, `pct ≥ WAD` o sin exactamente uno de activos y acciones, revierte; si pasa con control de
    precio, el precio lo respeta; la redención en especie no pasa si la lista no alcanzaba;
  - y no revierte por una de esas validaciones cuando no corresponde. El control de precio se prueba en su borde: con
    el precio exacto que realiza la llamada tiene que pasar, y con uno peor, revertir. En el depósito y la migración
    ese precio sale de las vistas; en el retiro forzado, de una corrida en seco de la misma salida que se revierte.

## 4. Harness (`local/nexus/secresearch/harness/morpho-org__bundles/NexusVaultBundles.t.sol`)

- **Entorno:** Morpho Blue (el mismo `Morpho.sol` que los otros cazadores de Bundles) con la IRM adaptativa real
  (0.8.19, que exige el adapter); tres mercados (dos del adapter y uno ajeno). Dos Vault V2 reales (0.8.28, por
  `deployCode` de su fábrica): uno con el adapter de Blue, topes, el mercado 0 como liquidez y penalidad de retiro
  forzado, y otro solo ocioso (para migraciones). Los dos cobran comisiones (10 % del rendimiento y 2 % anual de
  gestión) a una cuenta que no es de los actores, así que las acciones de comisión entran en el primer devengamiento
  de cada transacción.
- **Penalidad variable:** el curator la cambia entre llamadas: sin penalidad, 0,5 % o el máximo de Vault V2 (2 %). Las
  leyes leen la vigente; con una fija, un bundle que usara una constante en vez de la del adapter pasaba inadvertido.
- **Precio por acción no redondo:** los dos vaults tienen la tasa máxima de Vault V2 (200 % anual). Sin ella (0 por
  defecto) un vault no reconoce interés ni donaciones, el precio queda clavado en 1 y ningún redondeo de las vistas se
  ejercita: confundir acciones con activos o redondear al revés pasaba inadvertido. Con el interés de Blue y las
  donaciones, el precio llega a 1,06 en una corrida de 100 llamadas.
- **Actores:** cuatro usuarios con acciones en los dos vaults (que aprueban a los dos bundles) y dos referidos.
- **Entradas:** las cinco, con montos mezclados (1 de cada 4 crudos, el resto uniformes), comisiones extremas,
  controles de precio (sin control, justo el que realiza la llamada o uno peor), listas de mercados en distinto orden,
  con el ajeno en el medio o incompletas.
- **Escenario:** antes de la mitad de las salidas de VaultExitBundlesV1, el allocator saca la liquidez sin penalidad
  (lo ocioso y casi todo el mercado de liquidez) al otro mercado; sin eso, lo ocioso alcanzaba casi siempre.
- **Entre llamadas:** reasignaciones del allocator, préstamos y repagos en Blue (menos liquidez e interés), depósitos
  directos, donaciones a los vaults, cambios de penalidad y saltos de reloj.
- **Reversiones:** el log las separa por motivo: las validaciones del bundle, Vault V2 o Blue, el pánico aritmético
  (por ejemplo, salir con más de lo que se tiene) y los otros pánicos (división por cero cuando un depósito no da
  acciones, o la lista que no alcanza).

## 5. Verificación (31-oct, forge 1.8.6 en la PC)

En el proyecto reducido de `tools/forge_v2` (`NEXUS_PERFIL=vault-bundles`), con el fuzzing guiado por cobertura:

- pasa 64×200 con `0x2a` y `0x3` (12.800 llamadas cada una), sin falsos positivos ni reversiones del handler; en la
  última corrida pasaron las cinco entradas (9 y 11 depósitos, 7 y 5 retiros, 8 y 3 migraciones, 9 y 13 redenciones
  en especie y 9 y 10 retiros forzados), y una acción del vault con adapter terminó valiendo 1,060 y 1,047 activos
  (1,047 y 1,064 la del vault ocioso);
- se detectan las 28 mutaciones de `tools/forge_v2/mutaciones_vault_bundles.json`:

| Mutación | Ley que la ve |
|---|---|
| W1, W8, X7: la comisión de referido redondeada hacia arriba | VB-FEE (y VB-SHARES, VB-FUNDS) |
| W5: la comisión de referido va a quien llama | VB-FUNDS, VB-FEE |
| W2, W7, X6: sin el control de precio | VB-LIVE |
| W4, W6, X8: sin el control de exactamente uno, de la comisión o del plazo | VB-LIVE |
| W3: deposita a nombre del referido | VB-SHARES |
| W9, X10: el control de precio estricto | VB-LIVE (revierte con el precio exacto) |
| W10, W11, X9: el control de precio redondeado al revés | VB-LIVE |
| W12, W13: por acciones, retira esa cantidad de activo (confunde acciones con activos) | VB-FUNDS, VB-SHARES |
| X1, X5: desasigna sin descontar la penalidad | VB-KIND, VB-SHARES; VB-FUNDS, VB-FEE |
| X2, X3: la posición en Blue a nombre del bundle; lo ocioso no llega al usuario | VB-KIND |
| X4: retira del vault una unidad de más | VB-FUNDS |
| X11, X12: cobra la penalidad sobre el doble de lo que desasigna | VB-SHARES (la cota de acciones quemadas) |
| X13: no cuenta la liquidez del adapter de liquidez | VB-FUNDS |
| X14, X15: una penalidad fija en vez de la del adapter | VB-KIND; VB-FUNDS, VB-FEE, VB-SHARES |

Las W9 a W13 y X9 a X15 se sumaron con las mejoras del 31-oct. Salvo X12 y X13, ninguna se veía con la primera
versión del cazador: con el precio en 1, la penalidad fija, el control de precio sin borde exacto y sin la cota de
acciones del retiro forzado.

Campaña profunda (31-oct, de las 16:26 a las 16:58, 512×500 guiada por cobertura, 256.000 llamadas, semilla
`0xca1f61fd5c57cbfe`, `20261031-162639_vault-bundles_512x500_0xca1f61fd5c57cbfe`): **ninguna ley violada y 0
reversiones del handler**. En la última corrida pasaron 146 de 222 llamadas a los bundles (26 depósitos, 34 retiros,
19 migraciones, 43 redenciones en especie y 24 retiros forzados, 15 con desasignación), y la acción de los dos vaults
terminó valiendo 1,19 y 1,20 activos.

## 6. Qué NO cubre

- Vault V1 (MetaMorpho): `InKindRedemptionVaultV1` y los vaults V1 en `VaultBundlesV1`. Es la variante siguiente.
- Gates de Vault V2 (que consultan el `initiator` transitorio), permisos por firma y el token nativo.
- Pérdidas: el precio por acción solo sube (interés y donaciones); no hay deuda incobrable en Blue.
- Listas con mercados repetidos en la redención en especie (el bundle lo acepta y lo documenta).
- La guarda de reentrada (`initiator`): haría falta un token o un vault con ganchos.
