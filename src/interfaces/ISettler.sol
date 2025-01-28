// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISettler {
    error AtLeastOneAmountMustBeGreaterThanZero();
    error InsufficientBalance();

    function setProtocolFeeBps(uint24 _protocolFeeBps) external;
    function setProtocolFeeRecipient(address _protocolFeeRecipient) external;
    function setProtocolShareOfSenderFeeInPercent(uint8 _protocolShareOfSenderFeeInPercent) external;
    function settle(address token, uint256 amount, bytes memory message) external returns (uint256);
}
