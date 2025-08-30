#!/bin/bash

# 안정적인 단계별 배포 스크립트
# Kurtosis 연결 문제를 최소화하기 위한 개선된 배포 방식

set -e

RED='\033[0;31m'
GREEN='\033[0;32m' 
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENCLAVE_NAME="simple-devnet"

echo "=============================================="
echo "    안정적인 Optimism Devnet 배포"
echo "=============================================="
echo

# 1. 사전 체크
log_info "Step 1: 사전 환경 체크"
if ! bash "$SCRIPT_DIR/ultra-simple-check.sh"; then
    log_error "사전 체크 실패"
    exit 1
fi
echo

# 2. Kurtosis 엔진 상태 확인 및 재시작
log_info "Step 2: Kurtosis 엔진 안정성 체크"

# 엔진 재시작으로 연결 문제 방지
log_info "Kurtosis 엔진 재시작 중..."
kurtosis engine stop || true
sleep 5
kurtosis engine start
sleep 3

# 엔진 상태 확인
if kurtosis engine status >/dev/null 2>&1; then
    log_success "Kurtosis 엔진 정상 실행 중"
else
    log_error "Kurtosis 엔진 실행 실패"
    exit 1
fi
echo

# 3. 환경 완전 정리
log_info "Step 3: 환경 완전 정리"
kurtosis clean -a
sleep 2
log_success "환경 정리 완료"
echo

# 4. 단계별 배포 시도
log_info "Step 4: 단계별 안정적 배포 시작"
log_warning "이번에는 더 안정적인 방식으로 시도합니다..."

cd /Users/zena/tokamak-projects/optimism/kurtosis-devnet

# 더 짧은 타임아웃으로 빠른 실패 감지
log_info "배포 시작 (5분 타임아웃으로 빠른 감지)"
if timeout 300 kurtosis run --enclave "$ENCLAVE_NAME" github.com/ethpandaops/optimism-package --args-file simple.yaml; then
    log_success "🎉 배포 성공!"
    
    # 서비스 상태 확인
    echo
    log_info "배포된 서비스 확인:"
    kurtosis enclave inspect "$ENCLAVE_NAME" --brief || true
    
else
    exit_code=$?
    log_warning "배포 프로세스가 종료되었습니다 (exit code: $exit_code)"
    
    # 빠른 진단
    echo
    log_info "빠른 상태 진단:"
    kurtosis enclave ls || true
    
    if [[ $exit_code -eq 124 ]]; then
        log_info "타임아웃 발생 - enclave 상태 확인 중..."
        
        # enclave가 실제로 실행되고 있는지 확인
        if kurtosis enclave ls | grep -q "$ENCLAVE_NAME.*RUNNING"; then
            log_warning "⚠️  타임아웃이지만 enclave는 실행 중입니다"
            log_info "수동으로 상태를 확인해보세요:"
            echo "  kurtosis enclave inspect $ENCLAVE_NAME"
        else
            log_error "배포 실패 - enclave가 시작되지 않았습니다"
        fi
    else
        log_error "배포 중 오류 발생"
    fi
    
    exit $exit_code
fi