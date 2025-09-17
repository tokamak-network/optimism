#!/bin/bash

# Dispute Game State Checker
# Usage: ./check-game-state.sh <game_address> [l1_rpc]

set -e

GAME_ADDRESS=$1
L1_RPC=$2

# Auto-detect L1 RPC if not provided
if [[ -z "$L1_RPC" ]]; then
    TEMP_DIR="/tmp/devnet-desc"
    if [ -f "$TEMP_DIR/env.json" ]; then
        L1_RPC_PORT=$(jq -r '.l1.nodes[0].services.el.endpoints.rpc.port' $TEMP_DIR/env.json 2>/dev/null || echo "")
        if [[ -n "$L1_RPC_PORT" ]]; then
            L1_RPC="http://127.0.0.1:${L1_RPC_PORT}"
        else
            L1_RPC="http://127.0.0.1:57834"  # fallback
        fi
    else
        L1_RPC="http://127.0.0.1:57834"  # fallback
    fi
fi

if [[ -z "$GAME_ADDRESS" ]]; then
    echo "❌ Error: Game address is required"
    echo "Usage: $0 <game_address> [l1_rpc_url]"
    echo ""
    echo "Examples:"
    echo "  $0 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E"
    echo "  $0 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E http://127.0.0.1:8545"
    exit 1
fi

echo "🎮 Dispute Game Status Check"
echo "============================"
echo "Game: $GAME_ADDRESS"
echo "RPC: $L1_RPC"
echo ""

# Basic status
echo "📊 Basic Status"
STATUS=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "status() returns (uint8)" 2>/dev/null || echo "ERROR")
case $STATUS in
    0) echo "   🟡 Status: IN_PROGRESS" ;;
    1) echo "   🔴 Status: CHALLENGER_WINS" ;;
    2) echo "   🟢 Status: DEFENDER_WINS" ;;
    ERROR) echo "   ❌ Error: Cannot fetch game status" ; exit 1 ;;
    *) echo "   ❓ Status: UNKNOWN ($STATUS)" ;;
esac

# Timing information
echo ""
echo "⏰ Timing Information"
CREATED_AT_RAW=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "createdAt() returns (uint64)" 2>/dev/null || echo "0")

# Convert scientific notation to decimal if needed
if [[ "$CREATED_AT_RAW" =~ \[.*\] ]]; then
    CREATED_AT=$(echo "$CREATED_AT_RAW" | awk '{print $1}')
else
    CREATED_AT="$CREATED_AT_RAW"
fi

# Convert to integer if it contains 'e' (scientific notation)
if [[ "$CREATED_AT" =~ e ]]; then
    CREATED_AT=$(printf "%.0f" "$CREATED_AT")
fi

if [[ "$CREATED_AT" != "0" ]] && [[ -n "$CREATED_AT" ]]; then
    echo "   📅 Created: $(date -r $CREATED_AT '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $CREATED_AT)"

    # Check if resolved
    if [[ $STATUS != "0" ]]; then
        RESOLVED_AT_RAW=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "resolvedAt() returns (uint64)" 2>/dev/null || echo "0")

        # Convert scientific notation to decimal if needed
        if [[ "$RESOLVED_AT_RAW" =~ \[.*\] ]]; then
            RESOLVED_AT=$(echo "$RESOLVED_AT_RAW" | awk '{print $1}')
        else
            RESOLVED_AT="$RESOLVED_AT_RAW"
        fi

        # Convert to integer if it contains 'e' (scientific notation)
        if [[ "$RESOLVED_AT" =~ e ]]; then
            RESOLVED_AT=$(printf "%.0f" "$RESOLVED_AT")
        fi

        if [[ "$RESOLVED_AT" != "0" ]] && [[ -n "$RESOLVED_AT" ]]; then
            echo "   ✅ Resolved: $(date -r $RESOLVED_AT '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $RESOLVED_AT)"
            DURATION=$((RESOLVED_AT - CREATED_AT))
            echo "   ⏱️  Duration: $DURATION seconds ($(($DURATION/60))m $(($DURATION%60))s)"
        fi
    fi
else
    echo "   ❌ Error: Cannot fetch creation time"
fi

# Game configuration
echo ""
echo "⚙️ Game Configuration"
MAX_CLOCK=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "maxClockDuration() returns (uint64)" 2>/dev/null || echo "0")
CLOCK_EXT=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "clockExtension() returns (uint64)" 2>/dev/null || echo "0")
echo "   ⏰ Max Clock: ${MAX_CLOCK}s ($(($MAX_CLOCK/60))m)"
echo "   ➕ Extension: ${CLOCK_EXT}s ($(($CLOCK_EXT/60))m)"

# State information
echo ""
echo "🎯 State Information"
ROOT_CLAIM=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "rootClaim() returns (bytes32)" 2>/dev/null || echo "ERROR")
L2_BLOCK=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "l2BlockNumber() returns (uint256)" 2>/dev/null || echo "ERROR")
ABSOLUTE_PRESTATE=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "absolutePrestate() returns (bytes32)" 2>/dev/null || echo "ERROR")

echo "   🎯 Root Claim: $ROOT_CLAIM"
echo "   📦 L2 Block: $L2_BLOCK"
echo "   🏁 Absolute Prestate: $ABSOLUTE_PRESTATE"

# Dispute tree information
echo ""
echo "🌳 Dispute Tree"
CLAIM_COUNT=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "claimDataLen() returns (uint256)" 2>/dev/null || echo "ERROR")
echo "   📝 Total Claims: $CLAIM_COUNT"

if [[ "$CLAIM_COUNT" != "ERROR" ]] && [[ "$CLAIM_COUNT" != "0" ]]; then
    echo "   📋 Root Claim Details:"
    ROOT_CLAIM_DATA=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "claimData(uint256) returns (uint32,address,uint128,uint128,bytes32,uint256,uint256)" 0 2>/dev/null || echo "ERROR")
    if [[ "$ROOT_CLAIM_DATA" != "ERROR" ]]; then
        # Parse the returned data
        echo "   $ROOT_CLAIM_DATA" | while read -r line; do
            echo "      $line"
        done
    fi
fi

echo ""
echo "✅ Game state check completed!"