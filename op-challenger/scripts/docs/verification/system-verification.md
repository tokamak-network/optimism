# System Verification & Health Monitoring

Comprehensive guide for verifying your OP-Challenger installation and monitoring system health.

## Quick Health Check

### Automated System Check

Create and run the automated health check script:

```bash
cd /optimism/op-challenger/scripts

# Create comprehensive health check
cat << 'EOF' > system-health-check.sh
#!/bin/bash

echo "=== OP-Challenger System Health Check ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_TOTAL=0

# Helper function to run tests
run_test() {
    local test_name="$1"
    local test_command="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    printf "%-40s" "$test_name:"
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}"
        return 1
    fi
}

# 1. Infrastructure Tests
echo "=== Infrastructure ==="
run_test "Docker is running" "docker info"
run_test "Kurtosis is accessible" "kurtosis version"
run_test "Devnet enclave exists" "kurtosis enclave inspect simple-devnet"

# 2. Service Health Tests
echo ""
echo "=== Services ==="

# Get service count
RUNNING_SERVICES=$(kurtosis enclave inspect simple-devnet 2>/dev/null | grep "RUNNING" | wc -l | tr -d ' ')
run_test "All services running ($RUNNING_SERVICES)" "[ '$RUNNING_SERVICES' -gt 8 ]"

# Check specific services
run_test "L1 EL service" "kurtosis service inspect simple-devnet el-1-geth-teku"
run_test "L2 EL service" "kurtosis service inspect simple-devnet op-el-2151908-node0-op-geth"
run_test "Proposer service" "kurtosis service inspect simple-devnet op-proposer-2151908-op-kurtosis"

# 3. Network Connectivity Tests
echo ""
echo "=== Network Connectivity ==="

# Download devnet info if not exists
if [ ! -f "/tmp/devnet-desc/env.json" ]; then
    kurtosis files download simple-devnet devnet-descriptor-0 /tmp/devnet-desc >/dev/null 2>&1
fi

if [ -f "/tmp/devnet-desc/env.json" ]; then
    L1_RPC=$(grep -o '"rpc":"http://[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f4)
    L2_RPC=$(grep -o '"l2_rpc":"http://[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f4)

    run_test "L1 RPC connectivity" "cast block-number --rpc-url $L1_RPC"
    run_test "L2 RPC connectivity" "cast block-number --rpc-url $L2_RPC"

    # Check block production
    L1_BLOCK1=$(cast block-number --rpc-url $L1_RPC 2>/dev/null)
    L2_BLOCK1=$(cast block-number --rpc-url $L2_RPC 2>/dev/null)
    sleep 3
    L1_BLOCK2=$(cast block-number --rpc-url $L1_RPC 2>/dev/null)
    L2_BLOCK2=$(cast block-number --rpc-url $L2_RPC 2>/dev/null)

    run_test "L1 block production" "[ '$L1_BLOCK2' -gt '$L1_BLOCK1' ]"
    run_test "L2 block production" "[ '$L2_BLOCK2' -gt '$L2_BLOCK1' ]"
else
    echo -e "${YELLOW}⚠️  Could not download devnet info${NC}"
fi

# 4. Contract Deployment Tests
echo ""
echo "=== Contract Deployment ==="

if [ -f "/tmp/devnet-desc/env.json" ]; then
    OPCM_ADDRESS=$(grep -o 'OPContractsManager[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)
    DGF_ADDRESS=$(grep -o 'DisputeGameFactoryProxy[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)

    run_test "OPCM deployment" "cast code $OPCM_ADDRESS --rpc-url $L1_RPC | grep -q 0x"
    run_test "DisputeGameFactory deployment" "cast code $DGF_ADDRESS --rpc-url $L1_RPC | grep -q 0x"

    # Check deployment version
    DEPLOYMENT_VERSION=$(cast call $OPCM_ADDRESS "getDeploymentVersion()(string)" --rpc-url $L1_RPC 2>/dev/null)
    run_test "Custom deployment version" "echo '$DEPLOYMENT_VERSION' | grep -q -v 'v2.0.0'"
fi

# 5. Dispute Game System Tests
echo ""
echo "=== Dispute Game System ==="

if [ -f "/tmp/devnet-desc/env.json" ] && [ -n "$DGF_ADDRESS" ]; then
    # Check game count
    GAME_COUNT=$(cast call $DGF_ADDRESS "gameCount()(uint256)" --rpc-url $L1_RPC 2>/dev/null)
    run_test "Games created (count: $GAME_COUNT)" "[ '$GAME_COUNT' -gt 0 ]"

    # Check recent game activity
    if [ "$GAME_COUNT" -gt 0 ]; then
        LATEST_GAME_INDEX=$((GAME_COUNT - 1))
        LATEST_GAME_INFO=$(cast call $DGF_ADDRESS "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_GAME_INDEX --rpc-url $L1_RPC 2>/dev/null)
        GAME_TIMESTAMP=$(echo $LATEST_GAME_INFO | awk '{print $2}')
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - GAME_TIMESTAMP))

        # Game should be created within last 15 minutes (900 seconds)
        run_test "Recent game activity (<15min)" "[ '$TIME_DIFF' -lt 900 ]"
    fi
fi

# 6. Challenger Tests
echo ""
echo "=== Challenger ==="

CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)
if [ -n "$CHALLENGER_CONTAINER" ]; then
    run_test "Challenger container running" "docker ps --format '{{.Names}}' | grep -q challenger"

    # Check challenger logs for errors
    ERROR_COUNT=$(docker logs "$CHALLENGER_CONTAINER" --tail 100 2>/dev/null | grep -i "error\|failed\|panic" | wc -l)
    run_test "No recent errors (count: $ERROR_COUNT)" "[ '$ERROR_COUNT' -lt 5 ]"

    # Check challenger is registering games
    GAME_REGISTRATIONS=$(docker logs "$CHALLENGER_CONTAINER" --tail 100 2>/dev/null | grep -c "Registered to dispute game")
    run_test "Challenger monitoring games" "[ '$GAME_REGISTRATIONS' -gt 0 ]"
else
    echo -e "${YELLOW}⚠️  No challenger container found${NC}"
fi

# 7. Performance Tests
echo ""
echo "=== Performance ==="

# Check Docker resource usage
DOCKER_MEM_USAGE=$(docker stats --no-stream --format "table {{.MemUsage}}" | tail -n +2 | awk -F'/' '{total += $1} END {print total}' 2>/dev/null || echo "0")
run_test "Docker memory usage reasonable" "echo '$DOCKER_MEM_USAGE' | awk '{exit (\$1 > 8000000000) ? 1 : 0}'"

# Check disk space
DISK_USAGE=$(df -h /tmp | tail -1 | awk '{print $5}' | sed 's/%//')
run_test "Adequate disk space (<80%)" "[ '$DISK_USAGE' -lt 80 ]"

# Summary
echo ""
echo "=== Summary ==="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}/$TESTS_TOTAL"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo -e "${GREEN}🎉 All systems operational!${NC}"
    exit 0
elif [ $TESTS_PASSED -gt $((TESTS_TOTAL * 3 / 4)) ]; then
    echo -e "${YELLOW}⚠️  System mostly operational with minor issues${NC}"
    exit 1
else
    echo -e "${RED}❌ System has significant issues${NC}"
    exit 2
fi
EOF

chmod +x system-health-check.sh
./system-health-check.sh
```

