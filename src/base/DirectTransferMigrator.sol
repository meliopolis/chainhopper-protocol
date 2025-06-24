// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IDirectTransferMigrator} from "../interfaces/IDirectTransferMigrator.sol";
import {IDirectTransferSettler} from "../interfaces/IDirectTransferSettler.sol";
import {Migrator} from "./Migrator.sol";

/// @title DirectTransferMigrator
/// @notice Abstract contract for migrating positions on the same chain using direct transfers
abstract contract DirectTransferMigrator is IDirectTransferMigrator, Migrator {
    using SafeERC20 for IERC20;

    /// @notice Constructor for the DirectTransferMigrator contract
    constructor() {}

    /// @notice Internal function to bridge tokens (dummy function for same-chain operations)
    /// @param sender The sender of the migration
    /// @param chainId The destination chain id (should be same as current chain)
    /// @param settler The settler address on destination chain
    /// @param token The token needed on destination chain
    /// @param amount The amount to bridge
    /// @param inputToken The input token sent into the bridge
    /// @param routeData The route data
    /// @param data The data to bridge
    function _bridge(
        address sender,
        uint256 chainId,
        address settler,
        address token,
        uint256 amount,
        address inputToken,
        bytes memory routeData,
        bytes memory data
    ) internal override {
        // Verify we're on the same chain
        if (chainId != block.chainid) {
            revert CrossChainNotSupported();
        }

        IERC20(token).safeTransferFrom(address(this), settler, amount);
        settler.call(abi.encodeWithSelector(IDirectTransferSettler.handleDTMessage.selector, token, amount, data));
    }

    /// @notice Internal function to match a token with a route
    /// @param token The token to match
    /// @param tokenRoute The route to match
    /// @return isMatch True if the token matches the route, false otherwise
    function _matchTokenWithRoute(address token, TokenRoute memory tokenRoute) internal pure override returns (bool) {
        // For direct transfer, we match tokens directly without routing
        return token == tokenRoute.token;
    }

    /// @notice Internal function to check if an amount is sufficient
    function _isAmountSufficient(uint256 amount, TokenRoute memory tokenRoute) internal pure override returns (bool) {
        // For direct transfer, we only check against the minimum amount (no bridge fees)
        return amount >= tokenRoute.amountOutMin;
    }

    /// @notice Internal function to get the output token from a token route
    function _getOutputToken(TokenRoute memory tokenRoute) internal pure override returns (address outputToken) {
        // For direct transfer, the output token is the same as the input token
        outputToken = tokenRoute.token;
    }
} 