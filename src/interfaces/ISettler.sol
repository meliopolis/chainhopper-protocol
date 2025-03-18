// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISettler {
    error NotSelf();
    error NotRecipient();
    error AmountCannotBeZero();
    error SettlementTokensCannotBeTheSame();
    error SettlementMessagesMismatch();

    event Refunded(bytes32 indexed migrationId, address indexed recipient, address token, uint256 amount);
    event PartiallySettled(bytes32 indexed migrationId, address indexed recipient, address token, uint256 amount);
    event FullySettled(
        bytes32 indexed migrationId,
        address indexed recipient,
        uint256 indexed positionId,
        address token0,
        address token1,
        uint128 liquidity
    );

    struct BaseSettlementParams {
        bytes32 migrationId;
        address recipient;
        uint24 senderFeeBps;
        address senderFeeRecipient;
    }

    function withdraw(bytes32 migrationId) external;
    function settle(address token, uint256 amount, bytes memory data) external;
}
