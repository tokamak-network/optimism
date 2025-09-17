#!/bin/bash

# Auto Resolve Dispute Game Script
# Usage: ./auto-resolve-game.sh <game_address> [wait_minutes] [l1_rpc_url] [private_key]

set -e

# Default values
DEFAULT_WAIT_MINUTES=20
DEFAULT_L1_RPC="http://127.0.0.1:57834"
DEFAULT_PRIVATE_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

# Parse arguments
GAME_ADDRESS="${1}"
WAIT_MINUTES="${2:-$DEFAULT_WAIT_MINUTES}"
L1_RPC="${3:-$DEFAULT_L1_RPC}"
PRIVATE_KEY="${4:-$DEFAULT_PRIVATE_KEY}"

# Validate inputs
if [[ -z "$GAME_ADDRESS" ]]; then
    echo "❌ Error: Game address is required"
    echo "Usage: $0 <game_address> [wait_minutes] [l1_rpc_url] [private_key]"
    echo ""
    echo "Examples:"
    echo "  $0 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E"
    echo "  $0 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E 20"
    echo "  $0 0xb153c997C491E8E0e8eCe951f15449fe7a0Ea40E 20 http://127.0.0.1:8545"
    exit 1
fi

if ! [[ "$WAIT_MINUTES" =~ ^[0-9]+$ ]]; then
    echo "❌ Error: wait_minutes must be a number"
    exit 1
fi

echo "🎮 Auto Resolve Dispute Game"
echo "================================"
echo "📍 Game Address: $GAME_ADDRESS"
echo "⏰ Wait Duration: $WAIT_MINUTES minutes"
echo "🌐 L1 RPC: $L1_RPC"
echo "🔑 Private Key: ${PRIVATE_KEY:0:10}..."
echo ""

# Check game creation time
echo "🔍 Checking game status..."
CREATED_AT_RAW=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "createdAt() returns (uint256)" 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Convert scientific notation to decimal if needed
if [[ "$CREATED_AT_RAW" =~ \[.*\] ]]; then
    # Extract the number before the bracket
    CREATED_AT=$(echo "$CREATED_AT_RAW" | awk '{print $1}')
else
    CREATED_AT="$CREATED_AT_RAW"
fi

# Convert to integer if it contains 'e' (scientific notation)
if [[ "$CREATED_AT" =~ e ]]; then
    CREATED_AT=$(printf "%.0f" "$CREATED_AT")
fi

if [[ "$CREATED_AT" == "0" ]] || [[ -z "$CREATED_AT" ]]; then
    echo "❌ Error: Could not fetch game creation time. Check game address and RPC URL."
    echo "   Raw output: $CREATED_AT_RAW"
    exit 1
fi

ELAPSED=$((CURRENT_TIME - CREATED_AT))
WAIT_SECONDS=$((WAIT_MINUTES * 60))
REMAINING=$((CREATED_AT + WAIT_SECONDS - CURRENT_TIME))

echo "📅 Game created at: $(date -r $CREATED_AT '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$CREATED_AT" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")"
echo "🕐 Current time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "⏳ Elapsed time: $ELAPSED seconds ($(($ELAPSED/60))m $(($ELAPSED%60))s)"

if [[ $REMAINING -le 0 ]]; then
    echo "✅ Game is already eligible for resolution!"
    REMAINING=0
else
    echo "⏳ Time until resolution: $REMAINING seconds ($(($REMAINING/60))m $(($REMAINING%60))s)"
fi

# Check current game status
GAME_STATUS=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "status() returns (uint8)" 2>/dev/null || echo "255")
case $GAME_STATUS in
    0) echo "🟡 Game Status: IN_PROGRESS" ;;
    1) echo "🔴 Game Status: CHALLENGER_WINS" ;;
    2) echo "🟢 Game Status: DEFENDER_WINS" ;;
    *) echo "❓ Game Status: UNKNOWN ($GAME_STATUS)" ;;
esac

if [[ $GAME_STATUS != "0" ]]; then
    echo "⚠️  Game is already resolved. No action needed."
    exit 0
fi

# Check if there are challengers (more than 1 claim)
CLAIM_COUNT=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "claimDataLen() returns (uint256)" 2>/dev/null || echo "1")
echo "🌳 Claims in dispute tree: $CLAIM_COUNT"

