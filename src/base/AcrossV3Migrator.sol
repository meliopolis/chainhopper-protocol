// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import {Ownable2Step, Ownable} from "openzeppelin/access/Ownable2Step.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IAcrossV3SpokePool} from "../interfaces/external/IAcrossV3.sol";

abstract contract AcrossV3Migrator is IERC721Receiver, Ownable2Step {
    error NotPositionManager();

    address private immutable positionManager;
    IAcrossV3SpokePool internal immutable spokePool;
    mapping(uint256 => address) internal chainSettlers;

    constructor(address _positionManager, address _spokePool) Ownable(msg.sender) {
        positionManager = _positionManager;
        spokePool = IAcrossV3SpokePool(_spokePool);
    }

    function setChainSettler(uint256 chainID, address settler) external onlyOwner {
        chainSettlers[chainID] = settler;
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {
        if (msg.sender != positionManager) revert NotPositionManager();

        _migrate(from, tokenId, data);

        return this.onERC721Received.selector;
    }

    function _migrate(address sender, uint256 positionId, bytes memory data) internal virtual;
}
