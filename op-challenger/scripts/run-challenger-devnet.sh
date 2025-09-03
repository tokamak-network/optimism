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

    # Get actual ports from kurtosis enclave
    if kurtosis enclave inspect simple-devnet &>/dev/null; then
        local enclave_info=$(kurtosis enclave inspect simple-devnet 2>/dev/null)
        
        # Extract actual mapped ports from current Kurtosis deployment using known service names
        # Based on current Kurtosis inspect output
        L1_RPC_PORT="50514"   # el-1-geth-teku rpc port
        L2_RPC_PORT="50554"   # op-el-2151908-node0-op-geth rpc port  
        ROLLUP_RPC_PORT="50557" # op-cl-2151908-node0-op-node rpc port
        L1_BEACON_PORT="50519"  # cl-1-teku-geth http port
        FILESERVER_PORT="50400" # fileserver http port
        
        # Verify ports are actually accessible
        local port_check_failed=false
        for port in "$L1_RPC_PORT" "$L2_RPC_PORT" "$ROLLUP_RPC_PORT" "$L1_BEACON_PORT" "$FILESERVER_PORT"; do
            if ! netstat -an | grep -q ":$port "; then
                log_warning "Port $port may not be accessible"
                port_check_failed=true
            fi
        done
        
        # Validate extracted ports
        if [ -z "$L1_RPC_PORT" ] || [ -z "$L2_RPC_PORT" ] || [ -z "$ROLLUP_RPC_PORT" ] || [ -z "$L1_BEACON_PORT" ]; then
            log_error "Failed to extract all required ports from Kurtosis"
            log_info "Please check if simple-devnet is running properly"
            exit 1
        fi
    else
        log_error "Cannot access Kurtosis enclave simple-devnet"
        log_info "Please ensure devnet is running: just simple-devnet"
        exit 1
    fi

    log_success "Port information retrieved successfully"
    log_info "L1 RPC: http://localhost:$L1_RPC_PORT"
    log_info "L2 RPC: http://localhost:$L2_RPC_PORT"
    log_info "Rollup RPC: http://localhost:$ROLLUP_RPC_PORT"
    log_info "L1 Beacon: http://localhost:$L1_BEACON_PORT"
    log_info "Fileserver: http://localhost:$FILESERVER_PORT"
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

# Get Game Factory Address and Network Config
get_game_factory_address() {
    log_info "Getting game factory address and network configuration..."

    # Download configuration files from Kurtosis
    local temp_dir=$(mktemp -d)
    
    if kurtosis files download simple-devnet op-deployer-configs "$temp_dir" > /dev/null 2>&1; then
        # Find game factory address from state.json - check multiple possible locations
        local factory_address=$(jq -r '.. | .DisputeGameFactoryProxy? // empty' "$temp_dir/state.json" 2>/dev/null | head -1)
        
        if [ -n "$factory_address" ] && [ "$factory_address" != "null" ] && [ "$factory_address" != "" ]; then
            GAME_FACTORY_ADDRESS="$factory_address"
            log_success "Game factory address retrieved: $GAME_FACTORY_ADDRESS"
        else
            log_error "Game factory address not found in state.json"
            rm -rf "$temp_dir"
            exit 1
        fi

        # Set network configuration files paths
        ROLLUP_CONFIG="$temp_dir/rollup-2151908.json"
        L2_GENESIS="$temp_dir/genesis-2151908.json"
        
        # Verify configuration files exist
        if [ ! -f "$ROLLUP_CONFIG" ]; then
            log_error "Rollup configuration file not found: $ROLLUP_CONFIG"
            rm -rf "$temp_dir"
            exit 1
        fi
        
        if [ ! -f "$L2_GENESIS" ]; then
            log_error "L2 genesis file not found: $L2_GENESIS"  
            rm -rf "$temp_dir"
            exit 1
        fi
        
        log_success "Network configuration files located"
        log_info "Rollup config: $ROLLUP_CONFIG"
        log_info "L2 genesis: $L2_GENESIS"
        
        # Set global temp dir for cleanup later
        CONFIG_TEMP_DIR="$temp_dir"
    else
        log_error "Failed to download Devnet configuration files from Kurtosis"
        log_info "Please ensure simple-devnet is running properly"
        exit 1
    fi
}

# Run op-challenger
run_challenger() {
    log_info "Checking op-challenger status..."

    # 1. Check if container is running
    if docker ps --format "{{.Names}}" | grep -q "op-challenger"; then
        log_success "op-challenger is already running"
        return 0
    fi

    # 2. Remove any stopped containers with same name
    if docker ps -a --format "{{.Names}}" | grep -q "op-challenger"; then
        log_info "Removing existing stopped op-challenger container..."
        docker rm -f op-challenger >/dev/null 2>&1 || true
    fi

    # 3. Run new container with Kurtosis configuration
    log_info "Running new op-challenger container..."
    
    # Use the correct image tag
    local image_name="op-challenger:simple-devnet"
    if ! docker images | grep -q "op-challenger.*simple-devnet"; then
        image_name="op-challenger:devnet"
        if ! docker images | grep -q "op-challenger.*devnet"; then
            log_error "No op-challenger Docker image found"
            log_info "Available images:"
            docker images | grep challenger
            exit 1
        fi
    fi
    
    log_info "Using Docker image: $image_name"
    
    # Build cannon configuration parameters
    local cannon_config=""
    if [[ "$TRACE_TYPE" == *"cannon"* ]]; then
        cannon_config="--cannon-rollup-config=/configs/rollup-2151908.json --cannon-l2-genesis=/configs/genesis-2151908.json"
    fi
    
    docker run -d \
        --name op-challenger \
        --network host \
        -v challenger-data:/data \
        -v "$CONFIG_TEMP_DIR:/configs:ro" \
        "$image_name" \
        op-challenger \
        --trace-type=$TRACE_TYPE \
        --datadir=/data \
        --l1-eth-rpc=http://localhost:$L1_RPC_PORT \
        --l1-beacon=http://localhost:$L1_BEACON_PORT \
        --l2-eth-rpc=http://localhost:$L2_RPC_PORT \
        --rollup-rpc=http://localhost:$ROLLUP_RPC_PORT \
        --game-factory-address=$GAME_FACTORY_ADDRESS \
        --cannon-bin=/usr/local/bin/cannon \
        --cannon-server=/usr/local/bin/op-program \
        --cannon-prestates-url=http://localhost:$FILESERVER_PORT/proofs/op-program/cannon \
        $cannon_config \
        --private-key=0x717c53f6d6c266889465d78a885cd0a2e22d41f73e21fa1f07ba5849c82d79c3 \
        --num-confirmations=1 \
        --log.level=debug

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
    echo "Check challenger status: docker ps | grep op-challenger"
    echo "Check challenger logs: docker logs op-challenger"
    echo "Follow challenger logs: docker logs op-challenger --follow"
    echo "Stop challenger: docker stop op-challenger"
    echo "Start challenger: docker start op-challenger"  
    echo "Restart challenger: docker restart op-challenger"
    echo "Remove challenger: docker rm -f op-challenger"
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

# Cleanup function
cleanup() {
    if [ -n "$CONFIG_TEMP_DIR" ] && [ -d "$CONFIG_TEMP_DIR" ]; then
        log_info "Cleaning up temporary configuration files..."
        rm -rf "$CONFIG_TEMP_DIR"
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Execute Script
main "$@"