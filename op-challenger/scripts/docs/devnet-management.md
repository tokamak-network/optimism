# Devnet Management Guide

**Last Updated**: September 17, 2025
**Version**: 1.0
**Target**: Optimism Devnet Developers

## Overview

This guide covers essential devnet management operations including status monitoring, cleanup procedures, and log monitoring for all services.

## Check Devnet Status

### Basic Status Check
```bash
# Check overall devnet status
kurtosis enclave inspect simple-devnet

# Check if all services are running
kurtosis enclave inspect simple-devnet | grep -A 30 "User Services"

# Watch status updates in real-time
watch -n 1 "kurtosis enclave inspect simple-devnet | grep -A 30 'User Services'"
```

### Service-Specific Status
```bash
# Check specific service details
kurtosis service inspect simple-devnet op-challenger-challenger-2151908
kurtosis service inspect simple-devnet el-1-geth-teku
kurtosis service inspect simple-devnet op-deployer-apply

# Find challenger service name (may vary)
kurtosis enclave inspect simple-devnet | grep challenger

# Check all OP Stack services
kurtosis enclave inspect simple-devnet | grep -E "(challenger|batcher|proposer|op-node|op-geth)"
```

## Log Monitoring

### L1 (Ethereum) Services
```bash
# L1 Execution Layer (Geth)
kurtosis service logs simple-devnet el-1-geth-teku --follow

# L1 Consensus Layer (Teku)
kurtosis service logs simple-devnet cl-1-teku-geth --follow

# Monitor L1 block creation
kurtosis service logs simple-devnet el-1-geth-teku --follow | grep "Imported new potential chain segment"
```

### L2 (OP Stack) Services
```bash
# L2 Execution Layer (op-geth)
kurtosis service logs simple-devnet op-el-*-node0-op-geth --follow

# L2 Consensus Layer (op-node)
kurtosis service logs simple-devnet op-cl-*-node0-op-node --follow

# OP Batcher
kurtosis service logs simple-devnet op-batcher-*-op-kurtosis --follow

# OP Proposer
kurtosis service logs simple-devnet op-proposer-*-op-kurtosis --follow
```

### Challenger Services
```bash
# OP Challenger (main service)
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow

# Filter for errors only
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep "lvl=error"

# Filter for warnings and errors
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep -E "(lvl=warn|lvl=error)"

# Monitor last 100 lines
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --num-log-lines=100

# Real-time with limited history
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow=true --num-log-lines=50
```

### Other Services
```bash
# OP Faucet
kurtosis service logs simple-devnet op-faucet --follow

# Contract Deployer (during deployment)
kurtosis service logs simple-devnet op-deployer-apply --follow

# All services combined
kurtosis service logs simple-devnet --follow
```

### Log Analysis Patterns

**Normal challenger operation**:
```
t=2025-08-31T13:56:35+0000 lvl=info msg="challenger game service start completed"
t=2025-08-31T13:57:35+0000 lvl=info msg="Game info" game=0x... claims=1 status="In Progress"
```

**Normal synchronization warnings** (expected):
```
t=2025-08-31T13:57:24+0000 lvl=warn msg="Local node not sufficiently up to date"
```

**Block creation monitoring**:
```bash
# L1 block creation
kurtosis service logs simple-devnet el-1-geth-teku --follow | grep "Chain head was updated"

# L2 block creation
kurtosis service logs simple-devnet op-el-*-node0-op-geth --follow | grep "Imported new potential chain segment"
```

## Clean Up Operations

### Standard Cleanup
```bash
# Remove devnet enclave
kurtosis enclave rm --force simple-devnet

# Clean up any remaining Docker containers
docker stop $(docker ps -q) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Clean up Kurtosis engine
docker stop $(docker ps -q --filter ancestor=kurtosistech/engine) 2>/dev/null || true
docker rm $(docker ps -aq --filter ancestor=kurtosistech/engine) 2>/dev/null || true
```

### Deep Cleanup
```bash
# Complete Kurtosis cleanup
kurtosis clean -a

# Remove Docker volumes (optional)
docker volume prune -f

# Remove Docker networks (optional)
docker network prune -f

# Clean up environment files
rm -rf /tmp/devnet-desc

# Remove all Docker resources (use with caution)
docker system prune -af
```

