// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LPMigratorSingleToken} from "../src/LPMigratorSingleToken.sol";

contract LPMigratorSingleTokenTest is Test {
    LPMigratorSingleToken public migrator;

    function setUp() public {
        // deploy position manager
        // deploy swap router
        // deploy spoke pool
        // deploy base token
        // deploy migrator
    }

    function test_msgSenderIsNotNFTPositionManager() public {
        // todo: implement
    }

    function test_MigratorDoesNotOwnPosition() public {
        // todo: implement
    }

    function test_LiquidityIsZero() public {
        // todo: implement
    }

    function test_positionDoesNotContainBaseToken() public {
        // todo: implement
    }

    function test_MigratorReceivesPositionInRangeWithToken0BaseToken() public {
        // todo: implement
    }

    function test_MigratorReceivesPositionInRangeWithToken1BaseToken() public {
        // todo: implement
    }

    function test_MigratorReceivesPositionBelowRangeWithToken0BaseToken() public {
        // todo: implement
    }

    function test_MigratorReceivesPositionBelowRangeWithToken1BaseToken() public {
        // todo: implement
    }

    function test_MigratorReceivesPositionAboveRangeWithToken0BaseToken() public {
        // todo: implement
    }

    function test_MigratorReceivesPositionAboveRangeWithToken1BaseToken() public {
        // todo: implement
    }
}
