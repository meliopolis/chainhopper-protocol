// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IAcrossV3SpokePoolMessageHandler} from "../interfaces/external/IAcrossV3.sol";
import {Settler} from "./Settler.sol";

abstract contract AcrossSettler is Settler, IAcrossV3SpokePoolMessageHandler {
    error NotSpokePool();

    address private immutable spokePool;

    constructor(address _spokePool) {
        spokePool = _spokePool;
    }

    function handleV3AcrossMessage(address token, uint256 amount, address, bytes memory message) external override {
        require(msg.sender == spokePool, NotSpokePool());

        _settle(token, amount, message);
    }
}
