// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// Handler e invariantes del cazador de Vault V2 (variante A: VaultV2 + NexusAdapterMock), en tres variantes: sin
// comisión, con comisión de performance y de gestión, y activo de 6 decimales. Cada acción del handler pasa por sus
// leyes V-... (NexusVaultV2Hunter.sol). El rendimiento y las pérdidas se controlan con el saldo del adapter, así que el
// fantasma conoce los activos reales de forma exacta. Los montos los deriva el cazador del cambio de estado, no de los
// argumentos.

import {Test} from "../../lib/forge-std/src/Test.sol";
import {NexusVaultV2Hunter, NexusVaultV2Base, NexusV2Math} from "./NexusVaultV2Hunter.sol";

contract NexusVaultV2Handler is NexusVaultV2Hunter {
    constructor(uint256 fee, uint256 mgmtFee, uint8 assetDecimals) NexusVaultV2Base(fee, mgmtFee, assetDecimals) {
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

    /// @dev Acotado a lo ocioso y al tope efectivo de id-0: el absoluto y el relativo contra firstTotalAssets, que en
    /// esta transacción es el _totalAssets tras el primer devengamiento (el del modelo). La allocation de los dos ids es
    /// la posición del adapter, que tras asignar `a` queda en su saldo + `a`.
    function allocate(uint256 assets) external hunted(OP_ACCRUE, address(0), address(0)) {
        (uint256 firstTA,,) = _expectAccrual(_snap());
        uint256 cap = _min(ABS_CAP, firstTA * REL_CAP_0 / WAD);
        uint256 held = adapter.realAssets();
        uint256 a = _clamp(assets, 0, _min(token.balanceOf(address(vault)), cap > held ? cap - held : 0));
        if (a == 0) return _touch();
        vm.prank(ALLOCATOR);
        vault.allocate(address(adapter), idData0, a);
        ++hAllocs;
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

    /* AYUDAS */

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
        handler = new NexusVaultV2Handler(_fee(), _mgmtFee(), _assetDecimals());
        targetContract(address(handler));
    }

    function _fee() internal pure virtual returns (uint256) {
        return 0;
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
        (uint256 laws, uint256 checks_, uint256 zeroMints, uint256 maxPrice, uint256 feeShares) = handler.hunterStats();
        (uint256 losses, uint256 lossAssets, uint256 feeDrops, uint256 allocs, uint256 deallocs, uint256 transfers) =
            handler.coverage();
        emit log_named_uint("verificaciones", checks_);
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cazador: depositos con 0 acciones", zeroMints);
        emit log_named_uint("cazador: precio maximo de una accion", maxPrice);
        emit log_named_uint("cazador: acciones de comision acunadas", feeShares);
        emit log_named_uint("cazador: perdidas realizadas (V-LOSS)", losses);
        emit log_named_uint("cazador: activos de perdida realizados", lossAssets);
        emit log_named_uint("cazador: bajas de precio sin perdida (comision de gestion)", feeDrops);
        emit log_named_uint("cobertura: asignaciones con efecto", allocs);
        emit log_named_uint("cobertura: desasignaciones con efecto", deallocs);
        emit log_named_uint("cobertura: transferencias con efecto", transfers);
    }
}

contract NexusVaultV2InvariantFeeTest is NexusVaultV2InvariantTest {
    function _fee() internal pure override returns (uint256) {
        return 0.2e18;
    }

    function _mgmtFee() internal pure override returns (uint256) {
        return (0.05e18 / uint256(365 days)) / 2;
    }
}

contract NexusVaultV2InvariantSixDecimalsTest is NexusVaultV2InvariantTest {
    function _assetDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
