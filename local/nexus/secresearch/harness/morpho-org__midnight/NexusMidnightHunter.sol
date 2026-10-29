// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

// Cazador de vulnerabilidades de Morpho Midnight (morpho-org/midnight @ etiqueta 2026-08-24, 14e0b77843: el núcleo
// desplegado en 0x4716…045f tiene coincidencia completa en Sourcify con esa etiqueta). Un mercado con dos colaterales,
// cuatro actores que hacen de maker y de taker con un ratifier de prueba, oráculos ajustables, un liquidador y los
// roles de comisiones. El fantasma lee los getters y predice cada operación de forma exacta, con los redondeos del
// código. Leyes MN-... (docs/CAZADOR_MIDNIGHT.md).
//
// Compila con los ajustes del repo (solc 0.8.34, osaka, via_ir).

import {Test} from "forge-std/Test.sol";
import {Midnight} from "../../src/Midnight.sol";
import {Market, Offer, CollateralParams} from "../../src/interfaces/IMidnight.sol";
import {IRatifier} from "../../src/interfaces/IRatifier.sol";
import {TickLib} from "../../src/libraries/TickLib.sol";
import {CALLBACK_SUCCESS} from "../../src/libraries/ConstantsLib.sol";

/// @notice ERC-20 de prueba: transferencias exactas, sin ganchos ni comisiones (los supuestos de tokens del núcleo).
contract NexusMNToken {
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
contract NexusMNOracle {
    uint256 public price = 1e36;

    function setPrice(uint256 p) external {
        price = p;
    }
}

/// @notice Ratifier de prueba: ratifica toda oferta (la autorización del maker la sigue exigiendo el núcleo).
contract NexusMNRatifier is IRatifier {
    function isRatified(Offer memory, bytes memory, address) external pure returns (bytes32) {
        return CALLBACK_SUCCESS;
    }
}

/// @notice Reloj: con via_ir, block.timestamp leído en la misma función que un vm.warp puede quedar cacheado.
contract NexusMNClock {
    function time() external view returns (uint256) {
        return block.timestamp;
    }
}

/// @notice Base: el núcleo, los roles, los tokens, los oráculos, el mercado y los actores.
abstract contract NexusMNBase is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant PSCALE = 1e36; // ORACLE_PRICE_SCALE
    uint256 internal constant CBP = 1e12;
    uint256 internal constant M128 = type(uint128).max;
    uint256 internal constant MAX_TICK = 6744;
    uint256 internal constant MAX_CF = uint256(0.01e18) / uint256(365 days); // MAX_CONTINUOUS_FEE
    uint256 internal constant TTML = 60 minutes; // TIME_TO_MAX_LIF
    uint256 internal constant NH = 4;
    uint256 internal constant NC = 2;

    address internal constant FEE_SETTER = address(uint160(uint256(keccak256("nexus.mn.feeSetter"))));
    address internal constant FEE_CLAIMER = address(uint160(uint256(keccak256("nexus.mn.feeClaimer"))));
    address internal constant TICK_SETTER = address(uint160(uint256(keccak256("nexus.mn.tickSetter"))));
    address internal constant LIQ = address(uint160(uint256(keccak256("nexus.mn.liquidator"))));
    address internal constant CLAIM_TO = address(uint160(uint256(keccak256("nexus.mn.claims"))));

    Midnight internal midnight;
    NexusMNToken internal loan;
    NexusMNToken[2] internal coll;
    NexusMNOracle[2] internal oracle;
    NexusMNRatifier internal ratifier;
    NexusMNClock internal clock;
    bytes32 internal id;
    address[4] internal actors;
    uint256[2] internal lltv;
    uint256 internal immutable CURSOR;
    uint256 internal immutable MATURITY;
    uint256 internal immutable RCF_THRESHOLD;
    uint256 internal immutable MAX_AMT;
    uint256 internal immutable LDEC;

    // la configuración del mercado (Market tiene un arreglo dinámico: se arma en memoria con _market())
    address[2] internal cTok;
    address[2] internal cOra;

    /// @param dec decimales del activo prestado; @param sfPct comisión de liquidación por defecto, en % del máximo de
    /// cada punto; @param cfPct comisión continua por defecto, en % del máximo; @param lltvHigh el LLTV del segundo
    /// colateral (0,945 o 1).
    constructor(uint8 dec, uint256 sfPct, uint256 cfPct, uint256 lltvHigh) {
        LDEC = dec;
        MAX_AMT = 10 ** (uint256(dec) + 6);
        CURSOR = 0.3e18;
        MATURITY = block.timestamp + 30 days;
        RCF_THRESHOLD = 10 ** uint256(dec) / 100;
        clock = new NexusMNClock();
        midnight = new Midnight();
        ratifier = new NexusMNRatifier();
        midnight.setFeeSetter(FEE_SETTER);
        midnight.setFeeClaimer(FEE_CLAIMER);
        midnight.setTickSpacingSetter(TICK_SETTER);
        lltv[0] = 0.86e18;
        lltv[1] = lltvHigh;
        midnight.enableLltv(lltv[0]);
        midnight.enableLltv(lltv[1]);
        midnight.enableLiquidationCursor(CURSOR);

        loan = new NexusMNToken("loan", dec);
        NexusMNToken a = new NexusMNToken("collA", 18);
        NexusMNToken b = new NexusMNToken("collB", 18);
        (coll[0], coll[1]) = address(a) < address(b) ? (a, b) : (b, a);
        for (uint256 i; i < NC; ++i) {
            oracle[i] = new NexusMNOracle();
            // 1 colateral (18 decimales) vale 1 unidad entera del activo prestado
            oracle[i].setPrice(PSCALE * 10 ** uint256(dec) / 1e18);
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

        for (uint256 h; h < NH; ++h) {
            address u = address(uint160(uint256(keccak256(abi.encode("nexus.mn.actor", h)))));
            actors[h] = u;
            vm.startPrank(u);
            midnight.setIsAuthorized(address(ratifier), true, u);
            loan.approve(address(midnight), type(uint256).max);
            coll[0].approve(address(midnight), type(uint256).max);
            coll[1].approve(address(midnight), type(uint256).max);
            vm.stopPrank();
        }
        vm.prank(LIQ);
        loan.approve(address(midnight), type(uint256).max);
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
        mk.rcfThreshold = RCF_THRESHOLD;
    }

    /// @dev maxSettlementFee(index), escrito de nuevo (no se usa el de ConstantsLib).
    function _maxSF(uint256 k) internal pure returns (uint256) {
        if (k <= 1) return 0.000014e18;
        if (k == 2) return 0.000098e18;
        if (k == 3) return 0.000417e18;
        if (k == 4) return 0.00125e18;
        if (k == 5) return 0.0025e18;
        return 0.005e18;
    }

    /// @dev maxLif(lltv, cursor), escrito de nuevo: WAD·WAD / (WAD − cursor·(WAD − lltv)/WAD).
    function _maxLif(uint256 l) internal view returns (uint256) {
        return (WAD * WAD) / (WAD - (CURSOR * (WAD - l)) / WAD);
    }

    function _clamp(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + x % (hi - lo + 1);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _zfs(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function _up(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }
}

/// @notice Contabilidad fantasma y leyes MN-... del núcleo de Midnight.
abstract contract NexusMNHunter is NexusMNBase {
    uint8 internal constant L_POS = 0; // MN-POS: cada campo de cada posición exacto
    uint8 internal constant L_MKT = 1; // MN-MKT: el estado del mercado y la comisión reclamable exactos
    uint8 internal constant L_UNITS = 2; // MN-UNITS: totalUnits = Σ deuda + withdrawable
    uint8 internal constant L_CLAIM = 3; // MN-CLAIM: Σ crédito al día + continuousFeeCredit ≤ totalUnits
    uint8 internal constant L_FUNDS = 4; // MN-FUNDS: saldos de Midnight, de los actores y de los receptores exactos
    uint8 internal constant L_VIEW = 5; // MN-VIEW: updatePositionView, isHealthy y settlementFee iguales al modelo
    uint8 internal constant L_FAIR = 6; // MN-FAIR: la deuda incobrable recorta a cada prestamista en proporción
    uint8 internal constant L_LIVE = 7; // MN-LIVE: pasa si y solo si el modelo dice que pasa
    uint8 internal constant N_LAWS = 8;

    struct Pos {
        uint256 credit;
        uint256 pf; // pendingFee
        uint256 llf; // lastLossFactor
        uint256 la; // lastAccrual
        uint256 debt;
        uint256 bitmap;
        uint256[2] coll;
    }

    /// @dev Foto del estado: getters del núcleo, saldos de tokens, precios y la hora.
    struct Snap {
        uint256 ts;
        uint256 T; // totalUnits
        uint256 LF; // lossFactor
        uint256 W; // withdrawable
        uint256 CFC; // continuousFeeCredit
        uint256 cf; // continuousFee
        uint256[7] cbp; // settlementFeeCbp0..6
        uint256 spacing;
        uint256 claimable; // claimableSettlementFee[loan]
        Pos[4] pos;
        uint256[4] consumed; // consumed[actor][grupo vigente del actor]
        uint256[4] cash; // activo prestado de cada actor
        uint256[2][4] ccash; // colateral de cada actor: ccash[h][i]
        uint256 mLoan; // activo prestado en Midnight
        uint256[2] mColl; // colateral en Midnight
        uint256[2] price;
        uint256 liqCash; // activo prestado del liquidador
        uint256[2] liqColl; // colateral embargado que recibió el liquidador
        uint256 claimTo; // comisiones cobradas
    }

    uint256[4] internal groupNonce;
    /// @dev Operaciones de la corrida. El vencimiento no se cruza antes de MIN_OPS: pasado el vencimiento no entra
    /// deuda nueva, y una corrida que lo cruza enseguida no presta nada.
    uint256 internal nOps;
    uint256 internal constant MIN_OPS = 50;

    uint256 internal violations;
    uint256 internal lawMask;
    string internal firstViolation;

    // métricas (por corrida)
    uint256 internal hLaws;
    uint256 internal hTakes;
    uint256 internal hCreditSold; // takes en que el vendedor vendió crédito (no tomó deuda)
    uint256 internal hDebtRepaidByTake; // takes en que el comprador canceló deuda
    uint256 internal hBadDebt; // liquidaciones que realizaron deuda incobrable
    uint256 internal hLiq; // liquidaciones con embargo o repago
    uint256 internal hPostMaturity; // liquidaciones en modo post-vencimiento
    uint256 internal hWithdraw;
    uint256 internal hFeeAccrued; // actualizaciones que devengaron comisión continua
    uint256 internal hSlashed; // actualizaciones que recortaron crédito por deuda incobrable
    uint256 internal hRejected;

    function _group(uint256 h) internal view returns (bytes32) {
        return keccak256(abi.encode("nexus.mn.group", h, groupNonce[h]));
    }

    /* FOTO */

    function _snap() internal view returns (Snap memory s) {
        s.ts = clock.time();
        _snapMarket(s);
        s.claimable = midnight.claimableSettlementFee(address(loan));
        for (uint256 h; h < NH; ++h) {
            _snapPos(s, h);
            s.consumed[h] = midnight.consumed(actors[h], _group(h));
            s.cash[h] = loan.balanceOf(actors[h]);
            s.ccash[h][0] = coll[0].balanceOf(actors[h]);
            s.ccash[h][1] = coll[1].balanceOf(actors[h]);
        }
        s.mLoan = loan.balanceOf(address(midnight));
        s.liqCash = loan.balanceOf(LIQ);
        s.claimTo = loan.balanceOf(CLAIM_TO);
        for (uint256 i; i < NC; ++i) {
            s.mColl[i] = coll[i].balanceOf(address(midnight));
            s.price[i] = oracle[i].price();
            s.liqColl[i] = coll[i].balanceOf(LIQ);
        }
    }

    function _snapMarket(Snap memory s) internal view {
        (
            uint128 t,
            uint128 lf,
            uint128 w,
            uint128 cfc,
            uint16 c0,
            uint16 c1,
            uint16 c2,
            uint16 c3,
            uint16 c4,
            uint16 c5,
            uint16 c6,
            uint32 cf,
            uint8 sp
        ) = midnight.marketState(id);
        s.T = t;
        s.LF = lf;
        s.W = w;
        s.CFC = cfc;
        s.cbp = [uint256(c0), c1, c2, c3, c4, c5, c6];
        s.cf = cf;
        s.spacing = sp;
    }

    function _snapPos(Snap memory s, uint256 h) internal view {
        (uint128 c, uint128 pf, uint128 llf, uint128 la, uint128 d, uint128 bm) = midnight.position(id, actors[h]);
        Pos memory p = s.pos[h];
        p.credit = c;
        p.pf = pf;
        p.llf = llf;
        p.la = la;
        p.debt = d;
        p.bitmap = bm;
        p.coll[0] = midnight.collateral(id, actors[h], 0);
        p.coll[1] = midnight.collateral(id, actors[h], 1);
    }

    function _copy(Snap memory s) internal pure returns (Snap memory) {
        return abi.decode(abi.encode(s), (Snap));
    }

    /* MODELO (Midnight.sol @ 2026-08-24, con su aritmética: mulDivDown = x·y/d, mulDivUp = (x·y + d − 1)/d) */

    /// @dev settlementFee(id, ttm): interpolación lineal entre los puntos 0, 1, 7, 30, 90, 180 y 360 días.
    function _sf(Snap memory s, uint256 ttm) internal pure returns (uint256) {
        if (ttm >= 360 days) return s.cbp[6] * CBP;
        uint32[7] memory bp = [uint32(0), 1 days, 7 days, 30 days, 90 days, 180 days, 360 days];
        uint256 k;
        while (ttm >= bp[k + 1]) ++k;
        uint256 start = bp[k];
        uint256 end = bp[k + 1];
        return (s.cbp[k] * CBP * (end - ttm) + s.cbp[k + 1] * CBP * (ttm - start)) / (end - start);
    }

    /// @dev updatePositionView: (crédito nuevo, comisión pendiente nueva, comisión devengada).
    function _view(Snap memory s, uint256 h) internal view returns (uint256 nc, uint256 npf, uint256 fee) {
        Pos memory p = s.pos[h];
        uint256 psc = p.llf < M128 ? (p.credit * (M128 - s.LF)) / (M128 - p.llf) : 0;
        uint256 pspf = p.credit > 0 ? p.pf - _up(p.pf, p.credit - psc, p.credit) : 0;
        uint256 end = _min(s.ts, MATURITY);
        fee = p.la < MATURITY ? (pspf * (end - p.la)) / (MATURITY - p.la) : 0;
        nc = psc - fee;
        npf = pspf - fee;
    }

    /// @dev _updatePosition. false si revierte (el devengado no entra en uint128).
    function _update(Snap memory s, uint256 h) internal view returns (bool) {
        (uint256 nc, uint256 npf, uint256 fee) = _view(s, h);
        Pos memory p = s.pos[h];
        p.credit = nc;
        p.llf = s.LF;
        p.pf = npf;
        p.la = s.ts;
        if (fee > M128) return false;
        s.CFC += fee;
        return s.CFC <= M128;
    }

    /// @dev maxDebt de isHealthy y de liquidate: Σ ⌊⌊colateral·precio/1e36⌋·lltv/WAD⌋ sobre los activados.
    function _maxDebt(Snap memory s, uint256 h) internal view returns (uint256 md) {
        Pos memory p = s.pos[h];
        for (uint256 i; i < NC; ++i) {
            if (p.bitmap & (1 << i) != 0) md += ((p.coll[i] * s.price[i]) / PSCALE * lltv[i]) / WAD;
        }
    }

    function _healthy(Snap memory s, uint256 h) internal view returns (bool) {
        return s.pos[h].debt == 0 || _maxDebt(s, h) >= s.pos[h].debt;
    }

    /// @dev ¿Algún producto de isHealthy o liquidate desborda? (revertiría por la aritmética comprobada)
    function _mulOk(Snap memory s, uint256 h) internal pure returns (bool) {
        Pos memory p = s.pos[h];
        for (uint256 i; i < NC; ++i) {
            if (p.bitmap & (1 << i) != 0 && s.price[i] != 0 && p.coll[i] > type(uint256).max / s.price[i]) return false;
        }
        return true;
    }

    struct TakeIn {
        uint256 maker;
        uint256 taker;
        bool buy;
        uint256 tick;
        uint256 units;
        bool assetsCap;
        uint256 cap;
        bool reduceOnly;
        uint256 feeCap;
    }

    struct TakeOut {
        bool ok;
        uint256 buyerAssets;
        uint256 sellerAssets;
        uint256 bci; // buyerCreditIncrease
        uint256 scd; // sellerCreditDecrease
        uint256 sdi; // sellerDebtIncrease
    }

    /// @dev take() con una oferta del maker `t.maker` tomada por `t.taker`, sin callbacks; quien paga es el comprador.
    function _simTake(Snap memory m, TakeIn memory t) internal view returns (TakeOut memory o) {
        if (m.LF >= M128) return o;
        if (m.cf > t.feeCap) return o;
        if (t.tick % m.spacing != 0 || t.tick > MAX_TICK) return o;
        if (t.maker == t.taker || t.cap == 0) return o;
        uint256 price = TickLib.tickToPrice(t.tick);
        uint256 ttm = _zfs(MATURITY, m.ts);
        uint256 fee = _sf(m, ttm);
        if (t.buy && price < fee) return o;
        uint256 sellerPrice = t.buy ? price - fee : price;
        uint256 buyerPrice = sellerPrice + fee;
        o.buyerAssets = t.buy ? (t.units * buyerPrice) / WAD : _up(t.units, buyerPrice, WAD);
        o.sellerAssets = t.buy ? (t.units * sellerPrice) / WAD : _up(t.units, sellerPrice, WAD);
        uint256 nc = m.consumed[t.maker] + (t.assetsCap ? (t.buy ? o.buyerAssets : o.sellerAssets) : t.units);
        if (nc > t.cap) return o;
        (uint256 b, uint256 sl) = t.buy ? (t.maker, t.taker) : (t.taker, t.maker);
        Pos memory bp = m.pos[b];
        Pos memory sp = m.pos[sl];
        if (bp.credit > 0 || t.units > bp.debt) {
            if (!_update(m, b)) return o;
        }
        if (sp.credit > 0) {
            if (!_update(m, sl)) return o;
        }
        o.bci = _zfs(t.units, bp.debt);
        o.scd = _min(t.units, sp.credit);
        o.sdi = t.units - o.scd;
        uint256 bpfi = (o.bci * (m.cf * ttm)) / WAD;
        uint256 spfd = sp.credit > 0 ? _up(sp.pf, o.scd, sp.credit) : 0;
        if (bpfi > M128 || spfd > M128) return o;
        if (m.ts > MATURITY && o.sdi != 0) return o;
        if (t.reduceOnly && (t.buy ? o.bci != 0 : o.sdi != 0)) return o;
        bp.debt -= t.units - o.bci;
        bp.pf += bpfi;
        bp.credit += o.bci;
        if (bp.pf > M128 || bp.credit > M128) return o;
        sp.pf -= spfd;
        sp.credit -= o.scd;
        sp.debt += o.sdi;
        if (sp.debt > M128) return o;
        if (m.T + o.bci < o.scd) return o;
        uint256 t2 = m.T + o.bci - o.scd;
        if (t2 > M128) return o;
        m.T = t2;
        m.claimable += o.buyerAssets - o.sellerAssets;
        m.consumed[t.maker] = nc;
        // el comprador paga la comisión a Midnight y lo del vendedor directo al vendedor
        if (m.cash[b] < o.buyerAssets) return o;
        m.cash[b] -= o.buyerAssets;
        m.mLoan += o.buyerAssets - o.sellerAssets;
        m.cash[sl] += o.sellerAssets;
        if (sp.debt > 0 && (!_mulOk(m, sl) || !_healthy(m, sl))) return o;
        o.ok = true;
    }

    /// @dev withdraw(units) de `h` para sí.
    function _simWithdraw(Snap memory m, uint256 h, uint256 units) internal view returns (bool) {
        if (!_update(m, h)) return false;
        Pos memory p = m.pos[h];
        if (p.credit > 0) {
            uint256 d = _up(p.pf, units, p.credit);
            if (d > M128 || d > p.pf) return false;
            p.pf -= d;
        }
        if (units > p.credit || units > m.W || units > m.T) return false;
        p.credit -= units;
        m.W -= units;
        m.T -= units;
        if (m.mLoan < units) return false;
        m.mLoan -= units;
        m.cash[h] += units;
        return true;
    }

    /// @dev repay(units) de `h` para sí, pagando él.
    function _simRepay(Snap memory m, uint256 h, uint256 units) internal pure returns (bool) {
        Pos memory p = m.pos[h];
        if (units > p.debt) return false;
        p.debt -= units;
        m.W += units;
        if (m.W > M128 || m.cash[h] < units) return false;
        m.cash[h] -= units;
        m.mLoan += units;
        return true;
    }

    function _simSupply(Snap memory m, uint256 h, uint256 i, uint256 a) internal pure returns (bool) {
        Pos memory p = m.pos[h];
        if (p.coll[i] == 0 && a > 0) p.bitmap |= 1 << i;
        p.coll[i] += a;
        if (p.coll[i] > M128 || m.ccash[h][i] < a) return false;
        m.ccash[h][i] -= a;
        m.mColl[i] += a;
        return true;
    }

    function _simWithdrawColl(Snap memory m, uint256 h, uint256 i, uint256 a) internal view returns (bool) {
        Pos memory p = m.pos[h];
        if (a > p.coll[i]) return false;
        p.coll[i] -= a;
        if (p.coll[i] == 0 && a > 0) p.bitmap &= ~(uint256(1) << i);
        if (p.debt > 0 && (!_mulOk(m, h) || !_healthy(m, h))) return false;
        m.mColl[i] -= a;
        m.ccash[h][i] += a;
        return true;
    }

    struct LiqIn {
        uint256 borrower;
        uint256 idx;
        uint256 seized;
        uint256 repaid;
        bool pmm;
    }

    struct LiqOut {
        bool ok;
        uint256 badDebt;
        uint256 seized;
        uint256 repaid;
    }

    /// @dev liquidate(): deuda incobrable con maxLif, factor de pérdida, CFC escalado, embargo o repago con su LIF y la
    /// condición RCF en modo normal. El liquidador recibe el colateral y paga el repago.
    function _simLiq(Snap memory m, LiqIn memory l) internal view returns (LiqOut memory o) {
        Pos memory p = m.pos[l.borrower];
        if (l.repaid != 0 && l.seized != 0) return o;
        if (p.debt == 0) return o;
        if (!_mulOk(m, l.borrower)) return o;
        uint256 maxDebt;
        uint256 liqPrice;
        uint256 bad = p.debt;
        for (uint256 i; i < NC; ++i) {
            if (p.bitmap & (1 << i) == 0) continue;
            if (i == l.idx) liqPrice = m.price[i];
            maxDebt += ((p.coll[i] * m.price[i]) / PSCALE * lltv[i]) / WAD;
            uint256 v = _up(p.coll[i], m.price[i], PSCALE);
            bad = _zfs(bad, _up(v, WAD, _maxLif(lltv[i])));
        }
        if (l.pmm ? m.ts <= MATURITY : p.debt <= maxDebt) return o;
        if (bad > 0) {
            p.debt -= bad;
            uint256 oldLF = m.LF;
            m.LF = M128 - ((M128 - oldLF) * (m.T - bad)) / m.T;
            m.T -= bad;
            m.CFC = oldLF < M128 ? (m.CFC * (M128 - m.LF)) / (M128 - oldLF) : 0;
            o.badDebt = bad;
        }
        uint256 seized = l.seized;
        uint256 repaid = l.repaid;
        if (repaid > 0 || seized > 0) {
            uint256 ml = _maxLif(lltv[l.idx]);
            uint256 lif = l.pmm ? _min(ml, WAD + (ml - WAD) * (m.ts - MATURITY) / TTML) : ml;
            if (seized > 0) {
                repaid = _up(_up(seized, liqPrice, PSCALE), WAD, lif);
            } else {
                if (liqPrice == 0) return o;
                seized = ((repaid * lif) / WAD * PSCALE) / liqPrice;
            }
            if (!l.pmm && lltv[l.idx] < WAD) {
                if (p.debt < maxDebt) return o;
                uint256 maxRepaid = _up(p.debt - maxDebt, WAD * WAD, WAD * WAD - lif * lltv[l.idx]);
                bool rcf = repaid <= maxRepaid
                    || _zfs(((p.coll[l.idx] * liqPrice) / PSCALE * WAD) / lif, maxRepaid) < RCF_THRESHOLD;
                if (!rcf) return o;
            }
            if (seized > p.coll[l.idx]) return o;
            p.coll[l.idx] -= seized;
            if (p.coll[l.idx] == 0 && seized > 0) p.bitmap &= ~(uint256(1) << l.idx);
            m.W += repaid;
            if (m.W > M128 || repaid > p.debt) return o;
            p.debt -= repaid;
        }
        if (m.mColl[l.idx] < seized || m.liqCash < repaid) return o;
        m.mColl[l.idx] -= seized;
        m.liqColl[l.idx] += seized;
        m.liqCash -= repaid;
        m.mLoan += repaid;
        o.seized = seized;
        o.repaid = repaid;
        o.ok = true;
    }

    /// @dev claimContinuousFee(amount): baja CFC, totalUnits y withdrawable.
    function _simClaimCF(Snap memory m, uint256 a) internal pure returns (bool) {
        if (a > m.CFC || a > m.T || a > m.W || a > m.mLoan) return false;
        m.CFC -= a;
        m.T -= a;
        m.W -= a;
        m.mLoan -= a;
        m.claimTo += a;
        return true;
    }

    function _simClaimSF(Snap memory m, uint256 a) internal pure returns (bool) {
        if (a > m.claimable || a > m.mLoan) return false;
        m.claimable -= a;
        m.mLoan -= a;
        m.claimTo += a;
        return true;
    }

    /* LEYES */

    /// @dev MN-POS, MN-MKT, MN-FUNDS: el estado quedó exactamente como el modelo.
    function _lawState(Snap memory e, Snap memory p) internal {
        _ok(p.T == e.T, L_MKT, "totalUnits distinto del modelo (modelo, real)", e.T, p.T);
        _ok(p.LF == e.LF, L_MKT, "lossFactor distinto del modelo (modelo, real)", e.LF, p.LF);
        _ok(p.W == e.W, L_MKT, "withdrawable distinto del modelo (modelo, real)", e.W, p.W);
        _ok(p.CFC == e.CFC, L_MKT, "continuousFeeCredit distinto del modelo (modelo, real)", e.CFC, p.CFC);
        _ok(p.cf == e.cf, L_MKT, "continuousFee distinto del modelo (modelo, real)", e.cf, p.cf);
        _ok(p.spacing == e.spacing, L_MKT, "tickSpacing distinto del modelo (modelo, real)", e.spacing, p.spacing);
        _ok(p.claimable == e.claimable, L_MKT, "claimableSettlementFee distinto del modelo (modelo, real)", e.claimable, p.claimable);
        for (uint256 k; k < 7; ++k) {
            _ok(p.cbp[k] == e.cbp[k], L_MKT, "comision de liquidacion (cbp) distinta del modelo (modelo, real)", e.cbp[k], p.cbp[k]);
        }
        for (uint256 h; h < NH; ++h) {
            _lawPos(e.pos[h], p.pos[h]);
            _ok(p.consumed[h] == e.consumed[h], L_POS, "consumed del grupo distinto del modelo (modelo, real)", e.consumed[h], p.consumed[h]);
            _ok(p.cash[h] == e.cash[h], L_FUNDS, "activo prestado de un actor distinto del modelo (modelo, real)", e.cash[h], p.cash[h]);
            _ok(p.ccash[h][0] == e.ccash[h][0] && p.ccash[h][1] == e.ccash[h][1], L_FUNDS, "colateral de un actor distinto del modelo (modelo, real)", e.ccash[h][0] + e.ccash[h][1], p.ccash[h][0] + p.ccash[h][1]);
        }
        _ok(p.mLoan == e.mLoan, L_FUNDS, "activo prestado en Midnight distinto del modelo (modelo, real)", e.mLoan, p.mLoan);
        _ok(p.liqCash == e.liqCash, L_FUNDS, "activo prestado del liquidador distinto del modelo (modelo, real)", e.liqCash, p.liqCash);
        _ok(p.claimTo == e.claimTo, L_FUNDS, "comisiones cobradas distintas del modelo (modelo, real)", e.claimTo, p.claimTo);
        for (uint256 i; i < NC; ++i) {
            _ok(p.mColl[i] == e.mColl[i], L_FUNDS, "colateral en Midnight distinto del modelo (modelo, real)", e.mColl[i], p.mColl[i]);
            _ok(p.liqColl[i] == e.liqColl[i], L_FUNDS, "colateral del liquidador distinto del modelo (modelo, real)", e.liqColl[i], p.liqColl[i]);
        }
    }

    function _lawPos(Pos memory e, Pos memory p) internal {
        _ok(p.credit == e.credit, L_POS, "credit distinto del modelo (modelo, real)", e.credit, p.credit);
        _ok(p.pf == e.pf, L_POS, "pendingFee distinto del modelo (modelo, real)", e.pf, p.pf);
        _ok(p.llf == e.llf, L_POS, "lastLossFactor distinto del modelo (modelo, real)", e.llf, p.llf);
        _ok(p.la == e.la, L_POS, "lastAccrual distinto del modelo (modelo, real)", e.la, p.la);
        _ok(p.debt == e.debt, L_POS, "debt distinto del modelo (modelo, real)", e.debt, p.debt);
        _ok(p.bitmap == e.bitmap, L_POS, "collateralBitmap distinto del modelo (modelo, real)", e.bitmap, p.bitmap);
        _ok(p.coll[0] == e.coll[0] && p.coll[1] == e.coll[1], L_POS, "colateral de la posicion distinto del modelo (modelo, real)", e.coll[0] + e.coll[1], p.coll[0] + p.coll[1]);
    }

    /// @dev MN-UNITS, MN-CLAIM y la solvencia de los saldos (MN-FUNDS), sobre el estado real.
    function _lawGlobal(Snap memory s) internal {
        uint256 debts;
        uint256 claims = s.CFC;
        uint256 collSum0;
        uint256 collSum1;
        for (uint256 h; h < NH; ++h) {
            debts += s.pos[h].debt;
            (uint256 nc,,) = _view(s, h);
            claims += nc;
            collSum0 += s.pos[h].coll[0];
            collSum1 += s.pos[h].coll[1];
            _ok(s.pos[h].credit == 0 || s.pos[h].debt == 0, L_UNITS, "una posicion tiene credito y deuda a la vez (credito, deuda)", s.pos[h].credit, s.pos[h].debt);
            _ok(s.pos[h].pf <= s.pos[h].credit, L_UNITS, "pendingFee mayor que el credito (pendiente, credito)", s.pos[h].pf, s.pos[h].credit);
        }
        _ok(s.T == debts + s.W, L_UNITS, "totalUnits distinto de la suma de deudas mas withdrawable (totalUnits, suma)", s.T, debts + s.W);
        _ok(claims <= s.T, L_CLAIM, "los reclamos (credito al dia + continuousFeeCredit) superan totalUnits (reclamos, totalUnits)", claims, s.T);
        _ok(s.mLoan == s.W + s.claimable, L_FUNDS, "el activo en Midnight no es withdrawable + comision reclamable (saldo, suma)", s.mLoan, s.W + s.claimable);
        _ok(s.mColl[0] == collSum0 && s.mColl[1] == collSum1, L_FUNDS, "el colateral en Midnight no es la suma de las posiciones (saldo, suma)", s.mColl[0] + s.mColl[1], collSum0 + collSum1);
    }

    /// @dev MN-VIEW: las vistas del núcleo contra el modelo.
    function _lawViews(Snap memory s) internal {
        Market memory mk = _market();
        for (uint256 h; h < NH; ++h) {
            (uint256 nc, uint256 npf, uint256 fee) = _view(s, h);
            (uint128 rc, uint128 rpf, uint128 rfee) = midnight.updatePositionView(mk, id, actors[h]);
            _ok(rc == nc && rpf == npf && rfee == fee, L_VIEW, "updatePositionView distinto del modelo (credito modelo, real)", nc, rc);
            if (_mulOk(s, h)) {
                bool hv = midnight.isHealthy(mk, id, actors[h]);
                _ok(hv == _healthy(s, h), L_VIEW, "isHealthy distinto del modelo (modelo, real)", _healthy(s, h) ? 1 : 0, hv ? 1 : 0);
            }
        }
        uint256 ttm = _zfs(MATURITY, s.ts);
        _ok(midnight.settlementFee(id, ttm) == _sf(s, ttm), L_VIEW, "settlementFee distinto del modelo (modelo, real)", _sf(s, ttm), midnight.settlementFee(id, ttm));
    }

    function _ok(bool cond, uint8 law, string memory what, uint256 x, uint256 y) internal {
        ++hLaws;
        if (!cond) _flag(law, what, x, y);
    }

    function _flag(uint8 law, string memory what, uint256 x, uint256 y) internal {
        ++violations;
        lawMask |= 1 << law;
        if (bytes(firstViolation).length == 0) {
            firstViolation = string(abi.encodePacked(_lawName(law), ": ", what, " ", vm.toString(x), ", ", vm.toString(y)));
        }
    }

    function _lawName(uint8 law) internal pure returns (string memory) {
        if (law == L_POS) return "MN-POS";
        if (law == L_MKT) return "MN-MKT";
        if (law == L_UNITS) return "MN-UNITS";
        if (law == L_CLAIM) return "MN-CLAIM";
        if (law == L_FUNDS) return "MN-FUNDS";
        if (law == L_VIEW) return "MN-VIEW";
        if (law == L_FAIR) return "MN-FAIR";
        return "MN-LIVE";
    }

    /// @dev La primera violación y la lista de leyes violadas ("" si ninguna).
    function check() external view returns (string memory) {
        if (violations == 0) return "";
        string memory list;
        for (uint8 l; l < N_LAWS; ++l) {
            if (lawMask & (1 << l) != 0) list = string(abi.encodePacked(list, bytes(list).length == 0 ? "" : " ", _lawName(l)));
        }
        return string(abi.encodePacked(firstViolation, " [leyes: ", list, "]"));
    }

    function coverage()
        external
        view
        returns (uint256 laws, uint256 takes, uint256 creditSold, uint256 debtRepaid, uint256 badDebt, uint256 liq)
    {
        return (hLaws, hTakes, hCreditSold, hDebtRepaidByTake, hBadDebt, hLiq);
    }

    function coverage2()
        external
        view
        returns (uint256 postMaturity, uint256 withdraws, uint256 feeAccrued, uint256 slashed, uint256 rejected)
    {
        return (hPostMaturity, hWithdraw, hFeeAccrued, hSlashed, hRejected);
    }
}
