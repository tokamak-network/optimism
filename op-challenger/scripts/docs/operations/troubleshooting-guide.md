# Troubleshooting Guide

Comprehensive troubleshooting guide for common OP-Challenger issues and their solutions.

## Quick Diagnosis

### Emergency Recovery Commands

If your system is completely broken:

```bash
# Nuclear option - complete reset
cd /optimism/kurtosis-devnet
AUTOFIX=nuke just simple-devnet

# Docker cleanup if needed
docker system prune -f
docker volume prune -f

# Restart Docker Desktop (macOS)
osascript -e 'quit app "Docker Desktop"' && sleep 5 && open -a "Docker Desktop"
```

### Fast Diagnosis Script

```bash
# Quick problem identification
cat << 'EOF' > quick-diagnosis.sh
#!/bin/bash

echo "=== Quick Diagnosis ==="

# Check Docker
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running"
    exit 1
fi

# Check Kurtosis
if ! kurtosis version >/dev/null 2>&1; then
    echo "❌ Kurtosis is not accessible"
    exit 1
fi

# Check enclave
if ! kurtosis enclave inspect simple-devnet >/dev/null 2>&1; then
    echo "❌ Devnet enclave not found"
    echo "Run: AUTOFIX=true just simple-devnet"
    exit 1
fi

# Check services
RUNNING_SERVICES=$(kurtosis enclave inspect simple-devnet | grep "RUNNING" | wc -l)
if [ $RUNNING_SERVICES -lt 8 ]; then
    echo "⚠️  Only $RUNNING_SERVICES services running (expected 8+)"
    echo "Some services may have failed"
else
    echo "✅ $RUNNING_SERVICES services running"
fi

# Check challenger
if docker ps --format "{{.Names}}" | grep -q challenger; then
    echo "✅ Challenger container found"
else
    echo "⚠️  No challenger container - may need to start manually"
fi

echo "Basic diagnosis complete"
EOF

chmod +x quick-diagnosis.sh
./quick-diagnosis.sh
```

## Common Issues & Solutions

### 1. Cold Starting State Issues

#### Problem: All New Games Fail Prestate Validation with 0xdead... Error

**Symptoms**:
```
ERROR Failed to validate prestate
  contract_root=0xdead0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
  provider_root=0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195
  error="output root absolute prestate does not match"
```

**Diagnosis**:
```bash
# Check if in Cold Starting state
ANCHOR_STATE_REGISTRY="0x..."
ANCHOR_ROOT=$(cast call $ANCHOR_STATE_REGISTRY \
  "getAnchorRoot()(bytes32,uint256)" \
  --rpc-url $L1_RPC | head -1)

if [[ "$ANCHOR_ROOT" == "0xdead"* ]]; then
    echo "❌ System is in Cold Starting state"
    echo "💡 anchorGame not set yet"
else
    echo "✅ Anchor root is valid: $ANCHOR_ROOT"
fi

# Check anchorGame status
ANCHOR_GAME=$(cast call $ANCHOR_STATE_REGISTRY \
  "anchorGame()(address)" \
  --rpc-url $L1_RPC)

if [ "$ANCHOR_GAME" == "0x0000000000000000000000000000000000000000" ]; then
    echo "❌ anchorGame = address(0)"
    echo "💡 Need to resolve first valid game and call closeGame()"
fi
```

**Root Cause**:
- AnchorStateRegistry initialized with placeholder value (0xdead...)
- No valid game has been resolved and finalized yet
- `closeGame()` was never called to update anchorGame

