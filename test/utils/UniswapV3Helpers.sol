// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console, Vm} from "lib/forge-std/src/Test.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/external/INonfungiblePositionManager.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "@uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap-v3-core/interfaces/IUniswapV3Pool.sol";

contract UniswapV3Helpers is Test {
    function getCurrentTick(address nftPositionManager, address token0, address token1, uint24 fee)
        public
        view
        returns (int24)
    {
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));
        (, int24 currentTick,,,,,) = pool.slot0();
        return currentTick;
    }

    function mintV3Position(
        address nftPositionManager,
        address user,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) public returns (uint256, uint256, uint256) {
        // give user eth and usdc
        deal(token0, user, 10_000_000_000_000_000_000_000);
        deal(token1, user, 10_000_000_000_000_000_000_000);
        // mint v3 position
        vm.prank(user);
        IERC20(token0).approve(nftPositionManager, 1_000_000_000_000_000_000);
        vm.prank(user);
        IERC20(token1).approve(nftPositionManager, 1000_000_000);

        vm.prank(user);
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: 1_000_000_000_000_000_000,
            amount1Desired: 1000_000_000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp
        });
        (uint256 tokenId,, uint256 amount0, uint256 amount1) =
            INonfungiblePositionManager(nftPositionManager).mint(mintParams);
        // return position id
        return (tokenId, amount0, amount1);
    }

    function withdrawLiquidity(address nftPositionManager, address user, uint256 tokenId) public {
        (,,,,,,, uint128 liquidity,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        vm.prank(user);
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        INonfungiblePositionManager(nftPositionManager).decreaseLiquidity(decreaseLiquidityParams);
    }

    function findSwapEvents(Vm.Log[] memory logs) public view returns (Vm.Log[] memory) {
        bytes32 topic0 = keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");
        Vm.Log[] memory swapEvents = new Vm.Log[](1); // only have one swap event

        for (uint256 i = 0; i < logs.length; i++) {
            // skip events emitted by this contract
            if (logs[i].topics[0] == topic0 && logs[i].emitter != address(this)) {
                swapEvents[0] = logs[i];
                return swapEvents;
            }
        }
        return new Vm.Log[](0);
    }

    function findMintEvent(Vm.Log[] memory logs) public view returns (Vm.Log memory) {
        bytes32 topic0 = keccak256("Mint(address,address,int24,int24,uint128,uint256,uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            // skip events emitted by this contract
            if (logs[i].topics[0] == topic0 && logs[i].emitter != address(this)) {
                return logs[i];
            }
        }
        revert();
    }

    function parseSwapEvent(bytes memory data) public pure returns (uint256) {
        (int256 outputAmount0, int256 outputAmount1) = abi.decode(data, (int256, int256));
        if (outputAmount0 < 0) {
            return uint256(outputAmount0 * -1);
        }
        return uint256(outputAmount1 * -1);
    }

    function parseSwapEventForBothAmounts(bytes memory data)
        public
        pure
        returns (uint256 amountIn, uint256 amountOut)
    {
        (int256 outputAmount0, int256 outputAmount1) = abi.decode(data, (int256, int256));
        if (outputAmount0 < 0) {
            amountIn = uint256(outputAmount1);
            amountOut = uint256(outputAmount0 * -1);
        } else {
            amountIn = uint256(outputAmount0);
            amountOut = uint256(outputAmount1 * -1);
        }
        return (amountIn, amountOut);
    }

    function parseMintEvent(bytes memory data) public pure returns (uint256 amount0, uint256 amount1) {
        (,, amount0, amount1) = abi.decode(data, (address, uint128, uint256, uint256));
        return (amount0, amount1);
    }

    // add this to be excluded from coverage report
    function test() public virtual {}
}
