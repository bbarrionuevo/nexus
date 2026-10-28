// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// Handler e invariantes del cazador de Vault V2 (variante A: VaultV2 + NexusAdapterMock), en tres variantes: sin
// comisión, con comisión de performance y de gestión, y activo de 6 decimales, cada una con su penalidad de
// forceDeallocate. Cada acción del handler pasa por sus leyes V-... (NexusVaultV2Hunter.sol). El rendimiento y las
// pérdidas se controlan con el saldo del adapter, así que el fantasma conoce los activos reales de forma exacta. Los
// montos los deriva el cazador del cambio de estado, no de los argumentos. Algunas acciones hacen dos operaciones en la
// misma transacción (depositar y asignar, forzar y salir): la segunda ya no devenga.

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {
    NexusVaultV2Hunter,
    NexusVaultV2Base,
    NexusV2Math,
    NexusAdapterMock,
    NexusAdapterRegistry
} from "./NexusVaultV2Hunter.sol";

contract NexusVaultV2Handler is NexusVaultV2Hunter {
    constructor(uint256 fee, uint256 mgmtFee, uint8 assetDecimals, uint256 penalty)
        NexusVaultV2Base(fee, mgmtFee, assetDecimals, penalty)
    {
        _hunterInit();
        _govInit();
    }

    /* ACCIONES DE USUARIO (el monto se acota aquí; el cazador lo deriva del estado) */

    function deposit(uint256 actorSeed, uint256 assets) external hunted(OP_DEPOSIT, _actor(actorSeed), address(0)) {
        address who = _actor(actorSeed);
        uint256 a = 1 + assets % MAX_ASSETS;
        _give(who, a);
        vm.prank(who);
        vault.deposit(a, who);
    }

    function mint(uint256 actorSeed, uint256 shares) external hunted(OP_MINT, _actor(actorSeed), address(0)) {
        address who = _actor(actorSeed);
        _give(who, MAX_ASSETS * 4);
        vm.prank(who);
        vault.mint(1 + shares % MAX_ASSETS, who);
    }

    function withdraw(uint256 actorSeed, uint256 assets) external hunted(OP_WITHDRAW, _actor(actorSeed), address(0)) {
        address who = _actor(actorSeed);
        uint256 a = _clamp(assets, 0, _withdrawable(who));
        if (a == 0) return _touch();
        vm.prank(who);
        vault.withdraw(a, who, who);
    }

    function redeem(uint256 actorSeed, uint256 shares) external hunted(OP_REDEEM, _actor(actorSeed), address(0)) {
        address who = _actor(actorSeed);
        uint256 s = _clamp(shares, 0, _redeemable(who));
        if (s == 0) return _touch();
        vm.prank(who);
        vault.redeem(s, who, who);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 shares)
        external
        hunted(OP_TRANSFER, _actor(fromSeed), _actor(toSeed))
    {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        // El monto se calcula antes del prank: una llamada externa en los argumentos (balanceOf) consumiría el prank y
        // la transferencia saldría del handler, que no tiene acciones (así revertía el 94 % de las llamadas hasta el
        // 27-oct).
        uint256 s = _clamp(shares, 0, _bal(from));
        vm.prank(from);
        vault.transfer(to, s);
        if (s != 0 && from != to) ++hTransfers;
    }

    /* DEVENGAMIENTO, RENDIMIENTO Y PÉRDIDA (el saldo del adapter los hace exactos) */

    function accrue() external {
        _huntedAccrue();
    }

    function earn(uint256 gain) external {
        _setHeld(adapter.realAssets() + _clamp(gain, 0, MAX_ASSETS));
        _huntedAccrue();
    }

    /// @dev La pérdida sale del saldo del adapter: con capital asignado alcanza a lo depositado, no solo al rendimiento.
    function lose(uint256 amount) external {
        uint256 held = adapter.realAssets();
        uint256 x = _clamp(amount, 0, held);
        _setHeld(held - x);
        hLoss += x;
        _huntedAccrue();
    }

    function setMaxRate(uint256 r) external hunted(OP_ACCRUE, address(0), address(0)) {
        vm.prank(ALLOCATOR);
        vault.setMaxRate(_clamp(r, 0, MAX_MAX_RATE));
    }

    function warp(uint256 secs) external {
        vm.warp(hClock.time() + 1 + secs % (120 days));
    }

    /* ALLOCATOR: mover capital al adapter y de vuelta */

    /// @dev Dentro de lo ocioso y del tope efectivo (los topes absolutos y relativos de los dos ids, contra el
    /// firstTotalAssets que va a fijar el devengamiento de esta transacción): tiene que pasar. La posición del adapter
    /// tras asignar `a` es su saldo + `a`.
    function allocate(uint256 assets) external {
        Snap memory pre = _snap();
        (uint256 firstTA,,) = _expectAccrual(pre);
        uint256 cap = _effCap(firstTA);
        _allocateFrom(pre, _clamp(assets, 0, _min(token.balanceOf(address(vault)), cap > pre.held ? cap - pre.held : 0)));
    }

    /// @dev En el borde del tope efectivo (justo en el tope, uno más, uno menos), en el tope que valdría si contara el
    /// _totalAssets actual, o al azar hasta lo ocioso. V-CAP-1 compara si pasa con la predicción.
    function allocateAt(uint256 mode, uint256 seed) external {
        _allocateAround(_snap(), mode, seed);
    }

    /// @dev Depósito y allocate en la MISMA transacción (NexusV2Macro): el tope relativo se mide contra firstTotalAssets,
    /// el total del primer devengamiento, así que el depósito no lo puede ensanchar (la defensa contra préstamos flash).
    /// Entre dos transacciones el depósito sí cuenta: es el L-14 de Blackthorn, reconocido. Si lo devengado era 0, el
    /// primer total no nulo es el del allocate, que ya incluye el depósito (Spearbit 5.1.6). `mode`: justo en el tope,
    /// uno más, el tope que valdría si contara el depósito, o al azar.
    function depositAndAllocate(uint256 actorSeed, uint256 assets, uint256 mode) external {
        address who = _actor(actorSeed);
        uint256 x = 1 + assets % MAX_ASSETS;
        deal(address(token), address(batch), token.balanceOf(address(batch)) + x, true);
        Snap memory pre = _snap();
        (uint256 A,,) = _expectAccrual(pre);
        uint256 ft = A != 0 ? A : x; // firstTotalAssets cuando el allocate mide los topes
        uint256 capF = _effCap(ft);
        uint256 idle = token.balanceOf(address(vault)) + x;
        uint256 m = mode % 4;
        uint256 target = m == 0 ? capF : m == 1 ? capF + 1 : m == 2 ? _effCap(A + x) : pre.held + assets % (idle + 1);
        uint256 a = _min(target > pre.held ? target - pre.held : 0, idle);
        bool expect = _capsAllow(pre.held + a, ft);
        (bool ok, uint256 ftDep, uint256 ftAlloc) = batch.depositThenAllocate(who, x, a, idData0);
        Snap memory post = _snap();
        _lawCaps(ok, expect, pre.held + a, ft);
        _ok(ftDep == A, L_CAP, "firstTotalAssets tras el deposito no es lo devengado (modelo, real)", A, ftDep);
        _ok(ftAlloc == (ok ? ft : A), L_CAP, "firstTotalAssets tras el allocate no es el primer total no nulo (modelo, real)", ok ? ft : A, ftAlloc);
        _lawsAccruing(OP_DEPOSIT, who, pre, post); // el allocate no cambia _totalAssets, totalSupply, R ni saldos
        if (ok && a != 0) ++hAllocs;
        ++hSameTx;
    }

    /// @dev El vault exige allocation > 0; el adapter devuelve a lo sumo su saldo.
    function deallocate(uint256 assets) external hunted(OP_DEALLOC, address(0), address(0)) {
        if (vault.allocation(keccak256(idData0)) == 0) return;
        uint256 a = _clamp(assets, 0, adapter.realAssets());
        if (a == 0) return;
        vm.prank(ALLOCATOR);
        vault.deallocate(address(adapter), idData0, a);
        ++hDeallocs;
    }

    /* FORCE DEALLOCATE: cualquiera saca capital de un adapter, pagando la penalidad */

    function forceDeallocate(uint256 callerSeed, uint256 ownerSeed, uint256 assets) external {
        _force(_actor(callerSeed), _actor(ownerSeed), assets);
    }

    /// @dev Forzar y salir en la MISMA transacción (NexusV2Macro): el retiro se paga al precio que dejó forceDeallocate
    /// (pérdida realizada y penalidad cobrada), sin un segundo devengamiento. Así quien fuerza no evita su parte de una
    /// pérdida. Se retira todo lo que valen las acciones que le quedan a `o`, hasta lo ocioso.
    function forceExit(uint256 actorSeed, uint256 assets) external {
        address o = _actor(actorSeed);
        if (vault.allocation(keccak256(idData0)) == 0) return;
        Snap memory pre = _snap();
        (uint256 A, uint256 sp, uint256 sg) = _expectAccrual(pre);
        uint256 S = pre.T + sp + sg;
        uint256 bal = pre.bal[_idx(o)];
        uint256 pAmax = NexusV2Math.mulDivDown(bal, A + 1, S + vShares);
        uint256 a = _clamp(assets, 0, pre.pen == 0 ? pre.held : _min(pre.held, NexusV2Math.mulDivDown(pAmax, WAD, pre.pen)));
        uint256 pA = NexusV2Math.mulDivUp(a, pre.pen, WAD);
        uint256 sP = NexusV2Math.mulDivUp(pA, S + vShares, A + 1);
        uint256 w = _min(
            token.balanceOf(address(vault)) + a, NexusV2Math.mulDivDown(bal - sP, A - pA + 1, S - sP + vShares)
        );
        uint256 ft = batch.forceThenWithdraw(o, a, w, idData0);
        _lawsForceExit(o, pre, _snap(), ft);
        if (a != 0) ++hForces;
        ++hForceExits;
    }

    /* TOPES: el curador los baja sin demora; subirlos pasa por el timelock, que en el harness es 0 */

    /// @dev which % 8: 0–3 cambian un tope a un valor no nulo (absoluto de id-0, absoluto de id-1, relativo de id-0,
    /// relativo de id-1); 4 pone en 0 el absoluto de un id (nada se puede asignar); 5–7 vuelven a los topes iniciales.
    /// Sin la vuelta, el fuzzer (que propone 0 a menudo) dejaba los topes bajos casi toda la corrida y casi no había
    /// capital asignado sobre el que realizar pérdidas.
    function setCap(uint256 which, uint256 value) external {
        Snap memory pre = _snap();
        uint256 w = which % 8;
        bytes memory idData = which % 2 == 0 ? idData0 : idData1;
        if (w < 2) _setCap(true, idData, _clamp(value, 1, 2 * ABS_CAP));
        else if (w < 4) _setCap(false, idData, _clamp(value, 1, WAD));
        else if (w == 4) _setCap(true, idData, 0);
        else {
            _setCap(true, idData0, ABS_CAP);
            _setCap(true, idData1, ABS_CAP);
            _setCap(false, idData0, REL_CAP_0);
            _setCap(false, idData1, WAD);
        }
        _lawsNoAccrual(OP_STILL, address(0), address(0), pre, _snap());
        ++hCapChanges;
    }

    /// @dev Bajar un tope lo hace el curador sin demora; subirlo pasa por el timelock (0 en el harness).
    function _setCap(bool abs, bytes memory idData, uint256 nv) internal {
        bytes32 id = keccak256(idData);
        uint256 cur = abs ? vault.absoluteCap(id) : vault.relativeCap(id);
        if (abs && nv >= cur) {
            _curatedGov(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, nv)));
        } else if (abs) {
            vm.prank(CURATOR);
            vault.decreaseAbsoluteCap(idData, nv);
        } else if (nv >= cur) {
            _curatedGov(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, nv)));
        } else {
            vm.prank(CURATOR);
            vault.decreaseRelativeCap(idData, nv);
        }
        uint256 got = abs ? vault.absoluteCap(id) : vault.relativeCap(id);
        _ok(got == nv, L_CAP, "el tope no quedo en el valor pedido (pedido, real)", nv, got);
    }

    /* GOBIERNO CON TIMELOCK (V-GOV-1). El handler lleva una copia fantasma de timelocks, abdicaciones, pendientes, el
       registro de adapters y si el segundo adapter está dado de alta, y compara cada propuesta, ejecución y revocación
       con ella. Toca comisiones, sus receptores, la penalidad de forceDeallocate, los timelocks, abdicaciones, subidas
       de topes, el alta y la baja de un segundo adapter (vacío: no cambia la contabilidad) y el registro de adapters.
       Los topes tienen timelock 0, porque setCap los sube en el acto. Las comisiones y los receptores devengan antes de
       cambiar: V-FEE-1, sobre la foto previa, ve que el cambio no es retroactivo. */

    struct Pend {
        bytes data;
        bytes4 sel; // función con demora
        bytes4 tsel; // selector objetivo (increaseTimelock, decreaseTimelock, abdicate)
        uint256 v; // valor propuesto (un receptor o un registro van como uint160)
        bytes32 id; // id del tope (increaseAbsoluteCap, increaseRelativeCap)
    }

    bytes4 internal constant S_PF = IVaultV2.setPerformanceFee.selector;
    bytes4 internal constant S_MF = IVaultV2.setManagementFee.selector;
    bytes4 internal constant S_PFR = IVaultV2.setPerformanceFeeRecipient.selector;
    bytes4 internal constant S_MFR = IVaultV2.setManagementFeeRecipient.selector;
    bytes4 internal constant S_FDP = IVaultV2.setForceDeallocatePenalty.selector;
    bytes4 internal constant S_INC = IVaultV2.increaseTimelock.selector;
    bytes4 internal constant S_DEC = IVaultV2.decreaseTimelock.selector;
    bytes4 internal constant S_ABD = IVaultV2.abdicate.selector;
    bytes4 internal constant S_IAC = IVaultV2.increaseAbsoluteCap.selector;
    bytes4 internal constant S_IRC = IVaultV2.increaseRelativeCap.selector;
    bytes4 internal constant S_ADD = IVaultV2.addAdapter.selector;
    bytes4 internal constant S_RM = IVaultV2.removeAdapter.selector;
    bytes4 internal constant S_REG = IVaultV2.setAdapterRegistry.selector;
    uint256 internal constant MAX_GOV_TIMELOCK = 60 days;

    Pend[] internal gPending;
    mapping(bytes32 => uint256) internal gExec; // keccak256(data) → executableAt según el modelo
    mapping(bytes4 => uint256) internal gTimelock;
    mapping(bytes4 => bool) internal gAbdicated;
    NexusAdapterMock internal adapter2; // segundo adapter, siempre vacío
    NexusAdapterRegistry internal registry; // solo contiene al adapter principal
    bool internal gAdapter2; // adapter2 dado de alta, según el modelo
    address internal gRegistry; // registro vigente, según el modelo

    /// @dev Timelocks iniciales distintos de 0 y distintos entre sí, para que cada propuesta tenga una fecha futura y el
    /// borde exacto se pruebe desde el principio (con todo en 0 casi no había intentos un segundo antes). Quedan en 0
    /// el receptor de la comisión de gestión y removeAdapter (el camino sin demora), los topes (setCap) y
    /// decreaseTimelock, cuyas propuestas usan el timelock de la función objetivo. increaseTimelock va último: después
    /// ya no se ejecuta en el acto.
    function _govInit() internal {
        adapter2 = new NexusAdapterMock(address(vault), address(token));
        registry = new NexusAdapterRegistry(address(adapter));
        _govSetTimelock(S_PF, 3 days);
        _govSetTimelock(S_MF, 1 days);
        _govSetTimelock(S_FDP, 12 hours);
        _govSetTimelock(S_PFR, 2 days);
        _govSetTimelock(S_ABD, 5 days);
        _govSetTimelock(S_ADD, 4 days);
        _govSetTimelock(S_REG, 1 days);
        _govSetTimelock(S_INC, 1 hours);
    }

    /// @dev Como _curated, pero si el gobierno ya tiene ese mismo dato pendiente (un tope, con timelock 0: ya
    /// ejecutable), lo ejecuta y lo saca de los pendientes en vez de proponerlo de nuevo, que revertiría con
    /// DataAlreadyPending.
    function _curatedGov(bytes memory data) internal {
        bytes32 h = keccak256(data);
        if (gExec[h] == 0) return _curated(data);
        (bool ok,) = address(vault).call(data);
        require(ok, "nexus: tope pendiente");
        for (uint256 i; i < gPending.length; ++i) {
            if (keccak256(gPending[i].data) == h) return _govDrop(i, gPending[i]);
        }
    }

    function _govSetTimelock(bytes4 sel, uint256 tl) internal {
        _curated(abi.encodeCall(IVaultV2.increaseTimelock, (sel, tl)));
        gTimelock[sel] = tl;
    }

    /// @dev El curador propone un cambio con demora; una de cada siete veces lo intenta un actor y tiene que fallar.
    /// Proponer un dato ya pendiente revierte. Si pasa, executableAt = ahora + timelock de la función (para
    /// decreaseTimelock, el timelock de la función objetivo).
    function govSubmit(uint256 which, uint256 value) external {
        Pend memory p = _govPick(which, value);
        bool stranger = value % 7 == 0;
        bytes32 h = keccak256(p.data);
        uint256 tl = p.sel == S_DEC ? gTimelock[p.tsel] : gTimelock[p.sel];
        Snap memory pre = _snap();
        vm.prank(stranger ? actors[0] : CURATOR);
        (bool ok,) = address(vault).call(abi.encodeCall(IVaultV2.submit, (p.data)));
        _ok(ok == (!stranger && gExec[h] == 0), L_GOV, ok ? "submit paso sin ser el curador o con el dato pendiente (pendiente, 0)" : "el curador no pudo proponer un dato nuevo (pendiente, 0)", gExec[h], 0);
        _lawsNoAccrual(OP_STILL, address(0), address(0), pre, _snap());
        if (!ok) {
            ++hGovRejected;
            return;
        }
        uint256 at = hClock.time() + tl;
        _ok(vault.executableAt(p.data) == at, L_GOV, "executableAt no es ahora + timelock (modelo, real)", at, vault.executableAt(p.data));
        gExec[h] = at;
        gPending.push(p);
        ++hGovSubmits;
    }

    /// @dev Ejecuta un pendiente (cualquiera puede). Si su fecha todavía no llegó, tres de cada cuatro veces primero lo
    /// intenta un segundo antes (tiene que fallar) y después justo en la fecha; la cuarta, ahora (y falla). Pasa si y
    /// solo si llegó la fecha, la función no fue abdicada y se cumplen sus condiciones; si pasa, el efecto es el valor
    /// propuesto y el pendiente se borra.
    function govExecute(uint256 idx, uint256 edge) external {
        if (gPending.length == 0) return;
        uint256 i = idx % gPending.length;
        Pend memory p = gPending[i];
        uint256 at = gExec[keccak256(p.data)];
        if (edge % 4 != 3 && at > hClock.time() + 1) {
            vm.warp(at - 1);
            Snap memory pre0 = _snap();
            (bool early,) = address(vault).call(p.data);
            _ok(!early, L_GOV, "una funcion con demora se ejecuto antes de su fecha (fecha, ahora)", at, hClock.time());
            _lawsNoAccrual(OP_STILL, address(0), address(0), pre0, _snap());
            ++hGovEarly;
            vm.warp(at);
        }
        _govExec(i, p, at);
    }

    /// @dev Revoca un pendiente: el curador o un centinela (ALLOCATOR) pueden; un actor sin rol (la mitad de las veces)
    /// tiene que fallar. Lo revocado ya no se ejecuta, ni aunque haya llegado su fecha.
    function govRevoke(uint256 idx, uint256 who) external {
        if (gPending.length == 0) return;
        uint256 i = idx % gPending.length;
        Pend memory p = gPending[i];
        uint256 at = gExec[keccak256(p.data)];
        uint256 w = who % 4;
        Snap memory pre = _snap();
        vm.prank(w == 0 ? CURATOR : w == 1 ? ALLOCATOR : actors[1]);
        (bool ok,) = address(vault).call(abi.encodeCall(IVaultV2.revoke, (p.data)));
        _ok(ok == (w < 2), L_GOV, ok ? "un actor sin rol revoco un pendiente (0, revoco)" : "el curador o un centinela no pudo revocar (0, revirtio)", 0, 1);
        _lawsNoAccrual(OP_STILL, address(0), address(0), pre, _snap());
        if (!ok) {
            ++hGovRejected;
            return;
        }
        _ok(vault.executableAt(p.data) == 0, L_GOV, "revoke no borro el pendiente (0, executableAt)", 0, vault.executableAt(p.data));
        _govDrop(i, p);
        ++hGovRevokes;
        if (at > hClock.time()) vm.warp(at);
        Snap memory pre1 = _snap();
        (bool late,) = address(vault).call(p.data);
        _ok(!late, L_GOV, "se ejecuto un dato revocado (0, ejecuto)", 0, 1);
        _lawsNoAccrual(OP_STILL, address(0), address(0), pre1, _snap());
    }

    function _govExec(uint256 i, Pend memory p, uint256 at) internal {
        bool expect = hClock.time() >= at && !gAbdicated[p.sel] && _govPre(p);
        Snap memory pre = _snap();
        vm.prank(actors[i % actors.length]);
        (bool ok,) = address(vault).call(p.data);
        Snap memory post = _snap();
        _ok(ok == expect, L_GOV, ok ? "una funcion con demora paso sin fecha, abdicada o sin sus condiciones (fecha, ahora)" : "una funcion con demora vencida y valida revirtio (fecha, ahora)", at, hClock.time());
        if (!ok) {
            _lawsNoAccrual(OP_STILL, address(0), address(0), pre, post);
            ++hGovRejected;
            return;
        }
        // comisiones y receptores devengan antes de cambiar (con lo viejo); lo demás no devenga
        if (p.sel == S_PF || p.sel == S_MF || p.sel == S_PFR || p.sel == S_MFR) {
            _lawsAccruing(OP_ACCRUE, address(0), pre, post);
        } else {
            _lawsNoAccrual(OP_STILL, address(0), address(0), pre, post);
        }
        _govEffect(p);
        _ok(vault.executableAt(p.data) == 0, L_GOV, "el pendiente no se borro al ejecutarse (0, executableAt)", 0, vault.executableAt(p.data));
        _govDrop(i, p);
        ++hGovExecs;
    }

    /// @dev Condiciones propias de cada función, con el estado actual: comisión ≤ máximo y con receptor (o 0), receptor
    /// no nulo salvo con comisión 0, penalidad ≤ 2 %, increaseTimelock sube y decreaseTimelock baja (y ninguno sobre
    /// decreaseTimelock), un tope absoluto sube y cabe en 128 bits, uno relativo sube sin pasar de WAD, addAdapter
    /// solo sin registro (adapter2 no está en él), un registro no nulo tiene que contener a todos los adapters (al
    /// principal sí; a adapter2 no); removeAdapter y abdicate siempre.
    function _govPre(Pend memory p) internal view returns (bool) {
        if (p.sel == S_PF) return p.v <= MAX_PERFORMANCE_FEE && (vault.performanceFeeRecipient() != address(0) || p.v == 0);
        if (p.sel == S_MF) return p.v <= MAX_MANAGEMENT_FEE && (vault.managementFeeRecipient() != address(0) || p.v == 0);
        if (p.sel == S_PFR) return p.v != 0 || vault.performanceFee() == 0;
        if (p.sel == S_MFR) return p.v != 0 || vault.managementFee() == 0;
        if (p.sel == S_FDP) return p.v <= 0.02e18;
        if (p.sel == S_INC) return p.tsel != S_DEC && p.v >= gTimelock[p.tsel];
        if (p.sel == S_DEC) return p.tsel != S_DEC && p.v <= gTimelock[p.tsel];
        if (p.sel == S_IAC) return p.v >= vault.absoluteCap(p.id) && p.v <= type(uint128).max;
        if (p.sel == S_IRC) return p.v <= WAD && p.v >= vault.relativeCap(p.id);
        if (p.sel == S_ADD) return gRegistry == address(0);
        if (p.sel == S_REG) return p.v == 0 || !gAdapter2;
        return true;
    }

    function _govEffect(Pend memory p) internal {
        uint256 got;
        if (p.sel == S_PF) {
            got = vault.performanceFee();
        } else if (p.sel == S_MF) {
            got = vault.managementFee();
        } else if (p.sel == S_PFR) {
            got = uint160(vault.performanceFeeRecipient());
        } else if (p.sel == S_MFR) {
            got = uint160(vault.managementFeeRecipient());
        } else if (p.sel == S_FDP) {
            got = vault.forceDeallocatePenalty(address(adapter));
        } else if (p.sel == S_INC || p.sel == S_DEC) {
            got = vault.timelock(p.tsel);
            gTimelock[p.tsel] = p.v;
        } else if (p.sel == S_IAC) {
            got = vault.absoluteCap(p.id);
        } else if (p.sel == S_IRC) {
            got = vault.relativeCap(p.id);
        } else if (p.sel == S_REG) {
            gRegistry = address(uint160(p.v));
            got = uint160(vault.adapterRegistry());
        } else if (p.sel == S_ADD || p.sel == S_RM) {
            gAdapter2 = p.sel == S_ADD;
            bool real = vault.isAdapter(address(adapter2));
            _ok(real == gAdapter2, L_GOV, "isAdapter de adapter2 no quedo como lo pidio el gobierno (esperado, real)", gAdapter2 ? 1 : 0, real ? 1 : 0);
            uint256 n = gAdapter2 ? 2 : 1;
            _ok(vault.adaptersLength() == n, L_GOV, "la lista de adapters no tiene el largo esperado (esperado, real)", n, vault.adaptersLength());
            return;
        } else {
            gAbdicated[p.tsel] = true;
            _ok(vault.abdicated(p.tsel), L_GOV, "abdicate no marco la funcion como abdicada (1, 0)", 1, 0);
            _govProbeAbdicated(p.tsel);
            return;
        }
        _ok(got == p.v, L_GOV, "el efecto no es el valor propuesto (propuesto, real)", p.v, got);
    }

    /// @dev Tras abdicar: una propuesta nueva de esa función, con el valor vigente (que cumple sus condiciones), se
    /// acepta, pero llegada su fecha no se ejecuta. Si se ejecutara (la falla), no se revoca: revocaría un dato que ya
    /// no está pendiente, la llamada revertiría y forge descartaría la falla.
    function _govProbeAbdicated(bytes4 tsel) internal {
        bytes memory data = tsel == S_FDP
            ? abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), vault.forceDeallocatePenalty(address(adapter))))
            : abi.encodeCall(IVaultV2.setManagementFee, (vault.managementFee()));
        if (gExec[keccak256(data)] != 0) return; // ya está pendiente
        vm.prank(CURATOR);
        vault.submit(data);
        uint256 at = vault.executableAt(data);
        if (at > hClock.time()) vm.warp(at);
        Snap memory pre = _snap();
        (bool ok,) = address(vault).call(data);
        _ok(!ok, L_GOV, "se ejecuto una funcion abdicada (0, ejecuto)", 0, 1);
        _lawsNoAccrual(OP_STILL, address(0), address(0), pre, _snap());
        if (ok) return;
        vm.prank(CURATOR);
        vault.revoke(data);
    }

    function _govDrop(uint256 i, Pend memory p) internal {
        gExec[keccak256(p.data)] = 0;
        gPending[i] = gPending[gPending.length - 1];
        gPending.pop();
    }

    /// @dev which % 12: comisión de performance, de gestión, penalidad (a veces por encima del máximo), subir o bajar el
    /// timelock de una de esas tres (a veces sobre decreaseTimelock, que tiene que fallar), abdicar la penalidad o la
    /// comisión de gestión (la mitad de las veces; si no, otra penalidad), el receptor de una comisión (el del harness
    /// o 0: con otro, el fantasma no sabría a quién mirar), subir un tope absoluto o relativo (alrededor del vigente: la
    /// mitad baja y tiene que fallar; a veces más de 128 bits o más de WAD), dar de alta o de baja a adapter2, o poner o
    /// sacar el registro.
    function _govPick(uint256 which, uint256 value) internal view returns (Pend memory p) {
        uint256 w = which % 12;
        if (w >= 8) return _govPickVault(w, value);
        if (w == 5 && value % 2 != 0) w = 2;
        bytes4 t = value % 3 == 0 ? S_PF : (value % 3 == 1 ? S_MF : S_FDP);
        if (w == 0) {
            p.sel = S_PF;
            p.v = _clamp(value, 0, MAX_PERFORMANCE_FEE + 0.1e18);
            p.data = abi.encodeCall(IVaultV2.setPerformanceFee, (p.v));
        } else if (w == 1) {
            p.sel = S_MF;
            p.v = _clamp(value, 0, MAX_MANAGEMENT_FEE * 2);
            p.data = abi.encodeCall(IVaultV2.setManagementFee, (p.v));
        } else if (w == 2) {
            p.sel = S_FDP;
            p.v = _clamp(value, 0, 0.03e18);
            p.data = abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), p.v));
        } else if (w == 3) {
            // alrededor del timelock vigente: la mitad sube y la otra mitad (que tiene que fallar) baja. A lo sumo
            // 60 días: el gobierno avanza el reloj hasta la fecha, y sin devengar 10 años las comisiones superan a los
            // activos y el vault revierte (lo documenta accrueInterestView): sería una falsa alarma.
            p.sel = S_INC;
            p.tsel = value % 11 == 0 ? S_DEC : t;
            p.v = _clamp(value, 0, _min(2 * gTimelock[p.tsel] + 1 hours, MAX_GOV_TIMELOCK));
            p.data = abi.encodeCall(IVaultV2.increaseTimelock, (p.tsel, p.v));
        } else if (w == 4) {
            p.sel = S_DEC;
            p.tsel = value % 11 == 0 ? S_DEC : t;
            // sobre sí misma, 0: que falle solo por eso
            p.v = p.tsel == S_DEC ? 0 : _clamp(value, 0, _min(2 * gTimelock[p.tsel] + 1 hours, MAX_GOV_TIMELOCK));
            p.data = abi.encodeCall(IVaultV2.decreaseTimelock, (p.tsel, p.v));
        } else if (w == 5) {
            p.sel = S_ABD;
            p.tsel = value % 2 == 0 ? S_FDP : S_MF;
            p.data = abi.encodeCall(IVaultV2.abdicate, (p.tsel));
        } else if (w == 6) {
            p.sel = S_PFR;
            p.v = value % 2 == 0 ? uint160(PERF) : 0;
            p.data = abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (address(uint160(p.v))));
        } else {
            p.sel = S_MFR;
            p.v = value % 2 == 0 ? uint160(MGMT) : 0;
            p.data = abi.encodeCall(IVaultV2.setManagementFeeRecipient, (address(uint160(p.v))));
        }
    }

    /// @dev Los casos 8–11 de _govPick: topes, alta o baja de adapter2 y registro.
    function _govPickVault(uint256 w, uint256 value) internal view returns (Pend memory p) {
        bytes memory idData = value % 2 == 0 ? idData0 : idData1;
        if (w == 8) {
            p.sel = S_IAC;
            p.id = keccak256(idData);
            uint256 cur = vault.absoluteCap(p.id);
            p.v = value % 13 == 0 ? uint256(type(uint128).max) + 1 : _clamp(value / 2, 0, 2 * cur + 1);
            p.data = abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, p.v));
        } else if (w == 9) {
            p.sel = S_IRC;
            p.id = keccak256(idData);
            p.v = _clamp(value / 2, 0, WAD + WAD / 10);
            p.data = abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, p.v));
        } else if (w == 10) {
            bool add = value % 3 != 0;
            p.sel = add ? S_ADD : S_RM;
            p.data = add
                ? abi.encodeCall(IVaultV2.addAdapter, (address(adapter2)))
                : abi.encodeCall(IVaultV2.removeAdapter, (address(adapter2)));
        } else {
            p.sel = S_REG;
            p.v = value % 2 == 0 ? uint160(address(registry)) : 0;
            p.data = abi.encodeCall(IVaultV2.setAdapterRegistry, (address(uint160(p.v))));
        }
    }

    /* AYUDAS */

    /// @dev Elige la posición nueva del adapter según `mode` y la intenta desde el estado `s` de esta transacción.
    function _allocateAround(Snap memory s, uint256 mode, uint256 seed) internal {
        (uint256 newTA,,) = _expectAccrual(s);
        uint256 cap = _effCap(s.ft != 0 ? s.ft : newTA);
        uint256 idle = token.balanceOf(address(vault));
        uint256 m = mode % 5;
        uint256 target;
        if (m == 0) target = cap;
        else if (m == 1) target = cap + 1; // cap < 2^128 (toUint128 en el vault): no desborda
        else if (m == 2) target = cap == 0 ? 0 : cap - 1;
        else if (m == 3) target = _effCap(s.TA); // el tope si contara el _totalAssets actual (con un depósito de esta transacción)
        else target = s.held + seed % (idle + 1);
        _allocateFrom(s, _min(target > s.held ? target - s.held : 0, idle));
    }

    /// @dev allocate de `a` desde el estado `s`, contra la predicción de V-CAP-1, y las leyes de lo que haya pasado.
    function _allocateFrom(Snap memory s, uint256 a) internal {
        bool ok = _tryAllocate(a, s);
        Snap memory post = _snap();
        if (ok) _lawsAccruing(OP_ACCRUE, address(0), s, post);
        else _lawsNoAccrual(OP_STILL, address(0), address(0), s, post);
    }

    /// @dev forceDeallocate de `c` a nombre de `o`, acotado para que no revierta: allocation > 0, a lo sumo el saldo del
    /// adapter, y una penalidad que cubran las acciones de `o` (y, si c ≠ o, la allowance que `o` le da a `c`). Devuelve el
    /// estado posterior, o uno vacío (ts = 0) si no había nada que forzar.
    function _force(address c, address o, uint256 assets) internal returns (Snap memory post) {
        if (vault.allocation(keccak256(idData0)) == 0) return post;
        uint256 lim = _bal(o);
        if (c != o) {
            lim = _clamp(assets >> 128, 0, lim);
            vm.prank(o);
            vault.approve(c, lim);
        }
        // sP = ⌈pA·(S+v)/(A+1)⌉ ≤ lim  ⟺  pA ≤ ⌊lim·(A+1)/(S+v)⌋, y pA = ⌈a·p/W⌉ ≤ pAmax  ⟺  a ≤ ⌊pAmax·W/p⌋.
        (uint256 A, uint256 S) = _accrued();
        uint256 pen = vault.forceDeallocatePenalty(address(adapter));
        uint256 pAmax = NexusV2Math.mulDivDown(lim, A + 1, S + vShares);
        uint256 held = adapter.realAssets();
        uint256 a = _clamp(assets, 0, pen == 0 ? held : _min(held, NexusV2Math.mulDivDown(pAmax, WAD, pen)));
        Snap memory pre = _snap();
        uint256 alwPre = vault.allowance(o, c);
        vm.prank(c);
        vault.forceDeallocate(address(adapter), idData0, a, o);
        post = _snap();
        _lawsForce(c, o, pre, post, alwPre, vault.allowance(o, c));
        if (a != 0) ++hForces;
    }

    /// @dev Estado justo después del devengamiento según el modelo: (_totalAssets, totalSupply con las comisiones).
    function _accrued() internal view returns (uint256 A, uint256 S) {
        Snap memory s = _snap();
        (uint256 newTA, uint256 sp, uint256 sg) = _expectAccrual(s);
        return (newTA, s.T + sp + sg);
    }

    /// @dev Retirable sin adapter de liquidez: lo ocioso y, a lo sumo, el valor de las acciones del actor al precio ya
    /// devengado (con el precio sin devengar, un withdraw tras una pérdida pedía más de lo que valía el saldo).
    function _withdrawable(address who) internal view returns (uint256) {
        (uint256 A, uint256 S) = _accrued();
        return _min(token.balanceOf(address(vault)), NexusV2Math.mulDivDown(_bal(who), A + 1, S + vShares));
    }

    /// @dev Acciones cuyo valor (al precio ya devengado) cabe en lo ocioso: así el redeem no revierte por iliquidez.
    function _redeemable(address who) internal view returns (uint256) {
        (uint256 A, uint256 S) = _accrued();
        return _min(_bal(who), NexusV2Math.mulDivDown(token.balanceOf(address(vault)), S + vShares, A + 1));
    }

    function _setHeld(uint256 amount) internal {
        deal(address(token), address(adapter), amount, true);
    }

    /// @dev Un no-op que igual devenga, para que la ley de devengamiento se evalúe aunque el monto quede en 0.
    function _touch() internal {
        vault.accrueInterest();
    }

    function _huntedAccrue() internal {
        Snap memory pre = _snap();
        vault.accrueInterest();
        _hEnd(OP_ACCRUE, address(0), address(0), pre);
    }
}

contract NexusVaultV2InvariantTest is Test {
    NexusVaultV2Handler internal handler;

    function setUp() public virtual {
        handler = new NexusVaultV2Handler(_fee(), _mgmtFee(), _assetDecimals(), _penalty());
        targetContract(address(handler));
    }

    function _fee() internal pure virtual returns (uint256) {
        return 0;
    }

    /// @dev Penalidad de forceDeallocate (≤ 2 %): 1 % acá, el máximo con comisión y 0,37 % con 6 decimales (un valor
    /// que no da enteros, para que el redondeo hacia arriba importe).
    function _penalty() internal pure virtual returns (uint256) {
        return 0.01e18;
    }

    function _mgmtFee() internal pure virtual returns (uint256) {
        return 0;
    }

    function _assetDecimals() internal pure virtual returns (uint8) {
        return 18;
    }

    function invariant_vaultV2() public view {
        string memory err = handler.check();
        assertEq(bytes(err).length, 0, err);
    }

    function afterInvariant() public {
        _logHunter();
        _logCoverage();
        _logForceAndCaps();
        _logGov();
    }

    function _logGov() internal {
        (uint256 submits, uint256 execs, uint256 early, uint256 rejected, uint256 revokes) = handler.coverageGov();
        emit log_named_uint("gobierno: propuestas con demora (V-GOV-1)", submits);
        emit log_named_uint("gobierno: ejecuciones que pasaron", execs);
        emit log_named_uint("gobierno: intentos un segundo antes de la fecha", early);
        emit log_named_uint("gobierno: intentos rechazados como predijo el modelo", rejected);
        emit log_named_uint("gobierno: revocaciones", revokes);
    }

    function _logHunter() internal {
        (uint256 laws, uint256 checks_, uint256 zeroMints, uint256 maxPrice, uint256 feeShares) = handler.hunterStats();
        emit log_named_uint("verificaciones", checks_);
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cazador: depositos con 0 acciones", zeroMints);
        emit log_named_uint("cazador: precio maximo de una accion", maxPrice);
        emit log_named_uint("cazador: acciones de comision acunadas", feeShares);
    }

    function _logCoverage() internal {
        (uint256 losses, uint256 lossAssets, uint256 feeDrops, uint256 allocs, uint256 deallocs, uint256 transfers) =
            handler.coverage();
        emit log_named_uint("cazador: perdidas realizadas (V-LOSS)", losses);
        emit log_named_uint("cazador: activos de perdida realizados", lossAssets);
        emit log_named_uint("cazador: bajas de precio sin perdida (comision de gestion)", feeDrops);
        emit log_named_uint("cobertura: asignaciones con efecto", allocs);
        emit log_named_uint("cobertura: desasignaciones con efecto", deallocs);
        emit log_named_uint("cobertura: transferencias con efecto", transfers);
    }

    function _logForceAndCaps() internal {
        (
            uint256 forces,
            uint256 forceExits,
            uint256 capRejects,
            uint256 capEdges,
            uint256 capChanges,
            uint256 sameTx
        ) = handler.coverage2();
        emit log_named_uint("cobertura: forceDeallocate con monto (V-FD-1)", forces);
        emit log_named_uint("cobertura: salidas en la misma transaccion tras forzar", forceExits);
        emit log_named_uint("cobertura: allocate rechazados por los topes (V-CAP-1)", capRejects);
        emit log_named_uint("cobertura: allocate aceptados justo en el tope", capEdges);
        emit log_named_uint("cobertura: cambios de topes", capChanges);
        emit log_named_uint("cobertura: deposito y allocate en la misma transaccion", sameTx);
    }
}

contract NexusVaultV2InvariantFeeTest is NexusVaultV2InvariantTest {
    function _fee() internal pure override returns (uint256) {
        return 0.2e18;
    }

    function _mgmtFee() internal pure override returns (uint256) {
        return (0.05e18 / uint256(365 days)) / 2;
    }

    function _penalty() internal pure override returns (uint256) {
        return 0.02e18;
    }
}

contract NexusVaultV2InvariantSixDecimalsTest is NexusVaultV2InvariantTest {
    function _assetDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _penalty() internal pure override returns (uint256) {
        return 0.0037e18;
    }
}
