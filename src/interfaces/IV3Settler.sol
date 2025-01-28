// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISettler} from "./ISettler.sol";
import "./external/AcrossMessageHandler.sol";

interface IV3Settler is ISettler {
    struct V3SettlementParams {
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

    event SettledOnV3(address indexed recipient, uint256 indexed tokenId, uint256 amount0, uint256 amount1);
}
