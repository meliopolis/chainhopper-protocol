// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface ILPMigrator is IERC721Receiver {
    struct MigrationParams {
        address recipient;
        uint32 quoteTimestamp; // from AcrossQuote
        uint32 fillDeadlineBuffer; // from AcrossQuote
        uint256 maxFees; // from AcrossQuote
        address outputToken;
        address exclusiveRelayer; // from AcrossQuote
        uint32 exclusivityDeadline; // from AcrossQuote
        uint256 destinationChainId;
        bytes mintParams;
    }

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint24 percentToken0;
    }
}
