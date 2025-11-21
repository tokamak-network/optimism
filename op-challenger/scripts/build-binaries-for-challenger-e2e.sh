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
    echo "  --kona          Build Kona-Host assets (GameType 3)"
    echo "  -h, --help      Show this help message"
    echo
    echo "EXAMPLES:"
    echo "  $0              # Build only if binaries don't exist"
    echo "  $0 --force      # Force rebuild all binaries"
    echo "  $0 --asterisc   # Ensure ASTERISC binaries/prestates exist"
    echo "  $0 --kona       # Ensure Kona-Host binary exists"
    echo "  $0 --force --asterisc --kona  # Rebuild everything including ASTERISC and Kona"
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
            log_info "Kona-Host build enabled"
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

DEFAULT_KONA_DIR="$(dirname "$OPTIMISM_ROOT")/kona"
KONA_SOURCE_DIR="${KONA_DIR:-$DEFAULT_KONA_DIR}"

# E2E 전용 bin-e2e 디렉토리 사용
ASTERISC_TARGET_DIR="$OPTIMISM_ROOT/asterisc/bin-e2e"
OP_PROGRAM_TARGET_DIR="$OPTIMISM_ROOT/op-program/bin-e2e"
CANNON_TARGET_DIR="$OPTIMISM_ROOT/cannon/bin-e2e"
KONA_TARGET_DIR="$OPTIMISM_ROOT/kona/bin-e2e"

# Build cannon binary
build_cannon() {
    log_info "Building cannon binary for E2E (Mac native)..."

    cd "$OPTIMISM_ROOT/cannon"

    if [ ! -f "Makefile" ]; then
        log_error "Makefile not found in cannon directory"
        return 1
    fi

    log_info "Running: make cannon"
    if make cannon; then
        # E2E 전용 폴더에 복사
        mkdir -p "$CANNON_TARGET_DIR"
        cp bin/cannon "$CANNON_TARGET_DIR/"
        log_success "✅ cannon binary built and copied to $CANNON_TARGET_DIR"
        return 0
    else
        log_error "❌ Failed to build cannon binary"
        return 1
    fi
}

# Build op-program binary
build_op_program() {
    log_info "Building op-program binary for E2E..."

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

            # E2E 전용 폴더에 복사
            mkdir -p "$OP_PROGRAM_TARGET_DIR"
            cp bin/op-program "$OP_PROGRAM_TARGET_DIR/"

            # Copy prestate files to E2E directory
            log_info "Copying prestate files to E2E directory..."

            # Copy all variant-specific prestate files
            if [ -f "bin/prestate-mt64.bin.gz" ]; then
                cp bin/prestate-mt64.bin.gz "$OP_PROGRAM_TARGET_DIR/prestate-mt64.bin.gz"
                cp bin/prestate-mt64.bin.gz "$OP_PROGRAM_TARGET_DIR/prestate.bin.gz"
                log_success "✅ Copied prestate-mt64.bin.gz to E2E directory (both names)"
            fi

            if [ -f "bin/prestate-mt64Next.bin.gz" ]; then
                cp bin/prestate-mt64Next.bin.gz "$OP_PROGRAM_TARGET_DIR/prestate-mt64Next.bin.gz"
                log_success "✅ Copied prestate-mt64Next.bin.gz to E2E directory"
            fi

            # Warn if no prestate files found
            if [ ! -f "bin/prestate-mt64.bin.gz" ] && [ ! -f "bin/prestate-mt64Next.bin.gz" ]; then
                log_warning "⚠️  No MT64 prestate files found"
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
    log_info "Building ASTERISC VM for Mac (GameType 2 - E2E Testing)..."

    if ! ensure_asterisc_repo; then
        return 1
    fi

    log_info "Using ASTERISC repo at: $ASTERISC_SOURCE_DIR"
    cd "$ASTERISC_SOURCE_DIR/rvgo"

    log_info "Running: make build (Mac native binary)"
    if ! make build; then
        log_error "❌ Failed to build ASTERISC via make build"
        return 1
    fi

    log_info "Running: make prestate (with MONOREPO_ROOT=$OPTIMISM_ROOT)"
    cd "$ASTERISC_SOURCE_DIR"
    if ! make prestate MONOREPO_ROOT="$OPTIMISM_ROOT"; then
        log_error "❌ Failed to build ASTERISC prestate"
        return 1
    fi
    log_success "✅ Built ASTERISC prestate with latest op-program code"

    local source_bin_dir="$ASTERISC_SOURCE_DIR/rvgo/bin"
    local source_vm="$source_bin_dir/asterisc"
    local source_prestate_json="$source_bin_dir/prestate.json"
    local source_prestate_proof="$source_bin_dir/prestate-proof.json"
    local source_prestate_bin="$source_bin_dir/prestate.bin.gz"

    if [ ! -f "$source_vm" ]; then
        log_error "ASTERISC binary not found at $source_vm"
        return 1
    fi

    # Verify it's Mac-native
    file_output=$(file "$source_vm" 2>/dev/null || echo "unknown")
    if [[ "$file_output" == *"Mach-O"* ]] || [[ "$file_output" == *"arm64"* ]] || [[ "$file_output" == *"x86_64"* ]]; then
        log_success "✅ Built Mac-native ASTERISC binary"
    else
        log_warning "⚠️  Binary may not be Mac-native: $file_output"
    fi

    mkdir -p "$ASTERISC_TARGET_DIR"
    mkdir -p "$OP_PROGRAM_TARGET_DIR"

    cp "$source_vm" "$ASTERISC_TARGET_DIR/asterisc"
    chmod +x "$ASTERISC_TARGET_DIR/asterisc"
    log_success "✅ Copied ASTERISC binary to $ASTERISC_TARGET_DIR/asterisc"

    if generate_prestate_proof_if_missing "$source_prestate_json" "$source_prestate_proof"; then
        cp "$source_prestate_proof" "$ASTERISC_TARGET_DIR/prestate-proof.json"
        cp "$source_prestate_proof" "$OP_PROGRAM_TARGET_DIR/prestate-asterisc.json"
        log_success "✅ Copied prestate proof to E2E directories"
    else
        log_warning "⚠️  Skipping prestate proof copy due to generation failure"
    fi

    if [ -f "$source_prestate_json" ]; then
        cp "$source_prestate_json" "$ASTERISC_TARGET_DIR/prestate.json"
        log_success "✅ Copied prestate.json to E2E directory"
    fi

    if [ -f "$source_prestate_bin" ]; then
        cp "$source_prestate_bin" "$OP_PROGRAM_TARGET_DIR/prestate-asterisc.bin.gz"
        log_success "✅ Copied ASTERISC prestate archive to $OP_PROGRAM_TARGET_DIR/prestate-asterisc.bin.gz"
    else
        log_warning "⚠️  ASTERISC prestate.bin.gz not found; some workflows may require it"
    fi

    return 0
}

