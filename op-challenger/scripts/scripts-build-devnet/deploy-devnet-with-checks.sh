#!/bin/bash

# Devnet 배포 및 상태 확인 스크립트
# 작성자: Claude Code
# 설명: Optimism devnet 배포 중 발생할 수 있는 문제들을 실시간으로 모니터링하고 해결

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수들
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

# 시스템 리소스 확인
check_system_resources() {
    log_info "시스템 리소스 확인 중..."
    
    # 메모리 확인 (최소 8GB 권장)
    available_memory=$(free -g | awk 'NR==2{printf "%.1f", $7}' 2>/dev/null || echo "0")
    if command -v free >/dev/null 2>&1; then
        available_memory=$(free -g | awk 'NR==2{printf "%.1f", $7}')
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS용 메모리 확인
        available_memory=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//' | awk '{printf "%.1f", $1 * 4096 / 1024 / 1024 / 1024}')
    else
        available_memory="8.0"  # 기본값
    fi
    
    if (( $(echo "$available_memory < 4.0" | bc -l) )); then
        log_warning "사용 가능한 메모리가 부족합니다: ${available_memory}GB (권장: 8GB+)"
        log_warning "다른 애플리케이션을 종료하는 것을 권장합니다"
        read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "메모리 확인 완료: ${available_memory}GB 사용 가능"
    fi
    
    # 디스크 공간 확인 (최소 10GB 권장)
    available_disk=$(df -h . | awk 'NR==2{print $4}' | sed 's/G//' | sed 's/T/*1024/' | bc 2>/dev/null || echo "10")
    if (( $(echo "$available_disk < 10" | bc -l) )); then
        log_warning "디스크 공간이 부족합니다: ${available_disk}GB (권장: 10GB+)"
    else
        log_success "디스크 공간 확인 완료: ${available_disk}GB 사용 가능"
    fi
}

# 필요한 포트가 사용 중인지 확인
check_port_conflicts() {
    log_info "포트 충돌 확인 중..."
    
    # Optimism devnet에서 사용하는 주요 포트들
    ports=(8545 8546 9545 9546 7300 7301 8080 8081 9710 9711 9779 9730 9731)
    
    for port in "${ports[@]}"; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            log_warning "포트 $port이 이미 사용 중입니다"
            log_info "사용 중인 프로세스:"
            lsof -Pi :$port -sTCP:LISTEN
            read -p "포트 $port를 사용하는 프로세스를 종료하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                pid=$(lsof -Pi :$port -sTCP:LISTEN -t)
                kill -9 $pid 2>/dev/null || true
                log_success "포트 $port의 프로세스를 종료했습니다"
            fi
        fi
    done
    
    log_success "포트 충돌 확인 완료"
}

# Docker 상태 확인
check_docker_status() {
    log_info "Docker 상태 확인 중..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되어 있지 않습니다"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon이 실행되지 않고 있습니다"
        log_info "Docker를 시작해주세요"
        exit 1
    fi
    
    # Docker 리소스 제한 확인
    docker_memory=$(docker system info --format "{{.MemTotal}}" 2>/dev/null | awk '{printf "%.1f", $1/1024/1024/1024}')
    if [[ -n "$docker_memory" ]] && (( $(echo "$docker_memory < 8.0" | bc -l) )); then
        log_warning "Docker에 할당된 메모리가 부족합니다: ${docker_memory}GB (권장: 8GB+)"
        log_warning "Docker Desktop 설정에서 메모리 할당량을 증가시키세요"
    fi
    
    log_success "Docker 상태 확인 완료"
}

# 기존 devnet 정리
cleanup_existing_devnet() {
    log_info "기존 devnet 정리 중..."
    
    # Kurtosis enclaves 정리
    if command -v kurtosis &> /dev/null; then
        log_info "기존 Kurtosis enclaves 정리 중..."
        kurtosis enclave ls --output json 2>/dev/null | jq -r '.[].name' 2>/dev/null | while read enclave; do
            if [[ -n "$enclave" ]]; then
                log_info "Enclave 제거 중: $enclave"
                kurtosis enclave rm "$enclave" --force >/dev/null 2>&1 || true
            fi
        done
    fi
    
    # Docker 컨테이너 정리
    log_info "관련 Docker 컨테이너 정리 중..."
    docker ps -a --filter "name=kurtosis" --filter "name=op-" --filter "name=optimism" -q | xargs -r docker rm -f >/dev/null 2>&1 || true
    
    # Docker 네트워크 정리 
    log_info "관련 Docker 네트워크 정리 중..."
    docker network ls --filter "name=kurtosis" --filter "name=optimism" -q | xargs -r docker network rm >/dev/null 2>&1 || true
    
    log_success "기존 devnet 정리 완료"
}

