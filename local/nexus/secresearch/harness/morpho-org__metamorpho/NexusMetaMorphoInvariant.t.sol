// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// Invariantes de MetaMorpho con un handler: forge encadena llamadas al azar (depósitos, retiros, transferencias,
// donaciones, préstamos, paso del tiempo, deuda incobrable y reasignaciones del allocator) y después de cada una
// verifica:
//   1. Los max* no prometen de más: depositar maxDeposit, acuñar maxMint, retirar maxWithdraw y canjear maxRedeem
//      no revierten (ERC-4626: "MUST NOT be higher than the actual maximum").
//   2. Los preview* no mienten a favor del usuario: deposit >= previewDeposit, mint <= previewMint,
//      withdraw <= previewWithdraw y redeem >= previewRedeem.
//   3. El precio por acción no baja (más allá de unos wei de redondeo por mercado) si no hubo deuda incobrable:
//      si baja, alguien se llevó valor de los demás tenedores. Se mide el precio de la especificación (ver
//      _exactPrice) y además convertToAssets nunca puede valer menos que ese precio.
//   4. totalSupply = suma de saldos; lo que el vault promete canjear <= totalAssets; el vault no retiene tokens.
// Las variantes son las mismas que en NexusMetaMorphoERC4626.t.sol.
//
// Además cada acción pasa por NexusVulnerabilityHunter (modificador `hunted`): contabilidad fantasma independiente de
// los view del vault y leyes exactas de redondeo, comisiones y solvencia (ver ese archivo). La API del handler no cambia.

import {Test} from "../../lib/forge-std/src/Test.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketAllocation} from "../../src/interfaces/IMetaMorpho.sol";
import {NexusVulnerabilityHunter} from "./NexusVulnerabilityHunter.sol";

