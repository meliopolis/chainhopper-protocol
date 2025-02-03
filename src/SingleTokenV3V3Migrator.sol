// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC721Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "./interfaces/external/ISwapRouter.sol";
import {INonfungiblePositionManager} from "./interfaces/external/INonfungiblePositionManager.sol";
import {V3SpokePoolInterface} from "./interfaces/external/ISpokePool.sol";
import {ISingleTokenV3V3Migrator} from "./interfaces/ISingleTokenV3V3Migrator.sol";

contract SingleTokenV3V3Migrator is ISingleTokenV3V3Migrator {
    address public immutable nonfungiblePositionManager;
    address public immutable baseToken; // the token that will be used to send the message to the bridge
    address public immutable swapRouter;
    V3SpokePoolInterface public immutable spokePool;

    /**
     *
     *  Functions  *
     *
     */
    constructor(address _nonfungiblePositionManager, address _baseToken, address _swapRouter, address _spokePool) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        baseToken = _baseToken;
        swapRouter = _swapRouter;
        spokePool = V3SpokePoolInterface(_spokePool);
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data)
        external
        virtual
        override
        returns (
            // nonReentrant // is this needed?
            bytes4
        )
    {
        MigrationParams memory migrationParams = abi.decode(data, (MigrationParams));

        _migratePosition(from, tokenId, migrationParams);
        return this.onERC721Received.selector;
    }

    function _migratePosition(address from, uint256 tokenId, MigrationParams memory migrationParams) internal {
        if (msg.sender != nonfungiblePositionManager) revert SenderIsNotNFTPositionManager();

        INonfungiblePositionManager nftManager = INonfungiblePositionManager(nonfungiblePositionManager);

        // 1. get the tokens in the position and verify liquidity > 0
        (,, address token0, address token1, uint24 fee,,, uint128 liquidity,,,,) = nftManager.positions(tokenId);
        if (liquidity == 0) revert LiquidityIsZero();

        // For now, we only support positions with baseToken as one of the tokens
        if (token0 != baseToken && token1 != baseToken) revert NoBaseTokenFound();

        // 2. decrease liquidity
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        nftManager.decreaseLiquidity(decreaseLiquidityParams);

        // 3. collect fees
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        // this will collect both tokens from decreaseLiquidity and any accumulated fees
        (uint256 amount0Collected, uint256 amount1Collected) = nftManager.collect(collectParams);

        // 4. burn the position
        nftManager.burn(tokenId); // todo: check if this is needed

        // 5. swap one token for baseToken
        uint256 amountOut = 0;
        uint256 amountBaseTokenBeforeTrades = IERC20(baseToken).balanceOf(address(this));
        uint256 amountIn = 0;
        address tokenIn;
        if (token0 == baseToken && amount1Collected > 0) {
            tokenIn = token1;
            amountIn = amount1Collected;
        } else if (token1 == baseToken && amount0Collected > 0) {
            tokenIn = token0;
            amountIn = amount0Collected;
        }

        if (amountIn > 0) {
            IERC20(tokenIn).approve(swapRouter, amountIn);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: baseToken,
                fee: fee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        }

        // 6. send the baseToken to the bridge with LP position info
        uint256 amountBaseToken = amountBaseTokenBeforeTrades + amountOut;

        uint32 fillDeadline = uint32(block.timestamp + migrationParams.fillDeadlineBuffer);

        // approve spokPool to transfer baseToken
        // this is no longer accurate due to refunds that can be accumulated
        IERC20(baseToken).approve(address(spokePool), amountBaseToken);
        // send ETH to bridge with message
        uint256 minOutputAmount = amountBaseToken - migrationParams.maxFees;
        spokePool.depositV3(
            from, // depositor
            migrationParams.recipient, // recipient; todo should this be stored in the contract for security reasons?
            baseToken, // inputToken
            migrationParams.outputToken, // outputToken
            amountBaseToken, // inputAmount
            minOutputAmount,
            migrationParams.destinationChainId,
            migrationParams.exclusiveRelayer,
            migrationParams.quoteTimestamp,
            fillDeadline,
            migrationParams.exclusivityDeadline,
            migrationParams.settlementParams // message
        );
    }
}
