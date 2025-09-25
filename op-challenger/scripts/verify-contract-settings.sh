#!/bin/bash

# Step 4: Contract Configuration Verification Script
# Usage: ./verify-contract-settings.sh [enclave_name]
# Default enclave: simple-devnet

set -e

ENCLAVE_NAME=${1:-simple-devnet}
TEMP_DIR="/tmp/devnet-desc"

echo "🚀 Contract Configuration Verification Started (Enclave: $ENCLAVE_NAME)"
echo "=================================================="

# Download environment file - try multiple sources
echo "📥 Downloading environment file..."
rm -rf $TEMP_DIR

# Method 1: Try devnet-descriptor-0 (legacy format)
if kurtosis files download $ENCLAVE_NAME devnet-descriptor-0 $TEMP_DIR 2>/dev/null; then
    if [ -f "$TEMP_DIR/env.json" ]; then
        echo "✅ Found env.json from devnet-descriptor-0"
        ENV_SOURCE="devnet-descriptor"
    fi
fi

# Method 2: If not found, try op-deployer-configs (new format)
if [ ! -f "$TEMP_DIR/env.json" ]; then
    echo "📥 Trying alternative: op-deployer-configs..."
    rm -rf $TEMP_DIR
    mkdir -p $TEMP_DIR

    if kurtosis files download $ENCLAVE_NAME op-deployer-configs $TEMP_DIR/configs 2>/dev/null; then
        # Create env.json from op-deployer configs
        if [ -f "$TEMP_DIR/configs/state.json" ]; then
            echo "✅ Found state.json from op-deployer-configs, converting to env.json format..."

            # Get service info from Kurtosis
            L1_RPC_PORT=$(kurtosis enclave inspect $ENCLAVE_NAME | grep "el-1-geth" -A5 | grep "rpc: 8545/tcp" | sed 's/.*127.0.0.1:\([0-9]*\).*/\1/')
            L2_RPC_PORT=$(kurtosis enclave inspect $ENCLAVE_NAME | grep "op-el.*op-geth" -A5 | grep "rpc: 8545/tcp" | sed 's/.*127.0.0.1:\([0-9]*\).*/\1/')

            # Extract addresses from state.json
            OPTIMISM_PORTAL=$(jq -r '.opChainDeployments[0].OptimismPortalProxy' $TEMP_DIR/configs/state.json)
            DISPUTE_GAME_FACTORY=$(jq -r '.opChainDeployments[0].DisputeGameFactoryProxy' $TEMP_DIR/configs/state.json)
            OPCM_ADDRESS=$(jq -r '.superchainDeployments.OPContractsManagerImpl // empty' $TEMP_DIR/configs/state.json)

            # Create env.json in expected format
            cat > $TEMP_DIR/env.json << EOF
{
  "l1": {
    "nodes": [
      {
        "services": {
          "el": {
            "endpoints": {
              "rpc": {
                "port": "$L1_RPC_PORT"
              }
            }
          }
        }
      }
    ],
    "addresses": {
      "OpcmImpl": "$OPCM_ADDRESS"
    }
  },
  "l2": [
    {
      "nodes": [
        {
          "services": {
            "el": {
              "endpoints": {
                "rpc": {
                  "port": "$L2_RPC_PORT"
                }
              }
            }
          }
        }
      ],
      "l1_addresses": {
        "OptimismPortalProxy": "$OPTIMISM_PORTAL",
        "DisputeGameFactoryProxy": "$DISPUTE_GAME_FACTORY"
      }
    }
  ]
}
EOF
            ENV_SOURCE="op-deployer-configs"
            echo "✅ Created env.json from op-deployer-configs"
        fi
    fi
fi

if [ ! -f "$TEMP_DIR/env.json" ]; then
    echo "❌ Error: Could not find or create env.json file!"
    echo "   Tried: devnet-descriptor-0 and op-deployer-configs"

    # Show available files for debugging
    echo ""
    echo "🔍 Available files in enclave:"
    kurtosis enclave inspect $ENCLAVE_NAME | grep -A 20 "Files Artifacts" || echo "Could not list files"
    exit 1
