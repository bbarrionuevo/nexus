// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// Entorno local de nexus para MetaMorpho: Morpho Blue, un mercado con préstamos, un mercado "idle" y el vault.
// `python -m nexus.secresearch.validate ... --harness morpho-org__metamorpho` lo copia a test/nexus/ del clon y lo
// corre con forge (FFI apagado). Todo pasa en la EVM local de forge: sin RPC, sin forks, sin transacciones reales.
//
// No importa forge-std a propósito: el repo trae cinco copias (1.6 a 1.15) y dos importaciones podrían resolver a
// archivos distintos, con dos `Test` en el mismo árbol de herencia. Los tests heredan `Test` por un solo camino y
// este contrato usa los cheatcodes por una interfaz mínima propia.

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {IMetaMorpho} from "../../src/interfaces/IMetaMorpho.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {IrmMock} from "../../src/mocks/IrmMock.sol";
import {OracleMock} from "../../src/mocks/OracleMock.sol";

/// @dev Los cheatcodes de forge que usa el entorno (mismas firmas que forge-std/Vm.sol).
interface INexusCheats {
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function warp(uint256 newTimestamp) external;
    function mockCall(address callee, bytes calldata data, bytes calldata returnData) external;
    function getCode(string calldata artifactPath) external view returns (bytes memory creationBytecode);
}