**Solution** (Complete Process):
```bash
# Step 1: Find or create first valid game
DISPUTE_GAME_FACTORY="0x..."
GAME_COUNT=$(cast call $DISPUTE_GAME_FACTORY "gameCount()(uint256)" --rpc-url $L1_RPC)
echo "Total games: $GAME_COUNT"

# Get latest game
if [ "$GAME_COUNT" -gt "0" ]; then
    LATEST_INDEX=$((GAME_COUNT - 1))
    GAME_INFO=$(cast call $DISPUTE_GAME_FACTORY \
      "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_INDEX \
      --rpc-url $L1_RPC)
    GAME_ADDRESS=$(echo "$GAME_INFO" | tail -1)
    echo "Latest game: $GAME_ADDRESS"
fi

# Step 2: Check if game is resolved
GAME_STATUS=$(cast call $GAME_ADDRESS "status()(uint8)" --rpc-url $L1_RPC)
case $GAME_STATUS in
    0) echo "🟡 IN_PROGRESS - need to resolve" ;;
    1) echo "🔴 CHALLENGER_WINS - invalid game" ;;
    2) echo "🟢 DEFENDER_WINS - ready to close" ;;
esac

# Step 3: Resolve if needed
if [ "$GAME_STATUS" == "0" ]; then
    echo "Resolving game..."
    cast send $GAME_ADDRESS "resolve()" --rpc-url $L1_RPC --private-key $KEY
fi

# Step 4: Wait for finality delay
DELAY=$(cast call $ANCHOR_STATE_REGISTRY \
  "disputeGameFinalityDelaySeconds()(uint256)" \
  --rpc-url $L1_RPC)
echo "⏳ Waiting $DELAY seconds for finality..."
sleep $DELAY

# Step 5: 🔥 CRITICAL: Call closeGame()
echo "🎯 Calling closeGame() to update anchorGame..."
cast send $GAME_ADDRESS "closeGame()" \
  --rpc-url $L1_RPC \
  --private-key $KEY

# Step 6: Verify fix
ANCHOR_GAME_AFTER=$(cast call $ANCHOR_STATE_REGISTRY \
  "anchorGame()(address)" \
  --rpc-url $L1_RPC)

if [ "$ANCHOR_GAME_AFTER" != "0x0000000000000000000000000000000000000000" ]; then
    echo "✅ Cold Starting state resolved!"
    echo "✅ anchorGame updated to: $ANCHOR_GAME_AFTER"
    echo "✅ All new games will now use valid starting root"
else
    echo "❌ anchorGame still not set"
    echo "💡 Check if game meets requirements:"
    echo "   - Must be DEFENDER_WINS"
    echo "   - Must pass finality delay"
    echo "   - Must be proper game (not blacklisted)"
fi
```

**Prevention**:
```bash
# Always call closeGame() after resolving first game
# Add to deployment scripts:
echo "Resolving first game and updating anchorGame..."
cast send $FIRST_GAME "resolve()" --rpc-url $L1_RPC --private-key $KEY
sleep $FINALITY_DELAY
cast send $FIRST_GAME "closeGame()" --rpc-url $L1_RPC --private-key $KEY
```

**See Also**:
- [anchor-state-fix.md](../challenger/anchor-state-fix.md) - Detailed fix guide
- [anchor-game-update-guide.md](../dispute-games/anchor-game-update-guide.md) - Complete update process
- [challenger-prestate-validation.md](../challenger/challenger-prestate-validation.md) - Validation details

---

### 2. Installation Issues

#### Docker Desktop Not Running
**Problem**: Commands fail with Docker daemon errors
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

**Solutions**:
```bash
# Start Docker Desktop
open -a "Docker Desktop"

# Wait for Docker to start (check every 5 seconds)
while ! docker info >/dev/null 2>&1; do
    echo "Waiting for Docker to start..."
    sleep 5
done

# Verify Docker is working
docker run hello-world
```

#### Go Version Issues
**Problem**: Wrong Go version or Go not found
```bash
# Check current version
go version

# If wrong version, reinstall with mise
mise install go@1.23
mise use go@1.23
mise reshim go

# Verify
go version  # Should show 1.23+
```

#### Foundry/Cast Issues
**Problem**: `cast` command not found or version issues
```bash
# Reinstall Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Add to PATH if needed
export PATH="$HOME/.foundry/bin:$PATH"

# Verify
cast --version
forge --version
```

---

### 2. Devnet Deployment Issues

#### Kurtosis Enclave Errors
**Problem**: Enclave creation fails or gets stuck

**Solution 1 - Clean restart**:
```bash
# Stop existing enclave
kurtosis enclave stop simple-devnet
kurtosis enclave rm simple-devnet

# Clean Kurtosis engine
kurtosis engine stop
kurtosis engine start

# Redeploy
AUTOFIX=true just simple-devnet
```

**Solution 2 - Complete reset**:
```bash
# Nuclear option
kurtosis engine stop
docker rm -f $(docker ps -aq --filter ancestor=kurtosistech/engine)
kurtosis engine start

# Clean deploy
AUTOFIX=nuke just simple-devnet
```

#### Docker Registry Timeout
**Problem**: Image pulls timeout from `us-docker.pkg.dev`
```
Get "https://us-docker.pkg.dev/v2/token": Client.Timeout exceeded
```

**Solutions**:
```bash
# Solution 1: Restart Docker networking
docker network prune -f
osascript -e 'quit app "Docker Desktop"' && sleep 5 && open -a "Docker Desktop"

# Solution 2: Clean Docker cache
docker system prune -a -f

# Solution 3: Use different registry/tags
# Edit kurtosis config to use different image tags

# Solution 4: Pre-pull common images
docker pull consensys/teku:25.7.0
docker pull ethereum/client-go:v1.14.8
```

