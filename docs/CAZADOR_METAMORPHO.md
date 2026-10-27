# Cazador de vulnerabilidades para MetaMorpho

`NexusVulnerabilityHunter.sol` es la capa de contabilidad fantasma y leyes formales del harness de MetaMorpho
(`local/nexus/secresearch/harness/morpho-org__metamorpho/`). Se hereda en el handler y vigila cada acción con un
modificador. Caza tres familias de fallas:

1. inflación y redondeo;
2. desincronización de comisiones;
3. fugas de valor por deuda incobrable o por reasignación entre mercados.

Ninguna ley toma sus valores esperados de los `view` derivados del vault (`totalAssets`, `convert*`, `preview*`,
`max*`). Esos valores salen del estado crudo de Morpho Blue, leído con un solo `extSloads`, y de una aritmética propia.

| Archivo | Qué es |
|---|---|
| `NexusVulnerabilityHunter.sol` | `NexusHunterMath` (aritmética exacta), `NexusClock` y el contrato abstracto `NexusVulnerabilityHunter`: estado fantasma, fotos, leyes, gobierno y macros de cacería |
| `NexusMetaMorphoInvariant.t.sol` | El handler de siempre, con la misma API. Hereda el cazador y cada acción lleva `hunted(...)` |
| `NexusMetaMorphoHunter.t.sol` | Entorno multi-mercado: 4 mercados, topes que se alcanzan, colas en distinto orden, gobierno con timelock, saltos a la frontera de cada timelock y las macros. Tres variantes: sin comisión, 25 % y 6 decimales |

