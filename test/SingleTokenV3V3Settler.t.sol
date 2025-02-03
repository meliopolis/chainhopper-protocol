// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {SingleTokenV3Settler} from "../src/SingleTokenV3Settler.sol";
import {ISingleTokenV3Settler} from "../src/interfaces/ISingleTokenV3Settler.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolEvents} from "lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IUniswapV3Factory} from "lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "src/interfaces/external/INonfungiblePositionManager.sol";
import {ISingleTokenV3V3Migrator} from "../src/interfaces/ISingleTokenV3V3Migrator.sol";

contract SingleTokenV3V3SettlerTest is Test {
    SingleTokenV3Settler public settler;
    address public nftPositionManager = vm.envAddress("BASE_NFT_POSITION_MANAGER");
    address public baseToken = vm.envAddress("BASE_WETH");
    address public spokePool = vm.envAddress("BASE_SPOKE_POOL");
    address public swapRouter = vm.envAddress("BASE_SWAP_ROUTER");
    address public usdc = vm.envAddress("BASE_USDC");
    address public user = address(0x1);
    address public virtualToken = address(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b); // sorts before baseToken
    address public protocolFeeRecipient = 0xDd1D28e5BEdBd000A0539a3BF0ED558F4B721a84;

    enum Range {
        InRange,
        BelowTick,
        AboveTick
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);
        settler =
            new SingleTokenV3Settler(nftPositionManager, baseToken, swapRouter, spokePool, 10, protocolFeeRecipient);
    }

    function generateSettlementParams(
        address token0,
        address token1,
        uint24 feeTier,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Min,
        uint256 amount1Min
    ) public view returns (ISingleTokenV3V3Migrator.SettlementParams memory) {
        return ISingleTokenV3V3Migrator.SettlementParams({
            token0: token0,
            token1: token1,
            feeTier: feeTier,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: user
        });
    }

    function generateSettlementParams(
        uint256 amount0Min,
        uint256 amount1Min,
        int24 currentTick,
        Range range,
        bool token0BaseToken
    ) public view returns (ISingleTokenV3V3Migrator.SettlementParams memory) {
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

    function test_handleV3AcrossMessage_msgSenderIsNotSpokePool() public {
        vm.prank(user);
        vm.expectRevert(ISingleTokenV3Settler.OnlySpokePoolCanCall.selector);
        settler.handleV3AcrossMessage(baseToken, 100, address(0), new bytes(0));
    }

    function test_handleV3AcrossMessage_tokenSentIsNotBaseToken() public {
        vm.prank(spokePool);
        vm.expectRevert(ISingleTokenV3Settler.OnlyBaseTokenCanBeReceived.selector);
        settler.handleV3AcrossMessage(usdc, 100, address(0), new bytes(0));
    }

    function test_handleV3AcrossMessage_trySwapAndCreatePositionFailsAndTriggersCatch() public {
        uint256 userBalanceBefore = IERC20(baseToken).balanceOf(user);
        deal(baseToken, address(settler), 1 ether);
        // invalid settlement params for above tick
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams =
            this.generateSettlementParams(0, 1_000_000_000, -200000, Range.AboveTick, true);
        vm.prank(spokePool);
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), user, 1 ether);
        settler.handleV3AcrossMessage(baseToken, 1 ether, address(0), abi.encode(settlementParams));
        assertEq(IERC20(baseToken).balanceOf(user), userBalanceBefore + 1 ether);
    }

    function test_swapAndCreatePosition_insufficientBalance() public {
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams =
            this.generateSettlementParams(0, 0, -200000, Range.InRange, true);
        vm.expectRevert(ISingleTokenV3Settler.InsufficientBalance.selector);
        settler.swapAndCreatePosition(100, settlementParams);
    }

    function test_swapAndCreatePosition_bothAmountsZero() public {
        deal(baseToken, address(settler), 1 ether);
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams =
            this.generateSettlementParams(0, 0, -200000, Range.InRange, true);
        vm.expectRevert(ISingleTokenV3Settler.AtLeastOneAmountMustBeGreaterThanZero.selector);
        settler.swapAndCreatePosition(1 ether, settlementParams);
    }

    function test_swapAndCreatePosition_token0BaseTokenInRange() public {
        // deal baseToken to settler
        deal(baseToken, address(settler), 1 ether);

        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams =
            this.generateSettlementParams(0.5 ether, 1_500_000_000, currentTick, Range.InRange, true);

        // Approve for basetoken to swaprouter
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Approval(address(settler), swapRouter, 0.5 ether);

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(pool), address(settler), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(settler), 0, 1, 0, 0, 0);

        // Approve for usdc and basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false);
        emit IERC20.Approval(address(settler), nftPositionManager, 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Approval(address(settler), nftPositionManager, 0);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), address(user), 0);
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // protocol fee
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), address(protocolFeeRecipient), 0);

        settler.swapAndCreatePosition(1 ether, settlementParams);
    }

    function test_swapAndCreatePosition_token0BaseTokenBelowCurrentTick() public {
        // deal baseToken to settler
        deal(baseToken, address(settler), 1 ether);
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams =
            this.generateSettlementParams(0, 3_000_000_000, currentTick, Range.BelowTick, true);

        // Approve for basetoken to swaprouter
        vm.expectEmit(true, true, false, false);
        emit IERC20.Approval(address(settler), swapRouter, 0.5 ether);

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(pool), address(settler), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(settler), 0, 1, 0, 0, 0);

        // Approve for usdc and basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Approval(address(settler), nftPositionManager, 0);

        // Minting - only transferring one token
        vm.expectEmit(true, true, false, false, address(usdc));
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep - nothing to sweep

        // protocol fee
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), address(protocolFeeRecipient), 0);

        settler.swapAndCreatePosition(1 ether, settlementParams);
    }

    function test_swapAndCreatePosition_token0BaseTokenAboveCurrentTick() public {
        // deal baseToken to settler
        deal(baseToken, address(settler), 1 ether);
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams =
            this.generateSettlementParams(1 ether, 0, currentTick, Range.AboveTick, true);

        // Swap not needed

        // Approve for basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Approval(address(settler), nftPositionManager, 0);

        // Minting (no need to approve usdc, one-sided position)
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep - nothing to sweep either

        // protocol fee
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), address(protocolFeeRecipient), 0);

        settler.swapAndCreatePosition(1 ether, settlementParams);
    }

    function test_swapAndCreatePosition_token1BaseTokenInRange() public {
        // deal baseToken to settler
        deal(baseToken, address(settler), 1 ether);

        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(virtualToken, baseToken, 3000));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams =
            this.generateSettlementParams(0.5 ether, 0.5 ether, currentTick, Range.InRange, false);

        // Approve for basetoken to swaprouter
        vm.expectEmit(true, true, false, false);
        emit IERC20.Approval(address(settler), swapRouter, 0.5 ether);

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(pool), address(settler), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(settler), 0, 1, 0, 0, 0);

        // Approve for virtualToken and basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Approval(address(settler), nftPositionManager, 0);
        vm.expectEmit(true, true, false, false, virtualToken);
        emit IERC20.Approval(address(settler), nftPositionManager, 0);

        // Minting
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep remaining tokens to user
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), address(user), 0);

        // protocol fee
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), address(protocolFeeRecipient), 0);

        settler.swapAndCreatePosition(1 ether, settlementParams);
    }

    function test_swapAndCreatePosition_token1BaseTokenBelowCurrentTick() public {
        // deal baseToken to settler
        deal(baseToken, address(settler), 1 ether);

        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(virtualToken, baseToken, 3000));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams =
            this.generateSettlementParams(0, 1 ether, currentTick, Range.BelowTick, false);

        // Swap not needed

        // Approve for virtualToken and basetoken to nftPositionManager
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Approval(address(settler), nftPositionManager, 0);
        // vm.expectEmit(true, true, false, false, virtualToken);
        // emit IERC20.Approval(address(settler), nftPositionManager, 0);

        // // Minting
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep - nothing to sweep

        // protocol fee
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), address(protocolFeeRecipient), 0);

        settler.swapAndCreatePosition(1 ether, settlementParams);
    }

    function test_swapAndCreatePosition_token1BaseTokenAboveCurrentTick() public {
        // deal baseToken to settler
        deal(baseToken, address(settler), 1 ether);
        // get pool
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(virtualToken, baseToken, 3000));
        (, int24 currentTick,,,,,) = pool.slot0();

        // generate settlement params
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams =
            this.generateSettlementParams(500_000_000_000_000_000, 0, currentTick, Range.AboveTick, false);

        // Approve for basetoken to swaprouter
        vm.expectEmit(true, true, false, false, baseToken);
        emit IERC20.Approval(address(settler), swapRouter, 1 ether);

        // Transfer, Transfer, Swap events from swap
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(pool), address(settler), 0);
        vm.expectEmit(true, true, false, false);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(settler), 0, 1, 0, 0, 0);

        // Approve for virtualToken to nftPositionManager
        vm.expectEmit(true, true, false, false, virtualToken);
        emit IERC20.Approval(address(settler), nftPositionManager, 0);

        // Minting
        vm.expectEmit(true, true, false, false, virtualToken);
        emit IERC20.Transfer(address(settler), address(pool), 0);
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Mint(nftPositionManager, nftPositionManager, 0, 0, 0, 0, 0);

        // Transfer Position from 0x0 to user
        vm.expectEmit(true, false, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        // Sweep - nothing to sweep

        // protocol fee
        vm.expectEmit(true, true, false, false, address(baseToken));
        emit IERC20.Transfer(address(settler), address(protocolFeeRecipient), 0);

        settler.swapAndCreatePosition(1 ether, settlementParams);
    }
}
