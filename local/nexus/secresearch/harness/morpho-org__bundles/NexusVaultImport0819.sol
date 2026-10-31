// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

// Hace compilar la IRM adaptativa (solc 0.8.19, el de su pragma) en el proyecto reducido de los Bundles de vaults, para
// desplegarla con deployCode ("AdaptiveCurveIrm.sol"): el adapter de Vault V2 exige que los mercados la usen. Blue sale
// de NexusBlueImport.sol, el mismo que usan los otros cazadores de Bundles: con dos Morpho.sol compilados (el repo
// entero, en validate, compila todo el harness), deployCode("Morpho.sol") sería ambiguo.
import {AdaptiveCurveIrm} from "../../lib/vault-v2/lib/morpho-blue-irm/src/adaptive-curve-irm/AdaptiveCurveIrm.sol";
