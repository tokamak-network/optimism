#!/bin/bash

# Binary Build and Check Script
# Automatically builds required binaries for op-challenger

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

# Help Function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Build required binaries for op-challenger"
    echo
    echo "OPTIONS:"
    echo "  --force         Force rebuild even if binaries exist"
    echo "  --asterisc      Build ASTERISC VM assets (GameType 2)"
    echo "  --kona          Build Kona assets (GameType 3)"
    echo "  -h, --help      Show this help message"
    echo
    echo "EXAMPLES:"
    echo "  $0              # Build only if binaries don't exist"
    echo "  $0 --force      # Force rebuild all binaries"
    echo "  $0 --asterisc   # Ensure ASTERISC binaries/prestates exist"
    echo "  $0 --kona       # Ensure Kona binaries/prestates exist"
    echo "  $0 --force --asterisc --kona  # Rebuild everything"
    echo
}

# Parse Command Line Arguments
FORCE_BUILD=false
BUILD_ASTERISC=false
BUILD_KONA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD=true
            log_info "Force rebuild enabled"
            shift
            ;;
        --asterisc)
            BUILD_ASTERISC=true
            log_info "ASTERISC build enabled"
            shift
            ;;
        --kona)
            BUILD_KONA=true
            log_info "Kona build enabled"
            shift
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
done

# Script Information
echo "=========================================="
echo "OP-Challenger Binary Builder"
echo "Builds required binaries for challenger"
if [ "$FORCE_BUILD" = true ]; then
    echo "Mode: Force Rebuild"
else
    echo "Mode: Build if Missing"
fi
echo "=========================================="
echo

# 기본 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTIMISM_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

log_info "Optimism root: $OPTIMISM_ROOT"
DEFAULT_ASTERISC_DIR="$(dirname "$OPTIMISM_ROOT")/asterisc"
ASTERISC_SOURCE_DIR="${ASTERISC_DIR:-$DEFAULT_ASTERISC_DIR}"
ASTERISC_TARGET_DIR="$OPTIMISM_ROOT/asterisc/bin"
OP_PROGRAM_TARGET_DIR="$OPTIMISM_ROOT/op-program/bin"

# Kona directory configuration
DEFAULT_KONA_DIR="$(dirname "$OPTIMISM_ROOT")/kona"
KONA_SOURCE_DIR="${KONA_DIR:-$DEFAULT_KONA_DIR}"
KONA_TARGET_DIR="$OPTIMISM_ROOT/kona/bin"

# Build cannon binary
build_cannon() {
    log_info "Building cannon binary..."

    cd "$OPTIMISM_ROOT/cannon"

    if [ ! -f "Makefile" ]; then
        log_error "Makefile not found in cannon directory"
        return 1
    fi

    log_info "Running: make cannon"
    if make cannon; then
        log_success "✅ cannon binary built successfully"
        return 0
    else
        log_error "❌ Failed to build cannon binary"
        return 1
    fi
}

# Build op-program binary
build_op_program() {
    log_info "Building op-program binary..."

    cd "$OPTIMISM_ROOT/op-program"

    if [ ! -f "Makefile" ]; then
        log_error "Makefile not found in op-program directory"
        return 1
    fi

    log_info "Running: make op-program"
    if make op-program; then
        log_success "✅ op-program binary built successfully"

        # Generate prestate files
        log_info "Running: make reproducible-prestate"
        if make reproducible-prestate; then
            log_success "✅ prestate files generated successfully"

            # Rename prestate file for challenger compatibility
            log_info "Renaming prestate file for challenger compatibility..."
            cd "$OPTIMISM_ROOT/op-program/bin"

            # Rename MT64 prestate file to standard name
            if [ -f "prestate-mt64.bin.gz" ]; then
                mv prestate-mt64.bin.gz prestate.bin.gz
                log_success "✅ Renamed prestate-mt64.bin.gz -> prestate.bin.gz"
            elif [ -f "prestate-mt64Next.bin.gz" ]; then
                mv prestate-mt64Next.bin.gz prestate.bin.gz
                log_success "✅ Renamed prestate-mt64Next.bin.gz -> prestate.bin.gz"
            else
                log_warning "⚠️  No MT64 prestate file found for renaming"
            fi
        else
            log_warning "⚠️  Failed to generate prestate files, but continuing"
        fi

        return 0
    else
        log_error "❌ Failed to build op-program binary"
        return 1
    fi
}

