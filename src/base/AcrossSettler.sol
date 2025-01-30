// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAcrossV3SpokePoolMessageHandler} from "../interfaces/external/IAcrossV3.sol";
import {Settler} from "./Settler.sol";

abstract contract AcrossSettler is Settler, IAcrossV3SpokePoolMessageHandler {
    error NotSpokePool();
    error BridgedTokenMustBeUsedInPosition();

    address private immutable spokePool;

    constructor(address _spokePool) {
        spokePool = _spokePool;
    }

    function handleV3AcrossMessage(address token, uint256 amount, address, bytes memory message) external override {
        if (msg.sender != spokePool) revert NotSpokePool();
        this.settleOuter(token, amount, message);
    }

    // requires implementing this function in child contract
    function settleOuter(address token, uint256 amount, bytes memory message) external virtual returns (uint256);
}