fi

# Extract RPC and contract addresses
echo "🔍 Extracting RPC and contract addresses..."

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq is not installed. Install with 'brew install jq' command."
    exit 1
fi

# Extract L1 RPC
L1_RPC_PORT=$(jq -r '.l1.nodes[0].services.el.endpoints.rpc.port' $TEMP_DIR/env.json)
L1_RPC="http://127.0.0.1:${L1_RPC_PORT}"

# Extract OptimismPortal address
OP_PORTAL=$(jq -r '.l2[0].l1_addresses.OptimismPortalProxy' $TEMP_DIR/env.json)

# OPContractsManager is optional
OPCM_ADDRESS=$(jq -r '.l1.addresses.OpcmImpl // empty' $TEMP_DIR/env.json 2>/dev/null || echo "")

# Basic contract configuration verification
echo ""
echo "🔍 Basic Contract Configuration Verification"
echo "L1 RPC: $L1_RPC"
echo "OptimismPortal: $OP_PORTAL"
echo "OPContractsManager: $OPCM_ADDRESS"

if [ -z "$L1_RPC" ] || [ -z "$OP_PORTAL" ]; then
    echo "❌ Error: Unable to extract required addresses!"
    exit 1
fi

# Test L1 RPC connection
echo ""
echo "🌐 Testing L1 RPC connection..."
if ! curl -s "$L1_RPC" >/dev/null; then
    echo "❌ Error: Cannot connect to L1 RPC!"
    exit 1
fi
echo "✅ L1 RPC connection successful"

# 4.1 Check OptimismPortal configuration
echo ""
echo "🎯 OptimismPortal Configuration Check"
RESPECTED_GAME_TYPE=$(cast call $OP_PORTAL "respectedGameType()(uint32)" --rpc-url $L1_RPC)
echo "   respectedGameType: $RESPECTED_GAME_TYPE"

# Check actual games from DisputeGameFactory
DISPUTE_GAME_FACTORY=$(jq -r '.l2[0].l1_addresses.DisputeGameFactoryProxy' $TEMP_DIR/env.json)
GAME_COUNT=$(cast call $DISPUTE_GAME_FACTORY "gameCount()(uint256)" --rpc-url $L1_RPC 2>/dev/null || echo "0")

echo "   DisputeGameFactory: $DISPUTE_GAME_FACTORY"
echo "   Created games count: $GAME_COUNT"

if [ "$GAME_COUNT" != "0" ]; then
    # Check latest game type
    LATEST_GAME_INDEX=$((GAME_COUNT - 1))
    LATEST_GAME_INFO=$(cast call $DISPUTE_GAME_FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_GAME_INDEX --rpc-url $L1_RPC)
    ACTUAL_GAME_TYPE=$(echo "$LATEST_GAME_INFO" | head -1)
    LATEST_GAME_ADDR=$(echo "$LATEST_GAME_INFO" | tail -1)

    echo "   Latest game type: $ACTUAL_GAME_TYPE (expected: 0 = CANNON)"
    echo "   Latest game address: $LATEST_GAME_ADDR"

    if [ "$ACTUAL_GAME_TYPE" = "0" ]; then
        echo "✅ Actually created game is CANNON type"
    else
        echo "❌ Error: Actually created game is not CANNON type!"
        VERIFICATION_FAILED=true
    fi
else
    echo "⚠️  Warning: No games created yet"
fi

# 4.2 Check contract version (optional - only if OPCM_ADDRESS exists)
if [ -n "$OPCM_ADDRESS" ] && [ "$OPCM_ADDRESS" != "null" ]; then
    echo ""
    echo "🏷️  Contract Version Check"
    DEPLOYMENT_VERSION=$(cast call $OPCM_ADDRESS "getDeploymentVersion()(string)" --rpc-url $L1_RPC 2>/dev/null || echo "N/A")
    echo "   Deployment version: $DEPLOYMENT_VERSION"

    if [[ "$DEPLOYMENT_VERSION" == *"fixed-disputeGameType"* ]]; then
        echo "✅ Contract version verification passed"
    else
        echo "⚠️  Warning: Cannot verify contract version or differs from expected"
    fi
