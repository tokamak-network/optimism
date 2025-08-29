#!/bin/bash

# Local Devnet Challenger Execution Script
# For development and testing purposes only

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script Information
echo "=========================================="
echo "Local Devnet Challenger Execution"
echo "For Development and Testing Only"
echo "=========================================="
echo

# 기본 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTIMISM_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

# Check Devnet Status
check_devnet_status() {
    log_info "Checking Devnet status..."

    if ! kurtosis enclave ls | grep -q "simple-devnet"; then
        log_error "Devnet is not running."
        log_info "Please start Devnet first:"
        log_info "  ./build-devnet.sh"
        exit 1
    fi

    log_success "Devnet is running"
}

# Check op-challenger Docker Image
check_challenger_image() {
    log_info "Checking op-challenger Docker image..."

    if ! docker images | grep -q "op-challenger.*devnet"; then
        log_error "op-challenger Docker image not found."
        log_info "Please build Docker image first:"
        log_info "  ./build-devnet.sh"
        exit 1
    fi

    log_success "op-challenger Docker image is ready"
}

# Check Required Binary Files
check_required_binaries() {
    log_info "Checking required binary files..."

    # Check Cannon binary
    if [ ! -f "$OPTIMISM_ROOT/cannon/bin/cannon" ]; then
        log_error "Cannon binary not found: $OPTIMISM_ROOT/cannon/bin/cannon"
        log_info "Please build Cannon:"
        log_info "  cd $OPTIMISM_ROOT/cannon && make cannon"
        exit 1
    fi

    # Check op-program binary
    if [ ! -f "$OPTIMISM_ROOT/op-program/bin/op-program" ]; then
        log_error "op-program binary not found: $OPTIMISM_ROOT/op-program/bin/op-program"
        log_info "Please build op-program:"
        log_info "  cd $OPTIMISM_ROOT/op-program && make op-program"
        exit 1
    fi

    # Check prestate file
    if [ ! -f "$OPTIMISM_ROOT/op-program/bin/prestate-mt64Next.bin.gz" ]; then
        log_error "prestate file not found: $OPTIMISM_ROOT/op-program/bin/prestate-mt64Next.bin.gz"
        log_info "Please build op-program (including prestate files):"
        log_info "  cd $OPTIMISM_ROOT/op-program && make op-program"
        exit 1
    fi

    log_success "Required binary files are ready"
}

