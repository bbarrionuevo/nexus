// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.34;

// Cazador de VaultBundlesV1 y VaultExitBundlesV1 (morpho-org/bundles; lo desplegado son las etiquetas 2026-08-07 a
// 2026-08-24, igual en lógica a 2ed954e). Variante VB1: con Vault V2 (0.8.28, por deployCode) con un solo adapter, el
// MorphoMarketV1AdapterV2 sobre Morpho Blue real con la IRM adaptativa (0.8.19). Entradas: depositar, retirar y migrar
// (VaultBundlesV1), y la redención en especie y el retiro forzado de Vault V2 (VaultExitBundlesV1). Leyes exactas en
// cada llamada que pasa:
//   VB-FUNDS  el bundle no se queda con activo ni con acciones; lo que paga y cobra el usuario es exactamente lo
//             documentado;
//   VB-FEE    la comisión de referido es exactamente la documentada;
//   VB-SHARES las acciones del usuario cambian exactamente como dicen las vistas del vault (o, en la redención en
//             especie y en el retiro forzado, a lo sumo lo que vale exitAssets + N, como documenta el bundle);
//   VB-KIND   en la redención en especie, el usuario recibe exactamente lo ocioso que le toca y en cada mercado la
//             posición en Blue que deja el adapter, con el redondeo de Blue;
//   VB-ISO    nadie más cambia;
//   VB-LIVE   con el plazo vencido, pct >= WAD o assets y shares los dos distintos de cero (o los dos cero),
//             revierte; con el control de precio pedido, el precio final lo respeta; y al revés, no revierte por una
//             de esas validaciones cuando no corresponde (el precio pedido es justo el que realiza la llamada).
// Los vaults reconocen interés y donaciones (tasa máxima de 200 % anual), así que el precio por acción no es redondo.

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IVaultV2} from "../../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "../../lib/vault-v2/src/interfaces/IVaultV2Factory.sol";
import {IMorphoMarketV1AdapterV2} from "../../lib/vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {
    IMorphoMarketV1AdapterV2Factory
} from "../../lib/vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {IMorpho, MarketParams, Id, Position, Market} from "../../lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../lib/metamorpho/lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {MorphoBalancesLib} from "../../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {VaultBundlesV1} from "../../src/vault/VaultBundlesV1.sol";
import {VaultExitBundlesV1} from "../../src/vault-exit/VaultExitBundlesV1.sol";
import {IVaultBundlesV1} from "../../src/vault/interfaces/IVaultBundlesV1.sol";
import {IVaultExitBundlesV1} from "../../src/vault-exit/interfaces/IVaultExitBundlesV1.sol";
import {TokenPermit, PermitKind, Permit} from "../../src/libraries/TokenLib.sol";

