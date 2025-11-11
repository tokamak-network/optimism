# Dispute Game Monitoring Guide

This guide provides comprehensive tools and techniques for monitoring dispute game creation and status in the Optimism fault proof system.

## Quick Start

### Automated Monitoring Tools

The monitoring scripts are located in `/op-challenger/scripts/`:

```bash
cd /optimism/op-challenger/scripts

# Real-time monitoring (recommended)
./monitor-game-creation.sh monitor

# Quick status check
# Note: filter-game-logs.sh not available, using monitor-game-creation.sh instead

# Show recent games
./monitor-game-creation.sh recent 10
```

## Real-time Game Creation Monitoring

### Using the Monitor Script

The `monitor-game-creation.sh` script provides comprehensive monitoring capabilities:

```bash
# Start real-time monitoring (watches for new games every 5 seconds)
./monitor-game-creation.sh monitor

# Show recent 5 game creations (default)
./monitor-game-creation.sh recent

# Show recent 10 game creations
./monitor-game-creation.sh recent 10

# Show games created in specific block range
./monitor-game-creation.sh range 3000 3100

# Show help
./monitor-game-creation.sh help
```

### Monitor Output Format

```
=== Dispute Game Creation Monitor ===
Factory: 0x732515C7795d6a8b55Af55cdcA7EE03373a6EEa6
RPC: http://127.0.0.1:52679

🎮 NEW GAME(S) DETECTED! Count: 30 → 31
Block: 3083 | TX: 0xeb47af7c... | Game: 0xDC8d235D... | Type: 0 | Root: 0x68e7fa45...
```

## Quick Game Status Check

### Using the Filter Script

For a quick overview of the current game status:

```bash
# Note: filter-game-logs.sh not available
# Use monitor-game-creation.sh instead:
./monitor-game-creation.sh recent 5
```

Output includes:
- Recent game creation events
- Current total game count
- Latest game details (address, type, timestamp, status)

## Manual Monitoring Commands

### Environment Setup

First, get your devnet connection details:

```bash
# Get RPC endpoint (adjust port based on your setup)
RPC="http://127.0.0.1:52679"  # L1 RPC from kurtosis enclave

# DisputeGameFactory address (from deployment)
FACTORY="0x732515C7795d6a8b55Af55cdcA7EE03373a6EEa6"

# DisputeGameCreated event signature
EVENT_SIG="0x5b565efe82411da98814f356d0e7bcb8f0219b8d970307c5afb4a6903a8b2e35"
```

### Game Count and Status

```bash
# Check current total game count
cast call $FACTORY "gameCount()(uint256)" --rpc-url $RPC

# Get latest game details
LATEST_INDEX=$(($(cast call $FACTORY "gameCount()(uint256)" --rpc-url $RPC) - 1))
cast call $FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_INDEX --rpc-url $RPC

# Check specific game status
GAME_ADDRESS="0x..." # From gameAtIndex output
cast call $GAME_ADDRESS "status()(uint8)" --rpc-url $RPC
```

### Event Log Filtering

```bash
# Show recent game creation events (last 1000 blocks)
cast logs --from-block $(($(cast block-number --rpc-url $RPC) - 1000)) \
  --address $FACTORY \
  --rpc-url $RPC \
  | grep "$EVENT_SIG" | tail -10

# Filter events from specific block range
cast logs \
  --from-block 3000 \
  --to-block 3100 \
  --address $FACTORY \
  --rpc-url $RPC

# Parse event details with jq
cast logs --from-block $(($(cast block-number --rpc-url $RPC) - 500)) \
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
    }'
```

## Understanding Game Creation Events

### Event Structure

The `DisputeGameCreated` event has the following structure:

```solidity
event DisputeGameCreated(
    address indexed disputeProxy,
    GameType indexed gameType,
    Claim indexed rootClaim
);
```

**Event Signature**: `0x5b565efe82411da98814f356d0e7bcb8f0219b8d970307c5afb4a6903a8b2e35`

**Topics Array**:
- `topics[0]`: Event signature
- `topics[1]`: Game contract address (32 bytes, last 20 bytes are the address)
- `topics[2]`: Game type (0=CANNON, 1=PERMISSIONED, 2=ASTERISC)
- `topics[3]`: Root claim (proposed L2 output root)

### Game Types