ensure_asterisc_repo() {
    if [ ! -d "$ASTERISC_SOURCE_DIR" ]; then
        log_error "ASTERISC repository not found."
        log_error "Expected path: $ASTERISC_SOURCE_DIR"
        log_error "Clone it with:"
        log_error "  cd $(dirname "$OPTIMISM_ROOT") && git clone https://github.com/ethereum-optimism/asterisc.git"
        log_error "Or set ASTERISC_DIR to the repository path."
        return 1
    fi

    if [ ! -f "$ASTERISC_SOURCE_DIR/Makefile" ]; then
        log_error "Makefile not found in $ASTERISC_SOURCE_DIR"
        return 1
    fi

    return 0
}

generate_prestate_proof_if_missing() {
    local prestate_json="$1"
    local prestate_proof="$2"

    if [ -f "$prestate_proof" ]; then
        return 0
    fi

    if [ ! -f "$prestate_json" ]; then
        log_warning "⚠️  prestate.json not found at $prestate_json; cannot generate prestate-proof.json"
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        state_hash=$(jq -r '.stateHash // empty' "$prestate_json")
    else
        if command -v python3 >/dev/null 2>&1; then
            state_hash=$(python3 - <<'PY'
import json,sys
with open(sys.argv[1]) as f:
    data=json.load(f)
print(data.get("stateHash",""))
PY
 "$prestate_json")
        else
            log_warning "⚠️  Neither jq nor python3 found; cannot derive state hash"
            return 1
        fi
    fi

    if [ -z "$state_hash" ]; then
        log_warning "⚠️  Unable to extract stateHash from $prestate_json"
        return 1
    fi

    printf '{ "pre": "%s" }\n' "$state_hash" > "$prestate_proof"
    log_success "✅ Generated $prestate_proof from prestate.json"
    return 0
}

build_asterisc() {
    log_info "Building ASTERISC VM (GameType 2)..."

    if ! ensure_asterisc_repo; then
        return 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required to build ASTERISC assets. Please install/start Docker."
        return 1
    fi

    log_info "Using ASTERISC repo at: $ASTERISC_SOURCE_DIR"
    cd "$ASTERISC_SOURCE_DIR"

    log_info "Running: make reproducible-prestate"
    if ! make reproducible-prestate; then
        log_error "❌ Failed to build ASTERISC via make reproducible-prestate"
        return 1
    fi

    local source_bin_dir="$ASTERISC_SOURCE_DIR/bin"
    local source_vm="$source_bin_dir/asterisc"
    local source_prestate_json="$source_bin_dir/prestate.json"
    local source_prestate_proof="$source_bin_dir/prestate-proof.json"
    local source_prestate_bin="$source_bin_dir/prestate.bin.gz"

    if [ ! -f "$source_vm" ]; then
        log_error "ASTERISC binary not found at $source_vm"
        return 1
    fi

    mkdir -p "$ASTERISC_TARGET_DIR"
    mkdir -p "$OP_PROGRAM_TARGET_DIR"

    cp "$source_vm" "$ASTERISC_TARGET_DIR/asterisc"
    chmod +x "$ASTERISC_TARGET_DIR/asterisc"
    log_success "✅ Copied ASTERISC binary to $ASTERISC_TARGET_DIR/asterisc"

    if generate_prestate_proof_if_missing "$source_prestate_json" "$source_prestate_proof"; then
        cp "$source_prestate_proof" "$ASTERISC_TARGET_DIR/prestate-proof.json"
        cp "$source_prestate_proof" "$OP_PROGRAM_TARGET_DIR/prestate-asterisc.json"
        log_success "✅ Copied prestate proof to local directories"
    else
        log_warning "⚠️  Skipping prestate proof copy due to generation failure"
    fi

    if [ -f "$source_prestate_bin" ]; then
        cp "$source_prestate_bin" "$OP_PROGRAM_TARGET_DIR/prestate-asterisc.bin.gz"
        log_success "✅ Copied ASTERISC prestate archive to op-program/bin/prestate-asterisc.bin.gz"
    else
        log_warning "⚠️  ASTERISC prestate.bin.gz not found; some workflows may require it"
    fi

    return 0
}

