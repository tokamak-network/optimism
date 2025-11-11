# Optimism 전체 시스템 구동 가이드

## 목차
1. [시스템 개요](#시스템-개요)
2. [서비스 구성](#서비스-구성)
3. [사전 요구사항](#사전-요구사항)
4. [개발 환경 설정](#개발-환경-설정)
5. [Kurtosis Devnet를 통한 시스템 구동](#kurtosis-devnet를-통한-시스템-구동)
6. [각 서비스별 상세 설정](#각-서비스별-상세-설정)
7. [시스템 모니터링 및 디버깅](#시스템-모니터링-및-디버깅)
8. [문제 해결](#문제-해결)

---

## 시스템 개요

Optimism 스택은 Ethereum Layer 2 Rollup 솔루션으로, 다음과 같은 핵심 컴포넌트들로 구성됩니다:

```
┌─────────────────────────────────────────────────────────────┐
│                  Optimism Stack Architecture                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │    L1    │  │    L2    │  │ op-node  │  │op-batcher│   │
│  │ (geth)   │  │ (op-geth)│  │(rollup)  │  │(sequencer│   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  │  batcher)│   │
│       │             │             │         └────┬─────┘   │
│       └─────────────┴─────────────┴──────────────┘         │
│                         │                                   │
│       ┌─────────────────┼───────────────────┐              │
│       │                 │                   │              │
│  ┌────▼─────┐    ┌──────▼──────┐    ┌──────▼──────┐       │
│  │op-proposer│    │op-challenger│    │op-dispute- │       │
│  │(output   │    │(fault proof)│    │   mon      │       │
│  │proposer) │    └─────────────┘    └────────────┘       │
│  └──────────┘                                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 서비스 구성

### 핵심 서비스

#### 1. **L1 (Ethereum Layer 1)**
- **역할**: L1 블록체인 (로컬 개발용 또는 실제 네트워크)
- **포트**:
  - `8545`: HTTP JSON-RPC
  - `8546`: WebSocket JSON-RPC
- **기능**: L1 블록체인 시뮬레이션 및 스마트 컨트랙트 배포

#### 2. **L2 (Optimism Layer 2 - op-geth)**
- **역할**: L2 실행 레이어 (EVM 실행)
- **포트**:
  - `9545`: HTTP JSON-RPC
  - `8551`: Engine API (op-node 연결용)
- **기능**: L2 트랜잭션 실행 및 상태 관리

#### 3. **op-node (Rollup Node)**
- **역할**: Rollup 합의 레이어, L1↔L2 동기화
- **포트**:
  - `9546`: Rollup RPC
  - `9003`: P2P (TCP/UDP)
- **주요 기능**:
  - L1에서 블록 데이터 파싱
  - L2 상태 전이 검증
  - Sequencer 모드 지원

#### 4. **op-proposer (Output Proposer)**
- **역할**: L2 상태 루트를 L1에 제안
- **주요 설정**:
  - `--rollup-rpc`: op-node RPC 연결
  - `--l1-eth-rpc`: L1 연결
  - `--game-factory-address`: DisputeGameFactory 주소
- **기능**: 주기적으로 L2 output root를 L1에 제출

#### 5. **op-batcher (Batch Submitter)**
- **역할**: L2 트랜잭션을 배치로 묶어 L1에 제출
- **주요 설정**:
  - `--l1-eth-rpc`: L1 연결
  - `--l2-eth-rpc`: L2 연결
  - `--rollup-rpc`: op-node 연결
- **기능**: L2 트랜잭션 데이터를 압축하여 L1에 제출

#### 6. **op-challenger (Fault Proof Challenger)** ⭐
- **역할**: 무효한 output root에 이의 제기
- **지원 Trace Type**:
  - `cannon`: MIPS 기반 fault proof
  - `asterisc`: RISC-V 기반 fault proof (선택적)
- **주요 구성 요소**:
  - `cannon`: MIPS VM 시뮬레이터
  - `op-program`: Fault proof 프로그램
  - `prestate.bin.gz`: 초기 VM 상태

#### 7. **op-dispute-mon (Dispute Monitor)**
- **역할**: Dispute game 모니터링 및 알림
- **기능**: 게임 상태 추적 및 이상 상황 감지

---

## 사전 요구사항

### 필수 도구

```bash
# 1. Git
git --version  # >= 2.x

# 2. Docker & Docker Compose
docker --version          # >= 20.10
docker compose version    # >= 2.x

# 3. Go
go version  # >= 1.21

# 4. Node.js & pnpm (Contracts 빌드용)
node --version  # >= 18.x
pnpm --version  # >= 8.x

# 5. Foundry (Solidity 개발)
forge --version
cast --version

# 6. Python
python3 --version  # >= 3.9

# 7. jq (JSON 파싱)
jq --version

# 8. just (Task runner)
just --version

# 9. Kurtosis (Devnet 관리)
kurtosis version  # >= 최신 버전
```

### 설치 스크립트 (macOS/Linux)

```bash
# Homebrew (macOS)
brew install git docker go node pnpm jq python@3.9 just

# Foundry 설치
curl -L https://foundry.paradigm.xyz | bash
foundryup

# mise 설치 (도구 버전 관리)
curl https://mise.run | sh
mise install

# Kurtosis 설치
brew install kurtosis-tech/tap/kurtosis
# 또는
curl -L https://get.kurtosis.com | bash
```

---

## 개발 환경 설정

### 1. 저장소 클론

```bash
git clone https://github.com/ethereum-optimism/optimism.git
cd optimism
# 또는 특정 브랜치
git checkout feature/rat-poc-v1
```

### 2. 서브모듈 초기화

```bash
make submodules
# 또는
git submodule update --init --recursive
```

### 3. mise를 통한 개발 도구 설정

```bash
# mise 설정 확인
cat mise.toml

# 필요한 도구 설치
mise install
```

### 4. Contracts 빌드

```bash
cd packages/contracts-bedrock
just build
# 또는
forge build
```

### 5. Go 바이너리 빌드

```bash
# 루트 디렉토리에서
make build-go

# 개별 빌드
make op-node
make op-proposer
make op-batcher
make op-challenger
make op-dispute-mon
make op-program
make cannon
```

### 6. Cannon Prestate 생성

op-challenger는 cannon prestate가 필요합니다:

```bash
make cannon-prestates
```

**생성 파일**:
- `op-program/bin/prestate.bin.gz`: 초기 VM 상태 (압축)
- `op-program/bin/prestate-proof-*.json`: 증명 데이터
- `op-program/bin/meta-*.json`: 메타데이터

---

## Kurtosis Devnet를 통한 시스템 구동

Optimism은 Kurtosis를 사용하여 로컬 개발 환경을 구성합니다.

### 방법 1: Just를 사용한 빠른 시작 (권장)

#### Simple Devnet 시작

```bash
# Simple devnet 실행 (단일 L2 체인)
just simple-devnet
```

#### Interop Devnet 시작

```bash
# Interop devnet 실행 (여러 L2 체인, 상호운용성 테스트용)
just interop-devnet
```

#### Custom Devnet 시작

```bash
# 사용자 정의 설정으로 devnet 실행
just user-devnet <your-config.yaml>
```

**내부 동작**:
1. Docker Desktop 실행 확인
2. Kurtosis 엔진 시작
3. 필요한 Docker 이미지 빌드
4. L1 제네시스 및 스마트 컨트랙트 배포
5. L2 제네시스 생성
6. 모든 서비스 시작 (op-node, op-batcher, op-proposer, op-challenger 등)

### 방법 2: Kurtosis CLI 직접 사용

```bash
# Enclave 생성 및 실행
cd kurtosis-devnet
kurtosis run --enclave my-devnet .

# 특정 설정 파일 사용
kurtosis run --enclave my-devnet . --args-file simple.yaml
```

### Devnet 상태 확인

```bash
# 실행 중인 enclave 확인
kurtosis enclave ls

# Enclave 내 서비스 확인
kurtosis enclave inspect my-devnet

# 서비스 로그 확인
kurtosis service logs my-devnet <service-name>

# Docker 컨테이너 확인
docker ps | grep kurtosis
```

### Devnet 중지 및 정리

```bash
# Enclave 중지
kurtosis enclave stop my-devnet

# Enclave 삭제
kurtosis enclave rm my-devnet

# 완전 정리 (모든 enclave 및 네트워크)
kurtosis clean -a
```

---

## 각 서비스별 상세 설정

### op-node 설정

**바이너리 위치**: `./op-node/bin/op-node`

**주요 플래그**:
```bash
--l1=<L1_RPC_URL>                    # L1 연결
--l2=<L2_ENGINE_API_URL>             # L2 Engine API 연결
--l2.jwt-secret=<JWT_SECRET_PATH>    # Engine API JWT 인증
--rollup.config=<ROLLUP_JSON_PATH>   # Rollup 설정
--sequencer.enabled                  # 시퀀서 모드
--p2p.sequencer.key=<P2P_KEY>        # P2P 키
--rpc.addr=0.0.0.0
--rpc.port=9546
```

**환경 변수**:
```bash
OP_NODE_L1_ETH_RPC=http://localhost:8545
OP_NODE_L2_ENGINE_RPC=http://localhost:8551
OP_NODE_ROLLUP_CONFIG=./rollup.json
```

### op-challenger 설정

**바이너리 위치**: `./op-challenger/bin/op-challenger`

**기본 실행 명령**:
```bash
DISPUTE_GAME_FACTORY=$(jq -r .DisputeGameFactoryProxy addresses.json)

./op-challenger/bin/op-challenger \
  --trace-type cannon \
  --l1-eth-rpc http://localhost:8545 \
  --rollup-rpc http://localhost:9546 \
  --game-factory-address $DISPUTE_GAME_FACTORY \
  --datadir temp/challenger-data \
  --cannon-rollup-config rollup.json \
  --cannon-l2-genesis genesis-l2.json \
  --cannon-bin ./cannon/bin/cannon \
  --cannon-server ./op-program/bin/op-program \
  --cannon-prestate ./op-program/bin/prestate.bin.gz \
  --l2-eth-rpc http://localhost:9545 \
  --mnemonic "test test test test test test test test test test test junk" \
  --hd-path "m/44'/60'/0'/0/8" \
  --num-confirmations 1
```

**주요 설정**:
- `--trace-type`: 사용할 trace provider (cannon, asterisc 등)
- `--game-factory-address`: DisputeGameFactory 컨트랙트 주소
- `--datadir`: 게임 데이터 저장 경로
- `--cannon-prestate`: Cannon 초기 상태 파일

### op-proposer 설정

**바이너리 위치**: `./op-proposer/bin/op-proposer`

**환경 변수**:
```bash
OP_PROPOSER_L1_ETH_RPC=http://localhost:8545
OP_PROPOSER_ROLLUP_RPC=http://localhost:9546
OP_PROPOSER_POLL_INTERVAL=12s
OP_PROPOSER_GAME_FACTORY_ADDRESS=<FACTORY_ADDRESS>
OP_PROPOSER_PROPOSAL_INTERVAL=120s
OP_PROPOSER_MNEMONIC="test test test..."
OP_PROPOSER_HD_PATH=m/44'/60'/0'/0/1
```

### op-batcher 설정

**바이너리 위치**: `./op-batcher/bin/op-batcher`

**환경 변수**:
```bash
OP_BATCHER_L1_ETH_RPC=http://localhost:8545
OP_BATCHER_L2_ETH_RPC=http://localhost:9545
OP_BATCHER_ROLLUP_RPC=http://localhost:9546
OP_BATCHER_POLL_INTERVAL=1s
OP_BATCHER_MAX_CHANNEL_DURATION=1
OP_BATCHER_SUB_SAFETY_MARGIN=4
OP_BATCHER_MNEMONIC="test test test..."
OP_BATCHER_SEQUENCER_HD_PATH=m/44'/60'/0'/0/2
```

---

## 시스템 모니터링 및 디버깅

### Kurtosis를 통한 로그 확인

```bash
# Enclave 내 모든 서비스 로그
kurtosis service logs my-devnet

# 특정 서비스 로그
kurtosis service logs my-devnet op-challenger

# 실시간 로그 (follow)
kurtosis service logs my-devnet op-node -f

# 최근 N줄만 보기
kurtosis service logs my-devnet op-batcher --tail=100
```

### Docker를 통한 로그 확인

```bash
# 실행 중인 컨테이너 확인
docker ps | grep kurtosis

# 특정 컨테이너 로그
docker logs -f <container-id>

# 여러 컨테이너 동시 로그 확인 (docker-compose 유사)
docker compose logs -f  # (docker-compose.yml이 있는 경우)
```

### 서비스 상태 확인

```bash
# Kurtosis enclave 상태
kurtosis enclave inspect my-devnet

# 서비스 엔드포인트 확인
kurtosis service inspect my-devnet op-node

# L1 블록 높이 확인
cast block-number --rpc-url http://localhost:8545

# L2 블록 높이 확인
cast block-number --rpc-url http://localhost:9545
```

### 메트릭 확인

각 서비스는 Prometheus 메트릭을 노출합니다 (포트는 환경에 따라 다를 수 있음):

```bash
# op-node 메트릭
curl http://localhost:7300/metrics

# op-proposer 메트릭
curl http://localhost:7302/metrics

# op-batcher 메트릭
curl http://localhost:7301/metrics
```

**주요 메트릭**:
- `op_node_sync_status`: 동기화 상태
- `op_challenger_games_in_progress`: 진행 중 게임 수
- `op_challenger_games_challenger_won`: 챌린저 승리 게임 수
- `op_proposer_proposals_submitted`: 제출된 제안 수
- `op_batcher_batches_submitted`: 제출된 배치 수

### Dispute Game 상호작용

#### 게임 목록 조회

```bash
./op-challenger/bin/op-challenger list-games \
  --l1-eth-rpc http://localhost:8545 \
  --game-factory-address <FACTORY_ADDRESS>
```

#### 특정 게임 클레임 조회

```bash
./op-challenger/bin/op-challenger list-claims \
  --l1-eth-rpc http://localhost:8545 \
  --game-address <GAME_ADDRESS>
```

#### 수동 게임 생성

```bash
./op-challenger/bin/op-challenger create-game \
  --l1-eth-rpc http://localhost:8545 \
  --game-factory-address <FACTORY_ADDRESS> \
  --output-root <OUTPUT_ROOT> \
  --l2-block-num <L2_BLOCK_NUM> \
  --private-key <PRIVATE_KEY>
```

---

## 문제 해결

### 1. AnchorStateRegistry Cold Start 문제

**증상**: op-challenger 로그에 `"Provider: 0x... | Contract: 0xdead..."`과 같은 에러 발생

**원인**:
- CANNON 모드 (game_type: 0)는 L2OutputOracle를 사용하지 않음
- AnchorStateRegistry가 초기화 플레이스홀더 값(`0xdead...`)으로 시작
- 첫 번째 유효한 dispute game이 해결되어야 적절한 anchor state가 설정됨

**해결 방법**:

1. **자동 해결 (권장)**:
   ```bash
   # justfile에 fix-anchor-state 타겟이 있는 경우
   just fix-anchor-state
   ```

2. **수동 해결**:
   - 첫 번째 유효한 dispute game 생성 및 해결
   - 자세한 방법은 `op-challenger/scripts/docs/anchor-state-fix.md` 참조

### 2. Kurtosis 엔진 시작 오류

**증상**: `error ensuring kurtosis engine is running`

**해결**:
```bash
# Docker Desktop이 실행 중인지 확인
docker ps

# Docker Desktop 재시작
# (또는 OrbStack 등 대체 도구)
```

### 3. 네트워크 이미 존재 오류

**증상**: `network with name kt-interop-devnet already exists`

**해결**:
```bash
# Kurtosis 엔진 중지
kurtosis engine stop

# 기존 네트워크 삭제
docker network rm kt-interop-devnet

# 모든 kt-* 네트워크 확인 및 삭제
docker network ls | grep kt-
docker network rm <network-name>
```

### 4. AUTOFIX 모드를 통한 자동 복구

**일반 정리 모드**:
```bash
AUTOFIX=true just simple-devnet
```
- 쉘 설정 및 의존성 업데이트
- 중단된 네트워크 및 devnet 정리
- 다른 실행 중인 enclave는 보존

**전체 초기화 모드**:
```bash
AUTOFIX=nuke just simple-devnet
```
- 완전한 Kurtosis 환경 리셋
- 모든 네트워크 및 컨테이너 제거
- 새로운 시작이 필요할 때 사용

### 5. Prestate 누락 오류

**증상**: op-challenger가 시작되지 않거나 prestate 파일 관련 에러

**해결**:
```bash
# Prestate 재생성
make cannon-prestates

# 생성된 파일 확인
ls -la op-program/bin/
```

### 6. 컨트랙트 주소 누락

**증상**: `--game-factory-address` 등이 설정되지 않음

**해결**:
```bash
# Kurtosis devnet 출력에서 주소 확인
kurtosis enclave inspect my-devnet

# addresses.json 파일 확인 (Kurtosis가 생성)
cat <devnet-output-path>/addresses.json | jq

# 주요 주소 추출
FACTORY_ADDRESS=$(cat addresses.json | jq -r .DisputeGameFactoryProxy)
echo $FACTORY_ADDRESS
```

### 7. 포트 충돌

**증상**: 서비스가 시작되지 않고 "address already in use" 에러

**해결**:
```bash
# 포트 사용 확인
lsof -i :8545
lsof -i :9545
lsof -i :9546

# 프로세스 종료
kill -9 <PID>

# 또는 Kurtosis를 통해 깨끗하게 정리
kurtosis clean -a
```

### 8. 디스크 공간 부족

**확인**:
```bash
docker system df
docker volume ls
```

**정리**:
```bash
# 사용하지 않는 볼륨 제거
docker volume prune

# 전체 정리
docker system prune -a --volumes

# Kurtosis 데이터 정리
kurtosis clean -a
```

---

## 고급 사용법

### 게임 타입 이해

Optimism은 여러 가지 dispute game 타입을 지원합니다:

- **CANNON (game_type: 0)**: MIPS 기반 fault proof
- **PERMISSIONED_CANNON (game_type: 1)**: 권한이 있는 사용자만 참여 가능한 CANNON

자세한 내용은 `op-challenger/scripts/docs/game-types.md` 참조

### Prestate 동기화

**AUTOFIX 모드**가 활성화되면 prestate 빌드와 동기화가 자동으로 트리거됩니다.

자세한 내용은 `op-challenger/scripts/docs/prestate-synchronization.md` 참조

### 테스트 실행

```bash
# Go 단위 테스트
make test

# 특정 패키지 테스트
go test ./op-challenger/... -v

# E2E 테스트
cd op-e2e
go test ./... -v

# Contracts 테스트
cd packages/contracts-bedrock
just test
```

---

## 참고 자료

### 공식 문서
- [Optimism Specs](https://specs.optimism.io)
- [Fault Proof Specs](https://specs.optimism.io/experimental/fault-proof/)
- [Kurtosis Documentation](https://docs.kurtosis.com)

### 프로젝트 내 문서
- `README.md`: 프로젝트 개요
- `CONTRIBUTING.md`: 개발 가이드
- `op-challenger/README.md`: op-challenger 사용법
- `op-challenger/scripts/docs/`: 상세 가이드 모음
  - `game-types.md`: 게임 타입 설명
  - `anchor-state-fix.md`: AnchorStateRegistry 문제 해결
  - `prestate-synchronization.md`: Prestate 동기화 가이드
- `kurtosis-devnet/README.md`: Kurtosis devnet 사용법

### 주요 파일
- `Makefile`: 빌드 및 테스트 스크립트
- `justfile`: Task runner 설정
- `mise.toml`: 개발 도구 버전 관리
- `kurtosis-devnet/*.yaml`: Devnet 설정 파일

### 추가 도구
- **op-dispute-mon**: 게임 모니터링 대시보드
- **cannon**: MIPS VM 시뮬레이터
- **op-program**: Fault proof 프로그램
- **cast**: Foundry CLI 도구 (컨트랙트 상호작용)

---

## 유용한 명령어 모음

### 개발 워크플로우

```bash
# 전체 빌드
make build

# Go 컴포넌트만 빌드
make build-go

# Contracts만 빌드
make build-contracts

# 코드 변경 후 재빌드 (op-challenger)
make op-challenger

# Devnet 재시작
kurtosis enclave rm my-devnet
just simple-devnet

# 로그 실시간 모니터링
kurtosis service logs my-devnet op-challenger -f | grep -i "game"
```

### 정리 명령어

```bash
# Go 빌드 아티팩트 정리
make clean

# 완전 정리 (git clean 포함)
make nuke

# Kurtosis 정리
kurtosis clean -a

# Docker 정리
docker system prune -a --volumes
```

---

**문서 버전**: 1.0
**작성일**: 2025-01-17
**대상 프로젝트**: Optimism
**기반 브랜치**: feature/rat-poc-v1
