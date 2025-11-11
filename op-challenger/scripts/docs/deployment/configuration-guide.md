# Simple.yaml Configuration Guide

This guide covers the essential configuration settings for running the OP Stack devnet with proper challenger setup.

## Overview

The `simple.yaml` file in `/optimism/kurtosis-devnet/` controls the deployment configuration for the entire devnet stack. This guide focuses on the critical settings for challenger operations and common deployment issues.

## Core Configuration Sections

### 1. Game Type Configuration

The game type determines which fault proof system is used:

```yaml
proposer_params:
  image: {{ localDockerImage "op-proposer" }}
  extra_params: []
  game_type: 0            # Set to 0 for CANNON, 1 for PERMISSIONED
  proposal_interval: 10m
```

**Supported Game Types:**
| Type | Name | Purpose | Challenger Config | Status |
|------|------|---------|-------------------|--------|
| **0** | CANNON | Complete fault proof | Auto uses `cannon` | ⚠️ needs testing |
| **1** | PERMISSIONED | Fast development/testing | Auto uses `permissioned` | ✅ **working** |
| **2** | ASTERISC | Asterisc VM | Auto uses `asterisc` | ⚠️ needs testing |

### 2. Challenger Prestate Configuration

Critical for preventing prestate mismatch errors:

```yaml
challengers:
  challenger:
    enabled: true
    image: {{ localDockerImage "op-challenger" }}
    participants: "*"
    cannon_prestates_url: {{ localPrestate.URL }}  # Base URL for prestate files
    cannon_trace_types: ["cannon"]
```

**Configuration Explanation:**
- `cannon_prestates_url`: Base URL where challenger will automatically find hash-based prestate files
- The challenger automatically downloads the correct prestate file based on the game contract's absolute prestate hash

### 3. Network Timeout Prevention

For Docker registry timeout issues, use these alternatives:

**Docker Management Solutions:**
```bash
# Restart Docker Desktop to refresh network connections
osascript -e 'quit app "Docker Desktop"' && sleep 5 && open -a "Docker Desktop"

# Clean Docker cache and retry
docker system prune -a -f
```

**Local Image Priority:**
The configuration already uses `{{ localDockerImage }}` templates which prioritize locally built images over remote registry pulls.

## Contract Deployment Overrides

Configure fault proof system parameters:

```yaml
op_contract_deployer_params:
  image: {{ localDockerImage "op-deployer" }}
  l1_artifacts_locator: {{ localContractArtifacts "l1" }}
  l2_artifacts_locator: {{ localContractArtifacts "l2" }}
  overrides:
    faultGameAbsolutePrestate: {{ localPrestate.Hashes.prestate_mt64 }}
    vmType: "CANNON"
```

**Key Overrides:**
- `faultGameAbsolutePrestate`: Must match the prestate used by challenger
- `vmType`: Should match the game type (CANNON, PERMISSIONED, etc.)

## Common Configuration Patterns

### Development Environment (Fastest)

```yaml
proposer_params:
  game_type: 1  # PERMISSIONED - faster testing

challengers:
  challenger:
    cannon_prestates_url: {{ localPrestate.URL }}
    cannon_trace_types: ["cannon"]
```

### Production-like Testing (CANNON)

```yaml
proposer_params:
  game_type: 0  # CANNON - full fault proofs

challengers:
  challenger:
    cannon_prestates_url: {{ localPrestate.URL }}
    cannon_trace_types: ["cannon"]
```

### Offline Development

For offline development, the configuration already uses local images via `{{ localDockerImage }}` templates. If you encounter network issues, restart Docker Desktop or clean the Docker cache as shown in the Network Timeout Prevention section.

## Template Variables

The configuration uses several template variables that are resolved at deployment time:

| Variable | Example Value | Purpose |
|----------|---------------|---------|
| `{{ localDockerImage "op-challenger" }}` | `op-challenger:simple-devnet` | Local Docker image tag |
| `{{ localPrestate.URL }}` | `http://fileserver/proofs/op-program/cannon` | Prestate download URL |
| `{{ localPrestate.Hashes.prestate_mt64 }}` | `0x03a1a13511...` | Specific prestate hash |
| `{{ localContractArtifacts "l1" }}` | `artifact://contracts-abc123...` | Contract artifact locator |

## Validation and Verification

After deploying with your configuration, verify the settings were applied:

```bash
# Download deployment descriptor
kurtosis files download simple-devnet devnet-descriptor-0 /tmp/devnet-desc

# Get RPC endpoint
L1_RPC=$(grep -o '"rpc":"http://[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f4)

# Verify game type was applied
OP_PORTAL=$(grep -o 'OptimismPortalProxy[^"]*":"[^"]*' /tmp/devnet-desc/env.json | cut -d'"' -f3)
cast call $OP_PORTAL "respectedGameType()(uint32)" --rpc-url $L1_RPC

# Check challenger parameters
docker logs $(docker ps | grep challenger | awk '{print $1}') | grep "cannon-prestate"
```

## Troubleshooting Configuration Issues

### YAML Syntax Errors

**Problem:** `mapping values are not allowed in this context`

**Solution:** Check indentation - YAML is indent-sensitive:
```yaml
# Wrong - mixed indentation
network_params:
  preset: minimal
disable_peer_verification: true
    additional_preloaded_contracts: |

# Correct - consistent indentation
network_params:
  preset: minimal
  additional_preloaded_contracts: |
disable_peer_verification: true
```

### Template Resolution Errors

**Problem:** Variables like `{{ localPrestate.URL }}` not resolved

**Solution:** Ensure you're running from the correct directory and have built prestates:
```bash
cd /optimism/kurtosis-devnet
./build-binaries-for-challenger.sh --force  # Rebuild prestates
just simple-devnet
```

### Challenger Startup Errors

**Problem:** Challenger fails to start or has prestate mismatches

**Solution:** Verify both prestate parameters are configured:
```bash
# Should see prestates URL parameter in logs:
docker logs $(docker ps | grep challenger | awk '{print $1}') | grep "cannon-prestates-url"
```

## Configuration Examples

### Minimal Working Configuration

```yaml
optimism_package:
  challengers:
    challenger:
      enabled: true
      image: {{ localDockerImage "op-challenger" }}
      participants: "*"
      cannon_prestates_url: {{ localPrestate.URL }}
      cannon_trace_types: ["cannon"]
  proposer_params:
    game_type: 0

ethereum_package:
  participants:
    - el_type: geth
      cl_type: teku
```

### Full Production Configuration

See the complete example in `/optimism/kurtosis-devnet/simple.yaml` for all available options.

## Related Documentation

- [README.md](../README.md) - Main setup guide
- [Deployment Verification Guide](../verification/deployment-verification-guide.md) - Post-deployment checks
- [Troubleshooting Guide](../operations/troubleshooting-guide.md) - Common issues and solutions