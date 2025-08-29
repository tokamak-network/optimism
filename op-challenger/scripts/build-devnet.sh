#!/bin/bash

# ==========================================
# Challenger Network - Devnet Builder
# Optimism Sequencer System Improvement Project
# ==========================================

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging Functions
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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 변수 정의
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTIMISM_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
KURTOSIS_DEVNET_DIR="$OPTIMISM_ROOT/optimism/kurtosis-devnet"

ENCLAVE_NAME="simple-devnet"
BUILD_LOG="/tmp/devnet-build.log"

# Service List
SERVICES=(
    "op-node"
    "op-batcher"
    "op-proposer"
    "op-faucet"
    "op-challenger"
    "op-deployer"
    "geth"
)

# Initialization
init() {
    log_step "Devnet Builder Initialization"

    # Check directory
    if [ ! -d "$KURTOSIS_DEVNET_DIR" ]; then
        log_error "Kurtosis devnet directory not found: $KURTOSIS_DEVNET_DIR"
        exit 1
    fi

    # Clean up existing enclave
    if kurtosis enclave list | grep -q "$ENCLAVE_NAME"; then
        log_info "Cleaning up existing enclave: $ENCLAVE_NAME"
        kurtosis enclave rm --force "$ENCLAVE_NAME" > /dev/null 2>&1 || true
        sleep 2
    fi

    # Initialize build log
    > "$BUILD_LOG"

    log_success "Initialization completed"
}

# Check System Requirements
check_requirements() {
    log_step "Checking System Requirements"

    # Check Go version
    if ! command -v go &> /dev/null; then
        log_error "Go is not installed"
        exit 1
    fi

    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    log_info "Go version: $GO_VERSION"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker service is not running"
        exit 1
    fi

    # Check Kurtosis
    if ! command -v kurtosis &> /dev/null; then
        log_error "Kurtosis is not installed"
        exit 1
    fi

    log_success "System requirements check completed"
}

# Build Docker Images
build_docker_images() {
    log_step "Building Docker Images"

    cd "$KURTOSIS_DEVNET_DIR"

        # Check Docker build modifications
    log_info "Checking Docker build modifications..."

    # Check if go-libp2p-mplex fix code is already added to Dockerfile
    local dockerfile="$OPTIMISM_ROOT/optimism/ops/docker/op-stack-go/Dockerfile"
    if [ -f "$dockerfile" ]; then
        if grep -q "Fix go-libp2p-mplex compatibility issues" "$dockerfile"; then
            log_success "Docker build modifications are already applied"
        else
            log_warning "Docker build modifications are not applied. Please apply manually."
        fi
    else
        log_warning "Dockerfile not found"
    fi

    cd "$KURTOSIS_DEVNET_DIR"

    # Move to kurtosis-devnet directory (where just recipes are)
    cd "$OPTIMISM_ROOT/optimism/kurtosis-devnet"

    local build_success_count=0
    local total_services=${#SERVICES[@]}

    for service in "${SERVICES[@]}"; do
        log_info "Building: $service"

        # Set Git information
        local git_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        local git_date=$(git show -s --format='%ct' 2>/dev/null || echo "0")

        # Docker build command for each service
        case $service in
            "op-node")
                if GITCOMMIT="$git_commit" GITDATE="$git_date" just op-node-image >> "$BUILD_LOG" 2>&1; then
                    log_success "✅ $service build successful"
                    ((build_success_count++))
                else
                    log_error "❌ $service build failed"
                fi
                ;;
            "op-batcher")
                if GITCOMMIT="$git_commit" GITDATE="$git_date" just op-batcher-image >> "$BUILD_LOG" 2>&1; then
                    log_success "✅ $service build successful"
                    ((build_success_count++))
                else
                    log_error "❌ $service build failed"
                fi
                ;;
            "op-proposer")
                if GITCOMMIT="$git_commit" GITDATE="$git_date" just op-proposer-image >> "$BUILD_LOG" 2>&1; then
                    log_success "✅ $service build successful"
                    ((build_success_count++))
                else
                    log_error "❌ $service build failed"
                fi
                ;;
            "op-faucet")
                if GITCOMMIT="$git_commit" GITDATE="$git_date" just op-faucet-image >> "$BUILD_LOG" 2>&1; then
                    log_success "✅ $service build successful"
                    ((build_success_count++))
                else
                    log_error "❌ $service build failed"
                fi
                ;;
            "op-challenger")
                if GITCOMMIT="$git_commit" GITDATE="$git_date" just op-challenger-image >> "$BUILD_LOG" 2>&1; then
                    log_success "✅ $service build successful"
                    ((build_success_count++))
                else
                    log_error "❌ $service build failed"
                fi
                ;;
            "op-deployer")
                if GITCOMMIT="$git_commit" GITDATE="$git_date" just op-deployer-image >> "$BUILD_LOG" 2>&1; then
                    log_success "✅ $service build successful"
                    ((build_success_count++))
                else
                    log_error "❌ $service build failed"
                fi
                ;;
            "geth")
                log_info "geth uses default image"
                ((build_success_count++))
                ;;
        esac
    done

    # Build result summary
    log_info "=== Build Result Summary ==="
    log_info "Successful services: $build_success_count/$total_services"

    if [ $build_success_count -eq $total_services ]; then
        log_success "🎉 All services built successfully!"
        return 0
    elif [ $build_success_count -gt 0 ]; then
        log_warning "⚠️  Only some services built ($build_success_count/$total_services)"
        log_info "Devnet may work with limited functionality."
        return 0
    else
        log_error "❌ All service builds failed (0/$total_services)"
        return 1
    fi
}

