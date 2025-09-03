# Phase 1 Challenger Network

Simple, step-by-step guide to set up and run the OP-Challenger for dispute game monitoring.

## 🚀 Quick Start

### 1. Install Dependencies
```bash
cd /optimism/op-challenger/scripts
./install-tools.sh
```
This installs Docker, Go, Kurtosis, and all required tools automatically.

### 2. Build Contracts & Binaries
```bash
cd /optimism/packages/contracts-bedrock
forge build --force

cd /optimism/op-challenger/scripts
./build-contract-artifacts.sh
./build-binaries-for-challenger.sh --force
```

### 3. Deploy Devnet
```bash
cd /optimism/kurtosis-devnet

# Or normal deployment
AUTOFIX=true just simple-devnet

# automatic issue resolution
just devnet-with-fix simple.yaml

# Full reset (recommended when changing code)
AUTOFIX=nuke just simple-devnet
```

### 4. Start Challenger
```bash
cd /optimism/op-challenger/scripts
./run-challenger-devnet.sh
```

**💡 Note**: The challenger runs separately from the devnet. When you start the devnet above, it automatically runs an internal challenger service. This step is for running an additional external challenger if needed.

### 5. Verify Everything Works
```bash
# Monitor dispute games
./monitor-game-creation.sh monitor
```

**✅ Done!** Your challenger should now be monitoring dispute games created every 10 minutes.

---

## 📖 Detailed Guides

| Guide | Purpose | When to Use |
|-------|---------|-------------|
| **[📋 Installation Guide](./docs/installation-guide.md)** | Step-by-step setup with verification | First-time setup or detailed walkthrough |
| **[✅ System Verification](./docs/system-verification.md)** | Health checks and monitoring | After setup or when troubleshooting |
| **[🎮 Dispute Game Monitoring](./docs/dispute-game-monitoring.md)** | Game creation and challenger monitoring | Daily operations and debugging |
| **[🔧 Troubleshooting Guide](./docs/troubleshooting-guide.md)** | Problem diagnosis and solutions | When things go wrong |

---

## 🏃‍♂️ Quick Commands

### Check Status
```bash
# Service status
kurtosis enclave inspect simple-devnet

# Game monitoring
./monitor-game-creation.sh recent 10
```

### Monitor Logs
```bash
# Proposer (creates games every 10 minutes)
kurtosis service logs simple-devnet op-proposer-2151908-op-kurtosis --follow

# Challenger
docker logs op-challenger --follow

# All game creation events
./monitor-game-creation.sh monitor
```

### Troubleshooting
```bash
# Complete reset
AUTOFIX=nuke just simple-devnet

# Emergency recovery
docker system prune -f && kurtosis engine restart
```

---

## 🎯 What This System Does

### The Flow
1. **Proposer** creates dispute games every 10 minutes
2. **Challenger** monitors and validates each game
3. **You** can watch the process in real-time

### Key Components
- **DisputeGameFactory**: Creates new dispute games
- **FaultDisputeGame**: Individual games with claims
- **AnchorStateRegistry**: Manages game state anchoring
- **OP-Challenger**: Monitors and validates games

### Expected Behavior
- ✅ New dispute game every 10 minutes
- ✅ Challenger registers to each game
- ✅ Prestate validation (may initially fail due to cold start)
- ✅ Continuous monitoring without manual intervention

---

## 🚨 Common Issues

| Problem | Quick Fix | Detailed Fix |
|---------|-----------|--------------|
| **Devnet won't start** | `AUTOFIX=nuke just simple-devnet` | [Troubleshooting Guide](./docs/troubleshooting-guide.md) |
| **No games created** | Check proposer logs | [Game Monitoring Guide](./docs/dispute-game-monitoring.md) |
| **Challenger errors** | `docker logs op-challenger` | [System Verification](./docs/system-verification.md) |
| **Prestate validation fails** | Expected for new devnets | [Installation Guide](./docs/installation-guide.md) |

---

## 📊 Monitoring Dashboard

### Real-time Monitoring
```bash
# Start comprehensive monitoring
./monitor-game-creation.sh monitor
```

### Quick Status Check
```bash
# Get current system status
echo "=== Quick Status ==="
echo "Services: $(kurtosis enclave inspect simple-devnet | grep RUNNING | wc -l)/10"
echo "Games: $(cast call $DGF_ADDRESS 'gameCount()' --rpc-url $L1_RPC)"
echo "Challenger: $(docker ps | grep challenger | wc -l) container(s)"
```

---

## 🔗 Configuration

### Game Types
Edit `simple.yaml` to change game type:

```yaml
proposer_params:
  game_type: 0  # 0=CANNON, 1=PERMISSIONED, 2=ASTERISC
  proposal_interval: 10m  # Game creation frequency
```

### Challenger Settings
Built-in challenger can be enabled/disabled in `simple.yaml`:

```yaml
challengers:
  challenger:
    enabled: true  # Enable/disable built-in challenger
    participants: "*"  # Monitor all participants
```

---

## 🛠️ Advanced Usage

### Custom Scripts
All monitoring scripts are located in this directory and can be customized:
- `monitor-game-creation.sh` - Game creation monitoring
- `filter-game-logs.sh` - Quick game status
- `system-health-check.sh` - Comprehensive health check

### Integration
- **Grafana**: Metrics available at `http://localhost:3000`
- **Prometheus**: Metrics endpoint at `http://localhost:9090`
- **RPC Endpoints**: Available in `/tmp/devnet-desc/env.json`

### Development
- Modify contracts in `/optimism/packages/contracts-bedrock`
- Always rebuild with `--force` flag after changes
- Use `AUTOFIX=nuke` for clean deployment after contract changes

---

## 📞 Support

### Self-Help Resources
1. **[Installation Guide](./docs/installation-guide.md)** - Detailed setup
2. **[System Verification](./docs/system-verification.md)** - Health checks
3. **[Troubleshooting Guide](./docs/troubleshooting-guide.md)** - Problem solving

### Getting Help
Before asking for help:
1. Run `./system-health-check.sh`
2. Check the troubleshooting guide
3. Collect logs with `./collect-logs.sh` (if script exists)

### Emergency Recovery
```bash
# Nuclear option - start completely fresh
cd /optimism/kurtosis-devnet
AUTOFIX=nuke just simple-devnet
```

---

**🎉 Happy Challenging!**