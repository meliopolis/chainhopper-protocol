// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {V3SpokePoolInterface as IAcrossSpokePool} from "@across/interfaces/V3SpokePoolInterface.sol";
import {IAcrossMigrator} from "../../src/interfaces/IAcrossMigrator.sol";
import {IMigrator} from "../../src/interfaces/IMigrator.sol";
import {MockAcrossMigrator} from "../mocks/MockAcrossMigrator.sol";
import {TestContext} from "../utils/TestContext.sol";

contract AcrossMigratorTest is TestContext {
    string constant CHAIN_NAME = "BASE";

    MockAcrossMigrator private migrator;

    function setUp() public {
        _loadChain(CHAIN_NAME);

        migrator = new MockAcrossMigrator(owner, acrossSpokePool, weth);
    }

    function test_fuzz_bridge(uint256 amount, IAcrossMigrator.Route memory route, bool isTokenNative) public {
        vm.assume(amount < type(uint128).max);
        vm.assume(route.maxFees <= amount);
        route.fillDeadlineOffset = 0;
        route.exclusivityDeadline = 0;
        route.quoteTimestamp = uint32(block.timestamp);

        address token;
        address inputToken = weth;
        if (isTokenNative) {
            token = address(0);
            deal(address(migrator), amount);
        } else {
            token = address(1);
            deal(inputToken, address(migrator), amount);
        }

        if (!isTokenNative) {
            vm.expectEmit(true, true, true, true, inputToken);
            emit IERC20.Approval(address(migrator), acrossSpokePool, amount);
            vm.expectEmit(true, true, true, true, inputToken);
            emit IERC20.Transfer(address(migrator), acrossSpokePool, amount);
        }
        vm.expectEmit(true, false, true, false, acrossSpokePool);
        emit IAcrossSpokePool.FundsDeposited(
            bytes32(0), bytes32(0), 0, 0, 1, 0, 0, 0, 0, bytes32(uint256(uint160(user))), 0, 0, ""
        );
        if (!isTokenNative) {
            vm.expectEmit(true, true, true, true, inputToken);
            emit IERC20.Approval(address(migrator), acrossSpokePool, 0);
        }

        migrator.bridge(user, 1, address(0), token, amount, inputToken, abi.encode(route), "");
    }

    function test_fuzz_matchTokenWithRoute(
        IMigrator.TokenRoute memory tokenRoute,
        bool isTokenNative,
        bool isRouteTokenWeth,
        bool areTokensEqual
    ) public view {
        vm.assume(!(isTokenNative && isRouteTokenWeth && areTokensEqual));
        address token = isTokenNative ? address(0) : address(1);
        tokenRoute.token = isRouteTokenWeth ? weth : usdc;
        if (areTokensEqual) {
            isTokenNative ? tokenRoute.token = token : token = tokenRoute.token;
        }

        bool misMatch = !areTokensEqual && (!isTokenNative || !isRouteTokenWeth);
        assertEq(migrator.matchTokenWithRoute(token, tokenRoute), !misMatch);
    }

    function test_fuzz_isAmountSufficient(
        uint256 amount,
        IMigrator.TokenRoute memory tokenRoute,
        IAcrossMigrator.Route memory route
    ) public view {
        vm.assume(tokenRoute.amountOutMin < type(uint256).max - route.maxFees);
        tokenRoute.route = abi.encode(route);

        bool insufficient = amount < tokenRoute.amountOutMin + route.maxFees;
        assertEq(migrator.isAmountSufficient(amount, tokenRoute), !insufficient);
    }
}
