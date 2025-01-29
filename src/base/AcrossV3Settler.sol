// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import {IAcrossV3SpokePoolMessageHandler} from "../interfaces/external/IAcrossV3.sol";

abstract contract AcrossV3Settler is IAcrossV3SpokePoolMessageHandler {
    error NotSpokePool();

    address private immutable spokePool;

    constructor(address _spokePool) {
        spokePool = _spokePool;
    }

    function handleV3AcrossMessage(address token, uint256 amount, address, bytes memory message) external override {
        if (msg.sender != spokePool) revert NotSpokePool();

        _settle(token, amount, message);
    }

    function _settle(address token, uint256 amount, bytes memory message) internal virtual;
}
