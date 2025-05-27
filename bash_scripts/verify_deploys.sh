#!/bin/bash

source .env

# Function to get chain name from chain id
get_chain_name() {
    local chain_id=$1
    local i=0
    IFS=',' read -ra CHAIN_IDS <<< "$DEPLOY_CHAIN_IDS"
    IFS=',' read -ra CHAIN_NAMES <<< "$DEPLOY_CHAINS"
    for cid in "${CHAIN_IDS[@]}"; do
        if [ "$cid" = "$chain_id" ]; then
            echo "${CHAIN_NAMES[$i]}"
            return
        fi
        i=$((i+1))
    done
    echo "UNKNOWN"
}

# Function to get owner of a contract
get_owner() {
    local address=$1
    local chain_name=$2
    local rpc_var="${chain_name}_RPC_URL"
    cast call --rpc-url "${!rpc_var}" "$address" "owner()(address)" 2>/dev/null || echo "N/A"
}

# Function to check if settler is registered in migrator
check_settler_registration() {
    local migrator_address=$1
    local migrator_chain_name=$2
    local settler_chain_id=$3
    local settler_address=$4
    local rpc_var="${migrator_chain_name}_RPC_URL"
    
    # Call chainSettlers(uint256,address) function
    local is_registered=$(cast call --rpc-url "${!rpc_var}" "$migrator_address" "chainSettlers(uint256,address)(bool)" "$settler_chain_id" "$settler_address" 2>/dev/null || echo "N/A")
    echo "$is_registered"
}

# Function to get settler specific details
get_settler_details() {
    local address=$1
    local chain_name=$2
    local rpc_var="${chain_name}_RPC_URL"
    
    # Get protocol share bps
    local protocol_share=$(cast call --rpc-url "${!rpc_var}" "$address" "protocolShareBps()(uint16)" 2>/dev/null || echo "N/A")
    
    # Get protocol fee recipient
    local fee_recipient=$(cast call --rpc-url "${!rpc_var}" "$address" "protocolFeeRecipient()(address)" 2>/dev/null || echo "N/A")
    
    # Get protocol share of sender fee percentage
    local share_of_sender_fee=$(cast call --rpc-url "${!rpc_var}" "$address" "protocolShareOfSenderFeePct()(uint8)" 2>/dev/null || echo "N/A")
    
    echo "    Protocol Share BPS: $protocol_share"
    echo "    Protocol Fee Recipient: $fee_recipient"
    echo "    Protocol Share of Sender Fee %: $share_of_sender_fee"
}

# Function to print contract details
print_contract_details() {
    local name=$1
    local address=$2
    local chain_name=$3
    local temp_file=$4
    
    echo "  $name:"
    echo "    Address: $address"
    echo "    Owner: $(get_owner "$address" "$chain_name")"
    
    if [[ $name == *"Settler"* ]]; then
        get_settler_details "$address" "$chain_name"
    fi
    
    if [[ $name == *"Migrator"* ]]; then
        echo "    Registered Settlers:"
        # Get all settlers from other chains
        grep "Settler" "$temp_file" | while IFS=$'\t' read -r settler_chain_id settler_name settler_address; do
            if [ "$settler_chain_id" != "$chain_id" ]; then
                local is_registered=$(check_settler_registration "$address" "$chain_name" "$settler_chain_id" "$settler_address")
                local settler_chain_name=$(get_chain_name "$settler_chain_id")
                echo "      $settler_chain_name ($settler_chain_id) - $settler_name: $is_registered"
            fi
        done
    fi
    echo ""
}

# Read JSON from stdin (output of getDeployAddresses.sh)
json_input=$(cat | tr -d '\r')

# Create a temporary file to store the sorted data
temp_file=$(mktemp)
echo "$json_input" | jq -r 'to_entries[] | .key as $chain | .value | to_entries[] | [$chain, .key, .value] | @tsv' > "$temp_file"

# Process each chain
for chain_id in $(cut -f1 "$temp_file" | sort -u); do
    chain_name=$(get_chain_name "$chain_id")
    echo "Chain: $chain_name (ID: $chain_id)"
    echo "----------------------------------------"
    
    # First print migrators
    grep "^$chain_id" "$temp_file" | grep "Migrator" | sort | while IFS=$'\t' read -r _ name address; do
        print_contract_details "$name" "$address" "$chain_name" "$temp_file"
    done
    
    # Then print settlers
    grep "^$chain_id" "$temp_file" | grep "Settler" | sort | while IFS=$'\t' read -r _ name address; do
        print_contract_details "$name" "$address" "$chain_name" "$temp_file"
    done
    
    # Finally print any other contracts
    grep "^$chain_id" "$temp_file" | grep -v "Migrator" | grep -v "Settler" | sort | while IFS=$'\t' read -r _ name address; do
        print_contract_details "$name" "$address" "$chain_name" "$temp_file"
    done
    
    echo "========================================"
    echo ""
done

# Clean up temporary file
rm -f "$temp_file"