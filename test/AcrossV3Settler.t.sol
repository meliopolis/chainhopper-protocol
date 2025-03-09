// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "@forge-std/Test.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {AcrossV3Settler} from "../src/AcrossV3Settler.sol";
import {AcrossSettler} from "../src/base/AcrossSettler.sol";
import {IV3Settler} from "../src/interfaces/IV3Settler.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {AcrossV3SettlerHarness} from "./mocks/AcrossV3SettlerHarness.sol";
import {IUniswapV3Factory} from "lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolEvents} from "lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol";
import {INonfungiblePositionManager} from "src/interfaces/external/INonfungiblePositionManager.sol";

contract AcrossV3SettlerTest is Test {
    AcrossV3SettlerHarness public acrossV3SettlerHarness;
    AcrossV3Settler public acrossV3Settler;
    address public nftPositionManager = vm.envAddress("BASE_NFT_POSITION_MANAGER");
    address public baseToken = vm.envAddress("BASE_WETH");
    address public spokePool = vm.envAddress("BASE_SPOKE_POOL");
    address public swapRouter = vm.envAddress("BASE_SWAP_ROUTER");
    address public usdc = vm.envAddress("BASE_USDC");
    address public user = address(0x1);
    address public senderWallet = address(0x2);
    address public owner = address(0x3);
    address public virtualToken = address(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b); // sorts before baseToken
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
                IV3Settler.V3SettlementParams({
                    recipient: user,
                    token0: token0,
                    token1: token1,
                    feeTier: feeTier,
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

        address token0 = token0BaseToken ? address(baseToken) : address(virtualToken);
        address token1 = token0BaseToken ? address(usdc) : address(baseToken);

        uint24 feeTier = baseToken == token0 ? 500 : 3000;
        return this.generateSettlementParams(
            token0, token1, feeTier, tickLower, tickUpper, amount0Min, amount1Min, 15, senderWallet, migrationId
        );
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);
        vm.startPrank(owner);
        acrossV3SettlerHarness =
            new AcrossV3SettlerHarness(spokePool, protocolFeeRecipient, 10, 25, swapRouter, nftPositionManager);
        acrossV3Settler = new AcrossV3Settler(spokePool, protocolFeeRecipient, 10, 25, swapRouter, nftPositionManager);
        vm.stopPrank();
    }

    /*
     * Getters
     */

    function test__getSenderFeesReturnsCorrectValues() public view {
        (uint24 senderFeeBps, address senderFeeRecipient) = acrossV3SettlerHarness.exposed_getSenderFees(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0))
        );
        assertEq(senderFeeBps, 15);
        assertEq(senderFeeRecipient, senderWallet);
    }

    function test__getRecipientReturnsCorrectValue() public view {
        address recipient = acrossV3SettlerHarness.exposed_getRecipient(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0))
        );
        assertEq(recipient, user);
    }

    /*
    * Handle V3 Across Message
    */

    function test_handleV3AcrossMessage_msgSenderIsNotSpokePool() public {
        vm.prank(user);
        vm.expectRevert(AcrossSettler.NotSpokePool.selector);
        acrossV3Settler.handleV3AcrossMessage(baseToken, 100, address(0), new bytes(0));
    }

    function test_handleV3AcrossMessage_triggersCatch_withNoMigrationId() public {
        uint256 userBalanceBefore = IERC20(baseToken).balanceOf(user);
        deal(baseToken, address(acrossV3Settler), 1 ether);
        // invalid settlement params for above tick
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 1_000_000_000, -200000, Range.AboveTick, true, bytes32(0));
        vm.prank(spokePool);
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(acrossV3Settler), user, 1 ether);
        acrossV3Settler.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);
        assertEq(IERC20(baseToken).balanceOf(user), userBalanceBefore + 1 ether);
    }

    function test_handleV3AcrossMessage_triggersCatchAndRefundsBothTokens_withMigrationId() public {
        uint256 userBalanceBefore = IERC20(baseToken).balanceOf(user);
        uint256 userBalanceBeforeUSDC = IERC20(usdc).balanceOf(user);
        deal(baseToken, address(acrossV3Settler), 1 ether);
        deal(usdc, address(acrossV3Settler), 1_500_000_000);
        // invalid settlement params for above tick
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 1_000_000_000, -200000, Range.AboveTick, true, bytes32("111"));
        vm.prank(spokePool);
        acrossV3Settler.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);
        (address token, uint256 amount, IV3Settler.V3SettlementParams memory settlementParams) =
            acrossV3Settler.partialSettlements(bytes32("111"));
        assertEq(token, baseToken);
        assertEq(amount, 1 ether);
        assertEq(settlementParams.recipient, user);
        bytes memory migrationIdAndSettlementParamsChanged =
            this.generateSettlementParams(0, 1_000_000, -200000, Range.AboveTick, true, bytes32("111"));
        vm.prank(spokePool);
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(acrossV3Settler), user, 1 ether);
        emit IERC20.Transfer(address(acrossV3Settler), user, 1 ether);
        acrossV3Settler.handleV3AcrossMessage(usdc, 1_500_000_000, address(0), migrationIdAndSettlementParamsChanged);
        assertEq(IERC20(baseToken).balanceOf(user), userBalanceBefore + 1 ether);
        assertEq(IERC20(usdc).balanceOf(user), userBalanceBeforeUSDC + 1_500_000_000);
    }

    // function test_handleV3AcrossMessageWorks() public {
    //     // deal baseToken to settler
    //     deal(baseToken, address(acrossV3Settler), 1.1 ether); // slightly higher due to fees

    //     // get pool
    //     IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
    //     IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
    //     (, int24 currentTick,,,,,) = pool.slot0();

    //     // generate settlement params
    //     bytes memory migrationIdAndSettlementParams =
    //         this.generateSettlementParams(0.5 ether, 1_500_000_000, currentTick, Range.InRange, true, bytes32(0));

    //     vm.prank(spokePool);
    //     acrossV3Settler.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);
    // }

    /*
     * Helper tests
     */

    function test__refund_removesPartialSettlement() public {
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        // add a partial settlement
        bytes32 migrationId = bytes32("111");
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, migrationId);
        acrossV3SettlerHarness.exposed_settle(baseToken, 0.5 ether, migrationIdAndSettlementParams);
        // verify partial settlement was added
        (address token, uint256 amount, IV3Settler.V3SettlementParams memory settlementParams) =
            acrossV3SettlerHarness.partialSettlements(migrationId);
        assertEq(token, baseToken);
        assertEq(amount, 0.5 ether);
        assertEq(settlementParams.recipient, user);

        // refund it
        acrossV3SettlerHarness.exposed_refund(migrationId);
        // check that it's removed
        (address token1, uint256 amount1, IV3Settler.V3SettlementParams memory settlementParams1) =
            acrossV3SettlerHarness.partialSettlements(migrationId);
        assertEq(token1, address(0));
        assertEq(amount1, 0);
        assertEq(settlementParams1.recipient, address(0));
    }

    function test_compareSettlementParams_returnsTrueIfSame() public view {
        (, bytes memory message) = abi.decode(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0)),
            (bytes32, bytes)
        );
        (IV3Settler.V3SettlementParams memory a) = abi.decode(message, (IV3Settler.V3SettlementParams));
        (, bytes memory message2) = abi.decode(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0)),
            (bytes32, bytes)
        );
        (IV3Settler.V3SettlementParams memory b) = abi.decode(message2, (IV3Settler.V3SettlementParams));
        assertEq(acrossV3Settler.compareSettlementParams(a, b), true);
    }

    function test_compareSettlementParams_returnsFalseIfDifferent() public view {
        (, bytes memory message) = abi.decode(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true, bytes32(0)),
            (bytes32, bytes)
        );
        (IV3Settler.V3SettlementParams memory a) = abi.decode(message, (IV3Settler.V3SettlementParams));
        (, bytes memory message2) = abi.decode(
            this.generateSettlementParams(0.5 ether, 1_400_000_000, 0, Range.InRange, true, bytes32(0)),
            (bytes32, bytes)
        );
        (IV3Settler.V3SettlementParams memory b) = abi.decode(message2, (IV3Settler.V3SettlementParams));
        assertEq(acrossV3Settler.compareSettlementParams(a, b), false);
    }

    /*
     * _settle() tests
     */

    function test__settleFailsIfBothAmountsAreZero() public {
        deal(baseToken, address(acrossV3Settler), 1 ether);
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 0, -200000, Range.InRange, true, bytes32(0));
        vm.expectRevert(ISettler.AtLeastOneAmountMustBeGreaterThanZero.selector);
        acrossV3Settler.settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settleFailsIfBridgedTokenIsNotUsedInPosition() public {
        deal(baseToken, address(acrossV3Settler), 1 ether);
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1 ether, -200000, Range.InRange, true, bytes32(0));
        vm.expectRevert(AcrossSettler.BridgedTokenMustBeUsedInPosition.selector);
        acrossV3Settler.settle(address(0x4), 1 ether, migrationIdAndSettlementParams);
    }
    /*
    * Single token tests
    */

    function test__settle_noMigrationId_token0ReceivedAndPositionInRange() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0.5 ether, 1_500_000_000, currentTick, Range.InRange, true, bytes32(0));

        // Approve baseToken to swaprouter
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Approval(address(acrossV3SettlerHarness), swapRouter, 0.5 ether);

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(pool), address(acrossV3SettlerHarness), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(acrossV3SettlerHarness), 0, 1, 0, 0, 0);

        // Approve for usdc and basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false);
        emit IERC20.Approval(address(acrossV3SettlerHarness), nftPositionManager, 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Approval(address(acrossV3SettlerHarness), nftPositionManager, 0);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(user), 0);
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(user), 0);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token0ReceivedAndPositionBelowTick() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 3_000_000_000, currentTick, Range.BelowTick, true, bytes32(0));

        // Approve for basetoken to swaprouter
        vm.expectEmit(true, true, false, false);
        emit IERC20.Approval(address(acrossV3SettlerHarness), swapRouter, 0.5 ether);

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(pool), address(acrossV3SettlerHarness), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(acrossV3SettlerHarness), 0, 1, 0, 0, 0);

        // Approve for usdc and basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Approval(address(acrossV3SettlerHarness), nftPositionManager, 0);

        // Minting - only transferring one token
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep - nothing to sweep

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token0ReceivedAndPositionAboveTick() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 0, currentTick, Range.AboveTick, true, bytes32(0));

        // Swap not needed

        // Approve for basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Approval(address(acrossV3SettlerHarness), nftPositionManager, 0);

        // Minting (no need to approve usdc, one-sided position)
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep - nothing to sweep either

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token1ReceivedAndPositionInRange() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(virtualToken, baseToken, 3000));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0.5 ether, 0.5 ether, currentTick, Range.InRange, false, bytes32(0));

        // Approve for basetoken to swaprouter
        vm.expectEmit(true, true, false, false);
        emit IERC20.Approval(address(acrossV3SettlerHarness), swapRouter, 0.5 ether);

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(pool), address(acrossV3SettlerHarness), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(acrossV3SettlerHarness), 0, 1, 0, 0, 0);

        // Approve for virtualToken and basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Approval(address(acrossV3SettlerHarness), nftPositionManager, 0);
        vm.expectEmit(true, true, false, false, virtualToken);
        emit IERC20.Approval(address(acrossV3SettlerHarness), nftPositionManager, 0);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(user), 0);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token1ReceivedAndPositionBelowTick() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(virtualToken, baseToken, 3000));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 1 ether, currentTick, Range.BelowTick, false, bytes32(0));

        // Swap not needed

        // Approve for virtualToken and basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Approval(address(acrossV3SettlerHarness), nftPositionManager, 0);

        // Minting
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep - nothing to sweep

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_noMigrationId_token1ReceivedAndPositionAboveTick() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(virtualToken, baseToken, 3000));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(500_000_000_000_000_000, 0, currentTick, Range.AboveTick, false, bytes32(0));

        // Approve for basetoken to swaprouter
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Approval(address(acrossV3SettlerHarness), swapRouter, 1 ether);

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(pool), address(acrossV3SettlerHarness), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(acrossV3SettlerHarness), 0, 1, 0, 0, 0);

        // Approve for virtualToken to nftPositionManager
        vm.expectEmit(true, true, false, false, virtualToken);
        emit IERC20.Approval(address(acrossV3SettlerHarness), nftPositionManager, 0);

        // Minting
        vm.expectEmit(true, true, false, false, virtualToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep - nothing to sweep

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    /*
    * Dual token tests
    */

    function test__settle_migrationId_token0Received() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settle_migrationId_token1Received() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal usdc to settler
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test__settle_migrationId_token0Received_token1Received_BridgedTokenNotUsedInPosition() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        deal(virtualToken, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Bridged token ont used in position
        vm.expectRevert(AcrossSettler.BridgedTokenMustBeUsedInPosition.selector);

        acrossV3SettlerHarness.exposed_settle(virtualToken, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test__settle_migrationId_token1Received_token0Received_BridgedTokenNotUsedInPosition() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(virtualToken, address(acrossV3SettlerHarness), 1_000_000_000);
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);

        // Bridged token ont used in position
        vm.expectRevert(AcrossSettler.BridgedTokenMustBeUsedInPosition.selector);

        acrossV3SettlerHarness.exposed_settle(virtualToken, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_token0ReceivedTwice_BridgedTokensMustBeDifferent() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal base token to settler
        deal(baseToken, address(acrossV3SettlerHarness), 2 ether);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Bridged token must be different
        vm.expectRevert(AcrossSettler.BridgedTokensMustBeDifferent.selector);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_token1ReceivedTwice_BridgedTokensMustBeDifferent() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal usdc to settler
        deal(usdc, address(acrossV3SettlerHarness), 2_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);

        // Bridged token must be different
        vm.expectRevert(AcrossSettler.BridgedTokensMustBeDifferent.selector);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test__settle_migrationId_token0Received_token1Received_SettlementParamsMismatch() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams1 =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);
        bytes memory migrationIdAndSettlementParams2 =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.BelowTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams1);

        // Settlement params do not match
        vm.expectRevert(IV3Settler.SettlementParamsDoNotMatch.selector);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams2);
    }

    function test__settle_migrationId_token1Received_token0Received_SettlementParamsMismatch() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams1 =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);
        bytes memory migrationIdAndSettlementParams2 =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.BelowTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams1);

        // Settlement params do not match
        vm.expectRevert(IV3Settler.SettlementParamsDoNotMatch.selector);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams2);
    }

    function test_settle_migrationId_mintFailure_token0Received_token1Received() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(baseToken, usdc, 0, 0, 0, 1 ether, 1_000_000_000, 0, address(0), migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Refund bridged token to recipient
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), user, 1_000_000_000);

        // Refund partial settlement token to recipient
        vm.expectEmit(true, true, false, true, address(baseToken));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), user, 1 ether);

        vm.prank(spokePool);
        acrossV3SettlerHarness.handleV3AcrossMessage(usdc, 1_000_000_000, address(0), migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintFailure_token1Received_token0Received() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal tokens to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(baseToken, usdc, 0, 0, 0, 1 ether, 1_000_000_000, 0, address(0), migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, usdc, 1_000_000_000);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);

        // Refund bridged token to recipient
        vm.expectEmit(true, true, false, true, address(baseToken));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), user, 1 ether);

        // Refund partial settlement token to recipient
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), user, 1_000_000_000);

        vm.prank(spokePool);
        acrossV3SettlerHarness.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintSuccess_token0Received_token1Received_bothFeesNonZero() public {
        bytes32 migrationId = keccak256("migrationId");
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));

        // deal tokens to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Settled
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 9.975e17);

        vm.expectEmit(true, true, false, false, nftPositionManager);
        emit IERC721.Transfer(address(0), user, 0);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), user, 9.975e8);

        vm.expectEmit(true, true, false, true, baseToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), protocolFeeRecipient, 1.375e15);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), protocolFeeRecipient, 1.375e6);

        vm.expectEmit(true, true, false, true, baseToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), senderWallet, 1.125e15);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), senderWallet, 1.125e6);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintSuccess_token0Received_token1Received_bothFeesZero() public {
        bytes32 migrationId = keccak256("migrationId");
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        vm.startPrank(owner);
        acrossV3SettlerHarness.setProtocolFeeBps(0);
        acrossV3SettlerHarness.setProtocolShareOfSenderFeeInPercent(0);
        vm.stopPrank();

        // deal tokens to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams = this.generateSettlementParams(
            baseToken,
            usdc,
            500,
            (currentTick + 30000) / 30000 * 30000,
            (currentTick + 60000) / 30000 * 30000,
            1 ether,
            1_000_000,
            0,
            address(0),
            migrationId
        );

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Settled
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 1 ether);

        vm.expectEmit(true, true, false, false, nftPositionManager);
        emit IERC721.Transfer(address(0), user, 0);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), user, 1_000_000_000);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintSuccess_token0Received_token1Received_OnlyProtocolFee() public {
        bytes32 migrationId = keccak256("migrationId");
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // deal tokens to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams = this.generateSettlementParams(
            baseToken,
            usdc,
            500,
            (currentTick + 30000) / 30000 * 30000,
            (currentTick + 60000) / 30000 * 30000,
            1 ether,
            1_000_000,
            0,
            address(0),
            migrationId
        );

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Settled
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 9.99e17);

        vm.expectEmit(true, true, false, false, nftPositionManager);
        emit IERC721.Transfer(address(0), user, 0);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), user, 9.99e8);

        vm.expectEmit(true, true, false, true, baseToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), protocolFeeRecipient, 1e15);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), protocolFeeRecipient, 1e6);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test_settle_migrationId_mintSuccess_token0Received_token1Received_OnlySenderFee() public {
        bytes32 migrationId = keccak256("migrationId");
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));

        vm.startPrank(owner);
        acrossV3SettlerHarness.setProtocolFeeBps(0);
        acrossV3SettlerHarness.setProtocolShareOfSenderFeeInPercent(0);
        vm.stopPrank();

        // deal tokens to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);
        deal(usdc, address(acrossV3SettlerHarness), 1_000_000_000);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 1_000_000_000, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Settled
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), address(pool), 9.985e17);

        vm.expectEmit(true, true, false, false, nftPositionManager);
        emit IERC721.Transfer(address(0), user, 0);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), user, 9.985e8);

        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), senderWallet, 1.5e15);

        vm.expectEmit(true, true, false, true, usdc);
        emit IERC20.Transfer(address(acrossV3SettlerHarness), senderWallet, 1.5e6);

        acrossV3SettlerHarness.exposed_settle(usdc, 1_000_000_000, migrationIdAndSettlementParams);
    }

    function test_withdraw() public {
        bytes32 migrationId = keccak256("migrationId");

        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1 ether);

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 0, 0, Range.AboveTick, true, migrationId);

        // Partially Settled
        vm.expectEmit(true, true, true, true);
        emit ISettler.PartiallySettled(migrationId, user, baseToken, 1 ether);

        acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);

        // Refund to recipient
        vm.expectEmit(true, true, false, true, address(baseToken));
        emit IERC20.Transfer(address(acrossV3SettlerHarness), user, 1 ether);

        acrossV3SettlerHarness.withdraw(migrationId);
    }
}
