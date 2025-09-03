#!/bin/bash

# Build Contract Artifacts Script
# Compiles contracts and creates contract-artifacts folder structure

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Get script directory and paths
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
OPTIMISM_ROOT="$(realpath "$SCRIPT_DIR/../..")"
CONTRACTS_DIR="$OPTIMISM_ROOT/packages/contracts-bedrock"
CONTRACT_ARTIFACTS_DIR="$SCRIPT_DIR/contract-artifacts"
KURTOSIS_DEVNET_DIR="$OPTIMISM_ROOT/kurtosis-devnet"

echo "=========================================="
echo "Contract Artifacts Builder"
echo "Building local contract artifacts for devnet"
echo "=========================================="
echo

log_info "Paths:"
log_info "  Script directory: $SCRIPT_DIR"
log_info "  Optimism root: $OPTIMISM_ROOT"
log_info "  Contracts directory: $CONTRACTS_DIR"
log_info "  Contract artifacts output: $CONTRACT_ARTIFACTS_DIR"
log_info "  Kurtosis devnet directory: $KURTOSIS_DEVNET_DIR"
echo

# Check if contracts directory exists
if [ ! -d "$CONTRACTS_DIR" ]; then
    log_error "Contracts directory not found: $CONTRACTS_DIR"
    exit 1
fi

# Check if forge is available
if ! command -v forge &> /dev/null; then
    log_error "Forge not found. Please install Foundry first:"
    log_info "  curl -L https://foundry.paradigm.xyz | bash"
    log_info "  foundryup"
    exit 1
fi

log_success "All prerequisites found"
echo

# Clean and create contract-artifacts directory structure
# log_info "Setting up contract-artifacts directory structure..."
# if [ -d "$CONTRACT_ARTIFACTS_DIR" ]; then
#     rm -rf "$CONTRACT_ARTIFACTS_DIR"
#     log_info "Removed old contract-artifacts directory"
# fi

mkdir -p "$CONTRACT_ARTIFACTS_DIR"
mkdir -p "$CONTRACT_ARTIFACTS_DIR/cache"
mkdir -p "$CONTRACT_ARTIFACTS_DIR/forge-artifacts"
mkdir -p "$CONTRACT_ARTIFACTS_DIR/artifacts"

log_success "Created contract-artifacts directory structure"
echo

# # Clean previous build artifacts in contracts directory
# log_info "Cleaning previous build artifacts..."
# cd "$CONTRACTS_DIR"
# if [ -d "out" ]; then
#     rm -rf out
#     log_success "Removed old 'out' directory"
# fi
# if [ -d "forge-artifacts" ]; then
#     rm -rf forge-artifacts
#     log_success "Removed old 'forge-artifacts' directory"
# fi
# if [ -d "cache" ]; then
#     rm -rf cache
#     log_success "Removed old 'cache' directory"
# fi

# # Build contracts
# log_info "Building contracts with forge..."
# cd "$CONTRACTS_DIR"
# forge build

# if [ $? -eq 0 ]; then
#     log_success "Contract compilation completed successfully"
# else
#     log_error "Contract compilation failed"
#     exit 1
# fi
# echo

# Copy compiled artifacts to contract-artifacts structure
log_info "Copying compiled artifacts..."

# Copy cache if it exists
if [ -d "$CONTRACTS_DIR/cache" ]; then
    cp -r "$CONTRACTS_DIR/cache/"* "$CONTRACT_ARTIFACTS_DIR/cache/"
    log_success "Copied cache directory"
fi

# Copy build output (forge-artifacts)
if [ -d "$CONTRACTS_DIR/forge-artifacts" ] && [ "$(ls -A "$CONTRACTS_DIR/forge-artifacts" 2>/dev/null)" ]; then
    cp -r "$CONTRACTS_DIR/forge-artifacts/"* "$CONTRACT_ARTIFACTS_DIR/forge-artifacts/"
    log_success "Copied forge build output from 'forge-artifacts' directory"
else
    log_error "No contract artifacts found in 'forge-artifacts' directory"
    exit 1
fi

# Copy additional artifacts to artifacts folder (if any)
cp -r "$CONTRACTS_DIR/artifacts/"* "$CONTRACT_ARTIFACTS_DIR/artifacts/"
log_success "Created artifacts directory copy"

# Get git commit info
cd "$OPTIMISM_ROOT"
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_DATE=$(git show -s --format='%ct' 2>/dev/null || echo "unknown")

# Create COMMIT file (similar to official artifacts)
echo "$GIT_COMMIT" > "$CONTRACT_ARTIFACTS_DIR/COMMIT"
log_success "Created COMMIT file with: $GIT_COMMIT"

# Create metadata file
cat > "$CONTRACT_ARTIFACTS_DIR/metadata.json" << EOF
{
  "build_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "git_commit": "$GIT_COMMIT",
  "git_date": "$GIT_DATE",
  "optimism_root": "$OPTIMISM_ROOT",
  "contracts_dir": "$CONTRACTS_DIR"
}
EOF

log_success "Created metadata file"
echo

# Show directory structure
log_info "Contract artifacts directory structure:"
ls -la "$CONTRACT_ARTIFACTS_DIR"
echo

# Create compressed tarball and move to kurtosis-devnet
log_info "Creating compressed tarball..."
cd "$SCRIPT_DIR"
tar -czf contract-artifacts.tar.gz contract-artifacts/

if [ $? -eq 0 ] && [ -f "contract-artifacts.tar.gz" ]; then
    TARBALL_SIZE=$(ls -lh contract-artifacts.tar.gz | awk '{print $5}')
    log_success "Tarball created successfully (Size: $TARBALL_SIZE)"
else
    log_error "Failed to create tarball"
    exit 1
fi

# Move to kurtosis-devnet directory
log_info "Moving tarball to kurtosis-devnet directory..."
if [ -f "$KURTOSIS_DEVNET_DIR/contract-artifacts.tar.gz" ]; then
    rm -f "$KURTOSIS_DEVNET_DIR/contract-artifacts.tar.gz"
    log_info "Removed old tarball from kurtosis-devnet"
fi

mv contract-artifacts.tar.gz "$KURTOSIS_DEVNET_DIR/"

if [ -f "$KURTOSIS_DEVNET_DIR/contract-artifacts.tar.gz" ]; then
    log_success "Tarball moved to kurtosis-devnet directory"
else
    log_error "Failed to move tarball to kurtosis-devnet directory"
    exit 1
fi

echo
echo "=========================================="
log_success "Contract artifacts build completed!"
echo
log_info "Generated files:"
log_info "  Contract artifacts folder: $CONTRACT_ARTIFACTS_DIR"
log_info "  Compressed tarball: $KURTOSIS_DEVNET_DIR/contract-artifacts.tar.gz"
echo
log_info "Next steps:"
log_info "  1. The contract-artifacts.tar.gz is ready for devnet deployment"
log_info "  2. Run devnet build:"
log_info "     cd $OPTIMISM_ROOT/op-challenger/scripts"
log_info "     ./build-devnet.sh --game-type=0"
echo
log_info "This tarball includes:"
log_info "  - cache/: Forge compilation cache"
log_info "  - forge-artifacts/: Compiled contract artifacts"
log_info "  - artifacts/: Additional contract artifacts"
log_info "  - metadata.json: Build information"
log_info "  - All local modifications including TestContract.sol"
echo "=========================================="