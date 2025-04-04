// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";

contract ChainSettlers is Ownable2Step {
    error ChainSettlersParamsLengthMismatch();

    event ChainSettlerUpdated(uint32 indexed chainId, address indexed settler, bool value);

    mapping(uint32 => mapping(address => bool)) public chainSettlers;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setChainSettlers(uint32[] calldata chainIds, address[] calldata settlers, bool[] calldata values)
        external
        onlyOwner
    {
        if (chainIds.length != values.length || settlers.length != values.length) {
            revert ChainSettlersParamsLengthMismatch();
        }

        for (uint256 i = 0; i < values.length; i++) {
            chainSettlers[chainIds[i]][settlers[i]] = values[i];
            emit ChainSettlerUpdated(chainIds[i], settlers[i], values[i]);
        }
    }
}
