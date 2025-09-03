#!/bin/bash

# Optimism Devnet 배포 사전 점검 스크립트 (간단 버전)
# 실행 전에 배포 환경이 준비되었는지 확인

echo "=============================================="
echo "    Optimism Devnet 배포 사전 점검"
echo "=============================================="
echo

# 점검 결과 추적
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

check_item() {
    echo "[점검] $1"
    ((TOTAL_CHECKS++))
}

log_success() {
    echo "[✓ PASS] $1"
    ((PASSED_CHECKS++))
}

log_warning() {
    echo "[⚠ WARN] $1"
    ((WARNING_CHECKS++))
}

log_error() {
    echo "[✗ FAIL] $1"
    ((FAILED_CHECKS++))
}

# 1. 필수 도구 확인
echo "1. 필수 도구 설치 확인"
echo "------------------------"

tools=("docker" "kurtosis" "git")
for tool in "${tools[@]}"; do
    check_item "필수 도구: $tool"
    
    if command -v "$tool" >/dev/null 2>&1; then
        version=$("$tool" --version 2>/dev/null | head -1 | cut -d' ' -f1-3)
        log_success "$tool 설치됨 - $version"
    else
        log_error "$tool이 설치되어 있지 않습니다"
        case "$tool" in
            "docker") echo "  → https://docs.docker.com/get-docker/ 에서 설치" ;;
            "kurtosis") echo "  → https://docs.kurtosis.com/install 에서 설치" ;;
            "git") echo "  → 패키지 매니저를 통해 설치" ;;
        esac
    fi
done

echo

# 2. Docker 상태 확인
echo "2. Docker 환경 확인"
echo "-------------------"

check_item "Docker daemon 실행 상태"
if docker info >/dev/null 2>&1; then
    log_success "Docker daemon이 정상 실행 중"
else
    log_error "Docker daemon이 실행되지 않음 - Docker를 시작하세요"
fi

check_item "Docker 인터넷 연결"
if timeout 10 docker run --rm alpine:latest ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log_success "Docker 컨테이너 인터넷 연결 정상"
else
    log_warning "Docker 컨테이너 인터넷 연결 확인 실패"
fi

echo

# 3. 시스템 리소스 확인
echo "3. 시스템 리소스 확인"
echo "--------------------"

# 메모리 확인
check_item "시스템 메모리"
if [[ "$OSTYPE" == "darwin"* ]]; then
    total_memory=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
else
    total_memory=$(free -g 2>/dev/null | awk 'NR==2{print $2}' || echo "unknown")
fi

if [[ "$total_memory" != "unknown" ]]; then
    if (( total_memory >= 16 )); then
        log_success "시스템 메모리: ${total_memory}GB (충분함)"
    elif (( total_memory >= 8 )); then
        log_warning "시스템 메모리: ${total_memory}GB (권장: 16GB+)"
    else
        log_error "시스템 메모리 부족: ${total_memory}GB (최소: 8GB)"
    fi
else
    log_warning "시스템 메모리를 확인할 수 없음"
fi

# 디스크 공간 확인
check_item "디스크 공간"
available_disk=$(df -h . | awk 'NR==2{print $4}' | sed 's/[^0-9].*$//')
if [[ "$available_disk" =~ ^[0-9]+$ ]]; then
    if (( available_disk >= 20 )); then
        log_success "사용 가능한 디스크 공간: ${available_disk}GB"
    elif (( available_disk >= 10 )); then
        log_warning "사용 가능한 디스크 공간: ${available_disk}GB (권장: 20GB+)"
    else
        log_error "디스크 공간 부족: ${available_disk}GB (최소: 10GB)"
    fi
else
    log_warning "디스크 공간을 확인할 수 없음"
fi

echo

# 4. 네트워크 포트 확인
echo "4. 네트워크 포트 확인"
echo "--------------------"

check_item "필수 네트워크 포트"
ports=(8545 8546 9545 9546 7300 7301 8080 8081)
blocked_ports=()

for port in "${ports[@]}"; do
    if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        blocked_ports+=($port)
    fi
done

if [[ ${#blocked_ports[@]} -eq 0 ]]; then
    log_success "모든 필수 포트 사용 가능"
else
    log_warning "사용 중인 포트: ${blocked_ports[*]}"
    echo "  → 충돌 방지를 위해 해당 프로세스 종료 권장"
fi

echo

# 5. 프로젝트 구조 확인
echo "5. 프로젝트 구조 확인"
echo "--------------------"

check_item "Kurtosis devnet 디렉토리"
if [[ -d "kurtosis-devnet" ]]; then
    log_success "kurtosis-devnet 디렉토리 존재"
else
    log_error "kurtosis-devnet 디렉토리가 없음"
fi

check_item "설정 파일"
if [[ -f "kurtosis-devnet/simple.yaml" ]]; then
    log_success "simple.yaml 설정 파일 존재"
else
    log_error "simple.yaml 설정 파일이 없음"
fi

echo

# 6. 기존 환경 확인
echo "6. 기존 환경 확인"
echo "-----------------"

if command -v kurtosis >/dev/null 2>&1; then
    check_item "기존 Kurtosis enclaves"
    existing_enclaves=$(kurtosis enclave ls 2>/dev/null | grep -c "^[^N]" 2>/dev/null || echo "0")
    if [[ "$existing_enclaves" -gt 0 ]]; then
        log_warning "$existing_enclaves개의 기존 enclave 실행 중"
        echo "  → 정리 명령: kurtosis enclave rm <enclave-name>"
        kurtosis enclave ls 2>/dev/null | head -5
    else
        log_success "Kurtosis 환경이 깨끗함"
    fi
fi

check_item "관련 Docker 컨테이너"
running_containers=$(docker ps --filter "name=kurtosis" --filter "name=op-" 2>/dev/null | wc -l | xargs)
running_containers=$((running_containers - 1))  # 헤더 라인 제외

if [[ "$running_containers" -gt 0 ]]; then
    log_warning "$running_containers개의 관련 컨테이너 실행 중"
    echo "  → 정리 명령: docker ps --filter name=kurtosis -q | xargs docker rm -f"
else
    log_success "관련 Docker 컨테이너가 깨끗함"
fi

echo

# 최종 결과 요약
echo "=============================================="
echo "           점검 결과 요약"
echo "=============================================="
echo "전체 점검 항목: $TOTAL_CHECKS"
echo "통과: $PASSED_CHECKS"
echo "경고: $WARNING_CHECKS"  
echo "실패: $FAILED_CHECKS"
echo

if [[ $FAILED_CHECKS -eq 0 ]]; then
    if [[ $WARNING_CHECKS -eq 0 ]]; then
        echo "✓ 모든 점검을 통과했습니다! 배포를 시작할 수 있습니다."
        echo
        echo "배포 명령어:"
        echo "  cd kurtosis-devnet"
        echo "  kurtosis run --enclave optimism-devnet github.com/ethpandaops/optimism-package --args-file simple.yaml"
    else
        echo "⚠ 경고가 있지만 배포 시도가 가능합니다."
        echo "  위의 경고 사항들을 검토한 후 배포를 시작하세요."
    fi
else
    echo "✗ 중요한 문제가 발견되었습니다."
    echo "  위의 실패 항목들을 해결한 후 배포를 시도하세요."
fi

echo

# Exit code 반환
if [[ $FAILED_CHECKS -gt 0 ]]; then
    exit 1
else
    exit 0
fi