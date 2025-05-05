// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IMigrator} from "../../src/interfaces/IMigrator.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {IAcrossMigrator} from "../../src/interfaces/IAcrossMigrator.sol";
import {IUniswapV3Settler} from "../../src/interfaces/IUniswapV3Settler.sol";
import {console} from "lib/forge-std/src/console.sol";

library MigrationHelpers {
    function generateMigrationParams(address token, address settler)
        public
        view
        returns (IMigrator.MigrationParams memory)
    {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        return generateMigrationParams(tokens, settler);
    }

    function generateMigrationParams(address token0, address token1, address settler)
        public
        view
        returns (IMigrator.MigrationParams memory)
    {
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        return generateMigrationParams(tokens, settler);
    }

    function generateMigrationParams(address[] memory tokens, address settler)
        public
        view
        returns (IMigrator.MigrationParams memory)
    {
        uint256 chainId = 130;
        // generate routes
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            IAcrossMigrator.Route memory route = IAcrossMigrator.Route({
                outputToken: tokens[i],
                maxFees: 10_000_000,
                quoteTimestamp: uint32(block.timestamp),
                fillDeadlineOffset: 21600,
                exclusiveRelayer: address(0),
                exclusivityDeadline: 0
            });
            tokenRoutes[i] = IMigrator.TokenRoute({token: tokens[i], amountOutMin: 0, route: abi.encode(route)});
        }
        // generate MigrationParams
        // note: settlementParams contents don't matter for migrator, since it passes them to bridge as is
        return IMigrator.MigrationParams({
            chainId: chainId,
            settler: settler,
            tokenRoutes: tokenRoutes,
            settlementParams: ""
        });
    }
}
