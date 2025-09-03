#!/bin/bash

# Challenger Health Check Script
# 챌린저 상태를 종합적으로 체크하는 스크립트

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

echo "=========================================="
echo "OP-Challenger Health Check"
echo "=========================================="
echo

# 1. 컨테이너 상태 확인
log_info "Checking challenger container status..."
if docker ps --format "{{.Names}}" | grep -q "op-challenger"; then
    log_success "✅ Challenger container is running"
    
    # 컨테이너 시작 시간 확인
    START_TIME=$(docker inspect op-challenger --format='{{.State.StartedAt}}' | cut -d'T' -f1-2 | tr 'T' ' ')
    log_info "Container started at: $START_TIME"
else
    log_error "❌ Challenger container is not running"
    exit 1
fi

# 2. Devnet 상태 확인
log_info "Checking devnet status..."
if kurtosis enclave ls | grep -q "simple-devnet"; then
    log_success "✅ Devnet is running"
else
    log_error "❌ Devnet is not running"
    exit 1
fi

# 3. 포트 정보 추출
log_info "Getting port information..."
L1_RPC_PORT=$(kurtosis enclave inspect simple-devnet 2>/dev/null | grep "rpc: 8545/tcp" | head -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ')
L2_RPC_PORT=$(kurtosis enclave inspect simple-devnet 2>/dev/null | grep "rpc: 8545/tcp" | tail -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ')
ROLLUP_RPC_PORT=$(kurtosis enclave inspect simple-devnet 2>/dev/null | grep "rpc: 8547/tcp" | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ')

log_info "L1 RPC Port: $L1_RPC_PORT"
log_info "L2 RPC Port: $L2_RPC_PORT" 
log_info "Rollup RPC Port: $ROLLUP_RPC_PORT"

# 4. RPC 연결 테스트
log_info "Testing RPC connections..."

# L1 RPC 테스트
if curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "http://localhost:$L1_RPC_PORT" > /dev/null 2>&1; then
    log_success "✅ L1 RPC connection successful"
    
    # 현재 블록 번호 가져오기
    L1_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "http://localhost:$L1_RPC_PORT" | grep -o '"result":"[^"]*' | cut -d'"' -f4)
    L1_BLOCK_DEC=$((16#${L1_BLOCK:2}))
    log_info "Current L1 block: $L1_BLOCK_DEC"
else
    log_error "❌ L1 RPC connection failed"
fi

# L2 RPC 테스트  
if curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "http://localhost:$L2_RPC_PORT" > /dev/null 2>&1; then
    log_success "✅ L2 RPC connection successful"
    
    # 현재 블록 번호 가져오기
    L2_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "http://localhost:$L2_RPC_PORT" | grep -o '"result":"[^"]*' | cut -d'"' -f4)
    L2_BLOCK_DEC=$((16#${L2_BLOCK:2}))
    log_info "Current L2 block: $L2_BLOCK_DEC"
else
    log_error "❌ L2 RPC connection failed"
fi

# Rollup RPC 테스트
if curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"optimism_outputAtBlock","params":["latest"],"id":1}' \
    "http://localhost:$ROLLUP_RPC_PORT" > /dev/null 2>&1; then
    log_success "✅ Rollup RPC connection successful"
else
    log_warning "⚠️  Rollup RPC connection failed (may be normal for some configurations)"
fi

# 5. 챌린저 로그 분석
log_info "Analyzing challenger logs..."

# 최근 에러 확인
ERROR_COUNT=$(docker logs op-challenger --since="5m" 2>&1 | grep -c -i error || true)
if [ "$ERROR_COUNT" -eq 0 ]; then
    log_success "✅ No recent errors in logs (last 5 minutes)"
else
    log_warning "⚠️  Found $ERROR_COUNT errors in last 5 minutes"
    echo
    log_info "Recent errors:"
    docker logs op-challenger --since="5m" 2>&1 | grep -i error | tail -5
fi

# 시작 메시지 확인
if docker logs op-challenger 2>&1 | grep -q "starting scheduler"; then
    log_success "✅ Scheduler started successfully"
else
    log_warning "⚠️  Scheduler start message not found"
fi

if docker logs op-challenger 2>&1 | grep -q "starting monitoring"; then
    log_success "✅ Monitoring started successfully"  
else
    log_warning "⚠️  Monitoring start message not found"
fi

# 6. 리소스 사용량 확인
log_info "Checking resource usage..."
RESOURCE_INFO=$(docker stats op-challenger --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}" | tail -1)
log_info "Resource usage: $RESOURCE_INFO"

# 7. 게임 팩토리 상태 확인 (선택적)
log_info "Checking game factory status..."
if docker logs op-challenger 2>&1 | grep -q "game-factory-address"; then
    FACTORY_ADDRESS=$(docker logs op-challenger 2>&1 | grep -o "game-factory-address[= ][0-9a-fx]*" | head -1 | cut -d'=' -f2 | cut -d' ' -f2)
    if [ -n "$FACTORY_ADDRESS" ]; then
        log_info "Game factory address: $FACTORY_ADDRESS"
    fi
fi

# 8. 데이터 디렉토리 확인
log_info "Checking data directory..."
if docker exec op-challenger ls -la /data > /dev/null 2>&1; then
    log_success "✅ Data directory accessible"
    DATA_SIZE=$(docker exec op-challenger du -sh /data 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Data directory size: $DATA_SIZE"
else
    log_warning "⚠️  Data directory not accessible"
fi

# 최종 결과
echo
echo "=========================================="
echo "Health Check Summary"
echo "=========================================="

# 종합 상태 판단
ISSUES=0

if ! docker ps --format "{{.Names}}" | grep -q "op-challenger"; then
    ((ISSUES++))
fi

if [ "$ERROR_COUNT" -gt 10 ]; then
    ((ISSUES++))
fi

if [ "$ISSUES" -eq 0 ]; then
    log_success "🎉 Overall Status: HEALTHY"
    echo
    echo "Next steps:"
    echo "- Monitor logs: docker logs -f op-challenger" 
    echo "- Check detailed testing: see docs/challenger-testing.md"
else
    log_warning "⚠️  Overall Status: NEEDS ATTENTION ($ISSUES issues found)"
    echo
    echo "Recommended actions:"
    echo "- Check logs: docker logs op-challenger"
    echo "- See troubleshooting: docs/troubleshooting.md"
fi

echo