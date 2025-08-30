#!/bin/bash

# L1 Startup + Contract Deployment 사전 체크 스크립트
# 가장 시간이 오래 걸리고 자주 실패하는 단계를 위한 철저한 검증

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 로그 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓ PASS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠ WARN]${NC} $1"; }
log_error() { echo -e "${RED}[✗ FAIL]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

# 카운터
PASSED=0
WARNINGS=0
FAILED=0
TOTAL=0

check_item() {
    echo -e "${BLUE}[점검]${NC} $1"
    ((TOTAL++))
}

echo "=============================================="
echo "    L1 Startup + Contract Deployment"
echo "         사전 체크 스크립트"
echo "=============================================="
echo

# 1. Docker 환경 상세 체크
log_step "1. Docker 환경 상세 체크"
echo

check_item "Docker daemon 상태"
if docker info >/dev/null 2>&1; then
    docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    log_success "Docker daemon 정상 실행 중 (v${docker_version})"
    ((PASSED++))
else
    log_error "Docker daemon이 실행되지 않음"
    ((FAILED++))
fi

check_item "Docker 디스크 공간"
docker_space=$(docker system df 2>/dev/null | grep "Images" | awk '{print $3}' | sed 's/[^0-9.].*//' || echo "0")
if [[ "${docker_space}" =~ ^[0-9]+$ ]]; then
    if (( docker_space > 10 )); then
        log_success "Docker 이미지 공간: ${docker_space}GB"
        ((PASSED++))
    else
        log_warning "Docker 이미지 공간이 부족할 수 있음: ${docker_space}GB"
        ((WARNINGS++))
    fi
else
    log_warning "Docker 디스크 공간을 확인할 수 없음"
    ((WARNINGS++))
fi

check_item "Docker 네트워크 연결"
if timeout 10 docker run --rm alpine:latest ping -c 2 8.8.8.8 >/dev/null 2>&1; then
    log_success "Docker 컨테이너 인터넷 연결 정상"
    ((PASSED++))
else
    log_error "Docker 컨테이너에서 인터넷 접근 불가"
    ((FAILED++))
fi

check_item "Docker Hub 연결"
if timeout 15 docker pull hello-world:latest >/dev/null 2>&1; then
    log_success "Docker Hub 연결 및 이미지 pull 정상"
    ((PASSED++))
    docker rmi hello-world:latest >/dev/null 2>&1 || true
else
    log_error "Docker Hub 연결 실패 - 이미지 pull 불가"
    ((FAILED++))
fi

echo

# 2. 필수 Docker 이미지 체크
log_step "2. 필수 Docker 이미지 체크"
echo

required_images=("ethereum/client-go:latest" "consensys/teku:latest")
for image in "${required_images[@]}"; do
    check_item "이미지 pull 테스트: $image"
    if timeout 30 docker pull "$image" >/dev/null 2>&1; then
        log_success "$image pull 성공"
        ((PASSED++))
    else
        log_error "$image pull 실패"
        ((FAILED++))
    fi
done

echo

# 3. 시스템 리소스 실시간 체크
log_step "3. 시스템 리소스 실시간 체크"
echo

check_item "메모리 사용률"
if [[ "$OSTYPE" == "darwin"* ]]; then
    memory_pressure=$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | awk '{print $5}' | sed 's/%//' || echo "50")
    if [[ "$memory_pressure" =~ ^[0-9]+$ ]] && (( memory_pressure > 20 )); then
        log_success "메모리 여유: ${memory_pressure}% 사용 가능"
        ((PASSED++))
    else
        log_warning "메모리 압박 상황: ${memory_pressure}% 사용 가능"
        ((WARNINGS++))
    fi
else
    memory_available=$(free | awk 'NR==2{printf "%.0f", $7/$2*100}' 2>/dev/null || echo "50")
    if (( memory_available > 20 )); then
        log_success "메모리 여유: ${memory_available}% 사용 가능"
        ((PASSED++))
    else
        log_warning "메모리 부족: ${memory_available}% 사용 가능"
        ((WARNINGS++))
    fi
