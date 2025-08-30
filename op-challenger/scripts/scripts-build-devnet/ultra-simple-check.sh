#!/bin/bash

# 초간단 L1 Startup 사전 체크
echo "=== L1 Startup 필수 체크 ==="

# 1. Docker 실행 확인
if docker ps >/dev/null 2>&1; then
    echo "✓ Docker 실행 중"
else
    echo "✗ Docker 실행 안됨 - Docker를 시작하세요"
    exit 1
fi

# 2. Kurtosis 설치 확인  
if command -v kurtosis >/dev/null 2>&1; then
    echo "✓ Kurtosis 설치됨"
else
    echo "✗ Kurtosis 설치 안됨"
    exit 1
fi

# 3. 메모리 체크 (8GB 이상)
if [[ "$OSTYPE" == "darwin"* ]]; then
    memory_gb=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}' 2>/dev/null)
    if [[ "$memory_gb" -ge 8 ]]; then
        echo "✓ 메모리 충분: ${memory_gb}GB"
    else
        echo "⚠ 메모리 부족: ${memory_gb}GB (권장: 8GB+)"
    fi
fi

# 4. 핵심 포트 체크 (8545, 30303)
blocked=""
if lsof -Pi ":8545" -sTCP:LISTEN -t >/dev/null 2>&1; then
    blocked="8545 "
fi
if lsof -Pi ":30303" -sTCP:LISTEN -t >/dev/null 2>&1; then
    blocked="${blocked}30303"
fi

if [[ -n "$blocked" ]]; then
    echo "✗ 핵심 포트 사용 중: $blocked"
    echo "  → L1 체인 시작 실패 가능성 높음"
    echo "  → lsof -ti:포트번호 | xargs kill -9 로 정리"
    exit 1
else
    echo "✓ 핵심 포트 사용 가능"
fi

# 5. 인터넷 연결
if ping -c 1 -W 3000 8.8.8.8 >/dev/null 2>&1; then
    echo "✓ 인터넷 연결 정상"
else
    echo "⚠ 인터넷 연결 문제"
fi

echo
echo "🎉 L1 Startup 사전 체크 완료!"
echo "예상 시간: 6-10분"
echo
echo "다음 명령으로 배포 시작:"
echo "  ./build-devnet.sh"