ensure_kona_repo() {
    if [ ! -d "$KONA_SOURCE_DIR" ]; then
        log_error "Kona repository not found."
        log_error "Expected path: $KONA_SOURCE_DIR"
        log_error "Clone it with:"
        log_error "  cd $(dirname "$OPTIMISM_ROOT") && git clone https://github.com/ethereum-optimism/kona.git"
        log_error "Or set KONA_DIR to the repository path."
        return 1
    fi

    if [ ! -f "$KONA_SOURCE_DIR/Cargo.toml" ]; then
        log_error "Cargo.toml not found in $KONA_SOURCE_DIR"
        return 1
    fi

    return 0
}

build_kona() {
    log_info "Building Kona for Mac (GameType 3 - E2E Testing)..."

    if ! ensure_kona_repo; then
        return 1
    fi

    log_info "Using Kona repo at: $KONA_SOURCE_DIR"
    cd "$KONA_SOURCE_DIR"

    # Check if cargo is installed
    if ! command -v cargo &> /dev/null; then
        log_error "cargo command not found. Please install Rust:"
        log_error "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        return 1
    fi

    # Check and install Rust 1.88 if needed (kona requires 1.88 per rust-toolchain.toml)
    log_info "Checking Rust 1.88 installation..."
    if ! rustup toolchain list | grep -q "1.88"; then
        log_info "Installing Rust 1.88 toolchain..."
        if ! rustup toolchain install 1.88; then
            log_error "Failed to install Rust 1.88"
            return 1
        fi
    fi

    # Step 1: Build kona-host (Mac-native)
    log_info "Step 1/3: Building kona-host (Mac-native)..."
    log_info "Using Rust 1.88 as specified in kona/rust-toolchain.toml"
    # Explicitly use +1.88 to override any RUSTUP_TOOLCHAIN env var
    if ! cargo +1.88 build --release --bin kona-host; then
        log_error "❌ Failed to build kona-host"
        return 1
    fi

    local kona_host_bin="$KONA_SOURCE_DIR/target/release/kona-host"
    if [ ! -f "$kona_host_bin" ]; then
        log_error "kona-host binary not found at $kona_host_bin"
        return 1
    fi

    # Verify it's Mac-native
    file_output=$(file "$kona_host_bin" 2>/dev/null || echo "unknown")
    if [[ "$file_output" == *"Mach-O"* ]] || [[ "$file_output" == *"arm64"* ]] || [[ "$file_output" == *"x86_64"* ]]; then
        log_success "✅ Built Mac-native kona-host binary"
    else
        log_warning "⚠️  Binary may not be Mac-native: $file_output"
    fi

    # Step 2: Build kona-client (RISC-V ELF) using Docker
    log_info "Step 2/3: Building kona-client (RISC-V ELF) using Docker..."
    log_info "Note: kona-client requires Docker for cross-compilation (C dependencies need riscv64-unknown-elf-gcc)"

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "docker command not found. Please install Docker Desktop for Mac:"
        log_error "  https://docs.docker.com/desktop/install/mac-install/"
        return 1
    fi

    # Check if Docker daemon is running (use a simple check that works reliably)
    if ! docker ps &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker Desktop and try again."
        log_error "You can verify Docker is running with: docker ps"
        return 1
    fi

    log_info "Building kona-client using Kona's official Docker builder (this may take a while)..."
    log_info "Docker image: ghcr.io/op-rs/kona/asterisc-builder:0.3.0"

    # Use Kona's official Docker-based build method (from kona/justfile)
    if ! docker run \
        --rm \
        -v "$KONA_SOURCE_DIR:/workdir" \
        -w="/workdir" \
        ghcr.io/op-rs/kona/asterisc-builder:0.3.0 \
        cargo build -Zbuild-std=core,alloc -p kona-client --bin kona-client --profile release-client-lto; then
        log_error "❌ Failed to build kona-client in Docker"
        log_error "This is the official Kona build method. Check Docker logs above for details."
        return 1
    fi

    local kona_client_elf="$KONA_SOURCE_DIR/target/riscv64imac-unknown-none-elf/release-client-lto/kona-client"
    if [ ! -f "$kona_client_elf" ]; then
        log_error "kona-client ELF not found at $kona_client_elf"
        return 1
    fi
    log_success "✅ Built kona-client RISC-V ELF"

    # Step 3: Generate prestate using Mac-native asterisc
    log_info "Step 3/3: Generating Kona prestate files..."

    # Check if asterisc is available
    local asterisc_bin="$ASTERISC_TARGET_DIR/asterisc"
    if [ ! -f "$asterisc_bin" ]; then
        log_warning "⚠️  asterisc binary not found at $asterisc_bin"
        log_warning "⚠️  Attempting to build asterisc first..."
        if ! build_asterisc; then
            log_error "❌ Failed to build asterisc (required for prestate generation)"
            return 1
        fi
    fi

    mkdir -p "$KONA_TARGET_DIR"

    # Generate prestate.bin.gz
    local prestate_bin="$KONA_TARGET_DIR/prestate.bin.gz"
    log_info "Generating prestate.bin.gz..."
    if ! "$asterisc_bin" load-elf --path="$kona_client_elf" --out="$prestate_bin"; then
        log_error "❌ Failed to generate prestate.bin.gz"
        return 1
    fi
    log_success "✅ Generated prestate.bin.gz"

    # Generate prestate.json with state hash
    local prestate_json="$KONA_TARGET_DIR/prestate.json"
    log_info "Generating prestate.json..."

    # Extract state hash from asterisc witness JSON output
    local witness_output
    witness_output=$("$asterisc_bin" witness --input "$prestate_bin" 2>&1)

    if [ $? -eq 0 ]; then
        # Extract stateHash from JSON output using jq if available, otherwise use grep
        if command -v jq >/dev/null 2>&1; then
            state_hash=$(echo "$witness_output" | jq -r '.stateHash')
        else
            state_hash=$(echo "$witness_output" | grep -o '"stateHash"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"/\1/')
        fi

        if [ -n "$state_hash" ] && [ "$state_hash" != "null" ]; then
            printf '{\n  "pre": "%s"\n}\n' "$state_hash" > "$prestate_json"
            log_success "✅ Generated prestate.json with hash: $state_hash"
        else
            log_error "❌ Failed to extract stateHash from asterisc witness output"
            return 1
        fi
    else
        log_error "❌ Failed to run asterisc witness command"
        return 1
    fi

    # Generate prestate-proof.json (at step 0)
    local prestate_proof="$KONA_TARGET_DIR/prestate-proof.json"
    log_info "Generating prestate-proof.json..."
    if ! "$asterisc_bin" run --proof-at "=0" --stop-at "=1" --input "$prestate_bin" --meta /dev/null --proof-fmt "$KONA_TARGET_DIR/%d.json" --output "" 2>/dev/null; then
        log_warning "⚠️  Failed to generate prestate-proof.json (non-critical)"
    else
        if [ -f "$KONA_TARGET_DIR/0.json" ]; then
            mv "$KONA_TARGET_DIR/0.json" "$prestate_proof"
            log_success "✅ Generated prestate-proof.json"
        fi
    fi

    # Copy binaries to target directory
    cp "$kona_host_bin" "$KONA_TARGET_DIR/kona-host"
    chmod +x "$KONA_TARGET_DIR/kona-host"

    cp "$kona_client_elf" "$KONA_TARGET_DIR/kona-client-elf"
    chmod +x "$KONA_TARGET_DIR/kona-client-elf"

    log_success "✅ Kona build complete:"
    log_success "   - kona-host: $KONA_TARGET_DIR/kona-host"
    log_success "   - kona-client-elf: $KONA_TARGET_DIR/kona-client-elf"
    log_success "   - prestate.bin.gz: $KONA_TARGET_DIR/prestate.bin.gz"
    log_success "   - prestate.json: $KONA_TARGET_DIR/prestate.json"
    if [ -f "$prestate_proof" ]; then
        log_success "   - prestate-proof.json: $KONA_TARGET_DIR/prestate-proof.json"
    fi

    return 0
}