fi

check_item "CPU 로드"
cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' || echo "1.0")
cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "4")
cpu_load_percent=$(awk "BEGIN {printf \"%.0f\", $cpu_load * 100 / $cpu_cores}" 2>/dev/null || echo "25")

if (( cpu_load_percent < 80 )); then
    log_success "CPU 로드 정상: ${cpu_load_percent}%"
    ((PASSED++))
else
    log_warning "CPU 로드 높음: ${cpu_load_percent}%"
    ((WARNINGS++))
fi

check_item "디스크 I/O"
if command -v iostat >/dev/null 2>&1; then
    disk_util=$(iostat -d 1 2 2>/dev/null | tail -1 | awk '{print $NF}' || echo "50")
    if [[ "$disk_util" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(awk "BEGIN {print ($disk_util < 90)}") )); then
        log_success "디스크 I/O 정상: ${disk_util}%"
        ((PASSED++))
    else
        log_warning "디스크 I/O 높음: ${disk_util}%"
        ((WARNINGS++))
    fi
else
    log_warning "iostat를 사용할 수 없어 디스크 I/O를 확인할 수 없음"
    ((WARNINGS++))
fi

echo

# 4. 네트워크 및 포트 상세 체크
log_step "4. 네트워크 및 포트 상세 체크"
echo

# Ethereum 관련 필수 포트들
critical_ports=(8545 8546 30303 9000 5052)
l2_ports=(9545 9546 7300 7301 8080)

check_item "L1 Ethereum 필수 포트"
blocked_critical=()
for port in "${critical_ports[@]}"; do
    if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        blocked_critical+=($port)
    fi
done

