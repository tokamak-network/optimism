#!/bin/bash
set -e
cd "$(dirname "$0")"

CAST=/home/jazz/.foundry/bin/cast
FORGE=/home/jazz/.foundry/bin/forge
RPC=${L1_RPC:-http://127.0.0.1:33012}
KEY=b3d2d558e3491a3709b7c451100a0366b5872520c7aa020c17a0e7fa35b6a8df
ADDR=0xD3F2c5AFb2D76f5579F326b0cD7DA5F5a4126c35

echo "Using Admin Identity: $ADDR"

# Save Credentials
echo "PRIVATE_KEY=$KEY" > ../../test_credentials.env
echo "ADDRESS=$ADDR" >> ../../test_credentials.env

echo "Deploying Implementation (RAT)..."
IMPL_OUTPUT=$($FORGE create --rpc-url $RPC --private-key $KEY --legacy --broadcast src/L1/RAT.sol:RAT 2>&1)
IMPL_ADDR=$(echo "$IMPL_OUTPUT" | grep "Deployed to:" | awk '{print $3}')

if [ -z "$IMPL_ADDR" ]; then
    echo "Failed to deploy Implementation. Output:"
    echo "$IMPL_OUTPUT"
    exit 1
fi
echo "Implementation deployed at: $IMPL_ADDR"

echo "Deploying Proxy..."
PROXY_CODE=$(python3 extract_bytecode.py)
ADMIN_ARG=000000000000000000000000D3F2c5AFb2D76f5579F326b0cD7DA5F5a4126c35
FULL_PROXY_CODE="${PROXY_CODE}${ADMIN_ARG}"

# Use cast send with --create (flags before --create)
PROXY_OUTPUT=$($CAST send --rpc-url $RPC --private-key $KEY --legacy --gas-price 100gwei --create "$FULL_PROXY_CODE" 2>&1)
PROXY_ADDR=$(echo "$PROXY_OUTPUT" | grep "contractAddress" | awk '{print $2}')

if [ -z "$PROXY_ADDR" ]; then
    echo "Failed to deploy Proxy. Output:"
    echo "$PROXY_OUTPUT"
    exit 1
fi
echo "Proxy deployed at: $PROXY_ADDR"

echo "Initializing Proxy..."
INIT_DATA=$($CAST calldata "initialize(address,uint256,uint256,uint256,uint256,address)" $IMPL_ADDR 100000000000000000 60 1000000000000000000 50000 $ADDR)

for (( i=1; i<=10; i++ )); do
    if $CAST send --rpc-url $RPC --private-key $KEY $PROXY_ADDR "upgradeToAndCall(address,bytes)" $IMPL_ADDR $INIT_DATA --legacy --gas-price 100gwei > /dev/null 2>&1; then
        echo "Initialized successfully."
        break
    fi
    echo "Init attempt $i failed, retrying..."
    sleep 2
done

# Write info
echo "$PROXY_ADDR" > ../../deployment_info.txt
echo "RAT_PROXY=$PROXY_ADDR" >> ../../deployed_config.env
echo "RAT_IMPL=$IMPL_ADDR" >> ../../deployed_config.env

echo "Deployment Success. Proxy: $PROXY_ADDR"
