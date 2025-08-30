#!/bin/bash

echo "=============================================="
echo "    Optimism Devnet 최종 배포 사전 점검"
echo "=============================================="
echo

# 현재 위치
echo "현재 디렉토리: $(pwd)"
echo

PASSED=0
FAILED=0
WARNINGS=0

echo "1. 필수 도구 확인"
echo "----------------"

# Docker 확인
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "✓ Docker: 정상 실행 중"
    ((PASSED++))
else
    echo "✗ Docker: 문제 있음"
    ((FAILED++))
fi

# Kurtosis 확인
if command -v kurtosis >/dev/null 2>&1; then
    echo "✓ Kurtosis: 설치됨"
    ((PASSED++))
else
    echo "✗ Kurtosis: 설치되지 않음"
    ((FAILED++))
fi

echo

echo "2. 프로젝트 구조 확인"
echo "-------------------"

# kurtosis-devnet 디렉토리 확인
if [[ -d "/Users/zena/tokamak-projects/optimism/kurtosis-devnet" ]]; then
    echo "✓ kurtosis-devnet 디렉토리: 존재함"
    ((PASSED++))
else
    echo "✗ kurtosis-devnet 디렉토리: 없음"
    ((FAILED++))
fi

# simple.yaml 파일 확인
if [[ -f "/Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml" ]]; then
    echo "✓ simple.yaml 설정 파일: 존재함"
    ((PASSED++))
else
    echo "✗ simple.yaml 설정 파일: 없음"
    ((FAILED++))
fi

echo

echo "3. 환경 정리 상태"
echo "----------------"

# Kurtosis enclaves 확인
enclave_count=$(kurtosis enclave ls 2>/dev/null | grep -c "^[0-9]" || echo "0")
if [[ "$enclave_count" -eq 0 ]]; then
    echo "✓ Kurtosis enclaves: 깨끗함 (${enclave_count}개)"
    ((PASSED++))
else
    echo "⚠ Kurtosis enclaves: ${enclave_count}개 실행 중"
    ((WARNINGS++))
fi

# 관련 컨테이너 확인
container_count=$(docker ps --filter "name=kurtosis" --filter "name=op-" 2>/dev/null | wc -l | xargs)
container_count=$((container_count - 1))  # 헤더 제외

if [[ "$container_count" -le 0 ]]; then
    echo "✓ 관련 Docker 컨테이너: 깨끗함"
    ((PASSED++))
else
    echo "⚠ 관련 Docker 컨테이너: ${container_count}개 실행 중"
    ((WARNINGS++))
fi

echo

echo "4. 시스템 리소스"
echo "---------------"

# 메모리 확인
if [[ "$OSTYPE" == "darwin"* ]]; then
    total_memory=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024)}' || echo "unknown")
    if [[ "$total_memory" != "unknown" ]] && (( total_memory >= 8 )); then
        echo "✓ 시스템 메모리: ${total_memory}GB"
        ((PASSED++))
    else
        echo "✗ 시스템 메모리: 부족 (${total_memory}GB)"
        ((FAILED++))
    fi
fi

# 디스크 공간 확인
available_disk=$(df -h /Users/zena/tokamak-projects/optimism 2>/dev/null | awk 'NR==2{print $4}' | sed 's/[^0-9].*//' || echo "unknown")
if [[ "$available_disk" != "unknown" ]] && [[ "$available_disk" =~ ^[0-9]+$ ]] && (( available_disk >= 10 )); then
    echo "✓ 디스크 공간: ${available_disk}GB 사용 가능"
    ((PASSED++))
else
    echo "⚠ 디스크 공간: 확인 필요 (${available_disk}GB)"
    ((WARNINGS++))
fi

echo

echo "=============================================="
echo "           최종 점검 결과"
echo "=============================================="
echo "통과: $PASSED"
echo "경고: $WARNINGS"
echo "실패: $FAILED"
echo

if [[ $FAILED -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo "🎉 모든 점검 통과! 배포 준비 완료"
        echo
        echo "다음 명령어로 배포 시작:"
        echo "  cd /Users/zena/tokamak-projects/optimism/kurtosis-devnet"
        echo "  kurtosis run --enclave optimism-devnet github.com/ethpandaops/optimism-package --args-file simple.yaml"
    else
        echo "⚠️  경고 항목이 있지만 배포 가능"
        echo "   경고 사항을 검토한 후 배포하세요."
    fi
else
    echo "❌ 해결이 필요한 문제가 있습니다"
    echo "   실패 항목들을 먼저 해결하세요."
    exit 1
fi

echo