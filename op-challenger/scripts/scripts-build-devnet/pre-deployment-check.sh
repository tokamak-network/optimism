#!/bin/bash

# Optimism Devnet 배포 사전 점검 스크립트
# 작성자: Claude Code  
# 설명: 실제 배포 전에 시스템 환경과 설정을 점검하여 배포 성공 가능성을 확인

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 점검 결과 추적
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# 로그 함수들
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
    ((WARNING_CHECKS++))
}

log_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((FAILED_CHECKS++))
}

check_item() {
    echo -e "${BLUE}[점검]${NC} $1"
    ((TOTAL_CHECKS++))
}

# 1. 운영체제 및 아키텍처 확인
check_os_architecture() {
    check_item "운영체제 및 아키텍처"
    
    OS=$(uname -s)
    ARCH=$(uname -m)
    
    case "$OS" in
        "Darwin")
            log_success "macOS 감지됨 ($ARCH)"
            if [[ "$ARCH" == "arm64" ]]; then
                log_info "Apple Silicon (M1/M2) 아키텍처 - Docker 성능 최적화 권장"
            fi
            ;;
        "Linux")
            log_success "Linux 감지됨 ($ARCH)"
            ;;
        *)
            log_warning "지원되지 않는 운영체제일 수 있습니다: $OS"
            ;;
    esac
}

# 2. 필수 도구 설치 확인
check_required_tools() {
    local tools=("docker" "kurtosis" "git")
    
    for tool in "${tools[@]}"; do
        check_item "필수 도구: $tool"
        
        if command -v "$tool" >/dev/null 2>&1; then
            version=$("$tool" --version 2>/dev/null | head -1)
            log_success "$tool 설치됨 - $version"
        else
            log_error "$tool이 설치되어 있지 않습니다"
            case "$tool" in
                "docker")
                    echo "  → https://docs.docker.com/get-docker/ 에서 설치하세요"
                    ;;
                "kurtosis")
                    echo "  → https://docs.kurtosis.com/install 에서 설치하세요"
                    ;;
                "git")
                    echo "  → 패키지 매니저를 통해 설치하세요"
                    ;;
            esac
        fi
    done
}

# 3. Docker 상태 및 설정 확인
check_docker_environment() {
    check_item "Docker daemon 실행 상태"
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon이 실행되지 않고 있습니다"
        echo "  → Docker Desktop을 시작하거나 'sudo systemctl start docker' 실행"
        return
    fi
    
    log_success "Docker daemon이 정상 실행 중입니다"
    
    # Docker 리소스 설정 확인
    check_item "Docker 리소스 할당"
    
    # Docker Desktop의 메모리 설정 확인 (가능한 경우)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS Docker Desktop 설정 파일 확인
        docker_settings="$HOME/Library/Group Containers/group.com.docker/settings.json"
        if [[ -f "$docker_settings" ]]; then
            memory_gb=$(cat "$docker_settings" | python3 -c "import sys, json; print(json.load(sys.stdin).get('memoryMiB', 2048)/1024)" 2>/dev/null || echo "unknown")
            if [[ "$memory_gb" != "unknown" ]] && python3 -c "exit(0 if float('$memory_gb') >= 8 else 1)" 2>/dev/null; then
                log_success "Docker 메모리 할당: ${memory_gb}GB"
            elif [[ "$memory_gb" != "unknown" ]]; then
                log_warning "Docker 메모리 할당이 부족할 수 있습니다: ${memory_gb}GB (권장: 8GB+)"
                echo "  → Docker Desktop 설정에서 Resources > Advanced > Memory 증가"
            else
                log_warning "Docker 메모리 설정을 확인할 수 없습니다"
            fi
        else
            log_warning "Docker Desktop 설정을 확인할 수 없습니다"
        fi
    fi
    
    # Docker 네트워크 확인
    check_item "Docker 네트워크 연결"
    
    if docker run --rm alpine:latest ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_success "Docker 컨테이너 인터넷 연결 정상"
    else
        log_error "Docker 컨테이너에서 인터넷에 연결할 수 없습니다"
        echo "  → 네트워크 설정이나 방화벽을 확인하세요"
    fi
}

# 4. 시스템 리소스 확인
check_system_resources() {
    # 메모리 확인
    check_item "시스템 메모리"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 메모리 확인
        total_memory=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
        available_memory=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//' | awk '{print int($1 * 4096 / 1024 / 1024 / 1024)}')
    else
        # Linux 메모리 확인
        if command -v free >/dev/null 2>&1; then
            total_memory=$(free -g | awk 'NR==2{print $2}')
            available_memory=$(free -g | awk 'NR==2{print $7}')
        else
            total_memory="unknown"
            available_memory="unknown"
        fi
    fi
    
    if [[ "$total_memory" != "unknown" ]] && [[ "$available_memory" != "unknown" ]]; then
        if (( total_memory >= 16 )); then
            log_success "시스템 메모리: ${total_memory}GB (사용 가능: ${available_memory}GB)"
        elif (( total_memory >= 8 )); then
            log_warning "시스템 메모리: ${total_memory}GB (권장: 16GB+)"
            if (( available_memory < 4 )); then
                echo "  → 사용 가능한 메모리가 부족합니다. 다른 애플리케이션을 종료하세요"
            fi
        else
            log_error "시스템 메모리가 부족합니다: ${total_memory}GB (최소: 8GB)"
        fi
    else
        log_warning "시스템 메모리를 확인할 수 없습니다"
    fi
    
    # 디스크 공간 확인
    check_item "디스크 공간"
    
    available_disk=$(df -h . | awk 'NR==2{print $4}' | sed 's/G.*//')
    if [[ "$available_disk" =~ ^[0-9]+$ ]]; then
        if (( available_disk >= 20 )); then
            log_success "사용 가능한 디스크 공간: ${available_disk}GB"
        elif (( available_disk >= 10 )); then
            log_warning "사용 가능한 디스크 공간: ${available_disk}GB (권장: 20GB+)"
        else
            log_error "디스크 공간이 부족합니다: ${available_disk}GB (최소: 10GB)"
        fi
    else
        log_warning "디스크 공간을 확인할 수 없습니다"
    fi
}

