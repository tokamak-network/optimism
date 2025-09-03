#!/bin/bash

# Simple Game Log Filter
# Quick one-liners for filtering dispute game creation logs

RPC="http://127.0.0.1:52679"
FACTORY="0x732515C7795d6a8b55Af55cdcA7EE03373a6EEa6"
EVENT_SIG="0x5b565efe82411da98814f356d0e7bcb8f0219b8d970307c5afb4a6903a8b2e35"

echo "=== Dispute Game Log Filters ==="

# Show recent 5 game creation events
echo "Recent 5 game creations:"
cast logs --from-block $(($(cast block-number --rpc-url $RPC) - 1000)) \
  --address $FACTORY \
  --rpc-url $RPC \
  | grep "$EVENT_SIG" | tail -5

echo ""

# Show current game count
echo "Current game count:"
cast call $FACTORY "gameCount()(uint256)" --rpc-url $RPC

echo ""

# Show latest game details
echo "Latest game details:"
LATEST_INDEX=$(($(cast call $FACTORY "gameCount()(uint256)" --rpc-url $RPC) - 1))
if [ $LATEST_INDEX -ge 0 ]; then
    GAME_INFO=$(cast call $FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_INDEX --rpc-url $RPC)
    GAME_TYPE=$(echo $GAME_INFO | awk '{print $1}')
    TIMESTAMP=$(echo $GAME_INFO | awk '{print $2}')
    ADDRESS=$(echo $GAME_INFO | awk '{print $3}')
    
    echo "Game #$LATEST_INDEX:"
    echo "  Address: $ADDRESS"
    echo "  Type: $GAME_TYPE"
    echo "  Timestamp: $TIMESTAMP ($(date -r $TIMESTAMP 2>/dev/null || echo 'Invalid timestamp'))"
    
    # Check game status
    STATUS=$(cast call $ADDRESS "status()(uint8)" --rpc-url $RPC 2>/dev/null || echo "Unknown")
    echo "  Status: $STATUS"
fi