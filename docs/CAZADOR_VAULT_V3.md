# Cazador del Vault V3 (Yearn)

Estado: **variante A escrita y verificada con forge en la PC** (29-oct; arreglada el 30-oct). Pasa sin falsos
positivos ni reversiones en sus cuatro variantes (24×500 con las semillas `0x2a` y `0x3`, y `validate` sobre el repo
entero a 64×500), y las 28 mutaciones de referencia se detectan. La campaña profunda (768×1000) pasó sin leyes
violadas. Sus reversiones del handler venían de acciones infladas hasta desbordar, en el modelo y en el vault, y están
arregladas (sección 6). **No hay hallazgos.**

## 1. Qué versión y qué alcance

- **Programa:** Yearn Finance en Immunefi (en el catálogo, `in_scope` y `verified_by_owner`). El alcance (página
  actualizada el 25-jul-2026) lista **Vault V3.1.0** (`0xdD3F…7824`, el original) y su fábrica (`0x310a…bcAC`), y
  también la 3.0.4.
- **Versión probada: `v3.1.0` (`5b698f9`).** El `VaultV3.vy` verificado en Etherscan para el original
  `0xdD3FA86409658d207A9BE0141eE560C8db557824` (Vyper 0.3.10) tiene, normalizado a LF, el mismo SHA-256 que el del
  tag. Frente a la 3.0.4 la contabilidad casi no cambió: los módulos de límites pasaron a ser hooks con callback
  después del depósito y del retiro, se agregó una pausa y se reordenó la cola de retiro.
- **Sin FFI:** los tests del repo despliegan Vyper con `VyperDeployer` por FFI, que nexus no puede usar (R-2, R-6).
  El harness compila `VaultV3.vy` y `VaultFactory.vy` con forge (Vyper nativo, con el `vyper` 0.3.10 del venv en el
  PATH) y despliega como producción: la fábrica clona el original con `create_minimal_proxy_to` y lo inicializa.

## 2. Modelo

Estado crudo del vault (Vyper no empaqueta; el layout sale de `vyper -f layout`): `total_supply` (slot 20),
`total_debt` (21), `total_idle` (22), `balance_of` (HashMap en el slot 18, clave `keccak256(slot ++ dirección)`), y por
getters la deuda y el tope de cada estrategia, el bloqueo (`profit_unlocking_rate`, `full_profit_unlock_date`,
`last_profit_update`, `profit_max_unlock_time`), el mínimo ocioso, el límite de depósito, la pausa y el apagado.

- **Acciones:** `total_assets = total_idle + total_debt`; suministro efectivo `total_supply` menos lo desbloqueado
  (mismo esquema que TokenizedStrategy); conversión 1:1 con suministro 0 y 0 con activos 0; sin desplazamiento
  virtual.
- **Retiro (`_redeem`):** lo ocioso primero; después la cola, y por estrategia la parte de la pérdida no realizada del
  que retira (`convertToAssets(balanceOf(vault))` contra la deuda, redondeada hacia arriba, y acotada por lo líquido),
  el canje de `previewWithdraw` acciones, el exceso (acotado a la deuda: lo que la pasa queda en el balance del vault,
  fuera de `total_idle`) y la pérdida realizada, y `max_loss`.
- **Deuda (`_update_debt`):** bajar respeta el mínimo ocioso y lo retirable, exige que no haya pérdida no realizada y
  controla `max_loss`; subir respeta `max_debt`, el `maxDeposit` de la estrategia y el mínimo ocioso, y registra lo
  que de verdad salió.
- **Reporte (`_process_report`):** ganancia o pérdida contra la deuda; comisión y reembolso del accountant
  (acotado a lo que tiene); quema `⌈(pérdida + comisión)·s/A⌉` y bloquea `⌊(ganancia + reembolso)·s/A⌋`, neteando
  con lo desbloqueado; acciones de comisión al accountant y al protocolo; promedio ponderado del período.

## 3. Leyes (exactas, contra el almacenamiento crudo)

