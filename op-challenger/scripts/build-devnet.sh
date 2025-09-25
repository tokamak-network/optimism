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

# Help Function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Build Optimism devnet with configurable parameters"
    echo
    echo "OPTIONS:"
    echo "  --game-type=TYPE    Set game type (0=CANNON, 1=PERMISSIONED, 2=ASTERISC)"
    echo "                      Default: 1 (PERMISSIONED)"
    echo "  --verbose, -v       Show deployment logs in real-time"
    echo "  -h, --help          Show this help message"
    echo
    echo "EXAMPLES:"
    echo "  $0                      # Build with default game type (PERMISSIONED)"
    echo "  $0 --game-type=0        # Build with CANNON game type"
    echo "  $0 --game-type=1        # Build with PERMISSIONED game type"
    echo
    echo "GAME TYPES:"
    echo "  0  CANNON        Complete fault proof (requires cannon binaries)"
    echo "  1  PERMISSIONED  Fast development/testing (default)"
    echo "  2  ASTERISC      Asterisc VM (requires asterisc binaries)"
    echo
}

# Parse Command Line Arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --game-type=*)
                GAME_TYPE="${1#*=}"
                if ! [[ "$GAME_TYPE" =~ ^[0-2]$ ]]; then
                    log_error "Invalid game type: $GAME_TYPE"
                    log_error "Valid game types: 0 (CANNON), 1 (PERMISSIONED), 2 (ASTERISC)"
                    exit 1
                fi
                log_info "Game type set to: $GAME_TYPE"
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

# 변수 정의 (동적 경로 발견)
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
OPTIMISM_ROOT="$(realpath "$SCRIPT_DIR/../..")"
KURTOSIS_DEVNET_DIR="$OPTIMISM_ROOT/kurtosis-devnet"

# 경로 디버깅 (개발용)
if [ "${DEBUG_PATHS:-}" = "1" ]; then
    echo "DEBUG: SCRIPT_DIR=$SCRIPT_DIR"
    echo "DEBUG: OPTIMISM_ROOT=$OPTIMISM_ROOT"
    echo "DEBUG: KURTOSIS_DEVNET_DIR=$KURTOSIS_DEVNET_DIR"
fi

ENCLAVE_NAME="simple-devnet"
BUILD_LOG="/tmp/devnet-build.log"

# Default values - will be read from simple.yaml if not specified
DEFAULT_GAME_TYPE=""  # Will be set later
GAME_TYPE=""

# Core Services (Persistent)
CORE_SERVICES=(
    "op-node"
    "op-batcher"
    "op-proposer"
)

