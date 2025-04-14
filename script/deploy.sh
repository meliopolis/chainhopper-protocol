source ../.env

temp_txt="temp.txt"
touch $temp_txt

for chain in $DEPLOY_CHAINS; do
    rpc_var="${chain}_RPC_URL"
    etherscan_var="${chain}_ETHERSCAN_API_KEY"

    forge script DeployUniswapV3AcrossSettler.s.sol:DeployUniswapV3AcrossSettler \
    --rpc-url "${!rpc_var}" \
    --etherscan-api-key "${!etherscan_var}" \
    --broadcast \
    --verify \
    --sig 'run(string,address,string)' "${chain}" "${DEPLOY_INITIAL_OWNER}" "script/${temp_txt}"

    forge script DeployUniswapV4AcrossSettler.s.sol:DeployUniswapV4AcrossSettler \
    --rpc-url "${!rpc_var}" \
    --etherscan-api-key "${!etherscan_var}" \
    --broadcast \
    --verify \
    --sig 'run(string,address,string)' "${chain}" "${DEPLOY_INITIAL_OWNER}" "script/${temp_txt}"
done

for chain in $DEPLOY_CHAINS; do
    rpc_var="${chain}_RPC_URL"
    etherscan_var="${chain}_ETHERSCAN_API_KEY"

    forge script DeployUniswapV3AcrossMigrator.s.sol:DeployUniswapV3AcrossMigrator \
    --rpc-url "${!rpc_var}" \
    --etherscan-api-key "${!etherscan_var}" \
    --broadcast \
    --verify \
    --sig 'run(string,address,string)' "${chain}" "${DEPLOY_INITIAL_OWNER}" "script/${temp_txt}"

    forge script script/DeployUniswapV4AcrossMigrator.s.sol:DeployUniswapV4AcrossMigrator \
    --rpc-url "${!rpc_var}" \
    --etherscan-api-key "${!etherscan_var}" \
    --broadcast \
    --verify \
    --sig 'run(string,address,string)' "${chain}" "${DEPLOY_INITIAL_OWNER}" "script/${temp_txt}"
done

rm $temp_txt