| Ley | Qué exige |
|---|---|
| YV-TA | `total_idle`, `total_debt` y la deuda de cada estrategia exactos; lo que devuelve `process_report` |
| YV-SUP | `total_supply` crudo exacto |
| YV-LOCK | buffer, tasa, fecha y `last_profit_update` exactos |
| YV-FEE | acciones del accountant y del protocolo exactas |
| YV-WD | acciones y activo de cada usuario exactos: lo que paga, cobra y pierde |
| YV-INF-2 | el precio contable (`total_assets / suministro efectivo`) no baja, salvo en un reporte con pérdida que el buffer no cubre o al bajar deuda con pérdida realizada |
| YV-VIEW | totales, conversiones, previews y `maxDeposit` exactos |
| YV-FUNDS | el activo en el vault, las estrategias, el accountant y lo perdido; el vault nunca tiene menos que `total_idle` |
| YV-LIVE | cada operación pasa si y solo si el modelo dice que pasa, y la configuración queda como se pidió |
| YV-LEDGER | Σ saldos crudos = `total_supply` |

## 4. Demostraciones

**El retiro no le pasa la pérdida a los demás.** Con `A` = activos contables y `s` el suministro efectivo, un retiro
de `a` deja `A − a` (lo ocioso baja lo pagado; la deuda baja lo retirado más la parte de la pérdida no realizada, y
el que retira cobra eso de menos), y quema `⌈a·s/A⌉` (withdraw) o pide `a = ⌊x·A/s⌋` (redeem): en los dos casos
`(A − a)/(s − x) ≥ A/s`. La pérdida no realizada la carga quien retira de esa estrategia; la realizada en el canje,
también (contra su `max_loss`).

**El reporte con ganancia no baja el precio.** Las comisiones se pagan con acciones que salen de lo que se bloquea
(la quema de `⌈comisión·s/A⌉` y la emisión de las mismas al accountant se compensan), y lo bloqueado es
`⌊ganancia·s/A⌋`: `(A + g)/(s + ⌊g·s/A⌋) ≥ A/s`. Con pérdida, la quema `⌈ℓ·s/A⌉` sale del buffer; si alcanza, el precio
no baja (`A·⌈ℓ·s/A⌉ ≥ ℓ·s`); si no alcanza, la pérdida baja el precio (excepción de YV-INF-2).

**El período del reporte nunca es 0** por el mismo argumento que en TokenizedStrategy (docs/CAZADOR_TOKENIZED_STRATEGY.md
§4): con buffer, el numerador del promedio ponderado es al menos el buffer.

## 5. Harness (variante A)

`local/nexus/secresearch/harness/yearn__yearn-vaults-v3/`:

- **`NexusVaultV3Hunter.sol`**: tres estrategias ERC-4626 de OpenZeppelin 4.9.5 (sin offset) con perillas de liquidez
  (`maxRedeem`), recorte por retiro (pérdida realizada) y pausa de depósitos; un accountant de prueba (comisión sobre
  la ganancia y reembolso sobre la pérdida, en bps); el modelo y las leyes.
- **`NexusVaultV3Invariant.t.sol`**: el handler y cuatro variantes: comisión del accountant 10 %; con 20 %, reembolso
  50 % y protocolo 10 %; 6 decimales sin comisión; sin bloqueo de ganancias. Acciones: deposit, mint, withdraw y redeem
  con `max_loss` 0, 1, 100 y 10.000 bps, transferencias; `update_debt` (subir, bajar, a 0, al máximo) y
  `process_report`; ganancia, pérdida, liquidez, recorte y pausa de cada estrategia; accountant, protocolo, tope de
  deuda, mínimo ocioso, tiempo de desbloqueo, pausa, apagado y saltos de reloj; y las secuencias ciclo completo,
  salida con la estrategia en problemas, baja de deuda con el mínimo ocioso por encima de lo ocioso (el vault retira
  de más) y vuelta a una configuración sana.
- Compila sin `via_ir` (como el repo).

