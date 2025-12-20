#!/bin/bash
set -e
CAST=/home/jazz/.foundry/bin/cast
FORGE=/home/jazz/.foundry/bin/forge
RPC=http://127.0.0.1:32797
KEY=b3d2d558e3491a3709b7c451100a0366b5872520c7aa020c17a0e7fa35b6a8df

# Ensure we are in the script's directory (contracts-bedrock)
cd "$(dirname "$0")"

echo "Fetching Bytecodes..."
IMPL_CODE=$($FORGE inspect src/L1/RAT.sol:RAT bytecode)
PROXY_CODE=$(python3 extract_bytecode.py)

echo "Computing Addresses..."
IMPL_ADDR=$($CAST compute-address 0xD3F2c5AFb2D76f5579F326b0cD7DA5F5a4126c35 --nonce 500 --rpc-url $RPC | grep 'Computed Address' | awk '{print $3}')
PROXY_ADDR=$($CAST compute-address 0xD3F2c5AFb2D76f5579F326b0cD7DA5F5a4126c35 --nonce 501 --rpc-url $RPC | grep 'Computed Address' | awk '{print $3}')

echo "Impl Addr: $IMPL_ADDR"
echo "Proxy Addr: $PROXY_ADDR"

echo "Deploying Impl (Nonce 500)..."
$CAST send --rpc-url $RPC --private-key $KEY --nonce 500 --create $IMPL_CODE

echo "Deploying Proxy (Nonce 501)..."
# Admin Address encoded
ADMIN_ARG=000000000000000000000000D3F2c5AFb2D76f5579F326b0cD7DA5F5a4126c35
$CAST send --rpc-url $RPC --private-key $KEY --nonce 501 --create ${PROXY_CODE}${ADMIN_ARG}

echo "Initializing (Nonce 502)..."
INIT_DATA=$($CAST calldata "initialize(address,uint256,uint256,uint256,uint256,address)" $IMPL_ADDR 100000000000000000 60 1000000000000000000 50000 0xD3F2c5AFb2D76f5579F326b0cD7DA5F5a4126c35)
$CAST send --rpc-url $RPC --private-key $KEY --nonce 502 $PROXY_ADDR "upgradeToAndCall(address,bytes)" $IMPL_ADDR $INIT_DATA

echo "Deployment Complete!"