## Individual Component Verification

### 1. Service Status Verification

```bash
# Check all services in devnet
kurtosis enclave inspect simple-devnet

# Expected services (all should be RUNNING):
# - el-1-geth-teku (L1 Execution Layer)
# - cl-1-teku-geth (L1 Consensus Layer)
# - op-el-2151908-node0-op-geth (L2 Execution Layer)
# - op-cl-2151908-node0-op-node (L2 Consensus/Rollup Node)
# - op-proposer-2151908-op-kurtosis (Proposer)
# - op-batcher-2151908-op-kurtosis (Batcher)
# - Additional services: faucet, grafana, etc.
```

**Individual Service Health:**
```bash
# Check specific service health
kurtosis service inspect simple-devnet op-proposer-2151908-op-kurtosis

# Check service logs
kurtosis service logs simple-devnet op-proposer-2151908-op-kurtosis --tail 20

# Monitor service logs in real-time
kurtosis service logs simple-devnet op-proposer-2151908-op-kurtosis --follow
```

### 2. Network & RPC Verification

```bash
# Get network endpoints
kurtosis files download simple-devnet devnet-descriptor-0 /tmp/devnet-desc
L1_RPC=$(grep -o '"rpc":"http://[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f4)
L2_RPC=$(grep -o '"l2_rpc":"http://[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f4)

echo "L1 RPC: $L1_RPC"
echo "L2 RPC: $L2_RPC"

# Test connectivity
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $L1_RPC

# Check block numbers
echo "L1 Block: $(cast block-number --rpc-url $L1_RPC)"
echo "L2 Block: $(cast block-number --rpc-url $L2_RPC)"

# Verify block production (blocks should increase)
sleep 12
echo "L1 Block (12s later): $(cast block-number --rpc-url $L1_RPC)"
echo "L2 Block (12s later): $(cast block-number --rpc-url $L2_RPC)"
```