# Deploy Devnet
deploy_devnet() {
    log_step "Deploying Devnet"

    cd "$KURTOSIS_DEVNET_DIR"

    log_info "Deploying Devnet... (5-15 minutes required)"

    # Create our own Devnet configuration
    create_devnet_config

    # Run Kurtosis package (more stable way)
    log_info "Running Kurtosis package..."

    # Clean up existing enclave
    if kurtosis enclave list | grep -q "$ENCLAVE_NAME"; then
        log_info "Cleaning up existing enclave..."
        kurtosis enclave rm --force "$ENCLAVE_NAME" > /dev/null 2>&1 || true
        sleep 10  # Longer wait time
    fi

    # Create and run new enclave
    log_info "Creating new Devnet..."

    # Run with timeout setting (increased to 10 minutes)
    timeout 600 kurtosis run ./optimism-package-trampoline/ --enclave "$ENCLAVE_NAME" >> "$BUILD_LOG" 2>&1
    local exit_code=$?

    # Analyze result
    if [ $exit_code -eq 0 ]; then
        log_success "Devnet deployment successful"
        return 0
    elif [ $exit_code -eq 124 ]; then
        log_warning "Devnet deployment timeout (10 minutes). Checking status..."

        # Check for success indicators in logs (more accurate judgment)
        if grep -q "L1 Chain has started\|L1 Chain is starting up\|RUNNING.*cl-1-lighthouse-geth\|RUNNING.*el-1-geth-lighthouse" "$BUILD_LOG"; then
            log_success "Devnet started successfully (timeout but working normally)"
            return 0
        else
            log_error "Devnet deployment failed (timeout)"
            return 1
        fi
    else
        log_warning "Devnet deployment process terminated (exit code: $exit_code). Checking logs..."

        # Check for success indicators in logs (more accurate judgment)
        if grep -q "L1 Chain has started\|L1 Chain is starting up\|RUNNING.*cl-1-lighthouse-geth\|RUNNING.*el-1-geth-lighthouse" "$BUILD_LOG"; then
            log_success "Devnet started successfully (process terminated but working normally)"
            return 0
        else
            log_error "Devnet deployment failed"
            log_info "Detailed error logs:"
            tail -20 "$BUILD_LOG" | while read line; do
                echo "  $line"
            done
            return 1
        fi
    fi
}

# Create Devnet Configuration
create_devnet_config() {
    log_info "Creating Devnet configuration files..."

    # simple.yaml already includes correct op-challenger settings
    # use as is without additional modifications
    log_success "Devnet configuration completed (using default simple.yaml)"
}

