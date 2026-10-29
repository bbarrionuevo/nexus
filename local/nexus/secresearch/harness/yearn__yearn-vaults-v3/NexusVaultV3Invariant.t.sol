// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

// Handler e invariantes del cazador del Vault V3 (variante A), en cuatro variantes: comisión del accountant, con
// reembolsos y comisión del protocolo, activo de 6 decimales sin comisión y sin bloqueo de ganancias. Cada acción pasa
// por las leyes YV-... de NexusVaultV3Hunter.sol: el modelo predice si pasa (YV-LIVE) y el estado crudo exacto.

import {Test} from "forge-std/Test.sol";
import {NexusV3Hunter, NexusV3Base} from "./NexusVaultV3Hunter.sol";

contract NexusVaultV3Handler is NexusV3Hunter {
    constructor(uint8 dec, uint256 feeBps, uint256 refundBps, uint16 protoBps, uint256 unlockTime)
        NexusV3Base(dec, feeBps, refundBps, protoBps, unlockTime)
    {}

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

    function mint(uint256 actorSeed, uint256 shares) external {
        uint256 h = actorSeed % 4;
        uint256 s = _amt(shares);
        deal(address(token), actors[h], token.balanceOf(actors[h]) + _c2a(_snap(), s, true));
        _enter(h, s, true);
    }

    function _enter(uint256 h, uint256 x, bool isMint) internal {
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        uint256 a = isMint ? _c2a(pre, x, true) : x;
        uint256 sh = isMint ? x : _c2s(pre, x, false);
        bool expect = a <= _maxDep(pre) && a > 0 && sh > 0 && a <= pre.cash[h];
        if (expect) {
            m.cash[h] -= a;
            m.vaultCash += a;
            m.idle += a;
            _issue(m, h, sh);
        }
        vm.prank(actors[h]);
        (bool ok,) = address(vault).call(
            isMint
                ? abi.encodeWithSignature("mint(uint256,address)", x, actors[h])
                : abi.encodeWithSignature("deposit(uint256,address)", x, actors[h])
        );
        _settle(isMint ? "mint" : "deposit", ok, expect, pre, m, true);
    }

    /// @dev Retiro de hasta lo que valen las acciones del actor (un octavo de las veces, uno de más).
    function withdraw(uint256 actorSeed, uint256 amount, uint256 lossSeed) external {
        uint256 h = actorSeed % 4;
        Snap memory pre = _snap();
        uint256 own = _c2a(pre, pre.bal[h], false);
        uint256 a = amount % 8 == 0 ? own + 1 : _clamp(amount >> 3, 1, own);
        _exit(h, a, _c2s(pre, a, true), _ml(lossSeed, false), false, pre);
    }

    function redeem(uint256 actorSeed, uint256 shares, uint256 lossSeed) external {
        uint256 h = actorSeed % 4;
        Snap memory pre = _snap();
        uint256 s = shares % 8 == 0 ? pre.bal[h] + 1 : _clamp(shares >> 3, 1, pre.bal[h]);
        _exit(h, _c2a(pre, s, false), s, _ml(lossSeed, true), true, pre);
    }

    /// @dev max_loss: el de la firma estándar (withdraw 0, redeem 100 %) o 1, 100 o 10.000 bps.
    function _ml(uint256 seed, bool isRedeem) internal pure returns (uint256) {
        uint256 k = seed % 4;
        if (k == 0) return isRedeem ? MAX_BPS : 0;
        return k == 1 ? 1 : (k == 2 ? 100 : MAX_BPS);
    }

    function _exit(uint256 h, uint256 a, uint256 sh, uint256 ml, bool isRedeem, Snap memory pre) internal {
        Snap memory m = _copy(pre);
        (bool expect, W memory w) = _simRedeem(m, h, a, sh, ml);
        address who = actors[h];
        vm.prank(who);
        (bool ok,) = address(vault).call(
            isRedeem
                ? abi.encodeWithSignature("redeem(uint256,address,address,uint256)", sh, who, who, ml)
                : abi.encodeWithSignature("withdraw(uint256,address,address,uint256)", a, who, who, ml)
        );
        _settle(isRedeem ? "redeem" : "withdraw", ok, expect, pre, m, true);
        if (ok && expect) {
            if (w.unrealised) ++hUnrealised;
            if (w.realised) ++hWithdrawLoss;
            if (w.fromStrat) ++hFromStrat;
            if (w.excess) ++hExcess;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 shares) external {
        uint256 f = fromSeed % 4;
        uint256 t = toSeed % 4;
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        uint256 s = _clamp(shares, 0, pre.bal[f]);
        m.bal[f] -= s;
        m.bal[t] += s;
        vm.prank(actors[f]);
        (bool ok,) = address(vault).call(abi.encodeWithSignature("transfer(address,uint256)", actors[t], s));
        _settle("transfer", ok, true, pre, m, true);
    }

    /* DEUDA Y REPORTES (roles del gobierno) */

    function updateDebt(uint256 which, uint256 targetSeed, uint256 lossSeed) external {
        uint256 i = which % NS;
        uint256 k = targetSeed % 5;
        (,, uint256 cd,) = vault.strategies(address(strat[i]));
        uint256 target = k == 0 ? 0 : (k == 1 ? type(uint256).max : _clamp(targetSeed >> 3, 0, cd + vault.totalIdle()));
        _updateDebt(i, target, lossSeed % 3 == 0 ? MAX_BPS : (lossSeed % 3 == 1 ? 0 : 100));
    }

    function _updateDebt(uint256 i, uint256 target, uint256 ml) internal {
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        (bool expect, bool lossy) = _simUpdateDebt(m, i, target, ml);
        vm.prank(GOV);
        (bool ok,) = address(vault).call(
            abi.encodeWithSignature("update_debt(address,uint256,uint256)", address(strat[i]), target, ml)
        );
        _settle("update_debt", ok, expect, pre, m, !lossy);
        if (ok && expect) {
            if (m.cur[i] > pre.cur[i]) {
                ++hDebtUp;
            } else if (m.cur[i] < pre.cur[i]) {
                ++hDebtDown;
                // el mínimo ocioso hizo retirar más de lo pedido
                if (!pre.shutdown && target < pre.cur[i] && pre.idle + (pre.cur[i] - target) < pre.minIdle
                        && pre.cur[i] - m.cur[i] > pre.cur[i] - target) ++hIdleFloor;
            }
        }
    }

    function report(uint256 which) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        (bool expect, Rep memory r) = _simReport(m, i);
        vm.prank(GOV);
        (bool ok, bytes memory ret) = address(vault).call(abi.encodeWithSignature("process_report(address)", address(strat[i])));
        _settle("process_report", ok, expect, pre, m, !r.capped);
        if (ok && expect) {
            (uint256 g, uint256 l) = abi.decode(ret, (uint256, uint256));
            _ok(g == r.gain && l == r.loss, L_TA, "process_report devolvio otra ganancia o perdida (modelo, real)", r.gain + r.loss, g + l);
            if (r.gain > 0) ++hGain;
            if (r.loss > 0) ++hLoss;
            if (r.tfs > 0) ++hFees;
            if (r.refunds > 0) ++hRefunds;
        }
    }

    /* ESTRATEGIAS, ACCOUNTANT Y PROTOCOLO (fuera del vault) */

    function gain(uint256 which, uint256 x) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        deal(address(token), address(strat[i]), pre.tA[i] + _amt(x));
        _still(pre);
    }

    function loss(uint256 which, uint256 x) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        deal(address(token), address(strat[i]), pre.tA[i] - _clamp(x, 0, pre.tA[i]));
        _still(pre);
    }

    /// @dev Liquidez (un tercio de las veces acotada), recorte por retiro (un tercio) y pausa de depósitos (rara).
    function knobs(uint256 which, uint256 l, uint256 c, uint256 p) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        strat[i].setKnobs(l % 3 != 1 ? type(uint256).max : _amt(l >> 2), c % 3 != 1 ? 0 : 1 + (c >> 2) % 1e4, p % 8 == 0);
        _still(pre);
    }

    function fundAccountant(uint256 x) external {
        Snap memory pre = _snap();
        deal(address(token), address(acct), pre.acctCash + _amt(x));
        _still(pre);
    }

    function setAccountant(uint256 f, uint256 r) external {
        Snap memory pre = _snap();
        acct.set(f % 5_001, r % 10_001);
        _still(pre);
    }

    function setProtocolFee(uint256 v) external {
        Snap memory pre = _snap();
        vm.prank(GOV);
        factory.set_protocol_fee_bps(uint16(v % 4 == 0 ? 0 : v % 5_001));
        _still(pre);
    }

    /* CONFIGURACIÓN DEL VAULT */

    /// @dev Tope de deuda de una estrategia: un tercio de las veces sin tope, si no un monto.
    function setMaxDebt(uint256 which, uint256 v) external {
        uint256 i = which % NS;
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        m.maxd[i] = v % 3 == 0 ? type(uint256).max : _amt(v >> 2);
        vm.prank(GOV);
        (bool ok,) = address(vault).call(
            abi.encodeWithSignature("update_max_debt_for_strategy(address,uint256)", address(strat[i]), m.maxd[i])
        );
        _settle("update_max_debt_for_strategy", ok, true, pre, m, true);
    }

    /// @dev 0 (desbloquea todo de golpe), más de un año (revierte) o hasta 30 días.
    function setUnlockTime(uint256 v) external {
        uint256 t = v % 8 == 0 ? 0 : (v % 8 == 1 ? 31_556_953 : 1 + (v >> 3) % 30 days);
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool expect = t <= 31_556_952;
        if (expect && t == 0) {
            m.S -= m.B;
            m.B = 0;
            m.R = 0;
            m.D = 0;
        }
        vm.prank(GOV);
        (bool ok,) = address(vault).call(abi.encodeWithSignature("setProfitMaxUnlockTime(uint256)", t));
        _settle("setProfitMaxUnlockTime", ok, expect, pre, m, true);
        if (ok) _ok(vault.profitMaxUnlockTime() == t, L_LIVE, "profit_max_unlock_time no quedo como se pidio (pedido, real)", t, vault.profitMaxUnlockTime());
    }

    /// @dev Mínimo ocioso: casi siempre 0 (con uno alto no entra deuda), a veces polvo o un monto.
    function setMinIdle(uint256 v) external {
        _setMinIdle(v % 4 != 1 ? 0 : _amt(v >> 2));
    }

    function _setMinIdle(uint256 v) internal {
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        m.minIdle = v;
        vm.prank(GOV);
        (bool ok,) = address(vault).call(abi.encodeWithSignature("set_minimum_total_idle(uint256)", m.minIdle));
        _settle("set_minimum_total_idle", ok, true, pre, m, true);
    }

    /// @dev Pausa rara (un sexto de los pedidos pausa; el resto despausa).
    function setPaused(uint256 seed) external {
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        m.paused = seed % 6 == 0;
        vm.prank(GOV);
        (bool ok,) = address(vault).call(abi.encodeWithSignature("setPaused(bool)", m.paused));
        _settle("setPaused", ok, true, pre, m, true);
    }

    function shutdown(uint256 seed) external {
        if (seed % 64 != 0) return;
        Snap memory pre = _snap();
        Snap memory m = _copy(pre);
        bool expect = !pre.shutdown;
        if (expect) {
            m.shutdown = true;
            m.depLimit = 0;
        }
        vm.prank(GOV);
        (bool ok,) = address(vault).call(abi.encodeWithSignature("shutdown_vault()"));
        _settle("shutdown_vault", ok, expect, pre, m, true);
    }

    /* SECUENCIAS */

    /// @dev Ciclo completo sobre la estrategia i: depósito, deuda al máximo, ganancia o pérdida de la estrategia,
    /// reporte y un salto de reloj (el desbloqueo). Sin esto, ganar y reportar en la misma estrategia casi no coincide.
    function cycle(uint256 actorSeed, uint256 which, uint256 amount, uint256 delta) external {
        this.deposit(actorSeed, amount);
        this.updateDebt(which, 1, 0);
        if (delta % 3 == 0) this.loss(which, delta >> 2);
        else this.gain(which, delta >> 2);
        this.report(which);
        this.warp(delta, 2);
    }

    /// @dev Salida con la estrategia en problemas: depósito, toda la deuda en la estrategia i, y después una pérdida
    /// sin reportar (el retiro carga su parte de la pérdida no realizada) o un recorte en los retiros de la estrategia
    /// (pérdida realizada al retirar), y un canje grande con max_loss 100 %.
    function stressExit(uint256 actorSeed, uint256 which, uint256 amount, uint256 delta) external {
        uint256 h = actorSeed % 4;
        uint256 i = which % NS;
        this.deposit(h, amount);
        this.updateDebt(i, 1, 0);
        if (delta % 2 == 0) this.loss(i, delta >> 2);
        else this.knobs(i, 0, (((delta >> 2) % 3) * 3) + 1, 1);
        Snap memory pre = _snap();
        uint256 s = pre.bal[h] - pre.bal[h] / (1 + delta % 4);
        if (s == 0) return;
        _exit(h, _c2a(pre, s, false), s, MAX_BPS, true, pre);
    }

    /// @dev Baja de deuda con el mínimo ocioso por encima de lo ocioso: depósito, toda la deuda en la estrategia i, un
    /// mínimo ocioso mayor que lo ocioso más la baja pedida y una baja parcial; el vault retira de más para llegar al
    /// mínimo, acotado a la deuda y a lo retirable. Sin esto, el caso casi no aparece (la mitad de las veces el mínimo
    /// vuelve a 0 al final).
    function idleFloor(uint256 actorSeed, uint256 which, uint256 amount, uint256 seed) external {
        uint256 i = which % NS;
        this.deposit(actorSeed, amount);
        _updateDebt(i, type(uint256).max, MAX_BPS);
        Snap memory pre = _snap();
        uint256 cd = pre.cur[i];
        if (cd < 2) return;
        uint256 cut = 1 + seed % (cd - 1);
        _setMinIdle(pre.idle + cut + 1 + (seed >> 128) % cd);
        _updateDebt(i, cd - cut, (seed >> 64) % 3 == 0 ? MAX_BPS : 0);
        if ((seed >> 192) % 2 == 0) _setMinIdle(0);
    }

    /// @dev Vuelta a una configuración sana: sin pausa, sin mínimo ocioso, estrategias líquidas y sin recorte.
    function restore() external {
        if (vault.isPaused()) this.setPaused(1);
        if (vault.minimum_total_idle() != 0) this.setMinIdle(0);
        for (uint256 i; i < NS; ++i) {
            this.knobs(i, 0, 0, 1);
            this.setMaxDebt(i, 0);
        }
    }

    function warp(uint256 secs, uint256 mode) external {
        Snap memory pre = _snap();
        uint256 t = pre.ts + 1 + secs % 1 days;
        if (mode % 4 == 0 && pre.D > pre.ts + 1) t = pre.D - (secs % 2);
        else if (mode % 4 == 1) t = pre.ts + 1 + secs % 20 days;
        vm.warp(t);
        _still(pre);
    }

    /* COMÚN */

    function _settle(string memory op, bool ok, bool expect, Snap memory pre, Snap memory m, bool strict) internal {
        Snap memory post = _snap();
        if (ok != expect) {
            _ok(false, L_LIVE, string(abi.encodePacked(op, ok ? ": paso y el modelo decia que revertia" : ": revirtio y el modelo decia que pasaba", " (marca de tiempo, 0)")), pre.ts, 0);
            return;
        }
        if (!ok) {
            ++hRejected;
            _lawState(pre, post);
            return;
        }
        _lawState(m, post);
        bool cfg = post.minIdle == m.minIdle && post.depLimit == m.depLimit && post.paused == m.paused
            && post.shutdown == m.shutdown;
        for (uint256 i; i < NS; ++i) {
            cfg = cfg && post.maxd[i] == m.maxd[i];
        }
        _ok(cfg, L_LIVE, "configuracion del vault distinta del modelo (0, 0)", 0, 0);
        _lawViews(post);
        if (strict) _lawPrice(pre, post);
    }

    /// @dev Una acción fuera del vault no cambia su estado; el precio contable no se mueve.
    function _still(Snap memory pre) internal {
        Snap memory post = _snap();
        bool same = post.idle == pre.idle && post.debt == pre.debt && post.S == pre.S && post.B == pre.B
            && post.R == pre.R && post.D == pre.D && post.LPU == pre.LPU;
        _ok(same, L_TA, "una accion fuera del vault cambio su estado (idle antes, despues)", pre.idle, post.idle);
        for (uint256 i; i < NS; ++i) {
            _ok(post.cur[i] == pre.cur[i], L_TA, "una accion fuera del vault cambio una deuda (antes, despues)", pre.cur[i], post.cur[i]);
        }
        _lawLedger(post);
        _lawViews(post);
        _lawPrice(pre, post);
    }
}

