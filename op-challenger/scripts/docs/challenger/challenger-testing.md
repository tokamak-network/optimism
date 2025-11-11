# OP-Challenger 기능 테스트 가이드

## 개요

로컬 devnet 환경에서 OP-Challenger의 기능을 테스트하는 방법들을 설명합니다.

## 사전 준비

### 1. 환경 확인
```bash
# Devnet이 실행 중인지 확인
kurtosis enclave inspect simple-devnet

# Challenger가 실행 중인지 확인
docker ps | grep op-challenger

# Challenger 로그 확인
docker logs -f op-challenger
```

### 2. 포트 정보 확인
```bash
# 현재 사용 중인 포트들을 확인
kurtosis enclave inspect simple-devnet | grep -E "(rpc|http)"
```

## 기본 테스트 시나리오

### 1. **연결 상태 테스트**

#### L1 RPC 연결 확인
```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:65502
```

#### L2 RPC 연결 확인
```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:49163
```

#### Rollup RPC 연결 확인
```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"optimism_outputAtBlock","params":["latest"],"id":1}' \
  http://localhost:49168
```

### 2. **게임 팩토리 상태 확인**

#### 게임 카운트 확인
```bash
# 컨테이너 내부에서 실행
docker exec op-challenger op-challenger list-games \
  --game-factory-address [GAME_FACTORY_ADDRESS] \
  --l1-eth-rpc http://localhost:65502
```

#### 팩토리 주소 확인
```bash
# Devnet 설정에서 게임 팩토리 주소 확인
kurtosis files download simple-devnet op-deployer-configs /tmp/
grep -i "DisputeGameFactoryProxy" /tmp/state.json
```

### 3. **챌린저 상태 모니터링**

#### 로그 모니터링 (실시간)
```bash
# 에러 로그만 필터링
docker logs -f op-challenger 2>&1 | grep -i error

# 성공 로그만 필터링
docker logs -f op-challenger 2>&1 | grep -i "success\|completed"

# 게임 관련 로그만 필터링
docker logs -f op-challenger 2>&1 | grep -i game
```

#### 메트릭스 확인 (메트릭스 활성화된 경우)
```bash
# 메트릭스 엔드포인트 확인
curl http://localhost:7300/metrics
```

## 고급 테스트 시나리오

### 4. **Dispute Game 생성 및 참여 테스트**

#### 새 게임 생성 (테스트용)
```bash
docker exec op-challenger op-challenger create-game \
  --game-factory-address [GAME_FACTORY_ADDRESS] \
  --l1-eth-rpc http://localhost:65502 \
  --l2-block-number [L2_BLOCK_NUMBER] \
  --private-key [TEST_PRIVATE_KEY]
```

#### 게임 클레임 리스트 확인
```bash
docker exec op-challenger op-challenger list-claims \
  --game-address [GAME_CONTRACT_ADDRESS] \
  --l1-eth-rpc http://localhost:65502
```

### 5. **트레이스 생성 테스트**

#### Cannon 트레이스 실행 테스트
```bash
docker exec op-challenger op-challenger run-trace \
  --trace-type cannon \
  --cannon-bin /cannon-bin/cannon \
  --cannon-server /op-program-bin/op-program \
  --cannon-prestates-url http://fileserver:8080/prestates \
  --l1-eth-rpc http://localhost:65502 \
  --l2-eth-rpc http://localhost:49163 \
  --rollup-rpc http://localhost:49168
```

### 6. **트랜잭션 관리 테스트**

#### 지갑 잔액 확인
```bash
# 챌린저 지갑 주소 확인 (로그에서 확인 가능)
docker logs op-challenger 2>&1 | grep -i "address\|wallet"

# L1에서 잔액 확인
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBalance","params":["[CHALLENGER_ADDRESS]","latest"],"id":1}' \
  http://localhost:65502
```

## 문제 해결 테스트

### 7. **일반적인 문제 시나리오**

#### "unsupported game type" 에러 해결
```bash
# 현재 설정된 trace-type 확인
docker logs op-challenger 2>&1 | grep -i "trace-type\|starting"

# 모든 게임 타입에서 cannon trace-type 사용
# run-challenger-devnet.sh는 자동으로 cannon 사용
```

#### 연결 실패 테스트
```bash
# 각 RPC 엔드포인트 응답 시간 측정
time curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:65502

# 네트워크 연결 확인
docker exec op-challenger netstat -tuln
```

### 8. **성능 테스트**

#### 리소스 사용량 모니터링
```bash
# CPU, 메모리 사용량 실시간 모니터링
docker stats op-challenger

# 디스크 사용량 확인
docker exec op-challenger df -h /data
```

#### 처리량 테스트
```bash
# 블록 처리 속도 확인
docker logs op-challenger 2>&1 | grep -i "block.*processed\|updated"

# 게임 업데이트 빈도 확인
docker logs op-challenger 2>&1 | grep -i "game.*update" | tail -20
```

## 자동화된 테스트 스크립트

### 종합 헬스체크 스크립트
```bash
#!/bin/bash
# challenger-healthcheck.sh

echo "=== OP-Challenger Health Check ==="

# 1. 컨테이너 상태 확인
if docker ps --format "{{.Names}}" | grep -q "op-challenger"; then
    echo "✅ Challenger container is running"
else
    echo "❌ Challenger container is not running"
    exit 1
fi

# 2. RPC 연결 테스트
L1_RPC_PORT=$(kurtosis enclave inspect simple-devnet | grep "rpc: 8545/tcp" | head -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ')
L2_RPC_PORT=$(kurtosis enclave inspect simple-devnet | grep "rpc: 8545/tcp" | tail -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ')

if curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "http://localhost:$L1_RPC_PORT" > /dev/null 2>&1; then
    echo "✅ L1 RPC connection successful"
else
    echo "❌ L1 RPC connection failed"
fi

if curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "http://localhost:$L2_RPC_PORT" > /dev/null 2>&1; then
    echo "✅ L2 RPC connection successful"
else
    echo "❌ L2 RPC connection failed"
fi

# 3. 최근 에러 확인
ERROR_COUNT=$(docker logs op-challenger --since="5m" 2>&1 | grep -c -i error)
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo "✅ No recent errors in logs"
else
    echo "⚠️  Found $ERROR_COUNT errors in last 5 minutes"
    echo "Recent errors:"
    docker logs op-challenger --since="5m" 2>&1 | grep -i error | tail -5
fi

echo "=== Health Check Complete ==="
```

## 테스트 결과 해석

### 정상 작동 지표
- ✅ 컨테이너가 지속적으로 실행 중
- ✅ L1/L2 RPC 연결 성공
- ✅ 게임 팩토리와 통신 가능
- ✅ 로그에 "scheduler" 및 "monitoring" 시작 메시지 확인
- ✅ 주기적인 블록 업데이트 로그

### 문제 지표
- ❌ "unsupported game type" 에러 반복
- ❌ RPC 연결 실패
- ❌ "failed to create game player" 에러
- ❌ 메모리/CPU 사용량 과도한 증가
- ❌ 컨테이너 재시작 반복

## 다음 단계

1. **기본 테스트 완료 후**: 실제 dispute game 참여 테스트
2. **고급 테스트 완료 후**: 멀티 챌린저 환경 테스트
3. **성능 테스트 완료 후**: 프로덕션 환경 배포 준비

## 관련 문서

- [Challenger Parameters](./challenger-parameters.md) - 설정 옵션 상세 설명
- [Troubleshooting Guide](../operations/troubleshooting-guide.md) - 문제 해결 방법
- [Challenger Guide](./challenger-guide.md) - 기본 사용법