abstract contract NexusMetaMorphoBase {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    INexusCheats internal constant CHEATS = INexusCheats(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant MAX_ASSETS = 1e28; // = MAX_TEST_ASSETS de la suite de MetaMorpho
    uint256 internal constant SUPPLY_CAP = 1e30; // holgado y < uint128 (Morpho guarda los totales en uint128)
    uint256 internal constant LLTV = 0.8 ether;
    uint256 internal constant TIMELOCK = 1 weeks;

    address internal constant MORPHO_OWNER = address(uint160(uint256(keccak256("nexus.MorphoOwner"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("nexus.Owner"))));
    address internal constant CURATOR = address(uint160(uint256(keccak256("nexus.Curator"))));
    address internal constant ALLOCATOR = address(uint160(uint256(keccak256("nexus.Allocator"))));
    address internal constant FEE_RECIPIENT = address(uint160(uint256(keccak256("nexus.FeeRecipient"))));
    address internal constant DONOR = address(uint160(uint256(keccak256("nexus.Donor"))));
    address internal constant BORROWER = address(uint160(uint256(keccak256("nexus.Borrower"))));
    address internal constant BAD_BORROWER = address(uint160(uint256(keccak256("nexus.BadBorrower"))));
    address internal constant LIQUIDATOR = address(uint160(uint256(keccak256("nexus.Liquidator"))));

    IMorpho internal morpho;
    ERC20Mock internal loanToken;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    IMetaMorpho internal vault;
    MarketParams internal market; // con préstamos (colateral, oráculo, LLTV 80 %)
    MarketParams internal idle; // sin colateral: nadie puede pedir prestado

    /// @dev `fee` en WAD (máx. 0.5e18). `assetDecimals` != 18 cambia DECIMALS_OFFSET: 10**offset acciones virtuales.
    function _deployEnv(uint256 fee, uint8 assetDecimals) internal {
        morpho = IMorpho(_deploy("Morpho.sol", abi.encode(MORPHO_OWNER)));
        loanToken = new ERC20Mock("loan", "B");
        collateralToken = new ERC20Mock("collateral", "C");
        oracle = new OracleMock();
        oracle.setPrice(ORACLE_PRICE_SCALE);
        irm = new IrmMock();
        irm.setApr(0.5 ether); // 50 % anual, como la suite de MetaMorpho

        idle = MarketParams({
            loanToken: address(loanToken), collateralToken: address(0), oracle: address(0), irm: address(irm), lltv: 0
        });
        market = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            irm: address(irm),
            lltv: LLTV
        });

        CHEATS.startPrank(MORPHO_OWNER);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0);
        morpho.enableLltv(LLTV);
        CHEATS.stopPrank();
        morpho.createMarket(idle);
        morpho.createMarket(market);

        if (assetDecimals != 18) {
            CHEATS.mockCall(address(loanToken), abi.encodeWithSignature("decimals()"), abi.encode(assetDecimals));
        }
        vault = IMetaMorpho(
            _deploy(
                "MetaMorpho.sol",
                abi.encode(OWNER, address(morpho), TIMELOCK, address(loanToken), "MetaMorpho Vault", "MMV")
            )
        );

        CHEATS.startPrank(OWNER);
        vault.setCurator(CURATOR);
        vault.setIsAllocator(ALLOCATOR, true);
        vault.setFeeRecipient(FEE_RECIPIENT);
        if (fee != 0) vault.setFee(fee);
        CHEATS.stopPrank();

        CHEATS.startPrank(CURATOR);
        vault.submitCap(market, SUPPLY_CAP);
        vault.submitCap(idle, SUPPLY_CAP);
        CHEATS.stopPrank();
        CHEATS.warp(block.timestamp + TIMELOCK);
        vault.acceptCap(market); // la cola de retiro queda [market, idle]
        vault.acceptCap(idle);

        Id[] memory supplyQueue = new Id[](2);
        supplyQueue[0] = market.id(); // primero el mercado con préstamos, el idle al final (como test/ERC4626Test.sol)
        supplyQueue[1] = idle.id();
        CHEATS.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        CHEATS.prank(DONOR);
        loanToken.approve(address(morpho), type(uint256).max);
        CHEATS.startPrank(BORROWER);
        collateralToken.approve(address(morpho), type(uint256).max);
        loanToken.approve(address(morpho), type(uint256).max);
        CHEATS.stopPrank();
        CHEATS.prank(BAD_BORROWER);
        collateralToken.approve(address(morpho), type(uint256).max);
        CHEATS.prank(LIQUIDATOR);
        loanToken.approve(address(morpho), type(uint256).max);
    }

    /// @dev Liquidez del mercado con préstamos (con el interés pendiente que simula MorphoBalancesLib).
    function _liquidity() internal view returns (uint256) {
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(market);
        return totalSupplyAssets - totalBorrowAssets;
    }

    /// @dev Ganancia: cualquiera puede depositar en Morpho a nombre del vault y totalAssets sube sin emitir acciones.
    /// Es la "donación" de la suite a16z, que en MetaMorpho no cuenta si los tokens van directo al contrato.
    function _donate(uint256 assets) internal {
        if (assets == 0) return;
        loanToken.mint(DONOR, assets);
        CHEATS.prank(DONOR);
        morpho.supply(market, assets, 0, address(vault), hex"");
    }

    /// @dev Interés pendiente: un prestatario toma liquidez y pasa el tiempo. Morpho todavía no lo contabilizó (lo
    /// simula MorphoBalancesLib), así que totalAssets y preview* tienen que estimarlo igual que deposit/withdraw.
    function _borrowAndWait(uint256 assets, uint256 elapsed) internal {
        uint256 liquidity = _liquidity();
        if (assets > liquidity) assets = liquidity;
        if (assets != 0) {
            collateralToken.mint(BORROWER, assets * 4); // precio 1:1 y LLTV 80 %: aguanta años de interés
            CHEATS.startPrank(BORROWER);
            morpho.supplyCollateral(market, assets * 4, BORROWER, hex"");
            morpho.borrow(market, assets, 0, BORROWER, BORROWER);
            CHEATS.stopPrank();
        }
        CHEATS.warp(block.timestamp + elapsed);
    }

    /// @dev Pérdida: deuda incobrable. Un prestatario toma `assets`, el oráculo cae a 0, se le liquida todo el
    /// colateral sin repagar nada y Morpho descuenta la deuda restante a los proveedores del mercado (el vault).
    function _badDebt(uint256 assets) internal {
        uint256 liquidity = _liquidity();
        if (assets > liquidity) assets = liquidity;
        if (assets == 0) return;
        uint256 collateral = assets * 2;
        collateralToken.mint(BAD_BORROWER, collateral);
        CHEATS.startPrank(BAD_BORROWER);
        morpho.supplyCollateral(market, collateral, BAD_BORROWER, hex"");
        morpho.borrow(market, assets, 0, BAD_BORROWER, BAD_BORROWER);
        CHEATS.stopPrank();
        oracle.setPrice(0);
        CHEATS.prank(LIQUIDATOR);
        morpho.liquidate(market, BAD_BORROWER, collateral, 0, hex"");
        oracle.setPrice(ORACLE_PRICE_SCALE);
    }

    /// @dev Direcciones del entorno: los tests no las usan como usuarios (un depósito al receptor de comisiones,
    /// por ejemplo, se mezclaría con las acciones de comisión y daría una falla falsa).
    function _reserved(address a) internal view returns (bool) {
        return uint160(a) <= 0xff || a == MORPHO_OWNER || a == OWNER || a == CURATOR || a == ALLOCATOR
            || a == FEE_RECIPIENT || a == DONOR || a == BORROWER || a == BAD_BORROWER || a == LIQUIDATOR
            || a == address(vault) || a == address(morpho) || a == address(loanToken) || a == address(collateralToken);
    }

    function _deploy(string memory what, bytes memory args) internal returns (address addr) {
        bytes memory code = abi.encodePacked(CHEATS.getCode(what), args);
        assembly ("memory-safe") {
            addr := create(0, add(code, 0x20), mload(code))
        }
        require(addr != address(0), "nexus: no se pudo desplegar");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev `x` llevado a [lo, hi] sin depender de forge-std (y sin el log de `bound`).
    function _clamp(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        uint256 size = hi - lo;
        if (size == type(uint256).max) return x;
        return lo + x % (size + 1);
    }
}
