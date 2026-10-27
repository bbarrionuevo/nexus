// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// Cazador de vulnerabilidades para Morpho Vault V2 (variante A: VaultV2 + NexusAdapterMock).
//
// Contabilidad fantasma y leyes exactas evaluadas tras cada acción del handler, al estilo del cazador de MetaMorpho
// (NexusVulnerabilityHunter.sol) pero con la contabilidad de V2: devengamiento con tope de tasa, dos comisiones,
// realización de pérdidas y topes. El modelo formal y las demostraciones están en docs/CAZADOR_VAULT_V2.md (leyes V-...).
//
// El fantasma NO usa los métodos de vista del vault (totalAssets, previewX, accrueInterestView): esos son lo que se
// audita. Lee solo estado crudo (los getters de variables públicas: _totalAssets, totalSupply, lastUpdate, maxRate,
// las comisiones y balanceOf) y los activos reales desde fuera del vault (el token y el adapter).
//
// Ninguna ley revierte: las invariantes corren con fail_on_revert = false, así que si el cazador revirtiera, la acción
// entera se contaría como una reversión más y la violación quedaría oculta.

import {Test} from "../../lib/forge-std/src/Test.sol";
import {VaultV2} from "../../src/VaultV2.sol";
import {VaultV2Factory} from "../../src/VaultV2Factory.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {IAdapter} from "../../src/interfaces/IAdapter.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

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

/// @notice Adapter de prueba que cumple la especificación de adapters de VaultV2 (NatSpec "ADAPTERS"):
/// - `realAssets()` es su saldo del token: todo lo que informa está respaldado y se puede desasignar;
/// - cada allocate/deallocate informa `change` = posición nueva − posición anterior, así que Σ changes = la posición
///   y la `allocation` del vault es la posición real.
/// El AdapterMock del repo no cumple lo segundo: suma `interest − loss` en cada llamada, la allocation se desvía de la
/// posición y, tras una pérdida, una desasignación puede dejar `realAssets()` en underflow. El handler le acredita
/// rendimiento o le quita tokens (pérdida) con `deal`, así que el fantasma conoce los activos reales exacto.
contract NexusAdapterMock is IAdapter {
    address public immutable vault;
    address public immutable asset;
    uint256 public position;
    bytes32[] internal ids;

    constructor(address _vault, address _asset) {
        vault = _vault;
        asset = _asset;
        IERC20(_asset).approve(_vault, type(uint256).max);
        ids.push(keccak256("id-0"));
        ids.push(keccak256("id-1"));
    }

    function realAssets() external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /// @dev El vault ya transfirió los activos: la posición nueva es el saldo.
    function allocate(bytes memory, uint256, bytes4, address) external returns (bytes32[] memory, int256) {
        require(msg.sender == vault, "nexus: solo el vault");
        return (ids, _update(IERC20(asset).balanceOf(address(this))));
    }

    /// @dev El vault retira `assets` después de esta llamada: la posición nueva es el saldo menos `assets`.
    function deallocate(bytes memory, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        require(msg.sender == vault, "nexus: solo el vault");
        return (ids, _update(IERC20(asset).balanceOf(address(this)) - assets));
    }

    function _update(uint256 newPosition) internal returns (int256 change) {
        change = int256(newPosition) - int256(position);
        position = newPosition;
    }
}

