// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ISettler} from "../interfaces/ISettler.sol";
import {Ownable2Step, Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

abstract contract Settler is ISettler, Ownable2Step {
    uint24 public protocolFeeBps; // out of 10000
    address public protocolFeeRecipient;
    uint8 public senderFeeShareInPercent; // 1%, 2%, etc.

    constructor(uint24 _protocolFeeBps, address _protocolFeeRecipient, uint8 _senderFeeShareInPercent)
        Ownable(msg.sender)
    {
        protocolFeeBps = _protocolFeeBps;
        protocolFeeRecipient = _protocolFeeRecipient;
        senderFeeShareInPercent = _senderFeeShareInPercent;
    }

    function setProtocolFeeBps(uint24 _protocolFeeBps) external onlyOwner {
        protocolFeeBps = _protocolFeeBps;
    }

    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    function setSenderFeeShareInPercent(uint8 _senderFeeShareInPercent) external onlyOwner {
        senderFeeShareInPercent = _senderFeeShareInPercent;
    }

    function settle(address token, uint256 amount, bytes memory message) external override returns (uint256) {
        (uint24 senderFeeBps, address senderFeeRecipient) = _getSenderFees(message);
        uint256 senderFeeAmount = (amount * senderFeeBps) / 10000;
        uint256 protocolFeeAmount = (amount * protocolFeeBps) / 10000;
        uint256 amountToMigrate = amount - senderFeeAmount - protocolFeeAmount;

        // call _settle to fulfill the migration
        uint256 tokenId = _settle(token, amountToMigrate, message);

        // transfer fees
        uint256 protocolShareOfSenderFee = (senderFeeAmount * senderFeeShareInPercent) / 100;
        uint256 totalProtocolFee = protocolFeeAmount + protocolShareOfSenderFee;
        uint256 netSenderFee = senderFeeAmount - protocolShareOfSenderFee;
        IERC20(token).transfer(protocolFeeRecipient, totalProtocolFee);
        IERC20(token).transfer(senderFeeRecipient, netSenderFee);
        // todo emit event
        return tokenId;
    }

    function _getSenderFees(bytes memory message) internal view virtual returns (uint24, address);

    function _settle(address token, uint256 amount, bytes memory message) internal virtual returns (uint256);
}
