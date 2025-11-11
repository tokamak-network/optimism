#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# Service Health Check Script
#
# Checks the status of all deployed devnet services
#
# Usage: ./health-check.sh
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Health check counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

##############################################################################
# RPC health check function
##############################################################################

check_rpc() {
    local service_name="$1"
    local rpc_url="$2"
    local timeout="${3:-5}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if curl -s -m "$timeout" -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$rpc_url" > /dev/null 2>&1; then

        # Get block number
        block_hex=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "$rpc_url" | jq -r '.result')

        if [ "$block_hex" != "null" ] && [ -n "$block_hex" ]; then
            block_num=$((16#${block_hex#0x}))
            log_success "$service_name - RPC responding (block: $block_num)"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            return 0
        else
            log_warn "$service_name - RPC responding but no block number"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            return 1
        fi
    else
        log_error "$service_name - No RPC response"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# op-node specific health check
check_opnode_rpc() {
    local service_name="$1"
    local rpc_url="$2"
    local timeout="${3:-5}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    # Check if RPC is responding using optimism_syncStatus
    sync_status=$(curl -s -m "$timeout" -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' \
        "$rpc_url" 2>/dev/null)

    if [ -n "$sync_status" ]; then
        # Get unsafe L2 block number
        unsafe_l2_num=$(echo "$sync_status" | jq -r '.result.unsafe_l2.number // 0' 2>/dev/null)

        if [ "$unsafe_l2_num" != "null" ] && [ -n "$unsafe_l2_num" ] && [ "$unsafe_l2_num" != "0" ]; then
            log_success "$service_name - RPC responding (unsafe L2: $unsafe_l2_num)"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            return 0
        else
            log_warn "$service_name - RPC responding but L2 not synced yet"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            return 1
        fi
    else
        log_error "$service_name - No RPC response"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

##############################################################################
# Check Kurtosis enclave status
##############################################################################

check_kurtosis_enclave() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if command -v kurtosis >/dev/null 2>&1; then
        if kurtosis enclave ls 2>/dev/null | grep -q "simple-devnet"; then
            log_success "Kurtosis devnet enclave is running"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            return 0
        else
            log_error "Kurtosis devnet enclave not found"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            return 1
        fi
    else
        log_warn "Kurtosis CLI not installed"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

##############################################################################
# Get port information from Kurtosis
##############################################################################

get_port_info() {
    if ! command -v kurtosis >/dev/null 2>&1; then
        log_warn "Kurtosis CLI not available, using default ports"
        L1_RPC_PORT="8545"
        L2_RPC_PORT="9545"
        ROLLUP_RPC_PORT="7545"
        return
    fi

    local enclave_inspect=$(kurtosis enclave inspect simple-devnet 2>/dev/null || echo "")

    if [ -z "$enclave_inspect" ]; then
        log_warn "Cannot inspect devnet enclave, using default ports"
        L1_RPC_PORT="8545"
        L2_RPC_PORT="9545"
        ROLLUP_RPC_PORT="7545"
        return
    fi

    # Extract L1 RPC port (first 8545)
    L1_RPC_PORT=$(echo "$enclave_inspect" | grep "rpc: 8545/tcp" | head -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ' || echo "8545")

    # Extract L2 RPC port (second 8545)
    L2_RPC_PORT=$(echo "$enclave_inspect" | grep "rpc: 8545/tcp" | tail -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ' || echo "9545")

    # Extract Rollup RPC port (8547)
    ROLLUP_RPC_PORT=$(echo "$enclave_inspect" | grep "rpc: 8547/tcp" | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ' || echo "7545")

    log_info "Detected ports - L1:$L1_RPC_PORT L2:$L2_RPC_PORT Rollup:$ROLLUP_RPC_PORT"
}

##############################################################################
# Synchronization status check
##############################################################################

check_sync_status() {
    local service_name="$1"
    local rpc_url="$2"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    # Call eth_syncing
    sync_status=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        "$rpc_url" | jq -r '.result')

    if [ "$sync_status" = "false" ]; then
        log_success "$service_name - Synchronized"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    elif [ "$sync_status" = "null" ]; then
        log_warn "$service_name - Cannot check sync status"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    else
        # Syncing
        current=$(echo "$sync_status" | jq -r '.currentBlock // 0' 2>/dev/null || echo 0)
        highest=$(echo "$sync_status" | jq -r '.highestBlock // 0' 2>/dev/null || echo 0)

        if [ "$current" != "0" ] && [ "$highest" != "0" ]; then
            log_warn "$service_name - Syncing ($current / $highest)"
        else
            log_warn "$service_name - Syncing"
        fi
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

##############################################################################
# Main health check
##############################################################################

echo ""
log_info "=========================================="
log_info "Devnet Health Check Started"
log_info "=========================================="
echo ""

# 1. Check Kurtosis enclave
log_info "━━━ Kurtosis Enclave Status ━━━"
check_kurtosis_enclave || true
echo ""

# 2. Get port information
log_info "━━━ Service Port Information ━━━"
get_port_info
echo ""

# 3. L1 RPC check
log_info "━━━ L1 Ethereum RPC ━━━"
check_rpc "L1 Geth" "http://localhost:$L1_RPC_PORT" 5 || true
check_sync_status "L1 Geth" "http://localhost:$L1_RPC_PORT" || true
echo ""

# 4. L2 stack check
log_info "━━━ L2 OP Stack ━━━"
check_rpc "L2 op-geth" "http://localhost:$L2_RPC_PORT" 5 || true
check_sync_status "L2 op-geth" "http://localhost:$L2_RPC_PORT" || true
check_opnode_rpc "op-node" "http://localhost:$ROLLUP_RPC_PORT" 5 || true
echo ""

# 5. Challenger check (if running)
log_info "━━━ Challenger Status ━━━"
if docker ps --format '{{.Names}}' | grep -q "op-challenger"; then
    challenger_container=$(docker ps --format '{{.Names}}' | grep "op-challenger" | head -1)
    log_info "Found challenger container: $challenger_container"

    # Check for errors in recent logs
    error_count=$(docker logs --tail=50 "$challenger_container" 2>&1 | grep -i "error" | wc -l | tr -d ' \n' || echo "0")
    error_count=${error_count:-0}

    if [ "$error_count" -lt 5 ]; then
        log_success "Challenger - Operating normally (error logs: $error_count)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_warn "Challenger - Multiple errors found ($error_count)"
        log_info "Detailed logs: docker logs $challenger_container"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
else
    log_warn "Challenger container not found (may be disabled)"
fi
echo ""

##############################################################################
# Collect additional information
##############################################################################

log_info "━━━ Block Height Information ━━━"

# L1 and L2 block heights
l1_block=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "http://localhost:$L1_RPC_PORT" 2>/dev/null | jq -r '.result' || echo "0x0")

l2_block=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "http://localhost:$L2_RPC_PORT" 2>/dev/null | jq -r '.result' || echo "0x0")

if [ "$l1_block" != "0x0" ]; then
    l1_num=$((16#${l1_block#0x}))
    echo "L1 Block Height: $l1_num"
fi

if [ "$l2_block" != "0x0" ]; then
    l2_num=$((16#${l2_block#0x}))
    echo "L2 Block Height: $l2_num"
fi

echo ""

##############################################################################
# GameType Configuration Check
##############################################################################

log_info "━━━ GameType Configuration ━━━"

# Load addresses from Kurtosis files
ADDRESSES_FILE="${SCRIPT_DIR}/../../kurtosis-devnet/.l1-artifacts/.deploy-config"
if [ -f "$ADDRESSES_FILE" ]; then
    # Try to extract DisputeGameFactory address
    DGF_ADDRESS=$(grep -o "DisputeGameFactoryProxy.*0x[a-fA-F0-9]*" "$ADDRESSES_FILE" 2>/dev/null | awk '{print $NF}' | head -1 || echo "")

    if [ -n "$DGF_ADDRESS" ] && [ "$DGF_ADDRESS" != "null" ]; then
        log_info "DisputeGameFactory: $DGF_ADDRESS"

        # Check GameType 0 (CANNON)
        GT0_IMPL=$(cast call --rpc-url "http://localhost:$L1_RPC_PORT" "$DGF_ADDRESS" "gameImpls(uint32)(address)" 0 2>/dev/null || echo "")
        if [ -n "$GT0_IMPL" ] && [ "$GT0_IMPL" != "0x0000000000000000000000000000000000000000" ]; then
            log_success "GameType 0 (CANNON) - Deployed: $GT0_IMPL"
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        else
            log_warn "GameType 0 (CANNON) - Not deployed"
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi

        # Check GameType 1 (PERMISSIONED_CANNON)
        GT1_IMPL=$(cast call --rpc-url "http://localhost:$L1_RPC_PORT" "$DGF_ADDRESS" "gameImpls(uint32)(address)" 1 2>/dev/null || echo "")
        if [ -n "$GT1_IMPL" ] && [ "$GT1_IMPL" != "0x0000000000000000000000000000000000000000" ]; then
            log_success "GameType 1 (PERMISSIONED_CANNON) - Deployed: $GT1_IMPL"
        else
            log_info "GameType 1 (PERMISSIONED_CANNON) - Not deployed (optional)"
        fi
    else
        log_warn "DisputeGameFactory address not found"
    fi
else
    log_warn "Deploy config not found: $ADDRESSES_FILE"
fi

echo ""

##############################################################################
# Result summary
##############################################################################

echo ""
log_info "=========================================="
log_info "Health Check Completed"
log_info "=========================================="
echo ""

echo "Total Checks: $TOTAL_CHECKS"
echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
    log_success "All services are operating normally!"
    exit 0
elif [ $PASSED_CHECKS -gt $FAILED_CHECKS ]; then
    log_warn "Some services have issues. Check the logs."
    log_info "View logs: kurtosis service logs simple-devnet [service-name]"
    exit 1
else
    log_error "Multiple services have encountered problems!"
    log_info "All services: kurtosis enclave inspect simple-devnet"
    log_info "Specific service: kurtosis service logs simple-devnet [service-name]"
    exit 2
fi
