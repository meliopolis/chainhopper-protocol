// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {TestContext} from "./utils/TestContext.sol";
// import {ISettler} from "../src/interfaces/ISettler.sol";
// import {IUniswapV3Settler} from "../src/interfaces/IUniswapV3Settler.sol";
// import {UniswapV3AcrossSettler} from "../src/UniswapV3AcrossSettler.sol";
// import {UniswapV3Helpers} from "./utils/UniswapV3Helpers.sol";
// import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
// import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
// import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
// import {IUniswapV3PoolEvents} from "@uniswap-v3-core/interfaces/pool/IUniswapV3PoolEvents.sol";
// import {MigrationId, MigrationIdLibrary} from "../src/types/MigrationId.sol";
// import {MigrationModes, MigrationMode} from "../src/types/MigrationMode.sol";

// contract UniswapV3AcrossSettlerTest is TestContext, UniswapV3Helpers {
//     string public constant CHAIN_NAME = "BASE";
//     UniswapV3AcrossSettler public settler;

//     function setUp() public {
//         _loadChain(CHAIN_NAME);

//         vm.prank(owner);
//         settler = new UniswapV3AcrossSettler(owner, v3PositionManager, universalRouter, permit2, acrossSpokePool);
//     }

//     function generateSettlementParams() public view returns (ISettler.SettlementParams memory) {
//         ISettler.SettlementParams memory settlementParams = ISettler.SettlementParams({
//             recipient: user,
//             senderShareBps: 0,
//             senderFeeRecipient: address(0),
//             mintParams: abi.encode(
//                 IUniswapV3Settler.MintParams({
//                     token0: address(weth),
//                     token1: address(usdc),
//                     fee: 500,
//                     sqrtPriceX96: 0,
//                     tickLower: -250000,
//                     tickUpper: -100000,
//                     swapAmountInMilliBps: 0,
//                     amount0Min: 0,
//                     amount1Min: 0
//                 })
//             )
//         });
//         return settlementParams;
//     }

//     function generateSettlerData(MigrationId migrationId) public view returns (bytes memory) {
//         return abi.encode(migrationId, generateSettlementParams());
//     }

//     /*
//     Paths to include in tests:
//     - Single token path
//     - Dual token path (only applicable to both tokens being base tokens and in range)

//     TokenPairs to include in tests:
//     - weth/usdc (token0: weth and basetoken, token1: usdc)
//     - usdc/weth (token1: weth and basetoken, token0: ERC20)
//     - usdc/usdt (non-weth base token)

//     Ranges to include in tests:
//     - new pool
//     - below tickLower
//     - between tickLower and tickUpper
//     - above tickUpper

//     Outcomes
//     - success
//     - failure (trigger catch block)
//     */

//     /**
//      * SINGLE TOKEN PATHS ***
//      */
//     function test_handleV3AcrossMessage_ST_Token0BaseToken_failsAndRefunds() public {}

//     function test_handleV3AcrossMessage_ST_Token0BaseToken_InRange() public {}

//     function test_handleV3AcrossMessage_ST_Token0BaseToken_BelowTickLower() public {}

//     function test_handleV3AcrossMessage_ST_Token0BaseToken_AboveTickUpper() public {}

//     function test_handleV3AcrossMessage_ST_Token0BaseToken_SingleSided_NewPool() public {}

//     function test_handleV3AcrossMessage_ST_Token1BaseToken_failsAndRefunds() public {}

//     function test_handleV3AcrossMessage_ST_Token1BaseToken_InRange() public {}

//     function test_handleV3AcrossMessage_ST_Token1BaseToken_BelowTickLower() public {}

//     function test_handleV3AcrossMessage_ST_Token1BaseToken_AboveTickUpper() public {}

//     function test_handleV3AcrossMessage_ST_Token1BaseToken_SingleSided_NewPool() public {}

//     function test_handleV3AcrossMessage_ST_NonBaseToken_failsAndRefunds() public {}

//     /**
//      * DUAL TOKEN PATHS ***
//      */
//     function test_handleV3AcrossMessage_DT_SecondBridgeCallFailsAndRefundsBoth() public {}

//     function test_handleV3AcrossMessage_DT_InRange_ExistingPool_Token0ArrivesFirst() public {}

//     function test_handleV3AcrossMessage_DT_InRange_ExistingPool_Token1ArrivesFirst() public {}

//     function test_handleV3AcrossMessage_DT_InRange_NewPool_Token0ArrivesFirst() public {}

//     function test_handleV3AcrossMessage_DT_InRange_NewPool_Token1ArrivesFirst() public {}

//     function test() public override(TestContext, UniswapV3Helpers) {}
// }
