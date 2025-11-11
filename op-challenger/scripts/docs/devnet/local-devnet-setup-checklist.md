# 로컬 Devnet 구축 환경설정 체크리스트

## 사용자가 시스템 구축 전 확인해야 할 사항들

### 1. 게임 타입 설정 확인

**확인 파일**: `rollup-config.json`
```bash
# 게임 타입이 올바르게 설정되었는지 확인
cat rollup-config.json | jq '.game_type'
```

**필수 확인사항**:
- [ ] `game_type` 필드가 존재하는가?
- [ ] 값이 0 (CANNON) 또는 1 (PERMISSIONED_CANNON)인가?
- [ ] 네트워크 요구사항에 맞는 타입인가?

### 2. 주소 설정 확인

**확인 파일**: `rollup-config.json` 또는 환경변수
```bash
# 필수 주소들이 설정되었는지 확인
echo "Sequencer: $SEQUENCER_ADDRESS"
echo "Admin: $ADMIN_ADDRESS" 
echo "Proposer: $PROPOSER_ADDRESS"
echo "Challenger: $CHALLENGER_ADDRESS"
```

**필수 주소들**:
- [ ] **Sequencer Address**: L2 블록 생성 권한
- [ ] **Admin Address**: 시스템 관리 권한
- [ ] **Proposer Address**: 출력 루트 제출 권한  
- [ ] **Challenger Address**: 분쟁 게임 참여 권한
- [ ] **Batcher Address**: 배치 제출 권한

### 3. 네트워크 파라미터 확인

**확인 파일**: `rollup-config.json`
```bash
# L2 블록 시간 설정 확인
cat rollup-config.json | jq '.block_time'

# 체인 ID 확인
cat rollup-config.json | jq '.l1_chain_id, .l2_chain_id'
```

**필수 파라미터들**:
- [ ] **L2 Block Time**: 몇 초마다 블록 생성할지 (기본: 2초)
- [ ] **L1 Chain ID**: L1 네트워크 식별자
- [ ] **L2 Chain ID**: L2 네트워크 식별자 
- [ ] **Sequencer Window**: 시퀀서 드리프트 허용 시간

### 4. 바이너리 준비 확인

```bash
# 필수 바이너리들이 빌드되었는지 확인
ls -la ../bin/
```

**필수 바이너리들**:
- [ ] `op-node`: L2 노드 실행
- [ ] `op-batcher`: 배치 제출
- [ ] `op-proposer`: 출력 루트 제출
- [ ] `op-challenger`: 분쟁 게임 참여
- [ ] `op-deployer`: 컨트랙트 배포
- [ ] `cannon` 또는 `op-program`: 오류 증명 생성

**바이너리 빌드 방법**:
```bash
./build-binaries-for-challenger.sh
```

### 5. Docker 이미지 확인

```bash
# 로컬 이미지들이 빌드되었는지 확인
docker images | grep -E "(op-node|op-batcher|op-proposer|op-challenger|op-deployer)"
```

**필수 이미지들**:
- [ ] `op-node:latest`
- [ ] `op-batcher:latest` 
- [ ] `op-proposer:latest`
- [ ] `op-challenger:latest`
- [ ] `op-deployer:latest`

### 6. Prestate 파일 확인

```bash
# Cannon prestate 파일 존재 확인
ls -la *.json | grep prestate
```

**필수 Prestate들**:
- [ ] **MT64 Prestate**: 모든 게임 타입에 공통으로 사용
- [ ] **Fileserver에서 hash 기반으로 자동 배포됨**
- [ ] **수동 prestate 파일 지정은 불필요함**

### 7. 설정 일관성 체크

**자동 검사 스크립트**:
```bash
# 모든 설정 파일의 game_type 일관성 확인
./scripts/check-game-type-consistency.sh
```

**수동 확인사항**:
- [ ] rollup-config.json의 `game_type`
- [ ] simple.yaml의 `proposer_params.game_type`
- [ ] 생성될 intent.yaml의 `respectedGameType`
- [ ] 모든 값이 동일한가?

## 구축 전 필수 환경변수 설정

```bash
# 기본 환경변수 설정
export SEQUENCER_ADDRESS="0x..."
export ADMIN_ADDRESS="0x..." 
export PROPOSER_ADDRESS="0x..."
export CHALLENGER_ADDRESS="0x..."
export BATCHER_ADDRESS="0x..."

# 게임 타입 설정 (선택)
export GAME_TYPE=1  # 1=PERMISSIONED_CANNON, 0=CANNON
```

## 로컬 구축 시 추가 고려사항

### 1. 포트 충돌 확인
```bash
# 사용될 포트들이 비어있는지 확인
netstat -an | grep -E "(8080|8545|8546|9222)"
```

### 2. 디스크 공간 확인
```bash
# 충분한 디스크 공간이 있는지 확인 (최소 10GB)
df -h .
```

### 3. 메모리 확인
```bash
# 시스템 메모리 확인 (최소 8GB 권장)
free -h
```

### 4. Docker Daemon 상태
```bash
# Docker가 실행 중인지 확인
docker info > /dev/null && echo "Docker OK" || echo "Docker 문제"
```

## 문제 해결 가이드

### 게임 타입 불일치 오류
```bash
# 오류: "unsupported game type: X"
# 해결: 모든 설정 파일의 게임 타입 통일

# 1. rollup-config.json 확인
cat rollup-config.json | jq '.game_type'

# 2. 생성된 intent.yaml 확인  
cat /tmp/current-devnet-config/intent.yaml | jq '.respectedGameType'

# 3. 배포된 컨트랙트 확인
cast call $OPTIMISM_PORTAL_ADDRESS "respectedGameType()" --rpc-url $L1_RPC_URL
```

### 바이너리 없음 오류
```bash
# 오류: "binary not found"
# 해결: 바이너리 빌드 실행
./build-binaries-for-challenger.sh

# 빌드 확인
ls -la ../bin/ | grep -E "(op-challenger|cannon)"
```

### 주소 누락 오류
```bash
# 오류: "address not set" 
# 해결: 필수 환경변수 설정
source .env  # 환경변수 파일이 있다면
# 또는 수동으로 각 주소 설정
```

이 체크리스트를 사용하여 구축 전 모든 필수 사항을 확인하고 문제를 미리 방지할 수 있습니다.