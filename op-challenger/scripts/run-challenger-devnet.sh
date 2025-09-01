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
OPTIMISM_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

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

# Check and Build Required Binary Files
check_required_binaries() {
    log_info "Checking required binary files..."

    local need_build=false

    # Check Cannon binary
    if [ ! -f "$OPTIMISM_ROOT/cannon/bin/cannon" ]; then
        log_warning "Cannon binary not found: $OPTIMISM_ROOT/cannon/bin/cannon"
        need_build=true
    fi

    # Check op-program binary
    if [ ! -f "$OPTIMISM_ROOT/op-program/bin/op-program" ]; then
        log_warning "op-program binary not found: $OPTIMISM_ROOT/op-program/bin/op-program"
        need_build=true
    fi

    # Check prestate file
    if [ ! -f "$OPTIMISM_ROOT/op-program/bin/prestate.bin.gz" ]; then
        log_warning "prestate file not found: $OPTIMISM_ROOT/op-program/bin/prestate.bin.gz"
        need_build=true
    fi

    if [ "$need_build" = true ]; then
        echo
        log_error "❌ Required binaries are missing!"
        echo
        log_info "Please build the required binaries first:"
        echo "  ./build-binaries-for-challenger.sh"
        echo
        log_info "Manual build commands (if needed):"
        echo "  cd $OPTIMISM_ROOT/cannon && make cannon"
        echo "  cd $OPTIMISM_ROOT/op-program && make op-program && make reproducible-prestate"
        echo
        log_info "Build process takes approximately 4-5 minutes"
        echo
        log_info "Check build status:"
        echo "  ls -la $OPTIMISM_ROOT/cannon/bin/cannon"
        echo "  ls -la $OPTIMISM_ROOT/op-program/bin/op-program"
        echo "  ls -la $OPTIMISM_ROOT/op-program/bin/prestate.bin.gz"
        echo
        log_info "After build completes, re-run: ./run-challenger-devnet.sh"
        exit 1
    else
        log_success "All required binary files are ready"
    fi
}

# Get Devnet Port Information
get_devnet_ports() {
    log_info "Getting Devnet port information..."

    # For Kurtosis devnet, use standard port mappings
    # Based on README.md examples
    L1_RPC_PORT="8545"
    L2_RPC_PORT="9545" 
    ROLLUP_RPC_PORT="9546"
    L1_BEACON_PORT="4000"

    # Try to get actual ports from kurtosis if available
    if kurtosis enclave inspect simple-devnet &>/dev/null; then
        local enclave_info=$(kurtosis enclave inspect simple-devnet 2>/dev/null)
        
        # Extract actual mapped ports
        local l1_port=$(echo "$enclave_info" | grep "el-1.*rpc.*8545" | sed 's/.*-> localhost:\([0-9]*\).*/\1/' | head -1)
        local l2_port=$(echo "$enclave_info" | grep "op-el.*rpc.*8545" | sed 's/.*-> localhost:\([0-9]*\).*/\1/' | head -1)
        local rollup_port=$(echo "$enclave_info" | grep "op-cl.*rpc.*8547" | sed 's/.*-> localhost:\([0-9]*\).*/\1/' | head -1)
        local beacon_port=$(echo "$enclave_info" | grep "cl-1.*http.*4000" | sed 's/.*-> localhost:\([0-9]*\).*/\1/' | head -1)
        
        # Use extracted ports if found
        [ -n "$l1_port" ] && L1_RPC_PORT="$l1_port"
        [ -n "$l2_port" ] && L2_RPC_PORT="$l2_port" 
        [ -n "$rollup_port" ] && ROLLUP_RPC_PORT="$rollup_port"
        [ -n "$beacon_port" ] && L1_BEACON_PORT="$beacon_port"
    fi

    log_success "Port information retrieved successfully"
    log_info "L1 RPC: http://localhost:$L1_RPC_PORT"
    log_info "L2 RPC: http://localhost:$L2_RPC_PORT"
    log_info "Rollup RPC: http://localhost:$ROLLUP_RPC_PORT"
    log_info "L1 Beacon: http://localhost:$L1_BEACON_PORT"
}

