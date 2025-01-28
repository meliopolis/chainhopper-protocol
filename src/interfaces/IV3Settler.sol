// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISettler} from "./ISettler.sol";
import "./external/AcrossMessageHandler.sol";

interface IV3Settler is ISettler {
    event SettledOnV3(address indexed recipient, uint256 indexed tokenId, uint256 amount0, uint256 amount1);
}