| Type | Name | Description | VM Used |
|------|------|-------------|---------|
| **0** | CANNON | Full fault proofs, permissionless | cannon |
| **1** | PERMISSIONED | Semi-centralized, faster | cannon |
| **2** | ASTERISC | Alternative VM implementation | asterisc |

### Game Status Values

| Status | Value | Description |
|--------|-------|-------------|
| IN_PROGRESS | 0 | Game is active and can be interacted with |
| CHALLENGER_WINS | 1 | Challenger successfully disputed the claim |
| DEFENDER_WINS | 2 | Defender's claim was upheld |

## Proposer Log Analysis

### Understanding Proposer Logs

The proposer doesn't explicitly log "dispute game creation" - instead, look for these patterns:

```bash
# Monitor proposer logs for game creation indicators
docker logs op-proposer-2151908-op-kurtosis-... --follow | grep -E "(Proposing output root|Transaction confirmed)"
```

**Expected Log Pattern** (every 10 minutes):
```
t=2025-09-03T05:09:31+0000 lvl=info msg="No proposals found for at least proposal interval, submitting proposal now" proposalInterval=10m0s
t=2025-09-03T05:09:31+0000 lvl=info msg="Proposing output root" output=0x68e7fa45... block=9188
t=2025-09-03T05:09:31+0000 lvl=info msg="Publishing transaction" service=proposer tx=0xeb47af7c... nonce=30
t=2025-09-03T05:09:31+0000 lvl=info msg="Transaction successfully published" service=proposer tx=0xeb47af7c...
t=2025-09-03T05:10:43+0000 lvl=info msg="Transaction confirmed" service=proposer tx=0xeb47af7c... block=0xdb3acbda...:3083
```

## Challenger Log Monitoring

### Finding and Monitoring Challenger Logs

The challenger monitors dispute games and validates their correctness. Here's how to monitor challenger activity:

#### Kurtosis-managed Challenger
```bash
# If challenger is managed by Kurtosis
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow

# List challenger services
kurtosis service ls simple-devnet | grep challenger
```

#### Standalone Challenger
```bash
# If running challenger manually
docker logs op-challenger --follow

# Find challenger container
docker ps | grep challenger
```

### Understanding Challenger Log Patterns

#### Game Registration and Validation
```bash
# Monitor challenger for game detection
docker logs op-challenger --follow | grep -E "(game|dispute|validation)"
```

**Expected Challenger Activity**:
```
INFO challenger: Registered to dispute game    game=0xDC8d235D... gameType=CANNON status=IN_PROGRESS
INFO challenger: Starting game validation      game=0xDC8d235D... claims=1
INFO challenger: Prestate validation passed    game=0xDC8d235D... absolutePrestate=0x03a1a135...
INFO challenger: No invalid claims detected    game=0xDC8d235D... action=monitor
```

#### Challenger Error Patterns

**Prestate Validation Errors** (Cold Start Problem):
```
ERROR challenger: Failed to validate prestate  game=0x... error="output root absolute prestate does not match"
ERROR challenger: Provider: 0x03a1a135... | Contract: 0xdead00000000000000000000000000000000000000000000000000000000000
```

**Game Registration Issues**:
```
WARN challenger: Game not eligible for monitoring    game=0x... reason="invalid game type"
ERROR challenger: Failed to register game           game=0x... error="context canceled"
```

#### Action Detection Logs
```bash
# Monitor for challenger actions
docker logs op-challenger --follow | grep -E "(action|challenge|defend)"
```

**Action Patterns**:
```
INFO challenger: Invalid claim detected        game=0x... claim=0x... action=challenge
INFO challenger: Submitting challenge         game=0x... position=123 claim=0x...
INFO challenger: Challenge transaction sent   game=0x... tx=0xabc123...
INFO challenger: Step execution completed     game=0x... step=456 result=success
```

### Challenger Health Monitoring