contract NexusMetaMorphoHandler is NexusVulnerabilityHunter {
    using MorphoBalancesLib for IMorpho;

    uint256 internal constant N_ACTORS = 3;
    uint256 internal constant PRICE_UNIT = 1e36; // acciones de referencia para medir el precio sin perder precisión
    uint256 internal constant DUST = 4; // wei de redondeo tolerados por operación (Morpho redondea en cada mercado)

    struct Snap {
        uint256 price;
        uint256 supply;
    }

    address[N_ACTORS] public actors;
    uint256 public violations;
    string public firstViolation;
    uint256 public checks; // cuántas verificaciones corrieron de verdad (que no pase "en vacío")
    uint256 public losses;

    constructor(uint256 fee, uint8 assetDecimals) {
        _deployEnv(fee, assetDecimals);
        for (uint256 i; i < N_ACTORS; ++i) {
            actors[i] = address(uint160(uint256(keccak256(abi.encodePacked("nexus.actor", i)))));
            CHEATS.prank(actors[i]);
            loanToken.approve(address(vault), type(uint256).max);
        }
        _hunterInit(_hunterHolders(), _hunterMarkets());
    }

    /// @dev Tenedores que vigila el cazador: los actores y el receptor de comisiones.
    function _hunterHolders() internal view returns (address[] memory h) {
        h = new address[](N_ACTORS + 1);
        for (uint256 i; i < N_ACTORS; ++i) {
            h[i] = actors[i];
        }
        h[N_ACTORS] = FEE_RECIPIENT;
    }

    /// @dev Mercados del entorno; `market` es el índice 0 en el cazador.
    function _hunterMarkets() internal view virtual returns (MarketParams[] memory m) {
        m = new MarketParams[](2);
        m[0] = market;
        m[1] = idle;
    }

    /* ACCIONES DE USUARIOS */

    function deposit(uint256 actorSeed, uint256 assets) external hunted(OP_DEPOSIT, _actor(actorSeed), address(0), 0) {
        address a = _actor(actorSeed);
        uint256 max = vault.maxDeposit(a);
        assets = _clamp(assets, 0, _min(max, MAX_ASSETS));
        loanToken.mint(a, assets);
        uint256 preview = vault.previewDeposit(assets);
        Snap memory s0 = _snap();
        CHEATS.prank(a);
        try vault.deposit(assets, a) returns (uint256 shares) {
            if (shares < preview) _flag("deposit entrego menos acciones que previewDeposit (preview, real)", preview, shares);
        } catch {
            _flag("deposit de un monto <= maxDeposit revirtio (monto, maxDeposit)", assets, max);
        }
        _checkPrice(s0, "deposit");
    }

    function mint(uint256 actorSeed, uint256 shares) external hunted(OP_MINT, _actor(actorSeed), address(0), 0) {
        address a = _actor(actorSeed);
        uint256 max = vault.maxMint(a);
        shares = _clamp(shares, 0, _min(max, vault.previewDeposit(MAX_ASSETS)));
        uint256 preview = vault.previewMint(shares);
        loanToken.mint(a, preview);
        Snap memory s0 = _snap();
        CHEATS.prank(a);
        try vault.mint(shares, a) returns (uint256 assets) {
            if (assets > preview) _flag("mint cobro mas activos que previewMint (preview, real)", preview, assets);
        } catch {
            _flag("mint de acciones <= maxMint revirtio (acciones, maxMint)", shares, max);
        }
        _checkPrice(s0, "mint");
    }

    function withdraw(uint256 actorSeed, uint256 assets) external hunted(OP_WITHDRAW, _actor(actorSeed), address(0), 0) {
        address a = _actor(actorSeed);
        uint256 max = vault.maxWithdraw(a);
        assets = _clamp(assets, 0, max);
        uint256 preview = vault.previewWithdraw(assets);
        Snap memory s0 = _snap();
        CHEATS.prank(a);
        try vault.withdraw(assets, a, a) returns (uint256 shares) {
            if (shares > preview) _flag("withdraw quemo mas acciones que previewWithdraw (preview, real)", preview, shares);
        } catch {
            _flag("withdraw de un monto <= maxWithdraw revirtio (monto, maxWithdraw)", assets, max);
        }
        _checkPrice(s0, "withdraw");
    }

    function redeem(uint256 actorSeed, uint256 shares) external hunted(OP_REDEEM, _actor(actorSeed), address(0), 0) {
        address a = _actor(actorSeed);
        uint256 max = vault.maxRedeem(a);
        shares = _clamp(shares, 0, max);
        uint256 preview = vault.previewRedeem(shares);
        Snap memory s0 = _snap();
        CHEATS.prank(a);
        try vault.redeem(shares, a, a) returns (uint256 assets) {
            if (assets < preview) _flag("redeem entrego menos activos que previewRedeem (preview, real)", preview, assets);
        } catch {
            _flag("redeem de acciones <= maxRedeem revirtio (acciones, maxRedeem)", shares, max);
        }
        _checkPrice(s0, "redeem");
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 shares)
        external
        hunted(OP_TRANSFER, _actor(fromSeed), _actor(toSeed), 0)
    {
        address from = _actor(fromSeed);
        shares = _clamp(shares, 0, vault.balanceOf(from));
        Snap memory s0 = _snap();
        CHEATS.prank(from);
        vault.transfer(_actor(toSeed), shares);
        _checkPrice(s0, "transfer");
    }

    /* MERCADO Y TIEMPO */

    function donate(uint256 assets) external hunted(OP_DONATE, address(0), address(0), 0) {
        Snap memory s0 = _snap();
        _donate(_clamp(assets, 0, MAX_ASSETS));
        _checkPrice(s0, "donate");
    }

    function borrow(uint256 assets) external hunted(OP_BORROW, address(0), address(0), 0) {
        assets = _clamp(assets, 0, _liquidity() / 2); // deja liquidez para los retiros
        if (assets == 0) return;
        Snap memory s0 = _snap();
        _borrowAndWait(assets, 0);
        _checkPrice(s0, "borrow");
    }

    function repay(uint256 assets) external hunted(OP_REPAY, address(0), address(0), 0) {
        assets = _clamp(assets, 0, morpho.expectedBorrowAssets(market, BORROWER));
        if (assets == 0) return;
        loanToken.mint(BORROWER, assets);
        Snap memory s0 = _snap();
        CHEATS.prank(BORROWER);
        morpho.repay(market, assets, 0, BORROWER, hex"");
        _checkPrice(s0, "repay");
    }

    function warp(uint256 secs) external {
        Snap memory s0 = _snap();
        CHEATS.warp(block.timestamp + _clamp(secs, 1, 30 days));
        _checkPrice(s0, "warp");
    }

    function accrue() external hunted(OP_ACCRUE, address(0), address(0), 0) {
        Snap memory s0 = _snap();
        morpho.accrueInterest(market);
        _checkPrice(s0, "accrueInterest");
    }

    /// @dev Pérdida acotada al 10 % de la liquidez para que el vault no quede siempre en cero. El precio PUEDE bajar.
    function badDebt(uint256 assets) external hunted(OP_BAD_DEBT, address(0), address(0), 0) {
        assets = _clamp(assets, 0, _liquidity() / 10);
        if (assets == 0) return;
        _badDebt(assets);
        ++losses;
    }

    /// @dev El allocator mueve `assets` entre el mercado con préstamos y el idle (reallocate con el resto en max).
    function reallocate(bool toIdle, uint256 assets) external virtual hunted(OP_REALLOCATE, address(0), address(0), 0) {
        (MarketParams memory from, MarketParams memory to) = toIdle ? (market, idle) : (idle, market);
        uint256 supplied = morpho.expectedSupplyAssets(from, address(vault));
        assets = _clamp(assets, 0, toIdle ? _min(supplied, _liquidity()) : supplied);
        if (assets == 0) return;
        MarketAllocation[] memory allocations = new MarketAllocation[](2);
        allocations[0] = MarketAllocation({marketParams: from, assets: supplied - assets});
        allocations[1] = MarketAllocation({marketParams: to, assets: type(uint256).max});
        Snap memory s0 = _snap();
        CHEATS.prank(ALLOCATOR);
        vault.reallocate(allocations);
        _checkPrice(s0, "reallocate");
    }

    /* VERIFICACIÓN */

    /// @dev "" si todo está bien; si no, la primera violación con los números.
    function check() external view returns (string memory) {
        if (violations != 0) return firstViolation;
        uint256 sum = vault.balanceOf(FEE_RECIPIENT);
        uint256 promised = vault.previewRedeem(sum);
        for (uint256 i; i < N_ACTORS; ++i) {
            uint256 balance = vault.balanceOf(actors[i]);
            sum += balance;
            promised += vault.previewRedeem(balance);
        }
        if (sum != vault.totalSupply()) return "totalSupply distinto de la suma de saldos";
        if (promised > vault.totalAssets()) return "el vault promete canjear mas activos de los que tiene";
        if (loanToken.balanceOf(address(vault)) != 0) return "el vault retiene tokens sin depositar en Morpho";
        return "";
    }

    /// @dev Para depurar una secuencia reproducida: (vault, morpho, activo).
    function contracts() external view returns (address, address, address) {
        return (address(vault), address(morpho), address(loanToken));
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % N_ACTORS];
    }

    function _snap() internal view returns (Snap memory) {
        return Snap(_exactPrice(), vault.totalSupply());
    }

    /// @dev Precio de PRICE_UNIT acciones según la especificación: (totalAssets - comisión sobre el interés
    /// pendiente + 1) / (totalSupply + acciones virtuales). No sirve medir con convertToAssets: las acciones de
    /// comisión pendientes se redondean hacia abajo y, cuando ese piso salta, el precio "devuelve" hasta una acción
    /// entera de valor (con comisión del 25 % dio falsas alarmas de hasta 1,5 % con pocas acciones en circulación).
    function _exactPrice() internal view returns (uint256) {
        uint256 assets = vault.totalAssets();
        uint256 last = vault.lastTotalAssets();
        uint256 feeAssets = assets > last ? Math.mulDiv(assets - last, vault.fee(), 1 ether) : 0;
        return Math.mulDiv(PRICE_UNIT, assets + 1 - feeAssets, vault.totalSupply() + 10 ** vault.DECIMALS_OFFSET());
    }

    /// @dev Tolerancia: DUST wei de totalAssets repartidos entre las acciones (más 2 por los pisos de las cuentas).
    function _checkPrice(Snap memory s0, string memory action) internal {
        uint256 price = _exactPrice();
        uint256 shares = _min(s0.supply, vault.totalSupply()) + 10 ** vault.DECIMALS_OFFSET();
        uint256 tolerance = DUST * PRICE_UNIT / shares + 2;
        if (price + tolerance < s0.price) {
            _flag(string(abi.encodePacked(action, ": el precio por accion bajo sin perdida (antes, despues)")), s0.price, price);
        }
        // Con acciones de comisión redondeadas hacia abajo, convertToAssets >= precio exacto siempre (sin tolerancia).
        uint256 converted = vault.convertToAssets(PRICE_UNIT);
        if (converted < price) {
            _flag(string(abi.encodePacked(action, ": convertToAssets por debajo del precio exacto (convertido, exacto)")), converted, price);
        }
        ++checks;
    }

    /// @dev Las violaciones del cazador usan el mismo registro (check() devuelve la primera).
    function _hunterFlag(string memory what, uint256 x, uint256 y) internal override {
        _flag(what, x, y);
    }

    function _flag(string memory what, uint256 x, uint256 y) internal {
        if (violations++ == 0) {
            firstViolation = string(abi.encodePacked(what, ": ", _str(x), ", ", _str(y)));
        }
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
}

