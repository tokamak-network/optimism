# OP-Challenger Installation Guide

Complete step-by-step guide for setting up the OP-Challenger development environment.

## Prerequisites

- **macOS/Linux** (tested on macOS Sonoma 14.4+)
- **Docker Desktop** (6GB+ RAM, 4+ CPU cores)
- **Internet Connection** (for downloading dependencies)

## Installation Steps

### Step 1: Install System Tools

Run the automated tool installer:

```bash
cd /optimism/op-challenger/scripts
./install-tools.sh
```

**What this installs:**
- Go 1.23+
- Docker & Docker Desktop
- Mise (tool version manager)
- Kurtosis (devnet orchestration)
- Just (command runner)
- Foundry (cast, forge)

**Verification:**
```bash
# Check all tools are installed
go version        # Should show 1.23+
docker --version  # Should show Docker version
mise --version    # Should show mise version
kurtosis version  # Should show kurtosis version
just --version    # Should show just version
cast --version    # Should show foundry version
```

**Troubleshooting:**
- If Docker fails: Restart Docker Desktop manually
- If Go installation fails: Check system PATH
- If permission errors: Run with appropriate permissions

---

### Step 2: Build Contract Artifacts

Build the smart contracts and create necessary binaries:

```bash
# Build contracts
cd /optimism/packages/contracts-bedrock
forge build --force

# Build challenger binaries
cd /optimism/op-challenger/scripts
./build-contract-artifacts.sh
./build-binaries-for-challenger.sh --force
```

**What this creates:**
- Contract compilation artifacts
- Cannon VM binaries
- Prestate files
- MIPS/Asterisc binaries (if configured)

**Verification:**
```bash
# Check contract artifacts
ls -la /optimism/packages/contracts-bedrock/forge-artifacts/ | head -5

# Check challenger binaries
ls -la /optimism/op-challenger/scripts/artifacts/
# Should show: cannon, op-program, prestate files

# Verify prestate files
ls -la /optimism/op-challenger/scripts/artifacts/ | grep prestate
```

**Build Options:**
```bash
# Default: build only if missing
./build-binaries-for-challenger.sh

# Force rebuild (use after contract changes)
./build-binaries-for-challenger.sh --force

# Show help
./build-binaries-for-challenger.sh --help
```

**Troubleshooting:**
- If forge build fails: Check Go and Foundry versions
- If binaries fail to build: Ensure sufficient disk space
- If permission errors: Check file permissions

---

### Step 3: Configure Devnet Settings

Configure your devnet parameters:

```bash
cd /optimism/kurtosis-devnet

# Edit devnet configuration
vim simple.yaml  # or your preferred editor
```

**Key Configuration Options:**

```yaml
# Game type selection
proposer_params:
  game_type: 0  # 0=CANNON, 1=PERMISSIONED, 2=ASTERISC
  proposal_interval: 10m  # Game creation interval

# Challenger settings
challengers:
  challenger:
    enabled: true  # Enable/disable built-in challenger
    participants: "*"  # Monitor all participants
```

**Game Types:**

| Type | Name | Purpose | Status |
|------|------|---------|--------|
| **0** | CANNON | Full fault proofs | ⚠️ Needs testing |
| **1** | PERMISSIONED | Development/testing | ✅ Working |
| **2** | ASTERISC | Alternative VM | ⚠️ Needs testing |

**Verification:**
```bash
# Validate YAML syntax
python -c "import yaml; yaml.safe_load(open('simple.yaml'))"
# Should show no errors

# Check game type setting
grep -n "game_type" simple.yaml
```

**📖 Detailed Configuration**: [Configuration Guide](./configuration-guide.md)

---

### Step 4: Deploy Devnet

Deploy your local development network:

```bash
cd /optimism/kurtosis-devnet

# Option 1: Normal deployment
AUTOFIX=true just simple-devnet

# Option 2: Complete reset (if you changed contracts)
AUTOFIX=nuke just simple-devnet

# Option 3: With automatic fixes (recommended)
just devnet-with-fix simple.yaml
```

**Deployment Process:**
1. **Download Images**: Docker images are pulled (~5-10 minutes)
2. **Network Setup**: L1 and L2 networks are configured
3. **Contract Deployment**: Smart contracts are deployed
4. **Service Start**: All services start (proposer, batcher, etc.)

**Real-time Monitoring:**
```bash
# Watch deployment progress
kurtosis enclave inspect simple-devnet

# Monitor service logs during deployment
kurtosis service logs simple-devnet el-1-geth-teku --follow
```

**Autofix Options:**

- **`AUTOFIX=true`**: Cleanup previous deployment, preserve other enclaves
- **`AUTOFIX=nuke`**: Complete reset, remove all enclaves
- **`just devnet-with-fix`**: Deploy with automatic issue resolution

