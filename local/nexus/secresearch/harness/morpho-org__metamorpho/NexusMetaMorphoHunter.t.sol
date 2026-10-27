// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// Suite del cazador (NexusVulnerabilityHunter) en un entorno multi-mercado: el handler de
// NexusMetaMorphoInvariant.t.sol (misma API) más dos mercados con préstamos, topes que se alcanzan, colas en distinto
// orden, gobierno con timelock (topes, remociones, colas, comisión, timelock), saltos a la frontera de cada timelock y
// seis macros de cacería: inflación, comisión relámpago, ciclo de reasignaciones, tokens sueltos en el vault y las
// fronteras exactas de los timelocks de tope y de remoción.
//
// Las decisiones discretas (qué mercado, qué régimen de tope, qué cola) salen de un hash de la semilla: forge sesga
// los enteros hacia valores chicos y de diccionario, que sirven para montos (0, 1, máximos) pero no para elegir.

import {Test} from "../../lib/forge-std/src/Test.sol";
import {MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {IMorpho} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {MarketAllocation} from "../../src/interfaces/IMetaMorpho.sol";
import {OracleMock} from "../../src/mocks/OracleMock.sol";
import {NexusMetaMorphoHandler} from "./NexusMetaMorphoInvariant.t.sol";

contract NexusMetaMorphoHunterHandler is NexusMetaMorphoHandler {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    uint256 internal constant LLTV2 = 0.9 ether;
    uint256 internal constant LLTV3 = 0.945 ether;
    uint256 internal constant CAP_MARKET = 2e27; // se alcanza con MAX_ASSETS = 1e28 por depósito
    uint256 internal constant CAP_MARKET2 = 1e27;
    address internal constant SKIM = address(uint160(uint256(keccak256("nexus.Skim"))));

    MarketParams[] internal hm; // [market, idle, market2, market3]: mismo orden que el registro del cazador

    constructor(uint256 fee, uint8 assetDecimals) NexusMetaMorphoHandler(fee, assetDecimals) {
        OracleMock oracle2 = new OracleMock();
        OracleMock oracle3 = new OracleMock();
        oracle2.setPrice(ORACLE_PRICE_SCALE);
        oracle3.setPrice(ORACLE_PRICE_SCALE);
        MarketParams memory market2 = MarketParams(
            address(loanToken), address(collateralToken), address(oracle2), address(irm), LLTV2
        );
        MarketParams memory market3 = MarketParams(
            address(loanToken), address(collateralToken), address(oracle3), address(irm), LLTV3
        );
        CHEATS.startPrank(MORPHO_OWNER);
        morpho.enableLltv(LLTV2);
        morpho.enableLltv(LLTV3);
        CHEATS.stopPrank();
        morpho.createMarket(market2);
        morpho.createMarket(market3);

        CHEATS.startPrank(CURATOR);
        vault.submitCap(market, CAP_MARKET); // bajar es inmediato
        vault.submitCap(market2, CAP_MARKET2); // subir espera el timelock
        CHEATS.stopPrank();
        CHEATS.warp(vault.pendingCap(market2.id()).validAt); // absoluto: con via_ir block.timestamp puede estar cacheado
        vault.acceptCap(market2); // cola de retiro: [market, idle, market2]

        Id[] memory sq = new Id[](3);
        sq[0] = market2.id(); // cola de suministro en otro orden: [market2, market, idle]
        sq[1] = market.id();
        sq[2] = idle.id();
        CHEATS.prank(ALLOCATOR);
        vault.setSupplyQueue(sq);
        CHEATS.prank(OWNER);
        vault.setSkimRecipient(SKIM);

        hm.push(market);
        hm.push(idle);
        hm.push(market2);
        hm.push(market3); // creado y sin habilitar: donaciones a nombre del vault que no cuentan hasta aceptarlo
        _hunterInit(_hunterHolders(), hm);
    }

    /* ENTORNO MULTI-MERCADO */

    function donateTo(uint256 mSeed, uint256 assets) external hunted(OP_DONATE, address(0), address(0), _m(mSeed)) {
        assets = _clamp(assets, 0, MAX_ASSETS);
        if (assets == 0) return;
        loanToken.mint(DONOR, assets);
        CHEATS.prank(DONOR);
        morpho.supply(hm[_m(mSeed)], assets, 0, address(vault), hex"");
    }

    function borrowIn(uint256 mSeed, uint256 assets) external hunted(OP_BORROW, address(0), address(0), _m(mSeed)) {
        MarketParams memory p = hm[_m(mSeed)];
        if (p.collateralToken == address(0)) return; // idle
        assets = _clamp(assets, 0, _liq(p) / 2);
        if (assets == 0) return;
        collateralToken.mint(BORROWER, assets * 4);
        CHEATS.startPrank(BORROWER);
        morpho.supplyCollateral(p, assets * 4, BORROWER, hex"");
        morpho.borrow(p, assets, 0, BORROWER, BORROWER);
        CHEATS.stopPrank();
    }

    function repayIn(uint256 mSeed, uint256 assets) external hunted(OP_REPAY, address(0), address(0), _m(mSeed)) {
        MarketParams memory p = hm[_m(mSeed)];
        assets = _clamp(assets, 0, morpho.expectedBorrowAssets(p, BORROWER));
        if (assets == 0) return;
        loanToken.mint(BORROWER, assets);
        CHEATS.prank(BORROWER);
        morpho.repay(p, assets, 0, BORROWER, hex"");
    }

    function badDebtIn(uint256 mSeed, uint256 assets)
        external
        hunted(OP_BAD_DEBT, address(0), address(0), _m(mSeed))
    {
        MarketParams memory p = hm[_m(mSeed)];
        if (p.collateralToken == address(0)) return;
        assets = _clamp(assets, 0, _liq(p) / 10);
        if (assets == 0) return;
        uint256 collateral = assets * 2;
        collateralToken.mint(BAD_BORROWER, collateral);
        CHEATS.startPrank(BAD_BORROWER);
        morpho.supplyCollateral(p, collateral, BAD_BORROWER, hex"");
        morpho.borrow(p, assets, 0, BAD_BORROWER, BAD_BORROWER);
        CHEATS.stopPrank();
        OracleMock(p.oracle).setPrice(0);
        CHEATS.prank(LIQUIDATOR);
        morpho.liquidate(p, BAD_BORROWER, collateral, 0, hex"");
        OracleMock(p.oracle).setPrice(ORACLE_PRICE_SCALE);
        ++losses;
    }

    function accrueIn(uint256 mSeed) external hunted(OP_ACCRUE, address(0), address(0), _m(mSeed)) {
        morpho.accrueInterest(hm[_m(mSeed)]);
    }

    /// @dev El allocator mueve `assets` de un mercado a otro (retirar todo = retiro por shares).
    function reallocateTo(uint256 fromSeed, uint256 toSeed, uint256 assets)
        external
        hunted(OP_REALLOCATE, address(0), address(0), 0)
    {
        uint256 i = _m(fromSeed);
        uint256 j = _m(toSeed ^ 0x5a5a);
        if (i == j || !hCfg[i].inW || hCfg[j].cap == 0) return;
        MarketParams memory from = hm[i];
        uint256 supplied = morpho.expectedSupplyAssets(from, address(vault));
        uint256 toSupplied = morpho.expectedSupplyAssets(hm[j], address(vault));
        uint256 room = hCfg[j].cap > toSupplied ? hCfg[j].cap - toSupplied : 0;
        uint256 top = _min(supplied, _liq(from));
        if (_h(assets, 7) % 8 != 0) top = _min(top, room); // 1 de cada 8 pide más que el tope: tiene que revertir
        assets = _clamp(assets, 0, top);
        if (assets == 0) return;
        MarketAllocation[] memory al = new MarketAllocation[](2);
        al[0] = MarketAllocation({marketParams: from, assets: supplied - assets});
        al[1] = MarketAllocation({marketParams: hm[j], assets: type(uint256).max});
        CHEATS.prank(ALLOCATOR);
        vault.reallocate(al);
    }

    /// @dev El receptor cobra comisiones: canjea parte de sus acciones (libro "acuñadas − canjeadas" y H-INF-1).
    function claimFees(uint256 shares) external hunted(OP_REDEEM, FEE_RECIPIENT, address(0), 0) {
        shares = _clamp(shares, 0, vault.maxRedeem(FEE_RECIPIENT));
        CHEATS.prank(FEE_RECIPIENT);
        vault.redeem(shares, FEE_RECIPIENT, FEE_RECIPIENT);
    }

    /* GOBIERNO (cada resultado se compara con la predicción del cazador) */

    function submitCap(uint256 mSeed, uint256 capSeed) external {
        uint256 i = _m(mSeed);
        HSnap memory p = _hBegin(address(0));
        uint256 r = _h(capSeed, 1) % 5;
        uint256 claim = p.m[i].claim;
        uint256 cap = r == 0 ? 0 : r == 1 ? claim + capSeed % 1e21 : r == 2 ? claim / 2 : r == 3 ? SUPPLY_CAP : capSeed % 1e28;
        CHEATS.prank(CURATOR);
        bool ok;
        try vault.submitCap(hm[i], cap) {
            ok = true;
        } catch {}
        _hGovSubmitCap(i, cap, ok, p);
    }

    function acceptCap(uint256 mSeed) external {
        uint256 i = _m(mSeed);
        HSnap memory p = _hBegin(address(0));
        bool ok;
        try vault.acceptCap(hm[i]) {
            ok = true;
        } catch {}
        _hGovAcceptCap(i, ok, p);
    }

    function revokePending(uint256 mSeed, bool removal) external {
        uint256 i = _m(mSeed);
        HSnap memory p = _hBegin(address(0));
        CHEATS.prank(CURATOR);
        bool ok;
        if (removal) {
            try vault.revokePendingMarketRemoval(hCfg[i].id) {
                ok = true;
            } catch {}
        } else {
            try vault.revokePendingCap(hCfg[i].id) {
                ok = true;
            } catch {}
        }
        _hGovRevoke(i, removal, ok, p);
    }

    function submitRemoval(uint256 mSeed) external {
        uint256 i = _m(mSeed);
        HSnap memory p = _hBegin(address(0));
        CHEATS.prank(CURATOR);
        bool ok;
        try vault.submitMarketRemoval(hm[i]) {
            ok = true;
        } catch {}
        _hGovSubmitRemoval(i, ok, p);
    }

    /// @dev Saca un mercado de la cola de retiro (o ninguno) y rota el resto; a veces repite un índice.
    function updateWithdrawQueue(uint256 seed) external {
        uint256 len = hWQ.length;
        if (len == 0) return;
        HSnap memory p = _hBegin(address(0));
        uint256 r = _h(seed, 2);
        uint256 drop = r % (len + 1);
        uint256 rot = (r >> 64) % len;
        uint256 n = drop < len ? len - 1 : len;
        uint256[] memory idx = new uint256[](n);
        uint256 c;
        for (uint256 j; j < len; ++j) {
            uint256 k = (j + rot) % len;
            if (k != drop) idx[c++] = k;
        }
        if (n > 1 && (r >> 128) % 16 == 0) idx[1] = idx[0]; // índice repetido: tiene que revertir
        CHEATS.prank(ALLOCATOR);
        bool ok;
        try vault.updateWithdrawQueue(idx) {
            ok = true;
        } catch {}
        _hGovUpdateWQ(idx, ok, p);
    }

    /// @dev Subconjunto ordenado al azar y SIN repetidos: con repetidos maxDeposit promete de más, y MetaMorpho
    /// lo documenta ("May be higher than the actual max deposit due to duplicate markets in the supplyQueue").
    function setSupplyQueue(uint256 seed) external {
        HSnap memory p = _hBegin(address(0));
        uint256 r = _h(seed, 3);
        uint256 k = hm.length;
        uint8[] memory perm = new uint8[](k);
        for (uint256 j; j < k; ++j) {
            perm[j] = uint8(j);
        }
        for (uint256 j = k - 1; j > 0; --j) {
            uint256 q = (r >> (8 * j)) % (j + 1);
            (perm[j], perm[q]) = (perm[q], perm[j]);
        }
        uint256 n = 1 + r % k;
        uint8[] memory idx = new uint8[](n);
        Id[] memory ids = new Id[](n);
        for (uint256 j; j < n; ++j) {
            idx[j] = perm[j];
            ids[j] = hCfg[idx[j]].id;
        }
        CHEATS.prank(ALLOCATOR);
        bool ok;
        try vault.setSupplyQueue(ids) {
            ok = true;
        } catch {}
        _hGovSetSupplyQueue(idx, ok, p);
    }

    function setFee(uint256 seed) external {
        HSnap memory p = _hBegin(address(0));
        uint256 r = _h(seed, 4) % 6;
        uint256 newFee = r == 0 ? 0 : r == 1 ? 0.5e18 + 1 : r == 2 ? 0.5e18 : seed % 0.5e18;
        CHEATS.prank(OWNER);
        bool ok;
        try vault.setFee(newFee) {
            ok = true;
        } catch {}
        _hGovSetFee(newFee, ok, p);
    }

    function submitTimelock(uint256 seed) external {
        HSnap memory p = _hBegin(address(0));
        uint256 tl = _h(seed, 5) % 8 == 0 ? 2 weeks + 1 : 1 days + seed % (2 weeks - 1 days + 1);
        CHEATS.prank(OWNER);
        bool ok;
        try vault.submitTimelock(tl) {
            ok = true;
        } catch {}
        _hGovTimelock(false, tl, ok, p);
    }

    function acceptTimelock() external {
        HSnap memory p = _hBegin(address(0));
        bool ok;
        try vault.acceptTimelock() {
            ok = true;
        } catch {}
        _hGovTimelock(true, 0, ok, p);
    }

    /// @dev Salta a validAt − 1, validAt o validAt + 1 de algún tope, remoción o timelock pendiente: la frontera
    /// exacta, que un salto al azar de hasta 30 días casi nunca toca.
    function warpToBoundary(uint256 seed) external {
        uint256 k = hCfg.length;
        uint256 r = _h(seed, 6);
        uint256 now_ = hClock.time();
        uint256 target;
        for (uint256 j; j <= k; ++j) {
            uint256 i = (r + j) % (k + 1);
            uint256 at = i == k
                ? hPendingTlAt
                : hCfg[i].pendingValidAt != 0 ? hCfg[i].pendingValidAt : hCfg[i].removableAt;
            if (at > now_) {
                target = at;
                break;
            }
        }
        if (target == 0) return;
        uint256 t = target - 1 + (r >> 128) % 3;
        if (t > now_) CHEATS.warp(t);
    }

    /* MACROS DE CACERÍA */

    function huntInflation(uint256 aSeed, uint256 vSeed, uint256 dust, uint256 donation, uint256 y) external {
        address attacker = _actor(aSeed);
        address victim = _actor(aSeed + 1 + vSeed % (N_ACTORS - 1));
        _huntInflation(attacker, victim, dust, donation, y, _m(aSeed ^ vSeed));
    }

    function huntFeeFlash(uint256 wSeed, uint256 dt, uint256 assets) external {
        _huntFeeFlash(_actor(wSeed), dt, assets);
    }

    function huntReallocCycle(uint256 seed, uint256 amount) external {
        _huntReallocCycle(seed, amount);
    }

    function huntRawDonation(uint256 amount, uint256 vSeed, uint256 y) external {
        _huntRawDonation(amount, _actor(vSeed), y);
    }

    function huntTimelockCap(uint256 mSeed, uint256 capSeed) external {
        uint256 i = _m(mSeed);
        _huntTimelockCap(i, hCfg[i].cap + 1 + capSeed % 1e27);
    }

    function huntRemoval(uint256 mSeed) external {
        _huntRemoval(_m(mSeed));
    }

    /* AUXILIARES */

    function _m(uint256 seed) internal view returns (uint256) {
        return _h(seed, 0) % hm.length;
    }

    function _h(uint256 seed, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, salt)));
    }

    function _liq(MarketParams memory p) internal view returns (uint256) {
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(p);
        return totalSupplyAssets - totalBorrowAssets;
    }
}

