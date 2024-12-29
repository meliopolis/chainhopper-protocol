// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IV3Settler {
    struct SettlementParams {
        bytes32 counterpartKey;
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
