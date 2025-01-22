// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/external/ISwapRouter.sol";
import "./interfaces/external/INonfungiblePositionManager.sol";
import "./interfaces/external/ISpokePool.sol";
import "./interfaces/ILPMigrator.sol";

contract LPMigratorSingleToken is ILPMigrator {
    address public immutable nonfungiblePositionManager;
    address public immutable baseToken; // the token that will be used to send the message to the bridge
    address public immutable swapRouter;
    V3SpokePoolInterface public immutable spokePool;
    mapping(address => uint256) public refundAmount;

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
        (
            address recipient,
            uint32 quoteTimestamp,
            uint32 fillDeadlineBuffer,
            uint256 maxFees,
            address outputToken,
            address exclusiveRelayer,
            uint32 exclusivityDeadline,
            uint256 destinationChainId,
            bytes memory mintParams
        ) = abi.decode(data, (address, uint32, uint32, uint256, address, address, uint32, uint256, bytes));

        MigrationParams memory migrationParams = MigrationParams({
            recipient: recipient,
            quoteTimestamp: quoteTimestamp,
            fillDeadlineBuffer: fillDeadlineBuffer,
            exclusivityDeadline: exclusivityDeadline,
            maxFees: maxFees,
            outputToken: outputToken,
            exclusiveRelayer: exclusiveRelayer,
            destinationChainId: destinationChainId,
            mintParams: mintParams
        });

        _migratePosition(from, tokenId, migrationParams);
        return this.onERC721Received.selector;
    }

    function _migratePosition(address from, uint256 tokenId, MigrationParams memory migrationParams) internal {
        INonfungiblePositionManager nftManager = INonfungiblePositionManager(nonfungiblePositionManager);
        require(msg.sender == nonfungiblePositionManager, "Only nonfungiblePositionManager can call this function");
        // confirm that this tokenId is now owned by this contract
        require(nftManager.ownerOf(tokenId) == address(this), "Token not owned by this contract");

        // 1. get the tokens in the position and verify liquidity > 0
        (,, address token0, address token1,,,, uint128 liquidity,,,,) = nftManager.positions(tokenId);
        require(liquidity > 0, "Liquidity is 0");

        // 2. decrease liquidity
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0, // todo: might need to account for slippage
            amount1Min: 0, // todo: might need to account for slippage
            deadline: block.timestamp + 60 // 1 min (might be too long)
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

        uint256 amountToken0 = IERC20(token0).balanceOf(address(this));
        uint256 amountToken1 = IERC20(token1).balanceOf(address(this));

        // verify that the tokens collected match the balance in the contract
        // needs to be >=, otherwise someone could bork the contract by sending it some WETH
        require(amount0Collected >= amountToken0, "Incorrect amount of token0 collected");
        require(amount1Collected >= amountToken1, "Incorrect amount of token1 collected");

        uint256 amountOut = 0;
        uint256 amountBaseTokenBeforeTrades = IERC20(baseToken).balanceOf(address(this));

        // 5. swap one token for baseToken
        // Note: one of the tokens must be a baseToken; makes things simpler on the destination chain
        if (token0 != baseToken) {
            // swap token0 for baseToken
            IERC20(token0).approve(swapRouter, amount0Collected);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: baseToken,
                fee: 3000, // todo: make dynamic
                recipient: address(this),
                // deadline: block.timestamp + 60, // 1 min (might be too long)
                amountIn: amount0Collected,
                amountOutMinimum: 0, // todo: add slippage
                sqrtPriceLimitX96: 0
            });
            amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        } else if (token1 != baseToken) {
            // swap token1 for baseToken
            IERC20(token1).approve(swapRouter, amount1Collected);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: token1,
                tokenOut: baseToken,
                fee: 3000, // todo: make dynamic
                recipient: address(this),
                amountIn: amount1Collected,
                amountOutMinimum: 0, // todo: add slippage
                sqrtPriceLimitX96: 0
            });
            amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        }

        // 4. send the baseToken to the bridge with LP position info
        // this is no longer accurate due to refunds that can be accumulated
        // instead, need to calculate the exact amount of baseToken from the trade
        uint256 amountBaseToken = IERC20(baseToken).balanceOf(address(this));
        require(amountBaseToken >= amountBaseTokenBeforeTrades + amountOut, "baseToken balance mismatch");

        uint32 fillDeadline = uint32(block.timestamp + migrationParams.fillDeadlineBuffer);
        // uint256 minOutputAmount = amountBaseToken * (10000 - migrationParams.feePercentage) / 10000;

        // approve spokPool to transfer baseToken
        // this is no longer accurate due to refunds that can be accumulated
        IERC20(baseToken).approve(address(spokePool), amountBaseToken);
        refundAmount[from] = amountBaseToken;
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
            migrationParams.mintParams // message
        );
    }
}
