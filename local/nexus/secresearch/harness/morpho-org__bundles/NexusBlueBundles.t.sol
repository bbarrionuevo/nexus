// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.34;

// Cazador de BlueBundlesV1 (morpho-org/bundles; lo desplegado en 0x38B0…22e6AD es la etiqueta 2026-08-25, igual en
// lógica a 2026-10-06). Variante B1: las cinco entradas sin reasignaciones públicas, sobre Morpho Blue real (0.8.19,
// por deployCode, sin interés), con dos mercados de los mismos tokens (para la migración) y uno de otro colateral.
// Leyes exactas contra el estado de Blue, en cada llamada que pasa:
//   BB-FUNDS  el bundle no se queda con saldo; lo que paga y cobra el usuario es exactamente lo documentado;
//   BB-FEE    la comisión de referido es exactamente la documentada, sobre lo que de verdad se pidió, repagó o retiró;
//   BB-POS    la posición del usuario en Blue cambia exactamente (acciones redondeadas como Blue);
//   BB-LTV    con maxLtv, el LTV resultante (deuda redondeada hacia arriba, como el bundle) no lo supera;
//   BB-ISO    ninguna otra posición ni saldo cambia;
//   BB-LIVE   con el plazo vencido, pct >= WAD o tokens distintos en la migración, revierte.

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IMorpho, MarketParams, Position, Market} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {BlueBundlesV1} from "../../src/blue/BlueBundlesV1.sol";
import {IBlueBundlesV1, SignedAuthorization, PublicAllocations} from "../../src/blue/interfaces/IBlueBundlesV1.sol";
import {TokenPermit, PermitKind} from "../../src/libraries/TokenLib.sol";

