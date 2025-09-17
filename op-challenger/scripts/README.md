# Build Local Network for Challenger Test

## 🚀 Quick Installation

### Local Devnet Development Environment

#### Step 1: Install System Tools
```bash
cd op-challenger/scripts
./install-tools.sh
```

#### Step 2: Compile Contracts and Create Artifacts
```bash
cd /optimism/packages/contracts-bedrock
forge build --force

cd /optimism/op-challenger/scripts
./build-contract-artifacts.sh
./build-binaries-for-challenger.sh --force
```

##### Contract Build Options

The binary builder supports different modes:

```bash
# Build only if binaries don't exist (default)
./build-binaries-for-challenger.sh

# Force rebuild even if binaries exist (recommended after contract changes)
./build-binaries-for-challenger.sh --force

# Show help and options
./build-binaries-for-challenger.sh --help
```

**💡 Important**: Always use `--force` after modifying contracts to ensure cannon/prestate files are regenerated with your changes.

#### Step 3: Configure Devnet Settings

Edit `simple.yaml` to configure testing-optimized settings:

```bash
cd /optimism/kurtosis-devnet
vi simple.yaml  # or your preferred editor
```

**Required Configuration Checks and Edits:**

1. **L1 Account Funding** - Find and verify `ethereum_package` section:
   ```yaml
   ethereum_package:
     network_params:
       prefunded_accounts: '{"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": {"balance": "1000ETH"}}'
   ```
   **If missing**: Add this section to ensure test accounts have ETH for transactions.

2. **20-Minute Dispute Games** - Find and add `overrides` section:
   ```yaml
   overrides:
     deployer:
       faultGameMaxClockDuration: 1200
       faultGameClockExtension: 300
   ```
   **If missing**: Add this section to enable fast 20-minute dispute games instead of 3.5-day games.

3. **CANNON Game Type** - Find and verify `proposer_params` section:
   ```yaml
   proposer_params:
     game_type: 0
   ```
   **If missing or different**: Set `game_type: 0` to use CANNON dispute games.

**Verification**: Check that all three sections exist in your `simple.yaml` before proceeding to Step 4.

**📖 Complete Setup Guide**: [Fast Dispute Game Setup Guide](./docs/fast-dispute-game-setup.md) - Detailed configuration instructions and troubleshooting

**Supported Game Types:**
| Type | Name | Purpose | Status |
|------|------|---------|--------|
| **0** | CANNON | Complete fault proof | ✅ **recommended** |
| **1** | PERMISSIONED | Fast development/testing | ✅ working |
| **2** | ASTERISC | Asterisc VM | ⚠️ needs testing |

#### Step 4: Build Devnet Environment

**💡 Tips**: To avoid memory issues and speed up deployment, perform these tasks first and clean Docker cache after each:

```bash
# Pre-download consensys/teku:25.7.0 image
docker pull consensys/teku:25.7.0

# Clean unused cache only (safe)
docker builder prune
```

```bash
# For normal cleanup
LOG_LEVEL=debug AUTOFIX=true just simple-devnet

# For complete reset (use when code is changed and recompiled)
LOG_LEVEL=debug AUTOFIX=nuke just simple-devnet

# If Traefik network error occurs, run this after deployment:
cd /optimism/kurtosis-devnet && just fix-traefik
```

**💡 Pro Tips**: Use `just devnet-with-fix simple.yaml` in kurtosis-devnet directory to automatically handle common issues.

##### Autofix Mode

Autofix mode helps recover from failed devnet deployments by automatically cleaning up the environment:

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




## 📋 Deployment Verification

**🚀 Quick Post-Deployment Check**: [Post-Deployment Verification Guide](./docs/post-deployment-verification-guide-en.md) - Complete automated verification process with scripts

**What the verification guide includes:**
- ✅ Automated contract configuration verification
- ✅ Complete game status monitoring
- ✅ Auto-resolve dispute game testing
- ✅ Step-by-step troubleshooting

### Log Monitoring

#### L1 (Ethereum)
- **EL**: `kurtosis service logs simple-devnet el-1-geth-teku`
- **CL**: `kurtosis service logs simple-devnet cl-1-teku-geth`

#### L2 (OP Stack)
- **EL**: `kurtosis service logs simple-devnet op-el-2151908-node0-op-geth`
- **CL**: `kurtosis service logs simple-devnet op-cl-2151908-node0-op-node`
- **Batcher**: `kurtosis service logs simple-devnet op-batcher-2151908-op-kurtosis`
- **Proposer**: `kurtosis service logs simple-devnet op-proposer-2151908-op-kurtosis`

#### Other Services
- **Challenger**: `kurtosis service logs simple-devnet op-challenger-challenger-2151908`
- **Faucet**: `kurtosis service logs simple-devnet op-faucet`

### Post-Deployment Verification

After deploying your devnet, use the comprehensive automated verification process:

**🚀 Complete Verification**: [Post-Deployment Verification Guide](./docs/post-deployment-verification-guide-en.md)

**Quick automated commands:**
```bash
cd /optimism/op-challenger/scripts

# Verify all contract configurations
./verify-contract-settings.sh

# Check all dispute games status
./check-all-games.sh

# Auto-resolve specific dispute game
./auto-resolve-game.sh [GAME_ADDRESS]
```

The verification guide includes:
- ✅ Service status verification
- ✅ Contract configuration verification
- ✅ Account funding verification
- ✅ Dispute game creation and resolution testing
- ✅ Complete end-to-end workflow validation