/// @notice Base del harness de Vault V2: despliega el vault con un NexusAdapterMock, roles, topes y la comisión elegida.
abstract contract NexusVaultV2Base is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_MAX_RATE = 200e16 / uint256(365 days);
    uint256 internal constant MAX_PERFORMANCE_FEE = 0.5e18;
    uint256 internal constant MAX_MANAGEMENT_FEE = 0.05e18 / uint256(365 days);
    uint256 internal constant MAX_ASSETS = 1e28;
    uint256 internal constant ABS_CAP = 1e30;
    /// @dev Tope relativo de id-0 (id-1 queda sin tope relativo, WAD). Sin subirlo, el tope relativo vale 0 y el vault
    /// rechaza toda asignación (RelativeCapExceeded): hasta el 27-oct el 98 % de los allocate del harness revertía.
    uint256 internal constant REL_CAP_0 = 0.9e18;

    address internal constant OWNER = address(uint160(uint256(keccak256("nexus.v2.owner"))));
    address internal constant CURATOR = address(uint160(uint256(keccak256("nexus.v2.curator"))));
    address internal constant ALLOCATOR = address(uint160(uint256(keccak256("nexus.v2.allocator"))));
    address internal constant PERF = address(uint160(uint256(keccak256("nexus.v2.perf"))));
    address internal constant MGMT = address(uint160(uint256(keccak256("nexus.v2.mgmt"))));

    VaultV2 internal vault;
    ERC20Mock internal token;
    NexusAdapterMock internal adapter;
    bytes internal idData0 = "id-0";
    bytes internal idData1 = "id-1";

    address[] internal actors;
    uint256 internal violations;
    uint256 internal lawMask; // bit por ley violada (L_...)
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
        adapter = new NexusAdapterMock(address(vault), address(token));
        _curated(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        _curated(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData0, ABS_CAP)));
        _curated(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData1, ABS_CAP)));
        _curated(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData0, REL_CAP_0)));
        _curated(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData1, WAD)));

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
    // op: qué hizo el handler (decide la ley y el delta sobre el devengamiento).
    uint8 internal constant OP_DEPOSIT = 1;
    uint8 internal constant OP_MINT = 2;
    uint8 internal constant OP_WITHDRAW = 3;
    uint8 internal constant OP_REDEEM = 4;
    uint8 internal constant OP_ACCRUE = 5; // accrue/earn/lose/setMaxRate/allocate: devengan, sin cambiar shares de usuario
    uint8 internal constant OP_TRANSFER = 6; // no devenga
    uint8 internal constant OP_DEALLOC = 7; // no devenga
    uint8 internal constant OP_NONE = 8;

    // Leyes (bit de lawMask). Se informan todas las que fallan, no solo la primera: así cada mutación de referencia
    // muestra qué leyes la ven.
    uint8 internal constant L_TA = 0; // V-TA-1
    uint8 internal constant L_FEE = 1; // V-FEE-1
    uint8 internal constant L_INF1 = 2; // V-INF-1
    uint8 internal constant L_INF2 = 3; // V-INF-2
    uint8 internal constant L_LOSS1 = 4; // V-LOSS-1
    uint8 internal constant L_LOSS2 = 5; // V-LOSS-2
    uint8 internal constant L_LEDGER = 6; // V-LEDGER
    uint8 internal constant L_SOLV = 7; // V-SOLV-1
    uint8 internal constant N_LAWS = 8;

    uint256 internal constant NONE = 6; // _idx de una cuenta que no se sigue

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
    // métricas (por corrida: el estado vuelve al de setUp en cada una)
    uint256 internal hLaws;
    uint256 internal hZeroMints;
    uint256 internal hMaxPrice;
    uint256 internal hLoss; // activos quitados al adapter por el handler
    uint256 internal hFeeShares;
    uint256 internal hLosses; // devengamientos que realizaron una pérdida (premisa de V-LOSS)
    uint256 internal hLossAssets; // activos de pérdida realizados (_TA − R en esos devengamientos)
    uint256 internal hFeeDrops; // devengamientos sin pérdida en que el precio bajó (solo la comisión de gestión puede)
    uint256 internal hAllocs;
    uint256 internal hDeallocs;
    uint256 internal hTransfers;

    function _hunterInit() internal {
        hClock = new NexusV2Clock();
        vShares = vault.virtualShares();
    }

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

    /// @dev Comisiones en activos sobre un _totalAssets devengado A (como accrueInterestView): F^p sobre el interés
    /// A ⊖ _TA, F^g sobre A·Δt. Sin gates en el harness, los receptores siempre pueden recibir acciones.
    function _feeAssets(Snap memory p, uint256 A) internal pure returns (uint256 fpA, uint256 fgA) {
        uint256 elapsed = p.ts - p.lu;
        uint256 interest = NexusV2Math.zeroFloorSub(A, p.TA);
        fpA = (interest > 0 && p.fp > 0) ? NexusV2Math.mulDivDown(interest, p.fp, WAD) : 0;
        fgA = (elapsed > 0 && p.fg > 0) ? NexusV2Math.mulDivDown(A * elapsed, p.fg, WAD) : 0;
    }

    /// @dev Devengamiento esperado (replica accrueInterestView): newTA, σ^p, σ^g. Exacto con la misma semántica de
    /// redondeo (floor) del vault.
    function _expectAccrual(Snap memory p) internal view returns (uint256 newTA, uint256 sp, uint256 sg) {
        uint256 maxTA = p.TA + NexusV2Math.mulDivDown(p.TA * (p.ts - p.lu), p.mr, WAD);
        newTA = NexusV2Math.min(p.R, maxTA);
        (uint256 fpA, uint256 fgA) = _feeAssets(p, newTA);
        uint256 noFees = NexusV2Math.zeroFloorSub(newTA, fpA + fgA);
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
        if (op == OP_TRANSFER || op == OP_DEALLOC) _lawsNoAccrual(op, who, to, pre, post);
        else _lawsAccruing(op, who, pre, post);
    }

    /// @dev transfer y deallocate no devengan: TA, T y R no cambian (deallocate mueve activos del adapter a lo ocioso);
    /// una transferencia mueve exactamente lo que sale del emisor al receptor.
    function _lawsNoAccrual(uint8 op, address who, address to, Snap memory pre, Snap memory post) internal {
        _ok(post.TA == pre.TA, L_TA, "una operacion sin devengamiento cambio _totalAssets (antes, despues)", pre.TA, post.TA);
        _ok(post.T == pre.T, L_LEDGER, "una operacion sin devengamiento cambio totalSupply (antes, despues)", pre.T, post.T);
        _ok(post.R == pre.R, L_SOLV, "una operacion sin devengamiento cambio los activos reales (antes, despues)", pre.R, post.R);
        if (op == OP_TRANSFER && who != to) {
            uint256 sent = NexusV2Math.zeroFloorSub(pre.bal[_idx(who)], post.bal[_idx(who)]);
            uint256 got = NexusV2Math.zeroFloorSub(post.bal[_idx(to)], pre.bal[_idx(to)]);
            _ok(sent == got, L_LEDGER, "una transferencia creo o destruyo acciones (salieron, entraron)", sent, got);
        }
        _lawPriceOp(pre.TA, pre.T, post);
        _lawBystanders(pre, post, who, to, false);
        _lawSolvency(post);
    }

    /// @dev deposit/mint/withdraw/redeem y las acciones que solo devengan. El estado observado se descompone en el
    /// devengamiento (A = _totalAssets y S = totalSupply justo después, con las comisiones ya acuñadas) y la acción.
    function _lawsAccruing(uint8 op, address who, Snap memory pre, Snap memory post) internal {
        bool loss = pre.R < pre.TA; // premisa de V-LOSS: pérdida sin realizar al empezar la transacción
        bool enters = op == OP_DEPOSIT || op == OP_MINT;
        bool exits = op == OP_WITHDRAW || op == OP_REDEEM;
        uint256 inA = NexusV2Math.zeroFloorSub(post.R, pre.R); // deposit/mint: lo ocioso sube
        uint256 outA = NexusV2Math.zeroFloorSub(pre.R, post.R); // withdraw/redeem: baja
        uint256 sUser = enters ? _userDelta(who, pre, post) : (exits ? _userBurned(who, pre, post) : 0);

        if (post.TA + outA < inA || (enters && post.T < sUser)) {
            _ok(false, L_TA, "el estado no se descompone en devengamiento + accion (_totalAssets, totalSupply)", post.TA, post.T);
            return;
        }
        uint256 A = post.TA + outA - inA;
        uint256 S = enters ? post.T - sUser : post.T + sUser;
        uint256 gotP = NexusV2Math.zeroFloorSub(post.bal[4], pre.bal[4]);
        uint256 gotG = NexusV2Math.zeroFloorSub(post.bal[5], pre.bal[5]);
        (uint256 newTA, uint256 sp, uint256 sg) = _expectAccrual(pre);

        if (loss) _lawLoss(pre, A, gotP);

        // V-TA-1: A = min(R, _TA + ⌊_TA·Δt·maxRate/W⌋) bit a bit, y lastUpdate en la hora del devengamiento.
        _ok(A == newTA, L_TA, "devengamiento fuera del modelo (modelo, real)", newTA, A);
        _ok(post.lu == pre.ts, L_TA, "lastUpdate no quedo en la hora del devengamiento (hora, lastUpdate)", pre.ts, post.lu);
        // V-FEE-1: acciones de comisión = las del fantasma.
        _ok(gotP == sp, L_FEE, "comision de performance distinta del modelo (modelo, real)", sp, gotP);
        _ok(gotG == sg, L_FEE, "comision de gestion distinta del modelo (modelo, real)", sg, gotG);
        hFeeShares += gotP + gotG;

        _lawPriceAccrual(pre, A, S, loss);
        _lawConversion(op, sUser, inA, outA, pre.T + sp + sg + vShares, newTA + 1);
        uint256 expT = exits ? NexusV2Math.zeroFloorSub(pre.T + sp + sg, sUser) : pre.T + sp + sg + sUser;
        _ok(post.T == expT, L_LEDGER, "totalSupply distinto del esperado (esperado, real)", expT, post.T);
        _lawPriceOp(A, S, post);
        _lawBystanders(pre, post, who, address(0), loss);
        _lawSolvency(post);
        ++checks;
    }

    /// @dev V-LOSS-1: con una pérdida sin realizar al empezar la transacción (R < _TA), el primer devengamiento la
    /// realiza entera, A = R exacto (maxTA ≥ _TA > R, así que min(R, maxTA) = R), y no hay comisión de performance
    /// (el interés es 0).
    function _lawLoss(Snap memory pre, uint256 A, uint256 gotP) internal {
        _ok(A == pre.R, L_LOSS1, "la perdida no se realizo entera en el primer devengamiento (reales, _totalAssets)", pre.R, A);
        _ok(gotP == 0, L_LOSS1, "comision de performance con perdida (esperadas, acciones)", 0, gotP);
        ++hLosses;
        hLossAssets += pre.TA - pre.R;
    }

    /// @dev V-INF-2 en el devengamiento. Con T = totalSupply antes, A y S después, las comisiones evaluadas sobre el A
    /// observado, N = A − F^p − F^g y q = ⌊(A+1)(T+v)/(N+1)⌋:
    ///   (a) q − 1 ≤ S + v ≤ q: las acciones de comisión valen F^p + F^g, salvo los dos pisos;
    ///   (c) (A+1)(T+v) ≥ (min(_TA, R) ⊖ F^g + 1)(S+v): el precio solo baja por la pérdida realizada y por F^g.
    /// Demostración en docs/CAZADOR_VAULT_V2.md, §4.
    function _lawPriceAccrual(Snap memory pre, uint256 A, uint256 S, bool loss) internal {
        (uint256 fpA, uint256 fgA) = _feeAssets(pre, A);
        uint256 tv = pre.T + vShares;
        uint256 sv = S + vShares;
        uint256 q = NexusV2Math.mulDivDown(A + 1, tv, NexusV2Math.zeroFloorSub(A, fpA + fgA) + 1);
        _ok(sv <= q, L_INF2, "las comisiones se llevaron mas que F^p+F^g (acciones maximas, observadas)", q - vShares, S);
        _ok(sv + 1 >= q, L_INF2, "las comisiones se llevaron menos que F^p+F^g (acciones minimas, observadas)", NexusV2Math.zeroFloorSub(q, vShares + 1), S);
        uint256 floor1 = NexusV2Math.zeroFloorSub(NexusV2Math.min(pre.TA, pre.R), fgA) + 1;
        _ok(
            NexusV2Math.geq(A + 1, tv, floor1, sv),
            L_INF2,
            "el precio bajo mas que la perdida y la comision de gestion (piso*1e18, precio*1e18)",
            NexusV2Math.mulDivDown(floor1, WAD, tv),
            NexusV2Math.mulDivDown(A + 1, WAD, sv)
        );
        if (!loss && !NexusV2Math.geq(A + 1, tv, pre.TA + 1, sv)) ++hFeeDrops;
    }

    /// @dev V-INF-2 en la operación: ninguna acción baja el precio respecto del estado ya devengado,
    /// (A'+1)(S+v) ≥ (A+1)(S'+v). Sale de los redondeos: deposit y redeem al piso, mint y withdraw al techo.
    function _lawPriceOp(uint256 A, uint256 S, Snap memory post) internal {
        _ok(
            NexusV2Math.geq(post.TA + 1, S + vShares, A + 1, post.T + vShares),
            L_INF2,
            "la operacion bajo el precio de la accion (precio*1e18 antes, despues)",
            NexusV2Math.mulDivDown(A + 1, WAD, S + vShares),
            NexusV2Math.mulDivDown(post.TA + 1, WAD, post.T + vShares)
        );
    }

    /// @dev V-INF-1: las cuatro conversiones contra el estado devengado del fantasma (ta = T⁺ + v, d1 = TA + 1).
    function _lawConversion(uint8 op, uint256 s, uint256 inA, uint256 outA, uint256 ta, uint256 d1) internal {
        if (op == OP_DEPOSIT) {
            // s·(TA+1) ≤ a·(T+v) < (s+1)·(TA+1)
            uint256 fair = NexusV2Math.mulDivDown(inA, ta, d1);
            _ok(NexusV2Math.geq(inA, ta, s, d1), L_INF1, "deposit emitio mas que a*(T+v)/(TA+1) (justas, emitidas)", fair, s);
            _ok(!NexusV2Math.geq(inA, ta, s + 1, d1), L_INF1, "deposit emitio menos que el piso (justas, emitidas)", fair, s);
            if (s == 0 && inA != 0) ++hZeroMints;
        } else if (op == OP_MINT) {
            uint256 exp = NexusV2Math.mulDivUp(s, d1, ta);
            _ok(inA == exp, L_INF1, "mint cobro distinto del techo (modelo, real)", exp, inA);
        } else if (op == OP_WITHDRAW) {
            uint256 exp = NexusV2Math.mulDivUp(outA, ta, d1);
            _ok(s == exp, L_INF1, "withdraw quemo distinto del techo (modelo, real)", exp, s);
        } else if (op == OP_REDEEM) {
            uint256 exp = NexusV2Math.mulDivDown(s, d1, ta);
            _ok(outA == exp, L_INF1, "redeem pago distinto del piso (modelo, real)", exp, outA);
        }
    }

    /// @dev V-LOSS-2 (si la acción realizó una pérdida) y V-LEDGER: fuera de quien opera (`who` y, en una
    /// transferencia, `to`), ningún saldo cambia, salvo los de comisión, que solo pueden subir: la pérdida se reparte en
    /// el valor de las acciones, no en los saldos. Y todas las acciones están en las cuentas seguidas (Σ = totalSupply).
    function _lawBystanders(Snap memory pre, Snap memory post, address who, address to, bool loss) internal {
        uint8 law = loss ? L_LOSS2 : L_LEDGER;
        uint256 w = _idx(who);
        uint256 t = _idx(to);
        uint256 sum;
        for (uint256 k; k < 6; ++k) {
            unchecked {
                sum += post.bal[k];
            }
            if (k == w || k == t) continue;
            if (k < 4) {
                _ok(post.bal[k] == pre.bal[k], law, "cambio el saldo de un tercero (antes, despues)", pre.bal[k], post.bal[k]);
            } else {
                _ok(post.bal[k] >= pre.bal[k], law, "bajo el saldo de un receptor de comision (antes, despues)", pre.bal[k], post.bal[k]);
            }
        }
        _ok(sum == post.T, L_LEDGER, "la suma de los saldos no es totalSupply (suma, totalSupply)", sum, post.T);
    }

    /// @dev V-SOLV-1: lo reclamable (todas las acciones a precio de redeem) <= activos reales.
    function _lawSolvency(Snap memory post) internal {
        uint256 claim = NexusV2Math.mulDivDown(post.T, post.TA + 1, post.T + vShares);
        _ok(claim <= post.R, L_SOLV, "lo reclamable supera los activos reales (reclamable, reales)", claim, post.R);
        uint256 price = NexusV2Math.mulDivUp(1, post.TA + 1, post.T + vShares);
        if (price > hMaxPrice) hMaxPrice = price;
    }

    function _userDelta(address who, Snap memory pre, Snap memory post) internal view returns (uint256) {
        uint256 i = _idx(who);
        if (i == NONE) return 0;
        return NexusV2Math.zeroFloorSub(post.bal[i], pre.bal[i]);
    }

    function _userBurned(address who, Snap memory pre, Snap memory post) internal view returns (uint256) {
        uint256 i = _idx(who);
        if (i == NONE) return 0;
        return NexusV2Math.zeroFloorSub(pre.bal[i], post.bal[i]);
    }

    /// @dev Índice en Snap.bal de un actor; NONE para cualquier otra cuenta (address(0) en las acciones sin actor).
    function _idx(address who) internal view returns (uint256) {
        for (uint256 i; i < 4; ++i) {
            if (actors[i] == who) return i;
        }
        return NONE;
    }

    /* REGISTRO DE VIOLACIONES */

    function _ok(bool cond, uint8 law, string memory what, uint256 x, uint256 y) internal {
        unchecked {
            ++hLaws;
        }
        if (!cond) _hunterFlag(law, what, x, y);
    }

    function _hunterFlag(uint8 law, string memory what, uint256 x, uint256 y) internal {
        lawMask |= uint256(1) << law;
        if (violations++ == 0) {
            firstViolation = string(abi.encodePacked(_lawName(law), ": ", what, ": ", _str(x), ", ", _str(y)));
        }
    }

    function _lawName(uint8 law) internal pure returns (string memory) {
        if (law == L_TA) return "V-TA-1";
        if (law == L_FEE) return "V-FEE-1";
        if (law == L_INF1) return "V-INF-1";
        if (law == L_INF2) return "V-INF-2";
        if (law == L_LOSS1) return "V-LOSS-1";
        if (law == L_LOSS2) return "V-LOSS-2";
        if (law == L_LEDGER) return "V-LEDGER";
        return "V-SOLV-1";
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

    /* VERIFICACIÓN */

    /// @notice "" si ninguna ley falló; si no, la primera violación y la lista de todas las leyes que fallaron.
    function check() external view returns (string memory) {
        if (violations == 0) return "";
        string memory list;
        for (uint8 l; l < N_LAWS; ++l) {
            if (lawMask & (uint256(1) << l) != 0) list = string(abi.encodePacked(list, bytes(list).length == 0 ? "" : " ", _lawName(l)));
        }
        return string(abi.encodePacked(firstViolation, " [leyes: ", list, "]"));
    }

    function hunterStats()
        external
        view
        returns (uint256 laws, uint256 checks_, uint256 zeroMints, uint256 maxPrice, uint256 feeShares)
    {
        return (hLaws, checks, hZeroMints, hMaxPrice, hFeeShares);
    }

    /// @notice Cobertura de la corrida: pérdidas realizadas, bajas de precio sin pérdida y acciones con efecto.
    function coverage()
        external
        view
        returns (
            uint256 losses,
            uint256 lossAssets,
            uint256 feeDrops,
            uint256 allocs,
            uint256 deallocs,
            uint256 transfers
        )
    {
        return (hLosses, hLossAssets, hFeeDrops, hAllocs, hDeallocs, hTransfers);
    }
}
