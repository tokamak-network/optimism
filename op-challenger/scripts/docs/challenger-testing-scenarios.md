# OP-Challenger 동작 확인 시나리오 및 테스트 가이드

## 개요
로컬 devnet에서 OP-Challenger의 올바른 동작을 확인하기 위한 테스트 시나리오와 검증 방법

## 사전 준비사항

### 1. Devnet 상태 확인
```bash
# 1. Devnet이 실행 중인지 확인
kurtosis enclave inspect op-devnet

# 2. 모든 서비스가 RUNNING 상태인지 확인
docker ps | grep -E "(op-challenger|op-proposer|op-node)"

# 3. 게임 타입 설정 확인
cat /tmp/current-devnet-config/rollup-*.json | jq '.game_type'
```

### 2. 필수 환경변수 설정
```bash
export L1_RPC_URL="http://localhost:8545"
export L2_RPC_URL="http://localhost:9545" 
export OPTIMISM_PORTAL_ADDRESS=$(cat /tmp/current-devnet-config/deployment-*.json | jq -r '.OptimismPortalProxy')
export DISPUTE_GAME_FACTORY_ADDRESS=$(cat /tmp/current-devnet-config/deployment-*.json | jq -r '.DisputeGameFactoryProxy')
```

## 테스트 시나리오

### 시나리오 1: 정상 출력 루트 제출 확인

**목적**: OP-Proposer가 올바른 게임 타입으로 출력을 제출하는지 확인

**단계**:
```bash
# 1. 현재 게임 수 확인
BEFORE_COUNT=$(cast call $DISPUTE_GAME_FACTORY_ADDRESS "gameCount()" --rpc-url $L1_RPC_URL)
echo "제출 전 게임 수: $BEFORE_COUNT"

# 2. L2에서 트랜잭션 발생시켜 출력 생성 유도
cast send $RANDOM_ADDRESS "0x" --value 1ether --rpc-url $L2_RPC_URL --private-key $PRIVATE_KEY

# 3. 10분 대기 (proposal_interval: 10m)
echo "OP-Proposer가 출력을 제출할 때까지 대기..."
sleep 600

# 4. 새로운 게임이 생성되었는지 확인
AFTER_COUNT=$(cast call $DISPUTE_GAME_FACTORY_ADDRESS "gameCount()" --rpc-url $L1_RPC_URL)
echo "제출 후 게임 수: $AFTER_COUNT"

# 5. 게임 타입 확인
LATEST_GAME_INDEX=$((AFTER_COUNT - 1))
GAME_TYPE=$(cast call $DISPUTE_GAME_FACTORY_ADDRESS "gameAtIndex(uint256)" $LATEST_GAME_INDEX --rpc-url $L1_RPC_URL | cut -c1-2)
echo "생성된 게임 타입: $GAME_TYPE"
```

**성공 기준**:
- 게임 수가 증가함
- 생성된 게임 타입이 설정된 값과 일치 (0x01 = Type 1)

### 시나리오 2: OP-Challenger 게임 감지 확인

**목적**: OP-Challenger가 생성된 분쟁 게임을 올바르게 감지하고 처리하는지 확인

**단계**:
```bash
# 1. OP-Challenger 로그 모니터링 시작
docker logs -f $(docker ps -q --filter "name=op-challenger") &
LOG_PID=$!

# 2. 새로운 게임 생성 대기 (시나리오 1 실행)
echo "새로운 분쟁 게임이 생성되기를 대기 중..."

# 3. 로그에서 게임 감지 메시지 확인
sleep 30
kill $LOG_PID
```

**성공 기준**:
- "Found dispute game" 메시지가 로그에 나타남
- "unsupported game type" 오류가 없음
- 게임 타입이 올바르게 인식됨

### 시나리오 3: 분쟁 상황 시뮬레이션

**목적**: 실제 분쟁이 발생했을 때 OP-Challenger가 올바르게 대응하는지 확인

**단계**:
```bash
# 1. 잘못된 출력 루트 제출 (테스트용)
# 주의: 이것은 테스트 환경에서만 수행

# 2. OP-Challenger가 분쟁을 감지하는지 확인
docker logs op-challenger | grep -E "(dispute|challenge|fault)"

# 3. 분쟁 게임 상태 확인
GAME_ADDRESS=$(cast call $DISPUTE_GAME_FACTORY_ADDRESS "games(uint32,bytes32,bytes32)" $GAME_TYPE $ROOT_CLAIM $EXTRA_DATA --rpc-url $L1_RPC_URL)
cast call $GAME_ADDRESS "status()" --rpc-url $L1_RPC_URL
```

**성공 기준**:
- OP-Challenger가 분쟁을 감지함
- 적절한 반박 증명을 제출함
- 게임 상태가 올바르게 진행됨

### 시나리오 4: Trace Type 호환성 확인

**목적**: 설정된 게임 타입과 trace type이 호환되는지 확인

**단계**:
```bash
# 1. OP-Challenger 설정 확인
docker exec op-challenger printenv | grep -E "TRACE_TYPE|GAME_TYPE"

# 2. 지원되는 trace type 확인
docker logs op-challenger | grep -E "(cannon|permissioned)" | tail -10

# 3. 호환성 매트릭스 확인
echo "Game Type 1 (PERMISSIONED) + Trace Type cannon = ✅"
echo "Game Type 0 (CANNON) + Trace Type cannon = ✅"  
```

