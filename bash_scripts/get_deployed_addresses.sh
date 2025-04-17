#!/bin/bash

# Start the JSON object
echo "{"

# First find all matching files and process them
# We'll use a temporary file to store intermediate results to avoid issues with subshells
find ./broadcast -name "run-latest.json" | while read file; do
    dir=$(basename $(dirname $(dirname "$file")))
    cleaned_dir=$(echo "$dir" | sed 's/^Deploy//' | cut -d. -f1)
    # Extract chainId from the file
    chainId=$(jq -r '.chain' "$file")
    # Extract contract address
    addr=$(jq -r '.transactions[].contractAddress' "$file" | grep -v null | head -n 1)
    if [ ! -z "$addr" ] && [ "$addr" != "null" ]; then
        echo "$chainId:$cleaned_dir:$addr"
    fi
done | sort -t: -k1,1 | awk -F: '
BEGIN { 
    prev_chain = ""; 
    first_chain = 1;
}
{
    if (prev_chain != $1) {
        if (prev_chain != "") printf "\n  },"
        if (first_chain) first_chain = 0
        else printf "\n"
        printf "  \"%s\": {\n", $1
        prev_chain = $1
        first_dir = 1
    }
    if (!first_dir) printf ",\n"
    printf "    \"%s\": \"%s\"", $2, $3
    first_dir = 0
}
END {
    if (prev_chain != "") printf "\n  }\n"
}' 

# Close the JSON object
echo "}"