### Selective Cleanup
```bash
# Remove only challenger-related containers
docker ps -a | grep challenger | awk '{print $1}' | xargs docker rm -f

# Remove specific service
kurtosis service rm simple-devnet op-challenger-challenger-2151908

# Stop specific service (for restart)
kurtosis service stop simple-devnet op-challenger-challenger-2151908
```

## Advanced Log Management

### Save Logs to Files
```bash
# Save logs while viewing
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow | tee challenger.log

# Save specific time period
kurtosis service logs simple-devnet el-1-geth-teku --since="2024-01-01T00:00:00" > l1-geth.log

# Save last N lines
kurtosis service logs simple-devnet op-deployer-apply --num-log-lines=1000 > deployment.log
```

### Multi-Service Monitoring
```bash
# Monitor multiple services in parallel (use multiple terminals)
kurtosis service logs simple-devnet el-1-geth-teku --follow &
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow &
kurtosis service logs simple-devnet op-deployer-apply --follow &

# Or use tmux/screen for session management
tmux new-session -d -s devnet-logs
tmux send-keys -t devnet-logs:0 'kurtosis service logs simple-devnet el-1-geth-teku --follow' C-m
tmux split-window -t devnet-logs:0
tmux send-keys -t devnet-logs:0.1 'kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow' C-m
```

### Log Filtering and Analysis
```bash
# Filter by log level
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep "lvl=info"
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep "lvl=error"

# Search for specific events
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep "Game info"
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep "dispute"

# Count log entries
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep "lvl=error" | wc -l

# Time-based filtering
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep "$(date +%Y-%m-%d)"
```

## Resource Monitoring

### Container Resource Usage
```bash
# Monitor resource usage of all containers
docker stats

# Monitor specific service resource usage
docker stats $(docker ps --format "table {{.Names}}" | grep challenger)

# Check memory usage
docker exec $(docker ps -q --filter name=challenger) cat /proc/meminfo | head -5

# Check disk usage in containers
docker exec $(docker ps -q --filter name=challenger) df -h
```

### System Resource Monitoring
```bash
# Overall system resources
htop

# Network connections
netstat -tulpn | grep docker

# Port usage
lsof -i :8545
lsof -i :9001
```

## Metrics and Monitoring

### Challenger Metrics
```bash
# Access challenger metrics endpoint
L1_RPC_PORT=$(jq -r '.l1.nodes[0].services.el.endpoints.rpc.port' /tmp/devnet-desc/env.json)
curl http://127.0.0.1:${L1_RPC_PORT}/metrics

# Check if metrics endpoint is available
curl -f http://127.0.0.1:56838/metrics || echo "Metrics not available"
```

### Service Health Checks
```bash
# Check RPC endpoints
L1_RPC_PORT=$(jq -r '.l1.nodes[0].services.el.endpoints.rpc.port' /tmp/devnet-desc/env.json)
L2_RPC_PORT=$(jq -r '.l2.nodes[0].services.el.endpoints.rpc.port' /tmp/devnet-desc/env.json)

# Test L1 RPC
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:${L1_RPC_PORT}

# Test L2 RPC
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:${L2_RPC_PORT}
```

## Related Documentation

- **[Log Monitoring Guide](./monitoring-deployment-logs.md)** - Detailed deployment log monitoring
- **[Troubleshooting Guide](./devnet-troubleshooting.md)** - Common issues and solutions
- **[Post-Deployment Verification](./post-deployment-verification-guide-en.md)** - Automated verification process

## Quick Reference Commands

```bash
# Essential monitoring commands
kurtosis enclave inspect simple-devnet                                    # Overall status
kurtosis service logs simple-devnet op-challenger-challenger-2151908 -f  # Challenger logs
kurtosis service logs simple-devnet el-1-geth-teku -f                    # L1 logs
kurtosis service logs simple-devnet op-el-*-node0-op-geth -f             # L2 logs

# Essential cleanup commands
kurtosis enclave rm --force simple-devnet                                # Remove devnet
kurtosis clean -a                                                         # Clean all Kurtosis resources
docker system prune -f                                                   # Clean Docker resources

# Essential health checks
curl http://localhost:$(jq -r '.l1.nodes[0].services.el.endpoints.rpc.port' /tmp/devnet-desc/env.json) # L1 RPC
curl http://localhost:$(jq -r '.l2.nodes[0].services.el.endpoints.rpc.port' /tmp/devnet-desc/env.json) # L2 RPC
```

---

*This guide provides comprehensive devnet management operations for Optimism development and testing.*