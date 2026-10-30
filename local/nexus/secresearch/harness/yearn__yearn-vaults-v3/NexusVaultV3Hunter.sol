// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

// Cazador de vulnerabilidades del Vault V3 de Yearn (yearn/yearn-vaults-v3 @ v3.1.0: el VaultV3.vy verificado del
// original 0xdD3F…7824, en alcance en Immunefi, es el del tag). Variante A: tres estrategias ERC-4626 de OpenZeppelin
// con liquidez, recorte por retiro y pausa, así el fantasma conoce cada estrategia de forma exacta, y un accountant
// de prueba con comisión y reembolsos. El modelo porta _redeem, _update_debt y _process_report de Vyper con su misma
// aritmética (chequeada) y compara contra el almacenamiento crudo del vault. Leyes YV-... (docs/CAZADOR_VAULT_V3.md).
//
// Sin FFI: el vault se compila con el vyper del venv (forge nativo); la fábrica clona el original (proxy mínimo) y
// lo inicializa, como en producción. Compila sin via_ir (como el repo).

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IVaultV3 {
    function deposit(uint256, address) external returns (uint256);
    function process_report(address) external returns (uint256, uint256);
    function update_debt(address, uint256, uint256) external returns (uint256);
    function add_strategy(address, bool) external;
    function update_max_debt_for_strategy(address, uint256) external;
    function set_role(address, uint256) external;
    function set_deposit_limit(uint256, bool) external;
    function set_minimum_total_idle(uint256) external;
    function setProfitMaxUnlockTime(uint256) external;
    function set_accountant(address) external;
    function setPaused(bool) external;
    function shutdown_vault() external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function totalIdle() external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function unlockedShares() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function profitUnlockingRate() external view returns (uint256);
    function fullProfitUnlockDate() external view returns (uint256);
    function lastProfitUpdate() external view returns (uint256);
    function profitMaxUnlockTime() external view returns (uint256);
    function strategies(address) external view returns (uint256, uint256, uint256, uint256);
    function minimum_total_idle() external view returns (uint256);
    function deposit_limit() external view returns (uint256);
    function isShutdown() external view returns (bool);
    function isPaused() external view returns (bool);
    function convertToShares(uint256) external view returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
    function previewDeposit(uint256) external view returns (uint256);
    function previewMint(uint256) external view returns (uint256);
    function previewWithdraw(uint256) external view returns (uint256);
    function previewRedeem(uint256) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
}

interface IVaultFactory {
    function deploy_new_vault(address, string memory, string memory, address, uint256) external returns (address);
    function set_protocol_fee_bps(uint16) external;
    function set_protocol_fee_recipient(address) external;
    function protocol_fee_config(address) external view returns (uint16, address);
}

/// @notice Reloj del harness.
contract NexusV3Clock {
    function time() external view returns (uint256) {
        return block.timestamp;
    }
}

contract NexusV3Token is ERC20 {
    uint8 internal immutable dec;

    constructor(uint8 d) ERC20("nexus asset", "NXA") {
        dec = d;
    }

    function decimals() public view override returns (uint8) {
        return dec;
    }
}

