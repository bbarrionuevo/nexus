// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.34;

// Variante B del cazador de Midnight: además de todo lo de la variante A, take con los callbacks del comprador y del
// vendedor, repay y liquidate con callback, flashLoan, multicall y (en una de las dos variantes) gates. El contrato de
// callbacks ejecuta operaciones anidadas sobre Midnight en medio de la operación: colateral, repago, retiro,
// actualización, la liquidación de otro y un take anidado. El modelo aplica cada fase en el orden del núcleo:
// efectos, callback del comprador, pagos, callback del vendedor y salud final (con el bloqueo de liquidación del
// vendedor mientras corren los callbacks). Cada operación anidada se predice sobre el estado intermedio, y lo que
// registró el callback tiene que coincidir con la predicción (MN-LIVE).

import {Test} from "forge-std/Test.sol";
import {NexusMidnightHandler} from "./NexusMidnightInvariant.t.sol";
import {Market, Offer} from "../../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../../src/libraries/ConstantsLib.sol";

contract NexusMidnightCbHandler is NexusMidnightHandler {
    uint8 internal constant S_SUPPLY = 0;
    uint8 internal constant S_WCOLL = 1;
    uint8 internal constant S_REPAY = 2;
    uint8 internal constant S_WITHDRAW = 3;
    uint8 internal constant S_UPDATE = 4;
    uint8 internal constant S_LIQ = 5;
    uint8 internal constant S_TAKE = 6;
    uint8 internal constant N_STEP = 7;

    /// @dev Una operación anidada que ejecuta el callback (msg.sender = el callback).
    struct Step {
        uint8 kind;
        uint256 h; // actor sobre el que actúa (onBehalf, prestatario liquidado o taker del take anidado)
        uint256 i; // índice de colateral
        uint256 a; // monto: colateral, unidades o activos según el tipo
        uint256 mk; // maker del take anidado
        bool flag; // take anidado: oferta de compra; liquidación: modo post-vencimiento
        bool bySeized; // liquidación: por embargo (o por repago)
        uint256 tick; // take anidado
    }

    // métricas de la variante B (por corrida)
    uint256 internal hCbOps; // operaciones con callback que pasaron
    uint256 internal hNested; // operaciones anidadas ejecutadas dentro de operaciones que pasaron
    uint256 internal hNestedOk; // de esas, las que pasaron
    uint256 internal hLockedTry; // liquidaciones anidadas del vendedor bloqueado (tienen que revertir)
    uint256 internal hFlash; // préstamos flash que pasaron
    uint256 internal hMulti; // multicalls que pasaron

    constructor(uint8 dec, uint256 sfPct, uint256 cfPct, uint256 lltvHigh, bool gated)
        NexusMidnightHandler(dec, sfPct, cfPct, lltvHigh, gated)
    {}

    /* OPERACIONES ANIDADAS */

    function _mkStep(uint256 seed, Snap memory s) internal view returns (Step memory st) {
        st.kind = uint8(seed % N_STEP);
        st.h = (seed >> 8) % NH;
        st.i = (seed >> 16) % NC;
        uint256 r = seed >> 24;
        if (st.kind == S_SUPPLY) {
            st.a = 1 + r % (1e6 * 1e18);
        } else if (st.kind == S_WCOLL) {
            st.a = _clamp(r, 0, s.pos[st.h].coll[st.i]);
        } else if (st.kind == S_REPAY) {
            st.a = _clamp(r, 0, s.pos[st.h].debt);
        } else if (st.kind == S_WITHDRAW) {
            (uint256 nc,,) = _view(s, st.h);
            st.a = _clamp(r, 0, _min(nc, s.W));
        } else if (st.kind == S_LIQ) {
            st.i = _activeColl(st.h, seed >> 16);
            st.bySeized = r % 2 == 0;
            st.flag = s.ts > MATURITY && (r >> 1) % 2 == 0;
            st.a = st.bySeized ? _clamp(r >> 2, 1, s.pos[st.h].coll[st.i]) : _clamp(r >> 2, 1, s.pos[st.h].debt);
        } else if (st.kind == S_TAKE) {
            st.mk = (st.h + 1 + r % (NH - 1)) % NH;
            st.flag = (r >> 2) % 2 == 0;
            st.tick = 3800 + (r >> 3) % (MAX_TICK - 3800 + 1);
            st.tick -= st.tick % s.spacing;
            st.a = _amt(r >> 16);
        }
    }

    function _stepTake(Step memory st) internal pure returns (TakeIn memory t) {
        t.maker = st.mk;
        t.taker = st.h;
        t.buy = st.flag;
        t.tick = st.tick;
        t.units = st.a;
        t.cap = M128;
        t.feeCap = type(uint256).max;
        // oferta de compra: paga el maker y lo del vendedor (el taker) va al callback; de venta: paga el callback
        // (msg.sender) y lo del vendedor va al maker
        t.payer = st.flag ? st.mk : H_CB;
        t.rcv = st.flag ? H_CB : st.mk;
    }

    function _encStep(Step memory st) internal view returns (bytes memory) {
        Market memory mk = _market();
        if (st.kind == S_SUPPLY) return abi.encodeCall(midnight.supplyCollateral, (mk, st.i, st.a, actors[st.h]));
        if (st.kind == S_WCOLL) {
            return abi.encodeCall(midnight.withdrawCollateral, (mk, st.i, st.a, actors[st.h], address(cb)));
        }
        if (st.kind == S_REPAY) return abi.encodeCall(midnight.repay, (mk, st.a, actors[st.h], address(0), ""));
        if (st.kind == S_WITHDRAW) return abi.encodeCall(midnight.withdraw, (mk, st.a, actors[st.h], address(cb)));
        if (st.kind == S_UPDATE) return abi.encodeCall(midnight.updatePosition, (mk, actors[st.h]));
        if (st.kind == S_LIQ) {
            return abi.encodeCall(
                midnight.liquidate,
                (
                    mk,
                    st.i,
                    st.bySeized ? st.a : 0,
                    st.bySeized ? 0 : st.a,
                    actors[st.h],
                    st.flag,
                    address(cb),
                    address(0),
                    ""
                )
            );
        }
        TakeIn memory t = _stepTake(st);
        Offer memory off = _offer(t);
        return abi.encodeCall(midnight.take, (off, "", t.units, actors[t.taker], t.buy ? address(cb) : address(0), address(0), ""));
    }

    /// @dev Modelo de una operación anidada (msg.sender = el callback, autorizado por todos los actores).
    function _simStep(Snap memory m, Step memory st) internal view returns (bool) {
        if (st.kind == S_SUPPLY) return _simSupply(m, H_CB, st.h, st.i, st.a);
        if (st.kind == S_WCOLL) return _simWithdrawColl(m, st.h, st.i, st.a, H_CB);
        if (st.kind == S_REPAY) return _simRepay(m, H_CB, st.h, st.a);
        if (st.kind == S_WITHDRAW) return _simWithdraw(m, st.h, st.a, H_CB);
        if (st.kind == S_UPDATE) return _update(m, st.h);
        if (st.kind == S_LIQ) {
            LiqIn memory l;
            l.borrower = st.h;
            l.idx = st.i;
            if (st.bySeized) l.seized = st.a;
            else l.repaid = st.a;
            l.pmm = st.flag;
            l.payer = H_CB;
            l.rcv = H_CB;
            return _simLiq(m, l).ok;
        }
        return _simTake(m, _stepTake(st)).ok;
    }

    /// @dev Aplica las operaciones anidadas en orden: cada una sobre el estado que dejó la anterior; la que revierte
    /// no cambia nada. Guarda las predicciones desde `off`.
    function _runSteps(Snap memory m, Step[] memory sts, bool[] memory preds, uint256 off)
        internal
        view
        returns (Snap memory)
    {
        for (uint256 k; k < sts.length; ++k) {
            Snap memory c = _copy(m);
            bool ok = _simStep(c, sts[k]);
            preds[off + k] = ok;
            if (ok) m = c;
        }
        return m;
    }

    function _steps(uint256 seed, uint256 n, Snap memory s) internal view returns (Step[] memory sts, bytes[] memory enc) {
        sts = new Step[](n);
        enc = new bytes[](n);
        for (uint256 k; k < n; ++k) {
            sts[k] = _mkStep(uint256(keccak256(abi.encode(seed, k))), s);
            enc[k] = _encStep(sts[k]);
        }
    }

    /// @dev Fondos para el callback (paga como comprador, repago, liquidación, colateral anidado) y para los makers de
    /// los takes anidados de compra, que pagan ellos.
    function _fund(Step[] memory a, Step[] memory b, uint256 extra) internal {
        loan.mint(address(cb), extra + MAX_AMT);
        coll[0].mint(address(cb), 1e6 * 1e18);
        coll[1].mint(address(cb), 1e6 * 1e18);
        for (uint256 k; k < b.length; ++k) {
            if (b[k].kind == S_SUPPLY) coll[b[k].i].mint(address(cb), b[k].a);
        }
        for (uint256 k; k < a.length; ++k) {
            if (a[k].kind == S_TAKE && a[k].flag) loan.mint(actors[a[k].mk], 2 * a[k].a + 1);
        }
        for (uint256 k; k < b.length; ++k) {
            if (b[k].kind == S_TAKE && b[k].flag) loan.mint(actors[b[k].mk], 2 * b[k].a + 1);
        }
    }

    /// @dev MN-LIVE de las anidadas: el callback registró lo mismo que predijo el modelo.
    function _lawNested(bool[] memory preds, Step[] memory a, Step[] memory b, uint256 lockedSeller) internal {
        uint256 n = cb.resultsLength();
        _ok(n == preds.length, L_LIVE, "el callback no ejecuto todas las operaciones anidadas (esperadas, ejecutadas)", preds.length, n);
        if (n != preds.length) return;
        for (uint256 k; k < n; ++k) {
            bool real = cb.resultAt(k);
            _ok(real == preds[k], L_LIVE, "una operacion anidada paso o revirtio distinto del modelo (modelo, real)", preds[k] ? 1 : 0, real ? 1 : 0);
            ++hNested;
            if (real) ++hNestedOk;
            Step memory st = k < a.length ? a[k] : b[k - a.length];
            if (st.kind == S_LIQ && lockedSeller == st.h + 1) ++hLockedTry;
        }
    }

    /* TAKE CON CALLBACKS */

    struct CbTake {
        bool buyCb;
        bool sellCb;
        bytes32 ansBuy;
        bytes32 ansSell;
        address rt; // receiverIfTakerIsSeller
        address takerCb;
        uint256 seller;
    }

    function takeCb(uint256 makerSeed, uint256 takerSeed, uint256 tickSeed, uint256 unitsSeed, uint256 cbSeed) external {
        TakeIn memory t;
        t.maker = makerSeed % NH;
        t.taker = (t.maker + 1 + takerSeed % (NH - 1)) % NH;
        t.buy = (makerSeed >> 8) % 2 == 0;
        Snap memory s0 = _snap();
        t.tick = 3800 + tickSeed % (MAX_TICK - 3800 + 1);
        t.tick -= t.tick % s0.spacing;
        t.units = _amt(unitsSeed);
        t.cap = M128;
        t.feeCap = type(uint256).max;
        CbTake memory c;
        c.buyCb = cbSeed % 4 != 0;
        c.sellCb = (cbSeed >> 2) % 2 == 0;
        c.ansBuy = (cbSeed >> 3) % 16 == 0 ? bytes32(uint256(1)) : CALLBACK_SUCCESS;
        c.ansSell = (cbSeed >> 7) % 16 == 0 ? bytes32(uint256(1)) : CALLBACK_SUCCESS;
        c.seller = t.buy ? t.taker : t.maker;
        if ((cbSeed >> 11) % 4 != 0) _collateralize(c.seller, (cbSeed >> 13) % NC, s0.pos[c.seller].debt + t.units);
        s0 = _snap();
        (Step[] memory bs,) = _steps(cbSeed ^ 0xb0, c.buyCb ? (cbSeed >> 14) % 3 : 0, s0);
        (Step[] memory ss,) = _steps(cbSeed ^ 0x5e, c.sellCb ? (cbSeed >> 16) % 3 : 0, s0);
        _takeWithCb(t, c, bs, ss);
    }

    /// @dev Bloqueo de liquidación: el vendedor toma deuda sin colateral nuevo; en onBuy alguien intenta realizarle la
    /// deuda incobrable (liquidación con los dos montos en 0), que el bloqueo tiene que impedir; en onSell el
    /// callback le pone el colateral que lo deja sano. Sin el bloqueo, la liquidación anidada pasaría.
    function lockCycle(uint256 lenderSeed, uint256 borrowerSeed, uint256 amtSeed, uint256 tickSeed) external {
        TakeIn memory t;
        t.maker = lenderSeed % NH;
        t.taker = (t.maker + 1 + borrowerSeed % (NH - 1)) % NH;
        t.buy = true;
        Snap memory s0 = _snap();
        t.tick = 3800 + tickSeed % (MAX_TICK - 3800 + 1);
        t.tick -= t.tick % s0.spacing;
        t.units = _amt(amtSeed);
        t.cap = M128;
        t.feeCap = type(uint256).max;
        CbTake memory c;
        c.buyCb = true;
        c.sellCb = true;
        c.ansBuy = CALLBACK_SUCCESS;
        c.ansSell = CALLBACK_SUCCESS;
        c.seller = t.taker;
        Step[] memory bs = new Step[](1);
        bs[0].kind = S_LIQ;
        bs[0].h = t.taker;
        Step[] memory ss = new Step[](1);
        ss[0].kind = S_SUPPLY;
        ss[0].h = t.taker;
        ss[0].i = (borrowerSeed >> 8) % NC;
        uint256 p = s0.price[ss[0].i];
        uint256 need = p == 0 ? 1 : ((s0.pos[t.taker].debt + t.units) * WAD / lltv[ss[0].i] + 1) * PSCALE / p + 1;
        ss[0].a = need + need / 4;
        _takeWithCb(t, c, bs, ss);
    }

    /// @dev take con los callbacks de `c` y las operaciones anidadas `bs` (onBuy) y `ss` (onSell): efectos,
    /// onBuy, pagos, onSell y salud final, con el vendedor bloqueado mientras corren los callbacks.
    function _takeWithCb(TakeIn memory t, CbTake memory c, Step[] memory bs, Step[] memory ss) internal {
        uint256 b = t.buy ? t.maker : t.taker;
        bytes[] memory be = new bytes[](bs.length);
        bytes[] memory se = new bytes[](ss.length);
        for (uint256 k; k < bs.length; ++k) {
            be[k] = _encStep(bs[k]);
        }
        for (uint256 k; k < ss.length; ++k) {
            se[k] = _encStep(ss[k]);
        }
        _fund(bs, ss, 2 * t.units + 1);
        loan.mint(actors[b], 2 * t.units + 1);
        cb.reset();
        cb.load(0, be, c.ansBuy);
        cb.load(1, se, c.ansSell);

        t.payer = c.buyCb ? H_CB : b;
        // lo del vendedor: en una oferta de compra lo elige el taker (el callback si es el del vendedor); en una de
        // venta va al maker
        c.rt = t.buy ? (c.sellCb ? address(cb) : actors[t.taker]) : address(0);
        t.rcv = t.buy ? (c.sellCb ? H_CB : t.taker) : t.maker;
        Offer memory off = _offer(t);
        if (t.buy) {
            off.callback = c.buyCb ? address(cb) : address(0);
            c.takerCb = c.sellCb ? address(cb) : address(0);
        } else {
            off.callback = c.sellCb ? address(cb) : address(0);
            c.takerCb = c.buyCb ? address(cb) : address(0);
        }

        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool[] memory preds = new bool[](bs.length + ss.length);
        TakeOut memory o = _takeEffects(m, t);
        bool expect = o.ok;
        if (expect) {
            m.locked = c.seller + 1;
            if (c.buyCb) {
                m = _runSteps(m, bs, preds, 0);
                expect = c.ansBuy == CALLBACK_SUCCESS;
            }
            if (expect) expect = _takePay(m, t, o);
            if (expect && c.sellCb) {
                m = _runSteps(m, ss, preds, bs.length);
                expect = c.ansSell == CALLBACK_SUCCESS;
            }
            m.locked = 0;
            if (expect) expect = _takeHealth(m, c.seller);
        }
        vm.prank(actors[t.taker]);
        (bool ok,) = address(midnight).call(
            abi.encodeCall(midnight.take, (off, "", t.units, actors[t.taker], c.rt, c.takerCb, ""))
        );
        _settle("take con callbacks", ok, expect, pre, m);
        if (ok && expect) {
            ++hCbOps;
            ++hTakes;
            _lawNested(preds, bs, ss, c.seller + 1);
        }
    }

    /* REPAGO, LIQUIDACIÓN Y PRÉSTAMO FLASH CON CALLBACK */

    function repayCb(uint256 hs, uint256 unitsSeed, uint256 cbSeed) external {
        uint256 h = hs % NH;
        Snap memory s0 = _snap();
        uint256 d = s0.pos[h].debt;
        uint256 units = unitsSeed % 8 == 0 ? d + 1 : _clamp(unitsSeed >> 3, 0, d);
        (Step[] memory st, bytes[] memory enc) = _steps(cbSeed, cbSeed % 3, s0);
        bytes32 ans = (cbSeed >> 2) % 16 == 0 ? bytes32(uint256(1)) : CALLBACK_SUCCESS;
        _fund(st, new Step[](0), units);
        cb.reset();
        cb.load(2, enc, ans);
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool[] memory preds = new bool[](st.length);
        bool expect = _repayEffects(m, h, units);
        if (expect) {
            m = _runSteps(m, st, preds, 0);
            expect = ans == CALLBACK_SUCCESS && _payIn(m, H_CB, units);
        }
        vm.prank(actors[h]);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.repay, (_market(), units, actors[h], address(cb), "")));
        _settle("repay con callback", ok, expect, pre, m);
        if (ok && expect) {
            ++hCbOps;
            _lawNested(preds, st, new Step[](0), 0);
        }
    }

    function liquidateCb(uint256 bs, uint256 cs, uint256 amtSeed, uint256 cbSeed) external {
        LiqIn memory l;
        l.borrower = bs % NH;
        l.idx = cs % 4 == 0 ? (cs >> 2) % NC : _activeColl(l.borrower, cs >> 2);
        Snap memory s0 = _snap();
        l.pmm = s0.ts > MATURITY && amtSeed % 2 == 0;
        uint256 k = (amtSeed >> 1) % 4;
        if (k == 1) l.seized = _clamp(amtSeed >> 3, 1, s0.pos[l.borrower].coll[l.idx]);
        else if (k >= 2) l.repaid = _clamp(amtSeed >> 3, 1, s0.pos[l.borrower].debt);
        l.payer = H_CB;
        bool toCb = cbSeed % 2 == 0;
        l.rcv = toCb ? H_CB : H_LIQ;
        (Step[] memory st, bytes[] memory enc) = _steps(cbSeed, (cbSeed >> 1) % 3, s0);
        bytes32 ans = (cbSeed >> 3) % 16 == 0 ? bytes32(uint256(1)) : CALLBACK_SUCCESS;
        _fund(st, new Step[](0), s0.pos[l.borrower].debt + 1);
        cb.reset();
        cb.load(2, enc, ans);
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool[] memory preds = new bool[](st.length);
        LiqOut memory o = _liqEffects(m, l);
        bool expect = o.ok;
        if (expect) {
            m = _runSteps(m, st, preds, 0);
            expect = ans == CALLBACK_SUCCESS && _payIn(m, H_CB, o.repaid);
        }
        vm.prank(LIQ);
        (bool ok,) = address(midnight).call(
            abi.encodeCall(
                midnight.liquidate,
                (_market(), l.idx, l.seized, l.repaid, actors[l.borrower], l.pmm, toCb ? address(cb) : LIQ, address(cb), "")
            )
        );
        _settle("liquidate con callback", ok, expect, pre, m);
        if (ok && expect) {
            ++hCbOps;
            if (o.badDebt > 0) ++hBadDebt;
            if (o.seized > 0 || o.repaid > 0) ++hLiq;
            _lawNested(preds, st, new Step[](0), 0);
        }
    }

    /// @dev Préstamo flash del activo prestado o de un colateral (hasta lo que tiene Midnight, a veces uno de más).
    function flash(uint256 tokSeed, uint256 amtSeed, uint256 cbSeed) external {
        uint256 tok = tokSeed % 3;
        Snap memory s0 = _snap();
        uint256 bal = tok == 0 ? s0.mLoan : s0.mColl[tok - 1];
        uint256 a = amtSeed % 8 == 0 ? bal + 1 : _clamp(amtSeed >> 3, 0, bal);
        (Step[] memory st, bytes[] memory enc) = _steps(cbSeed, cbSeed % 3, s0);
        bytes32 ans = (cbSeed >> 2) % 16 == 0 ? bytes32(uint256(1)) : CALLBACK_SUCCESS;
        _fund(st, new Step[](0), 0);
        cb.reset();
        cb.load(2, enc, ans);
        address[] memory toks = new address[](1);
        toks[0] = tok == 0 ? address(loan) : address(coll[tok - 1]);
        uint256[] memory amts = new uint256[](1);
        amts[0] = a;
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool[] memory preds = new bool[](st.length);
        bool expect = _flashOut(m, tok, a);
        if (expect) {
            m = _runSteps(m, st, preds, 0);
            expect = ans == CALLBACK_SUCCESS && _flashIn(m, tok, a);
        }
        vm.prank(LIQ);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.flashLoan, (toks, amts, address(cb), "")));
        _settle("flashLoan", ok, expect, pre, m);
        if (ok && expect) {
            ++hFlash;
            _lawNested(preds, st, new Step[](0), 0);
        }
    }

    /* MULTICALL Y GATES */

    /// @dev Un actor agrupa dos operaciones propias en multicall: si una revierte, revierte todo.
    function multi(uint256 hs, uint256 seed) external {
        uint256 h = hs % NH;
        Snap memory s0 = _snap();
        coll[0].mint(actors[h], 1e6 * 1e18);
        coll[1].mint(actors[h], 1e6 * 1e18);
        loan.mint(actors[h], MAX_AMT);
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bytes[] memory calls = new bytes[](2);
        bool expect = true;
        Market memory mk = _market();
        for (uint256 k; k < 2; ++k) {
            uint256 r = uint256(keccak256(abi.encode(seed, k)));
            uint256 kind = r % 5;
            uint256 i = (r >> 8) % NC;
            uint256 a;
            if (kind == 0) {
                a = 1 + (r >> 16) % (1e6 * 1e18);
                calls[k] = abi.encodeCall(midnight.supplyCollateral, (mk, i, a, actors[h]));
                if (expect) expect = _simSupply(m, h, h, i, a);
            } else if (kind == 1) {
                a = _clamp(r >> 16, 0, s0.pos[h].coll[i]);
                calls[k] = abi.encodeCall(midnight.withdrawCollateral, (mk, i, a, actors[h], actors[h]));
                if (expect) expect = _simWithdrawColl(m, h, i, a, h);
            } else if (kind == 2) {
                a = _clamp(r >> 16, 0, s0.pos[h].debt);
                calls[k] = abi.encodeCall(midnight.repay, (mk, a, actors[h], address(0), ""));
                if (expect) expect = _simRepay(m, h, h, a);
            } else if (kind == 3) {
                (uint256 nc,,) = _view(s0, h);
                a = _clamp(r >> 16, 0, _min(nc, s0.W));
                calls[k] = abi.encodeCall(midnight.withdraw, (mk, a, actors[h], actors[h]));
                if (expect) expect = _simWithdraw(m, h, a, h);
            } else {
                uint256 u = (r >> 16) % NH;
                calls[k] = abi.encodeCall(midnight.updatePosition, (mk, actors[u]));
                if (expect) expect = _update(m, u);
            }
        }
        vm.prank(actors[h]);
        (bool ok,) = address(midnight).call(abi.encodeCall(midnight.multicall, (calls)));
        _settle("multicall", ok, expect, pre, m);
        if (ok && expect) ++hMulti;
    }

    /// @dev Interruptores del gate (solo en la variante con gates): cada uno, una de cada cuatro veces, cerrado.
    function setGates(uint256 seed) external {
        if (!GATED) return;
        Snap memory pre = _snap();
        gate.set(seed % 4 != 0, (seed >> 2) % 4 != 0, (seed >> 4) % 4 != 0);
        _still(pre);
    }

    function coverage3()
        external
        view
        returns (uint256 cbOps, uint256 nested, uint256 nestedOk, uint256 lockedTry, uint256 flashes, uint256 multis)
    {
        return (hCbOps, hNested, hNestedOk, hLockedTry, hFlash, hMulti);
    }
}

