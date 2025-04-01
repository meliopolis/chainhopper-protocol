// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MigrationId} from "../types/MigrationId.sol";

interface ISettler {
    error NotSelf();
    error NotRecipient();
    error TokenAmountMissing(address token);
    error InvalidSenderFeeBps(uint16 senderFeeBps);
    error SettlementDataMismatch();
    error MaxFeeExceeded(uint16 protocolShareBps, uint16 senderFeeBps);
    error NativeAssetTransferFailed(address to, uint256 amount);

    event Migrated(MigrationId indexed migrationId, address indexed recipient, address indexed token, uint256 amount);
    event Settlement(MigrationId indexed migrationId, address indexed recipient, uint256 positionId);
    event FeePayment(MigrationId indexed migrationId, address indexed token, uint256 protocolFee, uint256 senderFee);
    event Refund(MigrationId indexed migrationId, address indexed recipient, address indexed token, uint256 amount);

    struct SettlementParams {
        address recipient;
        uint16 senderFeeBps;
        address senderFeeRecipient;
        bytes mintParams;
    }

    function settle(address token, uint256 amount, bytes memory data) external;
    function withdraw(MigrationId migrationId) external;
}
