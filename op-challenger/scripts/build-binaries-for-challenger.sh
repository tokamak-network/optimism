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

# Script Information
echo "=========================================="
echo "OP-Challenger Binary Builder"
echo "Builds required binaries for challenger"
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
    
    # Check binaries
    if [ ! -f "$OPTIMISM_ROOT/cannon/bin/cannon" ]; then
        log_warning "❌ cannon binary not found"
        need_cannon=true
    else
        log_success "✅ cannon binary found"
    fi
    
    if [ ! -f "$OPTIMISM_ROOT/op-program/bin/op-program" ]; then
        log_warning "❌ op-program binary not found"
        need_op_program=true
    else
        log_success "✅ op-program binary found"
    fi
    
    if [ ! -f "$OPTIMISM_ROOT/op-program/bin/prestate-mt64Next.bin.gz" ]; then
        log_warning "❌ prestate file not found"
        need_op_program=true
    else
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