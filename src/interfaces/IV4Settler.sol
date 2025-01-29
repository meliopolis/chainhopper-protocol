// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./external/AcrossMessageHandler.sol";
import {ISettler} from "./ISettler.sol";

interface IV4Settler is ISettler {
    struct V4SettlementParams {
        address recipient; // always goes first
        address token0;
        address token1;
        uint24 feeTier;
        address hooks;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Min;
        uint256 amount1Min;
        uint24 senderFeeBps;
        address senderFeeRecipient;
    }

    event SettledOnV4(address indexed recipient, uint256 indexed tokenId, uint256 amount0, uint256 amount1);
}