## 🛠️ System Tools Auto Installation

### What the Auto-Installation Script Does

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

## 🏗️ Devnet Management

### Check Devnet Status
```bash
# Check devnet running status
kurtosis enclave inspect simple-devnet

# Check challenger status
docker ps | grep challenger
```

### Clean Up Running Devnet
```bash
# Clean up Kurtosis enclave
kurtosis enclave rm --force simple-devnet

# Clean up Docker containers (if any remain)
docker stop $(docker ps -q) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Clean up Kurtosis engine and restart
docker stop $(docker ps -q --filter ancestor=kurtosistech/engine)
docker rm $(docker ps -aq --filter ancestor=kurtosistech/engine)

# Clean up Docker volumes (optional)
docker volume prune -f
```

## 🔌 Connection Information

Once the devnet is running, you can access:

- **L1 RPC**: http://localhost:53620
- **L2 RPC**: http://localhost:56781
- **Rollup RPC**: http://localhost:57029

## 🚀 OP-Challenger Execution

### Basic Usage
```bash
# Run challenger (after completing previous steps)
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

### 🤖 Automated Dispute Game Resolution

For fast testing with 20-minute dispute games, use the auto-resolve script:

```bash
# Auto-resolve dispute games after their duration expires
./auto-resolve-game.sh 0x<GAME_ADDRESS>
```

**📖 Auto-Resolve Guide**: [Auto-Resolve Script Guide](./docs/auto-resolve-script-guide.md) - Complete guide for automated dispute game resolution

### Important Notes

⚠️ **For development and testing purposes only**
- Mnemonics and keys are for testing, do not use in production
- Network settings are configured for local devnet

## 🔧 Troubleshooting

### Common Issues and Solutions

#### 1. Docker Registry Timeout Error

**Problem**: Deployment fails with timeout errors when fetching images from `us-docker.pkg.dev`:
```
Get "https://us-docker.pkg.dev/v2/token?scope=...": net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)
```

**Solution**: Use Docker management commands
```bash
# Restart Docker Desktop to refresh network connections
osascript -e 'quit app "Docker Desktop"' && sleep 5 && open -a "Docker Desktop"

# Or clean Docker cache and retry
docker system prune -a -f
```

**Note**: The configuration already prioritizes local images via `{{ localDockerImage }}` templates.

#### 2. Traefik Network Error

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

#### 3. AnchorStateRegistry Cold Start Problem

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
# 1. Get environment variables from devnet
source <(cat /tmp/devnet-desc/env.json | jq -r 'to_entries | map("export " + .key + "=" + (.value | @sh)) | .[]')

# 2. Get L2 genesis root
L2_GENESIS_ROOT=$(cast block 0 --rpc-url $L2_RPC -f stateRoot)

# 3. Create first valid dispute game
cast send $DGF "create(uint32,bytes32,bytes)" \
  0 $L2_GENESIS_ROOT 0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url $L1_RPC \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Game will resolve automatically as DEFENDER_WINS (correct root), updating AnchorStateRegistry
```

**References**:
- [AnchorStateRegistry Fix Guide](./docs/anchor-state-fix.md) for detailed explanation
- [Game Types Guide](./docs/game-types.md) for CANNON vs PERMISSIONED differences
- [Fast Dispute Game Setup Guide](./docs/fast-dispute-game-setup.md) for 20-minute game configuration
- [Auto-Resolve Script Guide](./docs/auto-resolve-script-guide.md) for automated game resolution

#### 4. Docker Resource Issues

**Problem**: Deployment fails due to insufficient resources

**Solution**: Increase Docker Desktop resources
- **Memory**: 6GB or more (default: 2GB)
- **CPUs**: 4 cores or more (default: 2)
- **Disk**: 100GB+ free space

#### 5. Port Conflicts

**Problem**: Services fail to start due to port conflicts

**Solution**:
```bash
# Check port usage
lsof -i :8545
lsof -i :9001

# Stop conflicting processes or use different ports in simple.yaml
```

#### 6. Kurtosis Engine Connection Issues

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
   # Stop all background processes first
   pkill -f "just.*devnet" || true
   pkill -f "AUTOFIX" || true

   # Clean up devnet
   kurtosis enclave rm --force simple-devnet

   # Fresh start
   AUTOFIX=true just simple-devnet
   ```

4. **Check account funding after deployment**:
   ```bash
   # Verify accounts have ETH before proceeding
   L1_RPC="http://127.0.0.1:XXXX"  # Use actual port from inspect
   cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url $L1_RPC
   ```

**💡 Best Practice**: Always do a complete cleanup before redeploying if you encounter multiple failed processes or account funding issues.

**📖 For more detailed troubleshooting, see the documentation in `./docs/`**

---

## 🔍 Post-Deployment Testing

After successful deployment, use the comprehensive verification process:

**🚀 Automated Verification**: [Post-Deployment Verification Guide](./docs/post-deployment-verification-guide-en.md)

**Quick Commands:**
```bash
cd /optimism/op-challenger/scripts

# 1. Verify contract configurations
./verify-contract-settings.sh

# 2. Check all dispute games status
./check-all-games.sh

# 3. Test auto-resolve functionality
./auto-resolve-game.sh [GAME_ADDRESS]
```

**What gets verified:**
- ✅ Contract configuration (20-minute dispute games, CANNON type)
- ✅ Account funding status
- ✅ Game creation and resolution process
- ✅ Complete end-to-end dispute game lifecycle