fi

# 4.3 Check Dispute Game timing configuration
if [ -n "$LATEST_GAME_ADDR" ]; then
    echo ""
    echo "⏰ Dispute Game Timing Configuration Check"
    MAX_CLOCK_DURATION=$(cast call $LATEST_GAME_ADDR "maxClockDuration() returns (uint64)" --rpc-url $L1_RPC 2>/dev/null || echo "0")
    CLOCK_EXTENSION=$(cast call $LATEST_GAME_ADDR "clockExtension() returns (uint64)" --rpc-url $L1_RPC 2>/dev/null || echo "0")
    GAME_STATUS=$(cast call $LATEST_GAME_ADDR "status() returns (uint8)" --rpc-url $L1_RPC 2>/dev/null || echo "N/A")

    echo "   maxClockDuration: ${MAX_CLOCK_DURATION}s (expected: 1200 = 20min)"
    echo "   clockExtension: ${CLOCK_EXTENSION}s (expected: 300 = 5min)"
    echo "   Game status: $GAME_STATUS (0=IN_PROGRESS, 1=CHALLENGER_WINS, 2=DEFENDER_WINS)"

    # Verification
    if [ "$MAX_CLOCK_DURATION" = "1200" ] && [ "$CLOCK_EXTENSION" = "300" ]; then
        echo "✅ Dispute Game timing configuration verification passed"
    else
        echo "❌ Error: Dispute Game timing configuration is incorrect!"
        echo "   Current values - maxClockDuration: $MAX_CLOCK_DURATION, clockExtension: $CLOCK_EXTENSION"
        echo "   Expected values - maxClockDuration: 1200, clockExtension: 300"
        VERIFICATION_FAILED=true
    fi
elif [ "$GAME_COUNT" = "0" ]; then
    echo ""
    echo "⚠️  Warning: No dispute games created yet"
    echo "   With 10min proposal_interval, more time may be needed"
fi

# Check account balances
echo ""
echo "💰 Test Account Balance Check"

# Main test accounts
ACCOUNTS=(
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"  # Account 0
    "0x70997970C51812dc3A010C7d01b50e0d17dc79c8"  # Account 1
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"  # Account 2
)

# Check balances
MAX_BALANCE=0
SELECTED_ACCOUNT=""
HAS_FUNDED_ACCOUNT=false

for i in "${!ACCOUNTS[@]}"; do
    ACCOUNT=${ACCOUNTS[$i]}
    BALANCE=$(cast balance $ACCOUNT --rpc-url $L1_RPC 2>/dev/null || echo "0")
    BALANCE_ETH=$(cast --to-unit $BALANCE ether 2>/dev/null || echo "0")

    echo "   Account $i ($ACCOUNT): ${BALANCE_ETH} ETH"

    # Check if there's non-zero balance
    if [ "$BALANCE" != "0" ]; then
        HAS_FUNDED_ACCOUNT=true
        if [ $(echo "$BALANCE > $MAX_BALANCE" | bc -l 2>/dev/null || echo "0") = "1" ]; then
            MAX_BALANCE=$BALANCE
            SELECTED_ACCOUNT=$ACCOUNT
        fi
    fi
done

if [ "$HAS_FUNDED_ACCOUNT" = "true" ]; then
    echo "✅ Funded account found: $SELECTED_ACCOUNT"
    echo "   Maximum balance: $(cast --to-unit $MAX_BALANCE ether) ETH"
else
    echo "❌ Error: All accounts have zero balance!"
    echo "   Check prefunded_accounts setting in simple.yaml"
    VERIFICATION_FAILED=true
fi

# Final result
echo ""
echo "=================================================="
if [ "$VERIFICATION_FAILED" = "true" ]; then
    echo "❌ Contract configuration verification failed!"
    echo "Please fix the above errors and try again."
    exit 1
else
    echo "✅ Contract configuration verification successful!"
    echo "All configurations are properly set up."
fi