#### Traefik Network Configuration Error
**Problem**: Traefik can't configure Docker networks
```
failed to create Docker client: Cannot connect to Docker daemon
```

**Auto-fix (recommended)**:
```bash
cd /optimism/kurtosis-devnet

# Option 1: Use automated fix
just devnet-with-fix simple.yaml

# Option 2: Manual fix after deployment
just fix-traefik
```

**Manual fix**:
```bash
# Restart Traefik container
docker restart $(docker ps --filter "name=kurtosis-reverse-proxy" --format "{{.Names}}")

# Or recreate the problematic network
docker network rm $(docker network ls --filter name=kurtosis --format "{{.ID}}")
```

---

### 3. Service-Specific Issues

#### Proposer Not Creating Games
**Problem**: No dispute games being created

**Diagnosis**:
```bash
# Check proposer logs
docker logs op-proposer-2151908-op-kurtosis-... --tail 50

# Look for these patterns:
# ✅ Good: "Proposing output root" every 10 minutes
# ❌ Bad: Connection errors, transaction failures
```

**Solutions**:
```bash
# Check proposer configuration
docker exec op-proposer-... env | grep -E "GAME|FACTORY|PRIVATE"

# Verify factory address is correct
DGF_ADDRESS=$(grep -o 'DisputeGameFactoryProxy[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)
echo "Factory address: $DGF_ADDRESS"

# Test factory contract
L1_RPC=$(grep -o '"rpc":"http://[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f4)
cast call $DGF_ADDRESS "gameCount()(uint256)" --rpc-url $L1_RPC
```

#### L1/L2 Connectivity Issues
**Problem**: RPC calls timeout or fail

**Diagnosis**:
```bash
# Test L1 connectivity
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $L1_RPC

# Test L2 connectivity
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $L2_RPC
```

**Solutions**:
```bash
# Check service status
kurtosis service inspect simple-devnet el-1-geth-teku
kurtosis service inspect simple-devnet op-el-2151908-node0-op-geth

# Restart specific services
kurtosis service restart simple-devnet el-1-geth-teku
kurtosis service restart simple-devnet op-el-2151908-node0-op-geth

# Check port mappings
kurtosis enclave inspect simple-devnet | grep -A5 -B5 "rpc.*8545"
```

---

### 4. Challenger-Specific Issues

#### Challenger Container Not Starting
**Problem**: Challenger fails to start or immediately exits

**Diagnosis**:
```bash
# Check if challenger container exists
docker ps -a | grep challenger

# Check exit code and logs
docker logs op-challenger --tail 50

```

**Solutions**:
```bash
# Rebuild challenger binaries
cd /optimism/op-challenger/scripts
./build-binaries-for-challenger.sh --force

# Check artifact permissions
ls -la artifacts/
chmod +r artifacts/*

# Restart challenger manually
./run-challenger-devnet.sh
```

#### Prestate Validation Failures (Cold Start Problem)
**Problem**: Challenger logs show prestate mismatch errors
```
ERROR: output root absolute prestate does not match
Provider: 0x03a1a135... | Contract: 0xdead000000000000000000000000000000000000000000000000000000000000
```

**This is the AnchorStateRegistry "cold start" problem - expected for new devnets**

**Auto-fix**:
```bash
cd /optimism/kurtosis-devnet

# Use automated fix script
just fix-anchor-state

# Or deploy with fixes included
just devnet-with-fix simple.yaml
```

**Manual fix**:
```bash
# Get deployment info
source <(cat /tmp/devnet-desc/env.json | jq -r 'to_entries | map("export " + .key + "=" + (.value | @sh)) | .[]')

# Create valid dispute game with L2 genesis root
L2_GENESIS_ROOT=$(cast block 0 --rpc-url $L2_RPC -f stateRoot)

cast send $DGF "create(uint32,bytes32,bytes)" \
  0 $L2_GENESIS_ROOT 0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url $L1_RPC \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Game will resolve automatically, updating AnchorStateRegistry
```

#### Challenger Not Detecting Games
**Problem**: Challenger starts but doesn't register new games

**Diagnosis**:
```bash
# Check challenger is monitoring the right factory
docker logs op-challenger | grep -i "factory\|game.*address"

# Verify factory address matches deployment
DGF_ADDRESS=$(grep -o 'DisputeGameFactoryProxy[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)
docker logs op-challenger | grep -i "$DGF_ADDRESS"
```

