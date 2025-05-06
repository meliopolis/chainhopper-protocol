// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IMigrator} from "../../src/interfaces/IMigrator.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {IAcrossMigrator} from "../../src/interfaces/IAcrossMigrator.sol";
import {IUniswapV3Settler} from "../../src/interfaces/IUniswapV3Settler.sol";
import {console} from "lib/forge-std/src/console.sol";

library MigrationHelpers {
    function generateMigrationParams(address token, address settler, uint256 amountOutMin)
        public
        view
        returns (IMigrator.MigrationParams memory)
    {
        address[] memory tokensSourceChain = new address[](1);
        tokensSourceChain[0] = token;
        address[] memory tokensDestinationChain = new address[](1);
        tokensDestinationChain[0] = token;
        uint256[] memory amountOutMins = new uint256[](1);
        amountOutMins[0] = amountOutMin;
        return generateMigrationParams(tokensSourceChain, tokensDestinationChain, amountOutMins, settler);
    }

    function generateMigrationParams(
        address tokenSourceChain,
        address tokenDestinationChain,
        uint256 amountOutMin,
        address settler
    ) public view returns (IMigrator.MigrationParams memory) {
        address[] memory tokensSourceChain = new address[](1);
        tokensSourceChain[0] = tokenSourceChain;
        address[] memory tokensDestinationChain = new address[](1);
        tokensDestinationChain[0] = tokenDestinationChain;
        uint256[] memory amountOutMins = new uint256[](1);
        amountOutMins[0] = amountOutMin;
        return generateMigrationParams(tokensSourceChain, tokensDestinationChain, amountOutMins, settler);
    }

    function generateMigrationParams(
        address token0,
        address token1,
        address token0Destination,
        address token1Destination,
        uint256 amountOutMin0,
        uint256 amountOutMin1,
        address settler
    ) public view returns (IMigrator.MigrationParams memory) {
        address[] memory tokensSourceChain = new address[](2);
        tokensSourceChain[0] = token0;
        tokensSourceChain[1] = token1;
        address[] memory tokensDestinationChain = new address[](2);
        tokensDestinationChain[0] = token0Destination;
        tokensDestinationChain[1] = token1Destination;
        uint256[] memory amountOutMins = new uint256[](2);
        amountOutMins[0] = amountOutMin0;
        amountOutMins[1] = amountOutMin1;
        return generateMigrationParams(tokensSourceChain, tokensDestinationChain, amountOutMins, settler);
    }

    function generateMigrationParams(
        address[] memory tokensSourceChain,
        address[] memory tokensDestinationChain,
        uint256[] memory amountOutMins,
        address settler
    ) public view returns (IMigrator.MigrationParams memory) {
        uint256 chainId = 130;
        // generate routes
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](tokensSourceChain.length);

        for (uint256 i = 0; i < tokensSourceChain.length; i++) {
            IAcrossMigrator.Route memory route = IAcrossMigrator.Route({
                outputToken: tokensDestinationChain[i],
                maxFees: 10_000_000,
                quoteTimestamp: uint32(block.timestamp),
                fillDeadlineOffset: 21600,
                exclusiveRelayer: address(0),
                exclusivityDeadline: 0
            });
            tokenRoutes[i] = IMigrator.TokenRoute({
                token: tokensSourceChain[i],
                amountOutMin: amountOutMins[i],
                route: abi.encode(route)
            });
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