# Get Devnet Configuration
get_devnet_configuration() {
    log_info "Reading devnet configuration..."

    # Read game type from simple.yaml
    local config_file="$OPTIMISM_ROOT/kurtosis-devnet/simple.yaml"
    if [ -f "$config_file" ]; then
        GAME_TYPE=$(grep "game_type:" "$config_file" | sed 's/.*game_type: *\([0-9]*\).*/\1/')
        if [ -n "$GAME_TYPE" ]; then
            log_success "Game type from configuration: $GAME_TYPE"
        else
            log_warning "Game type not found in configuration. Using default: 0"
            GAME_TYPE="0"
        fi
    else
        log_warning "Configuration file not found. Using default game type: 0"
        GAME_TYPE="0"
    fi

    # Set trace type based on game type
    case $GAME_TYPE in
        0)
            TRACE_TYPE="cannon"
            log_info "Game type 0 (CANNON) -> trace-type: $TRACE_TYPE"
            ;;
        1)
            TRACE_TYPE="permissioned"
            log_info "Game type 1 (PERMISSIONED) -> trace-type: $TRACE_TYPE"
            ;;
        2)
            TRACE_TYPE="asterisc"
            log_info "Game type 2 (ASTERISC) -> trace-type: $TRACE_TYPE"
            ;;
        3)
            TRACE_TYPE="asterisc-kona"
            log_info "Game type 3 (ASTERISC_KONA) -> trace-type: $TRACE_TYPE"
            ;;
        4)
            TRACE_TYPE="super-cannon"
            log_info "Game type 4 (SUPER_CANNON) -> trace-type: $TRACE_TYPE"
            ;;
        5)
            TRACE_TYPE="super-permissioned"
            log_info "Game type 5 (SUPER_PERMISSIONED) -> trace-type: $TRACE_TYPE"
            ;;
        7)
            TRACE_TYPE="super-asterisc-kona"
            log_info "Game type 7 (SUPER_ASTERISC_KONA) -> trace-type: $TRACE_TYPE"
            ;;
        254)
            TRACE_TYPE="fast"
            log_info "Game type 254 (FAST) -> trace-type: $TRACE_TYPE"
            ;;
        255)
            TRACE_TYPE="alphabet"
            log_info "Game type 255 (ALPHABET) -> trace-type: $TRACE_TYPE"
            ;;
        *)
            TRACE_TYPE="cannon"
            log_warning "Unknown game type $GAME_TYPE -> using default trace-type: $TRACE_TYPE"
            ;;
    esac
}

