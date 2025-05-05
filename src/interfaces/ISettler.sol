// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MigrationMode} from "../types/MigrationMode.sol";

/// @title ISettler
/// @notice Interface for the Settler contract
interface ISettler {
    /// @notice Error thrown when the caller is not self
    error NotSelf();
    /// @notice Error thrown when the recipient is not the expected recipient
    error NotRecipient();
    /// @notice Error thrown when the migration hash does not match with data
    error InvalidMigration();
    /// @notice Error thrown when the tokens are the same between two halves of a dual migration
    error SameToken();
    /// @notice Error thrown when the data mismatches between two halves of a dual migration
    error MismatchingData();
    /// @notice Error thrown when the amount is missing
    error MissingAmount(address token);
    /// @notice Error thrown when an unexpected token is received
    error UnexpectedToken(address token);
    /// @notice Error thrown when the mode is unsupported
    error UnsupportedMode(MigrationMode mode);
    /// @notice Error thrown when the amount received is less than min amount
    error AmountTooLow(address token, uint256 amount, uint256 amountMin);
    /// @notice Error thrown when the native token transfer fails
    error NativeTokenTransferFailed(address recipient, uint256 amount);
    /// @notice Error thrown when total fee exceeds the maximum allowed fee
    error MaxFeeExceeded(uint16 protocolShareBps, uint16 senderShareBps);

    /// @notice Event emitted when a settlement is completed
    event Settlement(bytes32 indexed migrationHash, address indexed recipient, uint256 positionId);
    /// @notice Event emitted when fees are collected
    event FeePayment(bytes32 indexed migrationHash, address indexed token, uint256 protocolFee, uint256 senderFee);
    /// @notice Event emitted when a refund is issued
    event Refund(bytes32 indexed migrationHash, address indexed recipient, address indexed token, uint256 amount);

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
    /// @param data The data encoding the migration hash and migration data
    /// @return migrationHash The migration hash
    /// @return recipient The recipient of the settlement
    function selfSettle(address token, uint256 amount, bytes memory data) external returns (bytes32, address);

    /// @notice Function to withdraw a migration
    /// @dev this is needed in case one half of a dual migration is received and other half fails
    /// @param migrationHash The migration hash
    function withdraw(bytes32 migrationHash) external;
}
