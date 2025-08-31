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

    echo "Deploying UniswapV3AcrossSettler on chain ${chain}..."
    if ! forge script script/DeployUniswapV3AcrossSettler.s.sol:DeployUniswapV3AcrossSettler \
    --rpc-url "${!rpc_var}" \
    --etherscan-api-key "${!etherscan_var}" \
    --broadcast \
    --delay 15 \
    --verify \
    --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
        echo "Failed to deploy UniswapV3AcrossSettler on chain ${chain}"
        exit 1
    fi

    echo "Deploying UniswapV4AcrossSettler on chain ${chain}..."
    if ! forge script script/DeployUniswapV4AcrossSettler.s.sol:DeployUniswapV4AcrossSettler \
    --rpc-url "${!rpc_var}" \
    --etherscan-api-key "${!etherscan_var}" \
    --broadcast \
    --delay 15 \
    --verify \
    --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
        echo "Failed to deploy UniswapV4AcrossSettler on chain ${chain}"
        exit 1
    fi

    # Deploy Aerodrome Settler only on BASE
    if [ "${chain}" = "BASE" ]; then
        echo "Deploying AerodromeAcrossSettler on chain ${chain}..."
        if ! forge script script/DeployAerodromeAcrossSettler.s.sol:DeployAerodromeAcrossSettler \
        --rpc-url "${!rpc_var}" \
        --etherscan-api-key "${!etherscan_var}" \
        --broadcast \
        --delay 15 \
        --verify \
        --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
            echo "Failed to deploy AerodromeAcrossSettler on chain ${chain}"
            exit 1
        fi
    fi
done

# deploy migrators
for chain in $(echo $DEPLOY_CHAINS | tr ',' ' '); do
    rpc_var="${chain}_RPC_URL"
    etherscan_var="${chain}_ETHERSCAN_API_KEY"

    echo "Deploying UniswapV3AcrossMigrator on chain ${chain}..."
    if ! forge script script/DeployUniswapV3AcrossMigrator.s.sol:DeployUniswapV3AcrossMigrator \
    --rpc-url "${!rpc_var}" \
    --broadcast \
    --delay 15 \
    --etherscan-api-key "${!etherscan_var}" \
    --verify \
    --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
        echo "Failed to deploy UniswapV3AcrossMigrator on chain ${chain}"
        exit 1
    fi

    echo "Deploying UniswapV4AcrossMigrator on chain ${chain}..."
    if ! forge script script/DeployUniswapV4AcrossMigrator.s.sol:DeployUniswapV4AcrossMigrator \
    --rpc-url "${!rpc_var}" \
    --broadcast \
    --delay 15 \
    --etherscan-api-key "${!etherscan_var}" \
    --verify \
    --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
        echo "Failed to deploy UniswapV4AcrossMigrator on chain ${chain}"
        exit 1
    fi

    # Deploy Aerodrome Migrator only on BASE
    if [ "${chain}" = "BASE" ]; then
        echo "Deploying AerodromeAcrossMigrator on chain ${chain}..."
        if ! forge script script/DeployAerodromeAcrossMigrator.s.sol:DeployAerodromeAcrossMigrator \
        --rpc-url "${!rpc_var}" \
        --etherscan-api-key "${!etherscan_var}" \
        --broadcast \
        --delay 15 \
        --verify \
        --sig 'run(string,address)' "${chain}" "${DEPLOY_INITIAL_OWNER}"; then
            echo "Failed to deploy AerodromeAcrossMigrator on chain ${chain}"
            exit 1
        fi
    fi
done
