// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

// Cazador de vulnerabilidades de EulerEarn (euler-xyz/euler-earn @ a8cc099, la versión desplegada en Ethereum).
// Variante A: estrategias ERC-4626 de prueba sobre el ERC4626 de OpenZeppelin 5.3 (el mismo que usa EulerEarn), con
// offset de decimales y pausa, así el fantasma conoce los activos reales y el redondeo de cada estrategia de forma
// exacta. Leyes E-... en 512 bits, sin vistas de EulerEarn (docs/CAZADOR_EULER_EARN.md).

import {Test} from "../../lib/forge-std/src/Test.sol";
import {EulerEarnFactory} from "../../src/EulerEarnFactory.sol";
import {IEulerEarn, MarketAllocation} from "../../src/interfaces/IEulerEarn.sol";
import {IPerspective} from "../../src/interfaces/IPerspective.sol";
import {EthereumVaultConnector} from "../../lib/ethereum-vault-connector/src/EthereumVaultConnector.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @dev Aritmética de 512 bits: comparar dos tipos de cambio sin esconder 1 wei.
library NexusEEMath {
    uint256 internal constant WAD = 1e18;

    function mul512(uint256 a, uint256 b) internal pure returns (uint256 hi, uint256 lo) {
        assembly ("memory-safe") {
            let mm := mulmod(a, b, not(0))
            lo := mul(a, b)
            hi := sub(sub(mm, lo), lt(mm, lo))
        }
    }

    /// @dev a·b ≥ c·d exacto.
    function geq(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (bool) {
        (uint256 h1, uint256 l1) = mul512(a, b);
        (uint256 h2, uint256 l2) = mul512(c, d);
        return h1 > h2 || (h1 == h2 && l1 >= l2);
    }

    function fits(uint256 a, uint256 b) internal pure returns (bool) {
        (uint256 hi,) = mul512(a, b);
        return hi == 0;
    }

    function mulDivDown(uint256 a, uint256 b, uint256 d) internal pure returns (uint256) {
        (uint256 hi, uint256 lo) = mul512(a, b);
        if (hi == 0) return lo / d;
        return _div512(hi, lo, mulmod(a, b, d), d);
    }

    function mulDivUp(uint256 a, uint256 b, uint256 d) internal pure returns (uint256 r) {
        r = mulDivDown(a, b, d);
        if (mulmod(a, b, d) != 0) ++r;
    }

    function _div512(uint256 p1, uint256 p0, uint256 rem, uint256 d) private pure returns (uint256 r) {
        require(d > p1, "nexus: mulDiv desborda");
        unchecked {
            if (rem > p0) --p1;
            p0 -= rem;
            uint256 twos = d & (0 - d);
            d /= twos;
            p0 /= twos;
            twos = (0 - twos) / twos + 1;
            p0 |= p1 * twos;
            uint256 inv = (3 * d) ^ 2;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            r = p0 * inv;
        }
    }

    function zeroFloorSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

/// @notice Reloj del harness: lee block.timestamp en una llamada externa (via_ir puede cachearlo dentro de una función).
contract NexusEEClock {
    function time() external view returns (uint256) {
        return block.timestamp;
    }
}

/// @notice Token de prueba con decimales configurables (el handler acuña y quema con `deal`).
contract NexusEEToken is ERC20 {
    uint8 internal immutable dec;

    constructor(uint8 d) ERC20("nexus asset", "NXA") {
        dec = d;
    }

    function decimals() public view override returns (uint8) {
        return dec;
    }
}

/// @notice Estrategia ERC-4626 de prueba: el ERC4626 de OpenZeppelin 5.3 tal cual, con su offset de decimales y una
/// pausa que hace revertir deposit, mint, withdraw y redeem (las vistas no cambian), para recorrer los try/catch de
/// EulerEarn. Sus activos son su saldo del token: el rendimiento y la pérdida los pone el handler con `deal`.
contract NexusStrategy is ERC4626 {
    uint8 internal immutable offset;
    bool public paused;

    constructor(IERC20 asset_, uint8 offset_) ERC4626(asset_) ERC20("nexus strategy", "NXS") {
        offset = offset_;
    }

    function setPaused(bool p) external {
        paused = p;
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return offset;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        require(!paused, "nexus: estrategia pausada");
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        require(!paused, "nexus: estrategia pausada");
        super._withdraw(caller, receiver, owner, assets, shares);
    }
}

/// @notice Perspectiva de prueba: verifica las estrategias que el harness le indica.
contract NexusPerspective is IPerspective {
    mapping(address => bool) internal ok;

    function name() external pure returns (string memory) {
        return "nexus";
    }

    function perspectiveVerify(address vault) external {
        ok[vault] = true;
    }

    function perspectiveUnverify(address vault) external {
        ok[vault] = false;
    }

    function isVerified(address vault) external view returns (bool) {
        return ok[vault];
    }
}

/// @notice Base del harness: EVC real, perspectiva y fábrica de EulerEarn, el vault, tres estrategias con offsets 0, 3 y
/// 6 (la de offset 6, primera en la supplyQueue y con tope chico, para que los depósitos se repartan), roles y comisión.
abstract contract NexusEEBase is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant V = 1e6; // ConstantsLib.VIRTUAL_AMOUNT
    uint256 internal constant MAX_FEE = 0.5e18;
    uint256 internal constant NS = 3; // estrategias
    /// @dev Monto máximo por acción. Con offset 6 cada activo vale 10^6 acciones de la estrategia, y EulerEarn guarda
    /// las suyas en uint112 (≈ 5,2·10^33): 1e24 por acción deja margen para miles de depósitos (la cota E-BOUND).
    uint256 internal constant MAX_ASSETS = 1e24;
    uint256 internal constant CAP_BIG = 1e30;
    uint256 internal constant CAP_SMALL = 2e24;

    address internal constant OWNER = address(uint160(uint256(keccak256("nexus.ee.owner"))));
    address internal constant CURATOR = address(uint160(uint256(keccak256("nexus.ee.curator"))));
    address internal constant ALLOCATOR = address(uint160(uint256(keccak256("nexus.ee.allocator"))));
    address internal constant FEE = address(uint160(uint256(keccak256("nexus.ee.fee"))));
    address internal constant OUTSIDER = address(uint160(uint256(keccak256("nexus.ee.outsider"))));

    NexusEEToken internal token;
    EthereumVaultConnector internal evc;
    NexusPerspective internal perspective;
    EulerEarnFactory internal factory;
    IEulerEarn internal vault;
    NexusStrategy[3] internal strat;
    uint8[3] internal OFF = [0, 3, 6];

    address[] internal actors;
    uint256 internal violations;
    uint256 internal lawMask;
    string internal firstViolation;

    constructor(uint256 fee, uint8 assetDecimals) {
        token = new NexusEEToken(assetDecimals);
        evc = new EthereumVaultConnector();
        perspective = new NexusPerspective();
        factory = new EulerEarnFactory(OWNER, address(evc), address(0), address(perspective));
        vault = factory.createEulerEarn(OWNER, 0, address(token), "nexus earn", "NXE", bytes32(uint256(1)));

        vm.startPrank(OWNER);
        vault.setCurator(CURATOR);
        vault.setIsAllocator(ALLOCATOR, true);
        vm.stopPrank();

        for (uint256 i; i < NS; ++i) {
            strat[i] = new NexusStrategy(IERC20(address(token)), OFF[i]);
            perspective.perspectiveVerify(address(strat[i]));
            _raiseCap(i, i == 2 ? CAP_SMALL : CAP_BIG);
        }
        // supplyQueue: la de tope chico primero; el resto se derrama a las otras
        IERC4626[] memory sq = new IERC4626[](3);
        sq[0] = IERC4626(address(strat[2]));
        sq[1] = IERC4626(address(strat[0]));
        sq[2] = IERC4626(address(strat[1]));
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(sq);

        if (fee > 0) {
            vm.startPrank(OWNER);
            vault.setFeeRecipient(FEE);
            vault.setFee(fee);
            vm.stopPrank();
        }

        for (uint256 i; i < 4; ++i) {
            actors.push(address(uint160(uint256(keccak256(abi.encode("nexus.ee.actor", i))))));
            vm.prank(actors[i]);
            token.approve(address(vault), type(uint256).max);
        }
        vm.prank(OUTSIDER);
        token.approve(address(strat[0]), type(uint256).max);
        vm.prank(OUTSIDER);
        token.approve(address(strat[1]), type(uint256).max);
        vm.prank(OUTSIDER);
        token.approve(address(strat[2]), type(uint256).max);
    }

    /// @dev Subir un tope: submitCap del curador y acceptCap (timelock 0 en el harness).
    function _raiseCap(uint256 i, uint256 cap) internal {
        vm.prank(CURATOR);
        vault.submitCap(IERC4626(address(strat[i])), cap);
        vault.acceptCap(IERC4626(address(strat[i])));
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _clamp(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + x % (hi - lo + 1);
    }
}

/// @notice Contabilidad fantasma y leyes E-... de EulerEarn.
abstract contract NexusEEHunter is NexusEEBase {
    uint8 internal constant L_TA = 0; // E-TA-1: devengamiento exacto (lostAssets y lastTotalAssets)
    uint8 internal constant L_FEE = 1; // E-FEE-1: acciones de comisión exactas
    uint8 internal constant L_INF1 = 2; // E-INF-1: conversiones exactas
    uint8 internal constant L_INF2 = 3; // E-INF-2: el precio (L+V)/(T+V) nunca baja
    uint8 internal constant L_ALLOC = 4; // E-ALLOC-1: reparto exacto por las colas
    uint8 internal constant L_STRAT = 5; // E-STRAT-1: seguimiento interno de las acciones de cada estrategia
    uint8 internal constant L_LEDGER = 6; // E-LEDGER: Σ saldos = totalSupply, totalSupply esperado, terceros intactos
    uint8 internal constant L_LIVE = 7; // E-LIVE: pasa si y solo si el modelo dice que pasa
    uint8 internal constant N_LAWS = 8;

    struct Snap {
        uint256 ts;
        uint256 L; // lastTotalAssets
        uint256 P; // lostAssets
        uint256 T; // totalSupply
        uint256 f; // fee
        uint256 idle; // token.balanceOf(vault): EulerEarn no guarda activos ociosos
        uint256[3] tA; // activos de cada estrategia (su saldo del token)
        uint256[3] tS; // totalSupply de cada estrategia
        uint256[3] real; // acciones reales de EulerEarn en cada estrategia
        uint256[3] b; // config[i].balance: el seguimiento interno de EulerEarn
        uint256[3] cap;
        bool[3] enabled;
        bool[3] paused;
        uint256[3] rmAt; // config[i].removableAt
        uint256[3] pendAt; // pendingCap[i].validAt
        uint256[5] bal; // actors[0..3], FEE
        uint8[] sq; // supplyQueue, como índices de estrategia
        uint8[] wq; // withdrawQueue
    }

    NexusEEClock internal hClock;
    /// @dev Acciones de las estrategias que EulerEarn tiene y no sigue: donaciones y estrategias removidas con saldo.
    uint256[3] internal gExtra;

    // métricas (por corrida)
    uint256 internal hLaws;
    uint256 internal hChecks;
    uint256 internal hLosses; // devengamientos que subieron lostAssets
    uint256 internal hInterest; // devengamientos con interés
    uint256 internal hFeeShares;
    uint256 internal hSpills; // depósitos repartidos en más de una estrategia
    uint256 internal hSkips; // estrategias salteadas por pausa (try/catch)
    uint256 internal hRejected; // operaciones que el modelo predijo que revertían, y revirtieron
    uint256 internal hDonations;
    uint256 internal hBound; // depósitos que revertirían por el uint112 del seguimiento interno (E-BOUND)

    function _hunterInit() internal {
        hClock = new NexusEEClock();
    }

    function _sIdx(address id) internal view returns (uint8) {
        for (uint8 i; i < NS; ++i) {
            if (address(strat[i]) == id) return i;
        }
        revert("nexus: estrategia desconocida");
    }

    function _snap() internal view returns (Snap memory s) {
        s.ts = hClock.time();
        s.L = vault.lastTotalAssets();
        s.P = vault.lostAssets();
        s.T = vault.totalSupply();
        s.f = vault.fee();
        s.idle = token.balanceOf(address(vault));
        for (uint256 i; i < NS; ++i) {
            IERC4626 id = IERC4626(address(strat[i]));
            s.tA[i] = token.balanceOf(address(strat[i]));
            s.tS[i] = strat[i].totalSupply();
            s.real[i] = strat[i].balanceOf(address(vault));
            (uint112 b, uint136 cap, bool enabled, uint64 rmAt) = IEEStatic(address(vault)).config(id);
            s.b[i] = b;
            s.cap[i] = cap;
            s.enabled[i] = enabled;
            s.rmAt[i] = rmAt;
            (, uint64 validAt) = IEEStatic(address(vault)).pendingCap(id);
            s.pendAt[i] = validAt;
            s.paused[i] = strat[i].paused();
        }
        for (uint256 i; i < 4; ++i) {
            s.bal[i] = vault.balanceOf(actors[i]);
        }
        s.bal[4] = vault.balanceOf(FEE);
        uint256 n = vault.supplyQueueLength();
        s.sq = new uint8[](n);
        for (uint256 k; k < n; ++k) {
            s.sq[k] = _sIdx(address(vault.supplyQueue(k)));
        }
        n = vault.withdrawQueueLength();
        s.wq = new uint8[](n);
        for (uint256 k; k < n; ++k) {
            s.wq[k] = _sIdx(address(vault.withdrawQueue(k)));
        }
    }

    /* MODELO (fórmulas de OpenZeppelin 5.3 y de EulerEarn @ a8cc099, con la aritmética exacta del fantasma) */

    function _scale(uint256 i) internal view returns (uint256) {
        return 10 ** OFF[i];
    }

    /// @dev previewRedeem de la estrategia i: ⌊s·(tA+1)/(tS+10^off)⌋.
    function _redeem(uint256 i, uint256 shares, uint256 tA, uint256 tS) internal view returns (uint256) {
        return NexusEEMath.mulDivDown(shares, tA + 1, tS + _scale(i));
    }

    /// @dev Activos reales según el seguimiento interno: Σ previewRedeem(b_i) por la withdrawQueue.
    function _realTotal(Snap memory s) internal view returns (uint256 rt) {
        for (uint256 k; k < s.wq.length; ++k) {
            uint256 i = s.wq[k];
            rt += _redeem(i, s.b[i], s.tA[i], s.tS[i]);
        }
    }

    /// @dev Devengamiento esperado (replica _accruedFeeAndAssets): A = newTotalAssets, P2 = newLostAssets, σ.
    function _expectAccrual(Snap memory s) internal view returns (uint256 A, uint256 P2, uint256 sigma) {
        uint256 rt = _realTotal(s);
        uint256 lp = NexusEEMath.zeroFloorSub(s.L, s.P);
        P2 = rt < lp ? s.L - rt : s.P;
        A = rt + P2;
        uint256 interest = NexusEEMath.zeroFloorSub(A, s.L);
        if (interest != 0 && s.f != 0) {
            uint256 F = NexusEEMath.mulDivDown(interest, s.f, WAD);
            sigma = NexusEEMath.mulDivDown(F, s.T + V, A - F + V);
        }
    }

    /// @dev Reparto de un depósito de `a` por la supplyQueue (replica _supplyStrategy, con duplicados y pausas):
    /// devuelve el estado de las estrategias después y lo que quedó sin colocar (si no es 0, revierte). Si una
    /// estrategia acuñara más acciones de las que entran en el uint112 del seguimiento interno, `rem` vuelve en
    /// type(uint256).max: el cast está en el bloque de éxito del try, así que el depósito entero revierte (pasa tras una
    /// pérdida casi total de una estrategia que sigue en la supplyQueue con lugar en su tope: E-BOUND).
    function _simSupply(Snap memory s, uint256 a)
        internal
        view
        returns (uint256[3] memory tA, uint256[3] memory tS, uint256[3] memory b, uint256 rem, uint256 used)
    {
        for (uint256 i; i < NS; ++i) {
            (tA[i], tS[i], b[i]) = (s.tA[i], s.tS[i], s.b[i]);
        }
        rem = a;
        for (uint256 k; k < s.sq.length && rem != 0; ++k) {
            uint256 i = s.sq[k];
            if (s.cap[i] == 0) continue;
            uint256 toSupply = NexusEEMath.min(NexusEEMath.zeroFloorSub(s.cap[i], _redeem(i, b[i], tA[i], tS[i])), rem);
            if (toSupply == 0) continue;
            if (s.paused[i]) continue; // el try/catch de EulerEarn la saltea
            if (!NexusEEMath.fits(toSupply, tS[i] + _scale(i))) return (tA, tS, b, type(uint256).max, used);
            uint256 shares = NexusEEMath.mulDivDown(toSupply, tS[i] + _scale(i), tA[i] + 1);
            if (b[i] + shares > type(uint112).max) return (tA, tS, b, type(uint256).max, used);
            tA[i] += toSupply;
            tS[i] += shares;
            b[i] += shares;
            rem -= toSupply;
            ++used;
        }
    }

    /// @dev Retiro de `a` por la withdrawQueue (replica _withdrawStrategy): maxWithdrawFromStrategy es el mínimo entre
    /// el maxWithdraw de la estrategia (sobre las acciones reales) y previewRedeem del seguimiento interno.
    function _simWithdraw(Snap memory s, uint256 a)
        internal
        view
        returns (uint256[3] memory tA, uint256[3] memory tS, uint256[3] memory b, uint256 rem)
    {
        uint256[3] memory real;
        for (uint256 i; i < NS; ++i) {
            (tA[i], tS[i], b[i], real[i]) = (s.tA[i], s.tS[i], s.b[i], s.real[i]);
        }
        rem = a;
        for (uint256 k; k < s.wq.length && rem != 0; ++k) {
            uint256 i = s.wq[k];
            uint256 maxW = NexusEEMath.min(_redeem(i, real[i], tA[i], tS[i]), _redeem(i, b[i], tA[i], tS[i]));
            uint256 toWithdraw = NexusEEMath.min(maxW, rem);
            if (toWithdraw == 0 || s.paused[i]) continue;
            uint256 shares = NexusEEMath.mulDivUp(toWithdraw, tS[i] + _scale(i), tA[i] + 1);
            tA[i] -= toWithdraw;
            tS[i] -= shares;
            b[i] -= shares;
            real[i] -= shares;
            rem -= toWithdraw;
        }
    }

    /// @dev Lo que se puede retirar en total por la withdrawQueue (sin las pausadas).
    function _withdrawable(Snap memory s) internal view returns (uint256 w) {
        for (uint256 k; k < s.wq.length; ++k) {
            uint256 i = s.wq[k];
            if (s.paused[i]) continue;
            w += NexusEEMath.min(_redeem(i, s.real[i], s.tA[i], s.tS[i]), _redeem(i, s.b[i], s.tA[i], s.tS[i]));
        }
    }

    /* LEYES */

    /// @dev E-TA-1, E-FEE-1, E-INF-2 y E-LEDGER para una operación que devenga: `L1` es lastTotalAssets esperado después
    /// (A ± lo que entró o salió), `tUser` las acciones del usuario (acuñadas o quemadas, con su signo en `enters`).
    function _lawsAccrual(Snap memory pre, Snap memory post, uint256 L1, uint256 tUser, bool enters, address who)
        internal
    {
        (uint256 A, uint256 P2, uint256 sigma) = _expectAccrual(pre);
        _ok(post.L == L1, L_TA, "lastTotalAssets distinto del modelo (modelo, real)", L1, post.L);
        _ok(post.P == P2, L_TA, "lostAssets distinto del modelo (modelo, real)", P2, post.P);
        _ok(post.P >= pre.P, L_TA, "lostAssets bajo (antes, despues)", pre.P, post.P);
        uint256 gotFee = NexusEEMath.zeroFloorSub(post.bal[4], pre.bal[4]);
        if (who != FEE) _ok(gotFee == sigma, L_FEE, "acciones de comision distintas del modelo (modelo, real)", sigma, gotFee);
        uint256 expT = enters ? pre.T + sigma + tUser : pre.T + sigma - NexusEEMath.min(tUser, pre.T + sigma);
        _ok(post.T == expT, L_LEDGER, "totalSupply distinto del esperado (esperado, real)", expT, post.T);
        if (P2 > pre.P) ++hLosses;
        if (sigma != 0) hFeeShares += sigma;
        if (A > pre.L) ++hInterest;
        _lawPrice(pre, post);
        ++hChecks;
    }

    /// @dev E-INF-2: (L+V)/(T+V) nunca baja: (L'+V)(T+V) ≥ (L+V)(T'+V), exacto. La pérdida no se realiza (lostAssets la
    /// absorbe), la comisión se cobra a un precio que excluye la propia comisión y toda conversión redondea a favor del
    /// vault (demostración en docs/CAZADOR_EULER_EARN.md).
    function _lawPrice(Snap memory pre, Snap memory post) internal {
        _ok(
            NexusEEMath.geq(post.L + V, pre.T + V, pre.L + V, post.T + V),
            L_INF2,
            "el precio por accion bajo (L antes, L despues)",
            pre.L,
            post.L
        );
    }

    /// @dev E-ALLOC-1 y E-STRAT-1: las estrategias quedaron como predice el modelo (activos, acciones, seguimiento
    /// interno) y las acciones reales de EulerEarn son las seguidas más las que no sigue (donaciones, removidas).
    function _lawStrategies(Snap memory post, uint256[3] memory tA, uint256[3] memory tS, uint256[3] memory b) internal {
        for (uint256 i; i < NS; ++i) {
            _ok(post.tA[i] == tA[i], L_ALLOC, "activos de una estrategia distintos del reparto (modelo, real)", tA[i], post.tA[i]);
            _ok(post.tS[i] == tS[i], L_ALLOC, "acciones de una estrategia distintas del reparto (modelo, real)", tS[i], post.tS[i]);
            _ok(post.b[i] == b[i], L_STRAT, "seguimiento interno distinto del modelo (modelo, real)", b[i], post.b[i]);
        }
        _lawTracking(post);
    }

    /// @dev E-STRAT-1: acciones reales = seguidas + las que EulerEarn no sigue; y EulerEarn no guarda activos ociosos.
    function _lawTracking(Snap memory s) internal {
        for (uint256 i; i < NS; ++i) {
            _ok(s.real[i] == s.b[i] + gExtra[i], L_STRAT, "acciones reales distintas de seguidas + no seguidas (esperado, real)", s.b[i] + gExtra[i], s.real[i]);
        }
        _ok(s.idle == 0, L_ALLOC, "EulerEarn quedo con activos ociosos (0, ociosos)", 0, s.idle);
    }

    /// @dev E-LEDGER: Σ saldos = totalSupply.
    function _lawLedger(Snap memory s) internal {
        uint256 sum = s.bal[4];
        for (uint256 i; i < 4; ++i) {
            sum += s.bal[i];
        }
        _ok(sum == s.T, L_LEDGER, "la suma de los saldos no es totalSupply (suma, totalSupply)", sum, s.T);
    }

    /// @dev Operación sin devengamiento (eventos de las estrategias, intentos que revirtieron, transferencias):
    /// lastTotalAssets, lostAssets y totalSupply no cambian.
    function _lawsStill(Snap memory pre, Snap memory post) internal {
        _ok(post.L == pre.L, L_TA, "una operacion sin devengamiento cambio lastTotalAssets (antes, despues)", pre.L, post.L);
        _ok(post.P == pre.P, L_TA, "una operacion sin devengamiento cambio lostAssets (antes, despues)", pre.P, post.P);
        _ok(post.T == pre.T, L_LEDGER, "una operacion sin devengamiento cambio totalSupply (antes, despues)", pre.T, post.T);
        _lawTracking(post);
        _lawLedger(post);
    }

    /* REGISTRO */

    function _ok(bool cond, uint8 law, string memory what, uint256 x, uint256 y) internal {
        unchecked {
            ++hLaws;
        }
        if (!cond) _flag(law, what, x, y);
    }

    function _flag(uint8 law, string memory what, uint256 x, uint256 y) internal {
        lawMask |= uint256(1) << law;
        if (violations++ == 0) {
            firstViolation = string(abi.encodePacked(_lawName(law), ": ", what, ": ", vm.toString(x), ", ", vm.toString(y)));
        }
    }

    function _lawName(uint8 law) internal pure returns (string memory) {
        if (law == L_TA) return "E-TA-1";
        if (law == L_FEE) return "E-FEE-1";
        if (law == L_INF1) return "E-INF-1";
        if (law == L_INF2) return "E-INF-2";
        if (law == L_ALLOC) return "E-ALLOC-1";
        if (law == L_STRAT) return "E-STRAT-1";
        if (law == L_LEDGER) return "E-LEDGER";
        return "E-LIVE";
    }

    /// @notice "" si ninguna ley falló; si no, la primera violación y la lista de leyes que fallaron.
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

    function stats() external view returns (uint256 laws, uint256 checks_, uint256 feeShares) {
        return (hLaws, hChecks, hFeeShares);
    }

    function coverage()
        external
        view
        returns (uint256 losses, uint256 interest, uint256 spills, uint256 skips, uint256 rejected, uint256 donations)
    {
        return (hLosses, hInterest, hSpills, hSkips, hRejected, hDonations);
    }

    function coverageBound() external view returns (uint256 bound) {
        return hBound;
    }
}

/// @dev config() con tipos estáticos (IEulerEarnStaticTyping), para leer el seguimiento interno sin la struct.
interface IEEStatic {
    function config(IERC4626) external view returns (uint112 balance, uint136 cap, bool enabled, uint64 removableAt);
    function pendingCap(IERC4626) external view returns (uint136 value, uint64 validAt);
}
