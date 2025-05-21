// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AcrossSettler} from "../../src/base/AcrossSettler.sol";
import {Settler} from "../../src/base/Settler.sol";
import {UniswapV4Settler} from "../../src/base/UniswapV4Settler.sol";

/// @title UniswapV4AcrossSettler
/// @notice A settler that settles migrations on Uniswap V4 and Across
contract UniswapV4AcrossSettlerHarness is UniswapV4Settler, AcrossSettler {
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
        address spokePool,
        address weth
    )
        UniswapV4Settler(positionManager, universalRouter, permit2, weth)
        AcrossSettler(spokePool)
        Settler(initialOwner)
    {}

    function checkSettlementCache(bytes32 migrationId) public view returns (bool) {
        return settlementCaches[migrationId].recipient != address(0);
    }
}
