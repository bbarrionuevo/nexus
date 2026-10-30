// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.34;

// Cazador de MidnightBundlesV2 (morpho-org/bundles, etiqueta 2026-10-06: lo desplegado en 0x78ed…bDbA4). Fase 1: las
// cuatro entradas de quien toma ofertas (compra y venta, por unidades y por activos), sobre el núcleo real de Midnight,
// con ofertas de los otros actores y un ratifier de prueba. Leyes universales, sin modelo del núcleo, en cada llamada:
//   BU-FUNDS  lo que paga y cobra cada parte cuadra con lo llenado, y el bundle no se queda con saldo;
//   BU-ISO    nadie fuera de la operación cambia de posición ni de saldo;
//   BU-CONS   las unidades que gana o pierde quien llama las pierden o ganan los creadores de las ofertas tomadas,
//             salvo el repago y el retiro de crédito, que mueven `withdrawable` en la misma cantidad;
//   BU-FEE    la comisión de referido es exactamente la documentada, sobre lo que de verdad se llenó;
//   BU-LIMIT  las garantías documentadas de cada entrada: objetivo exacto, mínimos y máximos, reduceOnly, colateral;
//   BU-LIVE   con el plazo vencido o una comisión de referido de WAD o más, la llamada tiene que revertir.

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Midnight} from "../../lib/midnight/src/Midnight.sol";
import {Market, Offer, CollateralParams} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IRatifier} from "../../lib/midnight/src/interfaces/IRatifier.sol";
import {CALLBACK_SUCCESS} from "../../lib/midnight/src/libraries/ConstantsLib.sol";
import {TickLib} from "../../lib/midnight/src/libraries/TickLib.sol";
import {MidnightBundlesV2} from "../../src/midnight/MidnightBundlesV2.sol";
import {IMidnightBundlesV2, OfferFill, CollateralTransfer} from "../../src/midnight/interfaces/IMidnightBundlesV2.sol";

