// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./external/AcrossMessageHandler.sol";

interface ILPMigrationHandler is AcrossMessageHandler {
    error OnlySpokePoolCanCall();
    error OnlyBaseTokenCanBeReceived();
    error InsufficientBalance();
    error TryToSwapAndCreatePositionFails();
    error AtLeastOneAmountMustBeGreaterThanZero();
}
