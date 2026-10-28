// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

// Handler e invariantes del cazador de EulerEarn (variante A: tres estrategias ERC-4626 de prueba), en tres variantes:
// sin comisión, con comisión y activo de 6 decimales. Cada acción pasa por las leyes E-... de NexusEulerEarnHunter.sol.
// El modelo predice si cada operación pasa (E-LIVE) y cómo se reparte por las colas (E-ALLOC-1); el rendimiento y la
// pérdida de cada estrategia se controlan con su saldo, así que el fantasma conoce los activos reales exactos.

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IEulerEarnBase, MarketAllocation} from "../../src/interfaces/IEulerEarn.sol";
import {NexusEEHunter, NexusEEBase, NexusEEMath} from "./NexusEulerEarnHunter.sol";

interface IEEStaticH {
    function config(IERC4626) external view returns (uint112 balance, uint136 cap, bool enabled, uint64 removableAt);
}

contract NexusEulerEarnHandler is NexusEEHunter {
    uint256 internal hReallocs;
    uint256 internal hRemovals;
    uint256 internal hEnables;

    function coverage2() external view returns (uint256 reallocs, uint256 removals, uint256 enables) {
        return (hReallocs, hRemovals, hEnables);
    }

    constructor(uint256 fee, uint8 assetDecimals) NexusEEBase(fee, assetDecimals) {
        _hunterInit();
    }

    /* USUARIOS */

    /// @dev Depósito: pasa si y solo si el modelo lo coloca entero por la supplyQueue y acuña al menos una acción.
    function deposit(uint256 actorSeed, uint256 assets) external {
        address who = _actor(actorSeed);
        uint256 a = 1 + assets % MAX_ASSETS;
        Snap memory pre = _snap();
        (uint256 A,, uint256 sigma) = _expectAccrual(pre);
        uint256 s = NexusEEMath.mulDivDown(a, pre.T + sigma + V, A + V);
        (uint256[3] memory tA, uint256[3] memory tS, uint256[3] memory b, uint256 rem, uint256 used) = _simSupply(pre, a);
        uint256 tok = token.balanceOf(who);
        deal(address(token), who, tok + a);
        vm.prank(who);
        (bool ok,) = address(vault).call(abi.encodeCall(IERC4626.deposit, (a, who)));
        if (rem == type(uint256).max) ++hBound;
        _afterEnter(ok, rem == 0 && s != 0, pre, who, a, s, tA, tS, b, used);
        _lawTokens(who, ok ? tok : tok + a);
    }

    /// @dev Mint: cuesta ⌈s·(A+V)/(T+σ+V)⌉ y pasa si y solo si el modelo coloca ese monto.
    function mint(uint256 actorSeed, uint256 shares) external {
        address who = _actor(actorSeed);
        uint256 s = 1 + shares % MAX_ASSETS;
        Snap memory pre = _snap();
        (uint256 A,, uint256 sigma) = _expectAccrual(pre);
        uint256 a = NexusEEMath.mulDivUp(s, A + V, pre.T + sigma + V);
        (uint256[3] memory tA, uint256[3] memory tS, uint256[3] memory b, uint256 rem, uint256 used) = _simSupply(pre, a);
        uint256 tok = token.balanceOf(who);
        deal(address(token), who, tok + a);
        vm.prank(who);
        (bool ok,) = address(vault).call(abi.encodeCall(IERC4626.mint, (s, who)));
        if (rem == type(uint256).max) ++hBound;
        _afterEnter(ok, rem == 0, pre, who, a, s, tA, tS, b, used);
        _lawTokens(who, ok ? tok : tok + a);
    }

    /// @dev Retiro de hasta lo que valen las acciones del actor y lo retirable por la withdrawQueue; 0 solo devenga.
    function withdraw(uint256 actorSeed, uint256 assets) external {
        address who = _actor(actorSeed);
        Snap memory pre = _snap();
        (uint256 A,, uint256 sigma) = _expectAccrual(pre);
        uint256 own = NexusEEMath.mulDivDown(pre.bal[_idx(who)], A + V, pre.T + sigma + V);
        uint256 a = _clamp(assets, 0, NexusEEMath.min(own, _withdrawable(pre)));
        uint256 s = NexusEEMath.mulDivUp(a, pre.T + sigma + V, A + V);
        (uint256[3] memory tA, uint256[3] memory tS, uint256[3] memory b, uint256 rem) = _simWithdraw(pre, a);
        uint256 tok = token.balanceOf(who);
        vm.prank(who);
        (bool ok,) = address(vault).call(abi.encodeCall(IERC4626.withdraw, (a, who, who)));
        _afterExit(ok, rem == 0 && s <= pre.bal[_idx(who)], pre, who, a, s, tA, tS, b);
        _lawTokens(who, ok ? tok + a : tok);
    }

    /// @dev Canje de hasta las acciones del actor, acotado a lo retirable.
    function redeem(uint256 actorSeed, uint256 shares) external {
        address who = _actor(actorSeed);
        Snap memory pre = _snap();
        (uint256 A,, uint256 sigma) = _expectAccrual(pre);
        uint256 maxS = NexusEEMath.mulDivDown(_withdrawable(pre), pre.T + sigma + V, A + V);
        uint256 s = _clamp(shares, 0, NexusEEMath.min(pre.bal[_idx(who)], maxS));
        uint256 a = NexusEEMath.mulDivDown(s, A + V, pre.T + sigma + V);
        (uint256[3] memory tA, uint256[3] memory tS, uint256[3] memory b, uint256 rem) = _simWithdraw(pre, a);
        uint256 tok = token.balanceOf(who);
        vm.prank(who);
        (bool ok,) = address(vault).call(abi.encodeCall(IERC4626.redeem, (s, who, who)));
        _afterExit(ok, rem == 0, pre, who, a, s, tA, tS, b);
        _lawTokens(who, ok ? tok + a : tok);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 shares) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        Snap memory pre = _snap();
        uint256 s = _clamp(shares, 0, pre.bal[_idx(from)]);
        vm.prank(from);
        vault.transfer(to, s);
        Snap memory post = _snap();
        _lawsStill(pre, post);
        _lawPrice(pre, post);
        uint256 sent = pre.bal[_idx(from)] - post.bal[_idx(from)];
        if (from != to) {
            uint256 got = post.bal[_idx(to)] - pre.bal[_idx(to)];
            _ok(sent == s && got == s, L_LEDGER, "una transferencia no movio lo pedido (pedido, recibido)", s, got);
        }
    }

    /* ESTRATEGIAS (fuera de EulerEarn: rendimiento, pérdida, terceros, donaciones de acciones, pausa) */

    function earn(uint256 which, uint256 gain) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        deal(address(token), address(strat[i]), pre.tA[i] + 1 + gain % MAX_ASSETS);
        _lawsStillPrice(pre);
    }

    /// @dev Pérdida de una estrategia: alcanza al capital de EulerEarn; lostAssets la absorbe en el próximo devengamiento.
    function lose(uint256 which, uint256 amount) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        deal(address(token), address(strat[i]), pre.tA[i] - _clamp(amount, 0, pre.tA[i]));
        _lawsStillPrice(pre);
    }

    /// @dev Un tercero deposita o retira directo en una estrategia: cambia la relación activos/acciones de la que
    /// EulerEarn depende, y con ella el redondeo de previewRedeem.
    function outsider(uint256 which, uint256 amount, bool enter) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        if (pre.paused[i]) return;
        if (enter) {
            uint256 a = 1 + amount % MAX_ASSETS;
            deal(address(token), OUTSIDER, token.balanceOf(OUTSIDER) + a);
            vm.prank(OUTSIDER);
            strat[i].deposit(a, OUTSIDER);
        } else {
            uint256 s = _clamp(amount, 0, strat[i].balanceOf(OUTSIDER));
            vm.prank(OUTSIDER);
            strat[i].redeem(s, OUTSIDER, OUTSIDER);
        }
        _lawsStillPrice(pre);
    }

    /// @dev El tercero le transfiere acciones de una estrategia a EulerEarn: no entran al seguimiento interno.
    function donateShares(uint256 which, uint256 shares) external {
        uint256 i = which % NS;
        uint256 s = _clamp(shares, 0, strat[i].balanceOf(OUTSIDER));
        if (s == 0) return;
        Snap memory pre = _snap();
        vm.prank(OUTSIDER);
        strat[i].transfer(address(vault), s);
        gExtra[i] += s;
        ++hDonations;
        _lawsStillPrice(pre);
    }

    function pause(uint256 which, bool p) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        strat[i].setPaused(p);
        _lawsStillPrice(pre);
    }

    function warp(uint256 secs) external {
        vm.warp(hClock.time() + 1 + secs % (30 days));
    }

    /* COMISIÓN (el owner la cambia en el acto: devenga antes con la vieja) */

    function setFee(uint256 v) external {
        Snap memory pre = _snap();
        uint256 f = _clamp(v, 0, MAX_FEE + 0.1e18);
        address rec = vault.feeRecipient();
        bool expect = f != pre.f && f <= MAX_FEE && (f == 0 || rec != address(0));
        vm.prank(OWNER);
        (bool ok,) = address(vault).call(abi.encodeCall(IEulerEarnBase.setFee, (f)));
        _afterGov(ok, expect, pre);
        if (ok) _ok(vault.fee() == f, L_LIVE, "la comision no quedo en el valor pedido (pedido, real)", f, vault.fee());
    }

    function setFeeRecipient(bool toFee) external {
        Snap memory pre = _snap();
        address rec = toFee ? FEE : address(0);
        bool expect = rec != vault.feeRecipient() && (rec != address(0) || pre.f == 0);
        vm.prank(OWNER);
        (bool ok,) = address(vault).call(abi.encodeCall(IEulerEarnBase.setFeeRecipient, (rec)));
        _afterGov(ok, expect, pre);
    }

    /* ALLOCATOR Y CURADOR: reallocate, colas, topes y remoción (timelock 0 en el harness) */

    /// @dev Mueve capital de `from` a `to`: retira `amount` (o todo con assets 0, que canjea las acciones seguidas) y lo
    /// pone en `to` con type(uint256).max. Pasa si y solo si el modelo lo dice: habilitadas, sin pausa (reallocate no
    /// tiene try/catch), dentro del tope, sin desborde del uint112 y lo retirado igual a lo puesto. No toca
    /// lastTotalAssets ni totalSupply: la diferencia de redondeo aparece en el próximo devengamiento.
    function reallocate(uint256 fromSeed, uint256 toSeed, uint256 amount, bool all) external {
        uint256 f = fromSeed % NS;
        Snap memory pre = _snap();
        uint256 supplyF = _redeem(f, pre.b[f], pre.tA[f], pre.tS[f]);
        MarketAllocation[] memory al = new MarketAllocation[](2);
        al[0] = MarketAllocation(IERC4626(address(strat[f])), all ? 0 : supplyF - _clamp(amount, 0, supplyF));
        al[1] = MarketAllocation(IERC4626(address(strat[toSeed % NS])), type(uint256).max);
        (bool expect, uint256[3] memory tA, uint256[3] memory tS, uint256[3] memory b) = _simReallocate(pre, al);
        vm.prank(ALLOCATOR);
        (bool ok,) = address(vault).call(abi.encodeCall(IEulerEarnBase.reallocate, (al)));
        Snap memory post = _snap();
        _ok(ok == expect, L_LIVE, ok ? "reallocate paso y el modelo decia que revertia (desde, hacia)" : "reallocate revirtio y el modelo decia que pasaba (desde, hacia)", f, toSeed % NS);
        _lawsStill(pre, post);
        _lawPrice(pre, post);
        if (!ok) {
            ++hRejected;
            return;
        }
        _lawStrategies(post, tA, tS, b);
        ++hReallocs;
    }

    /// @dev Replica reallocate sobre la foto `s`.
    function _simReallocate(Snap memory s, MarketAllocation[] memory al)
        internal
        view
        returns (bool, uint256[3] memory tA, uint256[3] memory tS, uint256[3] memory b)
    {
        for (uint256 i; i < NS; ++i) {
            (tA[i], tS[i], b[i]) = (s.tA[i], s.tS[i], s.b[i]);
        }
        uint256 tw;
        uint256 ts;
        for (uint256 k; k < al.length; ++k) {
            uint256 i = _sIdx(address(al[k].id));
            if (!s.enabled[i]) return (false, tA, tS, b);
            uint256 supplyAssets = _redeem(i, b[i], tA[i], tS[i]);
            uint256 withdrawn = NexusEEMath.zeroFloorSub(supplyAssets, al[k].assets);
            if (withdrawn > 0) {
                if (s.paused[i]) return (false, tA, tS, b);
                uint256 wa = al[k].assets == 0 ? supplyAssets : withdrawn;
                uint256 wsh = al[k].assets == 0 ? b[i] : NexusEEMath.mulDivUp(withdrawn, tS[i] + _scale(i), tA[i] + 1);
                if (wsh > b[i]) return (false, tA, tS, b);
                (b[i], tA[i], tS[i]) = (b[i] - wsh, tA[i] - wa, tS[i] - wsh);
                tw += wa;
            } else {
                uint256 sup = al[k].assets == type(uint256).max
                    ? NexusEEMath.zeroFloorSub(tw, ts)
                    : NexusEEMath.zeroFloorSub(al[k].assets, supplyAssets);
                if (sup == 0) continue;
                if (supplyAssets + sup > s.cap[i] || s.paused[i]) return (false, tA, tS, b);
                if (!NexusEEMath.fits(sup, tS[i] + _scale(i))) return (false, tA, tS, b);
                uint256 sh = NexusEEMath.mulDivDown(sup, tS[i] + _scale(i), tA[i] + 1);
                if (b[i] + sh > type(uint112).max) return (false, tA, tS, b);
                (b[i], tA[i], tS[i]) = (b[i] + sh, tA[i] + sup, tS[i] + sh);
                ts += sup;
            }
        }
        return (tw == ts, tA, tS, b);
    }

    /// @dev Nueva supplyQueue de 1 a 4 entradas (puede repetir): pasa si y solo si todas tienen tope.
    function setSupplyQueue(uint256 seed, uint256 len) external {
        Snap memory pre = _snap();
        uint256 n = 1 + len % 4;
        IERC4626[] memory q = new IERC4626[](n);
        bool expect = true;
        for (uint256 k; k < n; ++k) {
            uint256 i = (seed >> (8 * k)) % NS;
            q[k] = IERC4626(address(strat[i]));
            if (pre.cap[i] == 0) expect = false;
        }
        vm.prank(ALLOCATOR);
        (bool ok,) = address(vault).call(abi.encodeCall(IEulerEarnBase.setSupplyQueue, (q)));
        _afterQueue(ok, expect, pre, n);
        if (ok) {
            for (uint256 k; k < n; ++k) {
                _ok(address(vault.supplyQueue(k)) == address(q[k]), L_LIVE, "la supplyQueue no quedo como se pidio (posicion, 0)", k, 0);
            }
        }
    }

    /// @dev Rota la withdrawQueue y, con `drop`, deja afuera una estrategia: pasa si y solo si la que sale tiene tope 0,
    /// ningún tope pendiente y, si todavía vale algo, su remoción vencida. La que sale deja sus acciones sin seguir (su
    /// valor pasa a lostAssets en el próximo devengamiento).
    function updateWithdrawQueue(uint256 seed, bool drop) external {
        Snap memory pre = _snap();
        uint256 n = pre.wq.length;
        if (n == 0 || (drop && n == 1)) return;
        uint256 m = drop ? n - 1 : n;
        uint256 rot = seed % n;
        uint256[] memory idx = new uint256[](m);
        for (uint256 k; k < m; ++k) {
            idx[k] = (k + rot) % n;
        }
        bool expect = true;
        uint256 out = NS;
        if (drop) {
            out = pre.wq[(m + rot) % n];
            if (pre.cap[out] != 0 || pre.pendAt[out] != 0) expect = false;
            else if (_redeem(out, pre.b[out], pre.tA[out], pre.tS[out]) != 0) {
                expect = pre.rmAt[out] != 0 && pre.ts >= pre.rmAt[out];
            }
        }
        vm.prank(ALLOCATOR);
        (bool ok,) = address(vault).call(abi.encodeCall(IEulerEarnBase.updateWithdrawQueue, (idx)));
        if (ok && out < NS) gExtra[out] += pre.b[out];
        _afterQueue(ok, expect, pre, m);
        if (ok && out < NS) {
            (uint112 b, uint136 cap, bool enabled, uint64 rmAt) = IEEStaticH(address(vault)).config(IERC4626(address(strat[out])));
            _ok(b == 0 && cap == 0 && !enabled && rmAt == 0, L_STRAT, "la estrategia removida no quedo borrada (acciones, tope)", b, cap);
            ++hRemovals;
        }
    }

    /// @dev Tope de una estrategia: bajarlo es inmediato; subirlo pasa por submitCap y acceptCap (timelock 0). El alta
    /// de una estrategia nueva o removida adopta sus acciones reales y suma su valor a lastTotalAssets sin comisión.
    function setCap(uint256 which, uint256 value) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        uint256 v = value % 4 == 0 ? 0 : _clamp(value, 1, 2 * CAP_BIG);
        IERC4626 id = IERC4626(address(strat[i]));
        bool expect = v != pre.cap[i] && pre.pendAt[i] == 0 && pre.rmAt[i] == 0;
        vm.prank(CURATOR);
        (bool ok,) = address(vault).call(abi.encodeCall(IEulerEarnBase.submitCap, (id, v)));
        _ok(ok == expect, L_LIVE, ok ? "submitCap paso y el modelo decia que revertia (pedido, tope)" : "submitCap revirtio y el modelo decia que pasaba (pedido, tope)", v, pre.cap[i]);
        if (!ok) {
            ++hRejected;
            return _lawsStillPrice(pre);
        }
        uint256 addL;
        if (v > pre.cap[i]) {
            (ok,) = address(vault).call(abi.encodeCall(IEulerEarnBase.acceptCap, (id)));
            _ok(ok, L_LIVE, "acceptCap revirtio con el timelock vencido (pedido, tope)", v, pre.cap[i]);
            if (!pre.enabled[i]) {
                addL = _redeem(i, pre.real[i], pre.tA[i], pre.tS[i]);
                gExtra[i] = 0;
                ++hEnables;
            }
        }
        Snap memory post = _snap();
        _ok(post.cap[i] == v, L_LIVE, "el tope no quedo en el valor pedido (pedido, real)", v, post.cap[i]);
        _ok(post.L == pre.L + addL, L_TA, "el alta no sumo a lastTotalAssets el valor de la estrategia (esperado, real)", pre.L + addL, post.L);
        _ok(post.P == pre.P && post.T == pre.T, L_TA, "un cambio de tope cambio lostAssets o totalSupply (antes, despues)", pre.P, post.P);
        uint256 expB = addL > 0 || (v > pre.cap[i] && !pre.enabled[i]) ? pre.real[i] : pre.b[i];
        _ok(post.b[i] == expB, L_STRAT, "el alta no adopto las acciones reales (esperado, real)", expB, post.b[i]);
        _lawTracking(post);
        _lawLedger(post);
        _lawPrice(pre, post);
    }

    /// @dev Remoción de una estrategia con tope 0: removableAt = ahora + timelock (0).
    function submitMarketRemoval(uint256 which) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        bool expect = pre.rmAt[i] == 0 && pre.cap[i] == 0 && pre.enabled[i] && pre.pendAt[i] == 0;
        vm.prank(CURATOR);
        (bool ok,) = address(vault).call(abi.encodeCall(IEulerEarnBase.submitMarketRemoval, (IERC4626(address(strat[i])))));
        _ok(ok == expect, L_LIVE, ok ? "submitMarketRemoval paso y el modelo decia que revertia (estrategia, 0)" : "submitMarketRemoval revirtio y el modelo decia que pasaba (estrategia, 0)", i, 0);
        if (!ok) ++hRejected;
        _lawsStillPrice(pre);
    }

    /// @dev Ciclo de vida de una estrategia, cada paso contra el modelo: tope 0, remoción, salida de la withdrawQueue
    /// (si todavía vale algo, su valor pasa a lostAssets en el próximo devengamiento) y, con `back`, el alta de nuevo con
    /// tope grande: adopta sus acciones reales y suma su valor a lastTotalAssets otra vez (el L-09 reconocido de Pashov:
    /// queda contado en lostAssets y en lastTotalAssets; el precio solo sube).
    function retire(uint256 which, bool back) external {
        uint256 i = which % NS;
        this.setCap(i, 0);
        this.submitMarketRemoval(i);
        uint256 n = vault.withdrawQueueLength();
        uint256 pos = n;
        for (uint256 k; k < n; ++k) {
            if (address(vault.withdrawQueue(k)) == address(strat[i])) pos = k;
        }
        if (pos == n || n == 1) return;
        this.updateWithdrawQueue((pos + 1) % n, true); // rot tal que la que queda afuera es la de la posición pos
        if (back) this.setCap(i, CAP_BIG - 1);
    }

    function _afterQueue(bool ok, bool expect, Snap memory pre, uint256 n) internal {
        _ok(ok == expect, L_LIVE, ok ? "un cambio de cola paso y el modelo decia que revertia (largo, 0)" : "un cambio de cola valido revirtio (largo, 0)", n, 0);
        if (!ok) ++hRejected;
        _lawsStillPrice(pre);
    }

    /* COMÚN */

    function _afterEnter(
        bool ok,
        bool expect,
        Snap memory pre,
        address who,
        uint256 a,
        uint256 s,
        uint256[3] memory tA,
        uint256[3] memory tS,
        uint256[3] memory b,
        uint256 used
    ) internal {
        Snap memory post = _snap();
        _ok(ok == expect, L_LIVE, ok ? "una entrada paso y el modelo decia que revertia (monto, acciones)" : "una entrada revirtio y el modelo decia que pasaba (monto, acciones)", a, s);
        if (!ok) {
            ++hRejected;
            return _lawsStill(pre, post);
        }
        (uint256 A,,) = _expectAccrual(pre);
        uint256 got = post.bal[_idx(who)] - pre.bal[_idx(who)];
        _ok(got == s, L_INF1, "acciones acunadas distintas de la conversion (modelo, real)", s, got);
        _lawsAccrual(pre, post, A + a, s, true, who);
        _lawStrategies(post, tA, tS, b);
        _lawBystanders(pre, post, who);
        _lawLedger(post);
        if (used > 1) ++hSpills;
        if (_anyPaused(pre)) ++hSkips;
    }

    function _afterExit(
        bool ok,
        bool expect,
        Snap memory pre,
        address who,
        uint256 a,
        uint256 s,
        uint256[3] memory tA,
        uint256[3] memory tS,
        uint256[3] memory b
    ) internal {
        Snap memory post = _snap();
        _ok(ok == expect, L_LIVE, ok ? "una salida paso y el modelo decia que revertia (monto, acciones)" : "una salida revirtio y el modelo decia que pasaba (monto, acciones)", a, s);
        if (!ok) {
            ++hRejected;
            return _lawsStill(pre, post);
        }
        (uint256 A,,) = _expectAccrual(pre);
        uint256 burned = pre.bal[_idx(who)] - post.bal[_idx(who)];
        _ok(burned == s, L_INF1, "acciones quemadas distintas de la conversion (modelo, real)", s, burned);
        _lawsAccrual(pre, post, NexusEEMath.zeroFloorSub(A, a), s, false, who);
        _lawStrategies(post, tA, tS, b);
        _lawBystanders(pre, post, who);
        _lawLedger(post);
        if (_anyPaused(pre)) ++hSkips;
    }

    /// @dev Operaciones del owner que solo devengan antes de cambiar (comisión y receptor).
    function _afterGov(bool ok, bool expect, Snap memory pre) internal {
        Snap memory post = _snap();
        _ok(ok == expect, L_LIVE, ok ? "un cambio de comision paso y el modelo decia que revertia (0, 1)" : "un cambio de comision valido revirtio (1, 0)", ok ? 0 : 1, ok ? 1 : 0);
        if (!ok) {
            ++hRejected;
            return _lawsStill(pre, post);
        }
        (uint256 A,,) = _expectAccrual(pre);
        _lawsAccrual(pre, post, A, 0, true, address(0));
        _lawStrategies(post, pre.tA, pre.tS, pre.b);
        _lawLedger(post);
    }

    /// @dev E-INF-1: el vault tomó o pagó exactamente lo que dice la conversión (saldo del token del actor).
    function _lawTokens(address who, uint256 expected) internal {
        uint256 got = token.balanceOf(who);
        _ok(got == expected, L_INF1, "el vault no tomo o no pago exactamente la conversion (esperado, saldo)", expected, got);
    }

    function _lawsStillPrice(Snap memory pre) internal {
        Snap memory post = _snap();
        _lawsStill(pre, post);
        _lawPrice(pre, post);
    }

    /// @dev E-LEDGER: fuera de quien opera y del receptor de la comisión, ningún saldo cambia.
    function _lawBystanders(Snap memory pre, Snap memory post, address who) internal {
        for (uint256 i; i < 4; ++i) {
            if (actors[i] == who) continue;
            _ok(post.bal[i] == pre.bal[i], L_LEDGER, "cambio el saldo de un tercero (antes, despues)", pre.bal[i], post.bal[i]);
        }
    }

    function _anyPaused(Snap memory s) internal pure returns (bool) {
        return s.paused[0] || s.paused[1] || s.paused[2];
    }

    function _idx(address who) internal view returns (uint256) {
        for (uint256 i; i < 4; ++i) {
            if (actors[i] == who) return i;
        }
        return 4;
    }
}

