// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISettler} from "./ISettler.sol";

interface IAcrossSettler is ISettler {
    error NotSpokePool();
}
