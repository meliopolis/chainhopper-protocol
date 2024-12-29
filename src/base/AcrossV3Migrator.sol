// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {Ownable2Step, Ownable} from "openzeppelin/access/Ownable2Step.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IAcrossV3SpokePool} from "../interfaces/external/IAcrossV3.sol";
import {IUniswapV3PositionManager} from "../interfaces/external/IUniswapV3.sol";
import {UniswapV3Library} from "../libraries/UniswapV3Library.sol";

abstract contract AcrossV3Migrator is IERC721Receiver, Ownable2Step {
    error NotPositionManager();

    using UniswapV3Library for IUniswapV3PositionManager;

    IUniswapV3PositionManager internal immutable positionManager;
    IAcrossV3SpokePool internal immutable spokePool;
    mapping(uint256 => address) internal chainSettlers;

    constructor(address _positionManager, address _spokePool) Ownable(msg.sender) {
        positionManager = IUniswapV3PositionManager(_positionManager);
        spokePool = IAcrossV3SpokePool(_spokePool);
    }

    function setChainSettler(uint256 chainID, address settler) external onlyOwner {
        chainSettlers[chainID] = settler;
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {
        require(msg.sender == address(positionManager), NotPositionManager());

        // liquidate position
        (address token0, address token1, uint24 fee, uint256 amount0, uint256 amount1) =
            positionManager.liquidatePosition(tokenId, address(this));

        _migrate(from, token0, token1, fee, tokenId, amount0, amount1, data);

        return this.onERC721Received.selector;
    }

    function _migrate(
        address sender,
        address token0,
        address token1,
        uint24 fee,
        uint256 positionId,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) internal virtual;
}
