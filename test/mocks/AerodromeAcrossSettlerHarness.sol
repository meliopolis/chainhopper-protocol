// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossSettler} from "../../src/base/AcrossSettler.sol";
import {Settler} from "../../src/base/Settler.sol";
import {AerodromeSettler} from "../../src/base/AerodromeSettler.sol";

/// @title UniswapV3AcrossSettler
/// @notice A settler that settles migrations on Uniswap V3 and Across
contract AerodromeAcrossSettlerHarness is AerodromeSettler, AcrossSettler {
    /// @notice Constructor
    /// @param initialOwner The initial owner of the settler
    /// @param positionManager The position manager
    /// @param router The router
    /// @param permit2 The permit2 contract
    /// @param spokePool The spokepool address
    constructor(address initialOwner, address positionManager, address router, address permit2, address spokePool)
        AerodromeSettler(positionManager, router, permit2)
        AcrossSettler(spokePool)
        Settler(initialOwner)
    {}

    function checkSettlementCache(bytes32 migrationId) public view returns (bool) {
        return settlementCaches[migrationId].recipient != address(0);
    }
}