# Docker 이미지 다운로드 진행률 모니터링
monitor_image_downloads() {
    log_info "Docker 이미지 다운로드 모니터링 중..."
    
    # 백그라운드에서 Docker 이벤트 모니터링
    docker events --filter type=image --format "table {{.Action}}\t{{.Actor.Attributes.name}}" &
    docker_events_pid=$!
    
    # 함수 종료시 모니터링 중단
    trap "kill $docker_events_pid 2>/dev/null || true" EXIT
}

# 배포 진행률 모니터링
monitor_deployment_progress() {
    local start_time=$(date +%s)
    local step_timeout=600  # 10분 타임아웃
    
    log_info "배포 진행률 모니터링 시작..."
    
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        # Kurtosis API 로그 확인
        if docker ps --filter "name=kurtosis-api" --format "table {{.Names}}" | grep -q kurtosis-api; then
            api_container=$(docker ps --filter "name=kurtosis-api" --format "{{.Names}}" | head -1)
            
            # 최근 로그에서 진행 상황 확인
            recent_logs=$(docker logs "$api_container" --tail 10 --since 30s 2>/dev/null || echo "")
            
            if echo "$recent_logs" | grep -q "ERROR\|FATAL\|error\|failed"; then
                log_error "배포 중 오류가 발생했습니다:"
                echo "$recent_logs" | grep -i "error\|fatal\|failed" | tail -5
                return 1
            elif echo "$recent_logs" | grep -q "Starting\|Running\|Listening\|Ready"; then
                log_info "진행 중... (경과 시간: ${elapsed}초)"
            fi
        fi
        
        # 타임아웃 체크
        if [ $elapsed -gt $step_timeout ]; then
            log_warning "배포가 예상보다 오래 걸리고 있습니다 (${elapsed}초 경과)"
            log_info "계속 기다리시거나 재시작을 시도할 수 있습니다"
            read -p "계속 기다리시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 1
            fi
            step_timeout=$((step_timeout + 300))  # 5분 더 기다리기
        fi
        
        sleep 10
    done
}

# 배포 상태 확인
check_deployment_health() {
    log_info "배포 상태 확인 중..."
    
    # 실행 중인 컨테이너 수 확인
    running_containers=$(docker ps --filter "name=kurtosis" --filter "name=op-" --format "{{.Names}}" | wc -l)
    
    if [ "$running_containers" -eq 0 ]; then
        log_error "실행 중인 devnet 컨테이너가 없습니다"
        return 1
    fi
    
    log_success "실행 중인 컨테이너: $running_containers개"
    
    # 각 컨테이너의 상태 확인
    docker ps --filter "name=kurtosis" --filter "name=op-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    return 0
}

# 재시작 함수
restart_deployment() {
    log_warning "배포를 재시작합니다..."
    cleanup_existing_devnet
    sleep 5
    start_deployment
}

# 배포 시작 함수
start_deployment() {
    log_info "Devnet 배포를 시작합니다..."
    
    # kurtosis-devnet 디렉토리로 이동
    if [ -d "kurtosis-devnet" ]; then
        cd kurtosis-devnet
    else
        log_error "kurtosis-devnet 디렉토리를 찾을 수 없습니다"
        exit 1
    fi
    
    # 배포 명령 실행
    if [ -f "simple.yaml" ]; then
        log_info "simple.yaml 구성으로 배포 시작..."
        kurtosis run --enclave optimism-devnet github.com/ethpandaops/optimism-package --args-file simple.yaml &
        deployment_pid=$!
        
        # 배포 모니터링
        monitor_deployment_progress &
        monitor_pid=$!
        
        # 배포 프로세스 대기
        wait $deployment_pid
        deployment_result=$?
        
        # 모니터링 프로세스 종료
        kill $monitor_pid 2>/dev/null || true
        
        if [ $deployment_result -eq 0 ]; then
            log_success "배포가 성공적으로 완료되었습니다!"
            check_deployment_health
        else
            log_error "배포가 실패했습니다"
            log_info "재시도하시겠습니까?"
            read -p "재시도 (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                restart_deployment
            fi
        fi
    else
        log_error "simple.yaml 구성 파일을 찾을 수 없습니다"
        exit 1
    fi
}

# 메인 함수
main() {
    log_info "=== Optimism Devnet 배포 헬스체크 시작 ==="
    
    # 필수 확인 단계들
    check_system_resources
    check_docker_status
    check_port_conflicts
    
    # 기존 환경 정리
    cleanup_existing_devnet
    
    # 이미지 다운로드 모니터링 시작
    monitor_image_downloads
    
    # 배포 시작
    start_deployment
    
    log_success "=== 모든 작업이 완료되었습니다 ==="
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi