#!/bin/bash

# ==========================================
# Challenger Network - Devnet Restart Script
# ==========================================

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 변수 정의
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENCLAVE_NAME="simple-devnet"

echo "=========================================="
echo "Challenger Network - Devnet Restart"
echo "=========================================="
echo

# Safety confirmation
log_warning "This script will:"
echo "  • Remove Kurtosis enclave: $ENCLAVE_NAME"  
echo "  • Stop and remove Devnet-related Docker containers"
echo "  • Optionally clean up Docker volumes"
echo "  • Rebuild and restart the entire devnet"
echo
read -p "Continue with devnet restart? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Devnet restart cancelled"
    exit 0
fi
echo

# 1. Clean up existing devnet
log_step "Cleaning up existing devnet..."

# Kurtosis enclave 정리
if kurtosis enclave list | grep -q "$ENCLAVE_NAME"; then
    log_info "Removing existing enclave: $ENCLAVE_NAME"
    kurtosis enclave rm --force "$ENCLAVE_NAME"
    sleep 5
    log_success "Enclave removed"
else
    log_info "No existing enclave found"
fi

# Clean up Devnet-related Docker containers only
log_info "Cleaning up Devnet-related Docker containers..."

# Stop and remove only Devnet-related containers
devnet_containers=$(docker ps -a --format "{{.Names}}" | grep -E "(op-|el-|cl-|geth|lighthouse|grafana|prometheus|proxyd|validator)" || true)

if [ -n "$devnet_containers" ]; then
    echo "$devnet_containers" | xargs docker stop 2>/dev/null || true
    echo "$devnet_containers" | xargs docker rm 2>/dev/null || true
    log_success "Devnet Docker containers cleaned"
else
    log_info "No Devnet Docker containers found"
fi

# Clean up Docker volumes (optional)
read -p "Do you want to clean Devnet-related Docker volumes? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleaning Devnet-related Docker volumes..."
    
    # Clean only volumes that might be related to Devnet
    devnet_volumes=$(docker volume ls --format "{{.Name}}" | grep -E "(devnet|kurtosis|optimism|op-)" || true)
    
    if [ -n "$devnet_volumes" ]; then
        echo "$devnet_volumes" | xargs docker volume rm 2>/dev/null || true
        log_success "Devnet Docker volumes cleaned"
    else
        log_info "No Devnet-related volumes found"
    fi
    
    # Also run general prune with confirmation
    log_warning "This will also remove ALL unused Docker volumes"
    read -p "Proceed with full volume cleanup? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker volume prune -f
        log_success "All unused Docker volumes cleaned"
    fi
fi

echo

# 2. Start new devnet
log_step "Starting new devnet..."

# Use absolute path to avoid path dependency issues
if [ -f "$SCRIPT_DIR/build-devnet.sh" ]; then
    "$SCRIPT_DIR/build-devnet.sh"
else
    log_error "build-devnet.sh not found in $SCRIPT_DIR"
    exit 1
fi

log_success "🎉 Devnet restart completed!"
