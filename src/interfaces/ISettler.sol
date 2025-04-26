// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MigrationId} from "../types/MigrationId.sol";
import {MigrationMode} from "../types/MigrationMode.sol";

/// @title ISettler
/// @notice Interface for the Settler contract
interface ISettler {
    /// @notice Error thrown when the caller is not self
    error NotSelf();
    /// @notice Error thrown when the recipient is not the expected recipient
    error NotRecipient();
    /// @notice Error thrown when the tokens are the same between two halves of a dual migration
    error SameToken();
    /// @notice Error thrown when the data mismatches between two halves of a dual migration
    error MismatchingData();
    /// @notice Error thrown when the amount is missing
    error MissingAmount(address token);
    /// @notice Error thrown when the mode is unsupported
    error UnsupportedMode(MigrationMode mode);
    /// @notice Error thrown when the native token transfer fails
    error NativeTokenTransferFailed(address recipient, uint256 amount);
    /// @notice Error thrown when total fee exceeds the maximum allowed fee
    error MaxFeeExceeded(uint16 protocolShareBps, uint16 senderShareBps);

    /// @notice Event emitted when a settlement is completed
    event Settlement(MigrationId indexed migrationId, address indexed recipient, uint256 positionId);
    /// @notice Event emitted when fees are collected
    event FeePayment(MigrationId indexed migrationId, address indexed token, uint256 protocolFee, uint256 senderFee);
    /// @notice Event emitted when a refund is issued
    event Refund(MigrationId indexed migrationId, address indexed recipient, address indexed token, uint256 amount);

    /// @notice Struct for settlement parameters
    /// @param recipient The recipient of the settlement
    /// @param senderShareBps The sender share of the fees in bps
    /// @param senderFeeRecipient The recipient of the sender fees
    /// @param mintParams The mint params
    struct SettlementParams {
        address recipient;
        uint16 senderShareBps;
        address senderFeeRecipient;
        bytes mintParams;
    }

    /// @notice Function to settle a migration
    /// @dev This function is only callable by the contract itself
    /// @param token The token received by the contract
    /// @param amount The amount received by the contract
    /// @param data The data encoding the migration id and settlement params
    /// @return migrationId The migration id
    /// @return recipient The recipient of the settlement
    function selfSettle(address token, uint256 amount, bytes memory data) external returns (MigrationId, address);

    /// @notice Function to withdraw a migration
    /// @dev this is needed in case one half of a dual migration is received and other half fails
    /// @param migrationId The migration id
    function withdraw(MigrationId migrationId) external;
}