contract NexusMidnightCallbacksTest is Test {
    NexusMidnightCbHandler internal handler;

    function setUp() public virtual {
        handler = new NexusMidnightCbHandler(18, 50, 50, 0.945e18, _gated());
        targetContract(address(handler));
    }

    function _gated() internal pure virtual returns (bool) {
        return false;
    }

    function invariant_midnightCallbacks() public view {
        string memory err = handler.check();
        require(bytes(err).length == 0, err);
    }

    function afterInvariant() public {
        (uint256 laws, uint256 takes,,, uint256 bad, uint256 liq) = handler.coverage();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cobertura: takes", takes);
        emit log_named_uint("cobertura: realizaciones de deuda incobrable", bad);
        emit log_named_uint("cobertura: liquidaciones con embargo o repago", liq);
        (uint256 cbOps, uint256 nested, uint256 nestedOk, uint256 lockedTry, uint256 flashes, uint256 multis) =
            handler.coverage3();
        emit log_named_uint("cobertura: operaciones con callback", cbOps);
        emit log_named_uint("cobertura: operaciones anidadas", nested);
        emit log_named_uint("cobertura: operaciones anidadas que pasaron", nestedOk);
        emit log_named_uint("cobertura: liquidaciones anidadas del vendedor bloqueado", lockedTry);
        emit log_named_uint("cobertura: prestamos flash", flashes);
        emit log_named_uint("cobertura: multicalls", multis);
    }
}

contract NexusMidnightCallbacksGatedTest is NexusMidnightCallbacksTest {
    function _gated() internal pure override returns (bool) {
        return true;
    }
}