### 3. Contract Deployment Verification

```bash
# Get contract addresses
OPCM_ADDRESS=$(grep -o 'OPContractsManager[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)
DGF_ADDRESS=$(grep -o 'DisputeGameFactoryProxy[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)
OP_PORTAL=$(grep -o 'OptimismPortalProxy[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)

echo "OPCM: $OPCM_ADDRESS"
echo "DisputeGameFactory: $DGF_ADDRESS"
echo "OptimismPortal: $OP_PORTAL"

# Verify contracts have code
cast code $OPCM_ADDRESS --rpc-url $L1_RPC | head -20
cast code $DGF_ADDRESS --rpc-url $L1_RPC | head -20

# Check deployment version (should show your custom version)
cast call $OPCM_ADDRESS "getDeploymentVersion()(string)" --rpc-url $L1_RPC

# Verify game type configuration
cast call $OP_PORTAL "respectedGameType()(uint32)" --rpc-url $L1_RPC
# Should match your simple.yaml game_type setting
```

## Dispute Game System Monitoring

### Game Creation Monitoring

```bash
# Check game count and recent activity
GAME_COUNT=$(cast call $DGF_ADDRESS "gameCount()(uint256)" --rpc-url $L1_RPC)
echo "Total games created: $GAME_COUNT"

# Get latest game info
if [ $GAME_COUNT -gt 0 ]; then
    LATEST_INDEX=$((GAME_COUNT - 1))
    LATEST_GAME=$(cast call $DGF_ADDRESS "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_INDEX --rpc-url $L1_RPC)
    echo "Latest game: $LATEST_GAME"

    # Parse game details
    GAME_TYPE=$(echo $LATEST_GAME | awk '{print $1}')
    TIMESTAMP=$(echo $LATEST_GAME | awk '{print $2}')
    ADDRESS=$(echo $LATEST_GAME | awk '{print $3}')

    echo "Game Type: $GAME_TYPE"
    echo "Created: $(date -r $TIMESTAMP)"
    echo "Address: $ADDRESS"

    # Check game status
    STATUS=$(cast call $ADDRESS "status()(uint8)" --rpc-url $L1_RPC)
    echo "Status: $STATUS (0=IN_PROGRESS, 1=CHALLENGER_WINS, 2=DEFENDER_WINS)"
fi
```

### Real-time Game Monitoring

```bash
# Use monitoring scripts
cd /optimism/op-challenger/scripts

# Start real-time monitoring
./monitor-game-creation.sh monitor

# Show recent 10 games
./monitor-game-creation.sh recent 10
```

### Game Creation Rate Analysis