contract NexusBBToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n) {
        name = n;
        symbol = n;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

/// @notice Oráculo de Blue de prueba (escala 1e36: activo prestado por unidad de colateral).
contract NexusBBOracle {
    uint256 public price = 1e36;

    function setPrice(uint256 p) external {
        price = p;
    }
}

contract NexusBlueBundlesHandler is Test {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant PSCALE = 1e36;
    uint256 internal constant NH = 4; // usuarios
    uint256 internal constant NA = 6; // los 4 usuarios y 2 referidos
    uint256 internal constant I_REF = 4;
    uint256 internal constant NM = 4; // mercados: 0 y 1 con un colateral, 2 y 3 con otro (distinto LLTV)
    uint256 internal constant AMT = 1e24;

    uint8 internal constant L_FUNDS = 0;
    uint8 internal constant L_FEE = 1;
    uint8 internal constant L_POS = 2;
    uint8 internal constant L_LTV = 3;
    uint8 internal constant L_ISO = 4;
    uint8 internal constant L_LIVE = 5;
    uint8 internal constant N_LAWS = 6;

    IMorpho internal blue;
    BlueBundlesV1 internal bundle;
    NexusBBToken internal loan;
    NexusBBToken[2] internal coll;
    NexusBBOracle[2] internal oracle;
    MarketParams[4] internal mps;
    address[6] internal accts;

    uint256 internal violations;
    uint256 internal lawMask;
    string internal firstViolation;
    uint256 internal hLaws;
    uint256[5] internal hCalls;
    uint256[5] internal hOk;
    uint256 internal hFees;
    uint256 internal hLtvChecked;
    uint256 internal hMigrations;
    uint256[8] internal hRev; // 0 LtvExceeded, 1 InconsistentTokens, 2 plazo o pct, 3 Blue (salud, liquidez), 4 pánico, 5 otro

    struct Acct {
        uint256 loan;
        uint256 c0;
        uint256 c1;
        uint256[4] supplyShares;
        uint256[4] borrowShares;
        uint256[4] collateral;
    }

    struct Snap {
        Acct[6] a;
        uint256 bLoan;
        uint256 bC0;
        uint256 bC1;
        uint256[4] tsa; // por mercado: totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares
        uint256[4] tss;
        uint256[4] tba;
        uint256[4] tbs;
    }

    struct P {
        uint256 u;
        uint256 m;
        uint256 pct;
        uint256 ref;
        uint256 deadline;
        uint256 maxLtv;
    }

    constructor() {
        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        blue.enableIrm(address(0));
        blue.enableLltv(0.86e18);
        blue.enableLltv(0.945e18);
        loan = new NexusBBToken("loan");
        coll[0] = new NexusBBToken("collA");
        coll[1] = new NexusBBToken("collB");
        oracle[0] = new NexusBBOracle();
        oracle[1] = new NexusBBOracle();
        mps[0] = MarketParams(address(loan), address(coll[0]), address(oracle[0]), address(0), 0.86e18);
        mps[1] = MarketParams(address(loan), address(coll[0]), address(oracle[0]), address(0), 0.945e18);
        mps[2] = MarketParams(address(loan), address(coll[1]), address(oracle[1]), address(0), 0.86e18);
        mps[3] = MarketParams(address(loan), address(coll[1]), address(oracle[1]), address(0), 0.945e18);
        // liquidez inicial de un prestamista aparte (no es un actor): sin ella casi no hay deuda que repagar o migrar
        address lp = address(uint160(uint256(keccak256("nexus.bb.lp"))));
        loan.mint(lp, NM * 100 * AMT);
        vm.prank(lp);
        loan.approve(address(blue), type(uint256).max);
        for (uint256 i; i < NM; ++i) {
            blue.createMarket(mps[i]);
            vm.prank(lp);
            blue.supply(mps[i], 100 * AMT, 0, lp, "");
        }
        bundle = new BlueBundlesV1(address(blue), address(uint160(uint256(keccak256("nexus.bb.allocator")))));
        for (uint256 h; h < NA; ++h) {
            address u = address(uint160(uint256(keccak256(abi.encode("nexus.bb.acct", h)))));
            accts[h] = u;
            if (h >= NH) continue;
            vm.startPrank(u);
            blue.setAuthorization(address(bundle), true);
            loan.approve(address(bundle), type(uint256).max);
            loan.approve(address(blue), type(uint256).max);
            for (uint256 i; i < 2; ++i) {
                coll[i].approve(address(bundle), type(uint256).max);
                coll[i].approve(address(blue), type(uint256).max);
            }
            vm.stopPrank();
        }
    }

    /* LAS ENTRADAS */

    function supplyCollateralAndBorrow(uint256 userSeed, uint256 seed, uint256 cSeed, uint256 bSeed) external {
        P memory p = _params(userSeed, seed);
        uint256 c = _h(cSeed, 1) % 8 == 0 ? 0 : _amt(cSeed, 2, AMT);
        NexusBBToken ct = _collOf(p.m);
        ct.mint(accts[p.u], c);
        uint256 maxB = _maxBorrow(p.u, p.m, c);
        uint256 b = _h(bSeed, 3) % 8 == 0 ? 0 : (_h(bSeed, 4) % 4 == 0 ? _amt(bSeed, 5, AMT) : _amt(bSeed, 6, maxB + 1) - 1);
        Snap memory pre = _snap();
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(bundle).call(
            abi.encodeCall(
                bundle.blueBundlesV1SupplyCollateralAndBorrow,
                (mps[p.m], c, b, p.maxLtv, _noPermit(), _noSig(), new PublicAllocations[](0), p.pct, accts[p.ref],
                    p.deadline)
            )
        );
        if (!_after(0, ok, ret, p, pre)) return;
        Snap memory post = _snap();
        uint256 fee = b * p.pct / WAD;
        _okI(_dl(pre, post, p.ref) == int256(fee), L_FEE, "SupplyCollateralAndBorrow: comision distinta de borrow*pct/WAD (esperada, real)", int256(fee), _dl(pre, post, p.ref));
        _okI(_dl(pre, post, p.u) == int256(b - fee), L_FUNDS, "SupplyCollateralAndBorrow: el usuario no recibio borrow menos la comision (esperado, recibido)", int256(b - fee), _dl(pre, post, p.u));
        _okI(_dc(pre, post, p.u, p.m) == -int256(c), L_FUNDS, "SupplyCollateralAndBorrow: el usuario no pago exactamente el colateral (esperado, pagado)", -int256(c), _dc(pre, post, p.u, p.m));
        _ok(post.a[p.u].collateral[p.m] == pre.a[p.u].collateral[p.m] + c, L_POS, "SupplyCollateralAndBorrow: el colateral en Blue no subio exactamente (esperado, real)", pre.a[p.u].collateral[p.m] + c, post.a[p.u].collateral[p.m]);
        uint256 sh = b == 0 ? 0 : b.toSharesUp(pre.tba[p.m], pre.tbs[p.m]);
        _ok(post.a[p.u].borrowShares[p.m] == pre.a[p.u].borrowShares[p.m] + sh, L_POS, "SupplyCollateralAndBorrow: las acciones de deuda no subieron como redondea Blue (esperado, real)", pre.a[p.u].borrowShares[p.m] + sh, post.a[p.u].borrowShares[p.m]);
        _ltvLaw(p.u, p.m, p.maxLtv, post);
        if (fee > 0) ++hFees;
    }

    function repayAndWithdrawCollateral(uint256 userSeed, uint256 seed, uint256 rSeed, uint256 cSeed) external {
        P memory p = _params(userSeed, seed);
        p.m = _withDebt(p.u, p.m);
        uint256 debtShares = blue.position(mps[p.m].id(), accts[p.u]).borrowShares;
        uint256 debtAssets = debtShares.toAssetsUp(_tba(p.m), _tbs(p.m));
        uint256 mode = _h(rSeed, 7) % 6; // 0: nada; 1, 4, 5: por activos; 2: por acciones; 3: todas (max)
        if (debtShares == 0 && mode != 0) mode = 3; // sin deuda: repago nulo (con max) y retiro del colateral libre
        uint256 rA;
        uint256 rS;
        // casi siempre dentro de la deuda; 1 de cada 8, hasta el doble (repagar de más revierte en Blue)
        uint256 capA = debtAssets == 0 ? AMT : (_h(rSeed, 21) % 8 == 0 ? 2 * debtAssets : debtAssets);
        if (mode == 1 || mode >= 4) rA = _amt(rSeed, 8, capA);
        if (mode == 2) rS = debtShares == 0 ? 1 : _amt(rSeed, 9, debtShares);
        if (mode == 3) rS = type(uint256).max;
        if (_h(rSeed, 10) % 32 == 0) {
            rA = 1 + rSeed % AMT; // los dos distintos de cero: Blue revierte
            rS = 1;
        }
        uint256 maxRepay = 2 * AMT + (_h(rSeed, 11) % 4 == 0 ? rSeed % AMT : 0);
        loan.mint(accts[p.u], maxRepay);
        uint256 have = blue.position(mps[p.m].id(), accts[p.u]).collateral;
        // retiro de colateral: nada, todo (sano si repaga todo), o hasta lo que sobra sobre la deuda actual
        uint256 spare = _spare(p.u, p.m);
        uint256 c = _h(cSeed, 12) % 3 == 0 ? 0 : (mode == 3 && _h(cSeed, 13) % 2 == 0 ? have : _amt(cSeed, 14, spare + 1) - 1);
        Snap memory pre = _snap();
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(bundle).call(
            abi.encodeCall(
                bundle.blueBundlesV1RepayAndWithdrawCollateral,
                (mps[p.m], rA, rS, maxRepay, c, p.maxLtv, _noPermit(), _noSig(), p.pct, accts[p.ref], p.deadline)
            )
        );
        if (!_after(1, ok, ret, p, pre)) return;
        Snap memory post = _snap();
        if (rS == type(uint256).max) rS = pre.a[p.u].borrowShares[p.m];
        uint256 repaid;
        uint256 sh;
        if (rA > 0) {
            repaid = rA;
            sh = rA.toSharesDown(pre.tba[p.m], pre.tbs[p.m]);
        } else if (rS > 0) {
            sh = rS;
            repaid = rS.toAssetsUp(pre.tba[p.m], pre.tbs[p.m]);
        }
        uint256 fee = repaid * p.pct / (WAD - p.pct);
        _okI(_dl(pre, post, p.ref) == int256(fee), L_FEE, "RepayAndWithdrawCollateral: comision distinta de repaid*pct/(WAD-pct) (esperada, real)", int256(fee), _dl(pre, post, p.ref));
        _okI(_dl(pre, post, p.u) == -int256(repaid + fee), L_FUNDS, "RepayAndWithdrawCollateral: el usuario no pago exactamente lo repagado mas la comision (esperado, pagado)", -int256(repaid + fee), _dl(pre, post, p.u));
        _ok(post.a[p.u].borrowShares[p.m] + sh == pre.a[p.u].borrowShares[p.m], L_POS, "RepayAndWithdrawCollateral: las acciones de deuda no bajaron como redondea Blue (esperado, real)", pre.a[p.u].borrowShares[p.m] - sh, post.a[p.u].borrowShares[p.m]);
        _ok(post.a[p.u].collateral[p.m] + c == pre.a[p.u].collateral[p.m], L_POS, "RepayAndWithdrawCollateral: el colateral en Blue no bajo exactamente (esperado, real)", pre.a[p.u].collateral[p.m] - c, post.a[p.u].collateral[p.m]);
        _okI(_dc(pre, post, p.u, p.m) == int256(c), L_FUNDS, "RepayAndWithdrawCollateral: el usuario no recibio exactamente el colateral (esperado, recibido)", int256(c), _dc(pre, post, p.u, p.m));
        _ltvLaw(p.u, p.m, p.maxLtv, post);
        if (fee > 0) ++hFees;
    }

    function supply(uint256 userSeed, uint256 seed, uint256 aSeed) external {
        P memory p = _params(userSeed, seed);
        uint256 a = _amt(aSeed, 15, AMT);
        loan.mint(accts[p.u], a);
        Snap memory pre = _snap();
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(bundle).call(
            abi.encodeCall(bundle.blueBundlesV1Supply, (mps[p.m], a, _noPermit(), p.pct, accts[p.ref], p.deadline))
        );
        if (!_after(2, ok, ret, p, pre)) return;
        Snap memory post = _snap();
        uint256 fee = a * p.pct / WAD;
        uint256 sh = (a - fee).toSharesDown(pre.tsa[p.m], pre.tss[p.m]);
        _okI(_dl(pre, post, p.ref) == int256(fee), L_FEE, "Supply: comision distinta de assets*pct/WAD (esperada, real)", int256(fee), _dl(pre, post, p.ref));
        _okI(_dl(pre, post, p.u) == -int256(a), L_FUNDS, "Supply: el usuario no pago exactamente assets (esperado, pagado)", -int256(a), _dl(pre, post, p.u));
        _ok(post.a[p.u].supplyShares[p.m] == pre.a[p.u].supplyShares[p.m] + sh, L_POS, "Supply: las acciones de oferta no subieron como redondea Blue (esperado, real)", pre.a[p.u].supplyShares[p.m] + sh, post.a[p.u].supplyShares[p.m]);
        if (fee > 0) ++hFees;
    }

    function withdraw(uint256 userSeed, uint256 seed, uint256 wSeed) external {
        P memory p = _params(userSeed, seed);
        uint256 have = blue.position(mps[p.m].id(), accts[p.u]).supplyShares;
        uint256 wA;
        uint256 wS;
        uint256 mode = _h(wSeed, 16) % 4;
        if (mode == 0) wS = have; // toda la posición
        else if (mode == 1) wS = _amt(wSeed, 17, have + 1) - 1;
        else wA = _amt(wSeed, 18, have == 0 ? AMT : have.toAssetsDown(_tsa(p.m), _tss(p.m)) + 1);
        Snap memory pre = _snap();
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(bundle).call(
            abi.encodeCall(
                bundle.blueBundlesV1Withdraw,
                (mps[p.m], wA, wS, _noSig(), new PublicAllocations[](0), p.pct, accts[p.ref], p.deadline)
            )
        );
        if (!_after(3, ok, ret, p, pre)) return;
        Snap memory post = _snap();
        uint256 got;
        uint256 sh;
        if (wA > 0) {
            got = wA;
            sh = wA.toSharesUp(pre.tsa[p.m], pre.tss[p.m]);
        } else {
            sh = wS;
            got = wS.toAssetsDown(pre.tsa[p.m], pre.tss[p.m]);
        }
        uint256 fee = got * p.pct / WAD;
        _okI(_dl(pre, post, p.ref) == int256(fee), L_FEE, "Withdraw: comision distinta de withdrawn*pct/WAD (esperada, real)", int256(fee), _dl(pre, post, p.ref));
        _okI(_dl(pre, post, p.u) == int256(got - fee), L_FUNDS, "Withdraw: el usuario no recibio lo retirado menos la comision (esperado, recibido)", int256(got - fee), _dl(pre, post, p.u));
        _ok(post.a[p.u].supplyShares[p.m] + sh == pre.a[p.u].supplyShares[p.m], L_POS, "Withdraw: las acciones de oferta no bajaron como redondea Blue (esperado, real)", pre.a[p.u].supplyShares[p.m] - sh, post.a[p.u].supplyShares[p.m]);
        if (fee > 0) ++hFees;
    }

    function migrate(uint256 userSeed, uint256 seed, uint256 dSeed) external {
        P memory p = _params(userSeed, seed);
        p.m = _withDebt(p.u, p.m);
        // la pareja con los mismos tokens; 1 de cada 8, un mercado de la otra familia (tiene que revertir)
        uint256 dst = _h(dSeed, 19) % 8 == 0 ? (p.m + 2) % NM : p.m ^ 1;
        bool otherTokens = (p.m >= 2) != (dst >= 2);
        Snap memory pre = _snap();
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(bundle).call(
            abi.encodeCall(
                bundle.blueBundlesV1MigrateBorrowPosition,
                (mps[p.m], mps[dst], p.maxLtv, _noSig(), new PublicAllocations[](0), p.pct, accts[p.ref], p.deadline)
            )
        );
        if (otherTokens) _ok(!ok, L_LIVE, "Migrate: paso con tokens distintos entre origen y destino (origen, destino)", p.m, dst);
        if (!_after(4, ok && !otherTokens, ret, p, pre)) return;
        Snap memory post = _snap();
        uint256 sh = pre.a[p.u].borrowShares[p.m];
        uint256 c = pre.a[p.u].collateral[p.m];
        uint256 repaid = sh.toAssetsUp(pre.tba[p.m], pre.tbs[p.m]);
        uint256 fee = repaid * p.pct / (WAD - p.pct);
        _ok(post.a[p.u].borrowShares[p.m] == 0 && post.a[p.u].collateral[p.m] == 0, L_POS, "Migrate: la posicion de origen no quedo en cero (acciones de deuda, colateral)", post.a[p.u].borrowShares[p.m], post.a[p.u].collateral[p.m]);
        _ok(post.a[p.u].collateral[dst] == pre.a[p.u].collateral[dst] + c, L_POS, "Migrate: el colateral de destino no subio exactamente el de origen (esperado, real)", pre.a[p.u].collateral[dst] + c, post.a[p.u].collateral[dst]);
        uint256 shDst = (repaid + fee).toSharesUp(pre.tba[dst], pre.tbs[dst]);
        _ok(post.a[p.u].borrowShares[dst] == pre.a[p.u].borrowShares[dst] + shDst, L_POS, "Migrate: la deuda de destino no es lo repagado mas la comision (esperado, real)", pre.a[p.u].borrowShares[dst] + shDst, post.a[p.u].borrowShares[dst]);
        _okI(_dl(pre, post, p.ref) == int256(fee), L_FEE, "Migrate: comision distinta de repaid*pct/(WAD-pct) (esperada, real)", int256(fee), _dl(pre, post, p.ref));
        _okI(_dl(pre, post, p.u), L_FUNDS, "Migrate: cambio el saldo del usuario (cambio, 0)", _dl(pre, post, p.u), 0);
        _ltvLaw(p.u, dst, p.maxLtv, post);
        ++hMigrations;
        if (fee > 0) ++hFees;
    }

    /* ENTRE LLAMADAS */

    /// @dev Otro actor deposita en Blue directo (liquidez para pedir prestado y retirar).
    function lend(uint256 seed, uint256 aSeed) external {
        uint256 h = _h(seed, 30) % NH;
        uint256 m = _h(seed, 31) % NM;
        uint256 a = _amt(aSeed, 32, AMT);
        loan.mint(accts[h], a);
        vm.prank(accts[h]);
        blue.supply(mps[m], a, 0, accts[h], "");
    }

    function setPrice(uint256 i, uint256 seed) external {
        oracle[i % 2].setPrice(PSCALE / 2 + seed % (2 * PSCALE));
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + 1 + secs % 7 days);
    }

    /* PIEZAS */

    function _h(uint256 seed, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, salt)));
    }

    /// @dev Un monto en [1, max]: 1 de cada 4 veces el valor crudo, las demás uniforme.
    function _amt(uint256 seed, uint256 salt, uint256 max) internal pure returns (uint256) {
        return _h(seed, salt) % 4 == 0 ? 1 + seed % max : 1 + _h(seed, salt + 1) % max;
    }

    function _params(uint256 userSeed, uint256 seed) internal view returns (P memory p) {
        uint256 s = _h(seed, 40);
        p.u = userSeed % NH;
        p.m = s % NM;
        uint256 k = (s >> 8) % 8;
        p.pct = k < 3 ? 0 : (k == 3 ? 1 : (k == 4 ? 0.003e18 : (k == 5 ? 0.5e18 : (k == 6 ? WAD - 1 : WAD))));
        p.ref = I_REF + (s >> 16) % 2;
        p.deadline = (s >> 24) % 32 == 0 ? block.timestamp - 1 : block.timestamp;
        uint256 l = (s >> 32) % 4;
        p.maxLtv = l == 0 ? 0.5e18 : (l == 1 ? 0.8e18 : type(uint256).max);
    }

    /// @dev Un mercado donde `u` tiene deuda, empezando por `m` (o `m` si no tiene en ninguno).
    function _withDebt(uint256 u, uint256 m) internal view returns (uint256) {
        for (uint256 j; j < NM; ++j) {
            uint256 k = (m + j) % NM;
            if (blue.position(mps[k].id(), accts[u]).borrowShares > 0) return k;
        }
        return m;
    }

    /// @dev El colateral de `u` en `m` que sobra sobre lo que pide su deuda actual (con el LLTV del mercado).
    function _spare(uint256 u, uint256 m) internal view returns (uint256) {
        Position memory pos = blue.position(mps[m].id(), accts[u]);
        uint256 owed = uint256(pos.borrowShares).toAssetsUp(_tba(m), _tbs(m));
        uint256 price = (m >= 2 ? oracle[1] : oracle[0]).price();
        if (price == 0) return 0;
        uint256 need = owed == 0 ? 0 : (owed * WAD / mps[m].lltv + 1) * PSCALE / price + 1;
        return pos.collateral > need ? pos.collateral - need : 0;
    }

    function _collOf(uint256 m) internal view returns (NexusBBToken) {
        return m >= 2 ? coll[1] : coll[0];
    }

    /// @dev Lo que se puede pedir sano con `c` de colateral más, contando lo que ya debe.
    function _maxBorrow(uint256 u, uint256 m, uint256 c) internal view returns (uint256) {
        Position memory pos = blue.position(mps[m].id(), accts[u]);
        uint256 col = pos.collateral + c;
        uint256 price = (m >= 2 ? oracle[1] : oracle[0]).price();
        uint256 maxB = col * price / PSCALE * mps[m].lltv / WAD;
        uint256 owed = uint256(pos.borrowShares).toAssetsUp(_tba(m), _tbs(m));
        uint256 liq = _tsa(m) - _tba(m);
        maxB = maxB > owed ? maxB - owed : 0;
        return maxB < liq ? maxB : liq;
    }

    function _tsa(uint256 m) internal view returns (uint256) {
        return blue.market(mps[m].id()).totalSupplyAssets;
    }

    function _tss(uint256 m) internal view returns (uint256) {
        return blue.market(mps[m].id()).totalSupplyShares;
    }

    function _tba(uint256 m) internal view returns (uint256) {
        return blue.market(mps[m].id()).totalBorrowAssets;
    }

    function _tbs(uint256 m) internal view returns (uint256) {
        return blue.market(mps[m].id()).totalBorrowShares;
    }

    function _noPermit() internal pure returns (TokenPermit memory t) {
        t.kind = PermitKind.None;
    }

    function _noSig() internal pure returns (SignedAuthorization memory a) {}

    function _snap() internal view returns (Snap memory s) {
        for (uint256 h; h < NA; ++h) {
            address w = accts[h];
            s.a[h].loan = loan.balanceOf(w);
            s.a[h].c0 = coll[0].balanceOf(w);
            s.a[h].c1 = coll[1].balanceOf(w);
            for (uint256 m; m < NM; ++m) {
                Position memory pos = blue.position(mps[m].id(), w);
                s.a[h].supplyShares[m] = pos.supplyShares;
                s.a[h].borrowShares[m] = pos.borrowShares;
                s.a[h].collateral[m] = pos.collateral;
            }
        }
        for (uint256 m; m < NM; ++m) {
            Market memory mk = blue.market(mps[m].id());
            s.tsa[m] = mk.totalSupplyAssets;
            s.tss[m] = mk.totalSupplyShares;
            s.tba[m] = mk.totalBorrowAssets;
            s.tbs[m] = mk.totalBorrowShares;
        }
        s.bLoan = loan.balanceOf(address(bundle));
        s.bC0 = coll[0].balanceOf(address(bundle));
        s.bC1 = coll[1].balanceOf(address(bundle));
    }

    /// @dev BB-LIVE, y si pasó, BB-FUNDS (el bundle sin saldo) y BB-ISO. Devuelve si siguen las leyes de la entrada.
    function _after(uint256 kind, bool ok, bytes memory ret, P memory p, Snap memory pre) internal returns (bool) {
        ++hCalls[kind];
        bool mustRevert = p.deadline < block.timestamp || p.pct >= WAD;
        _ok(!(ok && mustRevert), L_LIVE, "paso con el plazo vencido o con comision de referido >= WAD (entrada, comision)", kind, p.pct);
        if (!ok) {
            ++hRev[_revKind(ret)];
            return false;
        }
        if (mustRevert) return false;
        ++hOk[kind];
        Snap memory post = _snap();
        _ok(post.bLoan == 0 && post.bC0 == 0 && post.bC1 == 0, L_FUNDS, "el bundle quedo con saldo (activo, colateral 0)", post.bLoan, post.bC0);
        for (uint256 h; h < NA; ++h) {
            if (h == p.u || h == p.ref) continue;
            Acct memory a = pre.a[h];
            Acct memory b = post.a[h];
            bool same = a.loan == b.loan && a.c0 == b.c0 && a.c1 == b.c1;
            for (uint256 m; m < NM; ++m) {
                same = same && a.supplyShares[m] == b.supplyShares[m] && a.borrowShares[m] == b.borrowShares[m]
                    && a.collateral[m] == b.collateral[m];
            }
            _ok(same, L_ISO, "cambio la posicion o el saldo de alguien ajeno a la llamada (cuenta, entrada)", h, kind);
        }
        return true;
    }

    /// @dev BB-LTV: lo mismo que controla el bundle, sobre el estado final del mercado `m` de `u`. Parámetros sueltos y
    /// no un P: en Solidity, `P memory q = p` copia la referencia, y cambiar q.m cambiaba p.m (falso positivo del 30-oct).
    function _ltvLaw(uint256 u, uint256 m, uint256 maxLtv, Snap memory post) internal {
        if (maxLtv == type(uint256).max) return;
        uint256 shares = post.a[u].borrowShares[m];
        if (shares == 0) return;
        ++hLtvChecked;
        uint256 borrowed = shares.toAssetsUp(post.tba[m], post.tbs[m]);
        uint256 price = (m >= 2 ? oracle[1] : oracle[0]).price();
        uint256 maxBorrow = post.a[u].collateral[m] * price / PSCALE * maxLtv / WAD;
        _ok(borrowed <= maxBorrow, L_LTV, "paso con un LTV mayor que maxLtv (deuda, maximo)", borrowed, maxBorrow);
    }

    function _dl(Snap memory pre, Snap memory post, uint256 h) internal pure returns (int256) {
        return int256(post.a[h].loan) - int256(pre.a[h].loan);
    }

    /// @dev Variación del saldo del colateral del mercado `m` de `h`.
    function _dc(Snap memory pre, Snap memory post, uint256 h, uint256 m) internal pure returns (int256) {
        return m >= 2 ? int256(post.a[h].c1) - int256(pre.a[h].c1) : int256(post.a[h].c0) - int256(pre.a[h].c0);
    }

    function _revKind(bytes memory ret) internal pure returns (uint256) {
        if (ret.length < 4) return 5;
        bytes4 s = bytes4(ret);
        if (s == IBlueBundlesV1.LtvExceeded.selector) return 0;
        if (s == IBlueBundlesV1.InconsistentTokens.selector) return 1;
        if (s == IBlueBundlesV1.DeadlinePassed.selector || s == IBlueBundlesV1.PctExceeded.selector) return 2;
        if (s == bytes4(0x08c379a0)) return 3; // Error(string): los require de Blue
        if (s == bytes4(0x4e487b71)) return 4;
        return 5;
    }

    function _ok(bool cond, uint8 law, string memory what, uint256 x, uint256 y) internal {
        unchecked {
            ++hLaws;
        }
        if (!cond) {
            lawMask |= uint256(1) << law;
            if (violations++ == 0) {
                firstViolation = string(abi.encodePacked(_lawName(law), ": ", what, ": ", vm.toString(x), ", ", vm.toString(y)));
            }
        }
    }

    function _okI(bool cond, uint8 law, string memory what, int256 x, int256 y) internal {
        unchecked {
            ++hLaws;
        }
        if (!cond) {
            lawMask |= uint256(1) << law;
            if (violations++ == 0) {
                firstViolation = string(abi.encodePacked(_lawName(law), ": ", what, ": ", vm.toString(x), ", ", vm.toString(y)));
            }
        }
    }

    function _okI(int256 d, uint8 law, string memory what, int256 x, int256 y) internal {
        _okI(d == 0, law, what, x, y);
    }

    function _lawName(uint8 law) internal pure returns (string memory) {
        if (law == L_FUNDS) return "BB-FUNDS";
        if (law == L_FEE) return "BB-FEE";
        if (law == L_POS) return "BB-POS";
        if (law == L_LTV) return "BB-LTV";
        if (law == L_ISO) return "BB-ISO";
        return "BB-LIVE";
    }

    function check() external view returns (string memory) {
        if (violations == 0) return "";
        string memory list;
        for (uint8 l; l < N_LAWS; ++l) {
            if (lawMask & (uint256(1) << l) != 0) {
                list = string(abi.encodePacked(list, bytes(list).length == 0 ? "" : " ", _lawName(l)));
            }
        }
        return string(abi.encodePacked(firstViolation, " [leyes: ", list, "]"));
    }

    function coverage()
        external
        view
        returns (uint256, uint256[5] memory, uint256[5] memory, uint256, uint256, uint256, uint256[8] memory)
    {
        return (hLaws, hCalls, hOk, hFees, hLtvChecked, hMigrations, hRev);
    }
}

