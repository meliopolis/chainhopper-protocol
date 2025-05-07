// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {V3SpokePoolInterface as IAcrossSpokePool} from "@across/interfaces/V3SpokePoolInterface.sol";
import {IAcrossMigrator} from "../interfaces/IAcrossMigrator.sol";
import {Migrator} from "./Migrator.sol";

/// @title AcrossMigrator
/// @notice Abstract contract for migrating positions between chains using Across
abstract contract AcrossMigrator is IAcrossMigrator, Migrator {
    using SafeERC20 for IERC20;

    /// @notice The Across Spokepool address
    IAcrossSpokePool private immutable spokePool;
    /// @notice The WETH address
    address private immutable weth;

    /// @notice Constructor for the AcrossMigrator contract
    /// @param _spokePool The Across Spokepool address
    /// @param _weth The WETH address
    constructor(address _spokePool, address _weth) {
        spokePool = IAcrossSpokePool(_spokePool);
        weth = _weth;
    }

    /// @notice Internal function to bridge tokens
    /// @param sender The sender of the migration
    /// @param chainId The destination chain id
    /// @param settler The settler address on destination chain
    /// @param token The token needed on destination chain (ex: WETH or native token)
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
        Route memory route = abi.decode(routeData, (Route));

        // this appears to be needed even if sending native token
        IERC20(inputToken).forceApprove(address(spokePool), amount);
        uint256 value = token == address(0) ? amount : 0;

        // initiate migration via the spoke pool
        spokePool.depositV3{value: value}(
            sender,
            settler,
            inputToken,
            route.outputToken,
            amount,
            amount - route.maxFees,
            chainId,
            route.exclusiveRelayer,
            route.quoteTimestamp,
            uint32(block.timestamp) + route.fillDeadlineOffset,
            route.exclusivityDeadline,
            data
        );

        // clear allowance in case of sending native token
        IERC20(inputToken).forceApprove(address(spokePool), 0);
    }

    /// @notice Internal function to match a token with a route
    /// @param token The token to match
    /// @param tokenRoute The route to match
    /// @return isMatch True if the token matches the route, false otherwise
    function _matchTokenWithRoute(address token, TokenRoute memory tokenRoute) internal view override returns (bool) {
        return token == tokenRoute.token || (token == address(0) && tokenRoute.token == weth);
    }

    /// @notice Internal function to check if an amount is sufficient
    function _isAmountSufficient(uint256 amount, TokenRoute memory tokenRoute) internal pure override returns (bool) {
        return amount >= tokenRoute.amountOutMin + abi.decode(tokenRoute.route, (Route)).maxFees;
    }
}