Para iterar: `NEXUS_PERFIL=vault-v3` en [tools/forge_v2](../tools/forge_v2/README.md) (el clon en `5b698f9`). La
referencia es `validate` sobre el repo entero con `"aislado": true` y `"match_path": "test/nexus/*"`. El
`foundry.toml` del repo fija `match_path` a sus propios tests y, sin pisarlo, forge no corre ninguno del harness;
desde el 29-oct `validate` marca como error una corrida del harness sin tests. El manifiesto pide 64×500 y no
256×500: con el vault de Vyper y unas 35 leyes por llamada, 256×500 no entra en la hora que `limits.py` le da a los
tests. Las campañas largas van por el panel o por `tools/forge_v2`, que no tienen ese tope.

**Verificación del harness original (29-oct, forge 1.8.6 en la PC).** La del harness arreglado está en la sección 6.

- **Proyecto reducido:** las 4 variantes pasan 24×500 sin falsos positivos y con 0
  reversiones, con las semillas `0x2a` y `0x3` (12.000 llamadas por variante y semilla).
- **Referencia:** `validate` sobre el repo entero (`v3.1.0`, compilación aislada, 64×500, semilla
  `0x68a90a1321ee064a`) da 4 de 4 con 0 reversiones: 74 s de compilación y 1.687 s de tests.
- **Cobertura en la última corrida de cada variante a 24×500, con las dos semillas:**
  - de 17.000 a 19.700 leyes evaluadas;
  - reportes: 5 a 18 con ganancia, 1 a 15 con pérdida, 5 a 14 con comisión del accountant y 1 a 10 con reembolso;
  - retiros: 1 a 9 cargaron pérdida no realizada y 3 a 15 sacaron de alguna estrategia;
  - deuda: 8 a 45 subas y 9 a 21 bajas, de las que 2 a 12 retiraron de más por el mínimo ocioso;
  - 74 a 179 rechazos predichos por el modelo.
- **Lo que el cazador recorre poco:** los retiros con pérdida realizada en la estrategia (0 a 2 por corrida) y con
  exceso sobre la deuda (0 o 1).
- **La última corrida de `validate`:** fue más pobre (0 o 1 reporte por tipo y hasta 5 retiros desde estrategias).
  Como las cuatro variantes comparten la semilla, es la misma secuencia de llamadas en las cuatro. El log de
  `afterInvariant` muestra solo la última corrida.

**Mutaciones de referencia** ([tools/forge_v2/mutaciones_vault_v3.json](../tools/forge_v2/mutaciones_vault_v3.json);
64×200, semilla `0x2a`, con `NEXUS_PERFIL=vault-v3`): las 28 se detectan, cada una en las 4 variantes (la
numeración salta W7 y W16). Cada ley ve al menos una mutación, salvo YV-LEDGER: ninguna de las 28 cambia un saldo
sin cambiar el suministro. W14 no se detectaba hasta que se sumó la secuencia del mínimo ocioso: el fuzzer casi
nunca bajaba deuda con el mínimo por encima de lo ocioso.

