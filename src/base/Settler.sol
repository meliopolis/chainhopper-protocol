// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ISettler} from "../interfaces/ISettler.sol";

abstract contract Settler is ISettler, Ownable2Step {
    uint24 public protocolFeeBps; // out of 10000; ex: 10bps is 10
    address public protocolFeeRecipient;
    uint8 public protocolShareOfSenderFeeInPercent; // 1%, 2%, etc.; ex: 10% is 10

    constructor(uint24 _protocolFeeBps, address _protocolFeeRecipient, uint8 _protocolShareOfSenderFeeInPercent)
        Ownable(msg.sender)
    {
        protocolFeeBps = _protocolFeeBps;
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolShareOfSenderFeeInPercent = _protocolShareOfSenderFeeInPercent;
    }

    function setProtocolFeeBps(uint24 _protocolFeeBps) external onlyOwner {
        protocolFeeBps = _protocolFeeBps;
    }

    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    function setProtocolShareOfSenderFeeInPercent(uint8 _protocolShareOfSenderFeeInPercent) external onlyOwner {
        protocolShareOfSenderFeeInPercent = _protocolShareOfSenderFeeInPercent;
    }

    // settle handles fees before handing off to _settle()
    function settle(address token, uint256 amount, bytes memory message) external returns (uint256) {
        uint256 tokenId;
        (bytes32 migrationId) = abi.decode(message, (bytes32));
        if (migrationId == bytes32(0)) {
            (uint256 senderFeeAmount, uint256 protocolFeeAmount) = _calculateFees(amount, message);
            // call _settle to fulfill the migration
            tokenId = _settle(token, amount - senderFeeAmount - protocolFeeAmount, message);
            // transfer fees
            if (protocolFeeAmount > 0) {
                IERC20(token).transfer(protocolFeeRecipient, protocolFeeAmount);
            }
            if (senderFeeAmount > 0) {
                (, address senderFeeRecipient) = _getSenderFees(message);
                IERC20(token).transfer(senderFeeRecipient, senderFeeAmount);
            }
        } else {
            // if migrationId, then leave the fees for the contract that implements _settle()
            tokenId = _settle(token, amount, message);
        }
        return tokenId;
    }

    function _calculateFees(uint256 amount, bytes memory message) internal view returns (uint256, uint256) {
        (uint24 senderFeeBps,) = _getSenderFees(message);
        // todo check if senderFeeBps and senderFeeRecipient are valid
        uint256 senderFeeAmount = (amount * senderFeeBps) / 10000;
        uint256 protocolFeeAmount = (amount * protocolFeeBps) / 10000;
        uint256 protocolShareOfSenderFeeAmount = (senderFeeAmount * protocolShareOfSenderFeeInPercent) / 100;
        uint256 totalProtocolFeeAmount = protocolFeeAmount + protocolShareOfSenderFeeAmount;
        uint256 netSenderFeeAmount = senderFeeAmount - protocolShareOfSenderFeeAmount;
        return (netSenderFeeAmount, totalProtocolFeeAmount);
    }

    function _getSenderFees(bytes memory message) internal view virtual returns (uint24, address);
    function _getRecipient(bytes memory message) internal view virtual returns (address);
    function _refund(bytes32 migrationId) internal virtual;

    // this function contains the logic for the settlement
    function _settle(address token, uint256 amount, bytes memory message) internal virtual returns (uint256);
}
