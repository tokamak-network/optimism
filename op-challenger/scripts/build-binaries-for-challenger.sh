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
    echo "  -h, --help      Show this help message"
    echo
    echo "EXAMPLES:"
    echo "  $0              # Build only if binaries don't exist"
    echo "  $0 --force      # Force rebuild all binaries"
    echo
}

# Parse Command Line Arguments
FORCE_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD=true
            log_info "Force rebuild enabled"
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

# Main function
main() {
    local need_cannon=false
    local need_op_program=false

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

    # Build if needed
    if [ "$need_cannon" = false ] && [ "$need_op_program" = false ]; then
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

    log_success "🎉 All required binaries are now ready!"
}

# Execute Script
main "$@"