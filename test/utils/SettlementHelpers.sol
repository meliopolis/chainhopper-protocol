// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IAerodromeSettler} from "../../src/interfaces/IAerodromeSettler.sol";
import {IUniswapV3Settler} from "../../src/interfaces/IUniswapV3Settler.sol";
import {IUniswapV4Settler} from "../../src/interfaces/IUniswapV4Settler.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {MigrationData} from "../../src/types/MigrationData.sol";
import {MigrationMode, MigrationModes} from "../../src/types/MigrationMode.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";

library SettlementHelpers {
    address private constant SENDER_FEE_RECIPIENT = address(0x737383);

    enum Range {
        InRange,
        BelowTick,
        AboveTick
    }

    function generateV3SettlementParams(
        address user,
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint24 swapAmountInMilliBps,
        uint256 amount0Min,
        uint256 amount1Min,
        uint16 senderShareBps,
        address senderFeeRecipient
    ) public pure returns (ISettler.SettlementParams memory) {
        ISettler.SettlementParams memory settlementParams = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: senderShareBps,
            senderFeeRecipient: senderFeeRecipient,
            mintParams: abi.encode(
                IUniswapV3Settler.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: fee,
                    sqrtPriceX96: sqrtPriceX96,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    swapAmountInMilliBps: swapAmountInMilliBps,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min
                })
            )
        });
        return settlementParams;
    }

    function generateV3SettlementParamsUsingCurrentTick(
        address user,
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96,
        int24 currentTick,
        Range range,
        uint256 amount0Min,
        uint256 amount1Min,
        bool isToken0BaseToken,
        uint16 senderShareBps
    ) public pure returns (ISettler.SettlementParams memory) {
        int24 tickLower;
        int24 tickUpper;
        uint24 swapAmountInMilliBps = 0;

        if (range == Range.InRange) {
            tickLower = (currentTick - 6932 * 5) / 10000 * 10000;
            tickUpper = (currentTick + 4055 * 5) / 10000 * 10000;
            swapAmountInMilliBps = isToken0BaseToken ? 5_500_000 : 4_500_000; // intentionally set high, so both tokens are leftover
        } else if (range == Range.BelowTick) {
            tickLower = (currentTick - 60000) / 10000 * 10000;
            tickUpper = (currentTick - 30000) / 10000 * 10000;
            swapAmountInMilliBps = isToken0BaseToken ? 10_000_000 : 0; // TODO review
        } else {
            tickLower = (currentTick + 30000) / 10000 * 10000;
            tickUpper = (currentTick + 60000) / 10000 * 10000;
            swapAmountInMilliBps = isToken0BaseToken ? 0 : 10_000_000; // TODO review
        }
        return generateV3SettlementParams(
            user,
            token0,
            token1,
            fee,
            sqrtPriceX96,
            tickLower,
            tickUpper,
            swapAmountInMilliBps,
            amount0Min,
            amount1Min,
            senderShareBps,
            SENDER_FEE_RECIPIENT
        );
    }

    function generateV4SettlementParams(
        address user,
        PoolKey memory poolKey,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint24 swapAmountInMilliBps,
        uint256 amount0Min,
        uint256 amount1Min,
        uint16 senderShareBps,
        address senderFeeRecipient
    ) public pure returns (ISettler.SettlementParams memory) {
        ISettler.SettlementParams memory settlementParams = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: senderShareBps,
            senderFeeRecipient: senderFeeRecipient,
            mintParams: abi.encode(
                IUniswapV4Settler.MintParams({
                    token0: Currency.unwrap(poolKey.currency0),
                    token1: Currency.unwrap(poolKey.currency1),
                    fee: poolKey.fee,
                    tickSpacing: poolKey.tickSpacing,
                    hooks: address(poolKey.hooks),
                    sqrtPriceX96: sqrtPriceX96,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    swapAmountInMilliBps: swapAmountInMilliBps,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min
                })
            )
        });
        return settlementParams;
    }

    function generateV4SettlementParamsUsingCurrentTick(
        address user,
        PoolKey memory poolKey,
        uint160 sqrtPriceX96,
        int24 currentTick,
        Range range,
        uint256 amount0Min,
        uint256 amount1Min,
        bool isToken0BaseToken,
        uint16 senderShareBps
    ) public pure returns (ISettler.SettlementParams memory) {
        int24 tickLower;
        int24 tickUpper;
        uint24 swapAmountInMilliBps = 0;

        if (range == Range.InRange) {
            tickLower = (currentTick - 6932 * 5) / 10000 * 10000;
            tickUpper = (currentTick + 4055 * 5) / 10000 * 10000;
            swapAmountInMilliBps = isToken0BaseToken ? 5_500_000 : 4_500_000; // intentionally set high, so both tokens are leftover
        } else if (range == Range.BelowTick) {
            tickLower = (currentTick - 60000) / 10000 * 10000;
            tickUpper = (currentTick - 30000) / 10000 * 10000;
            swapAmountInMilliBps = isToken0BaseToken ? 10_000_000 : 0; // TODO review
        } else {
            tickLower = (currentTick + 30000) / 10000 * 10000;
            tickUpper = (currentTick + 60000) / 10000 * 10000;
            swapAmountInMilliBps = isToken0BaseToken ? 0 : 10_000_000; // TODO review
        }
        return generateV4SettlementParams(
            user,
            poolKey,
            sqrtPriceX96,
            tickLower,
            tickUpper,
            swapAmountInMilliBps,
            amount0Min,
            amount1Min,
            senderShareBps,
            SENDER_FEE_RECIPIENT
        );
    }

    function generateAerodromeSettlementParams(
        address user,
        address token0,
        address token1,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint24 swapAmountInMilliBps,
        uint256 amount0Min,
        uint256 amount1Min,
        uint16 senderShareBps,
        address senderFeeRecipient
    ) public pure returns (ISettler.SettlementParams memory) {
        ISettler.SettlementParams memory settlementParams = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: senderShareBps,
            senderFeeRecipient: senderFeeRecipient,
            mintParams: abi.encode(
                IAerodromeSettler.MintParams({
                    token0: token0,
                    token1: token1,
                    tickSpacing: tickSpacing,
                    sqrtPriceX96: sqrtPriceX96,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    swapAmountInMilliBps: swapAmountInMilliBps,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min
                })
            )
        });
        return settlementParams;
    }

    function generateAerodromeSettlementParamsUsingCurrentTick(
        address user,
        address token0,
        address token1,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        int24 currentTick,
        Range range,
        uint256 amount0Min,
        uint256 amount1Min,
        bool isToken0BaseToken,
        uint16 senderShareBps
    ) public pure returns (ISettler.SettlementParams memory) {
        int24 tickLower;
        int24 tickUpper;
        uint24 swapAmountInMilliBps = 0;

        if (range == Range.InRange) {
            tickLower = (currentTick - 6932 * 5) / 10000 * 10000;
            tickUpper = (currentTick + 4055 * 5) / 10000 * 10000;
            swapAmountInMilliBps = isToken0BaseToken ? 5_500_000 : 4_500_000; // intentionally set high, so both tokens are leftover
        } else if (range == Range.BelowTick) {
            tickLower = (currentTick - 60000) / 10000 * 10000;
            tickUpper = (currentTick - 30000) / 10000 * 10000;
            swapAmountInMilliBps = isToken0BaseToken ? 10_000_000 : 0; // TODO review
        } else {
            tickLower = (currentTick + 30000) / 10000 * 10000;
            tickUpper = (currentTick + 60000) / 10000 * 10000;
            swapAmountInMilliBps = isToken0BaseToken ? 0 : 10_000_000; // TODO review
        }
        return generateAerodromeSettlementParams(
            user,
            token0,
            token1,
            tickSpacing,
            sqrtPriceX96,
            tickLower,
            tickUpper,
            swapAmountInMilliBps,
            amount0Min,
            amount1Min,
            senderShareBps,
            SENDER_FEE_RECIPIENT
        );
    }

    function generateSettlerData(
        ISettler.SettlementParams memory settlementParams,
        MigrationMode mode,
        bytes memory routesData
    ) public view returns (bytes32 migrationId, bytes memory data) {
        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(1),
            nonce: 1,
            mode: mode,
            routesData: routesData,
            settlementData: abi.encode(settlementParams)
        });
        migrationId = migrationData.toId();
        return (migrationId, abi.encode(migrationId, migrationData));
    }

    function findFeePaymentEvent(Vm.Log[] memory logs) public view returns (Vm.Log memory) {
        bytes32 topic0 = keccak256("FeePayment(bytes32,address,uint256,uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            // skip events emitted by this contract
            if (logs[i].topics[0] == topic0 && logs[i].emitter != address(this)) {
                return logs[i];
            }
        }
        revert();
    }

    function findFeePaymentEvents(Vm.Log[] memory logs) public view returns (Vm.Log[] memory) {
        bytes32 topic0 = keccak256("FeePayment(bytes32,address,uint256,uint256)");
        Vm.Log[] memory feePaymentEvents = new Vm.Log[](2);
        uint256 feePaymentEventsIndex = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == topic0 && logs[i].emitter != address(this)) {
                feePaymentEvents[feePaymentEventsIndex] = logs[i];
                feePaymentEventsIndex++;
            }
        }
        return feePaymentEvents;
    }

    function parseFeePaymentEvent(bytes memory data) public pure returns (uint256) {
        (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));
        return amount0 + amount1;
    }

    function findTransferToUserEvents(Vm.Log[] memory logs, address user) public view returns (Vm.Log[] memory) {
        bytes32 topic0 = keccak256("Transfer(address,address,uint256)");

        // First count the number of matching events
        uint256 matchingEventsCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] == topic0 && logs[i].emitter != address(this)
                    && logs[i].topics[2] == bytes32(uint256(uint160(user)))
                    && logs[i].topics[1] != bytes32(uint256(uint160(address(0))))
            ) {
                matchingEventsCount++;
            }
        }

        // Create array of exact size needed
        Vm.Log[] memory transferEvents = new Vm.Log[](matchingEventsCount);
        uint256 transferEventsIndex = 0;

        // Fill the array with matching events
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] == topic0 && logs[i].emitter != address(this)
                    && logs[i].topics[2] == bytes32(uint256(uint160(user)))
                    && logs[i].topics[1] != bytes32(uint256(uint160(address(0))))
            ) {
                transferEvents[transferEventsIndex] = logs[i];
                transferEventsIndex++;
            }
        }
        return transferEvents;
    }

    function parseTransferToUserEvent(Vm.Log memory log) public pure returns (uint256) {
        (uint256 amount) = abi.decode(log.data, (uint256));
        return amount;
    }
}
