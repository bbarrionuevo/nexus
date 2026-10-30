// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

// Handler e invariantes del cazador de TokenizedStrategy v3.1.0, en cuatro variantes: contabilidad en vivo
// ("constant accrual") con comisión de desempeño, con comisión de desempeño y del protocolo, contabilidad por
// reporte (la de la v3.0.4) y activo de 6 decimales. Cada acción pasa por las leyes Y-... de
// NexusTokenizedStrategyHunter.sol: el modelo predice si pasa (Y-LIVE), el estado crudo exacto que deja, lo que dicen
// las vistas antes (Y-VIEW-1) y durante los callbacks (Y-REENT-1), y que el precio no baje sin una pérdida (Y-INF-2).

import {Test} from "forge-std/Test.sol";
import {NexusTSHunter, NexusTSBase, NexusTSMath} from "./NexusTokenizedStrategyHunter.sol";

contract NexusTokenizedStrategyHandler is NexusTSHunter {
    uint256 internal hSandwich;
    uint256 internal hOrphan; // entradas con suministro 0 y activos en la estrategia: el depósito 1:1 se los lleva

    constructor(bool live, uint8 dec, uint16 perfFee, uint16 protoFee) NexusTSBase(live, dec, perfFee, protoFee) {
        _hunterInit();
    }

    function coverage3() external view returns (uint256 sandwiches) {
        return hSandwich;
    }

    function coverage4() external view returns (uint256 orphans) {
        return hOrphan;
    }

    function coverage5() external view returns (uint256 overflow, uint256 domain) {
        return (hOverflow, hDomain);
    }

    /// @dev Montos: un cuarto de las veces polvo (1 a 1e4 unidades), si no hasta MAX_ASSETS.
    function _amt(uint256 seed) internal view returns (uint256) {
        if (seed % 4 == 0) return 1 + (seed >> 2) % 1e4;
        return 1 + (seed >> 2) % MAX_ASSETS;
    }

    /* USUARIOS */

    function deposit(uint256 actorSeed, uint256 amount) external {
        uint256 h = actorSeed % 4;
        uint256 a = _amt(amount);
        deal(address(token), actors[h], token.balanceOf(actors[h]) + a);
        _enter(h, a, false);
    }

    /// @dev deposit(type(uint256).max): deposita todo el saldo del actor.
    function depositAll(uint256 actorSeed, uint256 amount) external {
        uint256 h = actorSeed % 4;
        deal(address(token), actors[h], _amt(amount));
        _enter(h, type(uint256).max, false);
    }

    function mint(uint256 actorSeed, uint256 shares) external {
        uint256 h = actorSeed % 4;
        uint256 s = _amt(shares);
        (uint256 sup, uint256 ta) = _sim(_snap());
        deal(address(token), actors[h], token.balanceOf(actors[h]) + _c2a(s, sup, ta, true));
        _enter(h, s, true);
    }

    function _enter(uint256 h, uint256 amt, bool isMint) internal {
        Snap memory pre = _snap();
        _lawViews(pre, h);
        uint256 preview = _previewEnter(pre, h, amt, isMint);
        (Op memory o, Snap memory m) = _modelEnter(pre, h, amt, isMint);
        if (o.ok && m.TS > S_CAP) {
            ++hDomain;
            return;
        }
        source.resetSeen();
        vm.prank(actors[h]);
        (bool ok, bytes memory ret) = address(strategy).call(
            isMint
                ? abi.encodeWithSignature("mint(uint256,address)", amt, actors[h])
                : abi.encodeWithSignature("deposit(uint256,address)", amt, actors[h])
        );
        _settle(isMint ? "mint" : "deposit", ok, o.ok, pre, m, true);
        if (!ok || !o.ok) return;
        uint256 got = abi.decode(ret, (uint256));
        uint256 exp = isMint ? o.assets : o.shares;
        _ok(got == exp, L_INF1, "la entrada devolvio otra cosa que la conversion (modelo, real)", exp, got);
        _ok(preview == got, L_VIEW, "la preview de la entrada no es la ejecucion (preview, ejecucion)", preview, got);
        _lawProbe(o.probe, o.vL, o.vS);
        _countOp(pre, o);
        if (o.vS == 0 && o.vL != 0) ++hOrphan;
    }

    function _previewEnter(Snap memory pre, uint256 h, uint256 amt, bool isMint) internal returns (uint256 p) {
        (uint256 sup, uint256 ta) = _sim(pre);
        if (isMint) {
            p = ts.previewMint(amt);
            uint256 e = _c2a(amt, sup, ta, true);
            _ok(p == e, L_VIEW, "previewMint distinto del modelo (modelo, real)", e, p);
        } else {
            uint256 a = amt == type(uint256).max ? pre.cash[h] : amt;
            p = ts.previewDeposit(a);
            uint256 e = _c2s(a, sup, ta, false);
            _ok(p == e, L_VIEW, "previewDeposit distinto del modelo (modelo, real)", e, p);
        }
    }

    /// @dev Retiro de hasta maxWithdraw (un octavo de las veces, uno de más: tiene que revertir).
    function withdraw(uint256 actorSeed, uint256 amount, uint256 lossSeed) external {
        uint256 h = actorSeed % 4;
        Snap memory pre = _snap();
        (uint256 sup, uint256 ta) = _sim(pre);
        uint256 mw = _maxW(pre, h, sup, ta);
        uint256 a = amount % 8 == 0 ? mw + 1 : _clamp(amount >> 3, 1, mw);
        _exit(h, a, false, lossSeed, pre);
    }

    function redeem(uint256 actorSeed, uint256 amount, uint256 lossSeed) external {
        uint256 h = actorSeed % 4;
        Snap memory pre = _snap();
        (uint256 sup, uint256 ta) = _sim(pre);
        uint256 mr = _maxR(pre, h, sup, ta);
        uint256 s = amount % 8 == 0 ? mr + 1 : _clamp(amount >> 3, 1, mr);
        _exit(h, s, true, lossSeed, pre);
    }

    /// @dev maxLoss: la firma estándar (withdraw 0, redeem 100 %) o la de cuatro argumentos con 0, 1, 100 o 10.000 bps.
    function _maxLoss(uint256 seed, bool isRedeem) internal pure returns (bool std, uint256 maxLoss) {
        if (seed % 4 == 0) return (true, isRedeem ? MAX_BPS : 0);
        uint256 k = (seed >> 2) % 4;
        maxLoss = k == 0 ? 0 : (k == 1 ? 1 : (k == 2 ? 100 : MAX_BPS));
    }

    function _exitCall(uint256 h, uint256 amt, bool isRedeem, bool std, uint256 maxLoss)
        internal
        view
        returns (bytes memory)
    {
        address a = actors[h];
        if (std) {
            return isRedeem
                ? abi.encodeWithSignature("redeem(uint256,address,address)", amt, a, a)
                : abi.encodeWithSignature("withdraw(uint256,address,address)", amt, a, a);
        }
        return isRedeem
            ? abi.encodeWithSignature("redeem(uint256,address,address,uint256)", amt, a, a, maxLoss)
            : abi.encodeWithSignature("withdraw(uint256,address,address,uint256)", amt, a, a, maxLoss);
    }

    function _exit(uint256 h, uint256 amt, bool isRedeem, uint256 lossSeed, Snap memory pre) internal {
        _lawViews(pre, h);
        (bool std, uint256 maxLoss) = _maxLoss(lossSeed, isRedeem);
        uint256 preview = _previewExit(pre, amt, isRedeem);
        (Op memory o, Snap memory m) = _modelExit(pre, h, amt, isRedeem, maxLoss);
        if (o.ok && m.TS > S_CAP) {
            ++hDomain;
            return;
        }
        source.resetSeen();
        vm.prank(actors[h]);
        (bool ok, bytes memory ret) = address(strategy).call(_exitCall(h, amt, isRedeem, std, maxLoss));
        _settle(isRedeem ? "redeem" : "withdraw", ok, o.ok, pre, m, true);
        if (!ok || !o.ok) return;
        uint256 got = abi.decode(ret, (uint256));
        uint256 exp = isRedeem ? o.assets : o.shares;
        _ok(got == exp, L_INF1, "la salida devolvio otra cosa que la conversion (modelo, real)", exp, got);
        // con una pérdida del retiro, redeem paga menos que su preview; withdraw quema lo mismo
        if (!isRedeem || o.loss == 0) {
            _ok(preview == got, L_VIEW, "la preview de la salida no es la ejecucion (preview, ejecucion)", preview, got);
        }
        if (o.loss != 0) ++hWithdrawLoss;
        _lawProbe(o.probe, o.vL, o.vS);
        _countOp(pre, o);
    }

    function _previewExit(Snap memory pre, uint256 amt, bool isRedeem) internal returns (uint256 p) {
        (uint256 sup, uint256 ta) = _sim(pre);
        if (isRedeem) {
            p = ts.previewRedeem(amt);
            uint256 e = _c2a(amt, sup, ta, false);
            _ok(p == e, L_VIEW, "previewRedeem distinto del modelo (modelo, real)", e, p);
        } else {
            p = ts.previewWithdraw(amt);
            uint256 e = _c2s(amt, sup, ta, true);
            _ok(p == e, L_VIEW, "previewWithdraw distinto del modelo (modelo, real)", e, p);
        }
    }

    /// @dev Transferencia entre actores (no devenga); a la estrategia tiene que revertir.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 shares) external {
        uint256 f = fromSeed % 4;
        uint256 t = toSeed % 4;
        Snap memory pre = _snap();
        uint256 s = _clamp(shares, 0, pre.bal[f]);
        Snap memory m = _copy(pre);
        m.bal[f] -= s;
        m.bal[t] += s;
        vm.prank(actors[f]);
        (bool ok,) = address(strategy).call(abi.encodeWithSignature("transfer(address,uint256)", actors[t], s));
        _settle("transfer", ok, true, pre, m, true);
        vm.prank(actors[f]);
        (ok,) = address(strategy).call(abi.encodeWithSignature("transfer(address,uint256)", address(strategy), s));
        _ok(!ok, L_LIVE, "una transferencia a la estrategia paso (acciones, 0)", s, 0);
    }

    /* FUENTE Y ESTRATEGIA (fuera de TokenizedStrategy: rendimiento, pérdidas, liquidez, perillas) */

    /// @dev Ganancia en vivo: la estimación sube (en modo por reporte, entra recién en el reporte).
    function liveProfit(uint256 amount) external {
        Snap memory pre = _snap();
        deal(address(token), address(source), pre.tok + _amt(amount));
        _env(pre, false, true);
    }

    /// @dev Pérdida en vivo del valor real de la fuente.
    function liveLoss(uint256 amount) external {
        Snap memory pre = _snap();
        uint256 real = pre.tok > pre.pr + pre.pl ? pre.tok - pre.pr - pre.pl : 0;
        deal(address(token), address(source), pre.tok - _clamp(amount, 0, real));
        _env(pre, true, false);
    }

    /// @dev Recompensa que la estimación no ve hasta la cosecha del reporte.
    function queueReward(uint256 amount) external {
        Snap memory pre = _snap();
        uint256 x = _amt(amount);
        deal(address(token), address(source), pre.tok + x);
        source.addPending(x, 0);
        _env(pre, false, false);
    }

    /// @dev Pérdida escondida: la estimación la sigue contando hasta la cosecha del reporte.
    function queueLoss(uint256 amount) external {
        Snap memory pre = _snap();
        uint256 real = pre.tok > pre.pr + pre.pl ? pre.tok - pre.pr - pre.pl : 0;
        source.addPending(0, _clamp(amount, 0, real));
        _env(pre, false, false);
    }

    /// @dev Activo donado directo a la estrategia (ocioso): en vivo es ganancia; por reporte, entra en el reporte.
    function donateIdle(uint256 amount) external {
        Snap memory pre = _snap();
        deal(address(token), address(strategy), pre.idle + _amt(amount));
        _env(pre, false, true);
    }

    /// @dev Tope de liquidez de la fuente: un tercio de las veces, limitado.
    function setLiquidity(uint256 v) external {
        Snap memory pre = _snap();
        source.setLiquidity(v % 3 != 1 ? type(uint256).max : _amt(v >> 2));
        _env(pre, false, false);
    }

    /// @dev Perillas de la estrategia: cuánto coloca (a veces nada o una parte), tope de depósito (un cuarto de las
    /// veces) y límite de retiro a lo líquido (un tercio).
    function setKnobs(uint256 bps, uint256 cap, uint256 lw) external {
        Snap memory pre = _snap();
        uint256 b = bps % 3 == 0 ? MAX_BPS : bps % (MAX_BPS + 1);
        uint256 c = cap % 4 != 1 ? type(uint256).max : pre.L + _amt(cap >> 2);
        strategy.setKnobs(b, c, lw % 3 == 1);
        _env(pre, false, false);
    }

    /// @dev Una acción fuera de TokenizedStrategy no cambia su almacenamiento. El precio simulado solo puede bajar por
    /// una pérdida (`lossy`) o por el redondeo del piso de acciones muertas; con ganancia en vivo que entra (`profit`),
    /// a lo sumo por el piso de las acciones de comisión, menos de una acción (_lawPriceTol); si no, no se mueve.
    function _env(Snap memory pre, bool lossy, bool profit) internal {
        Snap memory post = _snap();
        _lawStill(pre, post);
        _lawViews(post, post.ts % 4);
        if (lossy || _simMoves(post)) return;
        if (profit) _lawPriceTol(pre, post);
        else _lawPrice(pre, post);
    }

    /* KEEPER */

    function report() external {
        Snap memory pre = _snap();
        _lawViews(pre, 0);
        (Rep memory r, Snap memory m) = _modelReport(pre);
        if (r.ok && m.TS > S_CAP) {
            ++hDomain;
            return;
        }
        source.resetSeen();
        vm.prank(KEEPER);
        (bool ok, bytes memory ret) = address(strategy).call(abi.encodeWithSignature("report()"));
        _settle("report", ok, r.ok, pre, m, r.nw >= r.vL);
        if (!ok || !r.ok) return;
        (uint256 p, uint256 l) = abi.decode(ret, (uint256, uint256));
        _ok(p == r.profit && l == r.loss, L_TA, "report devolvio otra ganancia o perdida (modelo, real)", r.profit + r.loss, p + l);
        _lawProbe(true, r.vL, r.vS);
        _countAcc(r.acc);
        if (r.profit != 0) ++hReportProfit;
        if (r.loss != 0) ++hReportLoss;
        if (r.plt != 0) ++hRelock;
    }

    function tend() external {
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool probe = _deploy(m, m.idle);
        source.resetSeen();
        vm.prank(KEEPER);
        (bool ok,) = address(strategy).call(abi.encodeWithSignature("tend()"));
        _settle("tend", ok, true, pre, m, true);
        if (ok) _lawProbe(probe, pre.L, _eff(pre));
    }

    /* MANAGEMENT Y EMERGENCIA */

    function setPerformanceFee(uint256 v) external {
        uint256 f = v % 7 == 0 ? MAX_FEE + 1 + (v >> 3) % 1000 : (v >> 3) % (MAX_FEE + 1);
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool expect = f <= MAX_FEE;
        Acc memory a;
        if (expect) {
            (expect, a, m) = _modelAccrue(pre);
            m.fee = f;
        }
        if (expect && m.TS > S_CAP) {
            ++hDomain;
            return;
        }
        vm.prank(MGMT);
        (bool ok,) = address(strategy).call(abi.encodeWithSignature("setPerformanceFee(uint16)", uint16(f)));
        _settle("setPerformanceFee", ok, expect, pre, m, true);
        if (ok) _countAcc(a);
    }

    function setPerformanceFeeRecipient(uint256 seed) external {
        Snap memory pre = _snap();
        uint256 idx = pre.feeIdx == H_FEE_A ? H_FEE_B : H_FEE_A;
        address rec = seed % 8 == 0 ? address(0) : (seed % 8 == 1 ? address(strategy) : _holder(idx));
        bool expect = rec != address(0) && rec != address(strategy);
        Snap memory m = _copy(pre);
        Acc memory a;
        if (expect) {
            (expect, a, m) = _modelAccrue(pre);
            m.feeIdx = idx;
        }
        if (expect && m.TS > S_CAP) {
            ++hDomain;
            return;
        }
        vm.prank(MGMT);
        (bool ok,) = address(strategy).call(abi.encodeWithSignature("setPerformanceFeeRecipient(address)", rec));
        _settle("setPerformanceFeeRecipient", ok, expect, pre, m, true);
        if (ok) _countAcc(a);
    }

    /// @dev 0 (desbloquea todo de golpe), más que un uint32 (se recorta), 10 días o hasta 30 días.
    function setProfitMaxUnlockTime(uint256 v) external {
        uint256 k = v % 16;
        uint256 t = k == 0 ? 0 : (k == 1 ? uint256(type(uint32).max) + 1 + (v >> 4) % 1000 : (k < 6 ? 10 days : 1 + (v >> 4) % 30 days));
        Snap memory pre = _snap();
        (bool expect, Acc memory a, Snap memory m) = _modelAccrue(pre);
        uint256 c = t > type(uint32).max ? type(uint32).max : t;
        if (expect && c == 0) {
            if (m.B != 0) _burnB(m, m.B);
            m.R = 0;
            m.D = 0;
        }
        m.T = c;
        if (expect && m.TS > S_CAP) {
            ++hDomain;
            return;
        }
        vm.prank(MGMT);
        (bool ok,) = address(strategy).call(abi.encodeWithSignature("setProfitMaxUnlockTime(uint256)", t));
        _settle("setProfitMaxUnlockTime", ok, expect, pre, m, true);
        if (ok) _countAcc(a);
    }

    /// @dev Pausar: management o emergencyAdmin; despausar: solo management. Un actor nunca puede. Solo un tercio de
    /// los pedidos de pausa se intentan (los otros pasan a despausar), para no dejar la estrategia pausada.
    function setPaused(bool p, uint256 whoSeed) external {
        if (p && (whoSeed >> 2) % 3 != 0) p = false;
        uint256 k = whoSeed % 3;
        address who = k == 0 ? EMERGENCY : (k == 1 ? MGMT : actors[whoSeed % 4]);
        bool expect = p ? (who == EMERGENCY || who == MGMT) : who == MGMT;
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        if (expect) m.paused = p;
        vm.prank(who);
        (bool ok,) = address(strategy).call(abi.encodeWithSignature("setPaused(bool)", p));
        _settle("setPaused", ok, expect, pre, m, true);
    }

    /// @dev Apagado (de una sola vía): raro, porque después no entra nadie más.
    function shutdown(uint256 seed) external {
        if (seed % 64 != 0) return;
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        m.shutdown = true;
        vm.prank(EMERGENCY);
        (bool ok,) = address(strategy).call(abi.encodeWithSignature("shutdownStrategy()"));
        _settle("shutdownStrategy", ok, true, pre, m, true);
    }

    /// @dev Retiro de emergencia de la fuente: solo con pausa o apagado; no devenga.
    function emergencyWithdraw(uint256 amount) external {
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool expect = pre.paused || pre.shutdown;
        uint256 x = _amt(amount);
        if (expect) {
            uint256 got = NexusTSMath.min(x, _liquid(m));
            m.idle += got;
            m.tok -= got;
        }
        source.resetSeen();
        vm.prank(EMERGENCY);
        (bool ok,) = address(strategy).call(abi.encodeWithSignature("emergencyWithdraw(uint256)", x));
        _settle("emergencyWithdraw", ok, expect, pre, m, true);
        if (ok) _lawProbe(true, pre.L, _eff(pre));
    }

    /// @dev Comisión del protocolo en la fábrica (no toca la estrategia ni el precio simulado).
    function setProtocolFee(uint256 v) external {
        Snap memory pre = _snap();
        factory.setFee(uint16(v % 4 == 0 ? 0 : v % (MAX_FEE + 1)));
        _env(pre, false, false);
    }

    /// @dev Vuelta a una configuración sana: sin pausa, perillas y liquidez por defecto.
    function restore() external {
        if (ts.isPaused()) this.setPaused(false, 1);
        this.setKnobs(0, 0, 0);
        this.setLiquidity(0);
    }

    /* TIEMPO */

    /// @dev Salto de reloj: justo en la fecha de desbloqueo o un segundo antes, hasta 20 días, o hasta un minuto.
    function warp(uint256 secs, uint256 mode) external {
        Snap memory pre = _snap();
        uint256 k = mode % 4;
        uint256 t = pre.ts + 1 + secs % 1 days;
        if (k == 0 && pre.D > pre.ts + 1) t = pre.D - (secs % 2);
        else if (k == 1) t = pre.ts + 1 + secs % 20 days;
        else if (k == 2) t = pre.ts + 1 + secs % 60;
        vm.warp(t);
        Snap memory post = _snap();
        _lawStill(pre, post);
        _lawViews(post, mode % 4);
        if (!_simMoves(post)) _lawPrice(pre, post);
    }

    /* SECUENCIAS */

    /// @dev Bloqueo y pérdida (en vivo): reporte con ganancia (queda bloqueada), un salto, una pérdida de una parte o
    /// de más que lo bloqueado, otro bloque y un depósito que devenga: la pérdida quema primero lo desbloqueado y
    /// después lo bloqueado, y el cronograma se rehace sobre lo que queda (_syncUnlockScheduleAfterLoss).
    function lockThenLose(uint256 reward, uint256 secs, uint256 loss, uint256 actorSeed) external {
        if (!LIVE) return;
        this.queueReward(reward);
        this.report();
        this.warp(secs, 1);
        this.liveLoss(loss);
        this.warp(0, 2);
        this.deposit(actorSeed, loss >> 3);
    }

    /// @dev Todos los actores canjean lo que pueden: el suministro queda en las acciones de comisión, las muertas y el
    /// buffer, y con eso se vuelve a recorrer el piso de 1e3 acciones.
    function drainAll(uint256 lossSeed) external {
        for (uint256 i; i < 4; ++i) {
            Snap memory pre = _snap();
            (uint256 sup, uint256 ta) = _sim(pre);
            uint256 mr = _maxR(pre, i, sup, ta);
            if (mr != 0) _exit(i, mr, true, lossSeed, pre);
        }
    }

    /* ATAQUES */

    /// @dev En un mismo bloque: depósito, reporte del keeper y canje de lo depositado. Con desbloqueo distinto de 0,
    /// la ganancia del reporte queda bloqueada: el que entra y sale cobra a lo sumo lo que valían sus acciones apenas
    /// entró, más el valor de una acción por redondeo (Y-INF-2). Se mide desde ahí y no desde lo depositado: con
    /// suministro 0 el depósito es 1:1 y se queda con lo que hubiera en la estrategia, y eso no es del reporte.
    function sandwichReport(uint256 actorSeed, uint256 amount) external {
        uint256 h = actorSeed % 4;
        Snap memory s0 = _snap();
        if (s0.paused || s0.shutdown || s0.T == 0) return;
        uint256 a = _amt(amount);
        deal(address(token), actors[h], s0.cash[h] + a);
        _enter(h, a, false);
        Snap memory sd = _snap();
        if (sd.bal[h] <= s0.bal[h]) return;
        uint256 sh = sd.bal[h] - s0.bal[h];
        (uint256 supD, uint256 taD) = _sim(sd);
        uint256 worth = _c2a(sh, supD, taD, false);
        this.report();
        Snap memory s1 = _snap();
        (uint256 sup, uint256 ta) = _sim(s1);
        uint256 oneShare = _c2a(1, sup, ta, true);
        _exit(h, sh, true, 0, s1);
        Snap memory s2 = _snap();
        if (s2.bal[h] != s0.bal[h]) return;
        uint256 paid = s2.cash[h] - sd.cash[h];
        _ok(paid <= worth + oneShare, L_INF2, "el sandwich del reporte en un bloque gano (valian al entrar, cobro)", worth, paid);
        ++hSandwich;
    }

    /* EL MODELO A PRUEBA DE DESBORDES: si una cuenta del modelo revierte, la misma de TokenizedStrategy también (ver
       simEnterExt) */

    function _modelEnter(Snap memory pre, uint256 h, uint256 amt, bool isMint) internal returns (Op memory, Snap memory) {
        try this.simEnterExt(pre, h, amt, isMint) returns (Op memory o, Snap memory m) {
            return (o, m);
        } catch {
            ++hOverflow;
            Op memory none;
            return (none, _copy(pre));
        }
    }

    function _modelExit(Snap memory pre, uint256 h, uint256 amt, bool isRedeem, uint256 maxLoss)
        internal
        returns (Op memory, Snap memory)
    {
        try this.simExitExt(pre, h, amt, isRedeem, maxLoss) returns (Op memory o, Snap memory m) {
            return (o, m);
        } catch {
            ++hOverflow;
            Op memory none;
            return (none, _copy(pre));
        }
    }

    function _modelReport(Snap memory pre) internal returns (Rep memory, Snap memory) {
        try this.simReportExt(pre) returns (Rep memory r, Snap memory m) {
            return (r, m);
        } catch {
            ++hOverflow;
            Rep memory none;
            return (none, _copy(pre));
        }
    }

    function _modelAccrue(Snap memory pre) internal returns (bool, Acc memory, Snap memory) {
        try this.accrueExt(pre) returns (Acc memory a, Snap memory m) {
            return (true, a, m);
        } catch {
            ++hOverflow;
            Acc memory none;
            return (false, none, _copy(pre));
        }
    }

    /* COMÚN */

    /// @dev Después de una operación: si el modelo acertó si pasaba (Y-LIVE), el estado crudo es el del modelo (o el
    /// de antes, si revirtió) y, con `strict`, el precio simulado no bajó.
    function _settle(string memory op, bool ok, bool expect, Snap memory pre, Snap memory m, bool strict) internal {
        Snap memory post = _snap();
        if (ok != expect) {
            _ok(
                false,
                L_LIVE,
                string(abi.encodePacked(op, ok ? ": paso y el modelo decia que revertia" : ": revirtio y el modelo decia que pasaba", " (marca de tiempo, 0)")),
                pre.ts,
                0
            );
            return;
        }
        if (!ok) {
            ++hRejected;
            _lawState(pre, post);
            return;
        }
        _lawState(m, post);
        if (strict) _lawPrice(pre, post);
    }

    /// @dev Una acción que no opera sobre TokenizedStrategy no cambia su almacenamiento.
    function _lawStill(Snap memory pre, Snap memory post) internal {
        _ok(post.L == pre.L && post.LA == pre.LA, L_TA, "una accion sin operacion cambio lastTotalAssets o lastAccrual (antes, despues)", pre.L, post.L);
        _ok(post.TS == pre.TS && post.B == pre.B, L_SUP, "una accion sin operacion cambio el suministro o el buffer (antes, despues)", pre.TS, post.TS);
        _ok(post.R == pre.R && post.D == pre.D && post.LR == pre.LR, L_LOCK, "una accion sin operacion cambio el cronograma (antes, despues)", pre.D, post.D);
        for (uint256 hh; hh < NH; ++hh) {
            _ok(post.bal[hh] == pre.bal[hh], L_LEDGER, "una accion sin operacion cambio un saldo (antes, despues)", pre.bal[hh], post.bal[hh]);
        }
        _lawLedger(post);
    }

    function _countOp(Snap memory pre, Op memory o) internal {
        _countAcc(o.acc);
        if (pre.ts == pre.LA && _live(pre) != pre.L) ++hLatched;
    }
}