contract NexusEulerEarnInvariantTest is Test {
    NexusEulerEarnHandler internal handler;

    function setUp() public virtual {
        handler = new NexusEulerEarnHandler(_fee(), _assetDecimals());
        targetContract(address(handler));
    }

    function _fee() internal pure virtual returns (uint256) {
        return 0;
    }

    function _assetDecimals() internal pure virtual returns (uint8) {
        return 18;
    }

    function invariant_eulerEarn() public view {
        string memory err = handler.check();
        assertEq(bytes(err).length, 0, err);
    }

    function afterInvariant() public {
        (uint256 laws, uint256 checks_, uint256 feeShares) = handler.stats();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("verificaciones de devengamiento", checks_);
        emit log_named_uint("cazador: acciones de comision acunadas", feeShares);
        (uint256 losses, uint256 interest, uint256 spills, uint256 skips, uint256 rejected, uint256 donations) =
            handler.coverage();
        emit log_named_uint("cobertura: devengamientos que subieron lostAssets", losses);
        emit log_named_uint("cobertura: devengamientos con interes", interest);
        emit log_named_uint("cobertura: depositos repartidos en mas de una estrategia", spills);
        emit log_named_uint("cobertura: operaciones con una estrategia pausada", skips);
        emit log_named_uint("cobertura: operaciones rechazadas como predijo el modelo", rejected);
        emit log_named_uint("cobertura: donaciones de acciones de estrategias", donations);
        emit log_named_uint("cota: depositos que revientan el uint112 de una estrategia (E-BOUND)", handler.coverageBound());
        (uint256 reallocs, uint256 removals, uint256 enables) = handler.coverage2();
        emit log_named_uint("cobertura: reallocate con efecto", reallocs);
        emit log_named_uint("cobertura: estrategias removidas de la withdrawQueue", removals);
        emit log_named_uint("cobertura: altas de estrategias (nuevas o removidas)", enables);
    }
}

