// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {IDirectMigrator} from "../interfaces/IDirectMigrator.sol";
import {IDirectSettler} from "../interfaces/IDirectSettler.sol";
import {Migrator} from "./Migrator.sol";

/// @title DirectMigrator
/// @notice Abstract contract for migrating positions on the same chain using direct transfers
abstract contract DirectMigrator is IDirectMigrator, Migrator {
    using SafeERC20 for IERC20;

    /// @notice The WETH address
    address private immutable weth;

    /// @notice Constructor for the DirectMigrator contract
    constructor(address _weth) {
        weth = _weth;
    }

    /// @notice Internal function to bridge tokens (dummy function for same-chain operations)
    /// @param 1 Ignored - The sender of the migration (not used for direct transfers)
    /// @param chainId The destination chain id (should be same as current chain)
    /// @param settler The settler address on destination chain
    /// @param token The token needed on destination chain
    /// @param amount The amount to bridge
    /// @param 6 Ignored - The input token sent into the bridge (not used for direct transfers)
    /// @param 7 Ignored - The route data (not used for direct transfers)
    /// @param data The data to bridge
    function _bridge(
        address,
        uint256 chainId,
        address settler,
        address token,
        uint256 amount,
        address,
        bytes memory,
        bytes memory data
    ) internal override {
        // Verify we're on the same chain
        if (chainId != block.chainid) {
            revert CrossChainNotSupported();
        }

        // settler can't receive native token
        if (token == address(0)) {
            // wrap the native token to WETH and transfer to the settler
            IWETH9(weth).deposit{value: amount}();
            IERC20(weth).safeTransferFrom(address(this), settler, amount);
        } else {
            // transfer ERC20 token to the settler
            IERC20(token).safeTransferFrom(address(this), settler, amount);
        }

        // call the handleDTMessage function on the settler
        (bool success,) =
            settler.call(abi.encodeWithSelector(IDirectSettler.handleDTMessage.selector, token, amount, data));
        if (!success) revert();
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