Estado y resultados: ver [Verificación](#verificación).

## 1. Auditoría del handler del PR #72

El pedido mencionaba un PR con un handler multi-mercado: colas dinámicas, decisiones derivadas por hash de la
semilla y contadores por acción. **Ese PR no está en el repo.** No hay PRs abiertos, y la última versión del handler
es la del PR #72 (fusionado), con un mercado con préstamos, el mercado idle y colas fijas. Se auditó esa versión. El
cazador es genérico (N mercados, colas y gobierno) para enchufarse al handler multi-mercado cuando llegue.

| Acción | Qué ejercita del vault y de Morpho | Qué verificaba | Qué faltaba (ahora lo cubre) |
|---|---|---|---|
| `deposit`, `mint` | `_accrueFee`, `_supplyMorpho` (cola de suministro y topes), `lastTotalAssets` | `max*` no revierte, `preview*`, precio con ±4 wei, `convertToAssets` ≥ precio | Acciones exactas contra un TA independiente (H-INF-1), comisión exacta (H-FEE-1), L exacto (H-FEE-2), reparto por la cola (H-SOLV-8), polvo exacto (H-SOLV-6) |
| `withdraw`, `redeem` | `_withdrawMorpho` (cola de retiro y liquidez) | ídem | Ídem, más que el receptor reciba exactamente lo que sale de Morpho y que se respete el orden de la cola |
| `transfer` | ERC-20 | precio | Conservación de saldos, sin comisión y ρ idéntico (H-LEDGER, H-FEE-5) |
| `donate` | `supply` a nombre del vault | precio | Acreditación exacta y ganancia ∈ [d − ⌈P⌉, d] (H-SOLV-6); la donación entra al rendimiento Y |
| `borrow`, `repay` | deuda y devengamiento | precio | Deuda exacta y TA intacto (H-DEBT-1, H-SOLV-2) |
| `accrue` | devengamiento | precio | Deuda reportada igual a la teórica (H-DEBT-1) y envolvente económica (H-DEBT-2) |
| `badDebt` | liquidación con deuda incobrable | **nada** (solo un contador) | Pérdida exacta y a prorrata, nadie escapa ni es señalado (H-SOLV-5) |
| `reallocate` | `reallocate` entre `market` e `idle` | precio (±4 wei) | Σ retirado = Σ suministrado, topes y fuga ≤ Σ⌈P⌉ (H-SOLV-4, H-SOLV-7) |
| `warp` | tiempo | precio | ρ y TA no bajan con el tiempo; el interés entra a Y (H-INF-2) |
| `check()` | — | Σ saldos = T; Σ `previewRedeem` ≤ `totalAssets`; el vault no retiene tokens | Solvencia contra el respaldo de todos los mercados (H-SOLV-1) y `totalAssets()` como sujeto (H-SOLV-2) |

Problemas de fondo del handler original:

- **Autorreferencia.** Todos los valores esperados salían de los `view` del propio vault. Un error coherente
  entre el `view` y la operación es invisible. Por ejemplo, M12 y M17 (abajo) dejan `lastTotalAssets` mal por 1 wei o
  más, y `_exactPrice` usa ese mismo valor: el harness original no detecta ninguna de las dos (ver
  [Verificación](#verificación)).
- **Tolerancia fija de 4 wei por acción.** Esconde fugas acumuladas: una secuencia que pierde 3 wei por llamada
  nunca dispara.
- **Sin transiciones de gobierno.** No hay topes con timelock, ni habilitación de mercados con supply, ni remoción
  forzada, ni cambios de colas o de comisión. Además el tope de 1e30 nunca se alcanza, así que el orden de las colas
  no importa.

## 2. Modelo

Constantes: $v = 10^{\delta}$ (acciones virtuales del vault), $V_S = 10^6$ y $V_A = 1$ (virtuales de Morpho),
$W = 10^{18}$.

**Mercado $m$ de Morpho Blue.** $A$, $S$, $B$, $S_B$ son los totales de suministro y de deuda, en activos y en
shares, y $s$ son las shares del vault. Devengamiento perezoso de $t_0$ a $t$ con tasa $r$:

$$x = r\,(t-t_0),\qquad \tau(x) = x + \left\lfloor \tfrac{x^2}{2W} \right\rfloor + \left\lfloor \tfrac{\lfloor x^2/2W\rfloor\, x}{3W} \right\rfloor,\qquad I = \left\lfloor \tfrac{B\,\tau(x)}{W} \right\rfloor,\qquad \hat A = A + I,\quad \hat B = B + I$$

$$P_m = \frac{\hat A_m + V_A}{\hat S_m + V_S},\qquad C_m = \lfloor s_m P_m \rfloor \quad\text{(reclamo del vault)}$$

**Vault.** $\mathcal W$ es la cola de retiro **fantasma** y $L$ el `lastTotalAssets` **fantasma**:

$$TA = \sum_{m\in\mathcal W} C_m,\qquad J = \max(0,\, TA - L),\qquad F = \left\lfloor \tfrac{J f}{W}\right\rfloor,\qquad \sigma = \left\lfloor \tfrac{F\,(T+v)}{TA - F + 1}\right\rfloor,\qquad T^+ = T + \sigma$$

$$\rho = \frac{TA - F + 1}{T + v}\ \text{(tipo de cambio de la especificación)},\qquad \mathcal R = \text{idle} + \sum_{m\in\mathcal M} C_m\ \text{(respaldo de todos los mercados)}$$

El fantasma **mide** el estado crudo de Morpho, el libro de acciones del vault y los saldos del token. Las
transiciones (L, colas, topes, pendientes, timelock, libros por usuario y de comisiones) las **predice** con sus
propias reglas.

**Lema D (polvo de Morpho).** Proveer $x$ en un mercado deja $C' - C \in [x - \lceil P\rceil,\ x]$; retirar $x$ por
activos, $C' - C \in [-x - \lceil P\rceil,\ -x]$; retirar por shares es exacto. Una llamada nunca crea valor y pierde
a lo sumo una share de Morpho.

**Lema F.** $\rho$ no baja con el tiempo: TA sube por enteros $\Delta$ y $F$ sube a lo sumo
$\lceil \Delta f/W\rceil \le \Delta$. Acuñar $\sigma$ no baja $\rho$, porque $\sigma \le F(T+v)/(TA-F+1)$ implica
$(TA+1)/(T^+ + v) \ge (TA - F + 1)/(T+v)$.

**Teorema 1 (redondeo y no dilución).** Con $T^+_v = T^+ + v$:

$$\text{deposit: } s = \left\lfloor \tfrac{a\,T^+_v}{TA+1}\right\rfloor \quad \text{mint: } a = \left\lceil \tfrac{s\,(TA+1)}{T^+_v}\right\rceil \quad \text{withdraw: } s = \left\lceil \tfrac{a\,T^+_v}{TA+1}\right\rceil \quad \text{redeem: } a = \left\lfloor \tfrac{s\,(TA+1)}{T^+_v}\right\rfloor$$

Junto con el Lema D: quien opera nunca gana, y los demás tenedores pierden a lo sumo
$\delta = \sum \lceil P\rceil$ por operación, en cualquier secuencia. Esa es la cota del *dust griefing*. Un depósito
emite 0 acciones solo si vale menos que una acción, $a < (TA+1)/T^+_v$: esa es la ventana de redondeo a cero que ve
el próximo usuario.

**Teorema 2 (comisiones).** Después de cada reinicio de $L$ (deposit, mint, withdraw, redeem, setFee) queda
$G = TA - L \le 0$. Entre reinicios, $G$ solo sube por rendimiento $Y$: interés más donaciones a mercados de la cola.
Habilitar un mercado suma lo mismo a $TA$ y a $L$. Por eso:

$$\sum_k J_k \le Y \quad\Rightarrow\quad \sum_k F_k \le \left\lfloor \tfrac{f_{\max}\,Y}{W} \right\rfloor,\qquad \text{valor}(\sigma_k) = \left\lfloor \tfrac{\sigma_k (TA_k+1)}{T_k + \sigma_k + v}\right\rfloor \le F_k$$

Un salto de tiempo seguido de un depósito relámpago no puede cambiar la comisión. El depósito entra después de
acuñar $\sigma$ y reinicia $L$ a $TA + a$, así que el canje inmediato acuña 0.

**Teorema 3 (solvencia).**
$\lfloor T^+ (TA+1)/(T^+ + v)\rfloor \le TA \le \mathcal R$: lo que los tenedores pueden reclamar está respaldado,
también durante remociones pendientes. Una remoción forzada baja TA exactamente en $C_m$ y no toca $L$. Reasignar no
crea valor y pierde a lo sumo $\sum\lceil P\rceil$. La deuda incobrable $B_d$ le cuesta al vault exactamente su parte:

$$\left\lfloor \tfrac{s\,B_d}{\hat S + V_S} \right\rfloor \le \Delta C \le \left\lceil \tfrac{s\,B_d}{\hat S + V_S}\right\rceil$$

Además ningún saldo de acciones cambia en ese momento.

## 3. Leyes

Cada acción vigilada toma una foto antes y otra después, y evalúa las leyes de esa operación. Entre dos acciones
solo puede pasar el tiempo (H-SYNC). Las comparaciones de tipos de cambio son productos cruzados de 512 bits, sin
redondeo y sin tolerancia fija: la única holgura es el polvo exacto de esa operación.

| Código | Ley | Caza |
|---|---|---|
| H-INF-1 | Las cuatro fórmulas del Teorema 1, en desigualdades exactas: justo y ajustado | Redondeo invertido, TA o T mal tomados |
| H-INF-2 | $(TA'-F'+1+\delta)(T+v) \ge (TA-F+1)(T'+v)$, con $\delta$ = polvo o pérdida exactos; entre acciones, $\rho$ y $TA$ no bajan | Dilución de los demás tenedores |
| H-INF-3 | Si $s = 0$, entonces $a < (TA+1)/T^+_v$; la víctima pierde a lo sumo $\lceil(TA+1)/T^+_v\rceil + \delta + 1$ | Redondeo a cero del próximo usuario |
| H-INF-4 | `mint` con $s > 0$ cuesta al menos 1 wei; un retiro con $w > 0$ quema al menos una acción | Acciones o activos gratis |
| H-INF-5 | Macro de inflación: con el vault vacío, el atacante no gana nada; sin comisión, ganancia del atacante ≤ pérdida de la víctima | Ataque de inflación (polvo, donación, retiros parciales) |
| H-INF-6 | Tokens sueltos en el contrato: TA, T, L, saldos y $\rho$ idénticos; después del skim no queda nada | Manipulación del saldo del contrato |
| H-FEE-1 | Acciones de comisión acuñadas = $\sigma$ calculada con el $L$ fantasma | Comisión sobre la base equivocada |
| H-FEE-2 | `lastTotalAssets` = $L$ fantasma después de cada acción | Comisión sobre depósitos, o sin descontar retiros |
| H-FEE-3 | Σ valor acuñado ≤ Σ $F$ | Cobro de más al acuñar |
| H-FEE-4 | Σ $F$ ≤ $\lfloor f_{\max} Y/W\rfloor$; en el relámpago, valor acuñado ∈ $[F - \lceil (TA+1)/(T+v)\rceil - 1,\ F]$ | Comisión desproporcionada por saltos de tiempo y depósitos relámpago |
| H-FEE-5 | Relámpago: canjeado ≤ depositado; sin comisión fuera de las acumulaciones; saldo del receptor = acuñadas − canjeadas | Captura de rendimiento pendiente |
| H-SOLV-1 | $\lfloor T^+(TA+1)/(T^++v)\rfloor \le \mathcal R$ | Insolvencia |
| H-SOLV-2 | `totalAssets()` = $\sum_{\mathcal W} C_m$; borrow, repay y accrue no mueven TA | Mercados mal sumados, saltos al realizar intereses |
| H-SOLV-3 | $B \le A$; $\sum(A-B) \le$ saldo de Morpho; shares sin dueño | Insolvencia de Morpho |
| H-SOLV-4 | Reasignación: Σ salida = Σ entrada, sin tokens fuera de Morpho, fuga ≤ Σ⌈P⌉, nunca crea valor (también en ciclos) | Fugas al mover capital |
| H-SOLV-5 | Deuda incobrable: registro exacto, $B_d \le b + 1$, pérdida a prorrata, ningún saldo de acciones cambia | Pérdidas mal repartidas |
| H-SOLV-6 | Vault con Morpho: $TA' \in [TA \pm a - \sum\lceil P\rceil,\ TA \pm a]$; donaciones acreditadas exactamente; el receptor recibe lo que sale | Creación o fuga de valor por redondeo |
| H-SOLV-7 | Lo suministrado respeta el tope | Topes ignorados |
| H-SOLV-8 | El reparto es el modelo exacto de las colas: suministro en orden con topes, retiro en orden con liquidez, mercados no visitados intactos | Errores de asignación |
| H-DEBT-1 | Deuda reportada = deuda teórica del fantasma, bit a bit, después de devengar, prestar o repagar | Devengamiento incorrecto |
| H-DEBT-2 | $\lfloor B x/W\rfloor \le I \le \lceil B(e^{x/W}-1)\rceil$ si $x \le W$ (con una cota superior rigurosa de $e^y - 1$) | Interés fuera de la teoría económica |
| H-DEBT-3 | Ningún otro mercado cambia; las shares de deuda tienen dueño; no queda deuda incobrable sin realizar | Contaminación entre mercados |
| H-GOV-1..4 | Cada acción de gobierno se compara con la predicción: éxito o reversión, efecto en topes, pendientes, colas (con orden), timelock y TA | Timelocks que vencen antes, remociones sin esperar, colas inconsistentes |
| H-LEDGER | T = Σ saldos conocidos; cada saldo = acuñadas − quemadas ± transferidas | Acciones creadas o destruidas por fuera |
| H-SYNC | Entre acciones vigiladas, el estado crudo (hash del extSloads), T y los saldos de token no cambian | Acciones sin vigilar y desincronización del arnés |

## 4. Macros de cacería

Cada macro es una secuencia dirigida dentro de una sola llamada del fuzzer. Cada paso pasa por sus leyes y, al
final, se evalúan las leyes de la secuencia completa. Con hardware limitado esto da mucha más señal por llamada que
encadenar pasos sueltos al azar.

- `_huntInflation`: el atacante deposita polvo cerca del precio de una acción, se queda con 1 acción, dona por
  Morpho, deposita la víctima y el atacante sale. Leyes H-INF-3 y H-INF-5.
- `_huntFeeFlash`: salto de tiempo, depósito masivo y canje inmediato. Leyes H-FEE-4 y H-FEE-5.
- `_huntReallocCycle`: 2 a 4 saltos entre mercados de la cola, de polvo, del reclamo entero (retiro por shares) o al
  azar. Ley H-SOLV-4 acumulada.
- `_huntRawDonation`: tokens sueltos en el contrato, un depósito y skim. Ley H-INF-6.

`NexusMetaMorphoHunter.t.sol` además salta a `validAt − 1`, `validAt` y `validAt + 1` de cada pendiente
(`warpToBoundary`). Un salto al azar de hasta 30 días casi nunca toca la frontera exacta de un timelock.

## 5. Cómo integrarlo en otro handler

1. Heredar `NexusVulnerabilityHunter` en lugar de `NexusMetaMorphoBase`.
2. Al final del constructor, llamar `_hunterInit(tenedores, mercados)`, con todos los que pueden tener acciones y
   todos los mercados que el vault puede llegar a tocar. Si el constructor cambia el gobierno después, se vuelve a
   llamar.
3. Implementar `_hunterFlag(qué, x, y)`; en nexus deriva a `_flag`, y `check()` devuelve la primera violación.
4. Agregar a cada acción `hunted(OP_*, quién, destinatario, índiceDeMercado)`. Es un modificador: **no cambia la
   firma ni el cuerpo**. `warp` puede quedar sin vigilar, porque el siguiente `_hBegin` atribuye el interés.
5. Las acciones de gobierno usan `_hBegin` y `_hGov*(…, ok, pre)`, con `ok` igual a si la llamada revirtió (try/catch).
6. Las macros (`_hunt*`) son internas: el handler decide cuáles expone.

Supuestos del fantasma, que hay que revisar al cambiar de entorno:

- La IRM no tiene estado (la del entorno es `IrmMock`).
- Los deudores son `BORROWER` y `BAD_BORROWER`.
- El vault es el único proveedor de sus mercados (`hSoleSupplier`).
- Los tenedores de acciones son conocidos.

Con via_ir el optimizador puede reutilizar un `block.timestamp` leído antes de `vm.warp`. Por eso el cazador lee la
hora con `NexusClock`, en otro contexto de llamada.

## 6. Cómo leer el informe

`validate` imprime el informe al terminar y lo guarda en `%LOCALAPPDATA%\nexus\secresearch\validate\`, es decir
`C:\Users\<usuario>\AppData\Local\nexus\...`. El Explorador oculta `AppData`; se abre con
`explorer $env:LOCALAPPDATA\nexus\secresearch\validate`. El ciclo programado escribe además `para_claude.md` en
`%LOCALAPPDATA%\nexus\secresearch\`.

Los contadores salen de la última corrida de cada campaña: forge la repite al final para juntar los logs de
`afterInvariant`.

| Línea | Qué es | Cuándo preocupa |
|---|---|---|
| corridas · llamadas · reversiones | totales de la campaña | reversiones por encima del 5 % |
| llamadas/reversiones por acción | métricas de forge por función del handler | una acción que revierte casi siempre no explora nada |
| `verificaciones` | chequeos de precio del handler original | 0: la corrida pasó en vacío |
| `cazador: leyes evaluadas` | leyes del cazador evaluadas | 0 |
| `depositos con 0 acciones` y `precio maximo de una accion` | la ventana de redondeo a cero: un depósito menor que el precio de una acción recibe 0 acciones | nunca por sí sola: H-INF-1 exige el redondeo exacto. Dice si la campaña llegó a precios extremos |
| `mayor perdida de una victima` | lo que pierde la víctima en la macro de inflación | nunca por sí sola: H-INF-3 ya exige a lo sumo una acción más el polvo |
| `comision devengada` y `comision acunada (valor)` | Σ F y el valor de las acciones de comisión al acuñarse | nunca por sí sola: H-FEE-1 verifica cada acuñación exacta y H-FEE-3 que no supere lo devengado |
| `perdida por deuda incobrable` y `por remocion forzada` | pérdidas que provocan a propósito `badDebt*` y la remoción de mercados con supply | nunca por sí sola: H-SOLV-5 y H-GOV-3 las verifican exactas |
| `gobierno con efecto` | acciones de gobierno que cambiaron algo, por tipo | un tipo en 0: esa parte del gobierno no se exploró |

**Activos de 18 decimales.** `DECIMALS_OFFSET` es 0 y hay una sola acción virtual. MetaMorpho documenta que así la
protección contra la inflación es baja, y recomienda un depósito inicial al crear el vault (`IMetaMorpho.sol`, en
`DECIMALS_OFFSET`). Por eso, en las suites de 18 decimales, una donación a un vault casi vacío puede llevar el precio
de una acción a valores enormes. Desde ese estado:

- hay depósitos que reciben 0 acciones, y la víctima puede perder hasta el precio de una acción;
- la comisión acuñada puede quedar muy por debajo de la devengada, porque cada acumulación redondea las acciones de
  comisión hacia abajo y puede perder hasta una acción entera.

Es un comportamiento conocido y documentado, no un hallazgo. Lo que se investiga es una ley `H-...` que falle: por
ejemplo, un atacante que gana con la inflación (H-INF-5) o una víctima que pierde más de una acción (H-INF-3). Con
6 decimales, `DECIMALS_OFFSET` es 12 e inflar el precio cuesta 10^12 veces más. Aun así puede pasar en las suites,
porque el fuzzer dona hasta 1e28 unidades sin escalar por decimales: con 6 decimales son 10^22 tokens, más de los que
existen.

## Verificación

En la nube, sin forge: EDR 0.25 con solc-js (Morpho 0.8.19, MetaMorpho 0.8.21 y harness 0.8.26 con via_ir), sobre
MetaMorpho `ded84e5`. Ver `tools/edr/README.md`.

**Falsos positivos.** Los 6 invariantes, 3 del handler original con el cazador y 3 multi-mercado, pasan con
256 corridas × 500 llamadas en la versión final con las semillas `0x2a` y `0x3` (1,5 M de llamadas) y en la anterior,
sin las macros de frontera, la identidad de valor ni `claimFees`, con `0x2a` y `0x1` (otros 1,5 M). La suite ERC-4626
de a16z pasa 78 de 78 con 2.000 corridas.

Durante el desarrollo aparecieron ocho falsos positivos y se corrigieron en el cazador o en el entorno, nunca
agregando tolerancia:

- comisión pendiente calculada con el L anterior;
- una desigualdad de `withdraw` invertida;
- la comisión pendiente contada como devengada en acciones de gobierno que no acumulan;
- `block.timestamp` cacheado por via_ir después de `vm.warp`;
- colas de suministro con repetidos, donde MetaMorpho documenta que `maxDeposit` promete de más;
- retiros de las macros sin acotar a la liquidez;
- aserciones de ganancia del atacante que no valían con comisión de desempeño;
- depósitos cuyas acciones no entran en `uint256`: revierten con `Panic(0x11)` en cualquier ERC-4626 (detalle abajo,
  en la segunda corrida).

**Reversiones.** Están entre 0,3 y 0,4 % en los invariantes del handler original y entre 2 y 4 % en los
multi-mercado. Con `failOnRevert` en 8 semillas × 3 variantes, todas son `SupplyCapExceeded` o `UnauthorizedMarket`:
la reasignación original no conoce los topes y `reallocateTo` pide más que el tope a propósito una vez de cada ocho.
Ninguna sale del cazador.

**Costo.** Con 4 núcleos compartidos entre 6 suites, el handler original con el cazador corre a ~735 llamadas/s por
suite (antes ~1.000) y el multi-mercado a ~560-620.

**Mutaciones.** Corridas con `python3 tools/edr/mutate.py`: 64 × 100 por invariante y 256 corridas de fuzz. Con el
cazador se detectan **21 de 21**, y en todas dispara una ley `H-...`. El harness original, sin el cazador, no detecta
10 de las 14 nuevas. La columna del cazador dice qué ley dispara y en cuántas de las 6 suites de invariantes (3 del
handler original y 3 multi-mercado):

| Mutación | Harness original | Con el cazador |
|---|---|---|
| M1 `deposit` redondea acciones hacia arriba | sí | H-INF-1 (6) |
| M2 `maxWithdraw` ignora la liquidez | sí | H-INF-5 en la macro de inflación, más `max*` (6) |
| M3 `deposit` no actualiza L (comisión sobre depósitos) | solo con comisión | H-FEE-2 (6, también sin comisión) |
| M4 `mint` redondea el costo hacia abajo | sí | H-INF-1 (6) |
| M5 `totalAssets` ignora el mercado idle | sí | H-SOLV-2 (3), más el precio original (3) |
| M6 `redeem` redondea activos hacia arriba | sí | H-INF-1 (6) |
| M7 comisión calculada de más | sí | H-FEE-1, más `convertToAssets` (4) |
| M8 habilitar un mercado con supply no suma su reclamo a L | no | H-FEE-2 (3) |
| M9 remover un mercado con supply sin esperar el timelock | no | H-GOV-3 (3) |
| M10 los timelocks vencen un segundo antes | no | H-GOV-1 (3) |
| M11 `_supplyMorpho` redondea el supply hacia abajo (pasa el tope por 1 wei) | no | H-SOLV-8 (3) |
| M12 `withdraw` no descuenta lo retirado de L | no | H-FEE-2 (6) |
| M13 `reallocate` no controla el tope | no | H-SOLV-7 (3) |
| M14 `totalAssets` suma la cola de suministro | no | H-SOLV-2 (3) |
| M15 acciones de comisión redondeadas hacia arriba (1 acción de más) | sí | H-FEE-1 y otras (4) |
| M16 `deposit` no acumula la comisión pendiente | sí | H-FEE-1 (3), más `previewDeposit` |
| M17 `deposit` deja L 1 wei arriba | no | H-FEE-2 (6): `18224` contra `18225` |
| B1 Morpho devenga un segundo de más | sí (a16z) | H-DEBT-1, H-SOLV-5, H-SOLV-6, H-SOLV-8 (6) |
| B2 Morpho `supply` redondea las shares hacia arriba | no | H-SOLV-6, H-SOLV-8 (6) |
| B3 Morpho no descuenta la deuda incobrable del suministro | sí (`max*`) | H-SOLV-5 (6) |
| B4 Morpho `withdraw` redondea las shares quemadas hacia abajo | no | H-SOLV-8, H-SOLV-4 (6) |

Las que solo detectan las suites multi-mercado (M8–M11, M13, M14) necesitan topes que se alcancen o gobierno, que el
handler original no tiene. M12 y M17 son errores de 1 wei en adelante que el modelo autorreferente no puede ver.

**Con los cambios del 27-oct** (`reallocate`, `setSupplyQueue` y `_mintFits`), las 21 siguen detectadas, cada una en
las mismas suites que en la tabla, y los 6 invariantes pasan 256 × 500 con las semillas `0x2a` y `0x3`. Cambió quién
nota primero M7 y M15, las dos de comisión. En las secuencias nuevas, el chequeo de precio del handler original salta
en un `donate` antes de que una acumulación llegue a H-FEE-1, y `check()` guarda solo la primera violación. Por eso
el resumen de `mutate.py` las cuenta como detectadas, pero no como detectadas por una ley `H-...`.

**Primera corrida con forge en la PC (26-oct, semilla nueva, 256 × 500).** Pasan los 84 tests y el informe muestra
`verificaciones`, las métricas por acción y las del cazador. Cambios que salieron de esa corrida:

- En la suite multi-mercado, el `reallocate` heredado revertía en el 78 % de sus llamadas: movía entre el mercado y
  el idle sin mirar los topes, que el gobierno baja seguido. Ahora respeta topes y habilitación y, si esa dirección no
  admite movimiento, prueba la inversa. La firma no cambia.
- Llamar a una acción de gobierno no alcanza: un `acceptCap` sin tope pendiente vencido no explora nada. El informe
  agrega `gobierno con efecto`, por tipo de acción.
- La guía para leer el informe (sección 6), porque algunas métricas parecen alarmantes y no lo son.

**Segunda corrida con forge (27-oct, semilla nueva).** Pasan los 84 tests. El `reallocate` heredado bajó del 78 % de
reversiones a 0,1–0,3 %, y las suites multi-mercado, de 3,2–3,8 % a 0,8–0,9 %. La línea `gobierno con efecto` mostró
que `setSupplyQueue` cambiaba la cola en solo 2 a 5 de unas 14 llamadas por corrida, porque armaba colas al azar con
los cuatro mercados y MetaMorpho revierte si alguno tiene tope 0. Ahora siete de cada ocho llamadas usan solo mercados
con tope, y la octava prueba la reversión.

Al verificar ese cambio en la nube, la semilla `0x2a` hizo fallar dos suites multi-mercado: un depósito menor o igual
a `maxDeposit` revertía. Con las colas cambiando de verdad aparece un estado nuevo:

1. Remociones forzadas de mercados con supply dejan `totalAssets` cerca de 0 con acciones en circulación.
2. El depósito siguiente acuña cantidades astronómicas de acciones, porque el precio de una acción es casi 0.
3. Otra remoción y otro depósito, y las acciones ya no entran en `uint256`.

Para clasificarlo, las fallas de vivacidad ahora dicen con qué error revirtió la llamada. Fue `Panic(0x11)`, un
desborde aritmético. Cualquier ERC-4626 revierte en ese caso, así que no es un error de MetaMorpho: hace falta que el
curador realice pérdidas totales dos veces. Las macros ahora exigen el depósito solo si sus acciones entran en
`uint256` (`_mintFits`), una condición exacta de 512 bits que no puede esconder otro error.

## Límites y próximos pasos

- **Vault V2** (leído en `morpho-org/vault-v2` @ `6f54361`; todavía no tiene harness). El modelo cambia así:

  - El vault guarda $TA_s$ (`_totalAssets`). Los activos reales son
    $\mathcal R = \text{idle} + \sum_a \text{realAssets}_a$: en V2 los activos ociosos están en el contrato.
  - Devenga una vez por transacción (`firstTotalAssets` es transient):

$$TA_{n} = \min\!\left(\mathcal R,\ TA_s + \left\lfloor \tfrac{TA_s\,\Delta t\,r_{\max}}{W}\right\rfloor\right),\qquad I = TA_n \ominus TA_s,\qquad F^p = \left\lfloor \tfrac{I f_p}{W}\right\rfloor,\qquad F^g = \left\lfloor \tfrac{TA_n\,\Delta t\, f_g}{W}\right\rfloor$$

$$\sigma^{p,g} = \left\lfloor \tfrac{F^{p,g}\,(T + v)}{TA_n - F^p - F^g + 1}\right\rfloor$$

  Consecuencias para las leyes:

  - H-INF-2 tiene que permitir que $\rho$ baje exactamente por $F^g$: la comisión de gestión baja el precio aunque no
    haya pérdidas, y el propio código lo documenta.
  - H-FEE-4 se separa en $\sum F^p \le f^p_{\max} \sum I$ y $\sum F^g \le f^g_{\max} \sum TA_n \Delta t$.
  - H-SOLV-1 pasa a $\mathcal R \ge TA_n$ en cada devengamiento: se cumple por el mínimo, y entre devengamientos
    $TA_s$ solo puede superar a $\mathcal R$ por pérdidas sin realizar.
  - H-INF-6 cambia de sentido: una donación al contrato sí sube $\mathcal R$, pero $TA$ sube a lo sumo
    $\lfloor TA_s \Delta t\, r_{\max}/W\rfloor$ por devengamiento. Es la defensa de V2 contra la inflación, y la ley
    tiene que medir esa cota.
  - `forceDeallocate` quema acciones como penalidad sin sacar activos: $TA_s$ baja y $\mathcal R$ no.
- No cubre todavía: tokens no estándar, reentrada, `permit`/`multicall`, préstamos flash ni IRM con estado.