| Mutación | Variantes que la ven | Leyes |
|---|---|---|
| W1 `convert_to_assets` no redondea hacia arriba | las 4 | YV-VIEW |
| W2 `convert_to_shares` no redondea hacia arriba | las 4 | YV-VIEW |
| W3 el depósito suma un activo de más a `total_idle` | las 4 | YV-TA, YV-FUNDS |
| W4 la pérdida no realizada no se le cobra al que retira | las 4 | YV-TA, YV-WD, YV-INF-2, YV-FUNDS, YV-LIVE |
| W5 la pérdida no realizada no baja la deuda | las 4 | YV-TA |
| W6 la parte de la pérdida no realizada no redondea hacia arriba | las 4 | YV-TA, YV-WD, YV-FUNDS |
| W8 el retiro de la estrategia redondea las acciones hacia abajo | las 4 | YV-TA, YV-INF-2, YV-FUNDS, YV-LIVE |
| W9 el idle suma lo pedido aunque haya pérdida | las 4 | YV-TA, YV-FUNDS |
| W10 `total_idle` queda con un activo de más al retirar | las 4 | YV-TA, YV-FUNDS |
| W11 `max_loss` no se controla | las 4 | YV-LIVE |
| W12 lo retirado al bajar deuda no se acota a la deuda | las 4 | YV-LIVE |
| W13 bajar deuda descuenta lo retirado y no lo pedido | las 4 | YV-TA |
| W14 bajar deuda ignora el mínimo ocioso | las 4 | YV-TA, YV-FUNDS |
| W15 subir deuda ignora `max_debt` | las 4 | YV-TA, YV-FUNDS |
| W17 el reporte quema acciones redondeando hacia abajo | las 4 | YV-LOCK, YV-FEE, YV-SUP |
| W18 las acciones de comisión suman una | las 4 | YV-SUP, YV-FEE, YV-INF-2 |
| W19 la parte del protocolo suma una acción | las 4 | YV-FEE |
| W20 el reporte bloquea redondeando hacia arriba | las 4 | YV-SUP, YV-LOCK, YV-INF-2 |
| W21 el suministro final no descuenta lo desbloqueado | las 4 | YV-SUP, YV-LOCK, YV-INF-2 |
| W22 la quema del reporte no se acota al buffer | las 4 | YV-LIVE |
| W23 el reembolso no entra a `total_idle` | las 4 | YV-TA |
| W24 la ganancia no sube `total_debt` | las 4 | YV-TA, YV-INF-2 |
| W25 la pérdida no baja `total_debt` | las 4 | YV-TA |
| W26 el promedio ponderado cuenta lo recién bloqueado como previo | las 4 | YV-LOCK |
| W27 la tasa de desbloqueo suma uno | las 4 | YV-LOCK |
| W28 el reporte no mueve `last_profit_update` | las 4 | YV-LOCK |
| W29 vencida la fecha no se desbloquea nada | las 4 | YV-VIEW |
| W30 el desbloqueo en 0 no quema el buffer | las 4 | YV-SUP, YV-LOCK, YV-INF-2 |

Las leyes de más en algunas filas son el efecto en cadena de la mutación.

## 6. La campaña profunda y el dominio del cazador (30-oct)

**La campaña.** 768×1000 (768.000 llamadas por variante, semilla `0xe782c4dd280d82a0`, del 29-oct a las 18:17 al
30-oct a las 02:49): las cuatro variantes en verde, sin ninguna ley violada. Pero el handler revirtió en dos, y esas
secuencias quedaron sin verificar:
- en la de comisiones, 43 veces: `stressExit` 14, `idleFloor` 11, `updateDebt` 6, `cycle` 5, `redeem` 4, `deposit` 2
  y `withdraw` 1;
- en la base, 31: `cycle` 15, `report` 8, `stressExit` 6, `idleFloor` 1 y `updateDebt` 1;
- en la de 6 decimales y en la sin bloqueo, ninguna.

**La causa: acciones infladas, no el vault.** Se reprodujo con `fail_on_revert` (variante base, semilla `0x204`). En
la llamada 78 de una corrida, un `stressExit` deposita y el modelo revierte con `panic 0x11`. Antes de ese depósito el
vault tenía unas 1,2e56 acciones contra 7,3e23 de activo, unos 6e-33 de activo por acción. La conversión del
depósito (`a·s`, hasta 1e24 × 1,2e56) pasa de 2^256. Así se llega:
- una pérdida casi total de una estrategia, reportada, deja el precio por acción cerca de 0;
- el depósito siguiente emite `a·s/A` acciones, y con `A` de unas pocas unidades eso multiplica `s` (con 18
  decimales: 1e24, 1e48, 1e72...);
- dos o tres vueltas después, desborda cualquier cuenta con `s`: la conversión del depósito, las vistas
  (`convertToShares(10^dec)`), la tasa de desbloqueo o las acciones de comisión de un reporte.

