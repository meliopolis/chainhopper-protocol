// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IAcrossV3SpokePoolMessageHandler {
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message) external;
}
