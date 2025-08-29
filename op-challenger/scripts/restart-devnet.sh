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

# 1. 기존 Devnet 정리
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

# Docker 컨테이너들 정리 (혹시 남아있는 경우)
log_info "Cleaning up Docker containers..."
docker stop $(docker ps -q) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
log_success "Docker containers cleaned"

# Docker 볼륨 정리 (선택사항)
read -p "Do you want to clean Docker volumes? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleaning Docker volumes..."
    docker volume prune -f
    log_success "Docker volumes cleaned"
fi

echo

# 2. Devnet 다시 시작
log_step "Starting new devnet..."
cd "$SCRIPT_DIR"
./build-devnet.sh

log_success "🎉 Devnet restart completed!"