contract NexusMetaMorphoInvariantTest is Test {
    NexusMetaMorphoHandler internal handler;

    function setUp() public virtual {
        handler = new NexusMetaMorphoHandler(_fee(), _assetDecimals());
        targetContract(address(handler));
    }

    function _fee() internal pure virtual returns (uint256) {
        return 0;
    }

    function _assetDecimals() internal pure virtual returns (uint8) {
        return 18;
    }

    function invariant_metaMorpho() public view {
        string memory err = handler.check();
        assertEq(bytes(err).length, 0, err);
    }

    function afterInvariant() public {
        emit log_named_uint("verificaciones", handler.checks());
        emit log_named_uint("perdidas", handler.losses());
        (uint256 laws, uint256 zeros, uint256 window, uint256 victimLoss, uint256 dust, uint256 budget,,,,,) =
            handler.hunterStats();
        emit log_named_uint("cazador: leyes evaluadas", laws);
        emit log_named_uint("cazador: depositos con 0 acciones", zeros);
        emit log_named_uint("cazador: precio maximo de una accion (ventana de redondeo a cero)", window);
        emit log_named_uint("cazador: mayor perdida de una victima", victimLoss);
        emit log_named_uint("cazador: polvo de Morpho absorbido (wei)", dust);
        emit log_named_uint("cazador: cota del polvo (wei)", budget);
    }
}

contract NexusMetaMorphoInvariantFeeTest is NexusMetaMorphoInvariantTest {
    function _fee() internal pure override returns (uint256) {
        return 0.25 ether;
    }
}

contract NexusMetaMorphoInvariantSixDecimalsTest is NexusMetaMorphoInvariantTest {
    function _assetDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