if [[ $CLAIM_COUNT == "1" ]]; then
    echo "ℹ️  No challengers detected (only root claim exists)"
    echo "   This is normal for uncontested games and will resolve after $WAIT_MINUTES minutes"
    echo "   Resolution process: resolveClaim(0,0) → resolve()"
fi

# Add buffer time for safety
BUFFER_SECONDS=30
TOTAL_WAIT=$((REMAINING + BUFFER_SECONDS))

if [[ $TOTAL_WAIT -gt 0 ]]; then
    echo ""
    # Calculate resolution time (macOS compatible)
    RESOLUTION_TIME=$((CURRENT_TIME + TOTAL_WAIT))
    RESOLUTION_DATE=$(date -r $RESOLUTION_TIME '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$RESOLUTION_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
    echo "⏰ Scheduling resolution for: $RESOLUTION_DATE (+${BUFFER_SECONDS}s buffer)"
    echo "🤖 Waiting $TOTAL_WAIT seconds..."

    # Create a background job to wait and then resolve
    (
        sleep $TOTAL_WAIT
        echo ""
        echo "🎯 Executing resolve() at $(date)..."

        # Execute the resolve transaction
        echo "🔧 Attempting resolve with:"
        echo "   RPC: $L1_RPC"
        echo "   Game: $GAME_ADDRESS"
        echo "   Account: $(cast wallet address --private-key "$PRIVATE_KEY")"

        # First try resolveClaim for root claim (index 0)
        echo ""
        echo "🎯 Step 1: Resolving root claim (index 0)..."
        RESOLVE_CLAIM_RESULT=$(cast send --rpc-url "$L1_RPC" \
            --private-key "$PRIVATE_KEY" \
            "$GAME_ADDRESS" \
            "resolveClaim(uint256,uint256)" 0 0 2>&1)

        if [[ $? -ne 0 ]]; then
            echo "⚠️  resolveClaim failed (this may be normal): $RESOLVE_CLAIM_RESULT"
            echo "🎯 Proceeding with direct resolve()..."
        else
            echo "✅ resolveClaim successful: $RESOLVE_CLAIM_RESULT"
            echo "⏳ Waiting 2 seconds before resolve()..."
            sleep 2
        fi

        # Then try resolve() for the entire game
        echo ""
        echo "🎯 Step 2: Resolving entire game..."
        TX_RESULT=$(cast send --rpc-url "$L1_RPC" \
            --private-key "$PRIVATE_KEY" \
            "$GAME_ADDRESS" \
            "resolve()" 2>&1)

        if [[ $? -ne 0 ]]; then
            echo "❌ Failed to send resolve transaction"
            echo "🔍 Error details: $TX_RESULT"

            # Check if game can be resolved
            echo "🔍 Checking if game can be resolved..."
            CAN_RESOLVE=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "status() returns (uint8)" 2>/dev/null || echo "ERROR")
            echo "   Game status: $CAN_RESOLVE (0=IN_PROGRESS, 1=CHALLENGER_WINS, 2=DEFENDER_WINS)"

            # Check account balance
            ACCOUNT=$(cast wallet address --private-key "$PRIVATE_KEY")
            BALANCE=$(cast balance "$ACCOUNT" --rpc-url "$L1_RPC" 2>/dev/null || echo "ERROR")
            echo "   Account balance: $BALANCE"

            exit 1
        fi

        TX_HASH="$TX_RESULT"

        echo "✅ Resolve transaction sent!"
        echo "📄 Transaction hash: $TX_HASH"

        # Wait for confirmation
        echo "⏳ Waiting for transaction confirmation..."
        sleep 5

        # Check final game status and detailed results
        echo ""
        echo "🎯 Resolution Results:"
        echo "===================="

        FINAL_STATUS=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "status() returns (uint8)" 2>/dev/null || echo "255")
        case $FINAL_STATUS in
            0) echo "🟡 Final Status: IN_PROGRESS (resolution may need more time)" ;;
            1) echo "🔴 Final Status: CHALLENGER_WINS" ;;
            2) echo "🟢 Final Status: DEFENDER_WINS" ;;
            *) echo "❓ Final Status: UNKNOWN ($FINAL_STATUS)" ;;
        esac

        # Show timing information
        RESOLVED_AT=$(date +%s)
        TOTAL_DURATION=$((RESOLVED_AT - CREATED_AT))
        echo "⏰ Resolution completed at: $(date)"
        echo "🕐 Total duration: $TOTAL_DURATION seconds ($(($TOTAL_DURATION/60))m $(($TOTAL_DURATION%60))s)"

        # Show additional game details
        echo ""
        echo "📊 Game Details:"
        CLAIM_COUNT=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "claimDataLen() returns (uint256)" 2>/dev/null || echo "N/A")
        ROOT_CLAIM=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "rootClaim() returns (bytes32)" 2>/dev/null || echo "N/A")
        L2_BLOCK=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "l2BlockNumber() returns (uint256)" 2>/dev/null || echo "N/A")

        echo "   🌳 Total claims: $CLAIM_COUNT"
        echo "   🎯 Root claim: $ROOT_CLAIM"
        echo "   📦 L2 block: $L2_BLOCK"

        echo ""
        echo "🎉 Auto-resolve completed successfully!"

    ) &

    BACKGROUND_PID=$!
    echo "🚀 Background process started (PID: $BACKGROUND_PID)"
    echo "📝 You can monitor progress or kill with: kill $BACKGROUND_PID"