contract NexusTokenizedStrategyInvariantTest is Test {
    NexusTokenizedStrategyHandler internal handler;

    function setUp() public virtual {
        handler = new NexusTokenizedStrategyHandler(_live(), _dec(), _perf(), _proto());
        targetContract(address(handler));
    }

    function _live() internal pure virtual returns (bool) {
        return true;
    }

    function _dec() internal pure virtual returns (uint8) {
        return 18;
    }

    function _perf() internal pure virtual returns (uint16) {
        return 1_000;
    }

    function _proto() internal pure virtual returns (uint16) {
        return 0;
    }

    /// @dev require y no assertEq: en forge-std 1.5.2 assertEq no lleva el mensaje al motivo de la falla, y el motivo
    /// ("... [leyes: ...]") es lo que lee tools/forge_v2 para atribuir cada mutación a sus leyes.
    function invariant_tokenizedStrategy() public view {
        string memory err = handler.check();
        require(bytes(err).length == 0, err);
    }

    function afterInvariant() public {
        (uint256 laws, uint256 liveProfit, uint256 dead, uint256 liveLoss, uint256 lockedBurn, uint256 feeShares) =
            handler.coverage();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cobertura: devengamientos en vivo con ganancia y comision", liveProfit);
        emit log_named_uint("cobertura: ganancias confiscadas al piso (acciones muertas)", dead);
        emit log_named_uint("cobertura: devengamientos en vivo con perdida", liveLoss);
        emit log_named_uint("cobertura: perdidas que quemaron acciones bloqueadas", lockedBurn);
        emit log_named_uint("cazador: acciones de comision en vivo", feeShares);
        (
            uint256 reportProfit,
            uint256 reportLoss,
            uint256 relock,
            uint256 withdrawLoss,
            uint256 latched,
            uint256 rejected,
            uint256 probes
        ) = handler.coverage2();
        emit log_named_uint("cobertura: reportes con ganancia", reportProfit);
        emit log_named_uint("cobertura: reportes con perdida", reportLoss);
        emit log_named_uint("cobertura: reportes con desbloqueo previo pendiente", relock);
        emit log_named_uint("cobertura: retiros con perdida para el usuario", withdrawLoss);
        emit log_named_uint("cobertura: operaciones en un bloque sincronizado con cambio pendiente", latched);
        emit log_named_uint("cobertura: operaciones rechazadas como predijo el modelo", rejected);
        emit log_named_uint("cobertura: callbacks con las vistas verificadas", probes);
        emit log_named_uint("cobertura: sandwiches del reporte en un bloque", handler.coverage3());
        emit log_named_uint("cobertura: entradas con suministro 0 y activos en la estrategia", handler.coverage4());
        (uint256 ovf, uint256 dom) = handler.coverage5();
        emit log_named_uint("cobertura: operaciones cuyo modelo desbordo, rechazadas como en TokenizedStrategy", ovf);
        emit log_named_uint("cobertura: operaciones salteadas por el dominio (totalSupply > 2^128)", dom);
    }
}