**Verification:**
```bash
# Check deployment status
kurtosis enclave inspect simple-devnet
# All services should show "RUNNING"

# Get connection info
kurtosis files download simple-devnet devnet-descriptor-0 /tmp/devnet-desc
cat /tmp/devnet-desc/env.json | jq -r '.L1_RPC'
```

**Common Deployment Issues:**
- **Traefik network error**: Automatically handled by `just devnet-with-fix`
- **Port conflicts**: Check for running services on required ports
- **Memory issues**: Ensure Docker has 6GB+ RAM allocated

---

### Step 5: Verify Deployment

Verify your deployment is working correctly:

```bash
# Download deployment info
kurtosis files download simple-devnet devnet-descriptor-0 /tmp/devnet-desc

# Get key addresses and endpoints
L1_RPC=$(grep -o '"rpc":"http://[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f4)
L2_RPC=$(grep -o '"l2_rpc":"http://[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f4)
OPCM_ADDRESS=$(grep -o 'OPContractsManager[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)

echo "L1 RPC: $L1_RPC"
echo "L2 RPC: $L2_RPC"
echo "OPCM: $OPCM_ADDRESS"
```

**Contract Verification:**
```bash
# Verify deployment version
cast call $OPCM_ADDRESS "getDeploymentVersion()(string)" --rpc-url $L1_RPC

# Check respected game type
OP_PORTAL=$(grep -o 'OptimismPortalProxy[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)
cast call $OP_PORTAL "respectedGameType()(uint32)" --rpc-url $L1_RPC
```

**Network Connectivity:**
```bash
# Test L1 connection
cast block-number --rpc-url $L1_RPC

# Test L2 connection
cast block-number --rpc-url $L2_RPC

# Check L2 is producing blocks
sleep 15
cast block-number --rpc-url $L2_RPC  # Should be higher
```

**Expected Results:**
- ✅ **Deployment version**: Shows your custom version string
- ✅ **Game type**: Matches your simple.yaml setting (0 for CANNON)
- ✅ **L1/L2 connectivity**: Both respond with block numbers
- ✅ **Block production**: L2 block number increases over time

---

### Step 6: Run Challenger

Start the OP-Challenger to monitor dispute games:

```bash
cd /optimism/op-challenger/scripts
./run-challenger-devnet.sh
```

**What the challenger does:**
- Monitors new dispute games created by proposer
- Validates game claims against local state
- Challenges invalid claims automatically
- Provides monitoring and metrics

**Verification:**
```bash
# Check challenger is running
docker ps | grep challenger

# Monitor challenger logs
docker logs op-challenger --follow

# Check challenger metrics (if enabled)
curl -s http://localhost:9001/metrics | grep challenger
```

**Healthy Challenger Logs:**
```
INFO challenger: Starting challenger service
INFO challenger: Connected to L1 RPC endpoint
INFO challenger: Monitoring dispute games...
INFO challenger: Registered to dispute game game=0x... status=IN_PROGRESS
```

---

## Post-Installation Verification

### Complete System Check

manually verify each component:

```bash
# 1. Check all services are running
kurtosis enclave inspect simple-devnet | grep RUNNING | wc -l
# Should show 8-10 running services

# 2. Verify dispute games are being created
./monitor-game-creation.sh recent 3

# 3. Check challenger is monitoring games
docker logs op-challenger --tail 20 | grep -i "game\|dispute"

# 4. Test basic L1/L2 functionality
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url $L1_RPC
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url $L2_RPC
```

### Performance Verification

```bash
# Check resource usage
docker stats --no-stream

# Monitor block production rate
watch -n 5 "echo 'L1:' && cast block-number --rpc-url $L1_RPC && echo 'L2:' && cast block-number --rpc-url $L2_RPC"

# Check proposer game creation frequency (should be every 10 minutes)
./monitor-game-creation.sh monitor
```

---

## Next Steps

Once installation is complete:

1. **📊 Monitoring**: [Dispute Game Monitoring Guide](./dispute-game-monitoring.md)
2. **🔧 Configuration**: [Configuration Guide](./configuration-guide.md)
3. **🚨 Troubleshooting**: [Troubleshooting Guide](./troubleshooting-guide.md)
4. **🧪 Testing**: [Testing Guide](./testing-guide.md)

## Quick Reference

**Essential Commands:**
```bash
# Check status
kurtosis enclave inspect simple-devnet

# Monitor games
./monitor-game-creation.sh monitor

# Check logs
docker logs op-challenger --follow
kurtosis service logs simple-devnet op-proposer-2151908-op-kurtosis --follow

# Cleanup
kurtosis enclave rm --force simple-devnet
```

**Key Files:**
- `/tmp/devnet-desc/env.json` - Deployment addresses and endpoints
- `simple.yaml` - Devnet configuration
- `artifacts/` - Built binaries and prestate files

**Default Ports:**
- L1 RPC: Dynamic (check env.json)
- L2 RPC: Dynamic (check env.json)
- Challenger metrics: 9001
- Proposer metrics: 9001