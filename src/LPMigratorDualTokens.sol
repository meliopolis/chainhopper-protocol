// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INonfungiblePositionManager} from "./interfaces/external/INonfungiblePositionManager.sol";
import {V3SpokePoolInterface} from "./interfaces/external/ISpokePool.sol";
import {ILPMigratorDualTokens} from "./interfaces/ILPMigratorDualTokens.sol";

contract LPMigratorDualTokens is ILPMigratorDualTokens {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    V3SpokePoolInterface public immutable spokePool;

    uint256 private migrationId;
    // origin token => destination chain => destination token
    mapping(address => mapping(uint256 => address)) private tokenMapping;

    constructor(address _nonfungiblePositionManager, address _spokePool) {
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        spokePool = V3SpokePoolInterface(_spokePool);
    }

    // invoked by replayer with signed permit for this contract to operate the LP position
    function migrateByPermit(LPMigrationOrder calldata order, NPMPermitParams calldata params) external {
        // permit this contract to operate the LP position
        nonfungiblePositionManager.permit(
            address(this), params.positionId, params.deadline, params.v, params.r, params.s
        );

        // TODO: needs to do order validation somehow, otherwise spoofable

        // get position info
        (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            nonfungiblePositionManager.positions(order.positionId);

        // burn all liquidity
        nonfungiblePositionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: order.positionId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // collect all tokens
        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: order.positionId,
                recipient: address(this), // TODO: direct transfer?
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // good hygiene
        nonfungiblePositionManager.burn(order.positionId);

        // collect bonds from relayer
        IERC20(token0).safeTransferFrom(msg.sender, address(this), order.bondAmount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), order.bondAmount1);

        // approve spokePool to pull tokens
        IERC20(token0).safeIncreaseAllowance(address(spokePool), amount0 + order.bondAmount0);
        IERC20(token1).safeIncreaseAllowance(address(spokePool), amount1 + order.bondAmount1);

        // values needed for deposits
        uint32 quoteTimestamp = uint32(block.timestamp);
        uint32 fillDeadline = uint32(block.timestamp + order.fillDeadlineBuffer);
        uint256 outputAmount0 = amount0 * (1e18 - order.feePercentage0) / 1e18;
        uint256 outputAmount1 = amount1 * (1e18 - order.feePercentage1) / 1e18;
        bytes memory message = abi.encode(
            LPMigrationMessage({
                migrationId: ++migrationId,
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0: outputAmount0,
                amount1: outputAmount1
            })
        );

        // deposit tokens to initiate Across Settlement
        spokePool.depositV3(
            order.depositor,
            order.recipient,
            token0,
            tokenMapping[token0][order.destinationChainId],
            amount0,
            outputAmount0,
            order.destinationChainId,
            order.exclusiveRelayer,
            quoteTimestamp,
            fillDeadline,
            fillDeadline, // exclusive all the way
            message
        );
        spokePool.depositV3(
            order.depositor,
            order.recipient,
            token1,
            tokenMapping[token1][order.destinationChainId],
            amount1,
            outputAmount1,
            order.destinationChainId,
            order.exclusiveRelayer,
            quoteTimestamp,
            fillDeadline,
            fillDeadline, // exclusive all the way
            message
        );
    }
}
