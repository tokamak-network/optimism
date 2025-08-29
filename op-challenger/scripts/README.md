# Phase 1 P2P Challenger Network

## 🚀 Quick Installation (Recommended)

### Local Devnet Development Environment

```bash
# Step 1: Install system tools
cd op-challenger/scripts
./install-tools.sh

# Step 2: Build Devnet Environment
./build-devnet.sh

# Step 3: Run Challenger
./run-challenger-devnet.sh
```

## ⏱️ Expected Build Times (Step 2)

### Docker Image Build (~3-7 minutes)
- **First time**: 5-7 minutes (no cache)
- **Subsequent builds**: 2-3 minutes (with cache)
- **Components**: op-node, op-batcher, op-proposer, op-faucet, op-challenger, op-deployer

### Devnet Deployment (~5-15 minutes)
The deployment process consists of 6 main steps:

| Step | Component | Expected Time | Description |
|------|-----------|---------------|-------------|
| 1/6 | Configuration | ~30 seconds | Creating devnet configuration files |
| 2/6 | Docker Images | ~2-3 minutes | Preparing container infrastructure |
| 3/6 | L1 + Contracts | ~5-8 minutes | **Longest step**: L1 chain startup + contract deployments |
| 4/6 | Service Verification | ~2-3 minutes | Checking all services are running |
| 5/6 | RPC Testing | ~1 minute | Testing L1/L2 RPC endpoints |
| 6/6 | Final Setup | ~30 seconds | Completing devnet setup |

**⚠️ Note**: Step 3/6 (L1 + Contracts) takes the longest time as it involves:
- Starting the L1 Ethereum chain
- Deploying all L2 smart contracts
- Initializing cross-chain bridges
- Setting up validator networks

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
docker stop $(docker ps -q) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Clean up Docker volumes (optional)
docker volume prune -f
```

## Connection Information

Once the devnet is running, you can access:

- **L1 RPC**: http://localhost:53620
- **L2 RPC**: http://localhost:56781
- **Rollup RPC**: http://localhost:57029

## Troubleshooting

If you encounter build errors, check:
1. Docker service is running
2. Go version is 1.23+
3. All required tools are installed via `./install-tools.sh`
4. Check build logs: `cat /tmp/devnet-build.log`




