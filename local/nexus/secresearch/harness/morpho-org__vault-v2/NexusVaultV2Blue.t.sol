// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// Cazador de Vault V2, variante B: VaultV2 + MorphoMarketV1AdapterV2 (el adapter real) sobre Morpho Blue con la IRM
// adaptativa. Dos mercados con colaterales distintos, prestatarios, cambios de precio y liquidaciones con deuda
// incobrable. Leyes del adapter (V-ADP) contra el estado crudo de Blue y del vault (V-TA-1, V-LOSS-1, V-SOLV-1) con los
// activos reales que informa el adapter. El modelo está en docs/CAZADOR_VAULT_V2.md (§4, variante B).
//
// Antes de cada foto el cazador llama a morpho.accrueInterest en los dos mercados: así el estado crudo de Blue es el
// que el adapter calcula con expectedMarketBalances, y realAssets se verifica con una cuenta propia (Blue redondea
// toAssetsDown con 1 activo y 1e6 acciones virtuales). Ninguna ley revierte.

import {Test} from "../../lib/forge-std/src/Test.sol";
import {VaultV2} from "../../src/VaultV2.sol";
import {VaultV2Factory} from "../../src/VaultV2Factory.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {MorphoMarketV1AdapterV2} from "../../src/adapters/MorphoMarketV1AdapterV2.sol";
import {MorphoMarketV1AdapterV2Factory} from "../../src/adapters/MorphoMarketV1AdapterV2Factory.sol";
import {IMorpho, MarketParams, Id, Market, Position} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {OracleMock} from "../../lib/morpho-blue/src/mocks/OracleMock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {NexusV2Math, NexusV2Clock} from "./NexusVaultV2Hunter.sol";

