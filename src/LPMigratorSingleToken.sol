// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/external/ISwapRouter.sol";
import "./interfaces/external/INonfungiblePositionManager.sol";
import "./interfaces/external/ISpokePool.sol";
import "./interfaces/ILPMigrator.sol";
import {console} from "forge-std/Script.sol";

contract LPMigratorSingleToken is ILPMigrator {
    mapping(address => bool) public supportedTokens;
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
        console.log("starting onERC721Received");

        (
            address recipient,
            uint32 fillDeadlineBuffer,
            uint256 feePercentage,
            address exclusiveRelayer,
            uint256 destinationChainId,
            bytes memory mintParams
        ) = abi.decode(data, (address, uint32, uint256, address, uint256, bytes));

        console.log("decoded migrationParams");

        MigrationParams memory migrationParams = MigrationParams({
            recipient: recipient,
            fillDeadlineBuffer: fillDeadlineBuffer,
            feePercentage: feePercentage,
            exclusiveRelayer: exclusiveRelayer,
            destinationChainId: destinationChainId,
            mintParams: mintParams
        });

        console.log("calling _migratePosition");
        _migratePosition(from, tokenId, migrationParams);
        console.log("returned from _migratePosition");
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
        uint256 amountBaseToken = IERC20(baseToken).balanceOf(address(this));
        require(amountBaseToken >= amountBaseTokenBeforeTrades + amountOut, "baseToken balance mismatch");

        uint32 quoteTimestamp = uint32(block.timestamp);
        // (
        //     address recipient,
        //     uint32 fillDeadlineBuffer,
        //     uint256 feePercentage,
        //     address exclusiveRelayer,
        //     uint256 destinationChainId,
        //     bytes memory mintParams
        // ) = abi.decode(data, (address, uint32, uint256, address, uint256, bytes));

        uint32 fillDeadline = uint32(block.timestamp + migrationParams.fillDeadlineBuffer);
        uint256 minOutputAmount = amountBaseToken * (10000 - migrationParams.feePercentage) / 10000;

        // approve spokPool to transfer baseToken
        IERC20(baseToken).approve(address(spokePool), amountBaseToken);
        console.log("block.timestamp", block.timestamp);
        // send ETH to bridge with message
        spokePool.depositV3(
            from, // depositor
            migrationParams.recipient, // recipient; todo should this be stored in the contract for security reasons?
            baseToken, // inputToken
            0x0000000000000000000000000000000000000000, // outputToken; resolved automatically
            amountBaseToken, // inputAmount
            minOutputAmount,
            migrationParams.destinationChainId,
            migrationParams.exclusiveRelayer,
            quoteTimestamp,
            fillDeadline,
            uint32(block.timestamp - 1000), // todo: is this correct? setting exclusivityDeadline and fillDeadline to the same value
            migrationParams.mintParams // message
        );
    }
}