```bash
# Check if proposer is creating games regularly (every 10 minutes)
cat << 'EOF' > check-game-frequency.sh
#!/bin/bash

FACTORY="0x732515C7795d6a8b55Af55cdcA7EE03373a6EEa6"  # Update with your factory address
RPC="$L1_RPC"

echo "=== Game Creation Frequency Analysis ==="

GAME_COUNT=$(cast call $FACTORY "gameCount()(uint256)" --rpc-url $RPC)
echo "Total games: $GAME_COUNT"

if [ $GAME_COUNT -gt 3 ]; then
    echo ""
    echo "Recent game creation times:"

    for i in $(seq $((GAME_COUNT-3)) $((GAME_COUNT-1))); do
        GAME_INFO=$(cast call $FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $i --rpc-url $RPC)
        TIMESTAMP=$(echo $GAME_INFO | awk '{print $2}')
        echo "Game $i: $(date -r $TIMESTAMP)"
    done

    # Calculate intervals
    GAME1_TIME=$(cast call $FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $((GAME_COUNT-2)) --rpc-url $RPC | awk '{print $2}')
    GAME2_TIME=$(cast call $FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $((GAME_COUNT-1)) --rpc-url $RPC | awk '{print $2}')

    INTERVAL=$((GAME2_TIME - GAME1_TIME))
    INTERVAL_MIN=$((INTERVAL / 60))

    echo ""
    echo "Last interval: ${INTERVAL_MIN} minutes"

    if [ $INTERVAL_MIN -ge 9 ] && [ $INTERVAL_MIN -le 11 ]; then
        echo "✅ Game creation frequency is normal (10 minutes)"
    else
        echo "⚠️  Game creation frequency is unusual (expected ~10 minutes)"
    fi
fi
EOF

chmod +x check-game-frequency.sh
./check-game-frequency.sh
```

## Challenger Health Monitoring

### Challenger Status Check

```bash
# Find challenger container
CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)

if [ -n "$CHALLENGER_CONTAINER" ]; then
    echo "Challenger container: $CHALLENGER_CONTAINER"

    # Check container status
    docker inspect $CHALLENGER_CONTAINER --format='{{.State.Status}}'

    # Check resource usage
    docker stats $CHALLENGER_CONTAINER --no-stream

    # Check recent logs
    echo "=== Recent Challenger Logs ==="
    docker logs $CHALLENGER_CONTAINER --tail 20
else
    echo "❌ No challenger container found"
fi
```

### Challenger Performance Analysis

```bash
# Create challenger performance monitor
cat << 'EOF' > monitor-challenger-performance.sh
#!/bin/bash

CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)

if [ -z "$CHALLENGER_CONTAINER" ]; then
    echo "❌ No challenger container found"
    exit 1
fi

echo "=== Challenger Performance Analysis ==="
echo "Container: $CHALLENGER_CONTAINER"
echo ""

# Check container health
echo "Container Status:"
docker inspect $CHALLENGER_CONTAINER --format='Status: {{.State.Status}}'
docker inspect $CHALLENGER_CONTAINER --format='Started: {{.State.StartedAt}}'
docker inspect $CHALLENGER_CONTAINER --format='Uptime: {{.State.Status}}'

echo ""
echo "Resource Usage:"
docker stats $CHALLENGER_CONTAINER --no-stream --format "CPU: {{.CPUPerc}}, Memory: {{.MemUsage}}"

echo ""
echo "Recent Activity (last 50 lines):"

# Game registration activity
REGISTRATIONS=$(docker logs $CHALLENGER_CONTAINER --tail 100 | grep -c "Registered to dispute game")
echo "Game registrations: $REGISTRATIONS"

# Error analysis
ERROR_COUNT=$(docker logs $CHALLENGER_CONTAINER --tail 200 | grep -i "error\|failed\|panic" | wc -l)
echo "Recent errors: $ERROR_COUNT"

# Prestate validation status
PRESTATE_ERRORS=$(docker logs $CHALLENGER_CONTAINER --tail 200 | grep -c "prestate.*does not match")
if [ $PRESTATE_ERRORS -gt 0 ]; then
    echo "⚠️  Prestate validation errors: $PRESTATE_ERRORS (Cold Start Problem)"
else
    echo "✅ No prestate validation errors"
fi

# Action analysis
ACTIONS=$(docker logs $CHALLENGER_CONTAINER --tail 500 | grep -c "challenge\|defend\|action")
echo "Challenger actions taken: $ACTIONS"

if [ $ACTIONS -eq 0 ]; then
    echo "ℹ️  No challenger actions (normal if all games are valid)"
else
    echo "⚠️  Challenger has taken actions - review logs for details"
fi

echo ""
echo "Recent Log Entries:"
docker logs $CHALLENGER_CONTAINER --tail 10
EOF

chmod +x monitor-challenger-performance.sh
./monitor-challenger-performance.sh
```

## System Performance Monitoring

### Resource Usage Analysis

```bash
# Docker resource overview
echo "=== Docker Resource Usage ==="
docker system df
echo ""

# Container resource usage
echo "=== Container Resource Usage ==="
docker stats --no-stream

# System resource usage
echo ""
echo "=== System Resources ==="
echo "Memory usage:"
free -h

echo ""
echo "Disk usage:"
df -h

echo ""
echo "CPU load:"
uptime
```