#### Health Check Script
```bash
# Create challenger health monitor
cat << 'EOF' > monitor-challenger-health.sh
#!/bin/bash

CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)

if [ -z "$CHALLENGER_CONTAINER" ]; then
    echo "❌ No challenger container found"
    exit 1
fi

echo "=== Challenger Health Check ==="
echo "Container: $CHALLENGER_CONTAINER"
echo ""

# Check if container is running
if docker ps --format "{{.Names}}" | grep -q "$CHALLENGER_CONTAINER"; then
    echo "✅ Container Status: Running"
else
    echo "❌ Container Status: Not Running"
    exit 1
fi

# Check recent logs for errors
echo ""
echo "Recent Error Logs (last 50 lines):"
docker logs "$CHALLENGER_CONTAINER" --tail 50 | grep -i "error\|failed\|panic" | tail -10

# Check game monitoring activity
echo ""
echo "Recent Game Activity (last 20 lines):"
docker logs "$CHALLENGER_CONTAINER" --tail 100 | grep -E "(game|dispute)" | tail -5

# Check prestate validation
echo ""
echo "Prestate Validation Status:"
PRESTATE_ERRORS=$(docker logs "$CHALLENGER_CONTAINER" --tail 200 | grep -c "prestate.*does not match")
if [ $PRESTATE_ERRORS -gt 0 ]; then
    echo "⚠️  Found $PRESTATE_ERRORS prestate validation errors (Cold Start Problem)"
    echo "   This is expected for newly deployed devnets"
else
    echo "✅ No prestate validation errors"
fi

# Check recent registrations
echo ""
echo "Recent Game Registrations:"
docker logs "$CHALLENGER_CONTAINER" --tail 100 | grep "Registered to dispute game" | tail -3
EOF

chmod +x monitor-challenger-health.sh
```

#### Challenger Metrics Monitoring
```bash
# Monitor challenger metrics (if metrics enabled)
curl -s http://localhost:9001/metrics | grep challenger

# Check challenger RPC health
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"debug_health","params":[],"id":1}' \
  http://localhost:8547  # Challenger RPC port
```

### Coordinated Monitoring: Proposer + Challenger

#### Combined Log Analysis
```bash
# Monitor both proposer and challenger activity together
cat << 'EOF' > monitor-proposer-challenger.sh
#!/bin/bash

PROPOSER_CONTAINER=$(docker ps --format "{{.Names}}" | grep proposer | head -1)
CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)

echo "=== Dispute Game System Activity ==="
echo "Proposer: $PROPOSER_CONTAINER"
echo "Challenger: $CHALLENGER_CONTAINER"
echo ""

# Function to get latest game from logs
get_latest_game_from_proposer() {
    docker logs "$PROPOSER_CONTAINER" --tail 50 | \
    grep "Proposing output root" | tail -1 | \
    grep -o 'output=0x[a-fA-F0-9]*' | cut -d'=' -f2
}

# Function to check if challenger detected the game
check_challenger_detection() {
    local output_root=$1
    if [ -n "$output_root" ]; then
        docker logs "$CHALLENGER_CONTAINER" --tail 100 | \
        grep -q "$output_root" && echo "✅ Detected" || echo "❌ Not Detected"
    else
        echo "N/A"
    fi
}

# Monitor recent activity
echo "Recent Activity:"
echo "----------------"

# Get last proposer activity
LAST_OUTPUT=$(get_latest_game_from_proposer)
echo "Latest Proposed Output: $LAST_OUTPUT"
echo "Challenger Detection: $(check_challenger_detection $LAST_OUTPUT)"

echo ""
echo "Last 3 Proposer Actions:"
docker logs "$PROPOSER_CONTAINER" --tail 50 | grep "Proposing output root" | tail -3

echo ""
echo "Last 3 Challenger Registrations:"
docker logs "$CHALLENGER_CONTAINER" --tail 50 | grep "Registered to dispute game" | tail -3

# Check for any challenger actions
echo ""
echo "Challenger Actions (last 24h):"
docker logs "$CHALLENGER_CONTAINER" --since 24h | grep -E "(challenge|defend|action)" | tail -5 || echo "No challenger actions found"
EOF

chmod +x monitor-proposer-challenger.sh
```

#### Real-time Coordinated Monitoring
```bash
# Watch both proposer and challenger in real-time
cat << 'EOF' > watch-dispute-system.sh
#!/bin/bash

PROPOSER_CONTAINER=$(docker ps --format "{{.Names}}" | grep proposer | head -1)
CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)

echo "Starting real-time dispute system monitoring..."
echo "Proposer: $PROPOSER_CONTAINER"
echo "Challenger: $CHALLENGER_CONTAINER"
echo "Press Ctrl+C to stop"
echo ""

# Start monitoring both containers
{
    docker logs "$PROPOSER_CONTAINER" --follow 2>&1 | sed 's/^/[PROPOSER] /' &
    docker logs "$CHALLENGER_CONTAINER" --follow 2>&1 | sed 's/^/[CHALLENGER] /' &
    wait
} | grep -E "(Proposing output root|Transaction confirmed|Registered to dispute game|validation|challenge|action|error)"
EOF

chmod +x watch-dispute-system.sh
```