contract NexusVBToken {
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

contract NexusVBOracle {
    uint256 public price = 1e36;

    function setPrice(uint256 p) external {
        price = p;
    }
}

contract NexusVaultBundlesHandler is Test {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using MorphoBalancesLib for IMorpho;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant NH = 4; // usuarios
    uint256 internal constant NA = 6; // los 4 usuarios y 2 referidos
    uint256 internal constant I_REF = 4;
    uint256 internal constant NM = 2; // mercados del adapter
    uint256 internal constant AMT = 1e24;
    uint256 internal constant FD_PENALTY = 0.005e18; // la de partida; el curator la cambia (setPenalty)
    uint256 internal constant MAX_PENALTY = 0.02e18; // MAX_FORCE_DEALLOCATE_PENALTY de Vault V2
    // la tasa máxima de Vault V2 (200 % anual): sin ella (0 por defecto) el vault no reconoce interés ni donaciones y
    // el precio por acción queda clavado en 1, con lo que ningún redondeo de las vistas se ejercita
    uint256 internal constant MAX_RATE = 200e16 / uint256(365 days);

    address internal constant BLUE_OWNER = address(uint160(uint256(keccak256("nexus.vb.blueOwner"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("nexus.vb.owner"))));
    address internal constant CURATOR = address(uint160(uint256(keccak256("nexus.vb.curator"))));
    address internal constant ALLOCATOR = address(uint160(uint256(keccak256("nexus.vb.allocator"))));
    address internal constant SEEDER = address(uint160(uint256(keccak256("nexus.vb.seeder"))));
    address internal constant BORROWER = address(uint160(uint256(keccak256("nexus.vb.borrower"))));
    address internal constant FEE_RECIPIENT = address(uint160(uint256(keccak256("nexus.vb.feeRecipient"))));

    uint8 internal constant L_FUNDS = 0;
    uint8 internal constant L_FEE = 1;
    uint8 internal constant L_SHARES = 2;
    uint8 internal constant L_KIND = 3;
    uint8 internal constant L_ISO = 4;
    uint8 internal constant L_LIVE = 5;
    uint8 internal constant N_LAWS = 6;

    IMorpho internal blue;
    address internal irm;
    NexusVBToken internal token;
    NexusVBToken[2] internal colls;
    NexusVBOracle internal oracle;
    MarketParams[3] internal mps; // 0 y 1 del adapter; 2, un mercado ajeno al vault
    IVaultV2 internal v1; // con el adapter sobre Blue y penalidad de retiro forzado
    IVaultV2 internal v2; // sin adapters: solo ocioso (destino y origen de migraciones)
    IMorphoMarketV1AdapterV2 internal adapter;
    VaultBundlesV1 internal vb;
    VaultExitBundlesV1 internal vx;
    address[6] internal accts;

    uint256 internal violations;
    uint256 internal lawMask;
    string internal firstViolation;
    uint256 internal hLaws;
    uint256[5] internal hCalls; // depositar, retirar, migrar, en especie, forzado
    uint256[5] internal hOk;
    uint256 internal hInKindMarkets; // mercados entregados en especie
    uint256 internal hDeallocated; // retiros forzados que desasignaron de Blue
    uint256 internal hFees;
    // reversiones: 0 deslizamiento, 1 plazo o pct, 2 exactamente uno, 3 Vault V2 o Blue (liquidez, etc.), 4 pánico
    // aritmético, 5 otro pánico (división por cero o índice fuera de la lista), 6 sin datos
    uint256[7] internal hRev;

    struct Acct {
        uint256 tok;
        uint256 s1;
        uint256 s2;
        uint256[3] blueShares;
    }

    struct Snap {
        Acct[6] a;
        uint256 bTok;
        uint256 bS1;
        uint256 bS2;
        uint256 xTok;
        uint256 xS1;
        uint256 xS2;
    }

    struct P {
        uint256 u;
        uint256 pct;
        uint256 ref;
        uint256 deadline;
    }

    constructor() {
        blue = IMorpho(deployCode("Morpho.sol", abi.encode(BLUE_OWNER)));
        irm = deployCode("AdaptiveCurveIrm.sol", abi.encode(address(blue)));
        vm.startPrank(BLUE_OWNER);
        blue.enableIrm(irm);
        blue.enableLltv(0.86e18);
        blue.enableLltv(0.945e18);
        vm.stopPrank();
        token = new NexusVBToken("asset");
        colls[0] = new NexusVBToken("collA");
        colls[1] = new NexusVBToken("collB");
        oracle = new NexusVBOracle();
        mps[0] = MarketParams(address(token), address(colls[0]), address(oracle), irm, 0.86e18);
        mps[1] = MarketParams(address(token), address(colls[1]), address(oracle), irm, 0.945e18);
        mps[2] = MarketParams(address(token), address(colls[1]), address(oracle), irm, 0.86e18);
        vm.startPrank(SEEDER);
        token.approve(address(blue), type(uint256).max);
        for (uint256 i; i < 3; ++i) {
            blue.createMarket(mps[i]);
            token.mint(SEEDER, 10 * AMT);
            blue.supply(mps[i], 10 * AMT, 0, SEEDER, "");
        }
        vm.stopPrank();

        IVaultV2Factory factory = IVaultV2Factory(deployCode("VaultV2Factory.sol"));
        v1 = IVaultV2(factory.createVaultV2(OWNER, address(token), bytes32(uint256(1))));
        v2 = IVaultV2(factory.createVaultV2(OWNER, address(token), bytes32(uint256(2))));
        IMorphoMarketV1AdapterV2Factory af =
            IMorphoMarketV1AdapterV2Factory(deployCode("MorphoMarketV1AdapterV2Factory.sol", abi.encode(address(blue), irm)));
        adapter = IMorphoMarketV1AdapterV2(af.createMorphoMarketV1AdapterV2(address(v1)));
        for (uint256 k; k < 2; ++k) {
            IVaultV2 v = k == 0 ? v1 : v2;
            vm.startPrank(OWNER);
            v.setCurator(CURATOR);
            vm.stopPrank();
            _curated(v, abi.encodeCall(IVaultV2.setIsAllocator, (ALLOCATOR, true)));
            // comisiones del vault (10 % del rendimiento y 2 % anual de gestión) a una cuenta que no es de los actores:
            // las acciones de comisión entran en el primer devengamiento de cada transacción
            _curated(v, abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (FEE_RECIPIENT)));
            _curated(v, abi.encodeCall(IVaultV2.setManagementFeeRecipient, (FEE_RECIPIENT)));
            _curated(v, abi.encodeCall(IVaultV2.setPerformanceFee, (0.1e18)));
            _curated(v, abi.encodeCall(IVaultV2.setManagementFee, (0.02e18 / uint256(365 days))));
        }
        _curated(v1, abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        _capAll(abi.encode("this", address(adapter)));
        for (uint256 i; i < NM; ++i) {
            _capAll(abi.encode("collateralToken", address(colls[i])));
            _capAll(abi.encode("this/marketParams", address(adapter), mps[i]));
        }
        _curated(v1, abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), FD_PENALTY)));
        vm.startPrank(ALLOCATOR);
        v1.setLiquidityAdapterAndData(address(adapter), abi.encode(mps[0]));
        v1.setMaxRate(MAX_RATE);
        v2.setMaxRate(MAX_RATE);
        vm.stopPrank();

        vb = new VaultBundlesV1();
        vx = new VaultExitBundlesV1(address(blue));
        for (uint256 h; h < NA; ++h) {
            address u = address(uint160(uint256(keccak256(abi.encode("nexus.vb.acct", h)))));
            accts[h] = u;
            if (h >= NH) continue;
            vm.startPrank(u);
            token.approve(address(v1), type(uint256).max);
            token.approve(address(v2), type(uint256).max);
            token.approve(address(vb), type(uint256).max);
            v1.approve(address(vb), type(uint256).max);
            v2.approve(address(vb), type(uint256).max);
            v1.approve(address(vx), type(uint256).max);
            v2.approve(address(vx), type(uint256).max);
            vm.stopPrank();
            // posiciones iniciales en los dos vaults
            token.mint(u, 2 * AMT);
            vm.startPrank(u);
            v1.deposit(AMT, u);
            v2.deposit(AMT, u);
            vm.stopPrank();
        }
        // parte del vault con adapter, del mercado de liquidez al otro mercado
        vm.startPrank(ALLOCATOR);
        v1.deallocate(address(adapter), abi.encode(mps[0]), 2 * AMT);
        v1.allocate(address(adapter), abi.encode(mps[1]), AMT);
        vm.stopPrank();
    }

    function _capAll(bytes memory idData) internal {
        _curated(v1, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        _curated(v1, abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, WAD)));
    }

    function _curated(IVaultV2 v, bytes memory data) internal {
        vm.prank(CURATOR);
        v.submit(data);
        (bool ok,) = address(v).call(data);
        require(ok, "nexus: gobierno del setUp");
    }

    /* VAULTBUNDLESV1 */

    function deposit(uint256 userSeed, uint256 seed, uint256 aSeed) external {
        P memory p = _params(userSeed, seed);
        IVaultV2 v = _h(seed, 50) % 2 == 0 ? v1 : v2;
        uint256 a = _amt(aSeed, 51, AMT);
        token.mint(accts[p.u], a);
        uint256 fee = p.pct < WAD ? a * p.pct / WAD : 0;
        uint256 expShares = v.previewDeposit(a - fee);
        uint256 maxPrice = _maxPrice(seed, a - fee, expShares);
        bool slip = expShares > 0 && maxPrice < _mulDivUp(a - fee, 1e27, expShares);
        Snap memory pre = _snap();
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(vb).call(
            abi.encodeCall(vb.vaultBundlesV1Deposit, (address(v), a, maxPrice, _noTokenPermit(), p.pct, accts[p.ref], p.deadline))
        );
        if (!_after(0, ok, ret, p, pre, false, slip)) return;
        Snap memory post = _snap();
        _okI(_dt(pre, post, p.ref) == int256(fee), L_FEE, "Deposit: comision distinta de assets*pct/WAD (esperada, real)", int256(fee), _dt(pre, post, p.ref));
        _okI(_dt(pre, post, p.u) == -int256(a), L_FUNDS, "Deposit: el usuario no pago exactamente assets (esperado, pagado)", -int256(a), _dt(pre, post, p.u));
        _okI(_ds(pre, post, p.u, v) == int256(expShares), L_SHARES, "Deposit: las acciones del usuario no subieron como previewDeposit (esperado, real)", int256(expShares), _ds(pre, post, p.u, v));
        if (expShares > 0) {
            _ok(_mulDivUp(a - fee, 1e27, expShares) <= maxPrice, L_LIVE, "Deposit: paso con un precio por accion mayor que maxSharePriceE27 (precio, maximo)", _mulDivUp(a - fee, 1e27, expShares), maxPrice);
        }
        if (fee > 0) ++hFees;
    }

    function withdraw(uint256 userSeed, uint256 seed, uint256 aSeed) external {
        P memory p = _params(userSeed, seed);
        IVaultV2 v = _h(seed, 52) % 2 == 0 ? v1 : v2;
        (uint256 a, uint256 s, bool bad) = _assetsOrShares(v, accts[p.u], aSeed);
        uint256 out = a > 0 ? a : v.previewRedeem(s);
        uint256 burn = a > 0 ? v.previewWithdraw(a) : s;
        uint256 fee = p.pct < WAD ? out * p.pct / WAD : 0;
        Snap memory pre = _snap();
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(vb).call(
            abi.encodeCall(vb.vaultBundlesV1Withdraw, (address(v), a, s, _noPermit(), p.pct, accts[p.ref], p.deadline))
        );
        if (!_after(1, ok, ret, p, pre, bad, false)) return;
        Snap memory post = _snap();
        _okI(_dt(pre, post, p.ref) == int256(fee), L_FEE, "Withdraw: comision distinta de withdrawn*pct/WAD (esperada, real)", int256(fee), _dt(pre, post, p.ref));
        _okI(_dt(pre, post, p.u) == int256(out - fee), L_FUNDS, "Withdraw: el usuario no recibio lo retirado menos la comision (esperado, recibido)", int256(out - fee), _dt(pre, post, p.u));
        _okI(_ds(pre, post, p.u, v) == -int256(burn), L_SHARES, "Withdraw: las acciones del usuario no bajaron como previewWithdraw o lo pedido (esperado, real)", -int256(burn), _ds(pre, post, p.u, v));
        if (fee > 0) ++hFees;
    }

    function migrate(uint256 userSeed, uint256 seed, uint256 aSeed) external {
        P memory p = _params(userSeed, seed);
        bool fromV1 = _h(seed, 53) % 2 == 0;
        IVaultV2 src = fromV1 ? v1 : v2;
        IVaultV2 dst = fromV1 ? v2 : v1;
        (uint256 a, uint256 s, bool bad) = _assetsOrShares(src, accts[p.u], aSeed);
        uint256 out = a > 0 ? a : src.previewRedeem(s);
        uint256 burn = a > 0 ? src.previewWithdraw(a) : s;
        uint256 fee = p.pct < WAD ? out * p.pct / WAD : 0;
        uint256 minted = dst.previewDeposit(out - fee);
        uint256 maxPrice = _maxPrice(seed, out - fee, minted);
        bool slip = minted > 0 && maxPrice < _mulDivUp(out - fee, 1e27, minted);
        Snap memory pre = _snap();
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(vb).call(
            abi.encodeCall(
                vb.vaultBundlesV1Migrate,
                (address(src), address(dst), a, s, maxPrice, _noPermit(), p.pct, accts[p.ref], p.deadline)
            )
        );
        if (!_after(2, ok, ret, p, pre, bad, slip)) return;
        Snap memory post = _snap();
        _okI(_dt(pre, post, p.ref) == int256(fee), L_FEE, "Migrate: comision distinta de withdrawn*pct/WAD (esperada, real)", int256(fee), _dt(pre, post, p.ref));
        _okI(_dt(pre, post, p.u), L_FUNDS, "Migrate: cambio el saldo de activo del usuario (cambio, 0)", _dt(pre, post, p.u), 0);
        _okI(_ds(pre, post, p.u, src) == -int256(burn), L_SHARES, "Migrate: las acciones de origen no bajaron como previewWithdraw o lo pedido (esperado, real)", -int256(burn), _ds(pre, post, p.u, src));
        _okI(_ds(pre, post, p.u, dst) == int256(minted), L_SHARES, "Migrate: las acciones de destino no subieron como previewDeposit (esperado, real)", int256(minted), _ds(pre, post, p.u, dst));
        if (minted > 0) {
            _ok(_mulDivUp(out - fee, 1e27, minted) <= maxPrice, L_LIVE, "Migrate: paso con un precio por accion de destino mayor que el maximo (precio, maximo)", _mulDivUp(out - fee, 1e27, minted), maxPrice);
        }
        if (fee > 0) ++hFees;
    }

    /* VAULTEXITBUNDLESV1, VAULT V2 */

    struct Kind {
        uint256 exit;
        uint256 fromIdle;
        uint256 toDealloc;
        uint256 n; // mercados con algo en especie
        uint8[3] order;
        uint256[3] amount;
        uint256[3] tsa;
        uint256[3] tss;
        uint256 len;
        bool shortList; // la lista no alcanza: el bundle se sale de la lista y revierte
    }

    function inKind(uint256 userSeed, uint256 seed, uint256 eSeed) external {
        P memory p = _params(userSeed, seed);
        if (_h(seed, 63) % 2 == 0) _sinLiquidez(_h(seed, 64));
        Kind memory k;
        uint256 have = v1.previewRedeem(v1.balanceOf(accts[p.u]));
        k.exit = _h(eSeed, 54) % 8 == 0 ? _amt(eSeed, 55, AMT) : _amt(eSeed, 56, have / 2 + 1);
        k.fromIdle = _min(token.balanceOf(address(v1)), k.exit);
        k.toDealloc = (k.exit - k.fromIdle) * WAD / (WAD + v1.forceDeallocatePenalty(address(adapter)));
        // la lista: los dos mercados del adapter en algún orden, a veces con el ajeno en el medio o sin uno
        uint256 s = _h(seed, 57);
        k.len = 1 + s % 3;
        uint8 first = uint8((s >> 4) % 2);
        k.order = [first, (s >> 8) % 4 == 0 ? 2 : 1 - first, (s >> 8) % 4 == 0 ? 1 - first : 2];
        MarketParams[] memory list = new MarketParams[](k.len);
        uint256 rem = k.toDealloc;
        for (uint256 i; i < k.len; ++i) {
            list[i] = mps[k.order[i]];
            (k.tsa[i], k.tss[i],,) = blue.expectedMarketBalances(mps[k.order[i]]);
            if (rem == 0) continue;
            uint256 a = k.order[i] < NM ? adapter.expectedSupplyAssets(Id.unwrap(mps[k.order[i]].id())) : 0;
            a = _min(a, rem);
            rem -= a;
            k.amount[i] = a;
            if (a > 0) ++k.n;
        }
        k.shortList = rem > 0;
        Snap memory pre = _snap();
        uint256 maxBurn = v1.previewWithdraw(k.exit + k.n) + 2 * k.n + 1;
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(vx).call(
            abi.encodeCall(
                vx.vaultExitBundlesV1InKindRedemptionVaultV2,
                (address(v1), address(adapter), list, k.exit, _noPermit(), p.deadline)
            )
        );
        P memory q = P(p.u, 0, p.ref, p.deadline); // sin comisión de referido (y una copia: `q = p` copiaría la referencia)
        if (!_after(3, ok, ret, q, pre, false, false)) return;
        _ok(!k.shortList, L_LIVE, "InKindV2: paso aunque la lista no alcanzaba para lo que habia que desasignar (falta, 0)", rem, 0);
        Snap memory post = _snap();
        _okI(_dt(pre, post, p.u) == int256(k.fromIdle), L_KIND, "InKindV2: el usuario no recibio exactamente lo ocioso que le tocaba (esperado, recibido)", int256(k.fromIdle), _dt(pre, post, p.u));
        for (uint256 i; i < k.len; ++i) {
            uint256 m = k.order[i];
            uint256 sh = k.amount[i] == 0 ? 0 : k.amount[i].toSharesDown(k.tsa[i], k.tss[i]);
            int256 got = int256(post.a[p.u].blueShares[m]) - int256(pre.a[p.u].blueShares[m]);
            _okI(got == int256(sh), L_KIND, "InKindV2: la posicion en Blue del usuario no subio como redondea Blue (esperado, real)", int256(sh), got);
            if (sh > 0) ++hInKindMarkets;
        }
        int256 burned = -_ds(pre, post, p.u, v1);
        _ok(burned >= 0 && uint256(burned) <= maxBurn, L_SHARES, "InKindV2: se quemaron mas acciones que las de exitAssets + N (quemadas, maximo)", burned >= 0 ? uint256(burned) : 0, maxBurn);
    }

    function forceWithdraw(uint256 userSeed, uint256 seed, uint256 eSeed) external {
        P memory p = _params(userSeed, seed);
        if (_h(seed, 65) % 2 == 0) _sinLiquidez(_h(seed, 66));
        uint256 have = v1.previewRedeem(v1.balanceOf(accts[p.u]));
        uint256 exit = _h(eSeed, 58) % 8 == 0 ? _amt(eSeed, 59, AMT) : _amt(eSeed, 60, have / 2 + 1);
        // lo que el vault paga sin penalidad: lo ocioso más lo que el adapter de liquidez puede sacar del mercado 0
        uint256 withdrawable = token.balanceOf(address(v1));
        (uint256 tsa, uint256 tss, uint256 tba,) = blue.expectedMarketBalances(mps[0]);
        uint256 liq = adapter.supplyShares(Id.unwrap(mps[0].id())).toAssetsDown(tsa, tss);
        withdrawable += _min(liq, tsa - tba);
        uint256 toWithdraw = _min(exit, withdrawable);
        uint256 toDealloc = (exit - toWithdraw) * WAD / (WAD + v1.forceDeallocatePenalty(address(adapter)));
        uint256 withdrawn = toWithdraw + toDealloc;
        uint256 fee = p.pct < WAD ? withdrawn * p.pct / WAD : 0;
        (uint256 minPrice, bool slip) = _minPrice(seed, p, exit);
        // a lo sumo N + 2 retiros (lo que se paga sin penalidad, la penalidad de cada mercado y lo desasignado) que
        // suman a lo sumo exitAssets + N, como documenta el bundle; el precio por acción no baja entre uno y otro
        uint256 maxBurn = v1.previewWithdraw(exit + NM) + NM + 2;
        Snap memory pre = _snap();
        vm.prank(accts[p.u]);
        (bool ok, bytes memory ret) = address(vx).call(
            abi.encodeCall(
                vx.vaultExitBundlesV1ForceWithdrawVaultV2,
                (address(v1), address(adapter), exit, minPrice, _noPermit(), p.pct, accts[p.ref], p.deadline)
            )
        );
        if (!_after(4, ok, ret, p, pre, false, slip)) return;
        Snap memory post = _snap();
        _okI(_dt(pre, post, p.ref) == int256(fee), L_FEE, "ForceWithdrawV2: comision distinta de withdrawn*pct/WAD (esperada, real)", int256(fee), _dt(pre, post, p.ref));
        _okI(_dt(pre, post, p.u) == int256(withdrawn - fee), L_FUNDS, "ForceWithdrawV2: el usuario no recibio lo retirado menos la comision (esperado, recibido)", int256(withdrawn - fee), _dt(pre, post, p.u));
        int256 burned = -_ds(pre, post, p.u, v1);
        _ok(burned >= 0 && uint256(burned) <= maxBurn, L_SHARES, "ForceWithdrawV2: se quemaron mas acciones que las de exitAssets + N (quemadas, maximo)", burned >= 0 ? uint256(burned) : 0, maxBurn);
        if (burned > 0) {
            _ok(withdrawn * 1e27 / uint256(burned) >= minPrice, L_LIVE, "ForceWithdrawV2: paso con un precio de salida menor que minSharePriceE27 (precio, minimo)", withdrawn * 1e27 / uint256(burned), minPrice);
        }
        if (toDealloc > 0) ++hDeallocated;
        if (fee > 0) ++hFees;
    }

    error NexusDryRun(uint256 withdrawn, uint256 burned);

    /// @dev minSharePriceE27 del retiro forzado: sin control, 0,999, el precio que realiza la misma salida (tiene que
    /// pasar) o uno más (tiene que revertir). El precio realizado sale de una corrida en seco que se revierte.
    function _minPrice(uint256 seed, P memory p, uint256 exit) internal returns (uint256 minPrice, bool slip) {
        uint256 k = _h(seed, 61) % 4;
        if (k == 0) return (0, false);
        try this.dryForce(p.u, exit, p.pct, accts[p.ref], p.deadline) {}
        catch (bytes memory r) {
            if (r.length != 68 || bytes4(r) != NexusDryRun.selector) return (k == 1 ? 0.999e27 : 0, false);
            uint256 burned = _word(r, 36);
            if (burned == 0) return (k == 1 ? 0.999e27 : 0, false); // sin acciones quemadas el bundle no controla
            uint256 realized = _word(r, 4) * 1e27 / burned;
            minPrice = k == 1 ? 0.999e27 : (k == 2 ? realized : realized + 1);
            slip = realized < minPrice;
        }
    }

    /// @dev Corrida en seco del retiro forzado, sin control de precio: revierte siempre, con lo retirado y las
    /// acciones quemadas si la salida pasa, o con el motivo si no.
    function dryForce(uint256 u, uint256 exit, uint256 pct, address ref, uint256 deadline) external {
        require(msg.sender == address(this), "nexus: solo el handler");
        address w = accts[u];
        uint256 shares = v1.balanceOf(w);
        uint256 got = token.balanceOf(w) + token.balanceOf(ref);
        vm.prank(w);
        vx.vaultExitBundlesV1ForceWithdrawVaultV2(address(v1), address(adapter), exit, 0, _noPermit(), pct, ref, deadline);
        revert NexusDryRun(token.balanceOf(w) + token.balanceOf(ref) - got, shares - v1.balanceOf(w));
    }

    /// @dev Escenario previo a las salidas de VaultExitBundlesV1: el allocator saca la liquidez sin penalidad (lo
    /// ocioso y, a veces, casi todo el mercado de liquidez) y la pone en el mercado 1. Así la salida tiene que
    /// desasignar con penalidad o entregar en especie; sin esto, lo ocioso alcanzaba casi siempre.
    function _sinLiquidez(uint256 s) internal {
        vm.startPrank(ALLOCATOR);
        uint256 pos0 = adapter.expectedSupplyAssets(Id.unwrap(mps[0].id()));
        if (pos0 > 1 && s % 2 == 0) {
            (bool ok,) = address(v1).call(
                abi.encodeCall(IVaultV2.deallocate, (address(adapter), abi.encode(mps[0]), pos0 - 1))
            );
            ok;
        }
        uint256 idle = token.balanceOf(address(v1));
        if (idle > 0) {
            (bool ok,) = address(v1).call(abi.encodeCall(IVaultV2.allocate, (address(adapter), abi.encode(mps[1]), idle)));
            ok;
        }
        vm.stopPrank();
    }

    /* ENTRE LLAMADAS */

    /// @dev El allocator mueve el vault entre ocioso y los dos mercados.
    function reallocate(uint256 seed, uint256 aSeed) external {
        uint256 s = _h(seed, 70);
        uint256 m = s % NM;
        vm.startPrank(ALLOCATOR);
        if ((s >> 4) % 2 == 0) {
            uint256 idle = token.balanceOf(address(v1));
            if (idle > 0) {
                (bool ok,) = address(v1).call(
                    abi.encodeCall(IVaultV2.allocate, (address(adapter), abi.encode(mps[m]), _amt(aSeed, 71, idle)))
                );
                ok;
            }
        } else {
            uint256 pos = adapter.expectedSupplyAssets(Id.unwrap(mps[m].id()));
            if (pos > 0) {
                (bool ok,) = address(v1).call(
                    abi.encodeCall(IVaultV2.deallocate, (address(adapter), abi.encode(mps[m]), _amt(aSeed, 72, pos)))
                );
                ok;
            }
        }
        vm.stopPrank();
    }

    /// @dev Un prestatario pide prestado en un mercado (menos liquidez para salir sin penalidad) o repaga.
    function borrow(uint256 seed, uint256 aSeed) external {
        uint256 s = _h(seed, 73);
        uint256 m = s % 3;
        (uint256 tsa,, uint256 tba,) = blue.expectedMarketBalances(mps[m]);
        vm.startPrank(BORROWER);
        if ((s >> 4) % 3 != 0 && tsa > tba) {
            uint256 a = _amt(aSeed, 74, (tsa - tba) / 2 + 1);
            uint256 c = a * 2;
            NexusVBToken ct = m == 0 ? colls[0] : colls[1];
            ct.mint(BORROWER, c);
            ct.approve(address(blue), type(uint256).max);
            blue.supplyCollateral(mps[m], c, BORROWER, "");
            (bool ok,) = address(blue).call(abi.encodeCall(blue.borrow, (mps[m], a, 0, BORROWER, BORROWER)));
            ok;
        } else {
            uint256 sh = blue.position(mps[m].id(), BORROWER).borrowShares;
            if (sh > 0) {
                token.mint(BORROWER, 2 * AMT + 1);
                token.approve(address(blue), type(uint256).max);
                (bool ok,) = address(blue).call(abi.encodeCall(blue.repay, (mps[m], 0, sh, BORROWER, "")));
                ok;
            }
        }
        vm.stopPrank();
    }

    /// @dev Un usuario deposita directo en un vault (más acciones para retirar).
    function depositDirect(uint256 userSeed, uint256 seed, uint256 aSeed) external {
        uint256 u = userSeed % NH;
        IVaultV2 v = _h(seed, 75) % 2 == 0 ? v1 : v2;
        uint256 a = _amt(aSeed, 76, AMT);
        token.mint(accts[u], a);
        vm.prank(accts[u]);
        v.deposit(a, accts[u]);
    }

    /// @dev El curator cambia la penalidad del retiro forzado: sin penalidad, la de partida o la máxima.
    function setPenalty(uint256 seed) external {
        uint256 k = _h(seed, 84) % 3;
        uint256 pen = k == 0 ? 0 : (k == 1 ? FD_PENALTY : MAX_PENALTY);
        _curated(v1, abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), pen)));
    }

    /// @dev Alguien dona activo a un vault: el vault lo reconoce con el tiempo, a lo sumo a la tasa máxima, y el precio
    /// por acción deja de ser redondo.
    function donate(uint256 seed, uint256 aSeed) external {
        IVaultV2 v = _h(seed, 82) % 2 == 0 ? v1 : v2;
        token.mint(address(v), _amt(aSeed, 83, AMT / 2));
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + 1 + secs % 3 days);
    }

    /* PIEZAS */

    function _h(uint256 seed, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, salt)));
    }

    function _amt(uint256 seed, uint256 salt, uint256 max) internal pure returns (uint256) {
        return _h(seed, salt) % 4 == 0 ? 1 + seed % max : 1 + _h(seed, salt + 1) % max;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    /// @dev La palabra de 32 bytes de r que empieza en off.
    function _word(bytes memory r, uint256 off) internal pure returns (uint256 x) {
        for (uint256 i; i < 32; ++i) {
            x = (x << 8) | uint8(r[off + i]);
        }
    }

    function _params(uint256 userSeed, uint256 seed) internal view returns (P memory p) {
        uint256 s = _h(seed, 40);
        p.u = userSeed % NH;
        uint256 k = (s >> 8) % 8;
        p.pct = k < 3 ? 0 : (k == 3 ? 1 : (k == 4 ? 0.003e18 : (k == 5 ? 0.5e18 : (k == 6 ? WAD - 1 : WAD))));
        p.ref = I_REF + (s >> 16) % 2;
        p.deadline = (s >> 24) % 32 == 0 ? block.timestamp - 1 : block.timestamp;
    }

    /// @dev Exactamente uno de los dos (por activos o por acciones); 1 de cada 16 los dos o ninguno (tiene que revertir).
    function _assetsOrShares(IVaultV2 v, address u, uint256 seed) internal view returns (uint256 a, uint256 s, bool bad) {
        uint256 sh = v.balanceOf(u);
        uint256 h = _h(seed, 77) % 16;
        if (h == 0) return (0, 0, true);
        if (h == 1) return (1 + seed % AMT, 1 + sh / 2, true);
        if (h % 2 == 0) s = _h(seed, 78) % 4 == 0 ? sh : _amt(seed, 79, sh / 2 + 1);
        else a = _amt(seed, 80, v.previewRedeem(sh) / 2 + 1);
        if (a == 0 && s == 0) bad = true;
    }

    /// @dev maxSharePriceE27: sin control, justo el precio esperado, o uno por debajo (tiene que revertir).
    function _maxPrice(uint256 seed, uint256 assets, uint256 shares) internal pure returns (uint256) {
        uint256 k = _h(seed, 81) % 4;
        if (k < 2 || shares == 0) return type(uint256).max;
        uint256 price = _mulDivUp(assets, 1e27, shares);
        return k == 2 ? price : price - 1;
    }

    function _noTokenPermit() internal pure returns (TokenPermit memory t) {
        t.kind = PermitKind.None;
    }

    function _noPermit() internal pure returns (Permit memory p) {}

    function _snap() internal view returns (Snap memory s) {
        for (uint256 h; h < NA; ++h) {
            address w = accts[h];
            s.a[h].tok = token.balanceOf(w);
            s.a[h].s1 = v1.balanceOf(w);
            s.a[h].s2 = v2.balanceOf(w);
            for (uint256 m; m < 3; ++m) {
                s.a[h].blueShares[m] = blue.position(mps[m].id(), w).supplyShares;
            }
        }
        s.bTok = token.balanceOf(address(vb));
        s.bS1 = v1.balanceOf(address(vb));
        s.bS2 = v2.balanceOf(address(vb));
        s.xTok = token.balanceOf(address(vx));
        s.xS1 = v1.balanceOf(address(vx));
        s.xS2 = v2.balanceOf(address(vx));
    }

    /// @dev VB-LIVE en las dos direcciones (revierte cuando corresponde, y no revierte por una validación del bundle
    /// que no corresponde: plazo, comisión, exactamente uno o deslizamiento con el precio dentro del límite) y, si
    /// pasó, VB-FUNDS (los bundles sin saldo) y VB-ISO. `slip`: el control de precio pedido tiene que fallar.
    function _after(uint256 kind, bool ok, bytes memory ret, P memory p, Snap memory pre, bool bad, bool slip)
        internal
        returns (bool)
    {
        ++hCalls[kind];
        bool late = p.deadline < block.timestamp;
        bool mustRevert = bad || late || p.pct >= WAD;
        _ok(!(ok && mustRevert), L_LIVE, "paso con el plazo vencido, comision >= WAD o sin exactamente uno de assets y shares (entrada, comision)", kind, p.pct);
        if (!ok) {
            uint256 r = _revKind(ret);
            ++hRev[r];
            bool wrong = (r == 0 && !slip) || (r == 1 && !late && p.pct < WAD) || (r == 2 && !bad);
            _ok(!wrong, L_LIVE, "revirtio por una validacion del bundle que no correspondia (entrada, motivo: 0 deslizamiento, 1 plazo o comision, 2 exactamente uno)", kind, r);
            return false;
        }
        if (mustRevert) return false;
        ++hOk[kind];
        Snap memory post = _snap();
        bool clean = post.bTok == 0 && post.bS1 == 0 && post.bS2 == 0 && post.xTok == 0 && post.xS1 == 0 && post.xS2 == 0;
        _ok(clean, L_FUNDS, "un bundle quedo con activo o acciones (activo de VaultBundles, de VaultExitBundles)", post.bTok, post.xTok);
        for (uint256 h; h < NA; ++h) {
            if (h == p.u || h == p.ref) continue;
            Acct memory a = pre.a[h];
            Acct memory b = post.a[h];
            bool same = a.tok == b.tok && a.s1 == b.s1 && a.s2 == b.s2;
            for (uint256 m; m < 3; ++m) {
                same = same && a.blueShares[m] == b.blueShares[m];
            }
            _ok(same, L_ISO, "cambio el saldo, las acciones o la posicion en Blue de alguien ajeno (cuenta, entrada)", h, kind);
        }
        return true;
    }

    function _dt(Snap memory pre, Snap memory post, uint256 h) internal pure returns (int256) {
        return int256(post.a[h].tok) - int256(pre.a[h].tok);
    }

    function _ds(Snap memory pre, Snap memory post, uint256 h, IVaultV2 v) internal view returns (int256) {
        return address(v) == address(v1) ? int256(post.a[h].s1) - int256(pre.a[h].s1) : int256(post.a[h].s2) - int256(pre.a[h].s2);
    }

    function _revKind(bytes memory ret) internal pure returns (uint256) {
        if (ret.length < 4) return 6;
        bytes4 s = bytes4(ret);
        if (s == IVaultBundlesV1.SlippageExceeded.selector) return 0;
        if (s == IVaultBundlesV1.DeadlinePassed.selector || s == IVaultBundlesV1.PctExceeded.selector) return 1;
        if (s == IVaultBundlesV1.NotExactlyOneZero.selector) return 2;
        if (s == bytes4(0x4e487b71)) return ret.length == 36 && _word(ret, 4) == 0x11 ? 4 : 5;
        return 3;
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
        if (law == L_FUNDS) return "VB-FUNDS";
        if (law == L_FEE) return "VB-FEE";
        if (law == L_SHARES) return "VB-SHARES";
        if (law == L_KIND) return "VB-KIND";
        if (law == L_ISO) return "VB-ISO";
        return "VB-LIVE";
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
        returns (uint256, uint256[5] memory, uint256[5] memory, uint256, uint256, uint256, uint256[7] memory)
    {
        return (hLaws, hCalls, hOk, hInKindMarkets, hDeallocated, hFees, hRev);
    }

    /// @dev Lo que vale hoy una acción (1e18 de acciones) de cada vault.
    function prices() external view returns (uint256, uint256) {
        return (v1.previewRedeem(WAD), v2.previewRedeem(WAD));
    }
}

contract NexusVaultBundlesTest is Test {
    NexusVaultBundlesHandler internal handler;

    function setUp() public {
        handler = new NexusVaultBundlesHandler();
        bytes4[] memory sels = new bytes4[](11);
        sels[0] = handler.deposit.selector;
        sels[1] = handler.withdraw.selector;
        sels[2] = handler.migrate.selector;
        sels[3] = handler.inKind.selector;
        sels[4] = handler.forceWithdraw.selector;
        sels[5] = handler.reallocate.selector;
        sels[6] = handler.borrow.selector;
        sels[7] = handler.depositDirect.selector;
        sels[8] = handler.donate.selector;
        sels[9] = handler.setPenalty.selector;
        sels[10] = handler.warp.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: sels}));
        targetContract(address(handler));
    }

    function invariant_vaultBundles() public view {
        string memory err = handler.check();
        require(bytes(err).length == 0, err);
    }

    function afterInvariant() public {
        (uint256 laws, uint256[5] memory calls, uint256[5] memory oks, uint256 kindMarkets, uint256 dealloc,
            uint256 fees, uint256[7] memory r) = handler.coverage();
        (uint256 price1, uint256 price2) = handler.prices();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cobertura: Deposit que pasaron", oks[0]);
        emit log_named_uint("cobertura: Withdraw que pasaron", oks[1]);
        emit log_named_uint("cobertura: Migrate que pasaron", oks[2]);
        emit log_named_uint("cobertura: InKindRedemptionVaultV2 que pasaron", oks[3]);
        emit log_named_uint("cobertura: ForceWithdrawVaultV2 que pasaron", oks[4]);
        emit log_named_uint("cobertura: llamadas a los bundles", calls[0] + calls[1] + calls[2] + calls[3] + calls[4]);
        emit log_named_uint("cobertura: mercados entregados en especie", kindMarkets);
        emit log_named_uint("cobertura: retiros forzados con desasignacion", dealloc);
        emit log_named_uint("cobertura: llamadas con comision de referido", fees);
        emit log_named_uint("cobertura: activo por accion del vault con adapter (1e18 = 1)", price1);
        emit log_named_uint("cobertura: activo por accion del vault ocioso (1e18 = 1)", price2);
        emit log_named_uint("reversiones: deslizamiento", r[0]);
        emit log_named_uint("reversiones: plazo o comision >= WAD", r[1]);
        emit log_named_uint("reversiones: no exactamente uno de assets y shares", r[2]);
        emit log_named_uint("reversiones: Vault V2 o Blue (liquidez, lista, gates)", r[3]);
        emit log_named_uint("reversiones: panico aritmetico", r[4]);
        emit log_named_uint("reversiones: otro panico (division por cero, la lista no alcanza)", r[5]);
        emit log_named_uint("reversiones: sin datos", r[6]);
    }
}