**Solutions**:
```bash
# Check challenger configuration
docker exec op-challenger env | grep -E "GAME|FACTORY|L1"

# Restart challenger with fresh config
docker stop op-challenger
./run-challenger-devnet.sh

# Verify game detection
./monitor-game-creation.sh recent 5
```

---

### 5. Performance Issues

#### High Memory Usage
**Problem**: Docker containers consuming too much memory

**Diagnosis**:
```bash
# Check container memory usage
docker stats --no-stream

# Check system memory
free -h
vm_stat  # macOS
```

**Solutions**:
```bash
# Increase Docker Desktop memory allocation (8GB+)
# Docker Desktop → Settings → Resources → Memory

# Reduce running services temporarily
kurtosis service stop simple-devnet grafana
kurtosis service stop simple-devnet prometheus

# Clean up unused containers/images
docker system prune -f
docker image prune -a -f
```

#### Slow Block Production
**Problem**: Blocks are produced slowly or irregularly

**Diagnosis**:
```bash
# Monitor block production rate
watch -n 5 "echo 'L1:' && cast block-number --rpc-url $L1_RPC && echo 'L2:' && cast block-number --rpc-url $L2_RPC"

# Check proposer interval
docker logs op-proposer-... | grep "proposal interval"
```

**Solutions**:
```bash
# Check CPU usage
top
docker stats --no-stream

# Adjust Docker resources
# Docker Desktop → Settings → Resources → CPUs (4+)

# Check for CPU throttling
docker exec el-1-geth-teku top
```

---

### 6. Network & Port Issues

#### Port Conflicts
**Problem**: Services fail to start due to port conflicts

**Diagnosis**:
```bash
# Check what's using common ports
lsof -i :8545  # Ethereum RPC
lsof -i :8546  # Ethereum WebSocket
lsof -i :9001  # Metrics
lsof -i :3000  # Grafana

# Check kurtosis port assignments
kurtosis enclave inspect simple-devnet | grep -E "rpc|tcp"
```

**Solutions**:
```bash
# Kill processes using conflicting ports
sudo kill $(lsof -ti:8545)

# Or modify simple.yaml to use different ports
# Edit port mappings in the configuration

# Restart with clean port assignments
kurtosis enclave rm simple-devnet
AUTOFIX=true just simple-devnet
```

#### DNS/Networking Issues
**Problem**: Services can't resolve each other's hostnames

**Solutions**:
```bash
# Check Docker networking
docker network ls
docker network inspect $(docker network ls --filter name=kurtosis --format "{{.ID}}")

# Recreate Docker networks
docker network prune -f
kurtosis engine restart
```

---

### 7. Data & State Issues

#### Corrupted State Data
**Problem**: Inconsistent state between services

**Solutions**:
```bash
# Clean state data
kurtosis enclave rm simple-devnet
docker volume prune -f

# Fresh deployment
AUTOFIX=nuke just simple-devnet
```

#### Missing Contract Artifacts
**Problem**: Contracts not found or outdated

**Solutions**:
```bash
# Rebuild all artifacts
cd /optimism/packages/contracts-bedrock
forge clean
forge build --force

cd /optimism/op-challenger/scripts
./build-contract-artifacts.sh
./build-binaries-for-challenger.sh --force

# Redeploy with fresh contracts
cd /optimism/kurtosis-devnet
AUTOFIX=nuke just simple-devnet
```

---

## Advanced Troubleshooting

### Log Analysis Scripts

