// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

// Cazador de vulnerabilidades de TokenizedStrategy de Yearn V3 (yearn/tokenized-strategy @ v3.1.0: el
// src/TokenizedStrategy.sol verificado en 0x310f…1e76, en alcance en Immunefi, es byte a byte el del tag). Una
// estrategia de prueba sobre BaseStrategy con una fuente de rendimiento que maneja el handler: el fantasma lee el
// almacenamiento crudo y predice cada operación de forma exacta, en los dos modos de la v3.1.0 (contabilidad por
// reporte y "constant accrual" en vivo). Leyes Y-... en 512 bits (docs/CAZADOR_TOKENIZED_STRATEGY.md).
//
// Compila sin via_ir (como el repo: solc 0.8.18, 200 runs, paris): funciones chicas y estructuras en memoria.

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BaseStrategy} from "../../src/BaseStrategy.sol";
import {TokenizedStrategy} from "../../src/TokenizedStrategy.sol";
import {TokenizedStrategyLib} from "../../src/libraries/TokenizedStrategyLib.sol";
import {ITokenizedStrategy} from "../../src/interfaces/ITokenizedStrategy.sol";

/// @dev Aritmética de 512 bits: comparar dos precios sin esconder 1 wei y replicar Math.mulDiv de OpenZeppelin.
library NexusTSMath {
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

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

/// @notice Reloj del harness: block.timestamp leído en una llamada externa.
contract NexusTSClock {
    function time() external view returns (uint256) {
        return block.timestamp;
    }
}

/// @notice Token de prueba con decimales configurables (el handler acuña con `deal`).
contract NexusTSToken is ERC20 {
    uint8 internal immutable dec;

    constructor(uint8 d) ERC20("nexus asset", "NXA") {
        dec = d;
    }

    function decimals() public view override returns (uint8) {
        return dec;
    }
}

/// @notice Fábrica de prueba: solo la configuración de la comisión del protocolo que lee TokenizedStrategy.
contract NexusTSFactory {
    uint16 public feeBps;
    address public recipient;

    constructor(uint16 bps, address r) {
        feeBps = bps;
        recipient = r;
    }

    function setFee(uint16 bps) external {
        feeBps = bps;
    }

    function protocol_fee_config() external view returns (uint16, address) {
        return (feeBps, recipient);
    }
}

/// @notice Fuente de rendimiento de prueba. `balance()` es la estimación que ve la estrategia: cuenta la pérdida
/// pendiente (valor ya perdido que solo se realiza en la cosecha) y no cuenta las recompensas pendientes (que entran
/// en la cosecha). Solo se puede retirar el valor real, hasta un tope de liquidez. En cada depósito, retiro o
/// cosecha que pide la estrategia, lee sus vistas: tienen que estar congeladas en el estado previo a la operación.
contract NexusYieldSource {
    ERC20 public immutable asset;
    uint256 public immutable probeX;
    address public strategy;
    uint256 public pendingRewards;
    uint256 public pendingLoss;
    uint256 public liquidity = type(uint256).max;
    address public constant SINK = address(uint160(uint256(keccak256("nexus.ts.sink"))));

    uint256 public seenCount;
    uint256 public seenTA;
    uint256 public seenTS;
    uint256 public seenC2A;
    uint256 public seenC2S;
    uint256 public seenPD;
    uint256 public seenPR;

    constructor(ERC20 a, uint256 x) {
        asset = a;
        probeX = x;
    }

    function setStrategy(address s) external {
        require(strategy == address(0), "nexus: estrategia ya fijada");
        strategy = s;
    }

    function setLiquidity(uint256 l) external {
        liquidity = l;
    }

    function addPending(uint256 rewards, uint256 loss) external {
        pendingRewards += rewards;
        pendingLoss += loss;
    }

    function resetSeen() external {
        seenCount = 0;
    }

    /// @dev Valor real (retirable si hay liquidez): el saldo sin las recompensas ni la pérdida pendientes.
    function real() public view returns (uint256) {
        uint256 tok = asset.balanceOf(address(this));
        uint256 locked = pendingRewards + pendingLoss;
        return tok > locked ? tok - locked : 0;
    }

    function liquid() public view returns (uint256) {
        uint256 r = real();
        return r < liquidity ? r : liquidity;
    }

    function balance() public view returns (uint256) {
        uint256 tok = asset.balanceOf(address(this));
        return tok > pendingRewards ? tok - pendingRewards : 0;
    }

    function deposit(uint256 a) external {
        _look();
        asset.transferFrom(msg.sender, address(this), a);
    }

    function withdraw(uint256 a) external returns (uint256 got) {
        _look();
        uint256 l = liquid();
        got = a < l ? a : l;
        if (got > 0) asset.transfer(msg.sender, got);
    }

    function harvest() external {
        _look();
        uint256 l = pendingLoss;
        pendingRewards = 0;
        pendingLoss = 0;
        if (l > 0) asset.transfer(SINK, l);
    }

    function _look() internal {
        if (msg.sender != strategy) return;
        ITokenizedStrategy s = ITokenizedStrategy(strategy);
        seenTA = s.totalAssets();
        seenTS = s.totalSupply();
        seenC2A = s.convertToAssets(probeX);
        seenC2S = s.convertToShares(probeX);
        seenPD = s.previewDeposit(probeX);
        seenPR = s.previewRedeem(probeX);
        ++seenCount;
    }
}

/// @notice Estrategia de prueba sobre BaseStrategy (v3.1.0). Con `live` sobreescribe `_strategyTotalAssets()` con la
/// estimación en vivo (ociosos + fuente): el modo "constant accrual"; sin `live` usa el de BaseStrategy
/// (`lastTotalAssets`, la contabilidad por reporte de la v3.0.4). Las perillas las mueve el handler.
contract NexusTSStrategy is BaseStrategy {
    NexusYieldSource public immutable source;
    bool public immutable live;
    uint256 public deployBps = 10_000;
    uint256 public depositCap = type(uint256).max;
    bool public limitWithdrawals;

    constructor(address a, NexusYieldSource s, bool l) BaseStrategy(a, "nexus strategy") {
        source = s;
        live = l;
        ERC20(a).approve(address(s), type(uint256).max);
    }

    function setKnobs(uint256 bps, uint256 cap, bool lw) external {
        deployBps = bps;
        depositCap = cap;
        limitWithdrawals = lw;
    }

    function _put(uint256 amount) internal {
        uint256 d = (amount * deployBps) / 10_000;
        if (d > 0) source.deposit(d);
    }

    function _deployFunds(uint256 amount) internal override {
        _put(amount);
    }

    function _freeFunds(uint256 amount) internal override {
        source.withdraw(amount);
    }

    function _harvestAndReport() internal override returns (uint256) {
        source.harvest();
        if (!TokenizedStrategyLib.isShutdown()) _put(asset.balanceOf(address(this)));
        return asset.balanceOf(address(this)) + source.balance();
    }

    function _strategyTotalAssets() internal view override returns (uint256) {
        if (!live) return super._strategyTotalAssets();
        return asset.balanceOf(address(this)) + source.balance();
    }

    function availableDepositLimit(address) public view override returns (uint256) {
        uint256 cap = depositCap;
        if (cap == type(uint256).max) return cap;
        uint256 ta = TokenizedStrategyLib.totalAssets();
        return cap > ta ? cap - ta : 0;
    }

    function availableWithdrawLimit(address) public view override returns (uint256) {
        if (!limitWithdrawals) return type(uint256).max;
        return asset.balanceOf(address(this)) + source.liquid();
    }

    function _tend(uint256 idle) internal override {
        _put(idle);
    }

    function _emergencyWithdraw(uint256 amount) internal override {
        source.withdraw(amount);
    }
}

/// @notice Base del harness: token, fábrica, la implementación desplegada en la dirección que fija BaseStrategy
/// (vm.etch del código compilado acá, con la fábrica de prueba como inmutable), la fuente, la estrategia y los roles.
abstract contract NexusTSBase is Test {
    uint256 internal constant MAX_BPS = 10_000;
    uint256 internal constant EXT = 1_000_000_000_000; // MAX_BPS_EXTENDED
    uint256 internal constant MIN_SUPPLY = 1e3;
    uint256 internal constant MAX_FEE = 5_000;
    address internal constant TS_ADDR = 0x310f5Db015E9d6E542fd41bd4542640790791e76;
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    bytes32 internal constant SLOT = bytes32(uint256(keccak256("yearn.base.strategy.storage")) - 1);

    address internal constant MGMT = address(uint160(uint256(keccak256("nexus.ts.management"))));
    address internal constant KEEPER = address(uint160(uint256(keccak256("nexus.ts.keeper"))));
    address internal constant EMERGENCY = address(uint160(uint256(keccak256("nexus.ts.emergency"))));
    address internal constant FEE_A = address(uint160(uint256(keccak256("nexus.ts.fee.a"))));
    address internal constant FEE_B = address(uint160(uint256(keccak256("nexus.ts.fee.b"))));
    address internal constant PROTO = address(uint160(uint256(keccak256("nexus.ts.protocol"))));

    NexusTSToken internal token;
    NexusTSFactory internal factory;
    NexusYieldSource internal source;
    NexusTSStrategy internal strategy;
    ITokenizedStrategy internal ts;
    bool internal immutable LIVE;
    uint8 internal immutable DEC;
    /// @dev Monto máximo por acción: un millón de unidades del activo, escalado por sus decimales.
    uint256 internal immutable MAX_ASSETS;

    address[] internal actors;
    uint256 internal violations;
    uint256 internal lawMask;
    string internal firstViolation;

    constructor(bool live, uint8 dec, uint16 perfFee, uint16 protoFee) {
        LIVE = live;
        DEC = dec;
        MAX_ASSETS = 10 ** (uint256(dec) + 6);
        token = new NexusTSToken(dec);
        factory = new NexusTSFactory(protoFee, PROTO);
        TokenizedStrategy impl = new TokenizedStrategy(address(factory));
        vm.etch(TS_ADDR, address(impl).code);
        source = new NexusYieldSource(ERC20(address(token)), 10 ** uint256(dec));
        strategy = new NexusTSStrategy(address(token), source, live);
        require(strategy.tokenizedStrategyAddress() == TS_ADDR, "nexus: BaseStrategy apunta a otra implementacion");
        source.setStrategy(address(strategy));
        ts = ITokenizedStrategy(address(strategy));
        ts.setKeeper(KEEPER);
        ts.setEmergencyAdmin(EMERGENCY);
        ts.setPerformanceFeeRecipient(FEE_A);
        ts.setPerformanceFee(perfFee);
        ts.setPendingManagement(MGMT);
        vm.prank(MGMT);
        ts.acceptManagement();
        for (uint256 i; i < 4; ++i) {
            actors.push(address(uint160(uint256(keccak256(abi.encode("nexus.ts.actor", i))))));
            vm.prank(actors[i]);
            token.approve(address(strategy), type(uint256).max);
        }
    }

    function _clamp(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + x % (hi - lo + 1);
    }
}

/// @notice Contabilidad fantasma y leyes Y-... de TokenizedStrategy v3.1.0.
abstract contract NexusTSHunter is NexusTSBase {
    uint8 internal constant L_TA = 0; // Y-TA-1: lastTotalAssets y lastAccrual exactos
    uint8 internal constant L_SUP = 1; // Y-SUP-1: totalSupply crudo y saldos exactos (acciones muertas incluidas)
    uint8 internal constant L_LOCK = 2; // Y-LOCK-1: buffer, tasa, fecha y lastReport del desbloqueo exactos
    uint8 internal constant L_FEE = 3; // Y-FEE-1: acciones de comisión (desempeño y protocolo) exactas
    uint8 internal constant L_INF1 = 4; // Y-INF-1: conversiones de los usuarios exactas (acciones y activos)
    uint8 internal constant L_INF2 = 5; // Y-INF-2: el precio simulado no baja salvo pérdida o el piso
    uint8 internal constant L_VIEW = 6; // Y-VIEW-1: vistas y previews exactas, y las previews son la ejecución
    uint8 internal constant L_REENT = 7; // Y-REENT-1: vistas congeladas durante los callbacks
    uint8 internal constant L_FUNDS = 8; // Y-FUNDS: movimiento exacto del activo (ociosos, fuente, cosecha)
    uint8 internal constant L_LIVE = 9; // Y-LIVE: pasa si y solo si el modelo dice que pasa
    uint8 internal constant L_LEDGER = 10; // Y-LEDGER: Σ saldos crudos = totalSupply crudo; buffer con fecha
    uint8 internal constant N_LAWS = 11;

    uint256 internal constant NH = 8; // tenedores: actores 0..3, FEE_A, FEE_B, PROTO, DEAD
    uint256 internal constant H_FEE_A = 4;
    uint256 internal constant H_FEE_B = 5;
    uint256 internal constant H_PROTO = 6;
    uint256 internal constant H_DEAD = 7;

    /// @dev Foto del estado crudo: el almacenamiento de la estrategia (vm.load), la fuente, las perillas y los saldos.
    struct Snap {
        uint256 ts;
        uint256 L; // lastTotalAssets
        uint256 LA; // lastAccrual
        uint256 R; // profitUnlockingRate
        uint256 D; // fullProfitUnlockDate
        uint256 LR; // lastReport
        uint256 TS; // totalSupply crudo (incluye el buffer)
        uint256 B; // balances[estrategia] crudo: el buffer de acciones bloqueadas
        uint256 fee; // performanceFee
        uint256 T; // profitMaxUnlockTime (uint32 crudo)
        uint256 feeIdx; // tenedor que recibe la comisión de desempeño (H_FEE_A o H_FEE_B)
        bool paused;
        bool shutdown;
        uint256 pbps; // comisión del protocolo (fábrica)
        uint256 idle; // activo ocioso en la estrategia
        uint256 tok; // activo en la fuente
        uint256 pr; // recompensas pendientes de la fuente
        uint256 pl; // pérdida pendiente de la fuente
        uint256 liq; // tope de liquidez de la fuente
        uint256 bps; // deployBps
        uint256 cap; // depositCap
        bool limitW; // availableWithdrawLimit limitado a lo líquido
        uint256 sink; // activo realizado como pérdida en la cosecha
        uint256[8] bal; // saldos crudos de los tenedores
        uint256[4] cash; // activo de cada actor
    }

    /// @dev Resultado de un devengamiento del modelo.
    struct Acc {
        bool ran;
        uint256 profit;
        uint256 loss;
        uint256 dead;
        uint256 fees;
        uint256 feeShares;
        uint256 lockedBurn;
    }

    /// @dev Resultado de una operación de usuario del modelo; vL y vS son las vistas congeladas de los callbacks.
    struct Op {
        bool ok;
        uint256 assets;
        uint256 shares;
        uint256 loss;
        bool probe;
        uint256 vL;
        uint256 vS;
        Acc acc;
    }

    /// @dev Resultado de un reporte del modelo.
    struct Rep {
        bool ok;
        uint256 nw;
        uint256 profit;
        uint256 loss;
        uint256 fees;
        uint256 feeShares;
        uint256 stl;
        uint256 plt;
        uint256 period;
        uint256 vL;
        uint256 vS;
        Acc acc;
    }

    NexusTSClock internal hClock;

    // métricas (por corrida)
    uint256 internal hLaws;
    uint256 internal hLiveProfit; // devengamientos en vivo con ganancia y comisión
    uint256 internal hDead; // ganancias confiscadas al piso (acciones muertas)
    uint256 internal hLiveLoss; // devengamientos en vivo con pérdida
    uint256 internal hLockedBurn; // pérdidas que quemaron acciones bloqueadas
    uint256 internal hReportProfit;
    uint256 internal hReportLoss;
    uint256 internal hRelock; // reportes con desbloqueo previo pendiente (promedio ponderado)
    uint256 internal hWithdrawLoss; // retiros que le pasaron una pérdida al usuario
    uint256 internal hLatched; // operaciones en un bloque ya sincronizado con un cambio en vivo pendiente
    uint256 internal hRejected; // operaciones que el modelo predijo que revertían, y revirtieron
    uint256 internal hProbes; // callbacks con las vistas verificadas
    uint256 internal hFeeShares;

    function _hunterInit() internal {
        hClock = new NexusTSClock();
    }

    function _holder(uint256 h) internal view returns (address) {
        if (h < 4) return actors[h];
        if (h == H_FEE_A) return FEE_A;
        if (h == H_FEE_B) return FEE_B;
        if (h == H_PROTO) return PROTO;
        return DEAD;
    }

    function _word(uint256 off) internal view returns (uint256) {
        return uint256(vm.load(address(strategy), bytes32(uint256(SLOT) + off)));
    }

    function _rawBal(address who) internal view returns (uint256) {
        return uint256(vm.load(address(strategy), keccak256(abi.encode(who, uint256(SLOT) + 4))));
    }

    function _snap() internal view returns (Snap memory s) {
        s.ts = hClock.time();
        s.TS = _word(2);
        s.L = _word(6);
        s.R = _word(7);
        s.D = _word(8) & type(uint96).max;
        uint256 w9 = _word(9);
        s.T = w9 & type(uint32).max;
        s.fee = (w9 >> 32) & type(uint16).max;
        address rec = address(uint160(w9 >> 48));
        s.feeIdx = rec == FEE_A ? H_FEE_A : (rec == FEE_B ? H_FEE_B : 99);
        s.LR = _word(10) & type(uint96).max;
        uint256 w12 = _word(12);
        s.shutdown = ((w12 >> 168) & 0xff) != 0;
        s.paused = ((w12 >> 176) & 0xff) != 0;
        s.LA = (w12 >> 184) & type(uint72).max;
        s.B = _rawBal(address(strategy));
        for (uint256 h; h < NH; ++h) {
            s.bal[h] = _rawBal(_holder(h));
        }
        for (uint256 i; i < 4; ++i) {
            s.cash[i] = token.balanceOf(actors[i]);
        }
        (uint16 pb,) = factory.protocol_fee_config();
        s.pbps = pb;
        s.idle = token.balanceOf(address(strategy));
        s.tok = token.balanceOf(address(source));
        s.pr = source.pendingRewards();
        s.pl = source.pendingLoss();
        s.liq = source.liquidity();
        s.bps = strategy.deployBps();
        s.cap = strategy.depositCap();
        s.limitW = strategy.limitWithdrawals();
        s.sink = token.balanceOf(source.SINK());
    }

    function _copy(Snap memory s) internal pure returns (Snap memory) {
        return abi.decode(abi.encode(s), (Snap));
    }

    /* MODELO (TokenizedStrategy.sol @ v3.1.0, con la aritmética exacta del fantasma) */

    function _mint(Snap memory m, uint256 h, uint256 x) internal pure {
        m.TS += x;
        m.bal[h] += x;
    }

    function _burn(Snap memory m, uint256 h, uint256 x) internal pure {
        m.bal[h] -= x;
        m.TS -= x;
    }

    function _mintB(Snap memory m, uint256 x) internal pure {
        m.TS += x;
        m.B += x;
    }

    function _burnB(Snap memory m, uint256 x) internal pure {
        m.B -= x;
        m.TS -= x;
    }

    /// @dev _unlockedShares: lineal hasta la fecha; después, todo el buffer.
    function _unl(Snap memory s) internal pure returns (uint256 u) {
        if (s.D > s.ts) {
            unchecked {
                u = (s.R * (s.ts - s.LR)) / EXT;
            }
        } else if (s.D != 0) {
            u = s.B;
        }
    }

    /// @dev _totalSupply: el crudo menos lo desbloqueado.
    function _eff(Snap memory s) internal pure returns (uint256) {
        return s.TS - _unl(s);
    }

    function _c2s(uint256 a, uint256 sup, uint256 ta, bool up) internal pure returns (uint256) {
        if (sup == 0) return a;
        if (ta == 0) return 0;
        return up ? NexusTSMath.mulDivUp(a, sup, ta) : NexusTSMath.mulDivDown(a, sup, ta);
    }

    function _c2a(uint256 sh, uint256 sup, uint256 ta, bool up) internal pure returns (uint256) {
        if (sup == 0) return sh;
        return up ? NexusTSMath.mulDivUp(sh, ta, sup) : NexusTSMath.mulDivDown(sh, ta, sup);
    }

    /// @dev _strategyTotalAssets(): en vivo, ociosos + estimación de la fuente; por reporte, lastTotalAssets.
    function _live(Snap memory s) internal view returns (uint256) {
        if (!LIVE) return s.L;
        return s.idle + (s.tok > s.pr ? s.tok - s.pr : 0);
    }

    function _liquid(Snap memory s) internal pure returns (uint256) {
        uint256 locked = s.pr + s.pl;
        uint256 r = s.tok > locked ? s.tok - locked : 0;
        return NexusTSMath.min(r, s.liq);
    }

    /// @dev _lossBurnState: (quema de bloqueadas, quema total) para una pérdida.
    function _lossBurn(Snap memory s, uint256 loss, uint256 sup, uint256 ta)
        internal
        pure
        returns (uint256 lockedBurn, uint256 totalBurn)
    {
        uint256 buffer = s.B;
        if (buffer == 0) return (0, 0);
        uint256 u = _unl(s);
        if (u >= buffer) return (0, buffer);
        uint256 ls = _c2s(loss, sup, ta, false);
        lockedBurn = NexusTSMath.min(buffer - u, ls);
        totalBurn = u + lockedBurn;
    }

    /// @dev _simulatedTotals fuera de un callback: lo que usan las vistas y las conversiones.
    function _sim(Snap memory s) internal view returns (uint256 sup, uint256 ta) {
        sup = _eff(s);
        if (s.ts == s.LA) return (sup, s.L);
        ta = _live(s);
        if (s.L == 0) return (sup < MIN_SUPPLY ? sup + ta : sup, ta);
        if (ta > s.L) {
            uint256 p = ta - s.L;
            if (sup < MIN_SUPPLY) {
                sup += _c2s(p, sup, s.L, true);
            } else if (s.fee != 0) {
                uint256 f = (p * s.fee) / MAX_BPS;
                sup += _c2s(f, sup, ta - f, false);
            }
        } else if (ta < s.L) {
            (uint256 lb,) = _lossBurn(s, s.L - ta, sup, s.L);
            sup -= lb;
        }
    }

    /// @dev _chargeFees: (comisión en activos, acciones de comisión) y los mintea al protocolo y al receptor.
    function _chargeFees(Snap memory m, uint256 profit, uint256 nw, bool useNew)
        internal
        pure
        returns (uint256 tf, uint256 fs)
    {
        if (m.fee == 0 || m.TS == 0) return (0, 0);
        unchecked {
            tf = (profit * m.fee) / MAX_BPS;
        }
        fs = _c2s(tf, _eff(m), useNew ? nw - tf : m.L, false);
        uint256 ps;
        if (m.pbps != 0) {
            unchecked {
                ps = (fs * m.pbps) / MAX_BPS;
            }
            _mint(m, H_PROTO, ps);
        }
        _mint(m, m.feeIdx, fs - ps);
    }

    /// @dev _syncUnlockScheduleAfterLoss.
    function _syncAfterLoss(Snap memory m) internal pure {
        m.LR = m.ts;
        if (m.D > m.ts && m.B != 0) {
            unchecked {
                m.R = (m.B * EXT) / (m.D - m.ts);
            }
        } else {
            m.R = 0;
        }
    }

    /// @dev _accrue: una vez por bloque, la estimación en vivo contra lastTotalAssets.
    function _accrue(Snap memory m) internal view returns (Acc memory a) {
        if (m.ts == m.LA) return a;
        a.ran = true;
        uint256 nw = _live(m);
        uint256 old = m.L;
        if (nw > old) {
            a.profit = nw - old;
            uint256 sup = _eff(m);
            if (sup < MIN_SUPPLY) {
                a.dead = old == 0 ? nw : _c2s(a.profit, sup, old, true);
                _mint(m, H_DEAD, a.dead);
            } else if (old != 0) {
                (a.fees, a.feeShares) = _chargeFees(m, a.profit, nw, true);
            }
        } else if (old > nw) {
            a.loss = old - nw;
            (uint256 lb, uint256 tb) = _lossBurn(m, a.loss, _eff(m), old);
            a.lockedBurn = lb;
            if (tb != 0) _burnB(m, tb);
            _syncAfterLoss(m);
        }
        m.L = nw;
        m.LA = m.ts;
    }

    /// @dev Pone `amount * deployBps / 10_000` en la fuente (deployFunds, tend y la cosecha).
    function _deploy(Snap memory m, uint256 amount) internal pure returns (bool called) {
        uint256 d = (amount * m.bps) / MAX_BPS;
        if (d > 0) {
            m.idle -= d;
            m.tok += d;
            called = true;
        }
    }

    /// @dev availableDepositLimit de la estrategia de prueba con totalAssets = `ta`.
    function _depLimit(Snap memory m, uint256 ta) internal pure returns (uint256) {
        if (m.cap == type(uint256).max) return m.cap;
        return m.cap > ta ? m.cap - ta : 0;
    }

    function _wLimit(Snap memory m) internal pure returns (uint256) {
        return m.limitW ? m.idle + _liquid(m) : type(uint256).max;
    }

    /// @dev Las cuatro max* de ERC-4626 con los totales (sup, ta).
    function _maxDep(Snap memory m, uint256 ta) internal pure returns (uint256) {
        if (m.shutdown || m.paused) return 0;
        return _depLimit(m, ta);
    }

    function _maxMint(Snap memory m, uint256 sup, uint256 ta) internal pure returns (uint256) {
        if (m.shutdown || m.paused) return 0;
        uint256 lim = _depLimit(m, ta);
        if (lim == type(uint256).max) return lim;
        return _c2s(lim, sup, ta, false);
    }

    function _maxW(Snap memory m, uint256 h, uint256 sup, uint256 ta) internal pure returns (uint256) {
        if (m.paused) return 0;
        uint256 lim = _wLimit(m);
        uint256 conv = _c2a(m.bal[h], sup, ta, false);
        return lim == type(uint256).max ? conv : NexusTSMath.min(conv, lim);
    }

    function _maxR(Snap memory m, uint256 h, uint256 sup, uint256 ta) internal pure returns (uint256) {
        if (m.paused) return 0;
        uint256 lim = _wLimit(m);
        if (lim == type(uint256).max) return m.bal[h];
        return NexusTSMath.min(_c2s(lim, sup, ta, false), m.bal[h]);
    }

    /// @dev deposit (isMint = false, `amt` en activos) o mint (isMint = true, `amt` en acciones) de `h` para sí.
    function _simEnter(Snap memory m, uint256 h, uint256 amt, bool isMint) internal view returns (Op memory o) {
        if (m.paused) return o;
        o.acc = _accrue(m);
        o.vL = m.L;
        o.vS = _eff(m);
        if (isMint) {
            if (amt > _maxMint(m, o.vS, m.L)) return o;
            o.shares = amt;
            o.assets = _c2a(amt, o.vS, m.L, true);
            if (o.assets == 0) return o;
        } else {
            if (amt == type(uint256).max) amt = m.cash[h];
            if (amt > _maxDep(m, m.L)) return o;
            o.assets = amt;
            o.shares = _c2s(amt, o.vS, m.L, false);
            if (o.shares == 0) return o;
        }
        if (m.cash[h] < o.assets) return o;
        m.cash[h] -= o.assets;
        m.idle += o.assets;
        o.probe = _deploy(m, m.idle);
        m.L += o.assets;
        _mint(m, h, o.shares);
        o.ok = true;
    }

    /// @dev withdraw (isRedeem = false, `amt` en activos) o redeem (`amt` en acciones) de `h`, con su maxLoss.
    function _simExit(Snap memory m, uint256 h, uint256 amt, bool isRedeem, uint256 maxLoss)
        internal
        view
        returns (Op memory o)
    {
        if (m.paused) return o;
        o.acc = _accrue(m);
        o.vL = m.L;
        o.vS = _eff(m);
        if (isRedeem) {
            if (amt > _maxR(m, h, o.vS, m.L)) return o;
            o.shares = amt;
            o.assets = _c2a(amt, o.vS, m.L, false);
            if (o.assets == 0) return o;
        } else {
            if (amt > _maxW(m, h, o.vS, m.L)) return o;
            o.assets = amt;
            o.shares = _c2s(amt, o.vS, m.L, true);
            if (o.shares == 0) return o;
        }
        if (maxLoss > MAX_BPS) return o;
        uint256 req = o.assets;
        if (m.idle < req) {
            o.probe = true;
            uint256 got = NexusTSMath.min(req - m.idle, _liquid(m));
            m.idle += got;
            m.tok -= got;
            if (m.idle < req) {
                o.loss = req - m.idle;
                if (maxLoss < MAX_BPS && o.loss > (req * maxLoss) / MAX_BPS) return o;
                o.assets = m.idle;
            }
        }
        m.L -= req;
        _burn(m, h, o.shares);
        m.idle -= o.assets;
        m.cash[h] += o.assets;
        o.ok = true;
    }

    /// @dev report(): devenga, cosecha (las recompensas pendientes entran, la pérdida pendiente sale), vuelve a
    /// colocar los ociosos si no está apagada, bloquea la ganancia neta de comisiones o cubre la pérdida con el
    /// buffer, y rehace el cronograma con el promedio ponderado. Si el período sale 0 revierte (división por 0).
    function _simReport(Snap memory m) internal view returns (Rep memory r) {
        r.acc = _accrue(m);
        r.vL = m.L;
        r.vS = _eff(m);
        r.nw = m.idle + m.tok - m.pl;
        m.tok -= m.pl;
        m.sink += m.pl;
        m.pl = 0;
        m.pr = 0;
        if (!m.shutdown) _deploy(m, m.idle);
        uint256 old = m.L;
        if (r.nw > old) {
            r.profit = r.nw - old;
            r.stl = _c2s(r.profit, _eff(m), old, false);
            (r.fees, r.feeShares) = _chargeFees(m, r.profit, r.nw, m.T == 0);
            if (m.T != 0) {
                unchecked {
                    r.stl -= r.feeShares;
                }
                uint256 u = _unl(m);
                if (u > r.stl) {
                    unchecked {
                        _burnB(m, u - r.stl);
                    }
                } else if (r.stl > u) {
                    unchecked {
                        _mintB(m, r.stl - u);
                    }
                }
            }
        } else {
            r.loss = old - r.nw;
            (, uint256 tb) = _lossBurn(m, r.loss, _eff(m), old);
            if (tb != 0) _burnB(m, tb);
        }
        if (!_schedule(m, r)) return r;
        m.L = r.nw;
        m.LR = m.ts;
        r.ok = true;
    }

    function _schedule(Snap memory m, Rep memory r) internal pure returns (bool) {
        uint256 tl = m.B;
        if (tl == 0) {
            m.D = 0;
            return true;
        }
        if (m.D > m.ts) {
            unchecked {
                r.plt = (m.D - m.ts) * (tl - r.stl);
            }
        }
        r.period = (r.plt + r.stl * m.T) / tl;
        if (r.period == 0) return false;
        m.R = (tl * EXT) / r.period;
        m.D = m.ts + r.period;
        return true;
    }

    /// @dev ¿La simulación de `s` confisca ganancia al piso o revela una pérdida? (excepciones de Y-INF-2)
    function _simMoves(Snap memory s) internal view returns (bool) {
        if (s.ts == s.LA) return false;
        uint256 a = _live(s);
        uint256 sup = _eff(s);
        if (s.L == 0) return a > 0 && sup < MIN_SUPPLY;
        if (a < s.L) return true;
        return a > s.L && sup < MIN_SUPPLY;
    }

    /* LEYES */

    /// @dev Y-TA-1, Y-SUP-1, Y-LOCK-1, Y-FEE-1, Y-INF-1, Y-FUNDS: el estado crudo quedó exactamente como el modelo.
    function _lawState(Snap memory e, Snap memory p) internal {
        _ok(p.L == e.L, L_TA, "lastTotalAssets distinto del modelo (modelo, real)", e.L, p.L);
        _ok(p.LA == e.LA, L_TA, "lastAccrual distinto del modelo (modelo, real)", e.LA, p.LA);
        _ok(p.TS == e.TS, L_SUP, "totalSupply crudo distinto del modelo (modelo, real)", e.TS, p.TS);
        _ok(p.B == e.B, L_LOCK, "buffer de acciones bloqueadas distinto del modelo (modelo, real)", e.B, p.B);
        _ok(p.R == e.R, L_LOCK, "profitUnlockingRate distinto del modelo (modelo, real)", e.R, p.R);
        _ok(p.D == e.D, L_LOCK, "fullProfitUnlockDate distinto del modelo (modelo, real)", e.D, p.D);
        _ok(p.LR == e.LR, L_LOCK, "lastReport distinto del modelo (modelo, real)", e.LR, p.LR);
        for (uint256 h; h < NH; ++h) {
            uint8 law = h < 4 ? L_INF1 : (h == H_DEAD ? L_SUP : L_FEE);
            _ok(p.bal[h] == e.bal[h], law, "saldo de acciones distinto del modelo (modelo, real)", e.bal[h], p.bal[h]);
        }
        for (uint256 i; i < 4; ++i) {
            _ok(p.cash[i] == e.cash[i], L_INF1, "el actor no pago o no cobro exactamente la conversion (modelo, real)", e.cash[i], p.cash[i]);
        }
        _ok(p.idle == e.idle, L_FUNDS, "activo ocioso distinto del modelo (modelo, real)", e.idle, p.idle);
        _ok(p.tok == e.tok, L_FUNDS, "activo en la fuente distinto del modelo (modelo, real)", e.tok, p.tok);
        _ok(p.pr == e.pr && p.pl == e.pl, L_FUNDS, "pendientes de la fuente distintos del modelo (recompensas, perdida)", p.pr, p.pl);
        _ok(p.sink == e.sink, L_FUNDS, "perdida realizada en la cosecha distinta del modelo (modelo, real)", e.sink, p.sink);
        _ok(p.fee == e.fee && p.T == e.T && p.feeIdx == e.feeIdx, L_LIVE, "configuracion distinta del modelo (comision, desbloqueo)", p.fee, p.T);
        _ok(p.paused == e.paused && p.shutdown == e.shutdown, L_LIVE, "pausa o apagado distintos del modelo (0, 0)", 0, 0);
        _lawLedger(p);
    }

    /// @dev Y-LEDGER y la forma del buffer: Σ saldos crudos = totalSupply crudo; sin fecha no hay buffer; lo
    /// desbloqueado nunca pasa al buffer.
    function _lawLedger(Snap memory s) internal {
        uint256 sum = s.B;
        for (uint256 h; h < NH; ++h) {
            sum += s.bal[h];
        }
        _ok(sum == s.TS, L_LEDGER, "la suma de los saldos crudos no es totalSupply (suma, totalSupply)", sum, s.TS);
        _ok(s.D != 0 || s.B == 0, L_LEDGER, "buffer sin fecha de desbloqueo (buffer, 0)", s.B, 0);
        uint256 u = _unl(s);
        _ok(u <= s.B, L_LOCK, "acciones desbloqueadas por encima del buffer (desbloqueadas, buffer)", u, s.B);
    }

    /// @dev Y-VIEW-1: las vistas de ERC-4626 y los getters, contra el modelo de las vistas (simulación), para `h`.
    function _lawViews(Snap memory s, uint256 h) internal {
        (uint256 sup, uint256 ta) = _sim(s);
        uint256 x = 10 ** uint256(DEC);
        _ok(ts.totalAssets() == ta, L_VIEW, "totalAssets distinto del modelo (modelo, real)", ta, ts.totalAssets());
        _ok(ts.totalSupply() == _eff(s), L_VIEW, "totalSupply distinto del modelo (modelo, real)", _eff(s), ts.totalSupply());
        _ok(ts.unlockedShares() == _unl(s), L_VIEW, "unlockedShares distinto del modelo (modelo, real)", _unl(s), ts.unlockedShares());
        _ok(ts.balanceOf(address(strategy)) == s.B - _unl(s), L_VIEW, "balanceOf(estrategia) distinto del modelo (modelo, real)", s.B - _unl(s), ts.balanceOf(address(strategy)));
        _ok(ts.convertToAssets(x) == _c2a(x, sup, ta, false), L_VIEW, "convertToAssets distinto del modelo (modelo, real)", _c2a(x, sup, ta, false), ts.convertToAssets(x));
        _ok(ts.convertToShares(x) == _c2s(x, sup, ta, false), L_VIEW, "convertToShares distinto del modelo (modelo, real)", _c2s(x, sup, ta, false), ts.convertToShares(x));
        _ok(ts.pricePerShare() == _c2a(x, sup, ta, false), L_VIEW, "pricePerShare distinto del modelo (modelo, real)", _c2a(x, sup, ta, false), ts.pricePerShare());
        _lawMaxViews(s, h, sup, ta);
        _lawGetters(s);
    }

    function _lawMaxViews(Snap memory s, uint256 h, uint256 sup, uint256 ta) internal {
        address a = actors[h];
        _ok(ts.maxDeposit(a) == _maxDep(s, ta), L_VIEW, "maxDeposit distinto del modelo (modelo, real)", _maxDep(s, ta), ts.maxDeposit(a));
        _ok(ts.maxMint(a) == _maxMint(s, sup, ta), L_VIEW, "maxMint distinto del modelo (modelo, real)", _maxMint(s, sup, ta), ts.maxMint(a));
        _ok(ts.maxWithdraw(a) == _maxW(s, h, sup, ta), L_VIEW, "maxWithdraw distinto del modelo (modelo, real)", _maxW(s, h, sup, ta), ts.maxWithdraw(a));
        _ok(ts.maxRedeem(a) == _maxR(s, h, sup, ta), L_VIEW, "maxRedeem distinto del modelo (modelo, real)", _maxR(s, h, sup, ta), ts.maxRedeem(a));
    }

    function _lawGetters(Snap memory s) internal {
        bool same = ts.lastTotalAssets() == s.L && ts.lastAccrual() == s.LA && ts.profitUnlockingRate() == s.R
            && ts.fullProfitUnlockDate() == s.D && ts.lastReport() == s.LR && ts.performanceFee() == s.fee
            && ts.isPaused() == s.paused && ts.isShutdown() == s.shutdown;
        _ok(same, L_VIEW, "un getter no coincide con el almacenamiento crudo (0, 0)", 0, 0);
        uint256 t = s.T == type(uint32).max ? type(uint256).max : s.T;
        _ok(ts.profitMaxUnlockTime() == t, L_VIEW, "profitMaxUnlockTime distinto del crudo (modelo, real)", t, ts.profitMaxUnlockTime());
    }

    /// @dev Y-REENT-1: lo que vio la fuente en el último callback es el estado congelado (vL, vS).
    function _lawProbe(bool expected, uint256 vL, uint256 vS) internal {
        uint256 n = source.seenCount();
        _ok((n > 0) == expected, L_REENT, "la fuente no recibio el callback esperado (esperado, vistos)", expected ? 1 : 0, n);
        if (n == 0) return;
        uint256 x = 10 ** uint256(DEC);
        _ok(source.seenTA() == vL, L_REENT, "totalAssets durante el callback no es el estado congelado (modelo, real)", vL, source.seenTA());
        _ok(source.seenTS() == vS, L_REENT, "totalSupply durante el callback no es el estado congelado (modelo, real)", vS, source.seenTS());
        uint256 c2a = _c2a(x, vS, vL, false);
        uint256 c2s = _c2s(x, vS, vL, false);
        _ok(source.seenC2A() == c2a && source.seenPR() == c2a, L_REENT, "convertToAssets o previewRedeem durante el callback (modelo, real)", c2a, source.seenC2A());
        _ok(source.seenC2S() == c2s && source.seenPD() == c2s, L_REENT, "convertToShares o previewDeposit durante el callback (modelo, real)", c2s, source.seenC2S());
        ++hProbes;
    }

    /// @dev Y-INF-2: el precio simulado (lo que usan las conversiones) no bajó: ta'·sup ≥ ta·sup', exacto.
    function _lawPrice(Snap memory pre, Snap memory post) internal {
        (uint256 sb, uint256 tb) = _sim(pre);
        (uint256 sa, uint256 ta) = _sim(post);
        if (sb == 0 || sa == 0) return;
        _ok(NexusTSMath.geq(ta, sb, tb, sa), L_INF2, "el precio por accion simulado bajo (activos antes, despues)", tb, ta);
    }

    /// @dev Y-INF-2 cuando entra ganancia en vivo (sin operación): la simulación redondea hacia abajo las acciones de
    /// comisión, ⌊f·s/(A − f)⌋, y cuando la comisión f sube 1 wei ese piso puede saltar una acción entera, que vale más
    /// que 1 wei. El precio sin piso, (A − f)/s, no baja (f sube a lo sumo 1 por wei con φ ≤ 50 %) y el simulado queda
    /// por encima de él, así que nunca baja de tb/(sb + 1): ta·(sb + 1) ≥ tb·sa, exacto (docs, §4).
    function _lawPriceTol(Snap memory pre, Snap memory post) internal {
        (uint256 sb, uint256 tb) = _sim(pre);
        (uint256 sa, uint256 ta) = _sim(post);
        if (sb == 0 || sa == 0) return;
        _ok(NexusTSMath.geq(ta, sb + 1, tb, sa), L_INF2, "el precio simulado bajo mas que una accion al entrar ganancia en vivo (activos antes, despues)", tb, ta);
    }

    /// @dev Métricas de un devengamiento del modelo.
    function _countAcc(Acc memory a) internal {
        if (!a.ran) return;
        if (a.dead != 0) ++hDead;
        if (a.feeShares != 0) {
            ++hLiveProfit;
            hFeeShares += a.feeShares;
        }
        if (a.loss != 0) ++hLiveLoss;
        if (a.lockedBurn != 0) ++hLockedBurn;
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
        if (law == L_TA) return "Y-TA-1";
        if (law == L_SUP) return "Y-SUP-1";
        if (law == L_LOCK) return "Y-LOCK-1";
        if (law == L_FEE) return "Y-FEE-1";
        if (law == L_INF1) return "Y-INF-1";
        if (law == L_INF2) return "Y-INF-2";
        if (law == L_VIEW) return "Y-VIEW-1";
        if (law == L_REENT) return "Y-REENT-1";
        if (law == L_FUNDS) return "Y-FUNDS";
        if (law == L_LIVE) return "Y-LIVE";
        return "Y-LEDGER";
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

    function coverage()
        external
        view
        returns (uint256 laws, uint256 liveProfit, uint256 dead, uint256 liveLoss, uint256 lockedBurn, uint256 feeShares)
    {
        return (hLaws, hLiveProfit, hDead, hLiveLoss, hLockedBurn, hFeeShares);
    }

    function coverage2()
        external
        view
        returns (
            uint256 reportProfit,
            uint256 reportLoss,
            uint256 relock,
            uint256 withdrawLoss,
            uint256 latched,
            uint256 rejected,
            uint256 probes
        )
    {
        return (hReportProfit, hReportLoss, hRelock, hWithdrawLoss, hLatched, hRejected, hProbes);
    }
}
