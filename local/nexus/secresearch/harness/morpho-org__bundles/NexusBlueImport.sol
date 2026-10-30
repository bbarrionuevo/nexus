// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

// Hace compilar Morpho Blue (solc 0.8.19, el de su pragma) en el proyecto reducido, para que la fase 2 del cazador de
// MidnightBundlesV2 lo despliegue con deployCode ("Morpho.sol"): no se puede importar desde un archivo 0.8.34.
import {Morpho} from "../../lib/morpho-blue/src/Morpho.sol";