# Get Game Factory Address  
get_game_factory_address() {
    log_info "Getting game factory address..."

    # Try to get from kurtosis devnet addresses
    local temp_dir=$(mktemp -d)
    
    if kurtosis files download simple-devnet op-deployer-configs "$temp_dir" > /dev/null 2>&1; then
        # Find game factory address from state.json
        local factory_address=$(jq -r '.DisputeGameFactoryProxy // empty' "$temp_dir/state.json" 2>/dev/null)
        
        if [ -n "$factory_address" ] && [ "$factory_address" != "null" ] && [ "$factory_address" != "" ]; then
            GAME_FACTORY_ADDRESS="$factory_address"
            log_success "Game factory address retrieved: $GAME_FACTORY_ADDRESS"
        else
            # Try alternative locations
            local alt_address=$(find "$temp_dir" -name "*.json" -exec jq -r '.DisputeGameFactoryProxy // .disputeGameFactoryProxy // empty' {} \; 2>/dev/null | head -1)
            if [ -n "$alt_address" ] && [ "$alt_address" != "null" ]; then
                GAME_FACTORY_ADDRESS="$alt_address"
                log_success "Game factory address found: $GAME_FACTORY_ADDRESS"
            else
                log_warning "Game factory address not found in configs. Using environment variable or default."
                GAME_FACTORY_ADDRESS="${DISPUTE_GAME_FACTORY:-0xd6E6dBf4F7EA0ac412fD8b65ED297e64BB7a06E1}"
            fi
        fi
    else
        log_warning "Failed to download Devnet configuration files."
        GAME_FACTORY_ADDRESS="${DISPUTE_GAME_FACTORY:-0xd6E6dBf4F7EA0ac412fD8b65ED297e64BB7a06E1}"
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

    # 3. Run new container - Based on README.md example
    log_info "Running new op-challenger container..."
    
    # Check if rollup.json and genesis-l2.json exist for cannon trace type
    local rollup_config=""
    local l2_genesis=""
    
    if [ "$TRACE_TYPE" = "cannon" ]; then
        if [ -f "$OPTIMISM_ROOT/.devnet/rollup.json" ]; then
            rollup_config="--cannon-rollup-config $OPTIMISM_ROOT/.devnet/rollup.json"
        fi
        if [ -f "$OPTIMISM_ROOT/.devnet/genesis-l2.json" ]; then
            l2_genesis="--cannon-l2-genesis $OPTIMISM_ROOT/.devnet/genesis-l2.json"
        fi
    fi
    
    docker run -d \
        --name op-challenger \
        --network host \
        -v challenger-data:/data \
        -v "$OPTIMISM_ROOT:/workspace:ro" \
        op-challenger:devnet \
        op-challenger \
        --trace-type=$TRACE_TYPE \
        --datadir=/data \
        --l1-eth-rpc=http://localhost:$L1_RPC_PORT \
        --l1-beacon=http://localhost:$L1_BEACON_PORT \
        --l2-eth-rpc=http://localhost:$L2_RPC_PORT \
        --rollup-rpc=http://localhost:$ROLLUP_RPC_PORT \
        --game-factory-address=$GAME_FACTORY_ADDRESS \
        --cannon-bin=/workspace/cannon/bin/cannon \
        --cannon-server=/workspace/op-program/bin/op-program \
        --cannon-prestate=/workspace/op-program/bin/prestate.bin.gz \
        $rollup_config \
        $l2_genesis \
        --mnemonic="test test test test test test test test test test test junk" \
        --hd-path="m/44'/60'/0'/0/8" \
        --num-confirmations=1 \
        --log.level=info

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
    log_success "🎉 Local Devnet Challenger execution completed!"

    echo
    echo "=== Connection Information ==="
    echo "L1 RPC: http://localhost:$L1_RPC_PORT"
    echo "L1 Beacon: http://localhost:$L1_BEACON_PORT"
    echo "L2 RPC: http://localhost:$L2_RPC_PORT"
    echo "Rollup RPC: http://localhost:$ROLLUP_RPC_PORT"
    echo

    echo "=== Management Commands ==="
    echo "Check challenger status: kurtosis service ls simple-devnet | grep challenger"
    echo "Check challenger logs: kurtosis service logs simple-devnet op-challenger-challenger-2151908"
    echo "Follow challenger logs: kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow"
    echo "Stop challenger: kurtosis service stop simple-devnet op-challenger-challenger-2151908"
    echo "Start challenger: kurtosis service start simple-devnet op-challenger-challenger-2151908"
    echo "Restart challenger: kurtosis service restart simple-devnet op-challenger-challenger-2151908"
    echo "Check devnet status: kurtosis enclave inspect simple-devnet"
    echo

    echo "=== Next Steps ==="
    echo "Challenger is ready!"
    echo "You can now proceed with challenger development."
    echo
}

# Main Function
main() {
    # Execute each step
    check_devnet_status
    check_challenger_image
    check_required_binaries
    get_devnet_ports
    get_devnet_configuration
    get_game_factory_address
    run_challenger
    verify_services
    show_completion_message
    validate_final_configuration
}

# Validate Final Configuration (after challenger is running)
validate_final_configuration() {
    log_info "Validating final configuration..."

    # Wait for challenger to initialize
    sleep 5

    echo
    echo "=== Configuration Summary ==="
    echo "Game Type (from simple.yaml): $GAME_TYPE"
    echo "Trace Type (challenger): $TRACE_TYPE"

    # Check challenger status
    if docker ps --format "{{.Names}}" | grep -q "op-challenger"; then
        echo "Challenger Status: ✅ Running"
        log_success "🎉 Configuration validated successfully!"
    else
        echo "Challenger Status: ❌ Not running"
        log_warning "⚠️  Challenger failed to start"
    fi

    echo "=== Validation Complete ==="
    echo
}

# Execute Script
main "$@"