### Challenger Performance Monitoring

#### Response Time Analysis
```bash
# Measure challenger response time to new games
cat << 'EOF' > measure-challenger-response.sh
#!/bin/bash

RPC="http://127.0.0.1:52679"
FACTORY="0x732515C7795d6a8b55Af55cdcA7EE03373a6EEa6"
CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)

echo "=== Challenger Response Time Analysis ==="

# Get latest game
LATEST_GAME_INDEX=$(($(cast call $FACTORY "gameCount()(uint256)" --rpc-url $RPC) - 1))
LATEST_GAME_INFO=$(cast call $FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_GAME_INDEX --rpc-url $RPC)
GAME_ADDRESS=$(echo $LATEST_GAME_INFO | awk '{print $3}')
GAME_TIMESTAMP=$(echo $LATEST_GAME_INFO | awk '{print $2}')

echo "Latest Game: $GAME_ADDRESS"
echo "Creation Time: $(date -r $GAME_TIMESTAMP)"

# Check challenger logs for this game
echo ""
echo "Challenger Activity for this Game:"
docker logs "$CHALLENGER_CONTAINER" --since $(date -r $GAME_TIMESTAMP -d "1 minute ago" '+%Y-%m-%dT%H:%M:%S') | \
    grep "$GAME_ADDRESS" | head -10

# Calculate response time (rough estimate)
FIRST_CHALLENGER_LOG=$(docker logs "$CHALLENGER_CONTAINER" --since $(date -r $GAME_TIMESTAMP '+%Y-%m-%dT%H:%M:%S') | \
    grep "$GAME_ADDRESS" | head -1)

if [ -n "$FIRST_CHALLENGER_LOG" ]; then
    echo ""
    echo "✅ Challenger responded to game creation"
    echo "First log entry: $FIRST_CHALLENGER_LOG"
else
    echo ""
    echo "⚠️  No challenger activity found for this game"
fi
EOF

chmod +x measure-challenger-response.sh
```

### Correlating Proposer Logs with Game Creation

To verify that a proposer transaction created a game:

```bash
# 1. Get transaction hash from proposer logs
PROPOSER_TX="0xeb47af7c2034979b46bdf035bd542e18eb7e54809b405623914a8ec600f87151"

# 2. Find the corresponding DisputeGameCreated event
cast logs \
  --from-block 3080 \
  --to-block 3090 \
  --address $FACTORY \
  --rpc-url $RPC \
  | jq -r --arg tx "$PROPOSER_TX" 'select(.transactionHash == $tx)'

# 3. Verify the game was created
cast call $FACTORY "gameCount()(uint256)" --rpc-url $RPC
```

## Advanced Monitoring Techniques

### Continuous Monitoring with Watch

```bash
# Monitor game count changes every 5 seconds
watch -n 5 "echo 'Game Count:' && cast call $FACTORY 'gameCount()' --rpc-url $RPC"

# Monitor latest game status
# Note: filter-game-logs.sh not available, using monitor-game-creation.sh instead
watch -n 10 "./monitor-game-creation.sh recent 1"
```

### Python-based Monitoring

For more sophisticated monitoring, use Python with web3:

```python
from web3 import Web3
import time

w3 = Web3(Web3.HTTPProvider('http://127.0.0.1:52679'))
factory_address = '0x732515C7795d6a8b55Af55cdcA7EE03373a6EEa6'

# Real-time event monitoring
def monitor_games():
    last_block = w3.eth.block_number - 100

    while True:
        current_block = w3.eth.block_number

        # Check for new events
        event_filter = w3.eth.filter({
            'fromBlock': last_block,
            'toBlock': current_block,
            'address': factory_address,
            'topics': ['0x5b565efe82411da98814f356d0e7bcb8f0219b8d970307c5afb4a6903a8b2e35']
        })

        for event in event_filter.get_all_entries():
            game_address = '0x' + event['topics'][1].hex()[26:]
            game_type = int(event['topics'][2].hex(), 16)
            root_claim = event['topics'][3].hex()

            print(f"🎮 New Game Created!")
            print(f"  Block: {event['blockNumber']}")
            print(f"  Address: {game_address}")
            print(f"  Type: {game_type}")
            print(f"  Root: {root_claim}")
            print()

        last_block = current_block
        time.sleep(5)

if __name__ == "__main__":
    monitor_games()
```

