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
import {NexusVaultV2Hunter, NexusVaultV2Base, NexusV2Math} from "./NexusVaultV2Hunter.sol";

contract NexusVaultV2Handler is NexusVaultV2Hunter {
    constructor(uint256 fee, uint256 mgmtFee, uint8 assetDecimals, uint256 penalty)
        NexusVaultV2Base(fee, mgmtFee, assetDecimals, penalty)
    {
        _hunterInit();
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
            _curated(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, nv)));
        } else if (abs) {
            vm.prank(CURATOR);
            vault.decreaseAbsoluteCap(idData, nv);
        } else if (nv >= cur) {
            _curated(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, nv)));
        } else {
            vm.prank(CURATOR);
            vault.decreaseRelativeCap(idData, nv);
        }
        uint256 got = abs ? vault.absoluteCap(id) : vault.relativeCap(id);
        _ok(got == nv, L_CAP, "el tope no quedo en el valor pedido (pedido, real)", nv, got);
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
        else if (m == 1) target = cap + 1; // cap ≤ 2·ABS_CAP: no desborda
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
