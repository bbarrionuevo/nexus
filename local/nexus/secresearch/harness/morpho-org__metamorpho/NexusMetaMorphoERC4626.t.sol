// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26; // con via_ir, la suite a16z da "stack too deep" en solc <= 0.8.24

// Propiedades ERC-4626 de la suite de a16z (lib/openzeppelin-contracts/lib/erc4626-tests, ya incluida en el repo)
// aplicadas a MetaMorpho. Cada corrida arma un estado distinto: 4 usuarios con acciones y saldo, y después una
// ganancia (donación por Morpho + interés pendiente) o una pérdida (deuda incobrable). Tres variantes: sin
// comisión, con comisión del 25 % y con un activo de 6 decimales (DECIMALS_OFFSET = 12).
//
// Un test que falla NO es una vulnerabilidad: `_delta_ = 0` hace visible hasta 1 wei de redondeo, y el sentido del
// redondeo (a favor o en contra del vault) es lo primero que hay que mirar.

import {ERC4626Test} from "../../lib/openzeppelin-contracts/lib/erc4626-tests/ERC4626.test.sol";
import {NexusMetaMorphoBase} from "./NexusMetaMorphoBase.sol";

contract NexusMetaMorphoERC4626Test is NexusMetaMorphoBase, ERC4626Test {
    function setUp() public virtual override {
        _deployEnv(0, 18);
        _init();
    }

    function _init() internal {
        _underlying_ = address(loanToken);
        _vault_ = address(vault);
        _delta_ = 0; // estricto
        _vaultMayBeEmpty = true; // MetaMorpho tiene acciones virtuales: vacío también tiene que cumplir
        _unlimitedAmount = false; // topes de suministro y totales uint128 de Morpho
    }

    function setUpVault(Init memory init) public virtual override {
        for (uint256 i; i < N; ++i) {
            vm.assume(!_reserved(init.user[i]));
            init.share[i] = _clamp(init.share[i], 0, MAX_ASSETS);
            init.asset[i] = _clamp(init.asset[i], 0, MAX_ASSETS);
        }
        // Rendimiento en [-MAX_ASSETS, MAX_ASSETS] (bound(int) no existe en todas las versiones de forge-std).
        init.yield = int256(uint256(init.yield) % (2 * MAX_ASSETS + 1)) - int256(MAX_ASSETS);
        super.setUpVault(init);
    }

    /// @dev La suite original acuña o quema el activo en el contrato del vault; en MetaMorpho eso no mueve
    /// totalAssets (que sale de Morpho), así que la ganancia y la pérdida se hacen como pasarían de verdad.
    function setUpYield(Init memory init) public virtual override {
        if (init.yield >= 0) {
            uint256 gain = uint256(init.yield);
            _donate(gain / 2);
            _borrowAndWait(gain / 4, gain % 365 days);
        } else {
            _badDebt(uint256(-init.yield));
        }
    }
}

contract NexusMetaMorphoERC4626FeeTest is NexusMetaMorphoERC4626Test {
    function setUp() public override {
        _deployEnv(0.25 ether, 18);
        _init();
    }
}

contract NexusMetaMorphoERC4626SixDecimalsTest is NexusMetaMorphoERC4626Test {
    function setUp() public override {
        _deployEnv(0, 6);
        _init();
    }
}
