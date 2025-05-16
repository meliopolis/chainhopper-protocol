// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ChainSettlers} from "../../src/base/ChainSettlers.sol";
import {IMigrator} from "../../src/interfaces/IMigrator.sol";
import {MigrationData} from "../../src/types/MigrationData.sol";
import {MigrationModes} from "../../src/types/MigrationMode.sol";
import {MockMigrator} from "../mocks/MockMigrator.sol";
import {TestContext} from "../utils/TestContext.sol";

contract MigratorTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    uint256[] internal chainIds = [123, 456, 789];
    address[] internal settlers = [address(0x123), address(0x456), address(0x789)];
    bool[] internal isChainSettlerEnabled = [true, true, true];

    MockMigrator internal migrator;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        migrator = new MockMigrator(owner);

        vm.prank(owner);
        migrator.setChainSettlers(chainIds, settlers, isChainSettlerEnabled);
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
        if (token0MatchesRoute) migrator.setDoTokenAndRouteMatch([true]);
        if (isAmountSufficient) migrator.setIsAmountSufficient([true, true]);

        address token0 = token0MatchesRoute ? weth : usdc;
        address token1 = token1MatchesRoute ? weth : usdc;
        uint256 amount0 = amount0NonZero ? 100 : 0;
        uint256 amount1 = amount1NonZero ? 200 : 0;
        migrator.setLiquidity(token0, token1, amount0, amount1);

        IMigrator.MigrationParams memory migrationParams = _mockMigrationParams(1);
        MigrationData memory migrationData = MigrationData(
            block.chainid, address(migrator), 1, MigrationModes.SINGLE, "", migrationParams.settlementParams
        );

        if (!token0MatchesRoute && !token1MatchesRoute) {
            vm.expectRevert(
                abi.encodeWithSelector(IMigrator.TokensAndRoutesMismatch.selector, token0, token1), address(migrator)
            );
        } else if (!isAmountSufficient) {
            vm.expectRevert();
        } else {
            vm.expectEmit(true, true, true, true);
            emit MockMigrator.Log("bridge");

            vm.expectEmit(true, true, true, true);
            emit IMigrator.MigrationStarted(
                migrationData.toId(), 0, chainIds[0], settlers[0], MigrationModes.SINGLE, user, weth, amount0 + amount1
            );
        }

        migrator.migrate(user, 0, abi.encode(migrationParams));
    }

    // dual route

    function test_fuzz_migrate_dualRoute(
        bool token0MatchesRoute,
        bool token1MatchesRoute,
        bool isAmount0Sufficient,
        bool isAmount1Sufficient
    ) public {
        migrator.setDoTokenAndRouteMatch([token0MatchesRoute]);
        migrator.setIsAmountSufficient([isAmount0Sufficient, isAmount1Sufficient]);

        address token0 = token0MatchesRoute ? weth : usdc;
        address token1 = token1MatchesRoute ? usdc : weth;
        uint256 amount0 = isAmount0Sufficient ? (token0MatchesRoute ? 100 : 200) : 0;
        uint256 amount1 = isAmount1Sufficient ? (token1MatchesRoute ? 200 : 100) : 0;
        migrator.setLiquidity(token0, token1, amount0, amount1);

        IMigrator.MigrationParams memory migrationParams = _mockMigrationParams(2);
        bytes memory routesData = abi.encode(
            migrationParams.tokenRoutes[0].token,
            migrationParams.tokenRoutes[1].token,
            migrationParams.tokenRoutes[0].amountOutMin,
            migrationParams.tokenRoutes[1].amountOutMin
        );
        MigrationData memory migrationData = MigrationData(
            block.chainid, address(migrator), 1, MigrationModes.DUAL, routesData, migrationParams.settlementParams
        );

        if (!token0MatchesRoute) {
            vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenAndRouteMismatch.selector, token0), address(migrator));
        } else if (!token1MatchesRoute) {
            vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenAndRouteMismatch.selector, token1), address(migrator));
        } else if (!isAmount0Sufficient) {
            vm.expectRevert();
        } else if (!isAmount1Sufficient) {
            vm.expectRevert();
        } else {
            vm.expectEmit(true, true, true, true);
            emit MockMigrator.Log("bridge");

            vm.expectEmit(true, true, true, true);
            emit MockMigrator.Log("bridge");

            vm.expectEmit(true, true, true, true);
            emit IMigrator.MigrationStarted(
                migrationData.toId(), 0, chainIds[0], settlers[0], MigrationModes.DUAL, user, weth, amount0
            );

            vm.expectEmit(true, true, true, true);
            emit IMigrator.MigrationStarted(
                migrationData.toId(), 0, chainIds[0], settlers[0], MigrationModes.DUAL, user, usdc, amount1
            );
        }

        migrator.migrate(user, 0, abi.encode(migrationParams));
    }
}