### Log Aggregation and Analysis

```bash
# Create comprehensive game creation log
cat << 'EOF' > game_creation_analysis.sh
#!/bin/bash
RPC="http://127.0.0.1:52679"
FACTORY="0x732515C7795d6a8b55Af55cdcA7EE03373a6EEa6"

echo "=== Dispute Game Creation Analysis ==="
echo "Timestamp: $(date)"
echo "Factory: $FACTORY"
echo ""

# Total games
TOTAL_GAMES=$(cast call $FACTORY "gameCount()" --rpc-url $RPC)
echo "Total Games Created: $TOTAL_GAMES"

# Recent activity (last 1000 blocks)
CURRENT_BLOCK=$(cast block-number --rpc-url $RPC)
FROM_BLOCK=$((CURRENT_BLOCK - 1000))

echo "Analyzing blocks $FROM_BLOCK to $CURRENT_BLOCK..."

# Game creation frequency
RECENT_GAMES=$(cast logs \
  --from-block $FROM_BLOCK \
  --address $FACTORY \
  --rpc-url $RPC \
  | grep "0x5b565efe" | wc -l)

echo "Games created in last 1000 blocks: $RECENT_GAMES"
echo "Average blocks per game: $(($((CURRENT_BLOCK - FROM_BLOCK)) / $((RECENT_GAMES > 0 ? RECENT_GAMES : 1))))"

# Latest game details
if [ $TOTAL_GAMES -gt 0 ]; then
    LATEST_INDEX=$((TOTAL_GAMES - 1))
    LATEST_GAME=$(cast call $FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_INDEX --rpc-url $RPC)
    echo ""
    echo "Latest Game (#$LATEST_INDEX):"
    echo "  $LATEST_GAME"
fi
EOF

chmod +x game_creation_analysis.sh
./game_creation_analysis.sh
```

## Troubleshooting

### Common Issues

1. **No Events Found**
   - Check if proposer is running: `docker ps | grep proposer`
   - Verify RPC endpoint: `cast block-number --rpc-url $RPC`
   - Ensure correct factory address from deployment

2. **Connection Errors**
   - Verify devnet is running: `kurtosis enclave inspect simple-devnet`
   - Check port mappings in kurtosis output
   - Restart services if needed

3. **Script Permissions**
   ```bash
   chmod +x /optimism/op-challenger/scripts/monitor-game-creation.sh
   chmod +x /optimism/op-challenger/scripts/filter-game-logs.sh
   ```

### Debugging Commands

```bash
# Check proposer configuration
docker exec op-proposer-... env | grep -E "GAME|FACTORY"

# Verify factory contract
cast code $FACTORY --rpc-url $RPC

# Check recent proposer activity
docker logs op-proposer-... --tail 20 | grep -i "proposal\|transaction"
```

## Integration with Other Tools

### Grafana Dashboards

Monitor game creation metrics by querying the RPC endpoint:

```bash
# Export metrics for Grafana
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"'$FACTORY'","data":"0xa87430ba"},"latest"],"id":1}' \
  $RPC
```

### Alerting

Set up alerts for game creation anomalies:

```bash
# Check if games are being created regularly (every 10 minutes)
LAST_GAME_TIME=$(cast call $FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $(($(cast call $FACTORY "gameCount()" --rpc-url $RPC) - 1)) --rpc-url $RPC | awk '{print $2}')
CURRENT_TIME=$(date +%s)
TIME_DIFF=$((CURRENT_TIME - LAST_GAME_TIME))

if [ $TIME_DIFF -gt 1200 ]; then  # 20 minutes
    echo "⚠️  WARNING: No new games in $TIME_DIFF seconds"
fi
```

This monitoring setup provides comprehensive visibility into dispute game creation and helps ensure the fault proof system is operating correctly.