#### Comprehensive Log Collector
```bash
cat << 'EOF' > collect-logs.sh
#!/bin/bash

LOG_DIR="/tmp/op-challenger-logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

echo "Collecting logs to: $LOG_DIR"

# System info
echo "=== System Info ===" > "$LOG_DIR/system-info.log"
uname -a >> "$LOG_DIR/system-info.log"
docker version >> "$LOG_DIR/system-info.log" 2>&1
kurtosis version >> "$LOG_DIR/system-info.log" 2>&1

# Docker info
docker ps > "$LOG_DIR/docker-ps.log"
docker stats --no-stream > "$LOG_DIR/docker-stats.log"

# Kurtosis info
kurtosis enclave inspect simple-devnet > "$LOG_DIR/kurtosis-enclave.log" 2>&1

# Service logs
for service in el-1-geth-teku cl-1-teku-geth op-el-2151908-node0-op-geth op-cl-2151908-node0-op-node op-proposer-2151908-op-kurtosis op-batcher-2151908-op-kurtosis; do
    kurtosis service logs simple-devnet "$service" --tail 200 > "$LOG_DIR/$service.log" 2>&1
done

# Challenger logs
CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)
if [ -n "$CHALLENGER_CONTAINER" ]; then
    docker logs "$CHALLENGER_CONTAINER" --tail 500 > "$LOG_DIR/challenger.log" 2>&1
fi

# Configuration files
if [ -f "/tmp/devnet-desc/env.json" ]; then
    cp /tmp/devnet-desc/env.json "$LOG_DIR/"
fi

if [ -f "/optimism/kurtosis-devnet/simple.yaml" ]; then
    cp /optimism/kurtosis-devnet/simple.yaml "$LOG_DIR/"
fi

# Create archive
tar -czf "$LOG_DIR.tar.gz" -C /tmp "$(basename $LOG_DIR)"

echo "Logs collected in: $LOG_DIR.tar.gz"
echo "Share this file when reporting issues"
EOF

chmod +x collect-logs.sh
```

#### Error Pattern Analysis
```bash
cat << 'EOF' > analyze-errors.sh
#!/bin/bash

echo "=== Error Pattern Analysis ==="

# Analyze challenger errors
CHALLENGER_CONTAINER=$(docker ps --format "{{.Names}}" | grep challenger | head -1)
if [ -n "$CHALLENGER_CONTAINER" ]; then
    echo "Challenger Errors:"
    docker logs "$CHALLENGER_CONTAINER" --tail 500 | grep -i "error\|failed\|panic" | sort | uniq -c | sort -nr
    echo ""
fi

# Analyze service errors
echo "Service Errors:"
for service in op-proposer-2151908-op-kurtosis op-batcher-2151908-op-kurtosis; do
    echo "--- $service ---"
    kurtosis service logs simple-devnet "$service" --tail 200 2>/dev/null | grep -i "error\|failed" | tail -5
done

# Analyze Docker errors
echo ""
echo "Docker System Errors:"
docker system events --since 1h --until now 2>/dev/null | grep -i "error\|failed" | tail -10
EOF

chmod +x analyze-errors.sh
./analyze-errors.sh
```

### Performance Profiling

```bash
# Create performance monitoring script
cat << 'EOF' > performance-profile.sh
#!/bin/bash

echo "=== Performance Profile ==="
echo "Timestamp: $(date)"
echo ""

# System resources
echo "System Memory:"
free -h
echo ""

echo "System CPU:"
uptime
echo ""

echo "Disk Usage:"
df -h /tmp /var
echo ""

# Docker resources
echo "Docker Stats:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
echo ""

# Network performance
echo "Network Performance Test:"
time cast block-number --rpc-url $L1_RPC >/dev/null 2>&1
echo "L1 RPC response time: ⬆"

time cast block-number --rpc-url $L2_RPC >/dev/null 2>&1
echo "L2 RPC response time: ⬆"
EOF

chmod +x performance-profile.sh
./performance-profile.sh
```

## Getting Additional Help

### Before Reporting Issues

1. **Run diagnostics**:
   ```bash
   ./quick-diagnosis.sh
   # Note: system-health-check.sh not available
   ./analyze-errors.sh
   ```

2. **Collect comprehensive logs**:
   ```bash
   ./collect-logs.sh
   # Share the generated .tar.gz file
   ```

3. **Try nuclear reset**:
   ```bash
   AUTOFIX=nuke just simple-devnet
   ```

### Common Support Information

When asking for help, include:

- **System**: macOS/Linux version
- **Docker**: Version and resource allocation
- **Error logs**: From the log collection script
- **Configuration**: Your `simple.yaml` settings
- **Reproduction steps**: What you did before the issue occurred

### Related Documentation

- **📖 Installation Guide**: [installation-guide.md](../deployment/installation-guide.md)
- **📊 System Verification**: [system-verification.md](../verification/system-verification.md)
- **🎮 Game Monitoring**: [dispute-game-monitoring.md](../dispute-games/dispute-game-monitoring.md)
- **⚙️ Configuration**: [configuration-guide.md](../deployment/configuration-guide.md)

### Emergency Recovery Checklist

If nothing else works:

- [ ] Stop Docker Desktop completely
- [ ] `rm -rf ~/.kurtosis` (removes all Kurtosis data)
- [ ] `docker system prune -a -f` (removes all Docker data)
- [ ] Restart computer
- [ ] Restart Docker Desktop
- [ ] `kurtosis engine start`
- [ ] Re-run installation from Step 1