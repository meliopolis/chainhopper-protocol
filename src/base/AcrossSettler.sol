// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMessageHandler as IAcrossMessageHandler} from "@across/interfaces/SpokePoolMessageHandler.sol";
import {IAcrossSettler} from "../interfaces/IAcrossSettler.sol";
import {Settler} from "./Settler.sol";

abstract contract AcrossSettler is IAcrossSettler, IAcrossMessageHandler, Settler {
    address private immutable spokePool;

    constructor(address _spokePool) {
        spokePool = _spokePool;
    }

    function handleV3AcrossMessage(address token, uint256 amount, address, bytes memory message) external {
        if (msg.sender != spokePool) revert NotSpokePool();

        try this.settle(token, amount, message) {}
        catch {
            BaseSettlementParams memory baseParams = abi.decode(message, (BaseSettlementParams));

            _transfer(token, amount, baseParams.recipient);

            if (baseParams.migrationId != bytes32(0)) {
                _refund(baseParams.migrationId, false);
            }
        }
    }
}