contract NexusMetaMorphoHunterTest is Test {
    NexusMetaMorphoHunterHandler internal handler;

    function setUp() public virtual {
        handler = new NexusMetaMorphoHunterHandler(_fee(), _assetDecimals());
        targetContract(address(handler));
    }

    function _fee() internal pure virtual returns (uint256) {
        return 0;
    }

    function _assetDecimals() internal pure virtual returns (uint8) {
        return 18;
    }

    function invariant_hunter() public view {
        string memory err = handler.check();
        assertEq(bytes(err).length, 0, err);
    }

    function afterInvariant() public {
        (
            uint256 laws,
            uint256 zeros,
            uint256 window,
            uint256 victimLoss,
            uint256 dust,
            uint256 budget,
            uint256 feeAccrued,
            uint256 feeValue,
            uint256 yield_,
            uint256 badDebt,
            uint256 forced
        ) = handler.hunterStats();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cazador: depositos con 0 acciones", zeros);
        emit log_named_uint("cazador: precio maximo de una accion (ventana de redondeo a cero)", window);
        emit log_named_uint("cazador: mayor perdida de una victima", victimLoss);
        emit log_named_uint("cazador: polvo de Morpho absorbido / cota (wei)", dust);
        emit log_named_uint("cazador: cota del polvo (wei)", budget);
        emit log_named_uint("cazador: comision devengada", feeAccrued);
        emit log_named_uint("cazador: comision acunada (valor)", feeValue);
        emit log_named_uint("cazador: rendimiento contable", yield_);
        emit log_named_uint("cazador: perdida por deuda incobrable", badDebt);
        emit log_named_uint("cazador: perdida por remocion forzada", forced);
    }
}

contract NexusMetaMorphoHunterFeeTest is NexusMetaMorphoHunterTest {
    function _fee() internal pure override returns (uint256) {
        return 0.25 ether;
    }
}

contract NexusMetaMorphoHunterSixDecimalsTest is NexusMetaMorphoHunterTest {
    function _assetDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
