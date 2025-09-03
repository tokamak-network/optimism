#!/bin/bash

# L1 Startup + Contract Deployment 빠른 사전 체크
# 가장 중요한 항목들만 빠르게 체크하여 배포 전 문제 조기 발견

set -e

# 색상 정의  
RED='\033[0;31m'
GREEN='\033[0;32m' 
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
WARNINGS=0
FAILED=0

log_success() { echo -e "${GREEN}[✓]${NC} $1"; ((PASSED++)); }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; ((WARNINGS++)); }
log_error() { echo -e "${RED}[✗]${NC} $1"; ((FAILED++)); }

echo "=============================================="
echo "     L1 Startup 빠른 사전 체크"
echo "=============================================="
echo

# 1. 핵심 도구 확인
echo "1. 핵심 도구 확인"
echo "----------------"

if command -v docker >/dev/null 2>&1; then
    log_success "Docker 설치됨"
else
    log_error "Docker 설치되지 않음"
fi

if command -v kurtosis >/dev/null 2>&1; then
    log_success "Kurtosis 설치됨"
else  
    log_error "Kurtosis 설치되지 않음"
fi

# 2. Docker 기본 상태
echo
echo "2. Docker 기본 상태"
echo "------------------"

if docker ps >/dev/null 2>&1; then
    log_success "Docker daemon 실행 중"
else
    log_error "Docker daemon 실행되지 않음"
fi

# 3. 시스템 리소스 (간단히)
echo
echo "3. 시스템 리소스"
echo "---------------"

if [[ "$OSTYPE" == "darwin"* ]]; then
    total_memory=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}' 2>/dev/null || echo "unknown")
    if [[ "$total_memory" != "unknown" ]] && (( total_memory >= 8 )); then
        log_success "메모리: ${total_memory}GB"
    else
        log_warning "메모리 부족: ${total_memory}GB"
    fi
fi

available_disk=$(df -h . | awk 'NR==2{print $4}' | sed 's/[^0-9].*//' | head -1)
if [[ "$available_disk" =~ ^[0-9]+$ ]] && (( available_disk >= 10 )); then
    log_success "디스크 공간: ${available_disk}GB"
else
    log_warning "디스크 공간 부족: ${available_disk}GB"
fi

# 4. 중요한 포트 체크
echo
echo "4. 중요한 포트 체크"  
echo "------------------"

# L1 Ethereum 포트 (가장 중요)
critical_ports=(8545 30303)
blocked_ports=()

for port in "${critical_ports[@]}"; do
    if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        blocked_ports+=($port)
    fi
done

if [[ ${#blocked_ports[@]} -eq 0 ]]; then
    log_success "핵심 포트 사용 가능 (8545, 30303)"
else
    log_error "핵심 포트 사용 중: ${blocked_ports[*]}"
    echo "           → L1 체인 시작 실패 가능성 높음"
fi

# 5. 기존 환경 정리 상태
echo
echo "5. 환경 정리 상태"
echo "----------------"

# Kurtosis enclave 확인
enclave_count=$(kurtosis enclave ls 2>/dev/null | grep -c "RUNNING\|STOPPED" 2>/dev/null || echo "0")
if [[ "$enclave_count" -eq 0 ]]; then
    log_success "Kurtosis 환경 깨끗함"
else
    log_warning "$enclave_count개 기존 enclave 존재"
    echo "           → kurtosis clean -a 권장"
fi

# 관련 컨테이너 확인
container_count=$(docker ps --filter "name=kurtosis" --filter "name=op-" --filter "name=geth" --filter "name=teku" 2>/dev/null | wc -l | xargs || echo "1")
container_count=$((container_count - 1))

if [[ "$container_count" -le 0 ]]; then
    log_success "관련 컨테이너 없음"
else
    log_warning "$container_count개 관련 컨테이너 실행 중"
    echo "           → 포트 충돌 가능성"
fi

# 6. 네트워크 연결 (빠른 체크)
echo
echo "6. 네트워크 연결"
echo "---------------"

if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log_success "인터넷 연결 정상"
else
    log_error "인터넷 연결 문제"
fi

if timeout 5 docker run --rm alpine:latest ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log_success "Docker 네트워크 정상"
else
    log_warning "Docker 네트워크 문제"
fi

echo
echo "=============================================="
echo "           빠른 체크 결과"
echo "=============================================="
echo "통과: $PASSED | 경고: $WARNINGS | 실패: $FAILED"
echo

if [[ $FAILED -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}🎉 모든 체크 통과! L1 startup 시작 가능${NC}"
        echo
        echo "예상 시간: 6-10분"
        echo "• L1 체인 시작: 2-3분" 
        echo "• Contract 배포: 3-5분"
        echo "• 검증 및 완료: 1-2분"
    else
        echo -e "${YELLOW}⚠️  경고 있음 - 신중하게 진행하세요${NC}"
        echo "경고 사항을 확인하고 필요시 해결 후 진행"
    fi
    exit 0
else
    echo -e "${RED}❌ 실패 항목 있음 - L1 startup 실패 가능성 높음${NC}"
    echo "위 실패 항목들을 해결한 후 시도하세요"
    echo
    echo "일반적인 해결책:"
    echo "• Docker 재시작"
    echo "• 포트 사용 프로세스 종료"  
    echo "• kurtosis clean -a"
    exit 1
fi