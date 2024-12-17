// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/external/ISwapRouter.sol";
import "./interfaces/external/INonfungiblePositionManager.sol";
import "./interfaces/external/ISpokePool.sol";
import "./interfaces/external/AcrossMessageHandler.sol";
import "./interfaces/ILPMigrationHandler.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LPMigrationSingleTokenHandler is ILPMigrationHandler {
    using SafeERC20 for IERC20;

    mapping(address => bool) public supportedTokens;
    address public immutable nftPositionManager;
    address public immutable baseToken; // token received from the bridge
    address public immutable swapRouter;
    address public immutable spokePool;

    /**
     *
     *  Functions  *
     *
     */
    constructor(address _nftPositionManager, address _baseToken, address _swapRouter, address _spokePool) {
        nftPositionManager = _nftPositionManager;
        baseToken = _baseToken;
        swapRouter = _swapRouter;
        spokePool = _spokePool;
    }

    function swapAndCreatePosition(uint256 amount, bytes memory message) external returns (uint256) {
        (
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            ,
            ,
            uint256 amount0Min,
            uint256 amount1Min,
            address recipient,
            uint24 percentToken0 // in bps
        ) = abi.decode(
            message, (address, address, uint24, int24, int24, uint256, uint256, uint256, uint256, address, uint24)
        );
        address otherToken = token0 == baseToken ? token1 : token0;
        uint256 amountIn = 0;
        if (token0 == baseToken) {
            // swap token1 for baseToken
            amountIn = amount * (10000 - percentToken0) / 10000;
        } else if (token1 == baseToken) {
            // swap token0 for baseToken
            amountIn = amount * percentToken0 / 10000;
        }

        // 2. swap baseToken for tokens needed in the position
        IERC20(baseToken).approve(swapRouter, amountIn);

        // v0.1: initially we'll calculate the current price of the pool and swap assuming position will be minted at that price
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: baseToken,
            tokenOut: otherToken,
            fee: fee,
            recipient: address(this),
            amountIn: amountIn, // need to calculate
            amountOutMinimum: 0, // todo: add slippage
            sqrtPriceLimitX96: 0
        });
        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        uint256 amount0Desired = 0;
        uint256 amount1Desired = 0;

        if (token0 == baseToken) {
            amount0Desired = amount - amountIn;
            amount1Desired = amountOut;
        } else if (token1 == baseToken) {
            amount0Desired = amountOut;
            amount1Desired = amount - amountIn;
        }
        // need to approve the nonfungible position manager to use the other token
        IERC20(token0).approve(nftPositionManager, amount0Desired * 1000);
        IERC20(token1).approve(nftPositionManager, amount1Desired * 1000);
        // 3. mint the position
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: recipient,
            deadline: block.timestamp
        });
        (uint256 tokenId,,,) = INonfungiblePositionManager(nftPositionManager).mint(mintParams);

        // 4. Sweep any remaining tokens to the recipient
        // INonfungiblePositionManager(nftPositionManager).safeTransferFrom(address(this), recipient, tokenId);

        require(
            INonfungiblePositionManager(nftPositionManager).ownerOf(tokenId) == recipient,
            "Position must be owned by recipient"
        );
        uint256 amountToken0Remaining = IERC20(token0).balanceOf(address(this));
        uint256 amountToken1Remaining = IERC20(token1).balanceOf(address(this));

        if (amountToken0Remaining > 0) {
            IERC20(token0).transfer(recipient, amountToken0Remaining);
        }
        if (amountToken1Remaining > 0) {
            IERC20(token1).transfer(recipient, amountToken1Remaining);
        }
        return tokenId;
    }

    // used to receive tokens from the bridge
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address, bytes memory message) external {
        require(msg.sender == address(spokePool), "Only spokePool can call this function");
        require(tokenSent == baseToken, "Only baseToken can be received");
        require(IERC20(baseToken).balanceOf(address(this)) >= amount, "Insufficient balance");
        // 1. check the message is valid. How?
        // per https://docs.across.to/use-cases/embedded-cross-chain-actions/cross-chain-actions-integration-guide/using-the-generic-multicaller-handler-contract#security-and-safety-considerations,
        //  Message can be spoofed. Across doesn't guarantee the message is valid.

        try this.swapAndCreatePosition(amount, message) returns (uint256 tokenId) {
            console.log("Successfully received baseToken and position created", tokenId);
        } catch {
            // revert
            (,,,,,,,,, address recipient,) = abi.decode(
                message, (address, address, uint24, int24, int24, uint256, uint256, uint256, uint256, address, uint24)
            );
            IERC20(baseToken).transfer(recipient, amount);
        }
    }
}
