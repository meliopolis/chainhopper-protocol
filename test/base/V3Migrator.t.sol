// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {INonfungiblePositionManager as IPositionManager} from
    "../../src/interfaces/external/INonfungiblePositionManager.sol";
import {IMigrator} from "../../src/interfaces/IMigrator.sol";
import {MockV3Migrator} from "../mocks/MockV3Migrator.sol";

contract V3MigratorTest is Test {
    string constant ENV = "BASE";
    address constant USER = address(0x123);

    MockV3Migrator migrator;
    address private positionManager;
    address private token0;
    address private token1;

    function setUp() public {
        vm.createSelectFork(vm.envString(string(abi.encodePacked(ENV, "_RPC_URL"))));
        positionManager = vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_V3_POSITION_MANAGER")));
        token0 = vm.envAddress(string(abi.encodePacked(ENV, "_WETH")));
        token1 = vm.envAddress(string(abi.encodePacked(ENV, "_USDC")));

        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        migrator = new MockV3Migrator(
            positionManager,
            vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_PERMIT2")))
        );
    }

    function test_onERC721Received_Fails_IfNotFromPoolManager() public {
        vm.expectRevert(abi.encodeWithSelector(IMigrator.NotPositionManager.selector));

        vm.prank(USER);
        migrator.onERC721Received(address(0), address(0), 0, "");
    }

    function test_onERC721Received_Succeeds() public {
        vm.prank(positionManager);
        migrator.onERC721Received(address(0), address(0), 0, "");
    }

    function test__liquidate_Succeeds() public {
        deal(token0, address(this), 1e18);
        deal(token1, address(this), 1e10);

        IERC20(token0).approve(positionManager, 1e18);
        IERC20(token1).approve(positionManager, 1e10);

        (uint256 positionId,,,) = IPositionManager(positionManager).mint(
            IPositionManager.MintParams(
                token0, token1, 500, -600, 600, 1e18, 1e10, 0, 0, address(migrator), block.timestamp
            )
        );

        assertGt(positionId, 0);

        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(address(migrator), address(0), positionId);

        (address _token0, address _token1, uint256 amount0, uint256 amount1,) = migrator.liquidate(positionId);

        assertEq(token0, _token0);
        assertEq(token1, _token1);
        assertGt(amount0 + amount1, 0);
    }

    function test__swap_Fails_IfAmountOtherMinNotMet() public {
        deal(token0, address(migrator), 1e18);

        vm.expectRevert();
        migrator.swap(abi.encode(token0, token1, uint24(500)), true, 1e18, type(uint256).max);
    }

    function test__swap_Succeeds() public {
        deal(token0, address(migrator), 1e18);

        uint256 amountOut = migrator.swap(abi.encode(token0, token1, uint24(500)), true, 1e18, 0);

        assertGt(amountOut, 0);
    }
}
