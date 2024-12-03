// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/INonfungiblePositionManager.sol";

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
        // todo: implement
    }

    // used to receive tokens from the bridge
    function _receiveToken(address token, uint256 amount) internal {
        // todo: implement
    }
}
