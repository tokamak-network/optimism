# Devnet Troubleshooting Guide

**Last Updated**: September 17, 2025
**Version**: 1.0
**Target**: Optimism Devnet Developers

## Common Issues and Solutions

### 1. Docker Registry Timeout Error

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

### 2. Traefik Network Error

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

### 3. AnchorStateRegistry Cold Start Problem

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
- [AnchorStateRegistry Fix Guide](../challenger/anchor-state-fix.md) for detailed explanation
- [Game Types Guide](../dispute-games/game-types.md) for CANNON vs PERMISSIONED differences
- [Fast Dispute Game Setup Guide](../dispute-games/fast-dispute-game-setup.md) for 20-minute game configuration
- [Auto-Resolve Script Guide](../challenger/auto-resolve-script-guide.md) for automated game resolution

### 4. Docker Resource Issues

**Problem**: Deployment fails due to insufficient resources

**Solution**: Increase Docker Desktop resources
- **Memory**: 6GB or more (default: 2GB)
- **CPUs**: 4 cores or more (default: 2)
- **Disk**: 100GB+ free space

### 5. Port Conflicts

**Problem**: Services fail to start due to port conflicts

**Solution**:
```bash
# Check port usage
lsof -i :8545
lsof -i :9001

# Stop conflicting processes or use different ports in simple.yaml
```

### 6. Kurtosis Engine Connection Issues

**Problem**: `kurtosis enclave inspect` fails

**Solution**:
```bash
# Restart Kurtosis engine
kurtosis engine restart

# Clean up stale containers
docker system prune -f
```

## Build and System Issues

### 7. System Requirements Check

**Problem**: Build failures or unexpected errors

**Solution**: Verify system requirements first
```bash
# Check Docker service
docker --version
docker ps

# Check Go version (1.23+ required)
go version

# Install/verify required tools
cd /optimism/op-challenger/scripts
./install-tools.sh

# Check build logs
cat /tmp/devnet-build.log
```

### 8. Binary Files Missing

**Problem**: Challenger cannot find required binaries
```
ERROR: Cannon binary not found: /path/to/cannon/bin/cannon
ERROR: op-program binary not found: /path/to/op-program/bin/op-program
```

**Solution**: Build required binaries
```bash
# Build cannon
cd $OPTIMISM_ROOT/cannon && make cannon

# Build op-program
cd $OPTIMISM_ROOT/op-program && make op-program

# Or use the automated build script
cd /optimism/op-challenger/scripts
./build-binaries-for-challenger.sh --force
```

### 9. Container Start Failures

**Problem**: OP-Challenger container fails to start

**Diagnosis steps**:
```bash
# 1. Check detailed logs
docker logs op-challenger

# 2. Check if container exists
docker ps -a | grep challenger

# 3. Try restart
docker restart op-challenger

# 4. Complete removal and restart
docker rm -f op-challenger
./run-challenger-devnet.sh
```

## Network and RPC Issues

### 10. RPC Connection Failures

**Problem**: Cannot connect to L1/L2 RPC endpoints

**Diagnosis**:
```bash
# Test L1 RPC connection
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:XXXX  # Use actual port from kurtosis enclave inspect

# Test L2 RPC connection
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:YYYY  # Use actual port from kurtosis enclave inspect

# Get current port information
kurtosis enclave inspect simple-devnet
```

### 11. Port Information Discovery

**Problem**: Need to find current RPC ports

**Solution**:
```bash
# Get all port mappings
kurtosis enclave inspect simple-devnet

# Extract specific RPC ports from environment file
jq -r '.l1.nodes[0].services.el.endpoints.rpc.port' /tmp/devnet-desc/env.json
jq -r '.l2.nodes[0].services.el.endpoints.rpc.port' /tmp/devnet-desc/env.json
```

## Data and Storage Issues

### 12. Disk Space Problems

**Problem**: Insufficient disk space causing build failures

**Solution**: Clean up Docker resources
```bash
# Remove unused Docker resources
docker system prune -af

# Remove unused volumes
docker volume prune -f

# Check available space
df -h
```

### 13. Data Reset and Cleanup

**Problem**: Need to start with fresh data

**Solution**: Complete data initialization
```bash
# Remove challenger container and data
docker rm -f op-challenger
docker volume rm challenger-data 2>/dev/null || true

# Clean up all Kurtosis resources
kurtosis clean -a

# Complete environment reset
rm -rf /tmp/devnet-desc
AUTOFIX=nuke just simple-devnet
```

## Performance and Resource Issues

### 14. Memory Issues

**Problem**: Container stops due to memory limits or OOM errors

**Diagnosis**:
```bash
# Check container resource usage
docker stats op-challenger

# Check system memory
free -h

# Check Docker memory limits
docker inspect op-challenger | grep -i memory

# Monitor specific process
top -p $(docker inspect --format '{{.State.Pid}}' op-challenger)
```

**Solution**: Increase Docker Desktop resource limits or system memory.

## Log Analysis and Monitoring

### 15. Effective Log Monitoring

**Real-time monitoring**:
```bash
# Follow challenger logs in real-time
docker logs -f op-challenger

# Monitor last 100 lines
docker logs --tail 100 op-challenger

# Filter for errors
docker logs op-challenger 2>&1 | grep -i error

# Filter for specific time period
docker logs --since="2024-01-01T00:00:00" op-challenger
```

**Log patterns to watch for**:

**Normal startup**:
```
INFO [12-01|10:00:00.000] Starting op-challenger
INFO [12-01|10:00:00.001] Connected to L1 RPC
INFO [12-01|10:00:00.002] Connected to L2 RPC
```

**Connection problems**:
```
ERROR [12-01|10:00:00.000] Failed to connect to L1 RPC
ERROR [12-01|10:00:00.001] dial tcp: connection refused
```

## Getting Help

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

5. **Collect diagnostic information**:
   ```bash
   # Save logs for troubleshooting
   docker logs op-challenger > challenger.log

   # System information
   docker version
   go version
   kurtosis version
   ```

**💡 Best Practice**: Always do a complete cleanup before redeploying if you encounter multiple failed processes or account funding issues.

---

*This guide provides comprehensive solutions to issues encountered during Optimism devnet deployment and operation.*