// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface ILPMigrator is IERC721Receiver {
    struct MigrationParams {
        address recipient;
        uint32 fillDeadlineBuffer;
        uint256 feePercentage;
        address exclusiveRelayer;
        uint256 destinationChainId;
        bytes mintParams;
    }
}