contract NexusTokenizedStrategyInvariantFeeTest is NexusTokenizedStrategyInvariantTest {
    function _perf() internal pure override returns (uint16) {
        return 2_000;
    }

    function _proto() internal pure override returns (uint16) {
        return 1_000;
    }
}

contract NexusTokenizedStrategyInvariantReportTest is NexusTokenizedStrategyInvariantTest {
    function _live() internal pure override returns (bool) {
        return false;
    }

    function _proto() internal pure override returns (uint16) {
        return 500;
    }
}

/// @dev 6 decimales y sin comisión de desempeño: sin acciones de comisión, vaciar la estrategia deja el suministro
/// debajo del piso y la ganancia siguiente se confisca a acciones muertas.
contract NexusTokenizedStrategyInvariantSixDecimalsTest is NexusTokenizedStrategyInvariantTest {
    function _dec() internal pure override returns (uint8) {
        return 6;
    }

    function _perf() internal pure override returns (uint16) {
        return 0;
    }
}

/// @notice Escenarios deterministas de la contabilidad nueva, cada paso contra el modelo.
contract NexusTokenizedStrategyEdgeTest is Test {
    /// @dev Semilla de `_amt` para polvo (1 a 1e4) y para montos grandes.
    function _dust(uint256 x) internal pure returns (uint256) {
        return (x - 1) << 2;
    }

    function _big(uint256 x) internal pure returns (uint256) {
        return ((x - 1) << 2) | 1;
    }

    /// @dev Con 999 acciones (debajo del piso de 1e3), una donación grande a la fuente se confisca a acciones muertas
    /// en el devengamiento siguiente: la víctima que deposita después no pierde nada.
    function test_piso_confisca_la_donacion_con_suministro_chico() public {
        NexusTokenizedStrategyHandler h = new NexusTokenizedStrategyHandler(true, 18, 1_000, 0);
        h.deposit(0, _dust(999));
        h.liveProfit(_big(1e24));
        h.warp(0, 2);
        h.deposit(1, _big(1e18));
        require(bytes(h.check()).length == 0, h.check());
        (,, uint256 dead,,,) = h.coverage();
        require(dead == 1, "nexus: la ganancia con suministro chico no fue a acciones muertas");
    }

    /// @dev Un reporte bloquea la ganancia; una pérdida en vivo menor que lo bloqueado quema acciones bloqueadas en el
    /// devengamiento siguiente y el cronograma se rehace sobre lo que queda.
    function test_perdida_en_vivo_cubierta_por_el_buffer() public {
        NexusTokenizedStrategyHandler h = new NexusTokenizedStrategyHandler(true, 18, 1_000, 0);
        h.deposit(0, _big(1e21));
        h.warp(0, 2);
        h.queueReward(_big(1e20));
        h.report();
        h.warp(3_600, 1);
        h.liveLoss(1e19);
        h.warp(0, 2);
        h.deposit(1, _big(1e18));
        require(bytes(h.check()).length == 0, h.check());
        (,,,, uint256 lockedBurn,) = h.coverage();
        require(lockedBurn == 1, "nexus: la perdida no quemo acciones bloqueadas");
    }

    /// @dev Pérdida total con suministro chico (500 acciones) y después una donación: con lastTotalAssets en 0 la
    /// simulación toma el camino del piso sin baseline (suministro + activos) y el devengamiento siguiente acuña los
    /// activos a acciones muertas 1:1. Las vistas del bloque nuevo tienen que coincidir con el modelo.
    function test_recuperacion_tras_perdida_total_con_suministro_chico() public {
        NexusTokenizedStrategyHandler h = new NexusTokenizedStrategyHandler(true, 18, 1_000, 0);
        h.deposit(0, _dust(500));
        h.warp(0, 2);
        h.liveLoss(500);
        h.warp(0, 2);
        h.setPerformanceFee(8); // devenga: la pérdida total deja lastTotalAssets en 0
        h.donateIdle(_big(1e18));
        h.warp(0, 2);
        h.deposit(1, _big(1e18));
        require(bytes(h.check()).length == 0, h.check());
        (,, uint256 dead,,,) = h.coverage();
        require(dead == 1, "nexus: la recuperacion no fue a acciones muertas");
    }

    /// @dev Depósito, reporte con ganancia y canje en un mismo bloque: la ganancia queda bloqueada.
    function test_sandwich_del_reporte_en_un_bloque() public {
        NexusTokenizedStrategyHandler h = new NexusTokenizedStrategyHandler(true, 18, 1_000, 0);
        h.deposit(0, _big(1e21));
        h.warp(0, 2);
        h.queueReward(_big(1e20));
        h.sandwichReport(1, _big(1e21));
        require(bytes(h.check()).length == 0, h.check());
        require(h.coverage3() == 1, "nexus: el sandwich no corrio");
    }

    /// @dev Regresión de la campaña del 28-oct (512×1500: 11 reversiones del handler en la variante con protocolo).
    /// Pérdidas casi totales seguidas de depósitos inflaban las acciones (1e24, 1e48, 1e72) hasta que una vista o el
    /// reporte desbordaba, en el modelo y en TokenizedStrategy, y el handler revertía. Ahora el cazador no deja pasar
    /// totalSupply de 2^128: los depósitos y el reporte que lo pasarían se saltean, y las leyes siguen valiendo.
    function test_inflacion_de_acciones_no_tumba_al_cazador() public {
        NexusTokenizedStrategyHandler h = new NexusTokenizedStrategyHandler(true, 18, 2_000, 1_000);
        for (uint256 k; k < 6; ++k) {
            h.deposit(k % 4, _big(1e24));
            h.warp(0, 2);
            h.liveLoss(k == 0 ? 1e24 - 1 : 1e24); // deja 1 de activo en la fuente
            h.warp(0, 2);
        }
        h.queueReward(_big(1e24));
        h.report();
        require(bytes(h.check()).length == 0, h.check());
        (, uint256 dom) = h.coverage5();
        require(dom > 0, "nexus: ninguna operacion salteada por el dominio");
    }
}