contract NexusBlueBundlesTest is Test {
    NexusBlueBundlesHandler internal handler;

    function setUp() public {
        handler = new NexusBlueBundlesHandler();
        bytes4[] memory sels = new bytes4[](8);
        sels[0] = handler.supplyCollateralAndBorrow.selector;
        sels[1] = handler.repayAndWithdrawCollateral.selector;
        sels[2] = handler.supply.selector;
        sels[3] = handler.withdraw.selector;
        sels[4] = handler.migrate.selector;
        sels[5] = handler.lend.selector;
        sels[6] = handler.setPrice.selector;
        sels[7] = handler.warp.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: sels}));
        targetContract(address(handler));
    }

    function invariant_blueBundles() public view {
        string memory err = handler.check();
        require(bytes(err).length == 0, err);
    }

    function afterInvariant() public {
        (uint256 laws, uint256[5] memory calls, uint256[5] memory oks, uint256 fees, uint256 ltv, uint256 mig,
            uint256[8] memory r) = handler.coverage();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cobertura: SupplyCollateralAndBorrow que pasaron", oks[0]);
        emit log_named_uint("cobertura: RepayAndWithdrawCollateral que pasaron", oks[1]);
        emit log_named_uint("cobertura: Supply que pasaron", oks[2]);
        emit log_named_uint("cobertura: Withdraw que pasaron", oks[3]);
        emit log_named_uint("cobertura: MigrateBorrowPosition que pasaron", oks[4]);
        emit log_named_uint("cobertura: llamadas al bundle", calls[0] + calls[1] + calls[2] + calls[3] + calls[4]);
        emit log_named_uint("cobertura: llamadas con comision de referido", fees);
        emit log_named_uint("cobertura: controles de maxLtv", ltv);
        emit log_named_uint("cobertura: migraciones", mig);
        emit log_named_uint("reversiones: LtvExceeded", r[0]);
        emit log_named_uint("reversiones: InconsistentTokens", r[1]);
        emit log_named_uint("reversiones: plazo o comision >= WAD", r[2]);
        emit log_named_uint("reversiones: Blue (salud, liquidez, entradas)", r[3]);
        emit log_named_uint("reversiones: panico aritmetico", r[4]);
        emit log_named_uint("reversiones: otras", r[5]);
    }
}