# Main function
main() {
    local need_cannon=false
    local need_op_program=false
    local need_asterisc=false
    local need_kona=false

    log_info "Checking required binary files in E2E directories..."

    # Check binaries (or force rebuild)
    if [ "$FORCE_BUILD" = true ] || [ ! -f "$CANNON_TARGET_DIR/cannon" ]; then
        if [ "$FORCE_BUILD" = true ] && [ -f "$CANNON_TARGET_DIR/cannon" ]; then
            log_info "🔄 cannon binary exists in E2E dir but forcing rebuild"
        else
            log_warning "❌ cannon binary not found in E2E directory"
        fi
        need_cannon=true
    else
        log_success "✅ cannon binary found in E2E directory"
    fi

    if [ "$FORCE_BUILD" = true ] || [ ! -f "$OP_PROGRAM_TARGET_DIR/op-program" ] || [ ! -f "$OP_PROGRAM_TARGET_DIR/prestate.bin.gz" ]; then
        if [ "$FORCE_BUILD" = true ]; then
            log_info "🔄 op-program/prestate exists in E2E dir but forcing rebuild"
        else
            if [ ! -f "$OP_PROGRAM_TARGET_DIR/op-program" ]; then
                log_warning "❌ op-program binary not found in E2E directory"
            fi
            if [ ! -f "$OP_PROGRAM_TARGET_DIR/prestate.bin.gz" ]; then
                log_warning "❌ prestate.bin.gz file not found in E2E directory"
            fi
        fi
        need_op_program=true
    else
        log_success "✅ op-program binary found in E2E directory"
        log_success "✅ prestate file found in E2E directory"
    fi

    if [ "$BUILD_ASTERISC" = true ]; then
        if [ "$FORCE_BUILD" = true ] || [ ! -f "$ASTERISC_TARGET_DIR/asterisc" ] || [ ! -f "$OP_PROGRAM_TARGET_DIR/prestate-asterisc.json" ]; then
            if [ "$FORCE_BUILD" = true ] && [ -f "$ASTERISC_TARGET_DIR/asterisc" ]; then
                log_info "🔄 ASTERISC assets exist in E2E dir but forcing rebuild"
            else
                if [ ! -f "$ASTERISC_TARGET_DIR/asterisc" ]; then
                    log_warning "❌ ASTERISC binary not found in E2E directory: $ASTERISC_TARGET_DIR/asterisc"
                fi
                if [ ! -f "$OP_PROGRAM_TARGET_DIR/prestate-asterisc.json" ]; then
                    log_warning "❌ ASTERISC prestate proof not found in E2E directory: $OP_PROGRAM_TARGET_DIR/prestate-asterisc.json"
                fi
            fi
            need_asterisc=true
        else
            log_success "✅ ASTERISC binary found in E2E directory"
            log_success "✅ ASTERISC prestate proof found in E2E directory"
        fi
    fi

    if [ "$BUILD_KONA" = true ]; then
        if [ "$FORCE_BUILD" = true ] || [ ! -f "$KONA_TARGET_DIR/kona-host" ] || [ ! -f "$KONA_TARGET_DIR/prestate.bin.gz" ]; then
            if [ "$FORCE_BUILD" = true ]; then
                log_info "🔄 Kona assets exist in E2E dir but forcing rebuild"
            else
                if [ ! -f "$KONA_TARGET_DIR/kona-host" ]; then
                    log_warning "❌ kona-host binary not found in E2E directory"
                fi
                if [ ! -f "$KONA_TARGET_DIR/prestate.bin.gz" ]; then
                    log_warning "❌ kona prestate.bin.gz not found in E2E directory"
                fi
            fi
            need_kona=true
        else
            log_success "✅ kona-host binary found in E2E directory"
            log_success "✅ kona prestate files found in E2E directory"
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