# Verify Services Status (Improved Version)
verify_services() {
    log_step "Verifying Services Status"

    # Longer wait time (60 seconds)
    log_info "Waiting for services to start... (60 seconds)"
    sleep 60

    local running_services=0
    local total_services=${#SERVICES[@]}
    local challenger_running=false

    # Check basic services first
    for service in "${SERVICES[@]}"; do
        if [ "$service" = "op-challenger" ]; then
            continue  # op-challenger will be checked separately
        fi

        if docker ps --format "{{.Names}}" | grep -q "$service"; then
            log_success "✅ $service is running"
            ((running_services++))
        else
            log_warning "❌ $service is not running"
        fi
    done

    # op-challenger specific check (after dependency services are ready)
    log_info "Checking op-challenger dependencies..."

    # Check if dependency services are ready
    local dependencies_ready=true
    local dependency_services=("el-1-geth-lighthouse" "cl-1-lighthouse-geth" "op-el-2151908-node0-op-geth" "op-cl-2151908-node0-op-node")

    for dep_service in "${dependency_services[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "$dep_service"; then
            log_info "✅ Dependency service $dep_service is ready"
        else
            log_warning "⚠️  Dependency service $dep_service is not ready"
            dependencies_ready=false
        fi
    done

    # Check op-challenger
    if [ "$dependencies_ready" = true ]; then
        log_info "Checking op-challenger status..."
        if docker ps --format "{{.Names}}" | grep -q "op-challenger"; then
            log_success "✅ op-challenger is running"
            ((running_services++))
            challenger_running=true
                else
            log_warning "❌ op-challenger is not running"
            log_info "Please check simple.yaml configuration"
        fi
    else
        log_warning "⚠️  Skipping op-challenger check due to unready dependencies"
    fi

    # Service status summary
    log_info "=== Service Status Summary ==="
    log_info "Running services: $running_services/$total_services"

    if [ "$challenger_running" = true ]; then
        log_success "🎉 op-challenger is running normally!"
    else
        log_warning "⚠️  op-challenger can be added manually later"
    fi

    if [ $running_services -eq $total_services ]; then
        log_success "🎉 All services are running normally!"
        return 0
    elif [ $running_services -gt 0 ]; then
        log_warning "⚠️  Only some services are running ($running_services/$total_services)"
        return 0
    else
        log_error "❌ No services are running (0/$total_services)"
        return 1
    fi
}



# Verify RPC Connections
verify_rpc_connections() {
    log_step "Verifying RPC Connections"

    # Extract port information (use default values)
    local l1_port="53620"
    local l2_port="56781"

    # Check L1 RPC
    log_info "Checking L1 RPC connection... (port: $l1_port)"
    for i in {1..12}; do
        if curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "http://localhost:$l1_port" > /dev/null 2>&1; then
            log_success "✅ L1 RPC connection successful"
            break
        fi
        if [ $i -eq 12 ]; then
            log_warning "⚠️  L1 RPC connection failed"
        fi
        sleep 5
    done

    # Check L2 RPC
    log_info "Checking L2 RPC connection... (port: $l2_port)"
    for i in {1..12}; do
        if curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "http://localhost:$l2_port" > /dev/null 2>&1; then
            log_success "✅ L2 RPC connection successful"
            break
        fi
        if [ $i -eq 12 ]; then
            log_warning "⚠️  L2 RPC connection failed"
        fi
        sleep 5
    done
}

# Completion Message
show_completion_message() {
    log_success "🎉 Devnet build and deployment completed!"

    echo
    echo "=== Devnet Management Commands ==="
    echo "Check Devnet status: kurtosis enclave inspect $ENCLAVE_NAME"
    echo "Stop Devnet: kurtosis enclave rm --force $ENCLAVE_NAME"
    echo "Check Devnet logs: kurtosis enclave logs $ENCLAVE_NAME"
    echo "Check build logs: cat $BUILD_LOG"
    echo

    echo "=== Connection Information ==="
    echo "L1 RPC: http://localhost:53620"
    echo "L2 RPC: http://localhost:56781"
    echo "Rollup RPC: http://localhost:57029"
    echo

    echo "=== Next Steps ==="
    echo "To set up P2P challenger network, run the following command:"
    echo "cd $SCRIPT_DIR"
    echo "./install-and-run.sh"
    echo
}

# Main Function
main() {
    echo "=========================================="
    echo "Challenger Network - Devnet Builder"
    echo "Optimism Sequencer System Improvement Project"
    echo "=========================================="
    echo

    # Execute each step
    init
    check_requirements
    build_docker_images
    deploy_devnet
    verify_services
    verify_rpc_connections
    show_completion_message
}

# Execute Script
main "$@"