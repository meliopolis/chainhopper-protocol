// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMessageHandler as IAcrossMessageHandler} from "@across/interfaces/SpokePoolMessageHandler.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IAcrossSettler} from "../interfaces/IAcrossSettler.sol";
import {MigrationModes} from "../types/MigrationMode.sol";
import {Settler} from "./Settler.sol";

abstract contract AcrossSettler is IAcrossSettler, IAcrossMessageHandler, Settler {
    using SafeERC20 for IERC20;

    address private immutable spokePool;

    constructor(address _spokePool) {
        spokePool = _spokePool;
    }

    function handleV3AcrossMessage(address token, uint256 amount, address, bytes memory message) external {
        if (msg.sender != spokePool) revert NotSpokePool();

        try this.settle(token, amount, message) {}
        catch {
            BaseSettlementParams memory baseParams = abi.decode(message, (BaseSettlementParams));

            // refund this and partially settled token if settlement fails
            IERC20(token).safeTransfer(baseParams.recipient, amount);
            if (baseParams.migrationId.mode() == MigrationModes.DUAL) {
                _refund(baseParams.migrationId, false);
            }
        }
    }
}