else
    echo ""
    echo "🎯 Executing resolve() now..."

    # First try resolveClaim for root claim (index 0)
    echo "🎯 Step 1: Resolving root claim (index 0)..."
    RESOLVE_CLAIM_RESULT=$(cast send --rpc-url "$L1_RPC" \
        --private-key "$PRIVATE_KEY" \
        "$GAME_ADDRESS" \
        "resolveClaim(uint256,uint256)" 0 0 2>/dev/null || echo "FAILED")

    if [[ "$RESOLVE_CLAIM_RESULT" == "FAILED" ]]; then
        echo "⚠️  resolveClaim failed (this may be normal)"
        echo "🎯 Proceeding with direct resolve()..."
    else
        echo "✅ resolveClaim successful: $RESOLVE_CLAIM_RESULT"
        echo "⏳ Waiting 2 seconds before resolve()..."
        sleep 2
    fi

    # Then try resolve() for the entire game
    echo ""
    echo "🎯 Step 2: Resolving entire game..."
    TX_HASH=$(cast send --rpc-url "$L1_RPC" \
        --private-key "$PRIVATE_KEY" \
        "$GAME_ADDRESS" \
        "resolve()" 2>/dev/null || echo "FAILED")

    if [[ "$TX_HASH" == "FAILED" ]]; then
        echo "❌ Failed to send resolve transaction"
        exit 1
    fi

    echo "✅ Resolve transaction sent!"
    echo "📄 Transaction hash: $TX_HASH"

    # Wait for confirmation and show results
    echo "⏳ Waiting for transaction confirmation..."
    sleep 5

    # Check final game status and detailed results
    echo ""
    echo "🎯 Resolution Results:"
    echo "===================="

    FINAL_STATUS=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "status() returns (uint8)" 2>/dev/null || echo "255")
    case $FINAL_STATUS in
        0) echo "🟡 Final Status: IN_PROGRESS (resolution may need more time)" ;;
        1) echo "🔴 Final Status: CHALLENGER_WINS" ;;
        2) echo "🟢 Final Status: DEFENDER_WINS" ;;
        *) echo "❓ Final Status: UNKNOWN ($FINAL_STATUS)" ;;
    esac

    # Show timing information
    RESOLVED_AT=$(date +%s)
    TOTAL_DURATION=$((RESOLVED_AT - CREATED_AT))
    echo "⏰ Resolution completed at: $(date)"
    echo "🕐 Total duration: $TOTAL_DURATION seconds ($(($TOTAL_DURATION/60))m $(($TOTAL_DURATION%60))s)"

    # Show additional game details
    echo ""
    echo "📊 Game Details:"
    CLAIM_COUNT=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "claimDataLen() returns (uint256)" 2>/dev/null || echo "N/A")
    ROOT_CLAIM=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "rootClaim() returns (bytes32)" 2>/dev/null || echo "N/A")
    L2_BLOCK=$(cast call --rpc-url "$L1_RPC" "$GAME_ADDRESS" "l2BlockNumber() returns (uint256)" 2>/dev/null || echo "N/A")

    echo "   🌳 Total claims: $CLAIM_COUNT"
    echo "   🎯 Root claim: $ROOT_CLAIM"
    echo "   📦 L2 block: $L2_BLOCK"

    echo ""
    echo "🎉 Auto-resolve completed successfully!"
fi