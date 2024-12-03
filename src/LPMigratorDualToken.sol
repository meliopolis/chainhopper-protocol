// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ISwapRouter.sol";
import "./INonfungiblePositionManager.sol";

contract LPMigratorSingleToken is IERC721Receiver, ReentrancyGuard, Pausable {
    mapping(address => bool) public supportedTokens;
    address public nonfungiblePositionManager;
    address public swapRouter;
    address public spokePool;
    /**
     *
     *  Modifiers  *
     *
     */

    modifier unpaused() {
        require(!paused(), "LPMigrator paused");
        _;
    }

    /**
     *
     *  Functions  *
     *
     */
    constructor(
        address _nonfungiblePositionManager,
        address[] memory _supportedTokens,
        address _swapRouter,
        address _spokePool
    ) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            supportedTokens[_supportedTokens[i]] = true;
        }
        swapRouter = _swapRouter;
        spokePool = _spokePool;
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

        // 1. get the tokens in the position

        (,, address token0, address token1,,,, uint128 liquidity,,, uint128 amount0Owed, uint128 amount1Owed) =
            nftManager.positions(tokenId);
        // todo: check if both tokens are supported

        // 2. collect fees and decrease liquidity
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        (uint256 amount0Fees, uint256 amount1Fees) = nftManager.collect(collectParams);

        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: amount0Owed, // todo: might need to account for slippage
            amount1Min: amount1Owed, // todo: might need to account for slippage
            deadline: block.timestamp + 60 // 1 min (might be too long)
        });
        (uint256 amount0, uint256 amount1) = nftManager.decreaseLiquidity(decreaseLiquidityParams);

        // 3. send token0 to bridge
        // 4. send token1 to bridge
    }

    // used to receive tokens from the bridge
    function _receiveToken(address token, uint256 amount) internal {
        // todo: implement
    }
}
