// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC721Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IMigrator} from "./IMigrator.sol";

interface IDualTokenMigrator is IERC721Receiver {
    error SenderIsNotNFTPositionManager();

    struct DualTokenMigrationParams {
        IMigrator.BaseMigrationParams baseParams;
        // across data for dual token bridging
        address outputToken0;
        address outputToken1;
        uint256 maxFees0;
        uint256 maxFees1;
        address exclusiveRelayer0;
        address exclusiveRelayer1;
        uint32 exclusivityDeadline0;
        uint32 exclusivityDeadline1;
        uint32 quoteTimestamp; // can use same timestamp for both
        uint32 fillDeadlineBuffer; // todo is this needed or can be read from spokepool?
    }

    event MigrationInitiatedDualToken(
        uint256 indexed tokenId,
        address indexed recipient,
        uint24 indexed destinationChainId,
        address tokenSent0,
        address tokenSent1,
        uint256 amountSent0,
        uint256 amountSent1
    );
}
