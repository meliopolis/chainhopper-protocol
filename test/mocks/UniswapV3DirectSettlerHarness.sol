// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {DirectSettler} from "../../src/base/DirectSettler.sol";
import {Settler} from "../../src/base/Settler.sol";
import {UniswapV3Settler} from "../../src/base/UniswapV3Settler.sol";

/// @title UniswapV3DirectSettlerHarness
/// @notice A settler harness that settles migrations on Uniswap V3 using DirectTransfer
contract UniswapV3DirectSettlerHarness is UniswapV3Settler, DirectSettler {
    /// @notice Constructor
    /// @param initialOwner The initial owner of the settler
    /// @param positionManager The position manager
    /// @param universalRouter The universal router
    /// @param permit2 The permit2 contract
    constructor(address initialOwner, address positionManager, address universalRouter, address permit2)
        UniswapV3Settler(positionManager, universalRouter, permit2)
        DirectSettler()
        Settler(initialOwner)
    {}

    function checkSettlementCache(bytes32 migrationId) public view returns (bool) {
        return settlementCaches[migrationId].recipient != address(0);
    }
}