contract NexusVaultV3InvariantTest is Test {
    NexusVaultV3Handler internal handler;

    function setUp() public virtual {
        handler = new NexusVaultV3Handler(_dec(), _fee(), _refund(), _proto(), _unlock());
        targetContract(address(handler));
    }

    function _dec() internal pure virtual returns (uint8) {
        return 18;
    }

    function _fee() internal pure virtual returns (uint256) {
        return 1_000;
    }

    function _refund() internal pure virtual returns (uint256) {
        return 0;
    }

    function _proto() internal pure virtual returns (uint16) {
        return 0;
    }

    function _unlock() internal pure virtual returns (uint256) {
        return 10 days;
    }

    /// @dev require y no assertEq: en forge-std 1.5.2 assertEq no lleva el mensaje al motivo de la falla.
    function invariant_vaultV3() public view {
        string memory err = handler.check();
        require(bytes(err).length == 0, err);
    }

    function afterInvariant() public {
        (uint256 laws, uint256 g, uint256 l, uint256 fees, uint256 refunds, uint256 unrealised) = handler.coverage();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cobertura: reportes con ganancia", g);
        emit log_named_uint("cobertura: reportes con perdida", l);
        emit log_named_uint("cobertura: reportes con comision del accountant", fees);
        emit log_named_uint("cobertura: reportes con reembolso", refunds);
        emit log_named_uint("cobertura: retiros que cargaron perdida no realizada", unrealised);
        (uint256 wl, uint256 fs, uint256 up, uint256 down, uint256 rej, uint256 ex) = handler.coverage2();
        emit log_named_uint("cobertura: retiros con perdida realizada en la estrategia", wl);
        emit log_named_uint("cobertura: retiros que sacaron de alguna estrategia", fs);
        emit log_named_uint("cobertura: subas de deuda", up);
        emit log_named_uint("cobertura: bajas de deuda", down);
        emit log_named_uint("cobertura: operaciones rechazadas como predijo el modelo", rej);
        emit log_named_uint("cobertura: retiros con exceso sobre la deuda", ex);
        emit log_named_uint("cobertura: bajas de deuda que retiraron de mas por el minimo ocioso", handler.coverage3());
    }
}

contract NexusVaultV3InvariantFeeTest is NexusVaultV3InvariantTest {
    function _fee() internal pure override returns (uint256) {
        return 2_000;
    }

    function _refund() internal pure override returns (uint256) {
        return 5_000;
    }

    function _proto() internal pure override returns (uint16) {
        return 1_000;
    }
}

contract NexusVaultV3InvariantSixDecimalsTest is NexusVaultV3InvariantTest {
    function _dec() internal pure override returns (uint8) {
        return 6;
    }

    function _fee() internal pure override returns (uint256) {
        return 0;
    }
}

contract NexusVaultV3InvariantNoLockTest is NexusVaultV3InvariantTest {
    function _unlock() internal pure override returns (uint256) {
        return 0;
    }
}
