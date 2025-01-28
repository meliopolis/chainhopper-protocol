// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISettler {
    error AtLeastOneAmountMustBeGreaterThanZero();
    error InsufficientBalance();

    struct BaseSettlementParams {
        address token0;
        address token1;
        uint24 feeTier;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint24 senderFeeBps;
        address senderFeeRecipient;
    }
}