/// @notice Base de la variante B: Morpho Blue, la IRM adaptativa, dos mercados sembrados, VaultV2 y el adapter real.
abstract contract NexusVaultV2BlueBase is Test {
    using MarketParamsLib for MarketParams;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant ORACLE_ONE = 1e36; // precio 1:1 entre tokens de 18 decimales
    uint256 internal constant MAX_ASSETS = 1e24;
    uint256 internal constant SEED = 1e18; // suministro inicial de cada mercado (el adapter lo exige, NatSpec)
    uint256 internal constant ABS_CAP = 1e30;
    uint256 internal constant MAX_MAX_RATE = 200e16 / uint256(365 days);
    uint256 internal constant VIRTUAL_SHARES = 1e6; // de Blue (SharesMathLib)
    uint256 internal constant VIRTUAL_ASSETS = 1;

    address internal constant OWNER = address(uint160(uint256(keccak256("nexus.v2b.owner"))));
    address internal constant CURATOR = address(uint160(uint256(keccak256("nexus.v2b.curator"))));
    address internal constant ALLOCATOR = address(uint160(uint256(keccak256("nexus.v2b.allocator"))));
    address internal constant MORPHO_OWNER = address(uint160(uint256(keccak256("nexus.v2b.morpho-owner"))));
    address internal constant SEEDER = address(uint160(uint256(keccak256("nexus.v2b.seeder"))));
    address internal constant LIQUIDATOR = address(uint160(uint256(keccak256("nexus.v2b.liquidator"))));

    VaultV2 internal vault;
    ERC20Mock internal token;
    IMorpho internal morpho;
    address internal irm;
    MorphoMarketV1AdapterV2 internal adapter;
    MarketParams[2] internal mps;
    OracleMock[2] internal oracles;
    ERC20Mock[2] internal collats;
    bytes32[2] internal marketIds; // ids de Blue
    bytes32[2] internal vaultMarketIds; // ids del vault por mercado: keccak256(abi.encode("this/marketParams", adapter, mp))
    bytes32[2] internal vaultCollatIds; // keccak256(abi.encode("collateralToken", colateral))
    bytes32 internal vaultAdapterId; // keccak256(abi.encode("this", adapter))

    address[] internal actors;
    address[] internal borrowers;
    uint256 internal violations;
    uint256 internal lawMask;
    string internal firstViolation;
    uint256 internal checks;

    constructor(uint256 fee, uint256 mgmtFee) {
        token = new ERC20Mock(18);
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(MORPHO_OWNER)));
        irm = deployCode("AdaptiveCurveIrm.sol", abi.encode(address(morpho)));
        vm.startPrank(MORPHO_OWNER);
        morpho.enableIrm(irm);
        morpho.enableLltv(0.8e18);
        morpho.enableLltv(0.9e18);
        vm.stopPrank();

        for (uint256 i; i < 2; ++i) {
            collats[i] = new ERC20Mock(18);
            oracles[i] = new OracleMock();
            oracles[i].setPrice(ORACLE_ONE);
            mps[i] = MarketParams({
                loanToken: address(token),
                collateralToken: address(collats[i]),
                oracle: address(oracles[i]),
                irm: irm,
                lltv: i == 0 ? 0.8e18 : 0.9e18
            });
            morpho.createMarket(mps[i]);
            marketIds[i] = Id.unwrap(mps[i].id());
            deal(address(token), SEEDER, token.balanceOf(SEEDER) + SEED, true);
            vm.startPrank(SEEDER);
            token.approve(address(morpho), type(uint256).max);
            morpho.supply(mps[i], SEED, 0, SEEDER, hex"");
            vm.stopPrank();
        }

        vault = VaultV2(new VaultV2Factory().createVaultV2(OWNER, address(token), bytes32(0)));
        vm.startPrank(OWNER);
        vault.setCurator(CURATOR);
        vault.setIsSentinel(ALLOCATOR, true);
        vm.stopPrank();
        _curated(abi.encodeCall(IVaultV2.setIsAllocator, (ALLOCATOR, true)));
        adapter = MorphoMarketV1AdapterV2(
            new MorphoMarketV1AdapterV2Factory(address(morpho), irm).createMorphoMarketV1AdapterV2(address(vault))
        );
        _curated(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        _capAll(abi.encode("this", address(adapter)));
        vaultAdapterId = keccak256(abi.encode("this", address(adapter)));
        for (uint256 i; i < 2; ++i) {
            _capAll(abi.encode("collateralToken", address(collats[i])));
            _capAll(abi.encode("this/marketParams", address(adapter), mps[i]));
            vaultCollatIds[i] = keccak256(abi.encode("collateralToken", address(collats[i])));
            vaultMarketIds[i] = keccak256(abi.encode("this/marketParams", address(adapter), mps[i]));
        }

        vm.prank(ALLOCATOR);
        vault.setMaxRate(MAX_MAX_RATE / 2);
        if (fee > 0) {
            _curated(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (address(0xFEE1))));
            _curated(abi.encodeCall(IVaultV2.setPerformanceFee, (fee)));
        }
        if (mgmtFee > 0) {
            _curated(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (address(0xFEE2))));
            _curated(abi.encodeCall(IVaultV2.setManagementFee, (mgmtFee)));
        }

        for (uint256 i; i < 4; ++i) {
            actors.push(address(uint160(uint256(keccak256(abi.encode("nexus.v2b.actor", i))))));
        }
        for (uint256 i; i < 2; ++i) {
            borrowers.push(address(uint160(uint256(keccak256(abi.encode("nexus.v2b.borrower", i))))));
        }
    }

    function _capAll(bytes memory idData) internal {
        _curated(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, ABS_CAP)));
        _curated(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, WAD)));
    }

    function _curated(bytes memory data) internal {
        vm.prank(CURATOR);
        vault.submit(data);
        (bool ok,) = address(vault).call(data);
        require(ok, "nexus: gov setUp");
    }

    function _clamp(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + x % (hi - lo + 1);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

/// @notice Leyes de la variante B. Fotos tras devengar Blue; nunca las vistas con devengamiento del vault.
abstract contract NexusVaultV2BlueHunter is NexusVaultV2BlueBase {
    uint8 internal constant L_TA = 0; // V-TA-1
    uint8 internal constant L_LOSS1 = 1; // V-LOSS-1
    uint8 internal constant L_SOLV = 2; // V-SOLV-1
    uint8 internal constant L_ADP1 = 3; // V-ADP-1 realAssets exacto
    uint8 internal constant L_ADP2 = 4; // V-ADP-2 allocations
    uint8 internal constant L_ADP3 = 5; // V-ADP-3 acciones internas = posición en Blue
    uint8 internal constant L_ADP4 = 6; // V-ADP-4 lista de mercados
    uint8 internal constant L_ADP5 = 7; // V-ADP-5 movimiento exacto en Blue
    uint8 internal constant N_LAWS = 8;

    struct BSnap {
        uint256 ts;
        uint256 TA;
        uint256 T;
        uint256 lu;
        uint256 mr;
        uint256 idle; // saldo del token en el vault
        uint256 real; // adapter.realAssets()
        uint256 vShares;
        uint256[2] shares; // adapter.supplyShares
        uint256[2] blueShares; // morpho.position(id, adapter).supplyShares
        uint256[2] tsa; // totalSupplyAssets de Blue (crudo, ya devengado)
        uint256[2] tss; // totalSupplyShares
        uint256[2] tba; // totalBorrowAssets
        uint256[2] allocM; // vault.allocation por mercado
        uint256[2] allocC; // vault.allocation por colateral
        uint256 allocA; // vault.allocation del adapter
        uint256[2] listed; // 1 si el mercado está en adapter.marketIds
        uint256 listLen;
    }

    NexusV2Clock internal hClock;
    uint256 internal hLaws;
    uint256 internal hLosses; // devengamientos con pérdida realizada (deuda incobrable de Blue)
    uint256 internal hBadDebt; // liquidaciones que dejaron deuda incobrable
    uint256 internal hAllocs;
    uint256 internal hDeallocs;
    uint256 internal hBorrows;
    uint256 internal hMaxRound; // mayor pérdida por redondeo en un allocate o deallocate

    function _hunterInit() internal {
        hClock = new NexusV2Clock();
    }

    /// @dev Materializa el interés de Blue (cualquiera puede llamarlo; en el mismo bloque no cambia nada).
    function _accrueBlue() internal {
        for (uint256 i; i < 2; ++i) {
            morpho.accrueInterest(mps[i]);
        }
    }

    function _snap() internal view returns (BSnap memory s) {
        s.ts = hClock.time();
        s.TA = vault._totalAssets();
        s.T = vault.totalSupply();
        s.lu = vault.lastUpdate();
        s.mr = vault.maxRate();
        s.idle = token.balanceOf(address(vault));
        s.real = adapter.realAssets();
        s.vShares = vault.virtualShares();
        for (uint256 i; i < 2; ++i) {
            s.shares[i] = adapter.supplyShares(marketIds[i]);
            s.blueShares[i] = morpho.position(Id.wrap(marketIds[i]), address(adapter)).supplyShares;
            Market memory m = morpho.market(Id.wrap(marketIds[i]));
            s.tsa[i] = m.totalSupplyAssets;
            s.tss[i] = m.totalSupplyShares;
            s.tba[i] = m.totalBorrowAssets;
            s.allocM[i] = vault.allocation(vaultMarketIds[i]);
            s.allocC[i] = vault.allocation(vaultCollatIds[i]);
        }
        s.allocA = vault.allocation(vaultAdapterId);
        s.listLen = adapter.marketIdsLength();
        for (uint256 j; j < s.listLen; ++j) {
            bytes32 id = adapter.marketIds(j);
            for (uint256 i; i < 2; ++i) {
                if (id == marketIds[i]) ++s.listed[i];
            }
        }
    }

    /// @dev Valor de `shares` acciones de suministro de Blue: ⌊shares·(tsa+1)/(tss+1e6)⌋ (toAssetsDown).
    function _value(uint256 shares, uint256 tsa, uint256 tss) internal pure returns (uint256) {
        return NexusV2Math.mulDivDown(shares, tsa + VIRTUAL_ASSETS, tss + VIRTUAL_SHARES);
    }

    /// @dev Lo que el adapter tiene que informar por mercado: el valor de sus acciones internas, si el mercado está en la
    /// lista (realAssets ignora los mercados que salieron de la lista).
    function _expectedReal(BSnap memory s) internal pure returns (uint256 r) {
        for (uint256 i; i < 2; ++i) {
            if (s.listed[i] != 0) r += _value(s.shares[i], s.tsa[i], s.tss[i]);
        }
    }

    /// @dev V-ADP-1 a V-ADP-4, en cualquier estado.
    function _lawsAdapter(BSnap memory s) internal {
        uint256 exp = _expectedReal(s);
        _ok(s.real == exp, L_ADP1, "realAssets no es el valor de las acciones internas en Blue (modelo, adapter)", exp, s.real);
        _ok(s.allocA == s.allocM[0] + s.allocM[1], L_ADP2, "la allocation del adapter no es la suma de los mercados (suma, adapter)", s.allocM[0] + s.allocM[1], s.allocA);
        for (uint256 i; i < 2; ++i) {
            _ok(s.allocC[i] == s.allocM[i], L_ADP2, "la allocation del colateral no es la de su mercado (mercado, colateral)", s.allocM[i], s.allocC[i]);
            _ok(s.shares[i] == s.blueShares[i], L_ADP3, "las acciones internas del adapter no son su posicion en Blue (Blue, adapter)", s.blueShares[i], s.shares[i]);
            _ok(s.listed[i] <= 1, L_ADP4, "un mercado aparece repetido en marketIds (veces, 1)", s.listed[i], 1);
            _ok((s.listed[i] != 0) == (s.allocM[i] != 0), L_ADP4, "marketIds no coincide con allocation > 0 (en la lista, allocation)", s.listed[i], s.allocM[i]);
        }
        _ok(s.listLen == s.listed[0] + s.listed[1], L_ADP4, "marketIds tiene mercados desconocidos (largo, conocidos)", s.listLen, s.listed[0] + s.listed[1]);
    }

    /// @dev V-ADP-2 tras interactuar con el mercado `m`: su allocation queda en el valor de las acciones internas.
    function _lawAllocAfter(BSnap memory s, uint256 m) internal {
        uint256 v = _value(s.shares[m], s.tsa[m], s.tss[m]);
        _ok(s.allocM[m] == v, L_ADP2, "tras interactuar, la allocation del mercado no es su valor (valor, allocation)", v, s.allocM[m]);
    }

    /// @dev _totalAssets tras el devengamiento, según el modelo: min(R, _TA + ⌊_TA·Δt·maxRate/W⌋), R = ocioso + realAssets.
    function _accruedTA(BSnap memory s) internal pure returns (uint256) {
        uint256 maxTA = s.TA + NexusV2Math.mulDivDown(s.TA * (s.ts - s.lu), s.mr, WAD);
        return NexusV2Math.min(s.idle + s.real, maxTA);
    }

    /// @dev V-TA-1 y V-LOSS-1 para una operación que devenga: A es el _totalAssets justo después del devengamiento (el
    /// final menos lo que entró por la operación, o más lo que salió) y tiene que ser min(R, _TA + ⌊_TA·Δt·maxRate/W⌋),
    /// con R = ocioso + realAssets antes de la operación. Sin comisiones en esta variante.
    function _lawsAccrual(BSnap memory pre, BSnap memory post, uint256 A) internal {
        uint256 R = pre.idle + pre.real;
        uint256 exp = _accruedTA(pre);
        _ok(A == exp, L_TA, "devengamiento fuera del modelo (modelo, real)", exp, A);
        if (R < pre.TA) {
            _ok(A == R, L_LOSS1, "la perdida no se realizo entera (reales, _totalAssets)", R, A);
            ++hLosses;
        }
        _ok(post.lu == pre.ts, L_TA, "lastUpdate no quedo en la hora del devengamiento (hora, lastUpdate)", pre.ts, post.lu);
        ++checks;
    }

    /// @dev V-SOLV-1 tras un devengamiento puro: _totalAssets ≤ R, así que lo reclamable está respaldado.
    function _lawSolvency(BSnap memory s) internal {
        uint256 claim = NexusV2Math.mulDivDown(s.T, s.TA + 1, s.T + s.vShares);
        _ok(claim <= s.idle + s.real, L_SOLV, "lo reclamable supera los activos reales (reclamable, reales)", claim, s.idle + s.real);
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

    function _lawName(uint8 law) internal pure returns (string memory) {
        if (law == L_TA) return "V-TA-1";
        if (law == L_LOSS1) return "V-LOSS-1";
        if (law == L_SOLV) return "V-SOLV-1";
        if (law == L_ADP1) return "V-ADP-1";
        if (law == L_ADP2) return "V-ADP-2";
        if (law == L_ADP3) return "V-ADP-3";
        if (law == L_ADP4) return "V-ADP-4";
        return "V-ADP-5";
    }

    function check() external view returns (string memory) {
        if (violations == 0) return "";
        string memory list;
        for (uint8 l; l < N_LAWS; ++l) {
            if (lawMask & (uint256(1) << l) != 0) list = string(abi.encodePacked(list, bytes(list).length == 0 ? "" : " ", _lawName(l)));
        }
        return string(abi.encodePacked(firstViolation, " [leyes: ", list, "]"));
    }

    function stats()
        external
        view
        returns (uint256 laws, uint256 checks_, uint256 losses, uint256 badDebt, uint256 allocs, uint256 deallocs, uint256 borrows, uint256 maxRound)
    {
        return (hLaws, checks, hLosses, hBadDebt, hAllocs, hDeallocs, hBorrows, hMaxRound);
    }
}

contract NexusVaultV2BlueHandler is NexusVaultV2BlueHunter {
    constructor(uint256 fee, uint256 mgmtFee) NexusVaultV2BlueBase(fee, mgmtFee) {
        _hunterInit();
    }

    /* USUARIOS DEL VAULT (sin adapter de liquidez: no tocan Blue) */

    function deposit(uint256 actorSeed, uint256 assets) external {
        address who = actors[actorSeed % actors.length];
        uint256 a = 1 + assets % MAX_ASSETS;
        deal(address(token), who, token.balanceOf(who) + a, true);
        vm.prank(who);
        token.approve(address(vault), type(uint256).max);
        _accrueBlue();
        BSnap memory pre = _snap();
        vm.prank(who);
        vault.deposit(a, who);
        BSnap memory post = _snap();
        _lawsAccrual(pre, post, post.TA - (post.idle - pre.idle));
        _lawsAdapter(post);
    }

    function withdraw(uint256 actorSeed, uint256 assets) external {
        address who = actors[actorSeed % actors.length];
        _accrueBlue();
        BSnap memory pre = _snap();
        uint256 A = _accruedTA(pre);
        uint256 a = _clamp(assets, 0, _min(pre.idle, NexusV2Math.mulDivDown(vault.balanceOf(who), A + 1, pre.T + pre.vShares)));
        if (a == 0) return;
        vm.prank(who);
        vault.withdraw(a, who, who);
        BSnap memory post = _snap();
        _lawsAccrual(pre, post, post.TA + (pre.idle - post.idle));
        _lawsAdapter(post);
    }

    function accrue() external {
        _accrueBlue();
        BSnap memory pre = _snap();
        vault.accrueInterest();
        BSnap memory post = _snap();
        _lawsAccrual(pre, post, post.TA);
        _lawsAdapter(post);
        _lawSolvency(post);
    }

    function warp(uint256 secs) external {
        vm.warp(hClock.time() + 1 + secs % (30 days));
    }

    /* ALLOCATOR */

    /// @dev allocate de `a` en el mercado m: Blue recibe exactamente `a`, el adapter suma ⌊a·(tss+1e6)/(tsa+1)⌋ acciones
    /// y la allocation del mercado queda en su valor (V-ADP-2, V-ADP-5).
    function allocate(uint256 marketSeed, uint256 assets) external {
        uint256 m = marketSeed % 2;
        _accrueBlue();
        BSnap memory pre = _snap();
        uint256 a = _clamp(assets, 0, pre.idle);
        vm.prank(ALLOCATOR);
        vault.allocate(address(adapter), abi.encode(mps[m]), a);
        BSnap memory post = _snap();
        uint256 minted = NexusV2Math.mulDivDown(a, pre.tss[m] + VIRTUAL_SHARES, pre.tsa[m] + VIRTUAL_ASSETS);
        _ok(post.tsa[m] == pre.tsa[m] + a, L_ADP5, "allocate no suministro exactamente los activos en Blue (esperado, Blue)", pre.tsa[m] + a, post.tsa[m]);
        _ok(post.shares[m] == pre.shares[m] + minted, L_ADP5, "allocate no sumo las acciones de toSharesDown (esperadas, adapter)", pre.shares[m] + minted, post.shares[m]);
        _lawRounding(pre, post, m);
        _lawsAccrual(pre, post, post.TA);
        _lawAllocAfter(post, m);
        _lawsAdapter(post);
        if (a != 0) ++hAllocs;
    }

    /// @dev deallocate de `a` del mercado m (a lo sumo el valor de la posición y la liquidez de Blue): Blue entrega
    /// exactamente `a` y quema ⌈a·(tss+1e6)/(tsa+1)⌉ acciones del adapter.
    function deallocate(uint256 marketSeed, uint256 assets) external {
        uint256 m = marketSeed % 2;
        _accrueBlue();
        BSnap memory pre = _snap();
        if (pre.allocM[m] == 0) return;
        // una de cada cuatro, todo lo que se pueda: así un mercado llega a 0 y sale de marketIds (V-ADP-4)
        uint256 most = _min(_value(pre.shares[m], pre.tsa[m], pre.tss[m]), pre.tsa[m] - pre.tba[m]);
        uint256 a = assets % 4 == 0 ? most : _clamp(assets, 0, most);
        vm.prank(ALLOCATOR);
        vault.deallocate(address(adapter), abi.encode(mps[m]), a);
        BSnap memory post = _snap();
        uint256 burned = NexusV2Math.mulDivUp(a, pre.tss[m] + VIRTUAL_SHARES, pre.tsa[m] + VIRTUAL_ASSETS);
        _ok(post.idle == pre.idle + a, L_ADP5, "deallocate no devolvio exactamente los activos (esperado, ocioso)", pre.idle + a, post.idle);
        _ok(pre.shares[m] == post.shares[m] + burned, L_ADP5, "deallocate no quemo las acciones de toSharesUp (esperadas, quemadas)", burned, pre.shares[m] - post.shares[m]);
        _ok(post.TA == pre.TA && post.T == pre.T, L_TA, "deallocate cambio _totalAssets o totalSupply (antes, despues)", pre.TA, post.TA);
        _lawRounding(pre, post, m);
        _lawAllocAfter(post, m);
        _lawsAdapter(post);
        if (a != 0) ++hDeallocs;
    }

    /// @dev V-ADP-5: mover activos entre lo ocioso y el mercado m cambia R = ocioso + realAssets solo por el redondeo de
    /// Blue, dentro de [−⌈p⌉, +1] con p = (tsa+1)/(tss+1e6) el precio de una acción de suministro antes del movimiento
    /// (demostración en docs/CAZADOR_VAULT_V2.md, §4: sin pisos el valor cambia en (−p, 0]; los dos pisos de
    /// toAssetsDown suman a lo sumo 1 de cada lado). Con las acciones virtuales de Blue, p ≪ 1 y el rango es [−1, +1].
    function _lawRounding(BSnap memory pre, BSnap memory post, uint256 m) internal {
        uint256 rPre = pre.idle + pre.real;
        uint256 rPost = post.idle + post.real;
        uint256 pUp = NexusV2Math.mulDivUp(1, pre.tsa[m] + VIRTUAL_ASSETS, pre.tss[m] + VIRTUAL_SHARES);
        _ok(rPost <= rPre + 1, L_ADP5, "mover activos a o desde Blue hizo ganar al vault mas de 1 (antes, despues)", rPre, rPost);
        _ok(rPost + pUp >= rPre, L_ADP5, "mover activos a o desde Blue perdio mas que el redondeo (antes, despues)", rPre, rPost);
        uint256 loss = rPre - _min(rPre, rPost);
        if (loss > hMaxRound) hMaxRound = loss;
    }

    /* PRESTATARIOS Y PRECIOS EN BLUE */

    /// @dev Un prestatario pone colateral y toma prestado hasta su LTV y la liquidez del mercado.
    function borrow(uint256 borrowerSeed, uint256 marketSeed, uint256 assets) external {
        uint256 m = marketSeed % 2;
        address b = borrowers[borrowerSeed % borrowers.length];
        _accrueBlue();
        Market memory mk = morpho.market(Id.wrap(marketIds[m]));
        uint256 liquidity = mk.totalSupplyAssets - mk.totalBorrowAssets;
        uint256 x = _clamp(assets, 0, liquidity / 2);
        if (x == 0) return;
        // Colateral para que TODA la deuda (la que ya tenía más x) quede al 50 % de LTV al precio actual.
        Position memory p = morpho.position(Id.wrap(marketIds[m]), b);
        uint256 debt = NexusV2Math.mulDivUp(p.borrowShares, mk.totalBorrowAssets + VIRTUAL_ASSETS, mk.totalBorrowShares + VIRTUAL_SHARES);
        // + 2: con montos chicos, Blue redondea la deuda hacia arriba y lo prestable hacia abajo
        uint256 need = NexusV2Math.mulDivUp((debt + x + 2) * 2, ORACLE_ONE, oracles[m].price());
        uint256 coll = need > p.collateral ? need - p.collateral : 0;
        deal(address(collats[m]), b, collats[m].balanceOf(b) + coll, true);
        vm.startPrank(b);
        collats[m].approve(address(morpho), type(uint256).max);
        if (coll != 0) morpho.supplyCollateral(mps[m], coll, b, hex""); // Blue rechaza 0 de colateral
        morpho.borrow(mps[m], x, 0, b, b);
        vm.stopPrank();
        ++hBorrows;
    }

    function repay(uint256 borrowerSeed, uint256 marketSeed) external {
        uint256 m = marketSeed % 2;
        address b = borrowers[borrowerSeed % borrowers.length];
        _accrueBlue();
        uint256 shares = morpho.position(Id.wrap(marketIds[m]), b).borrowShares;
        if (shares == 0) return;
        deal(address(token), b, token.balanceOf(b) + ABS_CAP, true);
        vm.startPrank(b);
        token.approve(address(morpho), type(uint256).max);
        morpho.repay(mps[m], 0, shares, b, hex"");
        vm.stopPrank();
    }

    /// @dev Precio del colateral entre 10 % y 150 % de 1:1: las caídas dejan posiciones liquidables y con deuda
    /// incobrable.
    function setPrice(uint256 marketSeed, uint256 price) external {
        oracles[marketSeed % 2].setPrice(_clamp(price, ORACLE_ONE / 10, ORACLE_ONE * 3 / 2));
    }

    /// @dev Liquida todo el colateral de un prestatario insolvente; si queda deuda, Blue la reparte entre los
    /// proveedores (el adapter incluido) y el vault la realiza en su próximo devengamiento (V-LOSS-1).
    function liquidate(uint256 borrowerSeed, uint256 marketSeed) external {
        uint256 m = marketSeed % 2;
        address b = borrowers[borrowerSeed % borrowers.length];
        _accrueBlue();
        Position memory p = morpho.position(Id.wrap(marketIds[m]), b);
        if (p.collateral == 0 || p.borrowShares == 0) return;
        deal(address(token), LIQUIDATOR, token.balanceOf(LIQUIDATOR) + ABS_CAP, true);
        vm.startPrank(LIQUIDATOR);
        token.approve(address(morpho), type(uint256).max);
        try morpho.liquidate(mps[m], b, p.collateral, 0, hex"") {
            if (morpho.position(Id.wrap(marketIds[m]), b).borrowShares == 0) ++hBadDebt;
        } catch {}
        vm.stopPrank();
    }
}

contract NexusVaultV2BlueTest is Test {
    NexusVaultV2BlueHandler internal handler;

    function setUp() public virtual {
        handler = new NexusVaultV2BlueHandler(_fee(), _mgmtFee());
        targetContract(address(handler));
    }

    function _fee() internal pure virtual returns (uint256) {
        return 0;
    }

    function _mgmtFee() internal pure virtual returns (uint256) {
        return 0;
    }

    function invariant_vaultV2Blue() public view {
        string memory err = handler.check();
        assertEq(bytes(err).length, 0, err);
    }

    function afterInvariant() public {
        (
            uint256 laws,
            uint256 checks_,
            uint256 losses,
            uint256 badDebt,
            uint256 allocs,
            uint256 deallocs,
            uint256 borrows,
            uint256 maxRound
        ) = handler.stats();
        emit log_named_uint("verificaciones", checks_);
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cazador: perdidas realizadas (deuda incobrable)", losses);
        emit log_named_uint("cobertura: liquidaciones con deuda incobrable", badDebt);
        emit log_named_uint("cobertura: asignaciones con efecto", allocs);
        emit log_named_uint("cobertura: desasignaciones con efecto", deallocs);
        emit log_named_uint("cobertura: prestamos", borrows);
        emit log_named_uint("cazador: mayor perdida por redondeo de Blue", maxRound);
    }
}