/// @notice Estrategia ERC-4626 de prueba (OpenZeppelin 4.9.5, sin offset): `liquidity` acota lo canjeable,
/// `haircut` es lo que se pierde en cada retiro (va a SINK) y `paused` cierra los depósitos.
contract NexusV3Strategy is ERC4626 {
    using SafeERC20 for IERC20;

    uint256 public liquidity = type(uint256).max;
    uint256 public haircut;
    bool public paused;
    address public constant SINK = address(uint160(uint256(keccak256("nexus.v3.sink"))));

    constructor(IERC20 a) ERC4626(a) ERC20("nexus v3 strategy", "NV3S") {}

    function setKnobs(uint256 l, uint256 h, bool p) external {
        liquidity = l;
        haircut = h;
        paused = p;
    }

    function maxDeposit(address) public view override returns (uint256) {
        return paused ? 0 : type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        return paused ? 0 : type(uint256).max;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 b = balanceOf(owner);
        if (liquidity == type(uint256).max) return b;
        uint256 l = _convertToShares(liquidity, Math.Rounding.Down);
        return b < l ? b : l;
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (caller != owner) _spendAllowance(owner, caller, shares);
        _burn(owner, shares);
        uint256 c = assets < haircut ? assets : haircut;
        IERC20(asset()).safeTransfer(receiver, assets - c);
        if (c > 0) IERC20(asset()).safeTransfer(SINK, c);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}

/// @notice Accountant de prueba: comisión sobre la ganancia y reembolso sobre la pérdida, en bps.
contract NexusV3Accountant {
    uint256 public feeBps;
    uint256 public refundBps;

    function set(uint256 f, uint256 r) external {
        feeBps = f;
        refundBps = r;
    }

    function approveVault(IERC20 a, address v) external {
        a.approve(v, type(uint256).max);
    }

    function report(address, uint256 gain, uint256 loss) external view returns (uint256 fees, uint256 refunds) {
        fees = gain * feeBps / 10_000;
        refunds = loss * refundBps / 10_000;
    }
}

/// @notice Base: token, fábrica con el blueprint, el vault, tres estrategias en la cola, accountant, roles y actores.
abstract contract NexusV3Base is Test {
    uint256 internal constant MAX_BPS = 10_000;
    uint256 internal constant EXT = 1_000_000_000_000;
    uint256 internal constant NS = 3;
    uint256 internal constant ALL_ROLES = 16383;
    address internal constant GOV = address(uint160(uint256(keccak256("nexus.v3.gov"))));
    address internal constant PROTO = address(uint160(uint256(keccak256("nexus.v3.protocol"))));

    NexusV3Token internal token;
    IVaultFactory internal factory;
    IVaultV3 internal vault;
    NexusV3Strategy[3] internal strat;
    NexusV3Accountant internal acct;
    NexusV3Clock internal hClock;
    uint256 internal immutable MAX_ASSETS;
    address[] internal actors;

    uint256 internal violations;
    uint256 internal lawMask;
    string internal firstViolation;

    constructor(uint8 dec, uint256 feeBps, uint256 refundBps, uint16 protoBps, uint256 unlockTime) {
        MAX_ASSETS = 10 ** (uint256(dec) + 6);
        hClock = new NexusV3Clock();
        token = new NexusV3Token(dec);
        // la fábrica clona el original con create_minimal_proxy_to y lo inicializa
        address original = deployCode("VaultV3.vy");
        factory = IVaultFactory(deployCode("VaultFactory.vy", abi.encode("nexus factory", original, GOV)));
        vault = IVaultV3(factory.deploy_new_vault(address(token), "nexus vault", "nxV", GOV, unlockTime));
        vm.startPrank(GOV);
        vault.set_role(GOV, ALL_ROLES);
        vault.set_deposit_limit(type(uint256).max, false);
        factory.set_protocol_fee_recipient(PROTO);
        if (protoBps > 0) factory.set_protocol_fee_bps(protoBps);
        vm.stopPrank();
        acct = new NexusV3Accountant();
        acct.set(feeBps, refundBps);
        acct.approveVault(IERC20(address(token)), address(vault));
        vm.prank(GOV);
        vault.set_accountant(address(acct));
        for (uint256 i; i < NS; ++i) {
            strat[i] = new NexusV3Strategy(IERC20(address(token)));
            vm.startPrank(GOV);
            vault.add_strategy(address(strat[i]), true);
            vault.update_max_debt_for_strategy(address(strat[i]), type(uint256).max);
            vm.stopPrank();
        }
        for (uint256 i; i < 4; ++i) {
            actors.push(address(uint160(uint256(keccak256(abi.encode("nexus.v3.actor", i))))));
            vm.prank(actors[i]);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function _clamp(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + x % (hi - lo + 1);
    }
}

/// @notice Fantasma, modelo y leyes del Vault V3.
abstract contract NexusV3Hunter is NexusV3Base {
    uint8 internal constant L_TA = 0; // YV-TA: total_idle, total_debt y la deuda de cada estrategia exactos
    uint8 internal constant L_SUP = 1; // YV-SUP: total_supply crudo y saldos exactos
    uint8 internal constant L_LOCK = 2; // YV-LOCK: buffer, tasa, fecha y last_profit_update exactos
    uint8 internal constant L_FEE = 3; // YV-FEE: acciones del accountant y del protocolo exactas
    uint8 internal constant L_WD = 4; // YV-WD: lo que cobra y paga cada usuario, con las pérdidas, exacto
    uint8 internal constant L_INF2 = 5; // YV-INF-2: el precio no baja sin pérdida ni comisión
    uint8 internal constant L_VIEW = 6; // YV-VIEW: vistas y previews exactas
    uint8 internal constant L_FUNDS = 7; // YV-FUNDS: el activo en el vault, las estrategias y el accountant
    uint8 internal constant L_LIVE = 8; // YV-LIVE: pasa si y solo si el modelo dice que pasa
    uint8 internal constant L_LEDGER = 9; // YV-LEDGER: Σ saldos crudos = total_supply
    uint8 internal constant N_LAWS = 10;

    uint256 internal constant NH = 6; // actores 0..3, accountant, protocolo
    uint256 internal constant H_ACCT = 4;
    uint256 internal constant H_PROTO = 5;
    /// @dev Dominio: total_supply crudo hasta 2^128. Pérdidas casi totales seguidas de depósitos o ganancias inflan las
    /// acciones (con 18 decimales, 1e24, 1e48, 1e72...) hasta que el vault y el modelo desbordan en la misma cuenta, un
    /// régimen sin sentido económico. Con este tope ninguna vista ni ley del cazador desborda; la operación que lo
    /// pasaría se saltea (hDomain).
    uint256 internal constant S_CAP = 2 ** 128;

    struct Snap {
        uint256 ts;
        uint256 idle;
        uint256 debt;
        uint256 S; // total_supply crudo
        uint256 B; // balance_of[vault] crudo: el buffer bloqueado
        uint256 R;
        uint256 D;
        uint256 LPU;
        uint256 T;
        uint256 minIdle;
        uint256 depLimit;
        bool paused;
        bool shutdown;
        uint256 vaultCash;
        uint256 acctCash;
        uint256 feeBps;
        uint256 refundBps;
        uint256 pbps;
        uint256 sink;
        uint256[3] cur;
        uint256[3] maxd;
        uint256[3] tA;
        uint256[3] tS;
        uint256[3] vsh;
        uint256[3] liq;
        uint256[3] cut;
        bool[3] sp;
        uint256[6] bal;
        uint256[4] cash;
    }

    // métricas
    uint256 internal hLaws;
    uint256 internal hGain;
    uint256 internal hLoss;
    uint256 internal hFees;
    uint256 internal hRefunds;
    uint256 internal hUnrealised; // retiros que cargaron pérdida no realizada
    uint256 internal hWithdrawLoss; // retiros con pérdida realizada en la estrategia
    uint256 internal hFromStrat; // retiros que sacaron de alguna estrategia
    uint256 internal hDebtUp;
    uint256 internal hDebtDown;
    uint256 internal hRejected;
    uint256 internal hExcess; // retiros con exceso por encima de la deuda (queda fuera de total_idle)
    uint256 internal hIdleFloor; // bajas de deuda en las que el mínimo ocioso hizo retirar más de lo pedido
    uint256 internal hOverflow; // operaciones cuyo modelo desbordó: se esperan rechazadas, como en el vault
    uint256 internal hDomain; // operaciones salteadas porque dejaban total_supply por encima de S_CAP

    function _holder(uint256 h) internal view returns (address) {
        if (h < 4) return actors[h];
        return h == H_ACCT ? address(acct) : PROTO;
    }

    function _slot(uint256 s) internal view returns (uint256) {
        return uint256(vm.load(address(vault), bytes32(s)));
    }

    /// @dev balance_of[a] de Vyper: HashMap en el slot 18, clave keccak256(slot ++ clave).
    function _vbal(address a) internal view returns (uint256) {
        return uint256(vm.load(address(vault), keccak256(abi.encode(uint256(18), a))));
    }

    function _snap() internal view returns (Snap memory s) {
        s.ts = hClock.time();
        s.S = _slot(20);
        s.debt = _slot(21);
        s.idle = _slot(22);
        s.B = _vbal(address(vault));
        s.R = vault.profitUnlockingRate();
        s.D = vault.fullProfitUnlockDate();
        s.LPU = vault.lastProfitUpdate();
        s.T = vault.profitMaxUnlockTime();
        s.minIdle = vault.minimum_total_idle();
        s.depLimit = vault.deposit_limit();
        s.paused = vault.isPaused();
        s.shutdown = vault.isShutdown();
        s.vaultCash = token.balanceOf(address(vault));
        s.acctCash = token.balanceOf(address(acct));
        s.feeBps = acct.feeBps();
        s.refundBps = acct.refundBps();
        (uint16 pb,) = factory.protocol_fee_config(address(vault));
        s.pbps = pb;
        s.sink = token.balanceOf(strat[0].SINK());
        for (uint256 i; i < NS; ++i) {
            (,, s.cur[i], s.maxd[i]) = vault.strategies(address(strat[i]));
            s.tA[i] = token.balanceOf(address(strat[i]));
            s.tS[i] = strat[i].totalSupply();
            s.vsh[i] = strat[i].balanceOf(address(vault));
            s.liq[i] = strat[i].liquidity();
            s.cut[i] = strat[i].haircut();
            s.sp[i] = strat[i].paused();
        }
        for (uint256 h; h < NH; ++h) {
            s.bal[h] = _vbal(_holder(h));
        }
        for (uint256 i; i < 4; ++i) {
            s.cash[i] = token.balanceOf(actors[i]);
        }
    }

    function _copy(Snap memory s) internal pure returns (Snap memory) {
        return abi.decode(abi.encode(s), (Snap));
    }

    /* MODELO DEL VAULT (VaultV3.vy @ v3.1.0, aritmética chequeada como la de Vyper) */

    function _unl(Snap memory s) internal pure returns (uint256) {
        if (s.D > s.ts) return s.R * (s.ts - s.LPU) / EXT;
        if (s.D != 0) return s.B;
        return 0;
    }

    function _eff(Snap memory s) internal pure returns (uint256) {
        return s.S - _unl(s);
    }

    function _c2a(Snap memory s, uint256 sh, bool up) internal pure returns (uint256 a) {
        if (sh == type(uint256).max || sh == 0) return sh;
        uint256 ts = _eff(s);
        if (ts == 0) return sh;
        uint256 num = sh * (s.idle + s.debt);
        a = num / ts;
        if (up && num % ts != 0) ++a;
    }

    function _c2s(Snap memory s, uint256 a, bool up) internal pure returns (uint256 sh) {
        if (a == type(uint256).max || a == 0) return a;
        uint256 ts = _eff(s);
        if (ts == 0) return a;
        uint256 ta = s.idle + s.debt;
        if (ta == 0) return 0;
        uint256 num = a * ts;
        sh = num / ta;
        if (up && num % ta != 0) ++sh;
    }

    function _maxDep(Snap memory s) internal pure returns (uint256) {
        if (s.paused) return 0;
        if (s.depLimit == type(uint256).max) return s.depLimit;
        uint256 ta = s.idle + s.debt;
        return ta >= s.depLimit ? 0 : s.depLimit - ta;
    }

    function _issue(Snap memory m, uint256 h, uint256 x) internal pure {
        m.bal[h] += x;
        m.S += x;
    }

    function _burnH(Snap memory m, uint256 h, uint256 x) internal pure {
        m.bal[h] -= x;
        m.S -= x;
    }

    /* MODELO DE LA ESTRATEGIA (ERC4626 de OpenZeppelin 4.9.5 sin offset) */

    function _sC2A(Snap memory s, uint256 i, uint256 sh) internal pure returns (uint256) {
        return Math.mulDiv(sh, s.tA[i] + 1, s.tS[i] + 1);
    }

    function _sMaxRedeem(Snap memory s, uint256 i) internal pure returns (uint256) {
        if (s.liq[i] == type(uint256).max) return s.vsh[i];
        uint256 l = Math.mulDiv(s.liq[i], s.tS[i] + 1, s.tA[i] + 1);
        return s.vsh[i] < l ? s.vsh[i] : l;
    }

    /// @dev _assess_share_of_unrealised_losses.
    function _assess(Snap memory s, uint256 i, uint256 cd, uint256 needed) internal pure returns (uint256 u) {
        uint256 sa = _sC2A(s, i, s.vsh[i]);
        if (sa >= cd || cd == 0) return 0;
        uint256 num = needed * sa;
        u = needed - num / cd;
        if (num % cd != 0 && u < needed) ++u;
    }

    /// @dev _withdraw_from_strategy: canje de min(previewWithdraw, saldo); devuelve lo que llegó al vault y si revierte.
    function _sWithdraw(Snap memory m, uint256 i, uint256 a) internal pure returns (bool ok, uint256 got) {
        uint256 pw = Math.mulDiv(a, m.tS[i] + 1, m.tA[i] + 1, Math.Rounding.Up);
        uint256 sh = pw < m.vsh[i] ? pw : m.vsh[i];
        if (sh > _sMaxRedeem(m, i)) return (false, 0);
        uint256 assets = _sC2A(m, i, sh);
        uint256 c = assets < m.cut[i] ? assets : m.cut[i];
        got = assets - c;
        m.tA[i] -= assets;
        m.tS[i] -= sh;
        m.vsh[i] -= sh;
        m.vaultCash += got;
        m.sink += c;
        ok = true;
    }

    function _sDeposit(Snap memory m, uint256 i, uint256 a) internal pure {
        uint256 sh = Math.mulDiv(a, m.tS[i] + 1, m.tA[i] + 1);
        m.tA[i] += a;
        m.tS[i] += sh;
        m.vsh[i] += sh;
        m.vaultCash -= a;
    }

    /* OPERACIONES DEL MODELO: cada una devuelve si pasa y deja en `m` el estado esperado */

    struct W {
        uint256 req;
        uint256 cti;
        uint256 ctd;
        uint256 needed;
        uint256 prev;
        uint256 atw;
        uint256 uls;
        uint256 cd;
        uint256 maxW;
        uint256 got;
        uint256 loss;
        bool unrealised;
        bool realised;
        bool excess;
        bool fromStrat;
    }

    /// @dev _redeem con la cola por defecto (las tres estrategias en orden).
    function _simRedeem(Snap memory m, uint256 h, uint256 assets, uint256 shares, uint256 maxLoss)
        internal
        pure
        returns (bool, W memory w)
    {
        if (m.paused || shares == 0 || assets == 0 || maxLoss > MAX_BPS || m.bal[h] < shares) return (false, w);
        w.req = assets;
        w.cti = m.idle;
        if (w.req > w.cti) {
            w.ctd = m.debt;
            w.needed = w.req - w.cti;
            w.prev = m.vaultCash;
            for (uint256 i; i < NS; ++i) {
                if (!_redeemStep(m, i, w)) return (false, w);
                if (w.req <= w.cti) break;
            }
            if (w.cti < w.req) return (false, w);
            m.debt = w.ctd;
        }
        if (assets > w.req && maxLoss < MAX_BPS && assets - w.req > assets * maxLoss / MAX_BPS) return (false, w);
        _burnH(m, h, shares);
        m.idle = w.cti - w.req;
        m.vaultCash -= w.req;
        m.cash[h] += w.req;
        return (true, w);
    }

    /// @dev Un paso del bucle de _redeem sobre la estrategia i. false = revierte.
    function _redeemStep(Snap memory m, uint256 i, W memory w) internal pure returns (bool) {
        w.cd = m.cur[i];
        w.atw = w.needed < w.cd ? w.needed : w.cd;
        w.maxW = _sC2A(m, i, _sMaxRedeem(m, i));
        w.uls = _assess(m, i, w.cd, w.atw);
        if (w.uls > 0) {
            w.unrealised = true;
            if (w.maxW < w.atw - w.uls) {
                uint256 wanted = w.atw - w.uls;
                w.uls = w.uls * w.maxW / wanted;
                w.atw = w.maxW + w.uls;
            }
            w.atw -= w.uls;
            w.req -= w.uls;
            w.needed -= w.uls;
            w.ctd -= w.uls;
            if (w.atw == 0 && w.uls > 0) m.cur[i] = w.cd - w.uls;
        }
        if (w.maxW < w.atw) w.atw = w.maxW;
        if (w.atw == 0) return true;
        (bool ok, uint256 got) = _sWithdraw(m, i, w.atw);
        if (!ok) return false;
        w.fromStrat = true;
        w.got = m.vaultCash - w.prev;
        w.loss = 0;
        if (w.got > w.atw) {
            w.excess = w.excess || w.got > w.cd;
            w.atw = w.got > w.cd ? w.cd : w.atw + (w.got - w.atw);
        } else if (w.got < w.atw) {
            w.loss = w.atw - w.got;
            w.realised = true;
        }
        got;
        if (w.atw + w.uls > w.cd) return false; // new_debt = current_debt - (...) chequeado
        w.cti += w.atw - w.loss;
        w.req -= w.loss;
        w.ctd -= w.atw;
        m.cur[i] = w.cd - (w.atw + w.uls);
        if (w.req <= w.cti) return true;
        w.prev = m.vaultCash;
        if (w.atw > w.needed) return false; // assets_needed -= assets_to_withdraw chequeado
        w.needed -= w.atw;
        return true;
    }

    /// @dev _update_debt. Devuelve (pasa, realizó una pérdida).
    function _simUpdateDebt(Snap memory m, uint256 i, uint256 target, uint256 maxLoss) internal pure returns (bool, bool) {
        uint256 nd = m.shutdown ? 0 : target;
        uint256 cd = m.cur[i];
        if (nd == cd) return (false, false);
        if (cd > nd) {
            uint256 atw = cd - nd;
            if (m.idle + atw < m.minIdle) {
                atw = m.minIdle - m.idle;
                if (atw > cd) atw = cd;
            }
            uint256 wd = _sC2A(m, i, _sMaxRedeem(m, i));
            if (wd < atw) atw = wd;
            if (atw == 0) return (true, false);
            if (_assess(m, i, cd, atw) != 0) return (false, false);
            uint256 pre = m.vaultCash;
            (bool ok,) = _sWithdraw(m, i, atw);
            if (!ok) return (false, false);
            uint256 got = m.vaultCash - pre;
            if (got > cd) got = cd;
            if (got < atw && maxLoss < MAX_BPS) {
                if (atw - got > atw * maxLoss / MAX_BPS) return (false, false);
            } else if (got > atw) {
                atw = got;
            }
            m.idle += got;
            m.debt -= atw;
            m.cur[i] = cd - atw;
            return (true, got < atw);
        }
        if (nd > m.maxd[i]) {
            nd = m.maxd[i];
            if (nd < cd) return (true, false);
        }
        if (m.sp[i]) return (true, false);
        uint256 atd = nd - cd;
        if (m.idle <= m.minIdle) return (true, false);
        uint256 avail = m.idle - m.minIdle;
        if (atd > avail) atd = avail;
        if (atd > 0) {
            _sDeposit(m, i, atd);
            m.idle -= atd;
            m.debt += atd;
        }
        m.cur[i] = cd + atd;
        return (true, false);
    }

    struct Rep {
        uint256 gain;
        uint256 loss;
        uint256 fees;
        uint256 refunds;
        uint256 stb;
        uint256 stl;
        uint256 tfs;
        uint256 pfs;
        bool capped; // la quema pedida pasó el buffer: la pérdida baja el precio
    }

    /// @dev _process_report(strategy i). false = revierte.
    function _simReport(Snap memory m, uint256 i) internal pure returns (bool, Rep memory r) {
        uint256 ta = _sC2A(m, i, m.vsh[i]);
        uint256 cd = m.cur[i];
        if (ta > cd) r.gain = ta - cd;
        else r.loss = cd - ta;
        r.fees = r.gain * m.feeBps / MAX_BPS;
        r.refunds = r.loss * m.refundBps / MAX_BPS;
        if (r.refunds > 0 && r.refunds > m.acctCash) r.refunds = m.acctCash;
        if (r.loss + r.fees > 0) {
            r.stb = _c2s(m, r.loss + r.fees, true);
            if (r.fees > 0) {
                r.tfs = r.stb * r.fees / (r.loss + r.fees);
                if (m.pbps > 0) r.pfs = r.tfs * m.pbps / MAX_BPS;
            }
        }
        if (r.gain + r.refunds > 0 && m.T != 0) r.stl = _c2s(m, r.gain + r.refunds, false);
        uint256 u = _unl(m);
        if (m.S + r.stl < r.stb + u) return (false, r);
        uint256 ending = m.S + r.stl - r.stb - u;
        if (ending > m.S) {
            uint256 x = ending - m.S;
            m.B += x;
            m.S += x;
        } else if (m.S > ending) {
            r.capped = m.S - ending > m.B;
            uint256 tb = m.S - ending < m.B ? m.S - ending : m.B;
            m.B -= tb;
            m.S -= tb;
        }
        r.stl = r.stl > r.stb ? r.stl - r.stb : 0;
        if (r.refunds > 0) {
            m.acctCash -= r.refunds;
            m.vaultCash += r.refunds;
            m.idle += r.refunds;
        }
        if (r.gain > 0) {
            m.cur[i] = cd + r.gain;
            m.debt += r.gain;
        } else if (r.loss > 0) {
            m.cur[i] = cd - r.loss;
            m.debt -= r.loss;
        }
        if (r.tfs > 0) {
            _issue(m, H_ACCT, r.tfs - r.pfs);
            if (r.pfs > 0) _issue(m, H_PROTO, r.pfs);
        }
        if (m.B > 0) {
            uint256 plt;
            if (m.D > m.ts) plt = (m.B - r.stl) * (m.D - m.ts);
            uint256 period = (plt + r.stl * m.T) / m.B;
            if (period == 0) return (false, r);
            m.R = m.B * EXT / period;
            m.D = m.ts + period;
            m.LPU = m.ts;
        } else {
            m.D = 0;
        }
        return (true, r);
    }

    /* EL MODELO POR LLAMADA EXTERNA
       El vault (Vyper) y las estrategias (mulDiv de OpenZeppelin) hacen las mismas cuentas que el modelo, con
       aritmética chequeada. El handler llama así al modelo de cada operación: si una cuenta desborda o divide por cero,
       el modelo revierte sin tumbar al handler, la operación se espera rechazada y YV-LIVE controla que el vault
       también revierta. */

    function simEnter(Snap memory pre, uint256 h, uint256 x, bool isMint)
        external
        pure
        returns (bool expect, Snap memory m)
    {
        m = _copy(pre);
        uint256 a = isMint ? _c2a(pre, x, true) : x;
        uint256 sh = isMint ? x : _c2s(pre, x, false);
        expect = a <= _maxDep(pre) && a > 0 && sh > 0 && a <= pre.cash[h];
        if (expect) {
            m.cash[h] -= a;
            m.vaultCash += a;
            m.idle += a;
            _issue(m, h, sh);
        }
    }

    function simRedeem(Snap memory pre, uint256 h, uint256 assets, uint256 shares, uint256 maxLoss)
        external
        pure
        returns (bool expect, W memory w, Snap memory m)
    {
        m = _copy(pre);
        (expect, w) = _simRedeem(m, h, assets, shares, maxLoss);
    }

    function simUpdateDebt(Snap memory pre, uint256 i, uint256 target, uint256 maxLoss)
        external
        pure
        returns (bool expect, bool lossy, Snap memory m)
    {
        m = _copy(pre);
        (expect, lossy) = _simUpdateDebt(m, i, target, maxLoss);
    }

    function simReport(Snap memory pre, uint256 i) external pure returns (bool expect, Rep memory r, Snap memory m) {
        m = _copy(pre);
        (expect, r) = _simReport(m, i);
    }

    /* LEYES */

    function _lawState(Snap memory e, Snap memory p) internal {
        _ok(p.idle == e.idle, L_TA, "total_idle distinto del modelo (modelo, real)", e.idle, p.idle);
        _ok(p.debt == e.debt, L_TA, "total_debt distinto del modelo (modelo, real)", e.debt, p.debt);
        for (uint256 i; i < NS; ++i) {
            _ok(p.cur[i] == e.cur[i], L_TA, "deuda de una estrategia distinta del modelo (modelo, real)", e.cur[i], p.cur[i]);
            _ok(p.tA[i] == e.tA[i] && p.tS[i] == e.tS[i] && p.vsh[i] == e.vsh[i], L_FUNDS, "estado de una estrategia distinto del modelo (activos, acciones del vault)", p.tA[i], p.vsh[i]);
        }
        _ok(p.S == e.S, L_SUP, "total_supply crudo distinto del modelo (modelo, real)", e.S, p.S);
        _ok(p.B == e.B, L_LOCK, "buffer distinto del modelo (modelo, real)", e.B, p.B);
        _ok(p.R == e.R && p.D == e.D && p.LPU == e.LPU, L_LOCK, "cronograma distinto del modelo (fecha modelo, fecha real)", e.D, p.D);
        for (uint256 h; h < NH; ++h) {
            _ok(p.bal[h] == e.bal[h], h < 4 ? L_WD : L_FEE, "saldo de acciones distinto del modelo (modelo, real)", e.bal[h], p.bal[h]);
        }
        for (uint256 i; i < 4; ++i) {
            _ok(p.cash[i] == e.cash[i], L_WD, "el actor no cobro o no pago lo del modelo (modelo, real)", e.cash[i], p.cash[i]);
        }
        _ok(p.vaultCash == e.vaultCash && p.acctCash == e.acctCash && p.sink == e.sink, L_FUNDS, "activo del vault, del accountant o perdido distinto del modelo (modelo, real)", e.vaultCash, p.vaultCash);
        _lawLedger(p);
    }

    function _lawLedger(Snap memory s) internal {
        uint256 sum = s.B;
        for (uint256 h; h < NH; ++h) {
            sum += s.bal[h];
        }
        _ok(sum == s.S, L_LEDGER, "la suma de los saldos crudos no es total_supply (suma, total_supply)", sum, s.S);
        _ok(s.vaultCash >= s.idle, L_FUNDS, "el vault tiene menos activo que total_idle (activo, total_idle)", s.vaultCash, s.idle);
    }

    /// @dev YV-VIEW: totales y conversiones del vault contra el modelo.
    function _lawViews(Snap memory s) internal {
        _ok(vault.totalSupply() == _eff(s), L_VIEW, "totalSupply distinto del modelo (modelo, real)", _eff(s), vault.totalSupply());
        _ok(vault.unlockedShares() == _unl(s), L_VIEW, "unlockedShares distinto del modelo (modelo, real)", _unl(s), vault.unlockedShares());
        _ok(vault.totalAssets() == s.idle + s.debt, L_VIEW, "totalAssets distinto de idle + debt (modelo, real)", s.idle + s.debt, vault.totalAssets());
        uint256 x = 10 ** uint256(token.decimals());
        _ok(vault.convertToAssets(x) == _c2a(s, x, false) && vault.previewRedeem(x) == _c2a(s, x, false), L_VIEW, "convertToAssets o previewRedeem distinto del modelo (modelo, real)", _c2a(s, x, false), vault.convertToAssets(x));
        _ok(vault.convertToShares(x) == _c2s(s, x, false) && vault.previewDeposit(x) == _c2s(s, x, false), L_VIEW, "convertToShares o previewDeposit distinto del modelo (modelo, real)", _c2s(s, x, false), vault.convertToShares(x));
        _ok(vault.previewMint(x) == _c2a(s, x, true) && vault.previewWithdraw(x) == _c2s(s, x, true), L_VIEW, "previewMint o previewWithdraw distinto del modelo (0, 0)", 0, 0);
        _ok(vault.maxDeposit(actors[0]) == _maxDep(s), L_VIEW, "maxDeposit distinto del modelo (modelo, real)", _maxDep(s), vault.maxDeposit(actors[0]));
    }

    /// @dev YV-INF-2: el precio (activos por acción efectiva) no bajó: ta'·s ≥ ta·s'.
    function _lawPrice(Snap memory pre, Snap memory post) internal {
        uint256 sb = _eff(pre);
        uint256 sa = _eff(post);
        if (sb == 0 || sa == 0) return;
        uint256 tb = pre.idle + pre.debt;
        uint256 ta = post.idle + post.debt;
        (uint256 h1, uint256 l1) = _mul(ta, sb);
        (uint256 h2, uint256 l2) = _mul(tb, sa);
        _ok(h1 > h2 || (h1 == h2 && l1 >= l2), L_INF2, "el precio por accion bajo (activos antes, despues)", tb, ta);
    }

    function _mul(uint256 a, uint256 b) internal pure returns (uint256 hi, uint256 lo) {
        assembly ("memory-safe") {
            let mm := mulmod(a, b, not(0))
            lo := mul(a, b)
            hi := sub(sub(mm, lo), lt(mm, lo))
        }
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
        if (law == L_TA) return "YV-TA";
        if (law == L_SUP) return "YV-SUP";
        if (law == L_LOCK) return "YV-LOCK";
        if (law == L_FEE) return "YV-FEE";
        if (law == L_WD) return "YV-WD";
        if (law == L_INF2) return "YV-INF-2";
        if (law == L_VIEW) return "YV-VIEW";
        if (law == L_FUNDS) return "YV-FUNDS";
        if (law == L_LIVE) return "YV-LIVE";
        return "YV-LEDGER";
    }

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
        returns (uint256 laws, uint256 gain, uint256 loss, uint256 fees, uint256 refunds, uint256 unrealised)
    {
        return (hLaws, hGain, hLoss, hFees, hRefunds, hUnrealised);
    }

    function coverage2()
        external
        view
        returns (uint256 withdrawLoss, uint256 fromStrat, uint256 debtUp, uint256 debtDown, uint256 rejected, uint256 excess)
    {
        return (hWithdrawLoss, hFromStrat, hDebtUp, hDebtDown, hRejected, hExcess);
    }

    function coverage3() external view returns (uint256 idleFloor, uint256 overflow, uint256 domain) {
        return (hIdleFloor, hOverflow, hDomain);
    }
}
