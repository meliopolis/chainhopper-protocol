// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IMigrator} from "../../src/interfaces/IMigrator.sol";
import {MigrationId, MigrationIdLibrary} from "../../src/types/MigrationId.sol";
import {MigrationModes} from "../../src/types/MigrationMode.sol";
import {MockMigrator} from "../mocks/MockMigrator.sol";
import {TestContext} from "../utils/TestContext.sol";
import {ChainSettlers} from "../../src/base/ChainSettlers.sol";

contract MigratorTest is TestContext {
    string constant CHAIN_NAME = "BASE";

    uint32[] private chainIds = [123, 456, 789];
    address[] private settlers = [address(0x123), address(0x456), address(0x789)];
    bool[] private values = [true, true, true];

    MockMigrator migrator;

    function setUp() public {
        _loadChain(CHAIN_NAME);

        migrator = new MockMigrator(owner);

        vm.prank(owner);
        migrator.setChainSettlers(chainIds, settlers, values);
    }

    function _mockTokenRoutes(uint256 count) private view returns (IMigrator.TokenRoute[] memory tokenRoutes) {
        tokenRoutes = new IMigrator.TokenRoute[](count);
        if (count > 0) tokenRoutes[0] = IMigrator.TokenRoute(weth, 100, "");
        if (count > 1) tokenRoutes[1] = IMigrator.TokenRoute(usdc, 200, "");
        if (count > 2) tokenRoutes[2] = IMigrator.TokenRoute(usdt, 300, "");
    }

    function _mockMigrationParams(uint256 tokeRouteCount)
        private
        view
        returns (IMigrator.MigrationParams memory params)
    {
        params = IMigrator.MigrationParams(chainIds[0], settlers[0], _mockTokenRoutes(tokeRouteCount), "");
    }

    // other than single or dual routes

    function test__migrate_fails_ifChainSettlerNotSupported() public {
        bytes memory data = abi.encode(IMigrator.MigrationParams(0, address(0), _mockTokenRoutes(0), ""));

        vm.expectRevert(
            abi.encodeWithSelector(ChainSettlers.ChainSettlerNotSupported.selector, 0, 0), address(migrator)
        );
        migrator.migrate(user, 0, data);
    }

    function test__migrate_fails_ifMissingTokenRoutes() public {
        bytes memory data = abi.encode(_mockMigrationParams(0));

        vm.expectRevert(abi.encodeWithSelector(IMigrator.MissingTokenRoutes.selector), address(migrator));
        migrator.migrate(user, 0, data);
    }

    function test__migrate_fails_ifTooManyTokenRoutes() public {
        bytes memory data = abi.encode(_mockMigrationParams(3));

        vm.expectRevert(abi.encodeWithSelector(IMigrator.TooManyTokenRoutes.selector), address(migrator));
        migrator.migrate(user, 0, data);
    }

    // single route

    function test_fuzz_migrate_singleRoute(
        bool token0MatchesRoute,
        bool token1MatchesRoute,
        bool amount0NonZero,
        bool amount1NonZero,
        bool isAmountSufficient
    ) public {
        vm.assume(!(token0MatchesRoute && token1MatchesRoute));
        if (token0MatchesRoute) migrator.setDoTokenAndRouteMatch([true, true]);
        if (isAmountSufficient) migrator.setIsAmountSufficient([true, true]);

        address token0 = token0MatchesRoute ? weth : usdc;
        address token1 = token1MatchesRoute ? weth : usdc;
        uint256 amount0 = amount0NonZero ? 100 : 0;
        uint256 amount1 = amount1NonZero ? 200 : 0;
        migrator.setLiquidity(token0, token1, amount0, amount1);

        if (!token0MatchesRoute && !token1MatchesRoute) {
            vm.expectRevert(
                abi.encodeWithSelector(IMigrator.TokensAndRoutesMismatch.selector, token0, token1), address(migrator)
            );
        } else if (!isAmountSufficient) {
            vm.expectRevert(
                abi.encodeWithSelector(IMigrator.AmountTooLow.selector, amount0 + amount1, 100), address(migrator)
            );
        } else {
            MigrationId migrationId =
                MigrationIdLibrary.from(uint32(block.chainid), address(migrator), MigrationModes.SINGLE, 1);

            vm.expectEmit(true, true, true, true);
            emit MockMigrator.Log("bridge");

            vm.expectEmit(true, true, true, true);
            emit IMigrator.MigrationStarted(migrationId, 0, weth, user, amount0 + amount1);
        }

        bytes memory data = abi.encode(_mockMigrationParams(1));
        migrator.migrate(user, 0, data);
    }

    // dual route

    function test_fuzz_migrate_dualRoute(
        bool token0MatchesRoute0,
        bool token1MatchesRoute1,
        bool isAmount0Sufficient,
        bool isAmount1Sufficient
    ) public {
        migrator.setDoTokenAndRouteMatch([token0MatchesRoute0, true]);
        migrator.setIsAmountSufficient([isAmount0Sufficient, isAmount1Sufficient]);

        address token0 = token0MatchesRoute0 ? weth : usdc;
        address token1 = token1MatchesRoute1 ? usdc : weth;
        uint256 amount0 = isAmount0Sufficient ? 100 : 0;
        uint256 amount1 = isAmount1Sufficient ? 200 : 0;
        migrator.setLiquidity(token0, token1, amount0, amount1);

        // if (!token0MatchesRoute1 || !token1MatchesRoute0) {
        if (!token0MatchesRoute0) {
            vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenAndRouteMismatch.selector, token0), address(migrator));
        } else if (!token1MatchesRoute1) {
            vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenAndRouteMismatch.selector, token1), address(migrator));
        } else if (!isAmount0Sufficient) {
            vm.expectRevert(abi.encodeWithSelector(IMigrator.AmountTooLow.selector, amount0, 100), address(migrator));
        } else if (!isAmount1Sufficient) {
            vm.expectRevert(abi.encodeWithSelector(IMigrator.AmountTooLow.selector, amount1, 200), address(migrator));
        } else {
            MigrationId migrationId =
                MigrationIdLibrary.from(uint32(block.chainid), address(migrator), MigrationModes.DUAL, 1);

            vm.expectEmit(true, true, true, true);
            emit IMigrator.MigrationStarted(migrationId, 0, weth, user, amount0);
            vm.expectEmit(true, true, true, true);
            emit IMigrator.MigrationStarted(migrationId, 0, usdc, user, amount1);
        }
        // } else {
        //     if (!isAmount0Sufficient) {
        //         vm.expectRevert(
        //             abi.encodeWithSelector(IMigrator.AmountTooLow.selector, amount1, 100), address(migrator)
        //         );
        //     } else if (!isAmount1Sufficient) {
        //         vm.expectRevert(
        //             abi.encodeWithSelector(IMigrator.AmountTooLow.selector, amount0, 200), address(migrator)
        //         );
        //     } else {
        //         MigrationId migrationId =
        //             MigrationIdLibrary.from(uint32(block.chainid), address(migrator), MigrationModes.DUAL, 1);

        //         vm.expectEmit(true, true, true, true);
        //         emit IMigrator.MigrationStarted(migrationId, 0, weth, user, amount1);
        //         vm.expectEmit(true, true, true, true);
        //         emit IMigrator.MigrationStarted(migrationId, 0, usdc, user, amount0);
        //     }
        // }

        bytes memory data = abi.encode(_mockMigrationParams(2));
        migrator.migrate(user, 0, data);
    }
}
