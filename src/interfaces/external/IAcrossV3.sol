// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// interface IAcrossV3SpokePool {
//     function depositV3(
//         address depositor,
//         address recipient,
//         address inputToken,
//         address outputToken,
//         uint256 inputAmount,
//         uint256 outputAmount,
//         uint256 destinationChainId,
//         address exclusiveRelayer,
//         uint32 quoteTimestamp,
//         uint32 fillDeadline,
//         uint32 exclusivityDeadline,
//         bytes calldata message
//     ) external payable;

//     function depositV3Now(
//         address depositor,
//         address recipient,
//         address inputToken,
//         address outputToken,
//         uint256 inputAmount,
//         uint256 outputAmount,
//         uint256 destinationChainId,
//         address exclusiveRelayer,
//         uint32 fillDeadlineOffset,
//         uint32 exclusivityDeadline,
//         bytes calldata message
//     ) external payable;
// }

// interface IAcrossV3SpokePoolMessageHandler {
//     function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message) external;
// }
