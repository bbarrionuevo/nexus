// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

// Hace compilar Vault V2 y la fábrica de su adapter de Blue (solc 0.8.28, el de su pragma) en el proyecto reducido de
// los Bundles de vaults, para desplegarlos con deployCode ("VaultV2Factory.sol", "MorphoMarketV1AdapterV2Factory.sol").
import {VaultV2Factory} from "../../lib/vault-v2/src/VaultV2Factory.sol";
import {MorphoMarketV1AdapterV2Factory} from "../../lib/vault-v2/src/adapters/MorphoMarketV1AdapterV2Factory.sol";
