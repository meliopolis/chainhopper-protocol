// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMigrator {
    error NotPositionManager();
    error ChainIdsAndSettlersLengthMismatch();
    error ChainSettlerNotSupported(uint32 chainId, address settler);
    error MissingTokenRoutes();
    error TooManyTokenRoutes();
    error AmountsCannotAllBeZero();
    error AmountCannotBeZero(address token);
    error TokensNotRouted();
    error TokenNotRouted(address token);

    event Migrated(
        bytes32 indexed migrationId,
        uint32 indexed destinationChainId,
        address indexed destinationSettler,
        address sender,
        address token,
        uint256 amount
    );

    struct TokenRoute {
        address token;
        bytes route;
    }

    struct MigrationParams {
        uint32 destinationChainId;
        address destinationSettler;
        TokenRoute[] tokenRoutes;
        uint256 amountOtherMin;
        bytes settlementParams;
    }
}
