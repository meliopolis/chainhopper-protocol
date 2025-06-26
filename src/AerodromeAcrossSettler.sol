// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {AerodromeSettler} from "./base/AerodromeSettler.sol";

/// @title AerodromeAcrossSettler
/// @notice A settler that settles migrations on Aerodrome and Across
contract AerodromeAcrossSettler is AerodromeSettler, AcrossSettler {
    /// @notice Constructor
    /// @param initialOwner The initial owner of the settler
    /// @param positionManager The position manager
    /// @param universalRouter The universal router
    /// @param permit2 The permit2 contract
    /// @param spokePool The spokepool address
    constructor(
        address initialOwner,
        address positionManager,
        address universalRouter,
        address permit2,
        address spokePool
    ) AerodromeSettler(positionManager, universalRouter, permit2) AcrossSettler(spokePool) Settler(initialOwner) {}
}
