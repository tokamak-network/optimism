# Phase 1 Challenger Network


## 🚀 Quick Installation

### Local Devnet Development Environment

# Step 1: Install system tools
```bash
cd op-challenger/scripts
./install-tools.sh
```

# Step 2: Compile contracts and create artifacts
```bash
cd /optimism/packages/contracts-bedrock
forge build
cd /optimism/op-challenger/scripts
./build-contract-artifacts.sh
```

# Step 3: Set Game Type
Edit game-type in 'simple.yaml'

```bash
cd /optimism/kurtosis-devnet


 - 'simple.yaml'

proposer_params:
        image: {{ localDockerImage "op-proposer" }}
        extra_params: []
        game_type: 0            //-> here
        proposal_interval: 10m
```

### Supported Game Types
| Type | Name | Purpose | Challenger Config | Status |
|------|------|---------|-------------------|--------|
| **0** | CANNON | Complete fault proof | Auto uses `cannon` | ⚠️ needs testing |
| **1** | PERMISSIONED | Fast development/testing | Auto uses `permissioned` | ✅ **working** |
| **2** | ASTERISC | Asterisc VM | Auto uses `asterisc` | ⚠️ needs testing |


# Step 4: Build Devnet Environment

```bash
# For normal cleanup
AUTOFIX=true just simple-devnet

# For complete reset, If the code is changed and recompiled, be sure to use this.
AUTOFIX=nuke just simple-devnet

# If Traefik network error occurs, run this after deployment:
cd /optimism/kurtosis-devnet && just fix-traefik
```

**💡 Pro Tips**:
- Use `just devnet-with-fix simple.yaml` in kurtosis-devnet directory to automatically handle **both Traefik and AnchorStateRegistry issues**
- For AnchorStateRegistry cold start problems only: `just fix-anchor-state`

### Autofix mode

Autofix mode helps recover from failed devnet deployments by automatically
cleaning up the environment. It has two modes:

1. **Normal Mode** (`AUTOFIX=true`)
   - Sets up the correct shell and updates dependencies
   - Cleans up dangling networks and stopped devnets
   - Preserves other running enclaves
   - Good for fixing minor deployment issues

2. **Nuke Mode** (`AUTOFIX=nuke`)
   - Sets up the correct shell and updates dependencies
   - Completely resets the Kurtosis environment
   - Removes all networks and containers
   - Use when you need a fresh start


# Step 4: Run Challenger
```bash
cd /optimism/op-challenger/scripts
./run-challenger-devnet.sh

```

**📖 Detailed Configuration Guide**: [Rollup Configuration Guide](./docs/rollup-configuration-guide.md)

**🔍 Deployment Monitoring**: [Log Monitoring Guide](./docs/monitoring-deployment-logs.md)


## System Tools Auto Installation

### What the auto-installation script does:

```bash
# Install system tools only
./install-tools.sh
```

✅ Automatic system status verification
✅ Auto-installation of missing tools
✅ Go 1.23+ auto-installation
✅ Docker, Mise, Kurtosis, Just auto-installation
✅ Optimized installation order (considering dependencies)
✅ User confirmation before installation

## Devnet Management

### Check Devnet Status
```bash
# Check Devnet running status
kurtosis enclave inspect simple-devnet

# Check challenger status
docker ps | grep challenger
```

### Clean Up Running Devnet
```bash
# Clean up Kurtosis enclave
kurtosis enclave rm --force simple-devnet

# Clean up Docker containers (if any remain)
# docker stop $(docker ps -q) 2>/dev/null || true
# docker rm $(docker ps -aq) 2>/dev/null || true

# Kurtosis engine 정리 및 재시작
docker stop $(docker ps -q --filter ancestor=kurtosistech/engine)
docker rm $(docker ps -aq --filter ancestor=kurtosistech/engine)

# Clean up Docker volumes (optional)
docker volume prune -f
```

## Connection Information

Once the devnet is running, you can access:

- **L1 RPC**: http://localhost:53620
- **L2 RPC**: http://localhost:56781
- **Rollup RPC**: http://localhost:57029

## OP-Challenger Execution

