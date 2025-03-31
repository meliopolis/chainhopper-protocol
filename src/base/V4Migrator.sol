// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap-universal-router/libraries/Commands.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IPositionManager} from "@uniswap-v4-periphery/interfaces/IPositionManager.sol";
import {IV4Router} from "@uniswap-v4-periphery/interfaces/IV4Router.sol";
import {Actions} from "@uniswap-v4-periphery/libraries/Actions.sol";
import {Migrator} from "./Migrator.sol";

abstract contract V4Migrator is IERC721Receiver, Migrator {
    using SafeERC20 for IERC20;

    IPositionManager private immutable positionManager;
    IUniversalRouter private immutable universalRouter;
    IPermit2 private immutable permit2;

    constructor(address _positionManager, address _universalRouter, address _permit2) {
        positionManager = IPositionManager(_positionManager);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IPermit2(_permit2);
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {
        if (msg.sender != address(positionManager)) revert NotPositionManager();

        _migrate(from, tokenId, data);

        return this.onERC721Received.selector;
    }

    function _liquidate(uint256 positionId)
        internal
        override
        returns (address, address, uint256, uint256, bytes memory)
    {
        // get pool key from the position
        (PoolKey memory poolKey,) = positionManager.getPoolAndPositionInfo(positionId);

        // cache balance before liquidation
        uint256 balance0Before = poolKey.currency0.balanceOfSelf();
        uint256 balance1Before = poolKey.currency1.balanceOfSelf();

        // liquidate the position
        bytes memory actions = abi.encodePacked(bytes1(uint8(Actions.BURN_POSITION)), bytes1(uint8(Actions.TAKE_PAIR)));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, 0, 0, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        return (
            Currency.unwrap(poolKey.currency0),
            Currency.unwrap(poolKey.currency1),
            poolKey.currency0.balanceOfSelf() - balance0Before,
            poolKey.currency1.balanceOfSelf() - balance1Before,
            abi.encode(poolKey)
        );
    }

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        internal
        override
        returns (uint256)
    {
        // decode pool key
        PoolKey memory poolKey = abi.decode(poolInfo, (PoolKey));

        // get currency in and out
        (Currency currencyIn, Currency currencyOut) =
            zeroForOne ? (poolKey.currency0, poolKey.currency1) : (poolKey.currency1, poolKey.currency0);

        // cache balance before swap
        uint256 balanceBefore = currencyOut.balanceOfSelf();

        // approve token transfer via permit2
        IERC20(Currency.unwrap(currencyIn)).safeIncreaseAllowance(address(permit2), amountIn);
        permit2.approve(Currency.unwrap(currencyIn), address(universalRouter), uint160(amountIn), 0);

        // prepare v4 router actions and params
        bytes memory actions = abi.encodePacked(
            bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE)), bytes1(uint8(Actions.TAKE_ALL)), bytes1(uint8(Actions.SETTLE))
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams(poolKey, zeroForOne, uint128(amountIn), uint128(amountOutMin), "")
        );
        params[1] = abi.encode(Currency.unwrap(currencyOut), 0);
        params[2] = abi.encode(Currency.unwrap(currencyIn), amountIn, true);

        // execute swap via universal router
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V4_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        universalRouter.execute(commands, inputs, block.timestamp);

        return currencyOut.balanceOfSelf() - balanceBefore;
    }

    receive() external payable {}
}