# Get Devnet Port Information
get_devnet_ports() {
    log_info "Getting Devnet port information..."

    # Extract port information from kurtosis enclave inspect
    local enclave_info=$(kurtosis enclave inspect simple-devnet 2>/dev/null)

    # L1 RPC port (el-1-geth-lighthouse)
    L1_RPC_PORT=$(echo "$enclave_info" | grep "rpc: 8545/tcp" | head -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ')

    # L2 RPC port (op-el-2151908-node0-op-geth)
    L2_RPC_PORT=$(echo "$enclave_info" | grep "rpc: 8545/tcp" | tail -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ')

    # Rollup RPC port (op-cl-2151908-node0-op-node)
    ROLLUP_RPC_PORT=$(echo "$enclave_info" | grep "rpc: 8547/tcp" | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ')

    # L1 Beacon port (cl-1-lighthouse-geth)
    L1_BEACON_PORT=$(echo "$enclave_info" | grep "http: 4000/tcp" | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ')

    # Set default values
    L1_RPC_PORT="${L1_RPC_PORT:-53620}"
    L2_RPC_PORT="${L2_RPC_PORT:-56781}"
    ROLLUP_RPC_PORT="${ROLLUP_RPC_PORT:-57029}"
    L1_BEACON_PORT="${L1_BEACON_PORT:-54357}"

    log_success "Port information retrieved successfully"
    log_info "L1 RPC: http://localhost:$L1_RPC_PORT"
    log_info "L2 RPC: http://localhost:$L2_RPC_PORT"
    log_info "Rollup RPC: http://localhost:$ROLLUP_RPC_PORT"
    log_info "L1 Beacon: http://localhost:$L1_BEACON_PORT"
}

# Get Game Factory Address
get_game_factory_address() {
    log_info "Getting game factory address..."

    # Create temporary directory
    local temp_dir=$(mktemp -d)

    # Download Devnet deployment configuration files
    if kurtosis files download simple-devnet op-deployer-configs "$temp_dir" > /dev/null 2>&1; then
        # Find game factory address
        local factory_address=$(grep -i "DisputeGameFactoryProxy" "$temp_dir/state.json" 2>/dev/null | sed 's/.*"DisputeGameFactoryProxy": *"\([^"]*\)".*/\1/')

        if [ -n "$factory_address" ] && [ "$factory_address" != "null" ]; then
            GAME_FACTORY_ADDRESS="$factory_address"
            log_success "Game factory address retrieved: $GAME_FACTORY_ADDRESS"
        else
            log_warning "Game factory address not found. Using default value."
            GAME_FACTORY_ADDRESS="0x1aec0f0a8be00abf8abcf926a9a65caa7c7ee095"
        fi
    else
        log_warning "Failed to download Devnet configuration files. Using default value."
        GAME_FACTORY_ADDRESS="0x1aec0f0a8be00abf8abcf926a9a65caa7c7ee095"
    fi

    # Clean up temporary directory
    rm -rf "$temp_dir"
}

# Run op-challenger
run_challenger() {
    log_info "Checking op-challenger status..."

    # 1. Check if container is running
    if docker ps --format "{{.Names}}" | grep -q "op-challenger"; then
        log_success "op-challenger is already running"
        return 0
    fi

    # 2. Check if container is stopped
    if docker ps -a --format "{{.Names}}" | grep -q "op-challenger"; then
        log_info "Starting stopped op-challenger container..."
        if docker start op-challenger; then
            log_success "op-challenger started successfully"
            return 0
        else
            log_error "Failed to start op-challenger"
            exit 1
        fi
    fi

    # 3. Run new container
    log_info "Running new op-challenger container..."
    docker run -d \
        --name op-challenger \
        --network host \
        -v challenger-data:/data \
        -v "$OPTIMISM_ROOT/cannon/bin:/cannon-bin:ro" \
        -v "$OPTIMISM_ROOT/op-program/bin:/op-program-bin:ro" \
        op-challenger:devnet \
        op-challenger \
        --network=op-sepolia \
        --datadir=/data \
        --l1-eth-rpc=http://localhost:$L1_RPC_PORT \
        --l1-beacon=http://localhost:$L1_BEACON_PORT \
        --l2-eth-rpc=http://localhost:$L2_RPC_PORT \
        --rollup-rpc=http://localhost:$ROLLUP_RPC_PORT \
        --game-factory-address=$GAME_FACTORY_ADDRESS \
        --trace-type=cannon \
        --cannon-bin=/cannon-bin/cannon \
        --cannon-server=/op-program-bin/op-program \
        --cannon-prestate=/op-program-bin/prestate-mt64Next.bin.gz \
        --mnemonic="test test test test test test test test test test test junk" \
        --hd-path="m/44'/60'/0'/0/0" \
        --p2p-enabled \
        --p2p-listen-addr=/ip4/0.0.0.0/tcp/9876 \
        --p2p-network-id=optimism-challenger-devnet \
        --p2p-max-peers=20 \
        --p2p-discovery-enabled \
        --log.level=INFO

    if [ $? -eq 0 ]; then
        log_success "op-challenger started successfully"
    else
        log_error "Failed to start op-challenger"
        exit 1
    fi
}

# Verify Services Status
verify_services() {
    log_info "Verifying services status..."

    # Wait a moment
    sleep 10

    # Check op-challenger status
    if docker ps --format "{{.Names}}" | grep -q "op-challenger"; then
        log_success "✅ op-challenger is running"
    else
        log_warning "❌ op-challenger is not running"
    fi

    # Check RPC connections
    log_info "Checking RPC connections..."

    # Check L1 RPC
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "http://localhost:$L1_RPC_PORT" > /dev/null 2>&1; then
        log_success "✅ L1 RPC connection successful"
    else
        log_warning "⚠️  L1 RPC connection failed"
    fi

    # Check L2 RPC
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "http://localhost:$L2_RPC_PORT" > /dev/null 2>&1; then
        log_success "✅ L2 RPC connection successful"
    else
        log_warning "⚠️  L2 RPC connection failed"
    fi
}

# Completion Message
show_completion_message() {
    log_success "🎉 Local Devnet P2P Challenger execution completed!"

    echo
    echo "=== Connection Information ==="
    echo "L1 RPC: http://localhost:$L1_RPC_PORT"
    echo "L1 Beacon: http://localhost:$L1_BEACON_PORT"
    echo "L2 RPC: http://localhost:$L2_RPC_PORT"
    echo "Rollup RPC: http://localhost:$ROLLUP_RPC_PORT"
    echo "P2P Port: 9876"
    echo

    echo "=== Management Commands ==="
    echo "Check challenger status: docker ps | grep challenger"
    echo "Check challenger logs: docker logs op-challenger"
    echo "Stop challenger: docker stop op-challenger"
    echo "Remove challenger: docker rm op-challenger"
    echo "Check data volume: docker volume ls | grep challenger"
    echo

    echo "=== Next Steps ==="
    echo "Challenger network is ready!"
    echo "You can now proceed with challenger development."
    echo "Use P2P port 9876 to connect with other challenger nodes."
    echo
}

# Main Function
main() {
    # Execute each step
    check_devnet_status
    check_challenger_image
    check_required_binaries
    get_devnet_ports
    get_game_factory_address
    run_challenger
    verify_services
    show_completion_message
}

# Execute Script
main "$@"