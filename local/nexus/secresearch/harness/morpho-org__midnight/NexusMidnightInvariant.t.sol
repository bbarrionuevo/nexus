// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

// Handler e invariantes del cazador de Midnight: un mercado de dos colaterales con ofertas de compra y de venta entre
// cuatro actores, colateral, repagos, retiros, liquidaciones (normales, post-vencimiento y de deuda incobrable),
// precios, el reloj hasta después del vencimiento y los roles de comisiones. Cada acción pasa por las leyes MN-... de
// NexusMidnightHunter.sol: el modelo predice si pasa (MN-LIVE) y el estado exacto.

import {Test} from "forge-std/Test.sol";
import {NexusMNHunter, NexusMNBase} from "./NexusMidnightHunter.sol";
import {Market, Offer} from "../../src/interfaces/IMidnight.sol";

contract NexusMidnightHandler is NexusMNHunter {
    constructor(uint8 dec, uint256 sfPct, uint256 cfPct, uint256 lltvHigh, bool gated)
        NexusMNBase(dec, sfPct, cfPct, lltvHigh, gated)
    {}

    /// @dev Un cuarto de las veces polvo (1 a 1e4); si no, hasta un millón de unidades del activo prestado.
    function _amt(uint256 seed) internal view returns (uint256) {
        if (seed % 4 == 0) return 1 + (seed >> 2) % 1e4;
        return 1 + (seed >> 2) % MAX_AMT;
    }

    /// @dev Un octavo de las veces cualquier tick (a veces fuera del spacing: revierte); si no, múltiplo del spacing,
    /// casi siempre con precios realistas (tick 3800 o más: precio de 0,85 a 1).
    function _tick(uint256 seed, uint256 sp) internal pure returns (uint256) {
        uint256 k = seed % 8;
        if (k == 0) return (seed >> 3) % (MAX_TICK + 1);
        uint256 lo = k == 1 ? 0 : 3800;
        uint256 t = lo + (seed >> 3) % (MAX_TICK - lo + 1);
        return t - t % sp;
    }

    /* COLATERAL */

    function supply(uint256 hs, uint256 cs, uint256 amount) external {
        _supply(hs % NH, cs % NC, 1 + amount % (1e6 * 1e18));
    }

    function _supply(uint256 h, uint256 i, uint256 a) internal {
        coll[i].mint(actors[h], a);
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool expect = _simSupply(m, h, h, i, a);
        vm.prank(actors[h]);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.supplyCollateral, (_market(), i, a, actors[h])));
        _settle("supplyCollateral", ok, expect, pre, m);
    }

    /// @dev Retiro de colateral: un octavo de las veces uno de más.
    function withdrawCollateral(uint256 hs, uint256 cs, uint256 amount) external {
        uint256 h = hs % NH;
        uint256 i = cs % NC;
        Snap memory pre = _snap();
        uint256 c = pre.pos[h].coll[i];
        uint256 a = amount % 8 == 0 ? c + 1 : _clamp(amount >> 3, 0, c);
        Snap memory m = _copy(pre);
        bool expect = _simWithdrawColl(m, h, i, a, h);
        vm.prank(actors[h]);
        (bool ok,) = address(midnight).call(
            abi.encodeCall(midnight.withdrawCollateral, (_market(), i, a, actors[h], actors[h]))
        );
        _settle("withdrawCollateral", ok, expect, pre, m);
    }

    /// @dev Colateral suficiente para que `h` tenga `debtTarget` de deuda al precio actual (con 25 % de margen).
    function _collateralize(uint256 h, uint256 i, uint256 debtTarget) internal {
        _collateralizeBy(h, i, debtTarget, 4);
    }

    /// @dev Lo mismo con un margen de 1/`div`. Con el precio en 0 (los desplomes lo pueden llevar ahí) no hay colateral
    /// que alcance y no pone nada.
    function _collateralizeBy(uint256 h, uint256 i, uint256 debtTarget, uint256 div) internal {
        uint256 p = oracle[i].price();
        if (p == 0 || debtTarget == 0) return;
        uint256 need = ((debtTarget * WAD) / lltv[i] + 1) * PSCALE / p + 1;
        _supply(h, i, need + need / div);
    }

    /* OFERTAS */

    function take(uint256 makerSeed, uint256 takerSeed, uint256 tickSeed, uint256 unitsSeed, uint256 capSeed) external {
        TakeIn memory t;
        t.maker = makerSeed % NH;
        t.taker = (t.maker + 1 + takerSeed % (NH - 1)) % NH;
        t.buy = (makerSeed >> 8) % 2 == 0;
        Snap memory s0 = _snap();
        t.tick = _tick(tickSeed, s0.spacing);
        t.units = _amt(unitsSeed);
        t.assetsCap = capSeed % 2 == 0;
        t.cap = (capSeed >> 1) % 4 == 0 ? s0.consumed[t.maker] + _amt(capSeed >> 3) : M128;
        t.reduceOnly = (capSeed >> 10) % 8 == 0;
        t.feeCap = (capSeed >> 13) % 16 == 0 && s0.cf > 0 ? s0.cf - 1 : type(uint256).max;
        // tres de cada cuatro veces el vendedor pone colateral para la deuda que tomaría
        if ((takerSeed >> 8) % 4 != 0) {
            uint256 sl = t.buy ? t.taker : t.maker;
            _collateralize(sl, (takerSeed >> 9) % NC, s0.pos[sl].debt + t.units);
        }
        _take(t);
    }

    function _take(TakeIn memory t) internal {
        uint256 b = t.buy ? t.maker : t.taker;
        t.payer = b; // sin callbacks paga el comprador
        t.rcv = t.buy ? t.taker : t.maker; // y lo del vendedor va al vendedor
        loan.mint(actors[b], 2 * t.units + 1); // alcanza para lo que paga el comprador (precio ≤ 1 + comisión)
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        TakeOut memory o = _simTake(m, t);
        Offer memory off = _offer(t);
        address rt = t.buy ? actors[t.taker] : address(0);
        vm.prank(actors[t.taker]);
        (bool ok, bytes memory ret) = address(midnight).call(
            abi.encodeCall(midnight.take, (off, "", t.units, actors[t.taker], rt, address(0), ""))
        );
        _settle("take", ok, o.ok, pre, m);
        if (ok && o.ok) {
            (uint256 ba, uint256 sa) = abi.decode(ret, (uint256, uint256));
            _ok(ba == o.buyerAssets && sa == o.sellerAssets, L_MKT, "take devolvio otros activos (comprador modelo, real)", o.buyerAssets, ba);
            ++hTakes;
            if (o.scd > 0) ++hCreditSold;
            if (t.units > o.bci) ++hDebtRepaidByTake;
        }
    }

    function _offer(TakeIn memory t) internal view returns (Offer memory off) {
        off.market = _market();
        off.buy = t.buy;
        off.maker = actors[t.maker];
        off.expiry = type(uint256).max;
        off.tick = t.tick;
        off.group = _group(t.maker);
        off.receiverIfMakerIsSeller = t.buy ? address(0) : actors[t.maker];
        off.ratifier = address(ratifier);
        off.reduceOnly = t.reduceOnly;
        uint128 cap = uint128(_min(t.cap, M128));
        if (t.assetsCap) off.maxAssets = cap;
        else off.maxUnits = cap;
        off.continuousFeeCap = t.feeCap;
    }

    /// @dev Cancela el grupo del maker (consumed al máximo) y pasa a uno nuevo.
    function cancel(uint256 hs) external {
        uint256 h = hs % NH;
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        m.consumed[h] = M128;
        bytes32 g = _group(h);
        vm.prank(actors[h]);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.setConsumed, (g, uint128(M128), actors[h])));
        _settle("setConsumed", ok, true, pre, m);
        ++groupNonce[h];
    }

    /* PRESTATARIOS Y PRESTAMISTAS */

    /// @dev Repago de la propia deuda (un octavo de las veces uno de más).
    function repay(uint256 hs, uint256 unitsSeed) external {
        uint256 h = hs % NH;
        uint256 d = midnight.debt(id, actors[h]);
        uint256 units = unitsSeed % 8 == 0 ? d + 1 : _clamp(unitsSeed >> 3, 0, d);
        _repay(h, units);
    }

    function _repay(uint256 h, uint256 units) internal {
        loan.mint(actors[h], units);
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool expect = _simRepay(m, h, h, units);
        vm.prank(actors[h]);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.repay, (_market(), units, actors[h], address(0), "")));
        _settle("repay", ok, expect, pre, m);
    }

    /// @dev Retiro de crédito: hasta lo que permiten el crédito al día y withdrawable (un octavo de las veces, uno de más).
    function withdraw(uint256 hs, uint256 unitsSeed) external {
        uint256 h = hs % NH;
        Snap memory pre = _snap();
        (uint256 nc,,) = _view(pre, h);
        uint256 top = _min(nc, pre.W);
        _withdraw(h, unitsSeed % 8 == 0 ? top + 1 : _clamp(unitsSeed >> 3, 0, top), pre);
    }

    function _withdraw(uint256 h, uint256 units, Snap memory pre) internal {
        Snap memory m = _copy(pre);
        bool expect = _simWithdraw(m, h, units, h);
        vm.prank(actors[h]);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.withdraw, (_market(), units, actors[h], actors[h])));
        _settle("withdraw", ok, expect, pre, m);
        if (ok && expect && units > 0) ++hWithdraw;
    }

    /// @dev updatePosition de un actor, llamado por un tercero (es sin permisos).
    function update(uint256 hs) external {
        uint256 h = hs % NH;
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        (uint256 nc,, uint256 fee) = _view(pre, h);
        bool expect = _update(m, h);
        vm.prank(LIQ);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.updatePosition, (_market(), actors[h])));
        _settle("updatePosition", ok, expect, pre, m);
        if (ok && expect) {
            if (fee > 0) ++hFeeAccrued;
            if (nc + fee < pre.pos[h].credit) ++hSlashed;
        }
    }

    /* LIQUIDACIONES */

    /// @dev Liquidación: modo post-vencimiento (si ya venció, la mitad de las veces) o normal; por embargo, por repago o
    /// con los dos en 0 (solo realiza la deuda incobrable).
    function liquidate(uint256 bs, uint256 cs, uint256 mode, uint256 amtSeed) external {
        LiqIn memory l;
        l.borrower = bs % NH;
        l.idx = cs % 4 == 0 ? (cs >> 2) % NC : _activeColl(l.borrower, cs >> 2);
        Snap memory s0 = _snap();
        l.pmm = s0.ts > MATURITY && mode % 2 == 0;
        uint256 k = amtSeed % 4;
        if (k == 1) l.seized = _clamp(amtSeed >> 2, 1, s0.pos[l.borrower].coll[l.idx]);
        else if (k >= 2) l.repaid = _clamp(amtSeed >> 2, 1, s0.pos[l.borrower].debt);
        _liquidate(l);
    }

    function _liquidate(LiqIn memory l) internal {
        l.payer = H_LIQ;
        l.rcv = H_LIQ;
        loan.mint(LIQ, midnight.debt(id, actors[l.borrower]) + 1);
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        LiqOut memory o = _simLiq(m, l);
        vm.prank(LIQ);
        (bool ok, bytes memory ret) = address(midnight).call(
            abi.encodeCall(
                midnight.liquidate,
                (_market(), l.idx, l.seized, l.repaid, actors[l.borrower], l.pmm, LIQ, address(0), "")
            )
        );
        _settle("liquidate", ok, o.ok, pre, m);
        if (ok && o.ok) {
            (uint256 sz, uint256 rp) = abi.decode(ret, (uint256, uint256));
            _ok(sz == o.seized && rp == o.repaid, L_MKT, "liquidate devolvio otros montos (embargo modelo, real)", o.seized, sz);
            if (o.badDebt > 0) {
                ++hBadDebt;
                _lawFair(pre, m);
            }
            if (o.seized > 0 || o.repaid > 0) ++hLiq;
            if (l.pmm) ++hPostMaturity;
        }
    }

    /// @dev MN-FAIR: tras una deuda incobrable, el crédito al día de cada prestamista baja en la misma proporción que el
    /// factor (M − LF), salvo redondeo. Con X = c·(M − LF)/(M − l), el crédito al día es X·(1 − k·t) + δ, con δ en
    /// (−1, 2) por los tres pisos (recorte, comisión pendiente y devengo); entonces |c1·a − c0·b| < 3a.
    function _lawFair(Snap memory pre, Snap memory post) internal {
        uint256 a = M128 - pre.LF;
        uint256 b = M128 - post.LF;
        for (uint256 h; h < NH; ++h) {
            (uint256 c0,,) = _view(pre, h);
            Snap memory q = _copy(pre);
            q.LF = post.LF;
            (uint256 c1,,) = _view(q, h);
            if (c0 == 0) continue;
            uint256 x = c1 * a;
            uint256 y = c0 * b;
            uint256 diff = x > y ? x - y : y - x;
            _ok(diff < 3 * a, L_FAIR, "un prestamista no perdio en proporcion a la deuda incobrable (desvio en unidades, tope)", diff / a, 3);
        }
    }

    /// @dev Un colateral activado de `h` (el primero desde `seed`); si no tiene, cualquiera.
    function _activeColl(uint256 h, uint256 seed) internal view returns (uint256) {
        uint256 bm = midnight.collateralBitmap(id, actors[h]);
        for (uint256 j; j < NC; ++j) {
            uint256 i = (seed + j) % NC;
            if (bm & (1 << i) != 0) return i;
        }
        return seed % NC;
    }

    /// @dev Liquidación normal: un préstamo con el colateral justo (2 % de margen), una baja de 3 a 15 % del precio de
    /// ese colateral y una liquidación por repago (una fracción de la deuda) o por embargo (una fracción del colateral),
    /// que el RCF puede rechazar si pasa lo necesario para volver a la salud.
    function liqCycle(uint256 lenderSeed, uint256 borrowerSeed, uint256 amtSeed, uint256 drop) external {
        uint256 lender = lenderSeed % NH;
        uint256 b = (lender + 1 + borrowerSeed % (NH - 1)) % NH;
        uint256 i = (borrowerSeed >> 8) % NC;
        TakeIn memory t;
        t.maker = lender;
        t.taker = b;
        t.buy = true;
        t.tick = 3800 + (drop >> 8) % (MAX_TICK - 3800 + 1);
        t.tick -= t.tick % midnight.tickSpacing(id);
        t.units = _amt(amtSeed);
        t.cap = M128;
        t.feeCap = type(uint256).max;
        _collateralizeBy(b, i, midnight.debt(id, actors[b]) + t.units, 50);
        _take(t);
        Snap memory pre = _snap();
        oracle[i].setPrice(pre.price[i] * (85 + drop % 13) / 100);
        _still(pre);
        LiqIn memory l;
        l.borrower = b;
        l.idx = i;
        l.pmm = _snap().ts > MATURITY && drop % 2 == 0;
        if ((drop >> 4) % 2 == 0) l.repaid = midnight.debt(id, actors[b]) / (2 + (drop >> 5) % 8);
        else l.seized = midnight.collateral(id, actors[b], i) / (2 + (drop >> 5) % 8);
        _liquidate(l);
    }

    /* MERCADO: PRECIOS, RELOJ Y ROLES */

    /// @dev Precio de un colateral: suave (±20 %), suba (hasta ×3) o desplome (al 1-30 %); acotado a ±1e6 del inicial.
    function setPrice(uint256 cs, uint256 seed) external {
        uint256 i = cs % NC;
        Snap memory pre = _snap();
        uint256 p = pre.price[i];
        uint256 k = seed % 8;
        uint256 np = k == 0 ? p * (1 + (seed >> 3) % 30) / 100 : (k == 1 ? p * (100 + (seed >> 3) % 201) / 100 : p * (80 + (seed >> 3) % 41) / 100);
        uint256 base = PSCALE * 10 ** LDEC / 1e18;
        if (np < base / 1e6) np = base / 1e6;
        if (np > base * 1e6) np = base * 1e6;
        oracle[i].setPrice(np);
        _still(pre);
    }

    /// @dev Reloj: casi siempre de unos minutos a un día o varios días; uno de cada dieciséis saltos va justo alrededor
    /// del vencimiento y otro después de él (pasado el vencimiento no entra deuda nueva: si fuera frecuente, el resto
    /// de la corrida no tendría préstamos).
    function warp(uint256 seed) external {
        Snap memory pre = _snap();
        uint256 k = seed % 16;
        if (k >= 14 && nOps < MIN_OPS) k = seed % 11;
        uint256 t;
        if (k <= 10) t = pre.ts + 1 + (seed >> 4) % 1 days;
        else if (k <= 13) t = pre.ts + 1 days + (seed >> 4) % 5 days;
        else if (k == 14) t = MATURITY - 1 hours + (seed >> 4) % 2 hours;
        else t = MATURITY + (seed >> 4) % (3 * TTML);
        if (t <= pre.ts) t = pre.ts + 1;
        vm.warp(t);
        _still(pre);
    }

    /// @dev Comisión continua del mercado (fee setter): 0, cualquiera hasta el máximo o el máximo + 1 (revierte).
    function setContinuousFee(uint256 seed) external {
        uint256 k = seed % 8;
        uint256 v = k == 0 ? 0 : (k == 1 ? MAX_CF + 1 : (seed >> 3) % (MAX_CF + 1));
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool expect = v <= MAX_CF;
        if (expect) m.cf = v;
        vm.prank(FEE_SETTER);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.setMarketContinuousFee, (id, v)));
        _settle("setMarketContinuousFee", ok, expect, pre, m);
    }

    /// @dev Comisión de liquidación de un punto (fee setter): múltiplo del cbp hasta el máximo; a veces inválida.
    function setSettlementFee(uint256 ks, uint256 seed) external {
        uint256 k = ks % 7;
        uint256 j = seed % 8;
        uint256 v = j == 0 ? _maxSF(k) + CBP : (j == 1 ? 1 + (seed >> 3) % CBP : ((seed >> 3) % (_maxSF(k) / CBP + 1)) * CBP);
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool expect = v <= _maxSF(k) && v % CBP == 0;
        if (expect) m.cbp[k] = v / CBP;
        vm.prank(FEE_SETTER);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.setMarketSettlementFee, (id, k, v)));
        _settle("setMarketSettlementFee", ok, expect, pre, m);
    }

    /// @dev Spacing de ticks (tick spacing setter): un divisor del actual (o uno que no lo es: revierte).
    function setTickSpacing(uint256 seed) external {
        Snap memory pre = _snap();
        uint256 v = 1 + seed % 4;
        Snap memory m = _copy(pre);
        bool expect = pre.spacing % v == 0;
        if (expect) m.spacing = v;
        vm.prank(TICK_SETTER);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.setMarketTickSpacing, (id, v)));
        _settle("setMarketTickSpacing", ok, expect, pre, m);
    }

    /// @dev El fee claimer cobra comisión continua (hasta CFC y withdrawable) o de liquidación (hasta lo reclamable).
    function claimFees(uint256 which, uint256 seed) external {
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool cont = which % 2 == 0;
        uint256 top = cont ? _min(pre.CFC, pre.W) : pre.claimable;
        uint256 a = seed % 8 == 0 ? top + 1 : _clamp(seed >> 3, 0, top);
        bool expect = cont ? _simClaimCF(m, a) : _simClaimSF(m, a);
        vm.prank(FEE_CLAIMER);
        (bool ok,) = address(midnight).call(
            cont
                ? abi.encodeCall(midnight.claimContinuousFee, (_market(), a, CLAIM_TO))
                : abi.encodeCall(midnight.claimSettlementFee, (address(loan), a, CLAIM_TO))
        );
        _settle(cont ? "claimContinuousFee" : "claimSettlementFee", ok, expect, pre, m);
    }

    /* SECUENCIAS */

    /// @dev Préstamo completo: el prestatario pone colateral y le vende deuda a una oferta de compra del prestamista.
    function loanCycle(uint256 lenderSeed, uint256 borrowerSeed, uint256 amtSeed, uint256 tickSeed) external {
        _loan(lenderSeed % NH, borrowerSeed, amtSeed, tickSeed);
    }

    function _loan(uint256 lender, uint256 borrowerSeed, uint256 amtSeed, uint256 tickSeed) internal returns (uint256) {
        uint256 borrower = (lender + 1 + borrowerSeed % (NH - 1)) % NH;
        TakeIn memory t;
        t.maker = lender;
        t.taker = borrower;
        t.buy = true;
        t.tick = 3800 + tickSeed % (MAX_TICK - 3800 + 1);
        t.tick -= t.tick % midnight.tickSpacing(id);
        t.units = _amt(amtSeed);
        t.cap = M128;
        t.feeCap = type(uint256).max;
        _collateralize(borrower, (borrowerSeed >> 8) % NC, midnight.debt(id, actors[borrower]) + t.units);
        _take(t);
        return borrower;
    }

    /// @dev Deuda incobrable: un préstamo, el desplome del colateral del prestatario y su liquidación (embargo de todo el
    /// colateral o los dos montos en 0).
    function badDebtCycle(uint256 lenderSeed, uint256 borrowerSeed, uint256 amtSeed, uint256 crash) external {
        uint256 b = _loan(lenderSeed % NH, borrowerSeed, amtSeed, crash >> 8);
        for (uint256 i; i < NC; ++i) {
            Snap memory pre = _snap();
            oracle[i].setPrice(pre.price[i] * (1 + crash % 40) / 100 + 1);
            _still(pre);
        }
        LiqIn memory l;
        l.borrower = b;
        l.idx = (borrowerSeed >> 8) % NC;
        l.pmm = _snap().ts > MATURITY;
        if (crash % 3 != 0) l.seized = midnight.collateral(id, actors[b], l.idx);
        _liquidate(l);
    }

    /// @dev Vencimiento: salto más allá del vencimiento, repagos parciales o totales, liquidaciones post-vencimiento de
    /// lo que quede y retiros de todos los prestamistas.
    function maturityCycle(uint256 seed) external {
        if (seed % 8 != 0 || nOps < MIN_OPS) return;
        seed >>= 3;
        Snap memory s0 = _snap();
        if (s0.ts <= MATURITY) {
            vm.warp(MATURITY + 1 + seed % (2 * TTML));
            _still(s0);
        }
        for (uint256 h; h < NH; ++h) {
            uint256 d = midnight.debt(id, actors[h]);
            if (d > 0 && (seed >> (h + 4)) % 2 == 0) _repay(h, (seed >> (h + 8)) % 3 == 0 ? d / 2 : d);
        }
        for (uint256 h; h < NH; ++h) {
            if (midnight.debt(id, actors[h]) == 0) continue;
            LiqIn memory l;
            l.borrower = h;
            l.idx = _activeColl(h, seed >> (h + 12));
            l.pmm = true;
            l.repaid = midnight.debt(id, actors[h]) / (1 + (seed >> (h + 16)) % 2);
            _liquidate(l);
        }
        for (uint256 h; h < NH; ++h) {
            Snap memory pre = _snap();
            (uint256 nc,,) = _view(pre, h);
            uint256 u = _min(nc, pre.W);
            if (u > 0) _withdraw(h, u, pre);
        }
    }

    /* COMÚN */

    function _settle(string memory op, bool ok, bool expect, Snap memory pre, Snap memory m) internal {
        ++nOps;
        Snap memory post = _snap();
        if (ok != expect) {
            _flag(L_LIVE, string(abi.encodePacked(op, ok ? ": paso y el modelo decia que revertia" : ": revirtio y el modelo decia que pasaba", " (marca de tiempo, 0)")), pre.ts, 0);
            return;
        }
        if (!ok) {
            ++hRejected;
            _lawState(pre, post);
            _lawGlobal(post);
            return;
        }
        _lawState(m, post);
        _lawGlobal(post);
        _lawViews(post);
    }

    /// @dev Una acción fuera del núcleo (precio, reloj) no cambia su estado; las vistas siguen al modelo.
    function _still(Snap memory pre) internal {
        ++nOps;
        Snap memory post = _snap();
        _lawState(pre, post);
        _lawGlobal(post);
        _lawViews(post);
    }
}