# Build Kona assets (GameType 3)
build_kona() {
    log_info "Building Kona VM (GameType 3)..."

    # Check if kona repository exists, clone if needed
    if [ ! -d "$KONA_SOURCE_DIR" ]; then
        log_warning "Kona repository not found at: $KONA_SOURCE_DIR"
        log_info "Cloning kona repository..."

        local parent_dir="$(dirname "$OPTIMISM_ROOT")"
        cd "$parent_dir"

        if git clone --depth 1 https://github.com/op-rs/kona.git; then
            log_success "✅ Kona repository cloned successfully"
            KONA_SOURCE_DIR="${parent_dir}/kona"
        else
            log_error "❌ Failed to clone kona repository"
            log_error "Please clone it manually:"
            log_error "  cd $(dirname "$OPTIMISM_ROOT") && git clone https://github.com/op-rs/kona.git"
            return 1
        fi
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required to build Kona assets. Please install/start Docker."
        return 1
    fi

    log_info "Using Kona repo at: $KONA_SOURCE_DIR"
    cd "$KONA_SOURCE_DIR"

    # Check for kona's official Dockerfile
    local dockerfile_path="docker/fpvm-prestates/asterisc-repro.dockerfile"
    if [ ! -f "$dockerfile_path" ]; then
        log_error "Kona's official dockerfile not found: $dockerfile_path"
        return 1
    fi

    log_info "Using kona's official prestate generation system..."
    log_info "  Dockerfile: $dockerfile_path"
    log_info "  This builds: asterisc + kona-client + prestate files"
    echo

    # Build arguments for kona's Dockerfile
    local ASTERISC_TAG="${ASTERISC_TAG:-master}"
    local CLIENT_BIN="${CLIENT_BIN:-kona-client}"
    local CLIENT_TAG="${CLIENT_TAG:-main}"
    local IMAGE_TAG="kona-prestate:local"

    log_info "Build arguments:"
    log_info "  ASTERISC_TAG=$ASTERISC_TAG"
    log_info "  CLIENT_BIN=$CLIENT_BIN"
    log_info "  CLIENT_TAG=$CLIENT_TAG"
    echo

    log_info "Running Docker build for kona (may take 15-20 minutes)..."
    if ! docker build --platform linux/amd64 \
        --build-arg ASTERISC_TAG="$ASTERISC_TAG" \
        --build-arg CLIENT_BIN="$CLIENT_BIN" \
        --build-arg CLIENT_TAG="$CLIENT_TAG" \
        -f "$dockerfile_path" -t "$IMAGE_TAG" .; then
        log_error "❌ Failed to build Kona via Docker"
        return 1
    fi

    log_success "✅ Kona image built successfully"

    # Extract prestate files from Docker image
    log_info "Extracting prestate files from Docker image..."
    local container_id=$(docker create "$IMAGE_TAG" true 2>/dev/null)

    if [ -z "$container_id" ]; then
        log_error "Failed to create temporary container from image"
        return 1
    fi

    mkdir -p "$KONA_TARGET_DIR"
    mkdir -p "$OP_PROGRAM_TARGET_DIR"

    # Extract prestate-proof.json (deployment format)
    if docker cp "${container_id}:/prestate-proof.json" "$OP_PROGRAM_TARGET_DIR/prestate-kona.json" 2>/dev/null; then
        log_success "✅ prestate-kona.json extracted (deployment format)"

        # Display hash if jq or python3 is available
        if command -v jq >/dev/null 2>&1; then
            local kona_hash=$(jq -r '.pre' "$OP_PROGRAM_TARGET_DIR/prestate-kona.json" 2>/dev/null)
            if [ -n "$kona_hash" ] && [ "$kona_hash" != "null" ]; then
                log_success "  Kona prestate hash: ${kona_hash:0:10}...${kona_hash: -8}"
            fi
        elif command -v python3 >/dev/null 2>&1; then
            local kona_hash=$(python3 -c "import json; print(json.load(open('$OP_PROGRAM_TARGET_DIR/prestate-kona.json')).get('pre', ''))" 2>/dev/null)
            if [ -n "$kona_hash" ]; then
                log_success "  Kona prestate hash: ${kona_hash:0:10}...${kona_hash: -8}"
            fi
        fi
    else
        log_warning "⚠️  prestate-proof.json not found in image"
    fi

    # Extract prestate.bin.gz (runtime format)
    if docker cp "${container_id}:/prestate.bin.gz" "$OP_PROGRAM_TARGET_DIR/prestate-kona.bin.gz" 2>/dev/null; then
        log_success "✅ prestate-kona.bin.gz extracted (runtime format)"
    else
        log_warning "⚠️  prestate.bin.gz not found in image"
        log_warning "      GameType 3 may not work properly without this file"
    fi

    # Extract kona-client binary
    if docker cp "${container_id}:/kona-client-elf" "$KONA_TARGET_DIR/kona-client" 2>/dev/null; then
        chmod +x "$KONA_TARGET_DIR/kona-client"
        log_success "✅ kona-client binary extracted"
    else
        log_warning "⚠️  kona-client binary not found in image"
    fi

    # Cleanup
    docker rm "$container_id" >/dev/null 2>&1

    return 0
}

