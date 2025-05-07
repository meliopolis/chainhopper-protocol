// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";

/// @title ProtocolFees
/// @notice Contract for managing protocol fees
contract ProtocolFees is Ownable2Step {
    /// @notice Error thrown when the protocol share bps is invalid
    error InvalidProtocolShareBps(uint16 protocolShareBps);
    /// @notice Error thrown when the protocol share of sender fee pct is invalid
    error InvalidProtocolShareOfSenderFeePct(uint8 protocolShareOfSenderFeePct);
    /// @notice Error thrown when the protocol fee recipient is invalid
    error InvalidProtocolFeeRecipient(address protocolFeeRecipient);

    /// @notice Event emitted when the protocol share bps is updated
    event ProtocolShareBpsUpdated(uint16 protocolShareBps);
    /// @notice Event emitted when the protocol share of sender fee pct is updated
    event ProtocolShareOfSenderFeePctUpdated(uint8 protocolShareOfSenderFeePct);
    /// @notice Event emitted when the protocol fee recipient is updated
    event ProtocolFeeRecipientUpdated(address protocolFeeRecipient);

    /// @notice The maximum share bps
    uint16 public constant MAX_SHARE_BPS = 200;
    /// @notice The maximum protocol share bps
    uint16 public constant MAX_PROTOCOL_SHARE_BPS = 200;
    /// @notice The maximum protocol share of sender fee pct
    uint8 public constant MAX_PROTOCOL_SHARE_OF_SENDER_FEE_PCT = 50;

    /// @notice The protocol share bps
    uint16 public protocolShareBps;
    /// @notice The protocol share of sender fee pct
    uint8 public protocolShareOfSenderFeePct;
    /// @notice The protocol fee recipient
    address public protocolFeeRecipient;

    /// @notice Constructor for the ProtocolFees contract
    /// @param initialOwner The initial owner of the contract
    constructor(address initialOwner) Ownable(initialOwner) {
        protocolFeeRecipient = initialOwner;
    }

    /// @notice Function to set the protocol share bps
    /// @param _protocolShareBps The new protocol share bps
    /// @dev Only the owner can call this function
    function setProtocolShareBps(uint16 _protocolShareBps) external onlyOwner {
        if (_protocolShareBps > MAX_PROTOCOL_SHARE_BPS) revert InvalidProtocolShareBps(_protocolShareBps);

        protocolShareBps = _protocolShareBps;

        emit ProtocolShareBpsUpdated(_protocolShareBps);
    }

    /// @notice Function to set the protocol share of sender fee pct
    /// @param _protocolShareOfSenderFeePct The new protocol share of sender fee pct
    /// @dev Only the owner can call this function
    function setProtocolShareOfSenderFeePct(uint8 _protocolShareOfSenderFeePct) external onlyOwner {
        if (_protocolShareOfSenderFeePct > MAX_PROTOCOL_SHARE_OF_SENDER_FEE_PCT) {
            revert InvalidProtocolShareOfSenderFeePct(_protocolShareOfSenderFeePct);
        }

        protocolShareOfSenderFeePct = _protocolShareOfSenderFeePct;

        emit ProtocolShareOfSenderFeePctUpdated(_protocolShareOfSenderFeePct);
    }

    /// @notice Function to set the protocol fee recipient
    /// @param _protocolFeeRecipient The new protocol fee recipient
    /// @dev Only the owner can call this function
    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        if (_protocolFeeRecipient == address(0)) revert InvalidProtocolFeeRecipient(_protocolFeeRecipient);

        protocolFeeRecipient = _protocolFeeRecipient;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }
}