contract NexusMBToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, uint8 d) {
        name = n;
        symbol = n;
        decimals = d;
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

/// @notice Oráculo de prueba (escala 1e36: activo prestado por unidad de colateral).
contract NexusMBOracle {
    uint256 public price = 1e36;

    function setPrice(uint256 p) external {
        price = p;
    }
}

/// @notice Ratifier de prueba: ratifica toda oferta (la autorización del creador la sigue exigiendo el núcleo).
contract NexusMBRatifier is IRatifier {
    function isRatified(Offer memory, bytes memory, address) external pure returns (bytes32) {
        return CALLBACK_SUCCESS;
    }
}

/// @notice Lo único que el constructor del bundle le pide a la fábrica de BlueBuyCallback (fase 1: sin Blue).
contract NexusMBFactoryStub {
    address public immutable MIDNIGHT;
    address public immutable BLUE;

    constructor(address m, address b) {
        MIDNIGHT = m;
        BLUE = b;
    }
}

/// @notice Base: el núcleo, el bundle, los tokens, los oráculos, el mercado y las cuentas.
abstract contract NexusMBBase is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant PSCALE = 1e36;
    uint256 internal constant CBP = 1e12;
    uint256 internal constant M128 = type(uint128).max;
    uint256 internal constant MAX_TICK = 6744;
    uint256 internal constant MAX_CF = uint256(0.01e18) / uint256(365 days);
    uint256 internal constant NH = 4; // actores: crean ofertas y llaman al bundle
    uint256 internal constant NC = 2;
    uint256 internal constant NA = 7; // los 4 actores, 2 referidos y 1 receptor
    uint256 internal constant I_REF = 4;
    uint256 internal constant I_RECV = 6;
    uint256 internal constant AMT = 1e24;
    uint256 internal constant CURSOR = 0.3e18;

    address internal constant FEE_SETTER = address(uint160(uint256(keccak256("nexus.mb.feeSetter"))));
    address internal constant FEE_CLAIMER = address(uint160(uint256(keccak256("nexus.mb.feeClaimer"))));
    address internal constant TICK_SETTER = address(uint160(uint256(keccak256("nexus.mb.tickSetter"))));

    Midnight internal midnight;
    MidnightBundlesV2 internal bundle;
    NexusMBToken internal loan;
    NexusMBToken[2] internal coll;
    NexusMBOracle[2] internal oracle;
    NexusMBRatifier internal ratifier;
    bytes32 internal id;
    bytes32 internal id2; // otro mercado: el mismo con un día más de vencimiento
    address[7] internal accts;
    uint256[2] internal lltv;
    uint256 internal immutable MATURITY;
    address[2] internal cTok;
    address[2] internal cOra;
    uint256 internal gNonce; // grupos nuevos por oferta (a veces compartidos), para que el consumo no se sature

    /// @param sfPct comisión de liquidación (settlement) por defecto, en % del máximo de cada punto; @param cfPct
    /// comisión continua por defecto, en % del máximo.
    constructor(uint256 sfPct, uint256 cfPct) {
        MATURITY = block.timestamp + 30 days;
        midnight = new Midnight();
        ratifier = new NexusMBRatifier();
        midnight.setFeeSetter(FEE_SETTER);
        midnight.setFeeClaimer(FEE_CLAIMER);
        midnight.setTickSpacingSetter(TICK_SETTER);
        lltv[0] = 0.86e18;
        lltv[1] = 0.945e18;
        midnight.enableLltv(lltv[0]);
        midnight.enableLltv(lltv[1]);
        midnight.enableLiquidationCursor(CURSOR);

        loan = new NexusMBToken("loan", 18);
        NexusMBToken a = new NexusMBToken("collA", 18);
        NexusMBToken b = new NexusMBToken("collB", 18);
        (coll[0], coll[1]) = address(a) < address(b) ? (a, b) : (b, a);
        for (uint256 i; i < NC; ++i) {
            oracle[i] = new NexusMBOracle();
            cTok[i] = address(coll[i]);
            cOra[i] = address(oracle[i]);
        }
        vm.startPrank(FEE_SETTER);
        for (uint256 k; k < 7; ++k) {
            uint256 f = _maxSF(k) * sfPct / 100;
            midnight.setDefaultSettlementFee(address(loan), k, f - f % CBP);
        }
        midnight.setDefaultContinuousFee(address(loan), MAX_CF * cfPct / 100);
        vm.stopPrank();
        id = midnight.touchMarket(_market());
        id2 = midnight.touchMarket(_market2());

        (address blue, address fac, address log) = _periphery();
        bundle = new MidnightBundlesV2(address(midnight), blue, fac, log);

        for (uint256 h; h < NA; ++h) {
            address u = address(uint160(uint256(keccak256(abi.encode("nexus.mb.acct", h)))));
            accts[h] = u;
            if (h >= NH) continue;
            vm.startPrank(u);
            midnight.setIsAuthorized(address(ratifier), true, u);
            midnight.setIsAuthorized(address(bundle), true, u);
            loan.approve(address(midnight), type(uint256).max);
            loan.approve(address(bundle), type(uint256).max);
            for (uint256 i; i < NC; ++i) {
                coll[i].approve(address(midnight), type(uint256).max);
                coll[i].approve(address(bundle), type(uint256).max);
            }
            vm.stopPrank();
        }
    }

    /// @dev Blue, la fábrica de BlueBuyCallback y el log del bundle. Fase 1: stubs, porque las entradas de toma no los
    /// usan; la fase 2 despliega los reales. Corre dentro del constructor, con el núcleo y los tokens ya desplegados.
    function _periphery() internal virtual returns (address blue, address fac, address log) {
        blue = address(uint160(uint256(keccak256("nexus.mb.blue"))));
        fac = address(new NexusMBFactoryStub(address(midnight), blue));
        log = address(uint160(uint256(keccak256("nexus.mb.log"))));
    }

    function _market() internal view returns (Market memory mk) {
        mk.chainId = block.chainid;
        mk.midnight = address(midnight);
        mk.loanToken = address(loan);
        mk.collateralParams = new CollateralParams[](NC);
        for (uint256 i; i < NC; ++i) {
            mk.collateralParams[i] =
                CollateralParams({token: cTok[i], lltv: lltv[i], liquidationCursor: CURSOR, oracle: cOra[i]});
        }
        mk.maturity = MATURITY;
        mk.rcfThreshold = 1e16;
    }

    function _market2() internal view returns (Market memory mk) {
        mk = _market();
        mk.maturity = MATURITY + 1 days;
    }

    /// @dev maxSettlementFee(index), escrito de nuevo.
    function _maxSF(uint256 k) internal pure returns (uint256) {
        if (k <= 1) return 0.000014e18;
        if (k == 2) return 0.000098e18;
        if (k == 3) return 0.000417e18;
        if (k == 4) return 0.00125e18;
        if (k == 5) return 0.0025e18;
        return 0.005e18;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev Pone el colateral `i` que necesita `h` para deber `units` más de lo que ya debe (con 25 % de margen).
    function _collateralize(uint256 h, uint256 i, uint256 units) internal {
        uint256 p = oracle[i].price();
        if (p == 0 || units == 0) return;
        uint256 need = ((units * WAD) / lltv[i] + 1) * PSCALE / p + 1;
        need += need / 4;
        coll[i].mint(accts[h], need);
        vm.prank(accts[h]);
        midnight.supplyCollateral(_market(), i, need, accts[h]);
    }
}

/// @notice Handler y leyes BU-... de MidnightBundlesV2.
contract NexusMidnightBundlesHandler is NexusMBBase {
    uint8 internal constant L_FUNDS = 0;
    uint8 internal constant L_ISO = 1;
    uint8 internal constant L_CONS = 2;
    uint8 internal constant L_FEE = 3;
    uint8 internal constant L_LIMIT = 4;
    uint8 internal constant L_LIVE = 5;
    uint8 internal constant N_LAWS = 6;

    uint256 internal violations;
    uint256 internal lawMask;
    string internal firstViolation;

    // métricas
    uint256 internal hLaws;
    uint256[4] internal hCalls; // por entrada: compra por unidades, venta por unidades, compra por activos, venta por activos
    uint256[4] internal hOk;
    uint256 internal hTakesFilled; // creadores cuya posición cambió en una llamada que pasó
    uint256 internal hRepaid; // llamadas de compra que repagaron deuda
    uint256 internal hWithdrawn; // llamadas de venta que retiraron crédito antes de tomar ofertas
    uint256 internal hFees; // llamadas que pagaron comisión de referido
    uint256[10] internal hRev; // reversiones del bundle por motivo (ver _revKind)
    uint256 internal hDirect; // posiciones directas (sin el bundle) que se abrieron
    uint256 internal hDirectRepay; // repagos directos
    bytes4 internal lastOther; // el último motivo de reversión sin clasificar
    uint256 internal lastPanic; // el código del último pánico

    struct Acct {
        uint256 loan;
        uint256 c0;
        uint256 c1;
        uint256 credit;
        uint256 debt;
        uint256 m0;
        uint256 m1;
    }

    struct Snap {
        Acct[7] a;
        uint256 bLoan;
        uint256 bC0;
        uint256 bC1;
        uint256 midLoan;
        uint256 withdrawable;
        uint256 ext; // activo prestado de Blue y los BlueBuyCallback (fase 2; 0 en la fase 1)
        uint256[] extState; // estado propio de la fase 2 (posiciones de los callbacks en Blue)
    }

    /// @dev Lo que eligió el fuzzer para una llamada.
    struct P {
        uint256 u; // quien llama
        uint256 target;
        uint256 bound; // maxBuyerAssets, minSellerAssets, minUnits o maxUnits
        bool reduceOnly;
        bool repay;
        uint256 pct;
        uint256 ref; // I_REF o I_REF + 1
        uint256 dest; // quien recibe: el colateral en las compras, el activo en las ventas (u o I_RECV)
        uint256 deadline;
        bool[4] maker;
        bool badFirst; // la primera oferta es del lado equivocado o de otro mercado
        uint256 maxCF; // maxContinuousFee de las compras
        bool mustRevert; // calculado por la entrada: llega a una oferta mala o la comisión continua supera maxCF
    }

    constructor(uint256 sfPct, uint256 cfPct) NexusMBBase(sfPct, cfPct) {}

    /* LAS CUATRO ENTRADAS DE QUIEN TOMA OFERTAS */

    function buyUnits(uint256 userSeed, uint256 offersSeed, uint256 paramsSeed, uint256 collSeed) external {
        P memory p = _params(userSeed, paramsSeed);
        p.target = _target(paramsSeed, midnight.debt(id, accts[p.u]));
        p.bound = _h(collSeed, 1) % 4 == 0 ? _amt(collSeed, 70, AMT) : 4 * AMT; // maxBuyerAssets
        OfferFill[] memory f = _fills(p, true, offersSeed);
        CollateralTransfer[] memory cw = _withdrawals(p.u, collSeed);
        loan.mint(accts[p.u], p.bound);
        Snap memory pre = _snap();
        uint256 tgt = p.target == type(uint256).max ? pre.a[p.u].debt : p.target;
        // sin ofertas, la llamada no toca ninguna y no controla lado, mercado ni comisión continua (repago directo)
        p.mustRevert = tgt > 0 && f.length > 0 && (p.badFirst || midnight.continuousFee(id) > p.maxCF);
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(bundle).call(
            abi.encodeCall(
                bundle.midnightBundlesV2BuyWithUnitsTargetAndWithdrawCollateral,
                (_market(), p.target, p.bound, p.reduceOnly, p.repay, f, cw, accts[p.dest], p.pct, accts[p.ref],
                    p.maxCF, p.deadline, address(0))
            )
        );
        if (!_after(0, ok, ret, p, pre)) return;
        Snap memory post = _snap();
        int256 filled = _filled(p, pre, post); // lo que el bundle pagó a los vendedores y a Midnight
        int256 fee = _dl(pre, post, p.ref);
        int256 paid = -_dl(pre, post, p.u);
        int256 expFee = filled > 0 ? int256(uint256(filled) * p.pct / (WAD - p.pct)) : int256(0);
        _okI(filled >= 0, L_FUNDS, "compra por unidades: el bundle cobro de los vendedores en vez de pagarles (llenado, 0)", filled, 0);
        _okI(fee == expFee, L_FEE, "compra por unidades: comision de referido distinta de filledBuyerAssets*pct/(WAD-pct) (esperada, real)", expFee, fee);
        _okI(paid == filled + fee, L_FUNDS, "compra por unidades: el usuario no pago lo llenado mas la comision (pago, llenado + comision)", paid, filled + fee);
        _okI(paid <= int256(p.bound), L_LIMIT, "compra por unidades: el usuario pago mas que maxBuyerAssets (pago, maximo)", paid, int256(p.bound));
        int256 target = int256(p.target == type(uint256).max ? pre.a[p.u].debt : p.target);
        _okI(_du(pre, post, p.u) == target, L_LIMIT, "compra por unidades: las unidades del usuario no subieron en targetUnits (objetivo, cambio)", target, _du(pre, post, p.u));
        if (p.reduceOnly) {
            _ok(post.a[p.u].credit == pre.a[p.u].credit, L_LIMIT, "compra reduceOnly: el usuario termino con mas credito (antes, despues)", pre.a[p.u].credit, post.a[p.u].credit);
        }
        _withdrawLaws(p, pre, post, cw);
        if (fee > 0) ++hFees;
    }

    function sellUnits(uint256 userSeed, uint256 offersSeed, uint256 paramsSeed, uint256 collSeed) external {
        P memory p = _params(userSeed, paramsSeed);
        (uint128 c0,,) = midnight.updatePositionView(_market(), id, accts[p.u]);
        p.target = _target(paramsSeed, c0);
        p.bound = _h(collSeed, 1) % 4 == 0 ? _amt(collSeed, 70, AMT) - 1 : 0; // minSellerAssets
        OfferFill[] memory f = _fills(p, false, offersSeed);
        CollateralTransfer[] memory cs = _supplies(p.u, collSeed);
        Snap memory pre = _snap();
        uint256 tgt = p.target == type(uint256).max ? pre.a[p.u].credit : p.target;
        p.mustRevert = p.badFirst && _min(_min(tgt, pre.a[p.u].credit), pre.withdrawable) < tgt;
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(bundle).call(
            abi.encodeCall(
                bundle.midnightBundlesV2SupplyCollateralAndSellWithUnitsTarget,
                (_market(), p.target, p.bound, p.reduceOnly, accts[p.dest], cs, f, p.pct, accts[p.ref], p.deadline,
                    address(0))
            )
        );
        if (!_after(1, ok, ret, p, pre)) return;
        Snap memory post = _snap();
        int256 filled = -_filled(p, pre, post); // lo que entró al bundle desde los compradores y Midnight
        int256 fee = _dl(pre, post, p.ref);
        int256 got = _dl(pre, post, p.dest);
        int256 expFee = filled > 0 ? int256(uint256(filled) * p.pct / WAD) : int256(0);
        _okI(filled >= 0, L_FUNDS, "venta por unidades: el bundle pago a los compradores en vez de cobrarles (llenado, 0)", filled, 0);
        _okI(fee == expFee, L_FEE, "venta por unidades: comision de referido distinta de filledSellerAssets*pct/WAD (esperada, real)", expFee, fee);
        _okI(got + fee == filled, L_FUNDS, "venta por unidades: lo cobrado mas la comision no es lo llenado (cobrado + comision, llenado)", got + fee, filled);
        _okI(got >= int256(p.bound), L_LIMIT, "venta por unidades: el receptor cobro menos que minSellerAssets (cobrado, minimo)", got, int256(p.bound));
        int256 target = int256(p.target == type(uint256).max ? pre.a[p.u].credit : p.target);
        _okI(_du(pre, post, p.u) == -target, L_LIMIT, "venta por unidades: las unidades del usuario no bajaron en targetUnits (objetivo, cambio)", -target, _du(pre, post, p.u));
        if (p.reduceOnly) {
            _ok(post.a[p.u].debt == pre.a[p.u].debt, L_LIMIT, "venta reduceOnly: el usuario termino con mas deuda (antes, despues)", pre.a[p.u].debt, post.a[p.u].debt);
        }
        _supplyLaws(p, pre, post, cs);
        if (fee > 0) ++hFees;
    }

    function buyAssets(uint256 userSeed, uint256 offersSeed, uint256 paramsSeed, uint256 collSeed) external {
        P memory p = _params(userSeed, paramsSeed);
        p.target = _amt(paramsSeed, 72, AMT); // targetBuyerAssets
        p.bound = _h(collSeed, 1) % 4 == 0 ? _amt(collSeed, 70, AMT) - 1 : 0; // minUnits
        OfferFill[] memory f = _fills(p, true, offersSeed);
        CollateralTransfer[] memory cw = _withdrawals(p.u, collSeed);
        loan.mint(accts[p.u], p.target);
        Snap memory pre = _snap();
        uint256 tf = p.pct < WAD ? p.target - p.target * p.pct / WAD : 0;
        p.mustRevert = tf > 0 && f.length > 0 && (p.badFirst || midnight.continuousFee(id) > p.maxCF);
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(bundle).call(
            abi.encodeCall(
                bundle.midnightBundlesV2BuyWithAssetsTargetAndWithdrawCollateral,
                (_market(), p.target, p.bound, p.reduceOnly, p.repay, f, cw, accts[p.dest], p.pct, accts[p.ref],
                    p.maxCF, p.deadline, address(0))
            )
        );
        if (!_after(2, ok, ret, p, pre)) return;
        Snap memory post = _snap();
        int256 filled = _filled(p, pre, post);
        int256 fee = _dl(pre, post, p.ref);
        int256 paid = -_dl(pre, post, p.u);
        int256 expFee = int256(p.target * p.pct / WAD);
        _okI(paid == int256(p.target), L_LIMIT, "compra por activos: el usuario no pago exactamente targetBuyerAssets (pago, objetivo)", paid, int256(p.target));
        _okI(fee == expFee, L_FEE, "compra por activos: comision de referido distinta de target*pct/WAD (esperada, real)", expFee, fee);
        _okI(filled == int256(p.target) - expFee, L_FUNDS, "compra por activos: lo llenado no es el objetivo menos la comision (esperado, llenado)", int256(p.target) - expFee, filled);
        _okI(_du(pre, post, p.u) >= int256(p.bound), L_LIMIT, "compra por activos: el usuario gano menos que minUnits (minimo, cambio)", int256(p.bound), _du(pre, post, p.u));
        if (p.reduceOnly) {
            _ok(post.a[p.u].credit == pre.a[p.u].credit, L_LIMIT, "compra reduceOnly: el usuario termino con mas credito (antes, despues)", pre.a[p.u].credit, post.a[p.u].credit);
        }
        _withdrawLaws(p, pre, post, cw);
        if (fee > 0) ++hFees;
    }

    function sellAssets(uint256 userSeed, uint256 offersSeed, uint256 paramsSeed, uint256 collSeed) external {
        P memory p = _params(userSeed, paramsSeed);
        p.target = _amt(paramsSeed, 72, AMT); // targetSellerAssets
        p.bound = _h(collSeed, 1) % 4 == 0 ? _amt(collSeed, 70, AMT) - 1 : type(uint256).max; // maxUnits
        OfferFill[] memory f = _fills(p, false, offersSeed);
        CollateralTransfer[] memory cs = _supplies(p.u, collSeed);
        Snap memory pre = _snap();
        uint256 tf = p.pct < WAD ? p.target + p.target * p.pct / (WAD - p.pct) : 0;
        p.mustRevert = p.badFirst && _min(_min(tf, pre.a[p.u].credit), pre.withdrawable) < tf;
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(bundle).call(
            abi.encodeCall(
                bundle.midnightBundlesV2SupplyCollateralAndSellWithAssetsTarget,
                (_market(), p.target, p.bound, p.reduceOnly, accts[p.dest], cs, f, p.pct, accts[p.ref], p.deadline,
                    address(0))
            )
        );
        if (!_after(3, ok, ret, p, pre)) return;
        Snap memory post = _snap();
        int256 filled = -_filled(p, pre, post);
        int256 fee = _dl(pre, post, p.ref);
        int256 got = _dl(pre, post, p.dest);
        int256 expFee = int256(p.target * p.pct / (WAD - p.pct));
        _okI(got == int256(p.target), L_LIMIT, "venta por activos: el receptor no cobro exactamente targetSellerAssets (cobrado, objetivo)", got, int256(p.target));
        _okI(fee == expFee, L_FEE, "venta por activos: comision de referido distinta de target*pct/(WAD-pct) (esperada, real)", expFee, fee);
        _okI(filled == int256(p.target) + expFee, L_FUNDS, "venta por activos: lo llenado no es el objetivo mas la comision (esperado, llenado)", int256(p.target) + expFee, filled);
        uint256 maxU = _min(p.bound, uint256(type(int256).max));
        _okI(-_du(pre, post, p.u) <= int256(maxU), L_LIMIT, "venta por activos: el usuario perdio mas que maxUnits (maximo, perdida)", int256(maxU), -_du(pre, post, p.u));
        if (p.reduceOnly) {
            _ok(post.a[p.u].debt == pre.a[p.u].debt, L_LIMIT, "venta reduceOnly: el usuario termino con mas deuda (antes, despues)", pre.a[p.u].debt, post.a[p.u].debt);
        }
        _supplyLaws(p, pre, post, cs);
        if (fee > 0) ++hFees;
    }

    /* ESTADO ENTRE LLAMADAS */

    /// @dev Posiciones directas entre dos actores (sin el bundle): quien vende queda con deuda o pierde crédito, quien
    /// compra gana crédito o paga deuda. Así hay deuda para repagar y crédito para vender.
    function position(uint256 seed, uint256 unitsSeed) external {
        uint256 s = _h(seed, 4);
        uint256 seller = s % NH;
        uint256 buyer = (seller + 1 + (s >> 8) % (NH - 1)) % NH;
        uint256 units = _amt(unitsSeed, 74, AMT);
        _collateralize(seller, (s >> 16) % NC, units);
        loan.mint(accts[buyer], 2 * units + 1);
        Offer memory o;
        o.market = _market();
        o.buy = true; // el creador (buyer) compra; el que toma (seller) vende
        o.maker = accts[buyer];
        o.expiry = type(uint256).max;
        o.tick = _tick(s >> 24, true);
        o.group = keccak256(abi.encode("nexus.mb.direct", buyer, ++gNonce));
        o.ratifier = address(ratifier);
        o.maxUnits = uint128(units);
        o.continuousFeeCap = type(uint256).max;
        vm.prank(accts[seller]);
        (bool ok,) = address(midnight).call(
            abi.encodeCall(midnight.take, (o, "", units, accts[seller], accts[seller], address(0), ""))
        );
        if (ok) ++hDirect;
    }

    /// @dev Un punto de precio accesible: la mitad de las veces cerca de 1 (tasas realistas), la otra mitad en
    /// cualquier lugar. Salvo 1 de cada 16 veces, tomable: en una oferta de venta el precio del comprador (precio más
    /// comisión de liquidación) no pasa de 1, y en una de compra el precio no es menor que la comisión. Con una oferta
    /// no tomable, TakeAmountsLib revierte (lo documenta) y el bundle la llama fuera del try: revierte la llamada
    /// entera en vez de saltear la oferta. Es un borde conocido de vivacidad; generarlas siempre gastaría llamadas.
    function _tick(uint256 s, bool buy) internal view returns (uint256) {
        uint256 sp = midnight.tickSpacing(id);
        uint256 t = s % 2 == 0 ? MAX_TICK - (s >> 1) % 600 : (s >> 1) % (MAX_TICK + 1);
        t -= t % sp;
        if ((s >> 160) % 16 == 0) return t;
        uint256 fee = midnight.settlementFee(id, MATURITY > block.timestamp ? MATURITY - block.timestamp : 0);
        if (_takeable(t, fee, buy)) return t;
        // el borde entre t y el precio 1/2 (tomable de los dos lados), por bisección: tomable es monótono en el punto
        uint256 half = (MAX_TICK / 2) / sp; // en pasos de sp
        uint256 a = t / sp < half ? t / sp : half;
        uint256 b = t / sp < half ? half : t / sp;
        while (a + 1 < b) {
            uint256 m = (a + b) / 2;
            bool ok = _takeable(m * sp, fee, buy);
            if (buy == ok) b = m;
            else a = m;
        }
        return (buy ? b : a) * sp;
    }

    function _takeable(uint256 t, uint256 fee, bool buy) internal pure returns (bool) {
        uint256 price = TickLib.tickToPrice(t);
        return buy ? price > fee : price + fee <= WAD;
    }

    /// @dev Un deudor repaga directo en Midnight (sin el bundle): deja liquidez retirable para las ventas.
    function repayDirect(uint256 seed, uint256 amt) external {
        uint256 h = _h(seed, 7) % NH;
        uint256 d = midnight.debt(id, accts[h]);
        if (d == 0) return;
        uint256 r = _amt(amt, 76, d);
        loan.mint(accts[h], r);
        vm.prank(accts[h]);
        midnight.repay(_market(), r, accts[h], address(0), "");
        ++hDirectRepay;
    }

    function warp(uint256 secs) external {
        uint256 t = block.timestamp + 1 + secs % 2 days;
        if (t >= MATURITY) t = block.timestamp + 1; // la fase 1 se queda antes del vencimiento
        vm.warp(t);
    }

    function setPrice(uint256 i, uint256 seed) external {
        uint256 base = PSCALE;
        oracle[i % NC].setPrice(base / 2 + seed % (2 * base));
    }

    /* PIEZAS */

    /// @dev Las decisiones (banderas, ramas) salen de un hash de la semilla: con semillas chicas, que el fuzzer da a
    /// menudo, los bits altos son cero y caerían siempre en la misma rama. Los montos salen de la semilla cruda, para
    /// que el fuzzer pueda apuntar a valores exactos de su diccionario.
    function _h(uint256 seed, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, salt)));
    }

    /// @dev targetUnits: type(uint256).max (toda la deuda o todo el crédito), una parte de lo que hay, o cualquiera.
    function _target(uint256 seed, uint256 have) internal pure returns (uint256) {
        uint256 k = _h(seed, 1) % 8;
        if (k < 2) return type(uint256).max;
        if (k == 2 && have > 0) return _amt(seed, 78, have);
        return _amt(seed, 80, AMT);
    }

    /// @dev Un monto en [1, max]: 1 de cada 4 veces el valor crudo (el diccionario del fuzzer apunta a valores
    /// exactos: saldos, posiciones, constantes), las demás uniforme. Con dictionary_weight = 80 (lo de forge para
    /// invariantes), casi todos los montos crudos salían del diccionario y quedaban chicos.
    function _amt(uint256 seed, uint256 salt, uint256 max) internal pure returns (uint256) {
        return _h(seed, salt) % 4 == 0 ? 1 + seed % max : 1 + _h(seed, salt + 1) % max;
    }

    function _params(uint256 userSeed, uint256 seed) internal view returns (P memory p) {
        uint256 s = _h(seed, 2);
        p.u = userSeed % NH;
        p.reduceOnly = (s >> 90) % 8 == 0;
        p.repay = (s >> 93) % 2 == 0;
        uint256 k = (s >> 96) % 8;
        // comisión de referido: 0, polvo, valores comunes y extremos (hasta WAD − 1; WAD tiene que revertir)
        p.pct = k < 3 ? 0 : (k == 3 ? 1 : (k == 4 ? 0.003e18 : (k == 5 ? 0.5e18 : (k == 6 ? WAD - 1 : WAD))));
        p.ref = I_REF + (s >> 100) % 2;
        p.dest = (s >> 101) % 2 == 0 ? p.u : I_RECV;
        p.deadline = (s >> 102) % 32 == 0 ? block.timestamp - 1 : block.timestamp;
        p.maxCF = (s >> 110) % 16 == 0 ? 0 : type(uint256).max;
    }

    /// @dev Entre 1 y 4 ofertas de los otros actores, del lado que corresponde (si quien llama compra, ofertas de
    /// venta). Algunas vencidas (el núcleo las rechaza y el bundle las saltea), con reduceOnly o con topes.
    function _fills(P memory p, bool takerBuys, uint256 seed) internal virtual returns (OfferFill[] memory f) {
        // sin ofertas 1 de cada 8 veces: repago o retiro directos (documentado: con targetUnits = type(uint256).max y
        // sin ofertas, la compra por unidades repaga toda la deuda)
        uint256 hn = _h(seed, 6);
        uint256 n = hn % 8 == 0 ? 0 : 1 + (hn >> 3) % 4;
        uint256 bad = _h(seed, 5) % 32; // 0: la primera oferta es del lado equivocado; 1: es de otro mercado
        p.badFirst = bad < 2 && n > 0;
        f = new OfferFill[](n);
        for (uint256 k; k < n; ++k) {
            uint256 s = uint256(keccak256(abi.encode(seed, k)));
            uint256 m = (p.u + 1 + s % (NH - 1)) % NH;
            p.maker[m] = true;
            Offer memory o;
            o.market = k == 0 && bad == 1 ? _market2() : _market();
            o.buy = k == 0 && bad == 0 ? takerBuys : !takerBuys;
            o.maker = accts[m];
            o.expiry = (s >> 8) % 16 == 0 ? block.timestamp - 1 : type(uint256).max;
            o.tick = _tick(s >> 16, o.buy);
            o.group = keccak256(abi.encode("nexus.mb.group", m, (s >> 56) % 4 == 0 ? gNonce : ++gNonce));
            o.receiverIfMakerIsSeller = o.buy ? address(0) : accts[m];
            o.ratifier = address(ratifier);
            o.reduceOnly = (s >> 32) % 8 == 0;
            uint128 cap = (s >> 40) % 3 == 0 ? uint128(M128) : uint128(1 + (s >> 48) % AMT);
            if ((s >> 120) % 2 == 0) o.maxUnits = cap;
            else o.maxAssets = cap;
            o.continuousFeeCap = type(uint256).max;
            f[k].offer = o;
            f[k].units = (s >> 128) % 4 == 0 ? type(uint256).max : 1 + (s >> 136) % AMT;
            if (o.buy) loan.mint(accts[m], 2 * AMT); // el creador compra: paga él
            else _collateralize(m, (s >> 200) % NC, 2 * AMT); // el creador vende: puede quedar con deuda
        }
    }

    /// @dev 0 a 2 retiros de colateral del usuario: una parte o todo (type(uint256).max).
    function _withdrawals(uint256 u, uint256 seed) internal view returns (CollateralTransfer[] memory cw) {
        uint256 n = _h(seed, 3) % 3;
        cw = new CollateralTransfer[](n);
        for (uint256 k; k < n; ++k) {
            uint256 s = uint256(keccak256(abi.encode(seed, "cw", k)));
            uint256 i = s % NC;
            uint256 have = midnight.collateral(id, accts[u], i);
            cw[k].collateralIndex = i;
            cw[k].assets = (s >> 8) % 4 == 0 ? type(uint256).max : (have == 0 ? 0 : (s >> 16) % (have / 2 + 1));
        }
    }

    /// @dev 0 a 2 aportes de colateral del usuario (se acuñan antes): lo que haga falta para vender algo de deuda.
    function _supplies(uint256 u, uint256 seed) internal returns (CollateralTransfer[] memory cs) {
        uint256 n = _h(seed, 3) % 3;
        cs = new CollateralTransfer[](n);
        for (uint256 k; k < n; ++k) {
            uint256 s = uint256(keccak256(abi.encode(seed, "cs", k)));
            cs[k].collateralIndex = s % NC;
            cs[k].assets = 1 + (s >> 8) % (3 * AMT);
            coll[cs[k].collateralIndex].mint(accts[u], cs[k].assets);
        }
    }

    function _snap() internal view returns (Snap memory s) {
        Market memory mk = _market();
        for (uint256 h; h < NA; ++h) {
            address w = accts[h];
            s.a[h].loan = loan.balanceOf(w);
            s.a[h].c0 = coll[0].balanceOf(w);
            s.a[h].c1 = coll[1].balanceOf(w);
            (uint128 c,,) = midnight.updatePositionView(mk, id, w);
            s.a[h].credit = c;
            s.a[h].debt = midnight.debt(id, w);
            s.a[h].m0 = midnight.collateral(id, w, 0);
            s.a[h].m1 = midnight.collateral(id, w, 1);
        }
        s.bLoan = loan.balanceOf(address(bundle));
        s.bC0 = coll[0].balanceOf(address(bundle));
        s.bC1 = coll[1].balanceOf(address(bundle));
        s.midLoan = loan.balanceOf(address(midnight));
        s.withdrawable = midnight.withdrawable(id);
        s.ext = _extLoan();
        s.extState = _extState();
    }

    /// @dev Fase 2: el activo prestado que tienen Blue y los BlueBuyCallback.
    function _extLoan() internal view virtual returns (uint256) {
        return 0;
    }

    /// @dev Fase 2: estado propio para sus leyes (posiciones de los callbacks en Blue y sus saldos).
    function _extState() internal view virtual returns (uint256[] memory) {}

    /// @dev Fase 2: leyes propias después de una llamada de toma que pasó.
    function _extLaws(uint256 kind, P memory p, Snap memory pre, Snap memory post) internal virtual {}

    /// @dev Lo común a toda llamada: BU-LIVE, y si pasó, BU-FUNDS (el bundle sin saldo), BU-ISO y BU-CONS. Devuelve
    /// si siguen las leyes propias de la entrada (no, si revirtió o si pasó cuando tenía que revertir).
    function _after(uint256 kind, bool ok, bytes memory ret, P memory p, Snap memory pre) internal returns (bool) {
        ++hCalls[kind];
        bool mustRevert = p.mustRevert || p.deadline < block.timestamp || p.pct >= WAD;
        _ok(!(ok && mustRevert), L_LIVE, "paso con el plazo vencido, comision de referido >= WAD, una oferta del lado o del mercado equivocado o comision continua sobre el maximo (entrada, comision)", kind, p.pct);
        if (!ok) {
            uint256 rk = _revKind(ret);
            ++hRev[rk];
            if (rk == 7 && ret.length >= 4) lastOther = bytes4(ret);
            if (rk == 6 && ret.length >= 36) lastPanic = uint256(bytes32(_slice4(ret)));
            _ok(rk != 5 || mustRevert, L_LIVE, "revirtio por una validacion (plazo, comision, lado, mercado o comision continua) que no correspondia (entrada, motivo)", kind, rk);
            return false;
        }
        if (mustRevert) return false;
        ++hOk[kind];
        Snap memory post = _snap();
        _ok(post.bLoan == 0 && post.bC0 == 0 && post.bC1 == 0, L_FUNDS, "el bundle quedo con saldo (activo, colateral 0)", post.bLoan, post.bC0);
        for (uint256 h; h < NA; ++h) {
            if (_involved(p, h)) continue;
            Acct memory a = pre.a[h];
            Acct memory b = post.a[h];
            bool same = a.loan == b.loan && a.c0 == b.c0 && a.c1 == b.c1 && a.credit == b.credit && a.debt == b.debt
                && a.m0 == b.m0 && a.m1 == b.m1;
            _ok(same, L_ISO, "cambio la posicion o el saldo de alguien ajeno a la llamada (cuenta, entrada)", h, kind);
        }
        int256 sum;
        for (uint256 h; h < NH; ++h) {
            if (h != p.u && !p.maker[h]) continue;
            int256 d = _du(pre, post, h);
            sum += d;
            if (h != p.u && d != 0) ++hTakesFilled;
        }
        int256 dw = int256(post.withdrawable) - int256(pre.withdrawable);
        _okI(sum == dw, L_CONS, "las unidades no se conservan: lo que cambio entre usuario y creadores no es lo que cambio withdrawable (suma, withdrawable)", sum, dw);
        if (dw > 0) ++hRepaid;
        if (dw < 0) ++hWithdrawn;
        _extLaws(kind, p, pre, post);
        return true;
    }

    /// @dev Clase del motivo de una reversión del bundle: 0 OutOfOffers, 1 UnitsTooLow, 2 UnitsTooHigh,
    /// 3 SellerAssetsTooLow, 4 NotReduceOnly, 5 validaciones (DeadlinePassed, PctExceeded, InconsistentSide,
    /// InconsistentMarket, ContinuousFeeAboveMax), 6 pánico (aritmética: en TakeAmountsLib, una oferta de compra con
    /// precio menor que la comisión), 7 otro, 8 PriceGreaterThanOne (TakeAmountsLib: oferta de venta no tomable),
    /// 9 sin datos (una oferta de compra tocada con un callback sin código: buyerAssetsBound revierte fuera del try).
    function _revKind(bytes memory ret) internal pure returns (uint256) {
        if (ret.length == 0) return 9;
        if (ret.length < 4) return 7;
        bytes4 s = bytes4(ret);
        if (s == IMidnightBundlesV2.OutOfOffers.selector) return 0;
        if (s == IMidnightBundlesV2.UnitsTooLow.selector) return 1;
        if (s == IMidnightBundlesV2.UnitsTooHigh.selector) return 2;
        if (s == IMidnightBundlesV2.SellerAssetsTooLow.selector) return 3;
        if (s == IMidnightBundlesV2.NotReduceOnly.selector) return 4;
        if (
            s == IMidnightBundlesV2.DeadlinePassed.selector || s == IMidnightBundlesV2.PctExceeded.selector
                || s == IMidnightBundlesV2.InconsistentSide.selector || s == IMidnightBundlesV2.InconsistentMarket.selector
                || s == IMidnightBundlesV2.ContinuousFeeAboveMax.selector
        ) return 5;
        if (s == bytes4(0x4e487b71)) return 6;
        if (s == TickLib.PriceGreaterThanOne.selector) return 8;
        return 7;
    }

    /// @dev ret sin el selector (los 32 bytes del código de pánico).
    function _slice4(bytes memory ret) internal pure returns (bytes memory out) {
        out = new bytes(ret.length - 4);
        for (uint256 i; i < out.length; ++i) {
            out[i] = ret[i + 4];
        }
    }

    function _involved(P memory p, uint256 h) internal pure returns (bool) {
        return h == p.u || (h < NH && p.maker[h]) || h == p.ref || h == p.dest;
    }

    /// @dev Variación de las unidades (crédito − deuda) de `h`.
    function _du(Snap memory pre, Snap memory post, uint256 h) internal pure returns (int256) {
        return (int256(post.a[h].credit) - int256(post.a[h].debt)) - (int256(pre.a[h].credit) - int256(pre.a[h].debt));
    }

    /// @dev Activo que entró a los creadores de las ofertas y a Midnight: lo que el bundle pagó por lo llenado (en una
    /// venta, con signo negativo: lo que el bundle recibió).
    function _filled(P memory p, Snap memory pre, Snap memory post) internal pure returns (int256 s) {
        for (uint256 h; h < NH; ++h) {
            if (!p.maker[h] || h == p.u) continue;
            s += int256(post.a[h].loan) - int256(pre.a[h].loan);
        }
        s += int256(post.midLoan) - int256(pre.midLoan);
        s += int256(post.ext) - int256(pre.ext);
    }

    /// @dev Variación del saldo de activo prestado de `h`.
    function _dl(Snap memory pre, Snap memory post, uint256 h) internal pure returns (int256) {
        return int256(post.a[h].loan) - int256(pre.a[h].loan);
    }

    /// @dev Los retiros de colateral: el receptor recibe exactamente lo pedido (todo, con type(uint256).max) y sale de
    /// la posición del usuario.
    function _withdrawLaws(P memory p, Snap memory pre, Snap memory post, CollateralTransfer[] memory cw) internal {
        uint256[2] memory left = [pre.a[p.u].m0, pre.a[p.u].m1];
        uint256[2] memory out;
        for (uint256 k; k < cw.length; ++k) {
            uint256 i = cw[k].collateralIndex;
            uint256 a = cw[k].assets == type(uint256).max ? left[i] : cw[k].assets;
            left[i] -= a;
            out[i] += a;
        }
        _ok(post.a[p.u].m0 == left[0] && post.a[p.u].m1 == left[1], L_LIMIT, "retiro de colateral: la posicion del usuario no bajo en lo pedido (esperado, real)", left[0], post.a[p.u].m0);
        uint256 g0 = post.a[p.dest].c0 - pre.a[p.dest].c0;
        uint256 g1 = post.a[p.dest].c1 - pre.a[p.dest].c1;
        _ok(g0 == out[0] && g1 == out[1], L_LIMIT, "retiro de colateral: el receptor no recibio lo pedido (esperado, recibido)", out[0], g0);
    }

    /// @dev Los aportes de colateral: salen del usuario y entran a su posición, exactos.
    function _supplyLaws(P memory p, Snap memory pre, Snap memory post, CollateralTransfer[] memory cs) internal {
        uint256[2] memory in_;
        for (uint256 k; k < cs.length; ++k) {
            in_[cs[k].collateralIndex] += cs[k].assets;
        }
        _ok(post.a[p.u].m0 == pre.a[p.u].m0 + in_[0] && post.a[p.u].m1 == pre.a[p.u].m1 + in_[1], L_LIMIT, "aporte de colateral: la posicion del usuario no subio en lo aportado (esperado, real)", pre.a[p.u].m0 + in_[0], post.a[p.u].m0);
        bool paidC = pre.a[p.u].c0 - post.a[p.u].c0 == in_[0] && pre.a[p.u].c1 - post.a[p.u].c1 == in_[1];
        _ok(paidC, L_LIMIT, "aporte de colateral: el usuario no pago exactamente lo aportado (aportado 0, 0)", in_[0], 0);
    }

    /* REGISTRO */

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
                firstViolation =
                    string(abi.encodePacked(_lawName(law), ": ", what, ": ", vm.toString(x), ", ", vm.toString(y)));
            }
        }
    }

    function _lawName(uint8 law) internal pure returns (string memory) {
        if (law == L_FUNDS) return "BU-FUNDS";
        if (law == L_ISO) return "BU-ISO";
        if (law == L_CONS) return "BU-CONS";
        if (law == L_FEE) return "BU-FEE";
        if (law == L_LIMIT) return "BU-LIMIT";
        return "BU-LIVE";
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
        returns (uint256 laws, uint256[4] memory calls, uint256[4] memory oks, uint256 takes, uint256 repaid,
            uint256 withdrawn, uint256 fees)
    {
        return (hLaws, hCalls, hOk, hTakesFilled, hRepaid, hWithdrawn, hFees);
    }

    function revertCounts() external view returns (uint256[10] memory, uint256, uint256, bytes4, uint256) {
        return (hRev, hDirect, hDirectRepay, lastOther, lastPanic);
    }
}