contract NexusEulerEarnInvariantFeeTest is NexusEulerEarnInvariantTest {
    function _fee() internal pure override returns (uint256) {
        return 0.2e18;
    }
}

contract NexusEulerEarnInvariantSixDecimalsTest is NexusEulerEarnInvariantTest {
    function _assetDecimals() internal pure override returns (uint8) {
        return 6;
    }
}

/// @notice E-BOUND con un escenario determinista: la estrategia de offset 6 (primera en la supplyQueue) recibe un
/// depósito y pierde todos sus activos; el depósito siguiente la encuentra con lugar en su tope y precio casi 0, acuña
/// más acciones de las que entran en el uint112 del seguimiento interno y revierte entero (el cast está en el bloque de
/// éxito del try). El modelo lo predice (E-LIVE) y ninguna ley falla. Es el borde del dominio tras una pérdida total de
/// una estrategia: lo deshace el allocator sacándola de la supplyQueue; no es un hallazgo.
contract NexusEulerEarnBoundTest is Test {
    function test_ebound_deposito_tras_la_perdida_total_de_una_estrategia() public {
        NexusEulerEarnHandler h = new NexusEulerEarnHandler(0, 18);
        h.deposit(0, 1e24 - 1); // 1e24 a la estrategia 2 (offset 6): 1e30 acciones internas
        h.lose(2, 1e24); // pierde todo
        h.deposit(1, 1e18 - 1); // 1e18 a precio ~0: ~1e48 acciones, no entran en uint112
        assertEq(h.coverageBound(), 1, "el modelo predijo la reversion por el uint112");
        assertEq(bytes(h.check()).length, 0, h.check());
    }
}