# Build Services (for Docker image building)
BUILD_SERVICES=(
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

    # Clean up orphaned Docker network (if exists)
    NETWORK_NAME="kt-$ENCLAVE_NAME"
    if docker network ls --format "table {{.Name}}" | grep -q "^$NETWORK_NAME$"; then
        log_info "Cleaning up orphaned Docker network: $NETWORK_NAME"
        docker network rm "$NETWORK_NAME" > /dev/null 2>&1 || true
        sleep 1
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
    log_info "Expected build time: ~3-7 minutes (depending on cache)"
    echo "   🔧 Building: op-node, op-batcher, op-proposer, op-faucet, op-challenger, op-deployer"

    cd "$KURTOSIS_DEVNET_DIR"

        # Check Docker build modifications
    log_info "Checking Docker build modifications..."

    # Check if go-libp2p-mplex fix code is already added to Dockerfile
    local dockerfile="$OPTIMISM_ROOT/ops/docker/op-stack-go/Dockerfile"
    if [ -f "$dockerfile" ]; then
        if grep -q "Fix go-libp2p-mplex compatibility issues" "$dockerfile"; then
            log_success "Docker build modifications are already applied"
        else
            log_warning "Docker build modifications are not applied. Please apply manually."
        fi
    else
        log_warning "Dockerfile not found"
    fi

    # Move to kurtosis-devnet directory (where just recipes are)
    cd "$KURTOSIS_DEVNET_DIR"

    # Verify we're in the correct directory
    if [ ! -f "justfile" ]; then
        log_error "justfile not found in $KURTOSIS_DEVNET_DIR"
        exit 1
    fi

    local build_success_count=0
    local total_services=${#BUILD_SERVICES[@]}

    for service in "${BUILD_SERVICES[@]}"; do
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

    log_info "Deploying Devnet... (Total: 5-15 minutes required)"
    echo "   ⏱️  Expected timeline:"
    echo "     • Configuration setup: ~30 seconds"
    echo "     • Docker image preparation: ~2-3 minutes"
    echo "     • L1 chain startup: ~2-3 minutes"
    echo "     • Contract deployments: ~3-5 minutes"
    echo "     • L2 chain startup: ~2-4 minutes"
    echo "     • Service verification: ~1-2 minutes"

    # Create our own Devnet configuration
    log_info "Step 1/6: Creating Devnet configuration... (~30 seconds)"
    create_devnet_config

    # Run Kurtosis package (more stable way)
    log_info "Step 2/6: Preparing Docker images and infrastructure... (~2-3 minutes)"

    # Clean up existing enclave
    if kurtosis enclave list | grep -q "$ENCLAVE_NAME"; then
        log_info "Cleaning up existing enclave..."
        kurtosis enclave rm --force "$ENCLAVE_NAME" > /dev/null 2>&1 || true
        sleep 10  # Longer wait time
    fi

    # Pre-deployment check before the most critical step
    log_info "Step 3/6: Starting L1 chain and deploying contracts... (~5-8 minutes)"
    log_warning "⚠️  This is the longest step - L1 startup + contract deployments"

    # Run quick pre-deployment check to catch issues early
    log_info "Running pre-deployment safety check..."
    if ! bash "$SCRIPT_DIR/scripts-build-devnet/ultra-simple-check.sh" >/dev/null 2>&1; then
        log_error "Pre-deployment check failed - aborting to prevent timeout"
        echo "       → Running detailed check for diagnosis:"
        bash "$SCRIPT_DIR/scripts-build-devnet/ultra-simple-check.sh"
        return 1
    fi
    log_success "Pre-deployment check passed ✓"

    # Run with timeout setting (increased to 10 minutes)
    # Use absolute paths to avoid YAML parsing issues
    # Add retry mechanism for GRPC communication issues
    local max_retries=3
    local attempt=1
    local exit_code=1

    while [ $attempt -le $max_retries ]; do
        log_info "Deployment attempt $attempt/$max_retries..."

        # Clean up previous failed attempt if not the first
        if [ $attempt -gt 1 ]; then
            log_info "Cleaning up previous attempt..."
            if kurtosis enclave list | grep -q "$ENCLAVE_NAME"; then
                kurtosis enclave rm --force "$ENCLAVE_NAME" > /dev/null 2>&1 || true
                sleep 5
            fi
        fi

        # Use a safer approach: create artifacts inside the package directory
        log_info "Preparing artifacts for package integration..."

        # Copy artifacts to package directory so they're included automatically
        if [ -f "$KURTOSIS_DEVNET_DIR/.l1-artifacts-tar-path" ] && [ -f "$KURTOSIS_DEVNET_DIR/.l2-artifacts-tar-path" ]; then
            local l1_tar_path=$(cat "$KURTOSIS_DEVNET_DIR/.l1-artifacts-tar-path")
            local l2_tar_path=$(cat "$KURTOSIS_DEVNET_DIR/.l2-artifacts-tar-path")

            # Extract and copy artifacts to trampoline package with verification
            log_info "Integrating artifacts into package..."
            cd "$KURTOSIS_DEVNET_DIR/optimism-package-trampoline"

            # Create artifacts directory in package
            mkdir -p artifacts/l1-artifacts artifacts/l2-artifacts

            # Extract L1 artifacts with error checking
            log_info "Extracting L1 artifacts from: $l1_tar_path"
            if [ -f "$l1_tar_path" ]; then
                if tar -xf "$l1_tar_path" -C artifacts/l1-artifacts/; then
                    local l1_count=$(find artifacts/l1-artifacts -name "*.json" -type f | wc -l)
                    log_info "✅ L1 artifacts extracted: $l1_count JSON files"
                else
                    log_error "❌ Failed to extract L1 artifacts from $l1_tar_path"
                    exit 1
                fi
            else
                log_error "❌ L1 tar file not found: $l1_tar_path"
                exit 1
            fi

            # Extract L2 artifacts with error checking
            log_info "Extracting L2 artifacts from: $l2_tar_path"
            if [ -f "$l2_tar_path" ]; then
                if tar -xf "$l2_tar_path" -C artifacts/l2-artifacts/; then
                    local l2_count=$(find artifacts/l2-artifacts -name "*.json" -type f | wc -l)
                    log_info "✅ L2 artifacts extracted: $l2_count JSON files"
                else
                    log_error "❌ Failed to extract L2 artifacts from $l2_tar_path"
                    exit 1
                fi
            else
                log_error "❌ L2 tar file not found: $l2_tar_path"
                exit 1
            fi

            # Verify critical artifacts exist
            local critical_files=("DeployImplementations.s.sol/DeployImplementations.json" "OptimismPortal2.sol/OptimismPortal2.json" "DisputeGameFactory.sol/DisputeGameFactory.json")
            for critical_file in "${critical_files[@]}"; do
                if [ -f "artifacts/l1-artifacts/$critical_file" ] || [ -f "artifacts/l2-artifacts/$critical_file" ]; then
                    log_info "✅ Critical artifact found: $critical_file"
                else
                    log_warning "⚠️  Critical artifact missing: $critical_file"
                fi
            done

            cd "$KURTOSIS_DEVNET_DIR"
            log_success "✅ Artifacts integrated and verified in package"
        else
            log_error "❌ Artifact tar paths not found. Ensure prepare_artifacts was successful."
            exit 1
        fi

        # Now run normally - artifacts are part of the package
        log_info "Running deployment with integrated artifacts..."
        timeout 1200 kurtosis run "$KURTOSIS_DEVNET_DIR/optimism-package-trampoline" --args-file "$KURTOSIS_DEVNET_DIR/simple-processed.yaml" --enclave "$ENCLAVE_NAME" 2>&1 | tee -a "$BUILD_LOG"
        exit_code=$?

        # Check for specific GRPC/UTF-8 errors that indicate communication issues
        if [ $exit_code -ne 0 ]; then
            if grep -q "grpc: error while marshaling.*UTF-8\|Unexpected error happened reading the stream" "$BUILD_LOG"; then
                log_warning "GRPC communication error detected on attempt $attempt"
                if [ $attempt -lt $max_retries ]; then
                    log_info "Retrying deployment due to communication issue..."
                    echo "   🔄 Communication errors are usually temporary"
                    sleep 10  # Wait before retry
                    attempt=$((attempt + 1))
                    continue
                else
                    log_error "All retry attempts failed due to communication issues"
                fi
            else
                # Different error, don't retry
                break
            fi
        else
            # Success!
            break
        fi

        attempt=$((attempt + 1))
    done

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

# Process template variables in YAML
process_yaml_templates() {
    local source_yaml="$1"
    local target_yaml="$2"

    log_info "Processing templates in $source_yaml..."

    # Copy the source file first
    cp "$source_yaml" "$target_yaml"

    # Replace Docker image templates
    sed -i '' 's/{{ localDockerImage "op-faucet" }}/op-faucet:devnet/g' "$target_yaml"
    sed -i '' 's/{{ localDockerImage "op-node" }}/op-node:devnet/g' "$target_yaml"
    sed -i '' 's/{{ localDockerImage "op-batcher" }}/op-batcher:devnet/g' "$target_yaml"
    sed -i '' 's/{{ localDockerImage "op-proposer" }}/op-proposer:devnet/g' "$target_yaml"
    sed -i '' 's/{{ localDockerImage "op-challenger" }}/op-challenger:devnet/g' "$target_yaml"
    sed -i '' 's/{{ localDockerImage "op-deployer" }}/op-deployer:devnet/g' "$target_yaml"

    # Replace other common templates with reasonable defaults
    sed -i '' 's/{{ localPrestate.URL }}/file:\/\/\/op-program\/prestate.json/g' "$target_yaml"
    # Use artifact:// locator as expected by Kurtosis (artifacts uploaded by prepare_contract_artifacts)
    sed -i '' 's/{{ localContractArtifacts "l1" }}/artifact:\/\/l1-artifacts/g' "$target_yaml"
    sed -i '' 's/{{ localContractArtifacts "l2" }}/artifact:\/\/l2-artifacts/g' "$target_yaml"
    sed -i '' 's/{{ localPrestate.Hashes.prestate_mt64 }}/0x038512e02c4c3f7bdaec27d00edf55b7155e0905301e1a88083e4e0a6764d54c/g' "$target_yaml"

    log_success "Template processing completed: $target_yaml"
}

# Prepare Contract Artifacts
prepare_contract_artifacts() {
    log_info "Preparing contract artifacts for deployment..."

    local contracts_dir="$OPTIMISM_ROOT/packages/contracts-bedrock"
    local forge_artifacts_dir="$contracts_dir/forge-artifacts"
    local kurtosis_dir="$KURTOSIS_DEVNET_DIR"

    # Check if forge-artifacts directory exists
    if [ ! -d "$forge_artifacts_dir" ]; then
        log_error "Forge artifacts directory not found: $forge_artifacts_dir"
        log_info "Please build contracts first with:"
        log_info "  cd $contracts_dir && forge build"
        return 1
    fi

    # Create artifacts directories in kurtosis-devnet (for direct file:// mounting)
    local l1_artifacts_dir="$kurtosis_dir/l1-artifacts"
    local l2_artifacts_dir="$kurtosis_dir/l2-artifacts"

    log_info "Creating artifact directories..."
    rm -rf "$l1_artifacts_dir" "$l2_artifacts_dir"  # Clean up existing directories
    mkdir -p "$l1_artifacts_dir"
    mkdir -p "$l2_artifacts_dir"

    # Copy all forge artifacts to both l1-artifacts and l2-artifacts
    # (We copy to both because the op-deployer looks in both locations)
    log_info "Copying forge artifacts..."

    # Copy all .sol directories containing JSON artifacts
    if cp -r "$forge_artifacts_dir"/* "$l1_artifacts_dir/" 2>/dev/null; then
        log_success "✅ L1 artifacts copied successfully"
    else
        log_error "❌ Failed to copy L1 artifacts"
        return 1
    fi

    if cp -r "$forge_artifacts_dir"/* "$l2_artifacts_dir/" 2>/dev/null; then
        log_success "✅ L2 artifacts copied successfully"
    else
        log_error "❌ Failed to copy L2 artifacts"
        return 1
    fi

    # Verify critical artifacts are present
    local critical_artifacts=(
        "DeployImplementations.s.sol/DeployImplementations.json"
        "OptimismPortal2.sol/OptimismPortal2.json"
        "DisputeGameFactory.sol/DisputeGameFactory.json"
        "SystemConfig.sol/SystemConfig.json"
    )

    log_info "Verifying critical artifacts..."
    local missing_artifacts=()

    for artifact in "${critical_artifacts[@]}"; do
        if [ ! -f "$l1_artifacts_dir/$artifact" ]; then
            missing_artifacts+=("$artifact")
        fi
    done

    if [ ${#missing_artifacts[@]} -eq 0 ]; then
        log_success "✅ All critical artifacts verified"

        # Show artifact statistics
        local total_artifacts=$(find "$l1_artifacts_dir" -name "*.json" | wc -l | tr -d ' ')
        log_info "Total artifacts copied: $total_artifacts JSON files"

        # Create Kurtosis-compatible artifact structure for upload
        log_info "Creating Kurtosis files artifacts..."

        # Create tar archives for Kurtosis files artifact system
        local temp_artifacts_dir="$kurtosis_dir/temp-kurtosis-artifacts"
        rm -rf "$temp_artifacts_dir"
        mkdir -p "$temp_artifacts_dir"

        # Create l1-artifacts.tar.gz
        cd "$l1_artifacts_dir"
        tar -czf "$temp_artifacts_dir/l1-artifacts.tar.gz" . 2>/dev/null

        # Create l2-artifacts.tar.gz
        cd "$l2_artifacts_dir"
        tar -czf "$temp_artifacts_dir/l2-artifacts.tar.gz" . 2>/dev/null

        cd "$OPTIMISM_ROOT"  # Return to original directory

        if [ -f "$temp_artifacts_dir/l1-artifacts.tar.gz" ] && [ -f "$temp_artifacts_dir/l2-artifacts.tar.gz" ]; then
            log_success "✅ Kurtosis artifacts created successfully"
            log_info "Artifacts ready for Kurtosis upload:"
            log_info "  - l1-artifacts.tar.gz ($(du -h "$temp_artifacts_dir/l1-artifacts.tar.gz" | cut -f1))"
            log_info "  - l2-artifacts.tar.gz ($(du -h "$temp_artifacts_dir/l2-artifacts.tar.gz" | cut -f1))"

            # Store artifact tar file paths for later upload (will be used by deploy_devnet function)
            echo "$temp_artifacts_dir/l1-artifacts.tar.gz" > "$kurtosis_dir/.l1-artifacts-tar-path"
            echo "$temp_artifacts_dir/l2-artifacts.tar.gz" > "$kurtosis_dir/.l2-artifacts-tar-path"
            # Keep original paths for backward compatibility
            echo "$l1_artifacts_dir" > "$kurtosis_dir/.l1-artifacts-path"
            echo "$l2_artifacts_dir" > "$kurtosis_dir/.l2-artifacts-path"
        else
            log_error "❌ Failed to create Kurtosis artifacts"
            return 1
        fi

        return 0
    else
        log_error "❌ Missing critical artifacts:"
        for missing in "${missing_artifacts[@]}"; do
            log_error "  - $missing"
        done
        return 1
    fi
}

# Create Devnet Configuration
create_devnet_config() {
    log_info "Creating Devnet configuration files..."

    # Process templates from original simple.yaml to create processed version
    local source_yaml="$KURTOSIS_DEVNET_DIR/simple.yaml"
    local processed_yaml="$KURTOSIS_DEVNET_DIR/simple-processed.yaml"

    if [ -f "$source_yaml" ]; then
        process_yaml_templates "$source_yaml" "$processed_yaml"
        log_success "Devnet configuration completed (processed from simple.yaml)"
    else
        log_error "Source YAML not found: $source_yaml"
        return 1
    fi
}

# Verify Services Status (Clear and Accurate)
verify_services() {
    log_step "Verifying Core Services"
    log_info "Step 4/6: Checking devnet core services... (~2-3 minutes)"
    echo "   📊 Checking: L1/L2 chains and core L2 services"

    # Wait for services to stabilize
    log_info "Waiting for services to stabilize... (60 seconds)"
    sleep 60

    local core_running=0
    local total_core=${#CORE_SERVICES[@]}

    # Check L1/L2 chain services
    local chain_services=("el-1-geth-lighthouse" "cl-1-lighthouse-geth" "op-el-*-op-geth" "op-cl-*-op-node")
    log_info "Checking L1/L2 chain services..."
    for pattern in "${chain_services[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "${pattern//\*/.*}"; then
            log_success "✅ Chain service running: $pattern"
        else
            log_warning "⚠️  Chain service not found: $pattern"
        fi
    done

    # Check core L2 services
    log_info "Checking core L2 services..."
    for service in "${CORE_SERVICES[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "$service"; then
            log_success "✅ $service is running"
            ((core_running++))
        else
            log_warning "❌ $service is not running"
        fi
    done

    # Status summary
    log_info "=== Devnet Status Summary ==="
    log_info "Core L2 services: $core_running/$total_core running"

    if [ $core_running -eq $total_core ]; then
        log_success "🎉 Core devnet services running successfully!"
        log_info "✅ Ready for Step 3: ./run-challenger-devnet.sh"
        return 0
    elif [ $core_running -gt 0 ]; then
        log_warning "⚠️  Some core services are not running ($core_running/$total_core)"
        return 0
    else
        log_error "❌ No core services are running"
        return 1
    fi
}



# Verify RPC Connections
verify_rpc_connections() {
    log_step "Verifying RPC Connections"
    log_info "Step 5/6: Testing L1/L2 RPC endpoints... (~1 minute)"
    echo "   🌐 Testing connections to ensure network is accessible"

    # Extract actual port information from Kurtosis enclave
    local l1_port=$(kurtosis enclave inspect $ENCLAVE_NAME | grep "el-1-geth-lighthouse" -A 5 | grep "rpc: 8545/tcp" | sed 's/.*127.0.0.1:\([0-9]*\).*/\1/')
    local l2_port=$(kurtosis enclave inspect $ENCLAVE_NAME | grep "op-el.*op-geth" -A 5 | grep "rpc: 8545/tcp" | sed 's/.*127.0.0.1:\([0-9]*\).*/\1/')

    # Fallback to default ports if extraction fails
    [ -z "$l1_port" ] && l1_port="53620"
    [ -z "$l2_port" ] && l2_port="56781"

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
    log_step "Step 6/6: Devnet Ready!"
    log_success "🎉 Core devnet services running successfully!"
    echo "   ⏱️  Total deployment time: Complete!"

    echo
    echo "=== Connection Information ==="

    # Extract actual port information
    local l1_port=$(kurtosis enclave inspect $ENCLAVE_NAME | grep "el-1-geth-lighthouse" -A 5 | grep "rpc: 8545/tcp" | sed 's/.*127.0.0.1:\([0-9]*\).*/\1/')
    local l2_port=$(kurtosis enclave inspect $ENCLAVE_NAME | grep "op-el.*op-geth" -A 5 | grep "rpc: 8545/tcp" | sed 's/.*127.0.0.1:\([0-9]*\).*/\1/')
    local l2_rollup_port=$(kurtosis enclave inspect $ENCLAVE_NAME | grep "op-cl.*op-node" -A 5 | grep "rpc: 8547/tcp" | sed 's/.*127.0.0.1:\([0-9]*\).*/\1/')

    # Display actual connection information
    echo "L1 RPC: http://localhost:${l1_port:-53620}"
    echo "L2 RPC: http://localhost:${l2_port:-56781}"
    echo "Rollup RPC: http://localhost:${l2_rollup_port:-57029}"
    echo

    echo "=== Devnet Management Commands ==="
    echo "Check Devnet status: kurtosis enclave inspect $ENCLAVE_NAME"
    echo "Stop Devnet: kurtosis enclave rm --force $ENCLAVE_NAME"
    echo "Check Devnet logs: kurtosis enclave logs $ENCLAVE_NAME"
    echo "Check build logs: cat $BUILD_LOG"
    echo

    echo "=== Next Steps ==="
    log_success "✅ Ready for Step 3: Run challenger with ./run-challenger-devnet.sh"
    echo "cd $SCRIPT_DIR"
    echo "./run-challenger-devnet.sh"
    echo
}

# Main Function
main() {
    # Parse command line arguments first
    parse_arguments "$@"

    # If GAME_TYPE not set via command line, read from simple.yaml
    if [ -z "$GAME_TYPE" ]; then
        if [ -f "$KURTOSIS_DEVNET_DIR/simple.yaml" ]; then
            GAME_TYPE=$(grep "game_type:" "$KURTOSIS_DEVNET_DIR/simple.yaml" | sed 's/.*game_type: *\([0-9]*\).*/\1/')
            log_info "Reading game_type from simple.yaml: $GAME_TYPE"
        else
            GAME_TYPE=1  # Default fallback
            log_warning "simple.yaml not found, using default game_type: $GAME_TYPE"
        fi
    fi

    # Validate game type
    case $GAME_TYPE in
        0) log_info "Using CANNON game type (requires cannon binaries)" ;;
        1) log_info "Using PERMISSIONED game type (development mode)" ;;
        2) log_info "Using ASTERISC game type (requires asterisc binaries)" ;;
        *)
            log_error "Invalid game type: $GAME_TYPE"
            exit 1
            ;;
    esac

    echo "=========================================="
    echo "Challenger Network - Devnet Builder"
    echo "Optimism Sequencer System Improvement Project"
    echo "=========================================="
    echo
    echo "Configuration:"
    echo "  Game Type: $GAME_TYPE"
    case $GAME_TYPE in
        0) echo "  Mode: CANNON (Complete fault proof)" ;;
        1) echo "  Mode: PERMISSIONED (Development)" ;;
        2) echo "  Mode: ASTERISC (Asterisc VM)" ;;
    esac
    echo

    # Execute each step
    init
    check_requirements
    build_docker_images
    prepare_contract_artifacts
    deploy_devnet
    verify_services
    verify_rpc_connections
    show_completion_message
}

