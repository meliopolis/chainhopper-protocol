// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
        try this.settle(token, amount, message) {
            // do nothing;
        }
        catch {
            // in case of error, return the amount to the recipient
            IERC20(token).transfer(_getRecipient(message), amount);
        }
    }
}