contract NexusMidnightBundlesTest is Test {
    NexusMidnightBundlesHandler internal handler;

    function setUp() public virtual {
        handler = new NexusMidnightBundlesHandler(_sf(), _cf());
        bytes4[] memory sels = new bytes4[](8);
        sels[0] = handler.buyUnits.selector;
        sels[1] = handler.sellUnits.selector;
        sels[2] = handler.buyAssets.selector;
        sels[3] = handler.sellAssets.selector;
        sels[4] = handler.position.selector;
        sels[5] = handler.warp.selector;
        sels[6] = handler.setPrice.selector;
        sels[7] = handler.repayDirect.selector;
        // solo las acciones del handler: sin failed() ni los demás públicos que hereda de Test
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: sels}));
        targetContract(address(handler));
    }

    function _sf() internal pure virtual returns (uint256) {
        return 50;
    }

    function _cf() internal pure virtual returns (uint256) {
        return 0;
    }

    /// @dev require y no assertEq: el motivo ("... [leyes: ...]") es lo que lee tools/forge_v2 para atribuir mutaciones.
    function invariant_midnightBundles() public view {
        string memory err = handler.check();
        require(bytes(err).length == 0, err);
    }

    function afterInvariant() public {
        (uint256 laws, uint256[4] memory calls, uint256[4] memory oks, uint256 takes, uint256 repaid,
            uint256 withdrawn, uint256 fees) = handler.coverage();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cobertura: compras por unidades que pasaron", oks[0]);
        emit log_named_uint("cobertura: ventas por unidades que pasaron", oks[1]);
        emit log_named_uint("cobertura: compras por activos que pasaron", oks[2]);
        emit log_named_uint("cobertura: ventas por activos que pasaron", oks[3]);
        emit log_named_uint("cobertura: llamadas al bundle", calls[0] + calls[1] + calls[2] + calls[3]);
        emit log_named_uint("cobertura: creadores cuya posicion cambio", takes);
        emit log_named_uint("cobertura: llamadas con repago", repaid);
        emit log_named_uint("cobertura: llamadas con retiro de credito", withdrawn);
        emit log_named_uint("cobertura: llamadas con comision de referido", fees);
        (uint256[10] memory r, uint256 direct, uint256 directRepay, bytes4 other, uint256 panic) =
            handler.revertCounts();
        emit log_named_uint("cobertura: posiciones directas abiertas", direct);
        emit log_named_uint("cobertura: repagos directos", directRepay);
        emit log_named_uint("reversiones: OutOfOffers", r[0]);
        emit log_named_uint("reversiones: UnitsTooLow", r[1]);
        emit log_named_uint("reversiones: UnitsTooHigh", r[2]);
        emit log_named_uint("reversiones: SellerAssetsTooLow", r[3]);
        emit log_named_uint("reversiones: NotReduceOnly", r[4]);
        emit log_named_uint("reversiones: validaciones (plazo, comision, lado, mercado, comision continua)", r[5]);
        emit log_named_uint("reversiones: panico aritmetico", r[6]);
        emit log_named_uint("reversiones: codigo del ultimo panico", panic);
        emit log_named_uint("reversiones: oferta de venta no tomable (PriceGreaterThanOne)", r[8]);
        emit log_named_uint("reversiones: sin datos (callback sin codigo)", r[9]);
        emit log_named_uint("reversiones: otras", r[7]);
        emit log_named_bytes32("reversiones: ultimo motivo sin clasificar", bytes32(other));
    }
}

/// @dev Comisiones al máximo: la de liquidación en cada punto y la continua.
contract NexusMidnightBundlesFeesTest is NexusMidnightBundlesTest {
    function _sf() internal pure override returns (uint256) {
        return 100;
    }

    function _cf() internal pure override returns (uint256) {
        return 100;
    }
}
