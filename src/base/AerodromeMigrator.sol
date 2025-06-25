// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
// copied and modified from uniswap-v3-periphery, as the original had bad imports
import {IAerodromeNonfungiblePositionManager as IPositionManager} from
    "../interfaces/external/IAerodromeNonfungiblePositionManager.sol";
import {IAerodromeMigrator} from "../interfaces/IAerodromeMigrator.sol";
import {AerodromeLibrary} from "../libraries/AerodromeLibrary.sol";
import {Migrator} from "./Migrator.sol";

/// @title AerodromeMigrator
/// @notice Abstract contract for migrating positions between chains using Aerodrome
abstract contract AerodromeMigrator is IAerodromeMigrator, IERC721Receiver, Migrator {
    IPositionManager private immutable positionManager;
    IUniversalRouter private immutable universalRouter;
    IPermit2 private immutable permit2;
    mapping(address => bool) isPermit2Approved;

    /// @notice Constructor for the AerodromeMigrator contract
    /// @param _positionManager The position manager address
    /// @param _universalRouter The universal router address
    /// @param _permit2 The permit2 address
    constructor(address _positionManager, address _universalRouter, address _permit2) {
        positionManager = IPositionManager(_positionManager);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IPermit2(_permit2);
    }

    /// @notice Callback function for ERC721 tokens
    /// @dev This function is called when a user transfers an ERC721 token to the contract. If it fails, the transaction will revert.
    /// @param from The sender of the transfer (ex: User EOA)
    /// @param tokenId The token id
    /// @param data The data of the transfer
    /// @return selector The selector of the callback
    function onERC721Received(address, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {
        if (msg.sender != address(positionManager)) revert NotAerodromePositionManager();

        _migrate(from, tokenId, data);

        return this.onERC721Received.selector;
    }

    /// @notice Internal function to liquidate a position
    /// @param positionId The id of the position
    /// @return token0 The first token
    /// @return token1 The second token
    /// @return amount0 The amount of token0 received
    /// @return amount1 The amount of token1 received
    /// @return poolInfo The pool info
    function _liquidate(uint256 positionId)
        internal
        override
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo)
    {
        int24 tickSpacing;
        (token0, token1, tickSpacing, amount0, amount1) =
            AerodromeLibrary.liquidatePosition(positionManager, positionId, 0, 0, address(this));

        poolInfo = abi.encode(token0, token1, tickSpacing);
    }

    /// @notice Internal function to swap tokens
    /// @param poolInfo The pool info
    /// @param zeroForOne The direction of the swap
    /// @param amountIn The amount to swap
    /// @return amountOut The amount of tokens received
    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn)
        internal
        override
        returns (uint256 amountOut)
    {
        (address token0, address token1, int24 tickSpacing) = abi.decode(poolInfo, (address, address, int24));

        // get token in and out
        (address tokenIn, address tokenOut) = zeroForOne ? (token0, token1) : (token1, token0);

        amountOut = AerodromeLibrary.swap(
            universalRouter, permit2, isPermit2Approved, tokenIn, tokenOut, tickSpacing, amountIn, 0, address(this)
        );
    }
}