contract NexusMidnightInvariantTest is Test {
    NexusMidnightHandler internal handler;

    function setUp() public virtual {
        handler = new NexusMidnightHandler(_dec(), _sfPct(), _cfPct(), _lltvHigh(), false);
        targetContract(address(handler));
    }

    function _dec() internal pure virtual returns (uint8) {
        return 18;
    }

    function _sfPct() internal pure virtual returns (uint256) {
        return 50;
    }

    function _cfPct() internal pure virtual returns (uint256) {
        return 50;
    }

    function _lltvHigh() internal pure virtual returns (uint256) {
        return 0.945e18;
    }

    function invariant_midnight() public view {
        string memory err = handler.check();
        require(bytes(err).length == 0, err);
    }

    /// @dev Regresión de la campaña del 29-oct (6 decimales): los desplomes de badDebtCycle dejan los precios en 1,
    /// liqCycle baja el del colateral 0 a 0, y el siguiente liqCycle sobre ese colateral dividía por cero al calcular el
    /// colateral necesario. Con el precio en 0 las leyes tienen que seguir valiendo.
    function test_liqCycleConPrecioCero() public {
        for (uint256 k; k < 20; ++k) {
            handler.badDebtCycle(0, 0, 0, 0);
        }
        handler.liqCycle(0, 0, 0, 0);
        handler.liqCycle(0, 0, 0, 0);
        string memory err = handler.check();
        require(bytes(err).length == 0, err);
    }

    function afterInvariant() public {
        (uint256 laws, uint256 takes, uint256 sold, uint256 repaidByTake, uint256 bad, uint256 liq) = handler.coverage();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cobertura: takes", takes);
        emit log_named_uint("cobertura: takes en que el vendedor vendio credito", sold);
        emit log_named_uint("cobertura: takes en que el comprador cancelo deuda", repaidByTake);
        emit log_named_uint("cobertura: realizaciones de deuda incobrable", bad);
        emit log_named_uint("cobertura: liquidaciones con embargo o repago", liq);
        (uint256 pmm, uint256 wd, uint256 fee, uint256 slashed, uint256 rej) = handler.coverage2();
        emit log_named_uint("cobertura: liquidaciones post-vencimiento", pmm);
        emit log_named_uint("cobertura: retiros", wd);
        emit log_named_uint("cobertura: actualizaciones que devengaron comision continua", fee);
        emit log_named_uint("cobertura: actualizaciones que recortaron credito", slashed);
        emit log_named_uint("cobertura: operaciones rechazadas como predijo el modelo", rej);
    }
}

contract NexusMidnightInvariantMaxFeesTest is NexusMidnightInvariantTest {
    function _sfPct() internal pure override returns (uint256) {
        return 100;
    }

    function _cfPct() internal pure override returns (uint256) {
        return 100;
    }
}

contract NexusMidnightInvariantSixDecimalsTest is NexusMidnightInvariantTest {
    function _dec() internal pure override returns (uint8) {
        return 6;
    }
}

contract NexusMidnightInvariantLltvOneTest is NexusMidnightInvariantTest {
    function _lltvHigh() internal pure override returns (uint256) {
        return 1e18;
    }

    function _cfPct() internal pure override returns (uint256) {
        return 0;
    }
}
