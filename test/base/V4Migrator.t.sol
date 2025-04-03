// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {Test} from "@forge-std/Test.sol";
// import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
// import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
// import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
// import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
// import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
// import {StateLibrary} from "@uniswap-v4-core/libraries/StateLibrary.sol";
// import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";
// import {Currency} from "@uniswap-v4-core/types/Currency.sol";
// import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
// import {IPositionManager} from "@uniswap-v4-periphery/interfaces/IPositionManager.sol";
// import {Actions} from "@uniswap-v4-periphery/libraries/Actions.sol";
// import {LiquidityAmounts} from "@uniswap-v4-periphery/libraries/LiquidityAmounts.sol";
// import {IMigrator} from "../../src/interfaces/IMigrator.sol";
// import {MockV4Migrator} from "../mocks/MockV4Migrator.sol";

// contract V4MigratorTest is Test {
//     using StateLibrary for IPoolManager;

//     string constant ENV = "BASE";
//     address constant USER = address(0x123);

//     MockV4Migrator migrator;
//     address private positionManager;
//     address private permit2;
//     address private token0;
//     address private token1;

//     function setUp() public {
//         vm.createSelectFork(vm.envString(string(abi.encodePacked(ENV, "_RPC_URL"))));
//         positionManager = vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_V4_POSITION_MANAGER")));
//         permit2 = vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_PERMIT2")));
//         token0 = vm.envAddress(string(abi.encodePacked(ENV, "_WETH")));
//         token1 = vm.envAddress(string(abi.encodePacked(ENV, "_USDC")));

//         (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

//         migrator = new MockV4Migrator(
//             positionManager, vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_UNIVERSAL_ROUTER"))), permit2
//         );
//     }

//     function test_onERC721Received_Fails_IfNotFromPoolManager() public {
//         vm.expectRevert(abi.encodeWithSelector(IMigrator.NotPositionManager.selector));

//         vm.prank(USER);
//         migrator.onERC721Received(address(0), address(0), 0, "");
//     }

//     function test_onERC721Received_Succeeds() public {
//         vm.prank(positionManager);
//         migrator.onERC721Received(address(0), address(0), 0, "");
//     }

//     function test__liquidate_Succeeds() public {
//         deal(token0, address(this), 1e18);
//         deal(token1, address(this), 1e10);

//         IERC20(token0).approve(address(permit2), 1e18);
//         IPermit2(permit2).approve(token0, address(positionManager), uint160(1e18), 0);
//         IERC20(token1).approve(address(permit2), 1e10);
//         IPermit2(permit2).approve(token1, address(positionManager), uint160(1e10), 0);

//         PoolKey memory poolKey = PoolKey(Currency.wrap(token0), Currency.wrap(token1), 500, 10, IHooks(address(0)));
//         (uint160 sqrtPriceX96,,,) = IPositionManager(positionManager).poolManager().getSlot0(poolKey.toId());
//         uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
//             sqrtPriceX96, TickMath.getSqrtPriceAtTick(-600), TickMath.getSqrtPriceAtTick(600), 1e18, 1e10
//         );

//         uint256 positionId = IPositionManager(positionManager).nextTokenId();

//         assertGt(positionId, 0);

//         bytes memory actions =
//             abi.encodePacked(bytes1(uint8(Actions.MINT_POSITION)), bytes1(uint8(Actions.SETTLE_PAIR)));
//         bytes[] memory _params = new bytes[](2);
//         _params[0] = abi.encode(poolKey, -600, 600, liquidity, 1e18, 1e10, address(migrator), "");
//         _params[1] = abi.encode(Currency.wrap(token0), Currency.wrap(token1));
//         IPositionManager(positionManager).modifyLiquidities(abi.encode(actions, _params), block.timestamp);

//         vm.expectEmit(true, true, true, true);
//         emit IERC721.Transfer(address(migrator), address(0), positionId);

//         (address _token0, address _token1, uint256 amount0, uint256 amount1,) = migrator.liquidate(positionId, 0, 0);

//         assertEq(token0, _token0);
//         assertEq(token1, _token1);
//         assertGt(amount0 + amount1, 0);
//     }

//     function test__swap_Fails_IfAmountOtherMinNotMet() public {
//         deal(token0, address(migrator), 1e18);

//         vm.expectRevert();
//         migrator.swap(abi.encode(token0, token1, uint24(500), int24(10), address(0)), true, 1e18, type(uint256).max);
//     }

//     function test__swap_Succeeds() public {
//         deal(token0, address(migrator), 1e18);

//         uint256 amountOut = migrator.swap(abi.encode(token0, token1, uint24(500), int24(10), address(0)), true, 1e18, 0);

//         assertGt(amountOut, 0);
//     }
// }
