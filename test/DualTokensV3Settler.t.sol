// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AcrossV3Settler} from "src/base/AcrossV3Settler.sol";
import {IDualTokensV3Settler} from "src/interfaces/IDualTokensV3Settler.sol";
import {DualTokensV3Settler} from "src/DualTokensV3Settler.sol";

contract DualTokensV3SettlerTest is Test {
    address private USDC = vm.envAddress("BASE_USDC");
    address private WETH = vm.envAddress("BASE_WETH");
    address private positionManager = vm.envAddress("BASE_NFT_POSITION_MANAGER");
    address private spokePool = vm.envAddress("BASE_SPOKE_POOL");
    address private recipient = address(0x123);

    DualTokensV3Settler private settler;
    bytes32 private migrationId1 = "1";
    bytes32 private migrationId2 = "2";
    IDualTokensV3Settler.SettlementParams private settlementParams1;
    IDualTokensV3Settler.SettlementParams private settlementParams2;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);

        deal(WETH, address(this), 100 * 1e18);
        deal(USDC, address(this), 100_000 * 1e6);

        settler = new DualTokensV3Settler(positionManager, spokePool);

        settlementParams1 =
            IDualTokensV3Settler.SettlementParams(migrationId1, address(0x123), WETH, USDC, 500, -600, 600);
        settlementParams2 =
            IDualTokensV3Settler.SettlementParams(migrationId2, address(0x123), WETH, USDC, 500, -600, 600);
    }

    function test_fuzz_msgSenderIsNotSpokePool(address msgSender) public {
        vm.assume(msgSender != spokePool);

        vm.expectRevert(AcrossV3Settler.NotSpokePool.selector);
        settler.handleV3AcrossMessage(WETH, 1e18, address(0), "");
    }

    function test_partialSettlement() public {
        IERC20(settlementParams1.token0).transfer(address(settler), 1e18);

        vm.startPrank(spokePool);
        vm.expectEmit(true, true, true, true, address(settler));
        emit IDualTokensV3Settler.PartialSettle(
            settlementParams1.migrationId, settlementParams1.recipient, settlementParams1.token0, 1e18
        );
        settler.handleV3AcrossMessage(settlementParams1.token0, 1e18, address(0), abi.encode(settlementParams1));
    }

    function test_fullSettlement() public {
        IERC20(settlementParams1.token0).transfer(address(settler), 1e18);
        IERC20(settlementParams1.token1).transfer(address(settler), 1e6);

        vm.startPrank(spokePool);

        vm.expectEmit(true, true, true, true, address(settler));
        emit IDualTokensV3Settler.PartialSettle(
            settlementParams1.migrationId, settlementParams1.recipient, settlementParams1.token0, 1e18
        );
        settler.handleV3AcrossMessage(settlementParams1.token0, 1e18, address(0), abi.encode(settlementParams1));

        vm.expectEmit(true, true, false, false, address(settler));
        emit IDualTokensV3Settler.Settle(settlementParams1.migrationId, settlementParams1.recipient, 0, 0, 0, 0, 0, 0);
        settler.handleV3AcrossMessage(settlementParams1.token1, 1e6, address(0), abi.encode(settlementParams1));

        vm.stopPrank();
    }

    function test_fuzz_escapeNonExistentSettlement(bytes32 migrationId) public {
        vm.expectRevert(DualTokensV3Settler.NotRecipient.selector);
        settler.escape(migrationId);
    }

    function test_escapePartialSettlementByNonRecipient() public {
        IERC20(settlementParams1.token0).transfer(address(settler), 1e18);
        vm.prank(address(spokePool));
        settler.handleV3AcrossMessage(settlementParams1.token0, 1e18, address(0), abi.encode(settlementParams1));

        vm.expectRevert(DualTokensV3Settler.NotRecipient.selector);
        settler.escape(settlementParams1.migrationId);
    }

    function test_escapePartialSettlementByRecipient() public {
        IERC20(settlementParams1.token0).transfer(address(settler), 1e18);
        vm.prank(address(spokePool));
        settler.handleV3AcrossMessage(settlementParams1.token0, 1e18, address(0), abi.encode(settlementParams1));

        vm.prank(settlementParams1.recipient);
        vm.expectEmit(true, true, true, true, address(settler));
        emit IDualTokensV3Settler.Escape(
            settlementParams1.migrationId, settlementParams1.recipient, settlementParams1.token0, 1e18
        );
        settler.escape(settlementParams1.migrationId);
    }

    function test_escapeFullSettlement() public {
        IERC20(settlementParams1.token0).transfer(address(settler), 1e18);
        IERC20(settlementParams1.token1).transfer(address(settler), 1e6);
        vm.startPrank(spokePool);
        settler.handleV3AcrossMessage(settlementParams1.token0, 1e18, address(0), abi.encode(settlementParams1));
        settler.handleV3AcrossMessage(settlementParams1.token1, 1e6, address(0), abi.encode(settlementParams1));
        vm.stopPrank();

        vm.prank(settlementParams1.recipient);
        vm.expectRevert(DualTokensV3Settler.NotRecipient.selector);
        settler.escape(settlementParams1.migrationId);
    }
}
