// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";

contract ProtocolFees is Ownable2Step {
    error InvalidProtocolShareBps(uint16 protocolShareBps);
    error InvalidProtocolShareOfSenderFeePct(uint8 protocolShareOfSenderFeePct);
    error InvalidProtocolFeeRecipient(address protocolFeeRecipient);
    error MaxFeeExceeded(uint16 protocolShareBps, uint16 senderShareBps);

    event ProtocolShareBpsUpdated(uint16 protocolShareBps);
    event ProtocolShareOfSenderFeePctUpdated(uint8 protocolShareOfSenderFeePct);
    event ProtocolFeeRecipientUpdated(address protocolFeeRecipient);

    uint16 public constant MAX_SHARE_BPS = 200;
    uint16 public constant MAX_PROTOCOL_SHARE_BPS = 200;
    uint8 public constant MAX_PROTOCOL_SHARE_OF_SENDER_FEE_PCT = 50;

    uint16 public protocolShareBps;
    uint8 public protocolShareOfSenderFeePct;
    address public protocolFeeRecipient;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setProtocolShareBps(uint16 _protocolShareBps) external onlyOwner {
        if (_protocolShareBps > MAX_PROTOCOL_SHARE_BPS) revert InvalidProtocolShareBps(_protocolShareBps);

        protocolShareBps = _protocolShareBps;

        emit ProtocolShareBpsUpdated(_protocolShareBps);
    }

    function setProtocolShareOfSenderFeePct(uint8 _protocolShareOfSenderFeePct) external onlyOwner {
        if (_protocolShareOfSenderFeePct > MAX_PROTOCOL_SHARE_OF_SENDER_FEE_PCT) {
            revert InvalidProtocolShareOfSenderFeePct(_protocolShareOfSenderFeePct);
        }

        protocolShareOfSenderFeePct = _protocolShareOfSenderFeePct;

        emit ProtocolShareOfSenderFeePctUpdated(_protocolShareOfSenderFeePct);
    }

    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        if (_protocolFeeRecipient == address(0)) revert InvalidProtocolFeeRecipient(_protocolFeeRecipient);

        protocolFeeRecipient = _protocolFeeRecipient;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    function _calculateFees(uint256 amount, uint16 senderShareBps)
        internal
        view
        returns (uint256 protocolFee, uint256 senderFee)
    {
        if (protocolShareBps + senderShareBps > MAX_SHARE_BPS) revert MaxFeeExceeded(protocolShareBps, senderShareBps);

        protocolFee = (amount * protocolShareBps) / 10000;
        senderFee = (amount * senderShareBps) / 10000;

        if (protocolShareOfSenderFeePct > 0) {
            uint256 protocolFeeFromSenderFee = (senderFee * protocolShareOfSenderFeePct) / 100;
            protocolFee += protocolFeeFromSenderFee;
            senderFee -= protocolFeeFromSenderFee;
        }
    }
}