**호환성 매트릭스**:
| Game Type | 지원 Trace Types | 설명 |
|-----------|-----------------|------|
| 0 (CANNON) | cannon | 표준 Fault Proof |
| 1 (PERMISSIONED) | cannon | 제한된 참여자, cannon trace 사용 |

## 자동화된 테스트 스크립트

### 전체 헬스체크 스크립트
```bash
#!/bin/bash
# challenger-health-check.sh

set -e

echo "=== OP-Challenger 헬스체크 시작 ==="

# 1. 설정 일관성 확인
echo "1. 게임 타입 설정 일관성 확인..."
ROLLUP_GAME_TYPE=$(cat /tmp/current-devnet-config/rollup-*.json | jq -r '.game_type')
INTENT_GAME_TYPE=$(cat /tmp/current-devnet-config/intent.yaml | yq -r '.respectedGameType')
echo "Rollup Config: $ROLLUP_GAME_TYPE, Intent: $INTENT_GAME_TYPE"

# 2. 서비스 상태 확인
echo "2. 서비스 상태 확인..."
docker ps --filter "name=op-challenger" --format "table {{.Names}}\t{{.Status}}"

# 3. 로그에서 오류 확인
echo "3. 최근 오류 로그 확인..."
docker logs op-challenger --since=1m | grep -E "(ERROR|FATAL|unsupported)" || echo "오류 없음"

# 4. 게임 생성 상태 확인
echo "4. 분쟁 게임 팩토리 상태..."
GAME_COUNT=$(cast call $DISPUTE_GAME_FACTORY_ADDRESS "gameCount()" --rpc-url $L1_RPC_URL)
echo "총 게임 수: $GAME_COUNT"

echo "=== 헬스체크 완료 ==="
```

### 성능 벤치마크 테스트
```bash
#!/bin/bash  
# challenger-performance-test.sh

echo "=== OP-Challenger 성능 테스트 시작 ==="

# 1. 응답 시간 측정
echo "1. 게임 감지 응답 시간 측정..."
START_TIME=$(date +%s)

# 새 게임 생성 (시나리오 1 실행)
# ...

# OP-Challenger가 감지할 때까지 시간 측정
END_TIME=$(date +%s)
RESPONSE_TIME=$((END_TIME - START_TIME))
echo "게임 감지 시간: ${RESPONSE_TIME}초"

# 2. 메모리 사용량 확인
echo "2. 메모리 사용량 확인..."
docker stats op-challenger --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# 3. 처리량 확인
echo "3. 게임 처리 처리량..."
PROCESSED_GAMES=$(docker logs op-challenger | grep -c "processing game" || echo 0)
echo "처리된 게임 수: $PROCESSED_GAMES"

echo "=== 성능 테스트 완료 ==="
```

## 문제 해결 절차

### 1. "unsupported game type" 오류 시
```bash
# 문제 진단
echo "=== 게임 타입 불일치 문제 진단 ==="

# 설정 확인
echo "Rollup Config:" $(cat rollup-config.json | jq '.game_type')
echo "Intent Config:" $(cat /tmp/current-devnet-config/intent.yaml | yq '.respectedGameType')

# 배포된 값 확인
echo "Deployed Contract:" $(cast call $OPTIMISM_PORTAL_ADDRESS "respectedGameType()" --rpc-url $L1_RPC_URL)

# 해결방안: 설정 통일 후 재배포
```

### 2. OP-Challenger 시작 실패 시
```bash
# 문제 진단
echo "=== OP-Challenger 시작 실패 진단 ==="

# 바이너리 확인
ls -la ../bin/op-challenger || echo "바이너리 없음 - 빌드 필요"

# 설정 파일 확인
cat /tmp/current-devnet-config/*.yaml | grep -A5 challenger

# 네트워크 연결 확인
curl -s $L1_RPC_URL > /dev/null && echo "L1 RPC 연결 OK" || echo "L1 RPC 연결 실패"
```

### 3. 게임 감지 안됨 시
```bash
# 문제 진단
echo "=== 게임 감지 실패 진단 ==="

# 게임 팩토리 상태 확인
cast call $DISPUTE_GAME_FACTORY_ADDRESS "gameCount()" --rpc-url $L1_RPC_URL

# OP-Challenger 구독 상태 확인
docker logs op-challenger | grep -E "(subscribe|listening)"

# 이벤트 필터링 확인
docker logs op-challenger | grep -E "(filter|event)"
```

## 검증 완료 기준

모든 테스트 시나리오 완료 후:

✅ **설정 일관성**: 모든 컴포넌트가 동일한 게임 타입 사용  
✅ **게임 생성**: OP-Proposer가 올바른 타입으로 게임 생성  
✅ **게임 감지**: OP-Challenger가 게임을 정상 감지  
✅ **분쟁 처리**: 분쟁 상황에서 적절한 대응  
✅ **성능**: 합리적인 응답 시간과 리소스 사용량  

이러한 시나리오를 통해 OP-Challenger가 로컬 환경에서 올바르게 동작함을 검증할 수 있습니다.