# Main function
main() {
    local need_cannon=false
    local need_op_program=false
    local need_asterisc=false
    local need_kona=false

    log_info "Checking required binary files..."

    # Check binaries (or force rebuild)
    if [ "$FORCE_BUILD" = true ] || [ ! -f "$OPTIMISM_ROOT/cannon/bin/cannon" ]; then
        if [ "$FORCE_BUILD" = true ] && [ -f "$OPTIMISM_ROOT/cannon/bin/cannon" ]; then
            log_info "🔄 cannon binary exists but forcing rebuild"
        else
            log_warning "❌ cannon binary not found"
        fi
        need_cannon=true
    else
        log_success "✅ cannon binary found"
    fi

    if [ "$FORCE_BUILD" = true ] || [ ! -f "$OPTIMISM_ROOT/op-program/bin/op-program" ] || [ ! -f "$OPTIMISM_ROOT/op-program/bin/prestate.bin.gz" ]; then
        if [ "$FORCE_BUILD" = true ]; then
            log_info "🔄 op-program/prestate exists but forcing rebuild"
        else
            if [ ! -f "$OPTIMISM_ROOT/op-program/bin/op-program" ]; then
                log_warning "❌ op-program binary not found"
            fi
            if [ ! -f "$OPTIMISM_ROOT/op-program/bin/prestate.bin.gz" ]; then
                log_warning "❌ prestate.bin.gz file not found"
            fi
        fi
        need_op_program=true
    else
        log_success "✅ op-program binary found"
        log_success "✅ prestate file found"
    fi

    if [ "$BUILD_ASTERISC" = true ]; then
        if [ "$FORCE_BUILD" = true ] || [ ! -f "$ASTERISC_TARGET_DIR/asterisc" ] || [ ! -f "$OP_PROGRAM_TARGET_DIR/prestate-asterisc.json" ]; then
            if [ "$FORCE_BUILD" = true ] && [ -f "$ASTERISC_TARGET_DIR/asterisc" ]; then
                log_info "🔄 ASTERISC assets exist but forcing rebuild"
            else
                if [ ! -f "$ASTERISC_TARGET_DIR/asterisc" ]; then
                    log_warning "❌ ASTERISC binary not found at $ASTERISC_TARGET_DIR/asterisc"
                fi
                if [ ! -f "$OP_PROGRAM_TARGET_DIR/prestate-asterisc.json" ]; then
                    log_warning "❌ ASTERISC prestate proof not found at $OP_PROGRAM_TARGET_DIR/prestate-asterisc.json"
                fi
            fi
            need_asterisc=true
        else
            log_success "✅ ASTERISC binary found"
            log_success "✅ ASTERISC prestate proof found"
        fi
    fi

    if [ "$BUILD_KONA" = true ]; then
        if [ "$FORCE_BUILD" = true ] || [ ! -f "$KONA_TARGET_DIR/kona-client" ] || [ ! -f "$OP_PROGRAM_TARGET_DIR/prestate-kona.json" ]; then
            if [ "$FORCE_BUILD" = true ] && [ -f "$KONA_TARGET_DIR/kona-client" ]; then
                log_info "🔄 Kona assets exist but forcing rebuild"
            else
                if [ ! -f "$KONA_TARGET_DIR/kona-client" ]; then
                    log_warning "❌ Kona client binary not found at $KONA_TARGET_DIR/kona-client"
                fi
                if [ ! -f "$OP_PROGRAM_TARGET_DIR/prestate-kona.json" ]; then
                    log_warning "❌ Kona prestate proof not found at $OP_PROGRAM_TARGET_DIR/prestate-kona.json"
                fi
            fi
            need_kona=true
        else
            log_success "✅ Kona client binary found"
            log_success "✅ Kona prestate proof found"
        fi
    fi

    # Build if needed
    if [ "$need_cannon" = false ] && [ "$need_op_program" = false ] && [ "$need_asterisc" = false ] && [ "$need_kona" = false ]; then
        log_success "🎉 All required binaries are already built!"
        return 0
    fi

    echo
    log_info "Building missing binaries..."

    if [ "$need_cannon" = true ]; then
        if ! build_cannon; then
            exit 1
        fi
    fi

    if [ "$need_op_program" = true ]; then
        if ! build_op_program; then
            exit 1
        fi
    fi

    if [ "$need_asterisc" = true ]; then
        if ! build_asterisc; then
            exit 1
        fi
    fi

    if [ "$need_kona" = true ]; then
        if ! build_kona; then
            exit 1
        fi
    fi

    log_success "🎉 All required binaries are now ready!"
}

# Execute Script
main "$@"