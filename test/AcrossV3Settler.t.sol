// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {AcrossV3Settler} from "../src/AcrossV3Settler.sol";
import {AcrossSettler} from "../src/base/AcrossSettler.sol";
import {IV3Settler} from "../src/interfaces/IV3Settler.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {AcrossV3SettlerHarness} from "./AcrossV3SettlerHarness.sol";
import {IUniswapV3Factory} from "lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolEvents} from "lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {INonfungiblePositionManager} from "src/interfaces/external/INonfungiblePositionManager.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract V3SettlerTest is Test {
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
        uint256 amount1Min
    ) public view returns (bytes memory) {
        return abi.encode(
            bytes32(0),
            IV3Settler.V3SettlementParams({
                recipient: user,
                token0: token0,
                token1: token1,
                feeTier: feeTier,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                senderFeeBps: 15,
                senderFeeRecipient: senderWallet
            })
        );
    }

    function generateSettlementParams(
        uint256 amount0Min,
        uint256 amount1Min,
        int24 currentTick,
        Range range,
        bool token0BaseToken
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
        return this.generateSettlementParams(token0, token1, feeTier, tickLower, tickUpper, amount0Min, amount1Min);
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);
        vm.startPrank(owner);
        acrossV3SettlerHarness = new AcrossV3SettlerHarness(spokePool, protocolFeeRecipient, 10, 25, swapRouter, nftPositionManager);
        acrossV3Settler = new AcrossV3Settler(spokePool, protocolFeeRecipient, 10, 25, swapRouter, nftPositionManager);
        vm.stopPrank();
    }

    /*
     * Getters
     */

    function test__getSenderFeesReturnsCorrectValues() public view {
        (uint24 senderFeeBps, address senderFeeRecipient) = acrossV3SettlerHarness.exposed_getSenderFees(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true)
        );
        assertEq(senderFeeBps, 15);
        assertEq(senderFeeRecipient, senderWallet);
    }

    function test__getRecipientReturnsCorrectValue() public view {
        address recipient = acrossV3SettlerHarness.exposed_getRecipient(
            this.generateSettlementParams(0.5 ether, 1_500_000_000, 0, Range.InRange, true)
        );
        assertEq(recipient, user);
    }

    /*
    * Setters
    */

    function test_setProtocolFeeBpsFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        acrossV3SettlerHarness.setProtocolFeeBps(5);
    }

    function test_setProtocolFeeBpsSucceedsWhenOwner() public {
        vm.prank(owner);
        acrossV3SettlerHarness.setProtocolFeeBps(1);
        assertEq(acrossV3SettlerHarness.protocolFeeBps(), 1);
    }

    function test_setProtocolFeeRecipientFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        acrossV3SettlerHarness.setProtocolFeeRecipient(address(0x4));
        assertEq(acrossV3SettlerHarness.protocolFeeRecipient(), protocolFeeRecipient);
    }

    function test_setProtocolFeeRecipientSucceedsWhenOwner() public {
        vm.prank(owner);
        acrossV3SettlerHarness.setProtocolFeeRecipient(address(0x4));
        assertEq(acrossV3SettlerHarness.protocolFeeRecipient(), address(0x4));
    }

    function test_setProtocolShareOfSenderFeeInPercentFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        acrossV3SettlerHarness.setProtocolShareOfSenderFeeInPercent(50);
        assertEq(acrossV3SettlerHarness.protocolShareOfSenderFeeInPercent(), 25);
    }

    function test_setProtocolShareOfSenderFeeInPercentSucceedsWhenOwner() public {
        vm.prank(owner);
        acrossV3SettlerHarness.setProtocolShareOfSenderFeeInPercent(50);
        assertEq(acrossV3SettlerHarness.protocolShareOfSenderFeeInPercent(), 50);
    }

    /*
    * Handle V3 Across Message
    */

    function test_handleV3AcrossMessage_msgSenderIsNotSpokePool() public {
        vm.prank(user);
        vm.expectRevert(AcrossSettler.NotSpokePool.selector);
        acrossV3Settler.handleV3AcrossMessage(baseToken, 100, address(0), new bytes(0));
    }

    function test_handleV3AcrossMessage_trySettleAndTriggersCatch() public {
        uint256 userBalanceBefore = IERC20(baseToken).balanceOf(user);
        deal(baseToken, address(acrossV3Settler), 1 ether);
        // invalid settlement params for above tick
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 1_000_000_000, -200000, Range.AboveTick, true);
        vm.prank(spokePool);
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(acrossV3Settler), user, 1 ether);
        acrossV3Settler.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);
        assertEq(IERC20(baseToken).balanceOf(user), userBalanceBefore + 1 ether);
    }

    function test_handleV3AcrossMessageWorks() public {
      // deal baseToken to settler
        deal(baseToken, address(acrossV3Settler), 1.1 ether); // slightly higher due to fees

        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0.5 ether, 1_500_000_000, currentTick, Range.InRange, true);

        vm.prank(spokePool);
        acrossV3Settler.handleV3AcrossMessage(baseToken, 1 ether, address(0), migrationIdAndSettlementParams);

    }

    /*
     * Settle() tests
     */

    function test_settleWithdrawsProtocolFeeWhenSenderFeeZero() public {
        // todo
    }

    function test_settleWithdrawsSenderFeeWhenProtocolFeeZero() public {
        // todo
    }

    function test_settleWithdrawsBothFeesWhenBothAreNonZero() public {
        // todo
    }

    /*
     * _settle() tests
     */

    function test__settleFailsIfBothAmountsAreZero() public {
        deal(baseToken, address(acrossV3Settler), 1 ether);
        bytes memory migrationIdAndSettlementParams = this.generateSettlementParams(0, 0, -200000, Range.InRange, true);
        vm.expectRevert(ISettler.AtLeastOneAmountMustBeGreaterThanZero.selector);
        acrossV3Settler.settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }

    function test__settleFailsIfBridgedTokenIsNotUsedInPosition() public {
        deal(baseToken, address(acrossV3Settler), 1 ether);
        bytes memory migrationIdAndSettlementParams = this.generateSettlementParams(1 ether, 1 ether, -200000, Range.InRange, true);
        vm.expectRevert(AcrossSettler.BridgedTokenMustBeUsedInPosition.selector);
        acrossV3Settler.settle(address(0x4), 1 ether, migrationIdAndSettlementParams);
    }
    /*
    * Single token tests
    */

    function test__settle_token0ReceivedAndPositionInRange() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0.5 ether, 1_500_000_000, currentTick, Range.InRange, true);

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

    function test__settle_token0ReceivedAndPositionBelowTick() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 3_000_000_000, currentTick, Range.BelowTick, true);

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

    function test__settle_token0ReceivedAndPositionAboveTick() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(1 ether, 0, currentTick, Range.AboveTick, true);

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

    function test__settle_token1ReceivedAndPositionInRange() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(virtualToken, baseToken, 3000));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0.5 ether, 0.5 ether, currentTick, Range.InRange, false);

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

    function test__settle_token1ReceivedAndPositionBelowTick() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees

        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(virtualToken, baseToken, 3000));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(0, 1 ether, currentTick, Range.BelowTick, false);

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

    function test__settle_token1ReceivedAndPositionAboveTick() public {
        // deal baseToken to settler
        deal(baseToken, address(acrossV3SettlerHarness), 1.1 ether); // slightly higher due to fees
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(virtualToken, baseToken, 3000));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        bytes memory migrationIdAndSettlementParams =
            this.generateSettlementParams(500_000_000_000_000_000, 0, currentTick, Range.AboveTick, false);

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

    function test__settle_dualTokenPath() public {
      // todo remove when real dual token path is implemented

      // generate settlement params
      bytes memory migrationIdAndSettlementParams =
          this.generateSettlementParams(0.5 ether, 0.5 ether, 0, Range.InRange, false);
      (, IV3Settler.V3SettlementParams memory settlementParams) = abi.decode(migrationIdAndSettlementParams, (bytes32, IV3Settler.V3SettlementParams));
      migrationIdAndSettlementParams = abi.encode(bytes32("migrationId"), settlementParams);

      acrossV3SettlerHarness.exposed_settle(baseToken, 1 ether, migrationIdAndSettlementParams);
    }
}
