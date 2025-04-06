// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MigrationId} from "../types/MigrationId.sol";
import {MigrationMode} from "../types/MigrationMode.sol";

interface ISettler {
    error NotSelf();
    error NotRecipient();
    error MismatchingData();
    error MissingAmount(address token);
    error UnsupportedMode(MigrationMode mode);
    error NativeTokenTransferFailed(address recipient, uint256 amount);
    error MaxFeeExceeded(uint16 protocolShareBps, uint16 senderShareBps);

    event Settlement(MigrationId indexed migrationId, address indexed recipient, uint256 positionId);
    event FeePayment(MigrationId indexed migrationId, address indexed token, uint256 protocolFee, uint256 senderFee);
    event Refund(MigrationId indexed migrationId, address indexed recipient, address indexed token, uint256 amount);

    struct SettlementParams {
        address recipient;
        uint16 senderShareBps;
        address senderFeeRecipient;
        bytes mintParams;
    }

    function selfSettle(address token, uint256 amount, bytes memory data) external returns (MigrationId, address);
    function withdraw(MigrationId migrationId) external;
}
