// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAcrossV3SpokePoolMessageHandler} from "../interfaces/external/IAcrossV3.sol";
import {Settler} from "./Settler.sol";

abstract contract AcrossSettler is Settler, IAcrossV3SpokePoolMessageHandler {
    error NotSpokePool();
    error BridgedTokenMustBeUsedInPosition();
    error BridgedTokensMustBeDifferent();

    address private immutable spokePool;

    constructor(address _spokePool) {
        spokePool = _spokePool;
    }

    function handleV3AcrossMessage(address token, uint256 amount, address, bytes memory message) external override {
        if (msg.sender != spokePool) revert NotSpokePool();
        try this.settle(token, amount, message) {}
        catch {
            // if error, pass the amount directly to the recipient
            IERC20(token).transfer(_getRecipient(message), amount);
            // if there is a migrationId, refund any partial settlements as well
            (bytes32 migrationId) = abi.decode(message, (bytes32));
            if (migrationId != bytes32(0)) {
                _refund(migrationId);
            }
        }
    }
}