# Create temporary YAML with modified game_type
create_temp_yaml() {
    log_step "Creating temporary configuration with game_type=$GAME_TYPE" >&2

    local source_yaml="$KURTOSIS_DEVNET_DIR/simple.yaml"
    local temp_yaml="/tmp/simple-temp-$$.yaml"

    if [ ! -f "$source_yaml" ]; then
        log_error "Source YAML not found: $source_yaml" >&2
        exit 1
    fi

    # Create temporary YAML with modified game_type
    sed "s/game_type: [0-9]*/game_type: $GAME_TYPE/g" "$source_yaml" > "$temp_yaml"

    # Verify the modification
    local modified_game_type=$(grep "game_type:" "$temp_yaml" | sed 's/.*game_type: *\([0-9]*\).*/\1/')
    if [ "$modified_game_type" != "$GAME_TYPE" ]; then
        log_error "Failed to modify game_type in YAML" >&2
        log_error "Expected: $GAME_TYPE, Got: $modified_game_type" >&2
        rm -f "$temp_yaml"
        exit 1
    fi

    log_success "Temporary YAML created: $temp_yaml" >&2
    log_success "Game type set to: $GAME_TYPE" >&2

    # Return only the file path (no other output)
    printf "%s" "$temp_yaml"
}

# Cleanup function
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/simple-temp-*.yaml
}

# Execute Script
trap cleanup_temp_files EXIT
main "$@"