if [[ ${#blocked_critical[@]} -eq 0 ]]; then
    log_success "L1 Ethereum 필수 포트 모두 사용 가능"
    ((PASSED++))
else
    log_error "L1 Ethereum 필수 포트 사용 중: ${blocked_critical[*]}"
    echo "       → 이 포트들은 L1 체인 시작에 필요합니다"
    ((FAILED++))
fi

check_item "L2 Optimism 포트"
blocked_l2=()
for port in "${l2_ports[@]}"; do
    if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        blocked_l2+=($port)
    fi
done

if [[ ${#blocked_l2[@]} -eq 0 ]]; then
    log_success "L2 Optimism 포트 모두 사용 가능"
    ((PASSED++))
else
    log_warning "L2 Optimism 포트 사용 중: ${blocked_l2[*]} (자동 포트 할당 가능)"
    ((WARNINGS++))
fi

echo

# 5. 외부 서비스 연결 체크
log_step "5. 외부 서비스 연결 체크"
echo

external_services=(
    "github.com:443"
    "registry-1.docker.io:443" 
    "gcr.io:443"
    "raw.githubusercontent.com:443"
)

check_item "외부 서비스 연결성"
failed_services=()
for service in "${external_services[@]}"; do
    host=$(echo $service | cut -d: -f1)
    port=$(echo $service | cut -d: -f2)
    if ! timeout 5 nc -z "$host" "$port" 2>/dev/null; then
        failed_services+=("$service")
    fi
done

if [[ ${#failed_services[@]} -eq 0 ]]; then
    log_success "모든 외부 서비스 연결 가능"
    ((PASSED++))
else
    log_warning "연결 불가 서비스: ${failed_services[*]}"
    echo "       → 네트워크 지연이나 방화벽 문제일 수 있음"
    ((WARNINGS++))
fi

echo

# 6. Kurtosis 환경 심화 체크
log_step "6. Kurtosis 환경 심화 체크"
echo

check_item "Kurtosis 엔진 상태"
if kurtosis engine status >/dev/null 2>&1; then
    log_success "Kurtosis 엔진 정상 작동"
    ((PASSED++))
else
    log_error "Kurtosis 엔진 문제 있음"
    ((FAILED++))
fi

check_item "기존 enclave 정리"
existing_enclaves=$(kurtosis enclave ls --output json 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0")
if [[ "$existing_enclaves" -eq 0 ]]; then
    log_success "Kurtosis 환경이 깨끗함"
    ((PASSED++))
else
    log_warning "$existing_enclaves개의 기존 enclave 존재 - 정리 권장"
    echo "       → kurtosis clean -a 명령으로 정리하세요"
    ((WARNINGS++))
fi

echo

# 7. Contract deployment 사전 조건
log_step "7. Contract Deployment 사전 조건"
echo

check_item "Go 런타임"
if command -v go >/dev/null 2>&1; then
    go_version=$(go version | awk '{print $3}' | sed 's/go//')
    if [[ "$(printf '%s\n' "1.19" "$go_version" | sort -V | head -n1)" = "1.19" ]]; then
        log_success "Go 버전 적합: $go_version"
        ((PASSED++))
    else
        log_warning "Go 버전이 낮을 수 있음: $go_version (권장: 1.19+)"
        ((WARNINGS++))
    fi
else
    log_error "Go가 설치되지 않음"
    ((FAILED++))
fi

check_item "Node.js/npm (contract 도구용)"
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    node_version=$(node --version | sed 's/v//')
    log_success "Node.js 사용 가능: v$node_version"
    ((PASSED++))
else
    log_warning "Node.js/npm 없음 - 일부 contract 도구 사용 불가"
    ((WARNINGS++))
fi

echo

# 8. 프로젝트 구조 상세 체크
log_step "8. 프로젝트 구조 상세 체크"
echo

critical_paths=(
    "/Users/zena/tokamak-projects/optimism/kurtosis-devnet"
    "/Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml"
    "/Users/zena/tokamak-projects/optimism"
)

for path in "${critical_paths[@]}"; do
    check_item "경로 확인: $(basename $path)"
    if [[ -e "$path" ]]; then
        log_success "$(basename $path) 존재함"
        ((PASSED++))
    else
        log_error "$(basename $path) 없음: $path"
        ((FAILED++))
    fi
done

echo

# 최종 결과 및 권장사항
echo "=============================================="
echo "           L1 Startup 사전 체크 결과"
echo "=============================================="
echo "전체 점검 항목: $TOTAL"
echo -e "${GREEN}통과: $PASSED${NC}"
echo -e "${YELLOW}경고: $WARNINGS${NC}"
echo -e "${RED}실패: $FAILED${NC}"
echo

if [[ $FAILED -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}🎉 완벽! L1 startup + contract deployment 준비 완료${NC}"
        echo
        echo "예상 실행 시간:"
        echo "  • L1 체인 시작: 2-3분"
        echo "  • Contract 배포: 3-5분"
        echo "  • 검증: 1-2분"
        echo "  • 총 예상 시간: 6-10분"
    else
        echo -e "${YELLOW}⚠️  경고가 있지만 L1 startup 시도 가능${NC}"
        echo "   위 경고사항들을 확인한 후 진행하세요."
        echo "   예상 실행 시간이 더 길어질 수 있습니다."
    fi
    
    echo
    echo "문제 발생시 체크사항:"
    echo "  1. Docker 메모리 할당 (8GB+ 권장)"
    echo "  2. 인터넷 연결 안정성"
    echo "  3. 포트 충돌"
    echo "  4. 디스크 공간 부족"
    
else
    echo -e "${RED}❌ 치명적 문제 발견 - L1 startup 실패 가능성 높음${NC}"
    echo "   위의 실패 항목들을 모두 해결한 후 시도하세요."
    echo
    echo "일반적인 해결 방법:"
    echo "  • Docker 재시작: brew services restart docker (macOS)"
    echo "  • 포트 정리: lsof -ti:<포트번호> | xargs kill -9"
    echo "  • Kurtosis 정리: kurtosis clean -a"
    echo "  • 시스템 재부팅 (최후 수단)"
    exit 1
fi

echo