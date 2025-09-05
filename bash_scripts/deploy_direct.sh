#!/bin/bash

source .env

# minimum balance to deploy, 0.01 ETH
minBalance=10000000000000000

# check wallet balance on all chains
for chain in $(echo $DEPLOY_CHAINS | tr ',' ' '); do
    rpc_var="${chain}_RPC_URL"
    balance=$(cast balance --rpc-url "${!rpc_var}" "${DEPLOY_INITIAL_OWNER}")
    balance_eth=$(echo "scale=4; if(${balance}/10^18 < 1) print 0; ${balance}/10^18" | bc)
    echo "Checking balance on chain ${chain}... ${balance_eth} ETH"
    if [ "$balance" -lt $minBalance ]; then
        echo "Insufficient balance on chain ${chain}"
        exit 1
    fi
done

# deploy settlers
for chain in $(echo $DEPLOY_CHAINS | tr ',' ' '); do
    rpc_var="${chain}_RPC_URL"
    etherscan_var="${chain}_ETHERSCAN_API_KEY"

    echo "Deploying UniswapV3DirectSettler on chain ${chain}..."
    if ! forge script script/DeployUniswapV3DirectSettler.s.sol:DeployUniswapV3DirectSettler \
    --rpc-url "${!rpc_var}" \
    --etherscan-api-key "${!etherscan_var}" \
    --broadcast \
    --delay 15 \
    --verify \
    --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
        echo "Failed to deploy UniswapV3DirectSettler on chain ${chain}"
        exit 1
    fi

    echo "Deploying UniswapV4DirectSettler on chain ${chain}..."
    if ! forge script script/DeployUniswapV4DirectSettler.s.sol:DeployUniswapV4DirectSettler \
    --rpc-url "${!rpc_var}" \
    --etherscan-api-key "${!etherscan_var}" \
    --broadcast \
    --delay 15 \
    --verify \
    --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
        echo "Failed to deploy UniswapV4DirectSettler on chain ${chain}"
        exit 1
    fi
done

# deploy migrators
for chain in $(echo $DEPLOY_CHAINS | tr ',' ' '); do
    rpc_var="${chain}_RPC_URL"
    etherscan_var="${chain}_ETHERSCAN_API_KEY"

    echo "Deploying UniswapV3DirectMigrator on chain ${chain}..."
    if ! forge script script/DeployUniswapV3DirectMigrator.s.sol:DeployUniswapV3DirectMigrator \
    --rpc-url "${!rpc_var}" \
    --broadcast \
    --delay 15 \
    --etherscan-api-key "${!etherscan_var}" \
    --verify \
    --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
        echo "Failed to deploy UniswapV3DirectMigrator on chain ${chain}"
        exit 1
    fi

    echo "Deploying UniswapV4DirectMigrator on chain ${chain}..."
    if ! forge script script/DeployUniswapV4DirectMigrator.s.sol:DeployUniswapV4DirectMigrator \
    --rpc-url "${!rpc_var}" \
    --broadcast \
    --delay 15 \
    --etherscan-api-key "${!etherscan_var}" \
    --verify \
    --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
        echo "Failed to deploy UniswapV4DirectMigrator on chain ${chain}"
        exit 1
    fi
done

echo "All Direct transfer contracts deployed successfully!"