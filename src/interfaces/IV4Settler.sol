// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISettler} from "./ISettler.sol";

interface IV4Settler is ISettler {
    struct SettlementParams {
        BaseSettlementParams baseParams; // must be first
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Min;
        uint256 amount1Min;
    }
}
