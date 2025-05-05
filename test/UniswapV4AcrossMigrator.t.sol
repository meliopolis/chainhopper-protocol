// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TestContext} from "./utils/TestContext.sol";
import {IMigrator} from "../src/interfaces/IMigrator.sol";
import {IAcrossMigrator} from "../src/interfaces/IAcrossMigrator.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {IUniswapV4Settler} from "../src/interfaces/IUniswapV4Settler.sol";
import {UniswapV4AcrossMigrator} from "../src/UniswapV4AcrossMigrator.sol";

contract UniswapV4AcrossMigratorTest is TestContext {
    string public constant CHAIN_NAME = "BASE";
    address public settler = address(123);
    UniswapV4AcrossMigrator public migrator;

    function setUp() public {
        _loadChain(CHAIN_NAME);

        vm.prank(owner);
        migrator =
            new UniswapV4AcrossMigrator(owner, v4PositionManager, universalRouter, permit2, acrossSpokePool, weth);
        // update chainSettler
        vm.prank(owner);
        uint32[] memory chainIds = new uint32[](1);
        chainIds[0] = uint32(130);
        address[] memory settlers = new address[](1);
        settlers[0] = address(settler);
        bool[] memory values = new bool[](1);
        values[0] = true;
        migrator.setChainSettlers(chainIds, settlers, values);
    }

    function generateMigrationParams() public view returns (IMigrator.MigrationParams memory) {
        ISettler.SettlementParams memory settlementParams = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: 0,
            senderFeeRecipient: address(0),
            mintParams: abi.encode(
                IUniswapV4Settler.MintParams({
                    token0: address(weth),
                    token1: address(usdc),
                    fee: 500,
                    tickSpacing: 100,
                    hooks: address(0),
                    sqrtPriceX96: 0,
                    tickLower: -200000,
                    tickUpper: -100000,
                    swapAmountInMilliBps: 0,
                    amount0Min: 0,
                    amount1Min: 0
                })
            )
        });
        IAcrossMigrator.Route memory route = IAcrossMigrator.Route({
            outputToken: address(weth),
            maxFees: 0,
            quoteTimestamp: uint32(block.timestamp),
            fillDeadlineOffset: 21600,
            exclusiveRelayer: address(0),
            exclusivityDeadline: 0
        });
        IMigrator.TokenRoute memory tokenRoute =
            IMigrator.TokenRoute({token: address(weth), amountOutMin: 0, route: abi.encode(route)});
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](1);
        tokenRoutes[0] = tokenRoute;
        return IMigrator.MigrationParams({
            chainId: 130,
            settler: settler,
            tokenRoutes: tokenRoutes,
            settlementParams: abi.encode(settlementParams)
        });
    }

    /*
    TokenPairs to include in tests:
    - eth/usdc (token0: eth and also the basetoken)
    - weth/usdc (token0: weth and also the basetoken)
    - usdc/weth (token1: weth and also the basetoken)
    - usdc/usdt (token0 is a non-weth base token)

    Ranges to include in tests:
    - below tickLower
    - between tickLower and tickUpper
    - above tickUpper

    Paths to include in tests:
    - Single token path
    - Dual token path (only applicable to both tokens being base tokens and in range)
    */

    /**
     * SINGLE TOKEN PATHS ***
     */
    function test_onERC721Received_NativeToken_InRange() public {}

    function test_onERC721Received_NativeToken_BelowTickLower() public {}

    function test_onERC721Received_NativeToken_AboveTickUpper() public {}

    function test_onERC721Received_Token0BaseToken_InRange() public {}

    function test_onERC721Received_Token0BaseToken_BelowTickLower() public {}

    function test_onERC721Received_Token0BaseToken_AboveTickUpper() public {}

    function test_onERC721Received_Token1BaseToken_InRange() public {}

    function test_onERC721Received_Token1BaseToken_BelowTickLower() public {}

    function test_onERC721Received_Token1BaseToken_AboveTickUpper() public {}

    /**
     * DUAL TOKEN PATHS ***
     */
    function test_onERC721Received_NativeTokenandERC20BaseTokens_InRange() public {}

    function test_onERC721Received_BothTokensERC20andBaseTokens_InRange() public {}
}
