// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "@uniswap-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IMigrator} from "../interfaces/IMigrator.sol";
import {UniswapV3Library} from "../libraries/UniswapV3Library.sol";

abstract contract Migrator is IMigrator, IERC721Receiver, Ownable2Step {
    using UniswapV3Library for INonfungiblePositionManager;

    INonfungiblePositionManager public immutable positionManager;
    mapping(uint256 => mapping(address => bool)) internal chainSettlers;
    uint256 internal _migrationCounter = 0;

    constructor(address _positionManager) Ownable(msg.sender) {
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    function addChainSettler(uint256 chainID, address settler) external onlyOwner {
        chainSettlers[chainID][settler] = true;
    }

    function removeChainSettler(uint256 chainID, address settler) external onlyOwner {
        chainSettlers[chainID][settler] = false;
    }

    function isChainSettler(uint256 chainID, address settler) external view returns (bool) {
        return chainSettlers[chainID][settler];
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data)
        external
        virtual
        override
        returns (bytes4)
    {
        if (msg.sender != address(positionManager)) revert NotPositionManager();

        _migrate(from, tokenId, data);

        return this.onERC721Received.selector;
    }

    function _migrate(address sender, uint256 positionId, bytes memory data) internal virtual;
}
