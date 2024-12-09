// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import {console} from "forge-std/Script.sol"; // todo: remove

contract LPMigratorSingleToken is IERC721Receiver, ReentrancyGuard, Pausable {
    mapping(address => bool) public supportedTokens;
    address public nonfungiblePositionManager;
    address public baseToken; // the token that will be used to send the message to the bridge
    address public swapRouter;
    address public spokePool;
    /**
     *
     *  Modifiers  *
     *
     */

    modifier unpaused() {
        require(!paused(), "Scythe paused");
        _;
    }

    /**
     *
     *  Functions  *
     *
     */
    constructor(address _nonfungiblePositionManager, address _baseToken, address _swapRouter) 
    // address _spokePool
    {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        baseToken = _baseToken;
        swapRouter = _swapRouter;
        // spokePool = _spokePool;
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data)
        external
        virtual
        override
        unpaused
        nonReentrant
        returns (bytes4)
    {
        _migratePosition(from, tokenId, data);
        return this.onERC721Received.selector;
    }

    function _migratePosition(address from, uint256 tokenId, bytes memory data) internal {
        INonfungiblePositionManager nftManager = INonfungiblePositionManager(nonfungiblePositionManager);

        // confirm that this tokenId is now owned by this contract
        require(nftManager.ownerOf(tokenId) == address(this), "Token not owned by this contract");

        // 1. get the tokens in the position

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
        (uint256 amount0Collected, uint256 amount1Collected) = nftManager.collect(collectParams);

        // 4. burn the position
        nftManager.burn(tokenId); // todo: check if this is needed

        uint256 amountToken0 = IERC20(token0).balanceOf(address(this));
        uint256 amountToken1 = IERC20(token1).balanceOf(address(this));

        // 3. swap one or both tokens for baseToken
        if (token0 != baseToken) {
            // swap token0 for baseToken
            uint256 amountToken0 = IERC20(token0).balanceOf(address(this));
            require(amountToken0 == amount0Collected, "Incorrect amount of token0 to swap");

            IERC20(token0).approve(swapRouter, amountToken0);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: baseToken,
                fee: 3000, // todo: make dynamic
                recipient: address(this),
                // deadline: block.timestamp + 60, // 1 min (might be too long)
                amountIn: amountToken0,
                amountOutMinimum: 0, // todo: add slippage
                sqrtPriceLimitX96: 0
            });
            uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        }
        if (token1 != baseToken) {
            // swap token1 for baseToken
            uint256 amountToken1 = IERC20(token1).balanceOf(address(this));
            require(amountToken1 == amount1Collected, "Incorrect amount of token1 to swap");
            IERC20(token1).approve(swapRouter, amountToken1);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: token1,
                tokenOut: baseToken,
                fee: 3000, // todo: make dynamic
                recipient: address(this),
                amountIn: amountToken1,
                amountOutMinimum: 0, // todo: add slippage
                sqrtPriceLimitX96: 0
            });
            uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        }

        // 4. send the baseToken to the bridge with LP position info
        uint256 amountBaseToken = IERC20(baseToken).balanceOf(address(this));

        // send ETH to bridge with message
        // SpokePool(spokePool).depositV3(
        //   from, // depositor
        //   address(this), // recipient
        //   baseToken, // inputToken
        //   0x0000000000000000000000000000000000000000, // outputToken; resolved automatically
        //   amountOut+amountBaseToken, // inputAmount
        //   0, // outputAmount; todo set from api call via data
        //   101, // destinationChainId; todo set from api call via data
        //   address(0x0), // exclusiveRelayer; todo set from api call via data
        //   0, // quoteTimestamp; todo set from api call via data
        //   0, // fillDeadline; todo set from api call via data
        //   0, // exclusivityDeadline; todo set from api call via data
        //   data // message
        // );

        // construct message to bridge

        // todo include info about LP position
    }

    // used to receive tokens from the bridge
    function _receiveToken(address token, uint256 amount) internal {
        // todo: implement
    }
}