### Network Performance

```bash
# RPC response time test
test_rpc_performance() {
    local rpc_url=$1
    local name=$2

    echo "Testing $name ($rpc_url):"

    # Test multiple calls and measure time
    for i in {1..5}; do
        time_start=$(date +%s.%N)
        cast block-number --rpc-url $rpc_url >/dev/null 2>&1
        time_end=$(date +%s.%N)
        duration=$(echo "$time_end - $time_start" | bc)
        echo "  Call $i: ${duration}s"
    done
}

echo "=== RPC Performance Test ==="
test_rpc_performance "$L1_RPC" "L1"
test_rpc_performance "$L2_RPC" "L2"
```

## Automated Monitoring Setup

### Continuous Health Monitoring

```bash
# Create continuous monitoring script
cat << 'EOF' > continuous-monitor.sh
#!/bin/bash

MONITOR_INTERVAL=${1:-60}  # Default 60 seconds
LOG_FILE="/tmp/op-challenger-monitor.log"

echo "Starting continuous monitoring (interval: ${MONITOR_INTERVAL}s)"
echo "Log file: $LOG_FILE"
echo "Press Ctrl+C to stop"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "=== $TIMESTAMP ==="

        # Quick health check
        RUNNING_SERVICES=$(kurtosis enclave inspect simple-devnet 2>/dev/null | grep "RUNNING" | wc -l)
        echo "Running services: $RUNNING_SERVICES"

        # Game count
        if [ -f "/tmp/devnet-desc/env.json" ]; then
            DGF_ADDRESS=$(grep -o 'DisputeGameFactoryProxy[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)
            L1_RPC=$(grep -o '"rpc":"http://[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f4)
            GAME_COUNT=$(cast call $DGF_ADDRESS "gameCount()(uint256)" --rpc-url $L1_RPC 2>/dev/null)
            echo "Total games: $GAME_COUNT"
        fi

        # Challenger status
        CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)
        if [ -n "$CHALLENGER_CONTAINER" ]; then
            echo "Challenger: Running"
        else
            echo "Challenger: Not found"
        fi

        echo ""

    } | tee -a $LOG_FILE

    sleep $MONITOR_INTERVAL
done
EOF

chmod +x continuous-monitor.sh

# Start monitoring (run in background)
# ./continuous-monitor.sh 30 &  # Check every 30 seconds
```

## Troubleshooting Integration

If health checks fail, see the comprehensive troubleshooting guide:

**📚 Related Guides:**
- [Installation Guide](./installation-guide.md) - Step-by-step setup
- [Dispute Game Monitoring Guide](./dispute-game-monitoring.md) - Detailed monitoring
- [Troubleshooting Guide](./troubleshooting-guide.md) - Problem resolution
- [Configuration Guide](./configuration-guide.md) - Advanced configuration

## Health Check Alerts

### Setting Up Alerts

```bash
# Create alert script for critical issues
cat << 'EOF' > health-alerts.sh
#!/bin/bash

# Configuration
ALERT_EMAIL="your-email@example.com"  # Optional
SLACK_WEBHOOK=""  # Optional

# Run health check and capture results
./system-health-check.sh > /tmp/health-check-result.log 2>&1
HEALTH_STATUS=$?

# Alert conditions
if [ $HEALTH_STATUS -eq 2 ]; then
    MESSAGE="🚨 CRITICAL: OP-Challenger system has significant issues"

    # Log alert
    echo "$(date): $MESSAGE" >> /tmp/health-alerts.log

    # Display alert
    echo "$MESSAGE"
    cat /tmp/health-check-result.log

    # Optional: Send email alert
    # echo "$MESSAGE" | mail -s "OP-Challenger Alert" $ALERT_EMAIL

elif [ $HEALTH_STATUS -eq 1 ]; then
    echo "⚠️  WARNING: Minor issues detected"
    grep "❌ FAIL" /tmp/health-check-result.log
fi
EOF

chmod +x health-alerts.sh

# Run alerts manually
./health-alerts.sh

# Or set up as cron job (every 5 minutes)
# */5 * * * * /path/to/health-alerts.sh
```