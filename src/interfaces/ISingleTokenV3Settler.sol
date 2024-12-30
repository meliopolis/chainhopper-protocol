// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISingleTokenV3Settler {
    struct SettlementParams {
        address recipient;
        // pool
        address token0;
        address token1;
        uint24 fee;
        // position params
        int24 tickLower;
        int24 tickUpper;
    }
}
