// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC721Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IMigrator} from "./IMigrator.sol";

interface ISingleTokenMigrator is IERC721Receiver {
    error NoBaseTokenFound();

    struct SingleTokenMigrationParams {
        IMigrator.BaseMigrationParams baseParams;
        // across data for single token bridging
        address outputToken;
        uint32 quoteTimestamp;
        uint32 fillDeadlineBuffer; // todo is this needed or can be read from spokepool?
        uint256 maxFees;
        address exclusiveRelayer;
        uint32 exclusivityDeadline;
    }

    event MigrationInitiatedSingleToken(
        uint256 indexed tokenId,
        address indexed recipient,
        uint24 indexed destinationChainId,
        address tokenSent,
        uint256 amountSent
    );
}
