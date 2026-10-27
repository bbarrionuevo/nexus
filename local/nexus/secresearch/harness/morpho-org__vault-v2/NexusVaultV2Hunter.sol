// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// Cazador de vulnerabilidades para Morpho Vault V2 (variante A: VaultV2 + AdapterMock).
//
// Contabilidad fantasma y leyes exactas evaluadas tras cada acción del handler, al estilo del cazador de MetaMorpho
// (NexusVulnerabilityHunter.sol) pero con la contabilidad de V2: devengamiento con tope de tasa, dos comisiones,
// realización de pérdidas y topes. El modelo formal está en docs/CAZADOR_VAULT_V2.md (leyes V-...).
//
// El fantasma NO usa los métodos de vista del vault (totalAssets, previewX, accrueInterestView): esos son lo que se
// audita. Lee solo estado crudo (los getters de variables públicas: _totalAssets, totalSupply, lastUpdate, maxRate,
// las comisiones y balanceOf) y los activos reales desde fuera del vault (el token y el adapter).

import {Test} from "../../lib/forge-std/src/Test.sol";
import {VaultV2} from "../../src/VaultV2.sol";
import {VaultV2Factory} from "../../src/VaultV2Factory.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {AdapterMock} from "../mocks/AdapterMock.sol";

/// @dev Aritmética de 512 bits: comparar dos tipos de cambio sin esconder 1 wei. V2 usa `mulDiv` de una sola palabra
/// (x*y/d), así que donde el vault puede desbordar, el fantasma lo predice en vez de imitarlo (ley V-BOUND).
library NexusV2Math {
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

    /// @dev ¿a·b entra en uint256? (si no, el `mulDiv` de una palabra del vault revierte).
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

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function zeroFloorSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }
}

/// @dev Reloj en otro contexto de llamada: con via_ir el optimizador puede cachear block.timestamp tras vm.warp.
contract NexusV2Clock {
    function time() external view returns (uint256) {
        return block.timestamp;
    }
}

