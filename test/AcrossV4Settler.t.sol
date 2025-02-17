// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {AcrossV4Settler} from "../src/AcrossV4Settler.sol";
import {AcrossSettler} from "../src/base/AcrossSettler.sol";
import {IV4Settler} from "../src/interfaces/IV4Settler.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {AcrossV4SettlerHarness} from "./mocks/AcrossV4SettlerHarness.sol";
// import {IUniswapV3Factory} from "lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
// import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
// import {IUniswapV3PoolEvents} from "lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IWETH} from "../src/interfaces/external/IWETH.sol";
// import {INonfungiblePositionManager} from "src/interfaces/external/INonfungiblePositionManager.sol";
// import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IHooks} from "../src/interfaces/external/IUniswapV4.sol";
import {IPoolManager} from "../src/interfaces/external/IUniswapV4.sol";
import {IPositionManager} from "../src/interfaces/external/IUniswapV4.sol";
import {Currency, PoolKey, PoolId, StateLibrary} from "../src/libraries/UniswapV4Library.sol";

contract AcrossV4SettlerTest is Test {
    using StateLibrary for IPoolManager;

    AcrossV4SettlerHarness public acrossV4SettlerHarness;
    AcrossV4Settler public acrossV4Settler;
    address public nftPositionManager = vm.envAddress("BASE_V4_POSITION_MANAGER");
    address public baseToken = vm.envAddress("BASE_WETH");
    address public spokePool = vm.envAddress("BASE_SPOKE_POOL");
    address public swapRouter = vm.envAddress("BASE_UNIVERSAL_ROUTER");
    address public cbeth = vm.envAddress("BASE_CBETH");
    address public usdc = vm.envAddress("BASE_USDC");
    address public permit2 = vm.envAddress("BASE_PERMIT2");
    address public user = address(0x5);
    address public senderWallet = address(0x2);
    address public owner = address(0x3);
    address public weth = address(0x4200000000000000000000000000000000000006); // sorts before baseToken
    address public protocolFeeRecipient = address(0x3ee);

    enum Range {
        InRange,
        BelowTick,
        AboveTick
    }

    function generateSettlementParams(
        address token0,
        address token1,
        uint24 feeTier,
        int24 tickSpacing,
        address hooks,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Min,
        uint256 amount1Min,
        uint24 senderFeeBps,
        address senderFeeRecipient,
        bytes32 migrationId
    ) public view returns (bytes memory) {
        return abi.encode(
            migrationId,
            abi.encode(
                IV4Settler.V4SettlementParams({
                    recipient: user,
                    token0: token0,
                    token1: token1,
                    feeTier: feeTier,
                    tickSpacing: tickSpacing,
                    hooks: hooks,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    senderFeeBps: senderFeeBps,
                    senderFeeRecipient: senderFeeRecipient
                })
            )
        );
    }

    function generateSettlementParams(
        uint256 amount0Min,
        uint256 amount1Min,
        int24 currentTick,
        Range range,
        bool token0BaseToken,
        bytes32 migrationId
    ) public view returns (bytes memory) {
        int24 tickLower;
        int24 tickUpper;

        if (range == Range.InRange) {
            tickLower = (currentTick - 30000) / 30000 * 30000;
            tickUpper = (currentTick + 30000) / 30000 * 30000;
        } else if (range == Range.BelowTick) {
            tickLower = (currentTick - 60000) / 30000 * 30000;
            tickUpper = (currentTick - 30000) / 30000 * 30000;
        } else {
            tickLower = (currentTick + 30000) / 30000 * 30000;
            tickUpper = (currentTick + 60000) / 30000 * 30000;
        }

        address token0 = token0BaseToken ? address(0) : cbeth;
        address token1 = token0BaseToken ? usdc : weth;

        uint24 feeTier = baseToken == token0 ? 3000 : 500;
        int24 tickSpacing = baseToken == token0 ? int24(100) : int24(10);
        address hooks = baseToken == token0 ? address(0xC15F260357D542334605E7A949a504f8e3fC8aC0) : address(0);

        return this.generateSettlementParams(
            token0,
            token1,
            feeTier,
            tickSpacing,
            hooks,
            tickLower,
            tickUpper,
            amount0Min,
            amount1Min,
            15,
            senderWallet,
            migrationId
        );
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 26400200);
        vm.startPrank(owner);
        acrossV4SettlerHarness = new AcrossV4SettlerHarness(
            spokePool, protocolFeeRecipient, 10, 25, swapRouter, nftPositionManager, baseToken, permit2
        );
        acrossV4Settler = new AcrossV4Settler(
            spokePool, protocolFeeRecipient, 10, 25, swapRouter, nftPositionManager, baseToken, permit2
        );
        vm.stopPrank();
    }

    /*
     * Getters
     */

    function test__getSenderFeesReturnsCorrectValues() public view {
        (uint24 senderFeeBps, address senderFeeRecipient) = acrossV4SettlerHarness.exposed_getSenderFees(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0))
        );
        assertEq(senderFeeBps, 15);
        assertEq(senderFeeRecipient, senderWallet);
    }

    function test__getRecipientReturnsCorrectValue() public view {
        address recipient = acrossV4SettlerHarness.exposed_getRecipient(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0))
        );
        assertEq(recipient, user);
    }

    /*
     * Handle V3 Across Message
     */

    function test_handleV4AcrossMessage_msgSenderIsNotSpokePool() public {
        vm.prank(user);
        vm.expectRevert(AcrossSettler.NotSpokePool.selector);
        acrossV4Settler.handleV3AcrossMessage(baseToken, 100, address(0), new bytes(0));
    }

    // TODO:
    // function test_handleV4AcrossMessage_triggersCatch_withNoMigrationId() public {
    //     uint256 userBalanceBefore = IERC20(baseToken).balanceOf(user);
    //     deal(baseToken, address(acrossV4Settler), 1 ether);
    //     // invalid settlement params for above tick
    //     bytes memory migrationIdAndSettlementParams =
    //         this.generateSettlementParams(0, 1_000_000_000, -200000, Range.AboveTick, true, bytes32(0));
    //     vm.prank(spokePool);
    //     vm.expectEmit(true, true, false, false, address(baseToken));
    //     emit IERC20.Transfer(address(acrossV4Settler), user, 1 ether);
    //     acrossV4Settler.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);
    //     assertEq(IERC20(baseToken).balanceOf(user), userBalanceBefore + 1 ether);
    // }

    function test_handleV3AcrossMessage_triggersCatchAndRefundsBothTokens_withMigrationId() public {
        uint256 userBalanceBefore = IERC20(baseToken).balanceOf(user);
        uint256 userBalanceBeforeUSDC = IERC20(usdc).balanceOf(user);
        deal(baseToken, address(acrossV4Settler), 1 ether);
        deal(usdc, address(acrossV4Settler), 1_500_000_000);
        // invalid settlement params for above tick
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 1_000_000_000, -200000, Range.AboveTick, true, bytes32("111"));
        vm.prank(spokePool);
        acrossV4Settler.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);
        (address token, uint256 amount, IV4Settler.V4SettlementParams memory settlementParams) =
            acrossV4Settler.partialSettlements(bytes32("111"));
        assertEq(token, baseToken);
        assertEq(amount, 1 ether);
        assertEq(settlementParams.recipient, user);
        bytes memory migrationIdAndSettlementParamsChanged =
            this.generateSettlementParams(0, 1_000_000, -200000, Range.AboveTick, true, bytes32("111"));
        vm.prank(spokePool);
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(acrossV4Settler), user, 1_500_000_000);
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(acrossV4Settler), user, 1 ether);
        acrossV4Settler.handleV3AcrossMessage(usdc, 1_500_000_000, address(0), migrationIdAndSettlementParamsChanged);
        assertEq(IERC20(baseToken).balanceOf(user), userBalanceBefore + 1 ether);
        assertEq(IERC20(usdc).balanceOf(user), userBalanceBeforeUSDC + 1_500_000_000);
    }

    // function test_handleV3AcrossMessageWorks() public {
    //     // deal baseToken to settler
    //     deal(baseToken, address(acrossV4Settler), 1.1 ether); // slightly higher due to fees

    //     // get pool
    //     IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
    //     IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
    //     (, int24 currentTick,,,,,) = pool.slot0();

    //     // generate settlement params
    //     bytes memory migrationIdAndSettlementParams =
    //         this.generateSettlementParams(0.5 ether, 1_500_000_000, currentTick, Range.InRange, true, bytes32(0));

    //     vm.prank(spokePool);
    //     acrossV4Settler.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);
    // }

    /*
     * Helper tests
     */

    function test__refund_removesPartialSettlement() public {
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);
        // add a partial settlement
        bytes32 migrationId = bytes32("111");
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, migrationId);
        acrossV4SettlerHarness.exposed_settle(baseToken, 0.5 ether, migrationIdAndSettlementParams);
        // verify partial settlement was added
        (address token, uint256 amount, IV4Settler.V4SettlementParams memory settlementParams) =
            acrossV4SettlerHarness.partialSettlements(migrationId);
        assertEq(token, baseToken);
        assertEq(amount, 0.5 ether);
        assertEq(settlementParams.recipient, user);

        // refund it
        acrossV4SettlerHarness.exposed_refund(migrationId);
        // check that it's removed
        (address token1, uint256 amount1, IV4Settler.V4SettlementParams memory settlementParams1) =
            acrossV4SettlerHarness.partialSettlements(migrationId);
        assertEq(token1, address(0));
        assertEq(amount1, 0);
        assertEq(settlementParams1.recipient, address(0));
    }

    function test_compareSettlementParams_returnsTrueIfSame() public view {
        (, bytes memory message) = abi.decode(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0)),
            (bytes32, bytes)
        );
        (IV4Settler.V4SettlementParams memory a) = abi.decode(message, (IV4Settler.V4SettlementParams));
        (, bytes memory message2) = abi.decode(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0)),
            (bytes32, bytes)
        );
        (IV4Settler.V4SettlementParams memory b) = abi.decode(message2, (IV4Settler.V4SettlementParams));
        assertEq(acrossV4Settler.compareSettlementParams(a, b), true);
    }

    function test_compareSettlementParams_returnsFalseIfDifferent() public view {
        (, bytes memory message) = abi.decode(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0)),
            (bytes32, bytes)
        );
        (IV4Settler.V4SettlementParams memory a) = abi.decode(message, (IV4Settler.V4SettlementParams));
        (, bytes memory message2) = abi.decode(
            this.generateSettlementParams(0.5 ether, 1_400_000_000, 0, Range.InRange, true, bytes32(0)),
            (bytes32, bytes)
        );
        (IV4Settler.V4SettlementParams memory b) = abi.decode(message2, (IV4Settler.V4SettlementParams));
        assertEq(acrossV4Settler.compareSettlementParams(a, b), false);
    }

    /*
     * Single token tests
     */

    function test__settleFailsIfBothAmountsAreZero() public {
        deal(baseToken, address(acrossV4Settler), 1 ether);
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 0, -200000, Range.InRange, true, bytes32(0));
        vm.expectRevert(ISettler.AtLeastOneAmountMustBeGreaterThanZero.selector);
        acrossV4Settler.settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settleFailsIfBridgedTokenIsNotUsedInPosition() public {
        deal(baseToken, address(acrossV4Settler), 1 ether);
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1 ether, -200000, Range.InRange, true, bytes32(0));
        vm.expectRevert(AcrossSettler.BridgedTokenMustBeUsedInPosition.selector);
        acrossV4Settler.settle(address(0x4), 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token0ReceivedAndPositionInRange() public {
        // inject liquidity
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(cbeth),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        _mintFullRangeLiquidity(poolKey, 1e24, 1e24);

        // deal baseToken to settler
        deal(cbeth, address(acrossV4SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get current tick
        IPoolManager poolManager = IPositionManager(nftPositionManager).poolManager();
        (, int24 currentTick,,) = poolManager.getSlot0(poolKey.toId());

        // uint128 liquidity = poolManager.getLiquidity(poolKey.toId());
        // console.log("Liquidity: %d", liquidity);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0.5 ether, 1_500_000_000, currentTick, Range.InRange, false, bytes32(0));

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(swapRouter), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(swapRouter), address(poolManager), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(poolManager), address(acrossV4SettlerHarness), 0);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        acrossV4SettlerHarness.exposed_settle(cbeth, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token0ReceivedAndPositionBelowTick() public {
        // inject liquidity
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(cbeth),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        _mintFullRangeLiquidity(poolKey, 1e24, 1e24);

        // deal baseToken to settler
        deal(cbeth, address(acrossV4SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get current tick
        IPoolManager poolManager = IPositionManager(nftPositionManager).poolManager();
        (, int24 currentTick,,) = poolManager.getSlot0(poolKey.toId());

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 1 ether, currentTick, Range.BelowTick, false, bytes32(0));

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(swapRouter), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(swapRouter), address(poolManager), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(poolManager), address(acrossV4SettlerHarness), 0);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        acrossV4SettlerHarness.exposed_settle(cbeth, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token0ReceivedAndPositionAboveTick() public {
        // inject liquidity
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(cbeth),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        _mintFullRangeLiquidity(poolKey, 1e24, 1e24);

        // deal baseToken to settler
        deal(cbeth, address(acrossV4SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get current tick
        IPoolManager poolManager = IPositionManager(nftPositionManager).poolManager();
        (, int24 currentTick,,) = poolManager.getSlot0(poolKey.toId());

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 0, currentTick, Range.AboveTick, false, bytes32(0));

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        acrossV4SettlerHarness.exposed_settle(cbeth, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token1ReceivedAndPositionInRange() public {
        // inject liquidity
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(cbeth),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        _mintFullRangeLiquidity(poolKey, 1e24, 1e24);

        // deal baseToken to settler
        deal(weth, address(acrossV4SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get current tick
        IPoolManager poolManager = IPositionManager(nftPositionManager).poolManager();
        (, int24 currentTick,,) = poolManager.getSlot0(poolKey.toId());

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0.5 ether, 0.5 ether, currentTick, Range.InRange, false, bytes32(0));

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(swapRouter), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(swapRouter), address(poolManager), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(poolManager), address(acrossV4SettlerHarness), 0);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        acrossV4SettlerHarness.exposed_settle(weth, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token1ReceivedAndPositionBelowTick() public {
        // inject liquidity
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(cbeth),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        _mintFullRangeLiquidity(poolKey, 1e24, 1e24);

        // deal baseToken to settler
        deal(weth, address(acrossV4SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get current tick
        IPoolManager poolManager = IPositionManager(nftPositionManager).poolManager();
        (, int24 currentTick,,) = poolManager.getSlot0(poolKey.toId());

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 1 ether, currentTick, Range.BelowTick, false, bytes32(0));

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        acrossV4SettlerHarness.exposed_settle(weth, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token1ReceivedAndPositionAboveTick() public {
        // inject liquidity
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(cbeth),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        _mintFullRangeLiquidity(poolKey, 1e24, 1e24);

        // deal baseToken to settler
        deal(weth, address(acrossV4SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get current tick
        IPoolManager poolManager = IPositionManager(nftPositionManager).poolManager();
        (, int24 currentTick,,) = poolManager.getSlot0(poolKey.toId());

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 0, currentTick, Range.AboveTick, false, bytes32(0));

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(swapRouter), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(swapRouter), address(poolManager), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(poolManager), address(acrossV4SettlerHarness), 0);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        acrossV4SettlerHarness.exposed_settle(weth, 1 ether, migrationIdAndSettlementParams);
    }

    /*
     * Dual token tests
     */

    function test__settle_migrationId_token0Received() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal baseToken to settler
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_migrationId_token1Received() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal usdc to settler
        deal(usdc, address(acrossV4SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV4SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test__settle_migrationId_token0Received_token1Received_BridgedTokenNotUsedInPosition() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);
        deal(cbeth, address(acrossV4SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Bridged token ont used in position
        vm.expectRevert(AcrossSettler.BridgedTokenMustBeUsedInPosition.selector);

        acrossV4SettlerHarness.exposed_settle(cbeth, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test__settle_migrationId_token1Received_token0Received_BridgedTokenNotUsedInPosition() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(cbeth, address(acrossV4SettlerHarness), 1_000_000_000);
        deal(usdc, address(acrossV4SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV4SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);

        // Bridged token ont used in position
        vm.expectRevert(AcrossSettler.BridgedTokenMustBeUsedInPosition.selector);

        acrossV4SettlerHarness.exposed_settle(cbeth, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_token0ReceivedTwice_BridgedTokensMustBeDifferent() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal base token to settler
        deal(baseToken, address(acrossV4SettlerHarness), 2 ether);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Bridged token must be different
        vm.expectRevert(AcrossSettler.BridgedTokensMustBeDifferent.selector);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_token1ReceivedTwice_BridgedTokensMustBeDifferent() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal usdc to settler
        deal(usdc, address(acrossV4SettlerHarness), 2_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV4SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);

        // Bridged token must be different
        vm.expectRevert(AcrossSettler.BridgedTokensMustBeDifferent.selector);

        acrossV4SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test__settle_migrationId_token0Received_token1Received_SettlementParamsMismatch() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);
        deal(usdc, address(acrossV4SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams1 =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);
        bytes memory migrationIdAndSettlementParams2 =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.BelowTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams1);

        // Settlement params do not match
        vm.expectRevert(IV4Settler.SettlementParamsDoNotMatch.selector);

        acrossV4SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams2);
    }

    function test__settle_migrationId_token1Received_token0Received_SettlementParamsMismatch() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);
        deal(usdc, address(acrossV4SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams1 =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);
        bytes memory migrationIdAndSettlementParams2 =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.BelowTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV4SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams1);

        // Settlement params do not match
        vm.expectRevert(IV4Settler.SettlementParamsDoNotMatch.selector);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams2);
    }

    function test_settle_migrationId_mintFailure_token0Received_token1Received() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);
        deal(usdc, address(acrossV4SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams = generateSettlementParams(
            baseToken, usdc, 0, 0, address(0), 0, 0, 1 ether, 1_000_000_000, 0, address(0), migrationId
        );

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Refund bridged token to recipient
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(acrossV4SettlerHarness), user, 1_000_000_000);

        // Refund partial settlement token to recipient
        vm.expectEmit(true, true, false, true, address(baseToken));
        emit IERC20.Transfer(address(acrossV4SettlerHarness), user, 1 ether);

        vm.prank(spokePool);
        acrossV4SettlerHarness.handleV3AcrossMessage(usdc, 1_000_000_000, address(0), migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintFailure_token1Received_token0Received() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);
        deal(usdc, address(acrossV4SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams = generateSettlementParams(
            baseToken, usdc, 0, 0, address(0), 0, 0, 1 ether, 1_000_000_000, 0, address(0), migrationId
        );

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV4SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);

        // Refund bridged token to recipient
        vm.expectEmit(true, true, false, true, address(baseToken));
        emit IERC20.Transfer(address(acrossV4SettlerHarness), user, 1 ether);

        // Refund partial settlement token to recipient
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(acrossV4SettlerHarness), user, 1_000_000_000);

        vm.prank(spokePool);
        acrossV4SettlerHarness.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintSuccess_token0Received_token1Received_bothFeesNonZero() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);
        deal(usdc, address(acrossV4SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Settled
        vm.expectEmit(true, true, false, false, weth);
        emit IWETH.Withdrawal(address(acrossV4SettlerHarness), 9.975e17);

        vm.expectEmit(true, true, false, false, nftPositionManager);
        emit IERC721.Transfer(address(0), user, 0);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), user, 9.975e8);

        vm.expectEmit(true, true, false, true, baseToken);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), protocolFeeRecipient, 1.375e15);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), protocolFeeRecipient, 1.375e6);

        vm.expectEmit(true, true, false, true, baseToken);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), senderWallet, 1.125e15);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), senderWallet, 1.125e6);

        acrossV4SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintSuccess_token0Received_token1Received_bothFeesZero() public {
        bytes32 migrationId = keccak256("migrationId");

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(cbeth),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        IPoolManager poolManager = IPositionManager(nftPositionManager).poolManager();
        (, int24 tick,,) = poolManager.getSlot0(poolKey.toId());

        vm.startPrank(owner);
        acrossV4SettlerHarness.setProtocolFeeBps(0);
        acrossV4SettlerHarness.setProtocolShareOfSenderFeeInPercent(0);
        vm.stopPrank();

        // deal tokens to settler
        deal(cbeth, address(acrossV4SettlerHarness), 1 ether);
        deal(weth, address(acrossV4SettlerHarness), 1 ether);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams = this.generateSettlementParams(
            cbeth, weth, 500, 10, address(0), tick + 30000, tick + 60000, 1 ether, 1 ether, 0, address(0), migrationId
        );

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, cbeth, 1 ether);

        acrossV4SettlerHarness.exposed_settle(cbeth, 1 ether, migrationIdAndSettlementParams);

        // Settled
        vm.expectEmit(true, true, false, false, cbeth);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 1 ether);

        vm.expectEmit(true, true, false, false, weth);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 1 ether);

        vm.expectEmit(true, true, false, false, nftPositionManager);
        emit IERC721.Transfer(address(0), user, 0);

        vm.expectEmit(true, true, false, true, weth);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), user, 1 ether);

        acrossV4SettlerHarness.exposed_settle(weth, 1 ether, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintSuccess_token0Received_token1Received_OnlyProtocolFee() public {
        bytes32 migrationId = keccak256("migrationId");

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(cbeth),
            currency1: Currency.wrap(weth),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        IPoolManager poolManager = IPositionManager(nftPositionManager).poolManager();
        (, int24 tick,,) = poolManager.getSlot0(poolKey.toId());

        // deal tokens to settler
        deal(cbeth, address(acrossV4SettlerHarness), 1 ether);
        deal(weth, address(acrossV4SettlerHarness), 1 ether);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams = this.generateSettlementParams(
            cbeth, weth, 500, 10, address(0), tick + 30000, tick + 60000, 1 ether, 1 ether, 0, address(0), migrationId
        );

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, cbeth, 1 ether);

        acrossV4SettlerHarness.exposed_settle(cbeth, 1 ether, migrationIdAndSettlementParams);

        // Settled
        vm.expectEmit(true, true, false, false, cbeth);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 9.99e17);

        vm.expectEmit(true, true, false, false, weth);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 9.99e17);

        vm.expectEmit(true, true, false, false, nftPositionManager);
        emit IERC721.Transfer(address(0), user, 0);

        vm.expectEmit(true, true, false, true, weth);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), user, 9.99e17);

        vm.expectEmit(true, true, false, true, cbeth);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), protocolFeeRecipient, 1e15);

        vm.expectEmit(true, true, false, true, weth);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), protocolFeeRecipient, 1e15);

        acrossV4SettlerHarness.exposed_settle(weth, 1 ether, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintSuccess_token0Received_token1Received_OnlySenderFee() public {
        bytes32 migrationId = keccak256("migrationId");
        IPoolManager poolManager = IPositionManager(nftPositionManager).poolManager();

        vm.startPrank(owner);
        acrossV4SettlerHarness.setProtocolFeeBps(0);
        acrossV4SettlerHarness.setProtocolShareOfSenderFeeInPercent(0);
        vm.stopPrank();

        // deal tokens to settler
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);
        deal(usdc, address(acrossV4SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Settled
        vm.expectEmit(true, true, false, false, usdc);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), address(poolManager), 9.985e8);

        vm.expectEmit(true, true, false, false, nftPositionManager);
        emit IERC721.Transfer(address(0), user, 0);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), user, 9.985e8);

        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), senderWallet, 1.5e15);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV4SettlerHarness), senderWallet, 1.5e6);

        acrossV4SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test_withdraw() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal baseToken to settler
        deal(baseToken, address(acrossV4SettlerHarness), 1 ether);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 0, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV4SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Refund to recipient
        vm.expectEmit(true, true, false, true, address(baseToken));
        emit IERC20.Transfer(address(acrossV4SettlerHarness), user, 1 ether);

        acrossV4SettlerHarness.withdraw(migrationId);
    }

    function _mintFullRangeLiquidity(PoolKey memory poolKey, uint128 amount0, uint128 amount1) internal {
        bytes32 migrationId = keccak256("migrationId");

        address token0 = Currency.unwrap(poolKey.currency0);
        if (token0 == address(0)) token0 = baseToken;
        address token1 = Currency.unwrap(poolKey.currency1);

        // deal tokens to settler
        if (token0 == baseToken) deal(token0, amount0);
        deal(token0, address(acrossV4SettlerHarness), amount0);
        deal(token1, address(acrossV4SettlerHarness), amount1);

        bytes memory migrationIdAndSettlementParams = this.generateSettlementParams(
            token0 == baseToken ? address(0) : token0,
            token1,
            poolKey.fee,
            poolKey.tickSpacing,
            address(poolKey.hooks),
            -887272 / poolKey.tickSpacing * poolKey.tickSpacing,
            887272 / poolKey.tickSpacing * poolKey.tickSpacing,
            amount0,
            amount1,
            15,
            senderWallet,
            migrationId
        );

        acrossV4SettlerHarness.exposed_settle(token0, amount0, migrationIdAndSettlementParams);
        acrossV4SettlerHarness.exposed_settle(token1, amount1, migrationIdAndSettlementParams);
    }
}
