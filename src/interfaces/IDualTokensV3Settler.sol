// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IDualTokensV3Settler {
    event Settle(
        bytes32 indexed migrationId,
        address indexed recipient,
        uint256 indexed positionId,
        uint128 liquidity,
        uint256 amountReceived0,
        uint256 amountReceived1,
        uint256 amountRefunded0,
        uint256 amountRefunded1
    );

    event Escape(bytes32 indexed migrationId, address indexed recipient, address token, uint256 amount);

    struct SettlementParams {
        bytes32 migrationId;
        address recipient;
        // pool
        address token0;
        address token1;
        uint24 fee;
        // position params
        int24 tickLower;
        int24 tickUpper;
    }

    function escape(bytes32 migrationId) external;
}