/// @notice Base del harness de Vault V2: despliega el vault con un AdapterMock, roles, un tope y la comisión elegida.
abstract contract NexusVaultV2Base is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_MAX_RATE = 200e16 / uint256(365 days);
    uint256 internal constant MAX_PERFORMANCE_FEE = 0.5e18;
    uint256 internal constant MAX_MANAGEMENT_FEE = 0.05e18 / uint256(365 days);
    uint256 internal constant MAX_ASSETS = 1e28;
    uint256 internal constant ABS_CAP = 1e30;

    address internal constant OWNER = address(uint160(uint256(keccak256("nexus.v2.owner"))));
    address internal constant CURATOR = address(uint160(uint256(keccak256("nexus.v2.curator"))));
    address internal constant ALLOCATOR = address(uint160(uint256(keccak256("nexus.v2.allocator"))));
    address internal constant PERF = address(uint160(uint256(keccak256("nexus.v2.perf"))));
    address internal constant MGMT = address(uint160(uint256(keccak256("nexus.v2.mgmt"))));

    VaultV2 internal vault;
    ERC20Mock internal token;
    AdapterMock internal adapter;
    bytes internal idData0 = "id-0";
    bytes internal idData1 = "id-1";

    address[] internal actors;
    uint256 internal violations;
    string internal firstViolation;
    uint256 internal checks;

    constructor(uint256 fee, uint256 mgmtFee, uint8 assetDecimals) {
        token = new ERC20Mock(assetDecimals);
        vault = VaultV2(new VaultV2Factory().createVaultV2(OWNER, address(token), bytes32(0)));

        vm.startPrank(OWNER);
        vault.setCurator(CURATOR);
        vault.setIsSentinel(ALLOCATOR, true);
        vm.stopPrank();

        _curated(abi.encodeCall(IVaultV2.setIsAllocator, (ALLOCATOR, true)));
        adapter = new AdapterMock(address(vault));
        _curated(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        _curated(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData0, ABS_CAP)));
        _curated(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData1, ABS_CAP)));

        vm.prank(ALLOCATOR);
        vault.setMaxRate(MAX_MAX_RATE / 2);

        if (fee > 0) {
            _curated(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (PERF)));
            _curated(abi.encodeCall(IVaultV2.setPerformanceFee, (fee)));
        }
        if (mgmtFee > 0) {
            _curated(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (MGMT)));
            _curated(abi.encodeCall(IVaultV2.setManagementFee, (mgmtFee)));
        }

        for (uint256 i; i < 4; ++i) {
            actors.push(address(uint160(uint256(keccak256(abi.encode("nexus.v2.actor", i))))));
        }
    }

    /// @dev Todo timelock arranca en 0: submit del curador y ejecución inmediata (quien sea; timelocked() no mira el
    /// remitente).
    function _curated(bytes memory data) internal {
        vm.prank(CURATOR);
        vault.submit(data);
        (bool ok,) = address(vault).call(data);
        require(ok, "nexus: gov setUp");
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _give(address who, uint256 amount) internal {
        deal(address(token), who, token.balanceOf(who) + amount, true);
        vm.prank(who);
        token.approve(address(vault), type(uint256).max);
    }

    function _clamp(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + x % (hi - lo + 1);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

/// @notice Contabilidad fantasma y leyes V-... de Vault V2. Lee estado crudo del vault y los activos reales del
/// adapter/token; nunca sus vistas con devengamiento.
abstract contract NexusVaultV2Hunter is NexusVaultV2Base {
    using NexusV2Math for uint256;

    // op: qué hizo el handler (decide la ley y el delta sobre el devengamiento).
    uint8 internal constant OP_DEPOSIT = 1;
    uint8 internal constant OP_MINT = 2;
    uint8 internal constant OP_WITHDRAW = 3;
    uint8 internal constant OP_REDEEM = 4;
    uint8 internal constant OP_ACCRUE = 5; // accrue/earn/lose/setMaxRate/allocate: devengan, sin cambiar shares de usuario
    uint8 internal constant OP_TRANSFER = 6; // no devenga
    uint8 internal constant OP_DEALLOC = 7; // no devenga
    uint8 internal constant OP_NONE = 8;

    struct Snap {
        uint256 ts;
        uint256 TA; // _totalAssets crudo
        uint256 T; // totalSupply crudo
        uint256 R; // activos reales: balance del token en el vault + adapter.realAssets()
        uint256 lu; // lastUpdate
        uint256 mr; // maxRate
        uint256 fp; // performanceFee
        uint256 fg; // managementFee
        uint256[6] bal; // actors[0..3], PERF, MGMT
    }

    NexusV2Clock internal hClock;
    uint256 internal vShares; // acciones virtuales (immutable del vault)
    // métricas
    uint256 internal hLaws;
    uint256 internal hZeroMints;
    uint256 internal hMaxPrice;
    uint256 internal hYield;
    uint256 internal hLoss;
    uint256 internal hFeeShares;

    function _hunterInit() internal {
        hClock = new NexusV2Clock();
        vShares = vault.virtualShares();
    }

    function _hunterFlag(string memory what, uint256 x, uint256 y) internal virtual;

    function _bal(address who) internal view returns (uint256) {
        return vault.balanceOf(who);
    }

    function _snap() internal view returns (Snap memory s) {
        s.ts = hClock.time();
        s.TA = vault._totalAssets();
        s.T = vault.totalSupply();
        s.R = token.balanceOf(address(vault)) + adapter.realAssets();
        s.lu = vault.lastUpdate();
        s.mr = vault.maxRate();
        s.fp = vault.performanceFee();
        s.fg = vault.managementFee();
        for (uint256 i; i < 4; ++i) {
            s.bal[i] = vault.balanceOf(actors[i]);
        }
        s.bal[4] = vault.balanceOf(PERF);
        s.bal[5] = vault.balanceOf(MGMT);
    }

    /// @dev Devengamiento esperado (replica accrueInterestView): newTA, σ^p, σ^g. Sin gates (no hay en el harness),
    /// así que las comisiones se acuñan si hay base. Exacto con la misma semántica de redondeo (floor) del vault.
    function _expectAccrual(Snap memory p) internal view returns (uint256 newTA, uint256 sp, uint256 sg) {
        uint256 elapsed = p.ts - p.lu;
        uint256 maxTA = p.TA + NexusV2Math.mulDivDown(p.TA * elapsed, p.mr, WAD);
        newTA = NexusV2Math.min(p.R, maxTA);
        uint256 interest = NexusV2Math.zeroFloorSub(newTA, p.TA);
        uint256 fpA = (interest > 0 && p.fp > 0) ? NexusV2Math.mulDivDown(interest, p.fp, WAD) : 0;
        uint256 fgA = (elapsed > 0 && p.fg > 0) ? NexusV2Math.mulDivDown(newTA * elapsed, p.fg, WAD) : 0;
        uint256 noFees = newTA - fpA - fgA;
        sp = NexusV2Math.mulDivDown(fpA, p.T + vShares, noFees + 1);
        sg = NexusV2Math.mulDivDown(fgA, p.T + vShares, noFees + 1);
    }

    modifier hunted(uint8 op, address who, address to) {
        Snap memory pre = _snap();
        _;
        _hEnd(op, who, to, pre);
    }

    /// @dev Los montos se DERIVAN del cambio de estado observado (activos: cambio de R ocioso; acciones: cambio de
    /// balance), no de los argumentos del handler. Así una acción acotada a 0 es un no-op consistente: el vault igual
    /// devenga, y la ley lo ve con monto 0.
    function _hEnd(uint8 op, address who, address to, Snap memory pre) internal {
        Snap memory post = _snap();
        if (op == OP_NONE) return;

        if (op == OP_TRANSFER) {
            _lawTransfer(who, to, pre, post);
            _lawSolvency(post);
            return;
        }
        if (op == OP_DEALLOC) {
            // deallocate no devenga y es neutro en R: TA, T y R quedan igual (mueve adapter -> idle).
            if (post.TA != pre.TA) _hunterFlag("V-TA: deallocate cambio _totalAssets (antes, despues)", pre.TA, post.TA);
            if (post.T != pre.T) _hunterFlag("V-LEDGER: deallocate acuno o quemo acciones (antes, despues)", pre.T, post.T);
            if (post.R != pre.R) _hunterFlag("V-SOLV: deallocate cambio los activos reales (antes, despues)", pre.R, post.R);
            _lawSolvency(post);
            return;
        }

        // Ops que devengan (deposit/mint/withdraw/redeem/accrue/allocate/setMaxRate).
        (uint256 newTA, uint256 sp, uint256 sg) = _expectAccrual(pre);
        unchecked {
            hLaws += 4;
        }
        // V-FEE-1: acciones de comision = las del fantasma.
        uint256 gotP = post.bal[4] - pre.bal[4];
        uint256 gotG = post.bal[5] - pre.bal[5];
        if (gotP != sp) _hunterFlag("V-FEE-1: comision de performance distinta del modelo (modelo, real)", sp, gotP);
        if (gotG != sg) _hunterFlag("V-FEE-1: comision de gestion distinta del modelo (modelo, real)", sg, gotG);
        hFeeShares += sp + sg;

        uint256 ta = pre.T + sp + sg + vShares; // totalSupply + virtuales tras acuñar comision
        uint256 d1 = newTA + 1;
        uint256 inAssets = NexusV2Math.zeroFloorSub(post.R, pre.R); // deposit/mint: lo ocioso sube
        uint256 outAssets = NexusV2Math.zeroFloorSub(pre.R, post.R); // withdraw/redeem: baja

        // V-TA-1: el _totalAssets tras devengar (observado menos el delta de la accion) = min(R, TA + tope).
        uint256 taAccrued = post.TA + outAssets - inAssets; // reconstruido de lo observado
        uint256 maxTA = pre.TA + NexusV2Math.mulDivDown(pre.TA * (pre.ts - pre.lu), pre.mr, WAD);
        if (taAccrued != NexusV2Math.min(pre.R, maxTA)) {
            _hunterFlag("V-TA-1: devengamiento fuera del modelo (modelo, real)", NexusV2Math.min(pre.R, maxTA), taAccrued);
        }

        if (op == OP_DEPOSIT) {
            uint256 s = _userDelta(who, pre, post);
            _lawEnterShares(s, inAssets, ta, d1);
            _lawLedger(post, pre.T + sp + sg + s);
            if (s == 0 && inAssets != 0) ++hZeroMints;
        } else if (op == OP_MINT) {
            uint256 s = _userDelta(who, pre, post);
            // V-INF-1 mint: aIn = ⌈s·(TA+1)/(T+v)⌉ exacto.
            if (inAssets != NexusV2Math.mulDivUp(s, d1, ta)) {
                _hunterFlag("V-INF-1: mint cobro distinto del techo (modelo, real)", NexusV2Math.mulDivUp(s, d1, ta), inAssets);
            }
            _lawLedger(post, pre.T + sp + sg + s);
        } else if (op == OP_WITHDRAW) {
            uint256 sOut = _userBurned(who, pre, post);
            // V-INF-1 withdraw: sOut = ⌈a·(T+v)/(TA+1)⌉ exacto.
            if (sOut != NexusV2Math.mulDivUp(outAssets, ta, d1)) {
                _hunterFlag("V-INF-1: withdraw quemo distinto del techo (modelo, real)", NexusV2Math.mulDivUp(outAssets, ta, d1), sOut);
            }
            _lawLedger(post, pre.T + sp + sg - sOut);
        } else if (op == OP_REDEEM) {
            uint256 s = _userBurned(who, pre, post);
            // V-INF-1 redeem: aOut = ⌊s·(TA+1)/(T+v)⌋ exacto.
            if (outAssets != NexusV2Math.mulDivDown(s, d1, ta)) {
                _hunterFlag("V-INF-1: redeem pago distinto del piso (modelo, real)", NexusV2Math.mulDivDown(s, d1, ta), outAssets);
            }
            _lawLedger(post, pre.T + sp + sg - s);
        } else {
            // OP_ACCRUE: sin cambio de acciones de usuario ni de activos.
            _lawLedger(post, pre.T + sp + sg);
        }

        _lawSolvency(post);
        ++checks;
    }

    function _userDelta(address who, Snap memory pre, Snap memory post) internal view returns (uint256) {
        uint256 i = _idx(who);
        return post.bal[i] >= pre.bal[i] ? post.bal[i] - pre.bal[i] : 0;
    }

    function _userBurned(address who, Snap memory pre, Snap memory post) internal view returns (uint256) {
        uint256 i = _idx(who);
        return pre.bal[i] >= post.bal[i] ? pre.bal[i] - post.bal[i] : 0;
    }

    function _idx(address who) internal view returns (uint256) {
        for (uint256 i; i < 4; ++i) {
            if (actors[i] == who) return i;
        }
        return 0;
    }

    /// @dev V-INF-1 deposit: s·(TA+1) <= a·(T+v) < (s+1)·(TA+1).
    function _lawEnterShares(uint256 s, uint256 a, uint256 ta, uint256 d1) internal {
        if (!NexusV2Math.geq(a, ta, s, d1)) {
            _hunterFlag("V-INF-1: deposit emitio mas que a*(T+v)/(TA+1) (justas, emitidas)", NexusV2Math.mulDivDown(a, ta, d1), s);
        } else if (NexusV2Math.geq(a, ta, s + 1, d1)) {
            _hunterFlag("V-INF-1: deposit emitio menos que el piso (justas, emitidas)", NexusV2Math.mulDivDown(a, ta, d1), s);
        }
    }

    /// @dev V-LEDGER: totalSupply observado == el esperado (comision + acciones de usuario, sin acciones fantasma).
    function _lawLedger(Snap memory post, uint256 expT) internal {
        if (post.T != expT) _hunterFlag("V-LEDGER: totalSupply distinto del esperado (esperado, real)", expT, post.T);
    }

    /// @dev V-SOLV-1: lo reclamable (todas las acciones a precio de redeem) <= activos reales.
    function _lawSolvency(Snap memory post) internal {
        uint256 claim = NexusV2Math.mulDivDown(post.T, post.TA + 1, post.T + vShares);
        if (claim > post.R) _hunterFlag("V-SOLV-1: lo reclamable supera los activos reales (reclamable, reales)", claim, post.R);
        uint256 price = NexusV2Math.mulDivUp(1, post.TA + 1, post.T + vShares);
        if (price > hMaxPrice) hMaxPrice = price;
    }

    /// @dev Transferencia: no devenga (V2 no acumula en transfer); solo mueve acciones entre balances. Lo que sale del
    /// emisor entra al receptor, y ni TA ni T cambian.
    function _lawTransfer(address from, address to, Snap memory pre, Snap memory post) internal {
        if (post.TA != pre.TA) _hunterFlag("V-FEE: una transferencia devengo (antes, despues)", pre.TA, post.TA);
        if (post.T != pre.T) _hunterFlag("V-LEDGER: una transferencia cambio totalSupply (antes, despues)", pre.T, post.T);
        unchecked {
            hLaws += 2;
        }
        if (from == to) return;
        uint256 sent = NexusV2Math.zeroFloorSub(pre.bal[_idx(from)], post.bal[_idx(from)]);
        uint256 got = NexusV2Math.zeroFloorSub(post.bal[_idx(to)], pre.bal[_idx(to)]);
        if (sent != got) _hunterFlag("V-LEDGER: una transferencia creo o destruyo acciones (salieron, entraron)", sent, got);
    }

    /* VERIFICACIÓN */

    function check() external view returns (string memory) {
        if (violations != 0) return firstViolation;
        return "";
    }

    function hunterStats()
        external
        view
        returns (uint256 laws, uint256 checks_, uint256 zeroMints, uint256 maxPrice, uint256 feeShares)
    {
        return (hLaws, checks, hZeroMints, hMaxPrice, hFeeShares);
    }
}
