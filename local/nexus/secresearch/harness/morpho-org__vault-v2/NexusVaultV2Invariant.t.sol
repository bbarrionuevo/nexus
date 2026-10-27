// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// Handler e invariantes del cazador de Vault V2 (variante A: VaultV2 + AdapterMock), en tres variantes: sin comisión,
// con comisión de performance y de gestión, y activo de 6 decimales. Cada acción del handler pasa por sus leyes V-...
// (NexusVaultV2Hunter.sol). El rendimiento y las pérdidas se controlan con el AdapterMock, así que el fantasma conoce
// los activos reales de forma exacta. Los montos los deriva el cazador del cambio de estado, no de los argumentos.

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {NexusVaultV2Hunter, NexusVaultV2Base} from "./NexusVaultV2Hunter.sol";

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
        vm.prank(from);
        vault.transfer(_actor(toSeed), _clamp(shares, 0, _bal(from)));
    }

    /* DEVENGAMIENTO, RENDIMIENTO Y PÉRDIDA (el AdapterMock los hace exactos) */

    function accrue() external {
        _huntedAccrue();
    }

    function earn(uint256 gain) external {
        adapter.setInterest(adapter.interest() + _clamp(gain, 0, MAX_ASSETS));
        _huntedAccrue();
    }

    function lose(uint256 amount) external {
        uint256 real = adapter.realAssets();
        uint256 x = _clamp(amount, 0, real);
        adapter.setLoss(adapter.loss() + x);
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

    function allocate(uint256 assets) external hunted(OP_ACCRUE, address(0), address(0)) {
        uint256 alloc = vault.allocation(keccak256(idData0));
        uint256 room = ABS_CAP > alloc ? ABS_CAP - alloc : 0;
        uint256 a = _clamp(assets, 0, _min(token.balanceOf(address(vault)), room));
        if (a == 0) return _touch();
        vm.prank(ALLOCATOR);
        vault.allocate(address(adapter), idData0, a);
    }

    function deallocate(uint256 assets) external hunted(OP_DEALLOC, address(0), address(0)) {
        uint256 a = _clamp(assets, 0, _min(adapter.deposit(), vault.allocation(keccak256(idData0))));
        if (a == 0) return;
        vm.prank(ALLOCATOR);
        vault.deallocate(address(adapter), idData0, a);
    }

    /* AYUDAS */

    /// @dev Retirable sin adapter de liquidez: lo ocioso y, a lo sumo, el valor de las acciones del actor (sin devengar).
    function _withdrawable(address who) internal view returns (uint256) {
        uint256 idle = token.balanceOf(address(vault));
        uint256 claim = _bal(who) * (vault._totalAssets() + 1) / (vault.totalSupply() + vShares);
        return _min(idle, claim);
    }

    function _redeemable(address who) internal view returns (uint256) {
        // acciones cuyo valor cabe en lo ocioso (sin devengar): acota el redeem para que no revierta por iliquidez
        uint256 idle = token.balanceOf(address(vault));
        uint256 ta = vault._totalAssets();
        uint256 t = vault.totalSupply();
        uint256 maxByIdle = ta == 0 ? _bal(who) : idle * (t + vShares) / (ta + 1);
        return _min(_bal(who), maxByIdle);
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

    /* REGISTRO DE VIOLACIONES */

    function _hunterFlag(string memory what, uint256 x, uint256 y) internal override {
        if (violations++ == 0) {
            firstViolation = string(abi.encodePacked(what, ": ", _str(x), ", ", _str(y)));
        }
    }

    function _str(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b = new bytes(78);
        uint256 i = 78;
        while (v != 0) {
            b[--i] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        bytes memory out = new bytes(78 - i);
        for (uint256 j; j < out.length; ++j) {
            out[j] = b[i + j];
        }
        return string(out);
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
        emit log_named_uint("verificaciones", checks_);
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cazador: depositos con 0 acciones", zeroMints);
        emit log_named_uint("cazador: precio maximo de una accion", maxPrice);
        emit log_named_uint("cazador: acciones de comision acunadas", feeShares);
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
