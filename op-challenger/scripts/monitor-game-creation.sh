#!/bin/bash

# Dispute Game Creation Monitor
# This script monitors and parses DisputeGameFactory events for new game creation

RPC="http://127.0.0.1:52679"
FACTORY="0x732515C7795d6a8b55Af55cdcA7EE03373a6EEa6"
EVENT_SIG="0x5b565efe82411da98814f356d0e7bcb8f0219b8d970307c5afb4a6903a8b2e35"

echo "=== Dispute Game Creation Monitor ==="
echo "Factory: $FACTORY"
echo "RPC: $RPC"
echo ""

# Function to parse game creation events
parse_game_events() {
    local from_block=$1
    local to_block=${2:-"latest"}
    
    echo "Searching for game creation events from block $from_block to $to_block..."
    
    cast logs \
        --from-block $from_block \
        --to-block $to_block \
        --address $FACTORY \
        --rpc-url $RPC \
        | jq -r --arg event_sig "$EVENT_SIG" '
            select(.topics[0] == $event_sig) |
            {
                block: .blockNumber,
                txHash: .transactionHash,
                gameAddress: ("0x" + .topics[1][26:]),
                gameType: (.topics[2] | tonumber),
                rootClaim: .topics[3]
            } |
            "Block: \(.block) | TX: \(.txHash) | Game: \(.gameAddress) | Type: \(.gameType) | Root: \(.rootClaim)"'
}

# Function to get current game count
get_game_count() {
    cast call $FACTORY "gameCount()(uint256)" --rpc-url $RPC
}

# Function to monitor in real-time
monitor_realtime() {
    echo "Starting real-time monitoring (Ctrl+C to stop)..."
    local last_count=$(get_game_count)
    echo "Current game count: $last_count"
    echo ""
    
    while true; do
        current_count=$(get_game_count)
        
        if [ "$current_count" -gt "$last_count" ]; then
            echo "🎮 NEW GAME(S) DETECTED! Count: $last_count → $current_count"
            
            # Parse recent events
            current_block=$(cast block-number --rpc-url $RPC)
            parse_game_events $((current_block - 10))
            
            last_count=$current_count
            echo ""
        fi
        
        sleep 5
    done
}

# Function to show recent games
show_recent_games() {
    local count=${1:-10}
    echo "=== Recent $count Games ==="
    
    current_block=$(cast block-number --rpc-url $RPC)
    parse_game_events $((current_block - 1000)) | tail -n $count
}

# Main script logic
case "${1:-recent}" in
    "monitor"|"watch")
        monitor_realtime
        ;;
    "recent")
        show_recent_games ${2:-5}
        ;;
    "range")
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 range <from_block> <to_block>"
            exit 1
        fi
        parse_game_events $2 $3
        ;;
    "help")
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  recent [count]     Show recent game creations (default: 5)"
        echo "  monitor           Start real-time monitoring"
        echo "  range <from> <to> Show games created in block range"
        echo "  help              Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac