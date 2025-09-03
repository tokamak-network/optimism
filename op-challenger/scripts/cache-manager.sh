#!/bin/bash

# 캐시 관리 및 최적화 스크립트

set -e

CACHE_DIR="$HOME/.optimism-devnet-cache"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

# 캐시 디렉토리 초기화
init_cache() {
    mkdir -p "$CACHE_DIR"/{docker-layers,prestate,binaries,artifacts}
    log_success "Cache directory initialized: $CACHE_DIR"
}

# Docker 빌드 캐시 최적화
optimize_docker_cache() {
    log_info "Optimizing Docker build cache..."
    
    # Docker buildkit 활성화
    export DOCKER_BUILDKIT=1
    export BUILDKIT_PROGRESS=plain
    
    # 빌드 캐시 마운트 설정
    cat > /tmp/docker-cache-config.json << EOF
{
  "experimental": true,
  "features": {
    "buildkit": true
  }
}
EOF
    
    # 기존 이미지 재사용 체크
    if docker images | grep -q "op-.*:latest"; then
        log_success "Found existing Docker images for reuse"
        export DOCKER_BUILDKIT_CACHE_FROM="--cache-from=op-node:latest,op-batcher:latest"
    fi
}

# 바이너리 캐시 관리
manage_binary_cache() {
    log_info "Managing binary cache..."
    
    local optimism_root="$(dirname "$(dirname "$SCRIPT_DIR")")"
    
    # cannon 바이너리 캐시
    if [ -f "$optimism_root/cannon/bin/cannon" ]; then
        cp "$optimism_root/cannon/bin/cannon" "$CACHE_DIR/binaries/"
        log_success "Cached cannon binary"
    fi
    
    # op-program 바이너리 캐시  
    if [ -f "$optimism_root/op-program/bin/op-program" ]; then
        cp "$optimism_root/op-program/bin/op-program" "$CACHE_DIR/binaries/"
        log_success "Cached op-program binary"
    fi
    
    # prestate 캐시
    if [ -f "$optimism_root/op-program/bin/prestate.bin.gz" ]; then
        cp "$optimism_root/op-program/bin/prestate.bin.gz" "$CACHE_DIR/prestate/"
        log_success "Cached prestate file"
    fi
}

# 캐시에서 바이너리 복원
restore_binaries() {
    log_info "Restoring binaries from cache..."
    
    local optimism_root="$(dirname "$(dirname "$SCRIPT_DIR")")"
    
    # 캐시된 바이너리들 복원
    if [ -f "$CACHE_DIR/binaries/cannon" ]; then
        mkdir -p "$optimism_root/cannon/bin"
        cp "$CACHE_DIR/binaries/cannon" "$optimism_root/cannon/bin/"
        chmod +x "$optimism_root/cannon/bin/cannon"
        log_success "Restored cannon binary from cache"
    fi
    
    if [ -f "$CACHE_DIR/binaries/op-program" ]; then
        mkdir -p "$optimism_root/op-program/bin"
        cp "$CACHE_DIR/binaries/op-program" "$optimism_root/op-program/bin/"
        chmod +x "$optimism_root/op-program/bin/op-program"
        log_success "Restored op-program binary from cache"
    fi
    
    if [ -f "$CACHE_DIR/prestate/prestate.bin.gz" ]; then
        mkdir -p "$optimism_root/op-program/bin"
        cp "$CACHE_DIR/prestate/prestate.bin.gz" "$optimism_root/op-program/bin/"
        log_success "Restored prestate from cache"
    fi
}

# 캐시 상태 확인
check_cache_status() {
    log_info "Cache status:"
    
    echo "  Docker images:"
    docker images | grep -E "op-(node|batcher|proposer|faucet|challenger|deployer)" | wc -l | xargs echo "    Available: $1 images"
    
    echo "  Cached binaries:"
    ls -la "$CACHE_DIR/binaries/" 2>/dev/null | wc -l | xargs echo "    Available: $1 files"
    
    echo "  Cache size:"
    du -sh "$CACHE_DIR" 2>/dev/null || echo "    No cache found"
}

# 캐시 정리
clean_cache() {
    log_info "Cleaning cache..."
    rm -rf "$CACHE_DIR"
    docker system prune -f
    log_success "Cache cleaned"
}

# 메인 함수
case "${1:-status}" in
    "init")
        init_cache
        optimize_docker_cache
        ;;
    "save")
        manage_binary_cache
        ;;
    "restore")
        restore_binaries
        ;;
    "status")
        check_cache_status
        ;;
    "clean")
        clean_cache
        ;;
    *)
        echo "Usage: $0 {init|save|restore|status|clean}"
        exit 1
        ;;
esac