El vault hace las mismas cuentas con la aritmética chequeada de Vyper (`_convert_to_shares` calcula
`assets · total_supply`), así que en ese estado también revierte. Un vault con 1e56 acciones respaldadas por una
fracción de token deja de aceptar depósitos, y es un régimen sin sentido económico: **no es un hallazgo**. Con 6
decimales los montos son un millón de veces más chicos, y sin bloqueo no están la tasa ni el buffer: por eso esas dos
variantes no revirtieron.

**El arreglo.**
- **El modelo a prueba de desbordes:** el handler llama al modelo de cada operación (depósito, retiro, `update_debt` y
  `process_report`) con una llamada externa. Si una cuenta del modelo desborda o divide por cero, la operación se
  espera rechazada, porque el vault (o el `mulDiv` de la estrategia) hace la misma cuenta. YV-LIVE controla que el
  vault revierta.
- **El dominio:** `total_supply` crudo hasta 2^128. Un depósito o un reporte que lo pasaría se saltea. El activo total
  del handler no pasa de unos 2^92, así que con ese tope ninguna vista ni ley del cazador desborda.
- **Dos métricas nuevas:** las operaciones cuyo modelo desbordó y las salteadas por el dominio.

**Pruebas de regresión**, en las cuatro variantes:
- `test_inflacionDeAcciones`: ocho vueltas de depósito, toda la deuda a una estrategia, una pérdida que deja 1 de
  activo y el reporte; después una ganancia y su reporte.
- `test_desbordeEnElReporte`: con `total_supply` en 1e38 y 1 de activo, la comisión de un reporte (acciones a quemar
  × comisión) desborda en el modelo y en el vault, que revierte como predice el modelo.

Con el harness viejo, las dos revierten por desborde, salvo la segunda en 6 decimales, que no tiene comisión y no
prueba nada. Con el arreglado pasan.

**Verificación del harness arreglado (30-oct, forge 1.8.6 en la PC).**

- **Proyecto reducido:** las cuatro variantes pasan 24×500 con `0x2a` y `0x3`, sin falsos positivos ni reversiones, y
  las dos pruebas de regresión pasan en las cuatro: 12 de 12 pruebas con cada semilla.
- **Referencia:** `validate` sobre el repo entero (`v3.1.0`, compilación aislada, 64×500, semilla
  `0x689e3107429f5a13`) da 12 de 12 con 0 reversiones en 128.000 llamadas: 46 s de compilación y 891 s de tests.
- **Mutaciones:** las 28 de referencia se detectan, cada una en las cuatro variantes y con las mismas leyes que en la
  tabla de la sección 5.
- **Confirmación con `fail_on_revert`:** las dos variantes que revertían (comisiones y base), dos copias cada una a
  64×1000 con semillas nuevas (`0x301` a `0x304`), dan 256.000 llamadas sin ninguna reversión ni ley violada. A la
  tasa de la campaña, con el harness viejo se esperaban unas 12.
- **Cobertura de la última corrida:** con `0x3`, en los rangos de la verificación original (5 a 15 reportes con
  ganancia, 3 a 11 con pérdida, 6 a 45 subas y 7 a 22 bajas de deuda, 77 a 192 rechazos). Con `0x2a` fue pobre en las
  cuatro variantes, que corren la misma secuencia: 0 o 1 reporte, una suba de deuda y 222 a 224 rechazos.
- **El borde es raro:** en ninguna corrida de la verificación hubo operaciones desbordadas ni salteadas por el
  dominio. En la campaña aparecía una vez cada 18.000 a 25.000 llamadas; las pruebas de regresión lo fuerzan.

## 7. Qué NO cubre

- La variante B: estrategias reales de TokenizedStrategy v3.1.0 (en vivo), donde `convertToAssets` incluye lo
  simulado. Es el paso siguiente.
- Los hooks de depósito y retiro (los pone un rol privilegiado), `buy_debt`, `force_revoke_strategy`, la cola elegida
  por el usuario, el auto-asignado de deuda al depositar, `process_report` del propio vault (donaciones al vault).
- `total_supply` por encima de 2^128 (sección 6): ahí el vault y el modelo desbordan en las mismas cuentas.