# 5. 네트워크 포트 확인
check_network_ports() {
    check_item "필수 네트워크 포트"
    
    # Optimism devnet에서 사용하는 주요 포트들
    local ports=(8545 8546 9545 9546 7300 7301 8080 8081 9710 9711 9779 9730 9731)
    local blocked_ports=()
    
    for port in "${ports[@]}"; do
        if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
            blocked_ports+=($port)
        fi
    done
    
    if [[ ${#blocked_ports[@]} -eq 0 ]]; then
        log_success "모든 필수 포트가 사용 가능합니다"
    else
        log_warning "다음 포트들이 이미 사용 중입니다: ${blocked_ports[*]}"
        echo "  → 사용 중인 프로세스를 확인하려면: lsof -Pi :<포트번호>"
        
        # 각 블록된 포트의 프로세스 정보 표시
        for port in "${blocked_ports[@]}"; do
            process_info=$(lsof -Pi ":$port" -sTCP:LISTEN -n | tail -1)
            echo "    포트 $port: $process_info"
        done
    fi
}

# 6. Kurtosis 환경 확인
check_kurtosis_environment() {
    if ! command -v kurtosis >/dev/null 2>&1; then
        return  # 이미 필수 도구 체크에서 확인됨
    fi
    
    check_item "Kurtosis 환경"
    
    # 기존 enclave 확인
    if kurtosis enclave ls --output json >/dev/null 2>&1; then
        existing_enclaves=$(kurtosis enclave ls --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null | wc -l | xargs)
        if [[ "$existing_enclaves" -gt 0 ]]; then
            log_warning "$existing_enclaves개의 기존 Kurtosis enclave이 실행 중입니다"
            echo "  → 충돌을 방지하려면 'kurtosis enclave rm <enclave-name>' 명령으로 정리하세요"
            kurtosis enclave ls
        else
            log_success "Kurtosis 환경이 깨끗합니다"
        fi
    else
        log_warning "Kurtosis 상태를 확인할 수 없습니다"
    fi
}

# 7. 프로젝트 구조 확인
check_project_structure() {
    check_item "프로젝트 구조"
    
    local required_dirs=("kurtosis-devnet")
    local required_files=("kurtosis-devnet/simple.yaml")
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_success "디렉토리 존재: $dir"
        else
            log_error "필수 디렉토리가 없습니다: $dir"
        fi
    done
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "설정 파일 존재: $file"
        else
            log_error "필수 설정 파일이 없습니다: $file"
        fi
    done
}

# 8. 인터넷 연결 확인
check_internet_connectivity() {
    check_item "인터넷 연결"
    
    local test_urls=("github.com" "docker.io" "registry-1.docker.io")
    local failed_connections=0
    
    for url in "${test_urls[@]}"; do
        if ! ping -c 1 -W 3 "$url" >/dev/null 2>&1; then
            ((failed_connections++))
            log_warning "$url에 연결할 수 없습니다"
        fi
    done
    
    if [[ $failed_connections -eq 0 ]]; then
        log_success "모든 필수 서비스에 연결 가능합니다"
    elif [[ $failed_connections -lt ${#test_urls[@]} ]]; then
        log_warning "일부 서비스에 연결할 수 없습니다 (네트워크 지연 가능)"
    else
        log_error "인터넷 연결에 문제가 있습니다"
        echo "  → 네트워크 연결과 DNS 설정을 확인하세요"
    fi
}

# 최종 결과 요약
print_summary() {
    echo
    echo "=============================================="
    echo "           점검 결과 요약"
    echo "=============================================="
    echo -e "전체 점검 항목: $TOTAL_CHECKS"
    echo -e "${GREEN}통과: $PASSED_CHECKS${NC}"
    echo -e "${YELLOW}경고: $WARNING_CHECKS${NC}"  
    echo -e "${RED}실패: $FAILED_CHECKS${NC}"
    echo
    
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        if [[ $WARNING_CHECKS -eq 0 ]]; then
            echo -e "${GREEN}✓ 모든 점검을 통과했습니다! 배포를 시작할 수 있습니다.${NC}"
            echo
            echo "배포 명령어:"
            echo "  cd kurtosis-devnet"
            echo "  kurtosis run --enclave optimism-devnet github.com/ethpandaops/optimism-package --args-file simple.yaml"
        else
            echo -e "${YELLOW}⚠ 경고가 있지만 배포 시도가 가능합니다.${NC}"
            echo "   위의 경고 사항들을 검토한 후 배포를 시작하세요."
        fi
    else
        echo -e "${RED}✗ 중요한 문제가 발견되었습니다.${NC}"
        echo "   위의 실패 항목들을 해결한 후 배포를 시도하세요."
    fi
    
    echo
}

# 메인 실행 함수
main() {
    echo "=============================================="
    echo "    Optimism Devnet 배포 사전 점검"
    echo "=============================================="
    echo
    
    check_os_architecture
    check_required_tools
    check_docker_environment
    check_system_resources
    check_network_ports
    check_kurtosis_environment
    check_project_structure
    check_internet_connectivity
    
    print_summary
    
    # 점검 결과에 따른 exit code 반환
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi