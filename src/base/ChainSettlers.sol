// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";

/// @title ChainSettlers
/// @notice Contract for managing chain settlers
contract ChainSettlers is Ownable2Step {
    /// @notice Error thrown when the chain settler params length mismatch
    error ChainSettlersParamsLengthMismatch();
    /// @notice Error thrown when the chain settler is not supported
    error ChainSettlerNotSupported(uint256 chainId, address settler);

    /// @notice Event emitted when a chain settler is updated
    event ChainSettlerUpdated(uint256 indexed chainId, address indexed settler, bool value);

    mapping(uint256 => mapping(address => bool)) public chainSettlers;

    /// @notice Constructor for the ChainSettlers contract
    /// @param initialOwner The initial owner of the contract
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Function to set the chain settlers
    /// @param chainIds The chain ids
    /// @param settlers The settlers
    /// @param values The values
    /// @dev Only the owner can call this function
    function setChainSettlers(uint256[] calldata chainIds, address[] calldata settlers, bool[] calldata values)
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