### Basic Usage
```bash
# Step 3: Run Challenger (after completing Step 2 above)
./run-challenger-devnet.sh
```

### Management Commands
```bash
# Check status
docker ps | grep challenger

# Check logs
docker logs op-challenger

# Stop/Remove
docker stop op-challenger
docker rm op-challenger

# Run health check
./challenger-healthcheck.sh
```

### Important Notes

⚠️ **For development and testing purposes only**
- Mnemonics and keys are for testing, do not use in production
- Network settings are configured for local devnet

## 🔧 Troubleshooting

### Common Issues and Solutions

#### 1. Traefik Network Error
**Problem**: Deployment fails with Traefik network configuration error:
```
Error: failed to set Traefik network configuration: failed to create Docker client:
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

**Solution**: Use the automated fix script
```bash
cd /optimism/kurtosis-devnet

# Option 1: Automatic fix after deployment
just fix-traefik

# Option 2: Deploy with automatic fix
just devnet-with-fix simple.yaml

# Option 3: Manual restart (quick fix)
docker restart $(docker ps --filter "name=kurtosis-reverse-proxy" --format "{{.Names}}")
```

**Root Cause**: Traefik tries to connect to hardcoded network IDs that change between deployments.

#### 2. AnchorStateRegistry Cold Start Problem
**Problem**: Challenger logs show prestate validation failures with 0xdead:
```
Failed to validate prestate: output root absolute prestate does not match
Provider: 0x50c8... | Contract: 0xdead000000000000000000000000000000000000000000000000000000000000
```

**This is the AnchorStateRegistry "cold start" problem** - intentional design requiring manual intervention.

**Automated Solution**:
```bash
cd /optimism/kurtosis-devnet

# Option 1: Run fix script directly
just fix-anchor-state

# Option 2: Deploy with automatic fixes included
just devnet-with-fix simple.yaml
```

**Manual Solution** (if automated script fails):
```bash
# 1. Get L2 genesis root
L2_GENESIS_ROOT=$(cast block 0 --rpc-url http://op-el-2151908-node0-op-geth:8545 -f stateRoot)

# 2. Get contract addresses
DISPUTE_GAME_FACTORY=$(grep -o '"DisputeGameFactoryProxy": *"[^"]*"' /tmp/devnet-desc/env.json | cut -d'"' -f4)

# 3. Create first valid dispute game
cast send $DISPUTE_GAME_FACTORY "create(uint32,bytes32,bytes)" \
  0 $L2_GENESIS_ROOT 0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url http://127.0.0.1:58524 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Game will resolve automatically as DEFENDER_WINS (correct root), updating AnchorStateRegistry
```

**References**:
- [AnchorStateRegistry Fix Guide](./docs/anchor-state-fix.md) for detailed explanation
- [Game Types Guide](./docs/game-types.md) for CANNON vs PERMISSIONED differences

#### 3. Docker Resource Issues
**Problem**: Deployment fails due to insufficient resources

**Solution**: Increase Docker Desktop resources
- **Memory**: 6GB or more (default: 2GB)
- **CPUs**: 4 cores or more (default: 2)
- **Disk**: 20GB+ free space

#### 4. Port Conflicts
**Problem**: Services fail to start due to port conflicts

**Solution**:
```bash
# Check port usage
lsof -i :8545
lsof -i :9001

# Stop conflicting processes or use different ports in simple.yaml
```

#### 5. Kurtosis Engine Connection Issues
**Problem**: `kurtosis enclave inspect` fails

**Solution**:
```bash
# Restart Kurtosis engine
kurtosis engine restart

# Clean up stale containers
docker system prune -f
```

### Getting Help

If you encounter issues not covered here:

1. **Check service logs**:
   ```bash
   kurtosis service logs simple-devnet op-challenger-challenger-2151908
   ```

2. **Check deployment status**:
   ```bash
   kurtosis enclave inspect simple-devnet
   ```

3. **Complete environment reset**:
   ```bash
   AUTOFIX=nuke just simple-devnet
   ```

**📖 For more detailed troubleshooting, see the documentation in `./docs/`**


