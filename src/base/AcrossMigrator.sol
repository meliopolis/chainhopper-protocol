// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {V3SpokePoolInterface as IAcrossSpokePool} from "@across/interfaces/V3SpokePoolInterface.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IAcrossMigrator} from "../interfaces/IAcrossMigrator.sol";
import {Migrator} from "./Migrator.sol";

abstract contract AcrossMigrator is IAcrossMigrator, IERC721Receiver, Migrator {
    address private immutable positionManager;
    IAcrossSpokePool private immutable spokePool;

    constructor(address _positionManager, address _spokePool) {
        positionManager = _positionManager;
        spokePool = IAcrossSpokePool(_spokePool);
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {
        if (msg.sender != positionManager) revert NotPositionManager();

        try this.migrate(from, tokenId, data) {}
        catch {
            IERC721(msg.sender).safeTransferFrom(address(this), from, tokenId);
        }

        return this.onERC721Received.selector;
    }

    function _migrate(
        address sender,
        uint32 destinationChainId,
        address destinationSettler,
        TokenRoute memory tokenRoute,
        uint256 amount,
        bytes memory message
    ) internal override {
        Route memory route = abi.decode(tokenRoute.route, (Route));

        spokePool.depositV3(
            sender,
            destinationSettler,
            route.inputToken,
            route.outputToken,
            amount,
            amount - route.maxFees,
            destinationChainId,
            route.exclusiveRelayer,
            route.quoteTimestamp,
            uint32(block.timestamp) + route.fillDeadlineOffset,
            route.exclusivityDeadline,
            message
        );
    }
}
