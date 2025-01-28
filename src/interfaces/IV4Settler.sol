// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./external/AcrossMessageHandler.sol";
import {ISettler} from "./ISettler.sol";

interface IV4Settler is ISettler {

    struct V4SettlementParams {
        ISettler.BaseSettlementParams baseParams;
        address hooks;
    }

    event SettledOnV4(address indexed recipient, uint256 indexed tokenId, uint256 amount0, uint256 amount1);
}
