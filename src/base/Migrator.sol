// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Ownable2Step, Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {IERC721Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IMigrator} from "../interfaces/IMigrator.sol";

abstract contract Migrator is IMigrator, IERC721Receiver, Ownable2Step {
    error NotPositionManager();

    address private immutable positionManager;
    mapping(uint256 => mapping(address => bool)) internal chainSettlers;

    constructor(address _positionManager) Ownable(msg.sender) {
        positionManager = _positionManager;
    }

    function addChainSettler(uint256 chainID, address settler) external onlyOwner {
        chainSettlers[chainID][settler] = true;
    }

    function removeChainSettler(uint256 chainID, address settler) external onlyOwner {
        chainSettlers[chainID][settler] = false;
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {
        require(msg.sender == positionManager, NotPositionManager());

        _migrate(from, tokenId, data);

        return this.onERC721Received.selector;
    }

    function _migrate(address sender, uint256 positionId, bytes memory data) internal virtual;
}
