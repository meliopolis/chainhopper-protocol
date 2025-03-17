// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMigrator {
    error NotPositionManager();
    error ChainSettlerNotSupported();
    error MisconfigedTokenRoutes();
    error AmountsCannotAllBeZero();
    error TokenNotRouted();

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
        bytes settlementParams;
    }
}
