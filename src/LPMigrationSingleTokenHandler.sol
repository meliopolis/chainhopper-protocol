// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/external/ISwapRouter.sol";
import "./interfaces/external/INonfungiblePositionManager.sol";
import "./interfaces/external/ISpokePool.sol";
import "./interfaces/external/AcrossMessageHandler.sol";
import "./interfaces/ILPMigrationHandler.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ILPMigrator.sol";

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

    function swapAndCreatePosition(uint256 amount, ILPMigrator.SettlementParams memory settlementParams)
        external
        returns (uint256)
    {
        if (IERC20(baseToken).balanceOf(address(this)) < amount) revert InsufficientBalance();

        address token0 = settlementParams.token0;
        address token1 = settlementParams.token1;
        uint24 feeTier = settlementParams.feeTier;

        if (settlementParams.amount0Min == 0 && settlementParams.amount1Min == 0) {
            revert AtLeastOneAmountMustBeGreaterThanZero();
        }

        uint256 amountToTrade =
            token0 == baseToken ? amount - settlementParams.amount0Min : amount - settlementParams.amount1Min;
        uint256 amountOut = 0;
        if (amountToTrade > 0) {
            // 2. swap baseToken for tokens needed in the position
            IERC20(baseToken).approve(swapRouter, amountToTrade);

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: baseToken,
                tokenOut: token0 == baseToken ? token1 : token0,
                fee: feeTier,
                recipient: address(this),
                amountIn: amountToTrade,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        }
        uint256 amount0Desired = 0;
        uint256 amount1Desired = 0;

        if (token0 == baseToken) {
            amount0Desired = settlementParams.amount0Min;
            amount1Desired = amountOut;
        } else if (token1 == baseToken) {
            amount0Desired = amountOut;
            amount1Desired = settlementParams.amount1Min;
        }
        // need to approve the nonfungible position manager to use the other token
        if (amount0Desired > 0) {
            IERC20(token0).approve(nftPositionManager, amount0Desired);
        }
        if (amount1Desired > 0) {
            IERC20(token1).approve(nftPositionManager, amount1Desired);
        }
        // 3. mint the position
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: token0, // assumes message has sorted token
            token1: token1,
            fee: feeTier,
            tickLower: settlementParams.tickLower,
            tickUpper: settlementParams.tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0, // are these needed?
            amount1Min: 0, // are these needed?
            recipient: settlementParams.recipient,
            deadline: block.timestamp
        });
        (uint256 tokenId,, uint256 amount0Minted, uint256 amount1Minted) =
            INonfungiblePositionManager(nftPositionManager).mint(mintParams);

        // 4. Sweep any remaining tokens to the recipient
        uint256 amountToken0Remaining = amount0Desired - amount0Minted;
        uint256 amountToken1Remaining = amount1Desired - amount1Minted;

        if (amountToken0Remaining > 0) {
            IERC20(token0).transfer(settlementParams.recipient, amountToken0Remaining);
        }
        if (amountToken1Remaining > 0) {
            IERC20(token1).transfer(settlementParams.recipient, amountToken1Remaining);
        }
        return tokenId;
    }

    // used to receive tokens from the bridge
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address, bytes memory message) external {
        if (msg.sender != address(spokePool)) revert OnlySpokePoolCanCall();
        if (tokenSent != baseToken) revert OnlyBaseTokenCanBeReceived();

        // TODO: decide if message needs to be validated
        // per https://docs.across.to/use-cases/embedded-cross-chain-actions/cross-chain-actions-integration-guide/using-the-generic-multicaller-handler-contract#security-and-safety-considerations,
        //  Message can be spoofed. Across doesn't guarantee the message is valid.

        ILPMigrator.SettlementParams memory settlementParams = abi.decode(message, (ILPMigrator.SettlementParams));
        try this.swapAndCreatePosition(amount, settlementParams) returns (uint256) {
            // TODO: add fees transfer
            // console.log("Successfully received baseToken and position created", tokenId);
        } catch {
            // revert
            IERC20(baseToken).transfer(settlementParams.recipient, amount);
        }
    }
}
