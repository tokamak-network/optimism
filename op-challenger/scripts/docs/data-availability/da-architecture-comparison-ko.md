# Data Availability (DA) 아키텍처 비교: Tokamak Thanos vs Optimism

## 목차
1. [개요](#개요)
2. [DA 시스템이란?](#da-시스템이란)
3. [Tokamak Thanos의 Plasma DA](#tokamak-thanos의-plasma-da)
4. [Optimism의 Alt-DA](#optimism의-alt-da)
5. [아키텍처 비교](#아키텍처-비교)
6. [비용 vs 보안 트레이드오프](#비용-vs-보안-트레이드오프)
7. [Alt-DA 활성화 방법](#alt-da-활성화-방법)
8. [권장사항](#권장사항)

---

## 개요

Optimism과 Tokamak Thanos는 모두 Optimism 스택을 기반으로 하지만, **Data Availability (데이터 가용성)** 전략에서 중요한 차이가 있습니다. 이 문서는 두 시스템의 DA 아키텍처를 비교하고, 각각의 설계 철학과 사용 사례를 설명합니다.

### 핵심 차이점

| 항목 | Tokamak Thanos | Optimism |
|------|----------------|----------|
| **기본 DA 방식** | Plasma DA | Calldata |
| **DA 서버** | 필수 (`da-server` 서비스) | 선택적 (`op-alt-da`) |
| **데이터 저장 위치** | 외부 DA 서버 | L1 블록체인 (calldata) |
| **비용** | 낮음 | 높음 |
| **보안성** | 중간 (DA 서버 신뢰 필요) | 높음 (L1 보안 상속) |
| **설계 철학** | 비용 효율성 우선 | 보안 및 탈중앙화 우선 |

---

## DA 시스템이란?

### Data Availability의 중요성

Rollup은 트랜잭션 실행을 L2에서 처리하지만, **트랜잭션 데이터**를 어딘가에 저장해야 합니다. 이는 다음과 같은 이유로 중요합니다:

1. **상태 재구성**: 누구나 L2 상태를 독립적으로 재구성할 수 있어야 함
2. **Fraud Proof**: 무효한 상태 전이를 증명하기 위해 데이터 필요
3. **검증 가능성**: 검증자가 시퀀서의 행동을 감시할 수 있어야 함

### 두 가지 주요 접근 방식

#### 1. **Calldata 방식** (Optimism 기본)
```
L2 Transaction → op-batcher → L1 Calldata → 영구 저장
                                  ↓
                          모든 노드가 접근 가능
```

**장점:**
- L1의 보안과 탈중앙화 상속
- 데이터 영구성 보장
- 추가 신뢰 가정 없음

**단점:**
- L1 calldata 비용이 높음 (가스비의 대부분 차지)
- 스토리지 비용 증가

#### 2. **Alt-DA/Plasma 방식** (Tokamak Thanos 기본)
```
L2 Transaction → op-batcher → DA Server → 외부 스토리지
                              ↓
                    L1에 커밋먼트만 제출
```

**장점:**
- L1 비용 대폭 절감 (90% 이상)
- 높은 처리량

**단점:**
- DA 서버 신뢰 필요
- 데이터 가용성 위험 (서버 다운 시)
- 추가 인프라 운영 필요

---

## Tokamak Thanos의 Plasma DA

### 아키텍처

Tokamak Thanos는 **Plasma 모드**를 기본으로 사용하며, 전용 DA 서버를 운영합니다.

```
┌─────────────────────────────────────────────────────────────┐
│              Tokamak Thanos DA Architecture                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐            │
│  │ op-node  │────▶│ op-batcher│────▶│ da-server│            │
│  │          │     │           │     │  :3100   │            │
│  └──────────┘     └──────────┘     └─────┬────┘            │
│       │                                   │                 │
│       │ plasma.enabled=true               │                 │
│       │ plasma.da-server=...              ▼                 │
│       │                            ┌──────────────┐         │
│       │                            │File Storage  │         │
│       │                            │/data         │         │
│       │                            └──────────────┘         │
│       │                                                     │
│       │    ┌────────────────────────────────────┐          │
│       └───▶│ L1 (commitment only)               │          │
│            │ - 커밋먼트 해시만 제출               │          │
│            │ - 실제 데이터는 DA 서버에 저장       │          │
│            └────────────────────────────────────┘          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Docker Compose 설정

```yaml
# ops-bedrock/docker-compose.yml (Tokamak Thanos)
services:
  da-server:
    image: tokamaknetwork/thanos-da-server:latest
    build:
      context: ..
      dockerfile: ops/docker/op-stack-go/Dockerfile
      target: da-server-target
    ports:
      - "3100:3100"
    command: |
      da-server \
        --file.path=/data \
        --addr=0.0.0.0 \
        --port=3100 \
        --log.level=debug \
        --generic-commitment=${PLASMA_GENERIC_DA}
    volumes:
      - da_data:/data

  op-node:
    environment:
      - PLASMA_ENABLED=true
      - PLASMA_DA_SERVER=http://da-server:3100
    command: |
      op-node \
        --plasma.enabled=true \
        --plasma.da-server=http://da-server:3100 \
        ...

  op-batcher:
    environment:
      - OP_BATCHER_PLASMA_ENABLED=true
      - OP_BATCHER_PLASMA_DA_SERVER=http://da-server:3100
    depends_on:
      - da-server

volumes:
  da_data:
```

### 환경 변수

```bash
# .env 파일
PLASMA_ENABLED=true
PLASMA_DA_SERVICE=true
PLASMA_GENERIC_DA=false

# DA 서버 주소
DA_SERVER_URL=http://da-server:3100
```

### 데이터 흐름

1. **트랜잭션 배치 생성**
   ```
   op-batcher: L2 트랜잭션 수집 → 배치 생성
   ```

2. **DA 서버에 저장**
   ```
   op-batcher → POST /data → da-server
   da-server → 파일 시스템에 저장 → 커밋먼트 반환
   ```

3. **L1에 커밋먼트 제출**
   ```
   op-batcher → L1 트랜잭션 (커밋먼트 해시만 포함)
   ```

4. **검증자 데이터 조회**
   ```
   검증자 → GET /data/{commitment} → da-server
   da-server → 저장된 데이터 반환
   ```

---

## Optimism의 Alt-DA

### 아키텍처

Optimism에서는 DA 서버가 **선택적(optional)** 컴포넌트가 되었습니다. 기본적으로 **Calldata 방식**을 사용하며, 필요한 경우 **Alt-DA**를 활성화할 수 있습니다.

```
┌─────────────────────────────────────────────────────────────┐
│                Optimism DA Architecture                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │            기본 모드: Calldata                        │   │
│  │                                                       │   │
│  │  op-batcher ──────────────────▶ L1 Calldata         │   │
│  │                                   (전체 데이터)       │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │      선택적 모드: Alt-DA (활성화 필요)                 │   │
│  │                                                       │   │
│  │  op-batcher ──▶ op-alt-da (daserver) ──▶ Storage   │   │
│  │              │                           (S3/LevelDB)│   │
│  │              └──▶ L1 (커밋먼트만)                     │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 프로젝트 구조

```
optimism/
├── op-alt-da/                    # Alt-DA 구현
│   ├── cmd/
│   │   └── daserver/            # DA 서버 실행 파일
│   │       ├── main.go
│   │       ├── flags.go
│   │       └── README.md        # 설정 가이드
│   ├── daclient.go              # DA 클라이언트
│   ├── damgr.go                 # DA 관리자
│   ├── daserver.go              # DA 서버 로직
│   ├── commitment.go            # 커밋먼트 처리
│   ├── Dockerfile               # Docker 이미지
│   ├── Makefile
│   └── justfile
```

### 기본 설정 (Kurtosis Devnet)

```yaml
# kurtosis-devnet/simple.yaml
optimism_package:
  chains:
    op-kurtosis:
      batcher_params:
        image: {{ localDockerImage "op-batcher" }}
        extra_params: []
        # Alt-DA 설정 없음 → Calldata 모드 사용
```

**주목할 점:**
- `simple.yaml`에 `plasma` 또는 `alt-da` 관련 설정이 **전혀 없음**
- 이는 Optimism이 기본적으로 Calldata 방식을 사용함을 의미

---

## 아키텍처 비교

### 서비스 구성 비교

#### Tokamak Thanos

```yaml
services:
  l1:         # L1 노드
  l2:         # L2 노드
  op-node:    # Rollup 노드
  op-batcher: # 배치 제출자
  op-proposer: # Output 제안자
  op-challenger: # 챌린저
  da-server:  # ⭐ Plasma DA 서버 (필수)
  artifact-server: # 설정 파일 서버
```

#### Optimism

```yaml
services:
  l1:         # L1 노드 (Kurtosis enclave)
  l2:         # L2 노드 (Kurtosis enclave)
  op-node:    # Rollup 노드
  op-batcher: # 배치 제출자 (Calldata 모드)
  op-proposer: # Output 제안자
  op-challenger: # 챌린저
  # da-server 없음 (선택적)
```

### 설정 비교

#### Tokamak Thanos - op-batcher

```bash
# 환경 변수
OP_BATCHER_PLASMA_ENABLED=true
OP_BATCHER_PLASMA_DA_SERVER=http://da-server:3100

# 플래그
--plasma.enabled=true \
--plasma.da-server=http://da-server:3100 \
--plasma.verify-on-read=true
```

#### Optimism - op-batcher (기본)

```bash
# Calldata 모드 (추가 설정 불필요)
OP_BATCHER_L1_ETH_RPC=http://localhost:8545
OP_BATCHER_L2_ETH_RPC=http://localhost:9545
OP_BATCHER_ROLLUP_RPC=http://localhost:9546

# Alt-DA는 명시적으로 활성화해야 함
```

#### Optimism - op-batcher (Alt-DA 활성화 시)

```bash
# 환경 변수
OP_BATCHER_DA_TYPE=altda
OP_BATCHER_ALTDA_SERVER=http://da-server:3100

# 플래그
--da-type=altda \
--altda-server=http://da-server:3100
```

---

## 비용 vs 보안 트레이드오프

### 상세 비교

| 측면 | Calldata (Optimism 기본) | Alt-DA/Plasma (Thanos 기본) |
|------|-------------------------|---------------------------|
| **L1 가스 비용** | 높음 (전체 데이터) | 낮음 (커밋먼트만) |
| **예상 비용 절감** | 기준 (100%) | ~5-10% (90-95% 절감) |
| **데이터 영구성** | L1에 영구 저장 | DA 서버 의존 |
| **검증 가능성** | 모든 노드 즉시 접근 가능 | DA 서버 가용성 필요 |
| **신뢰 가정** | L1만 신뢰 | DA 서버도 신뢰 필요 |
| **탈중앙화** | 완전 탈중앙화 | 부분적 중앙화 (DA 서버) |
| **인프라 복잡도** | 낮음 | 높음 (DA 서버 운영) |
| **데이터 검열 저항** | 높음 | 중간 (DA 서버가 검열 가능) |
| **적합한 사용 사례** | 메인넷, 프로덕션 | 테스트넷, 개발 환경 |

### 비용 계산 예시

**시나리오**: 1,000 TPS, 각 트랜잭션 100 바이트

#### Calldata 방식
```
데이터 크기: 1,000 tx/s × 100 bytes = 100 KB/s
L1 가스: 100,000 bytes × 16 gas/byte = 1,600,000 gas/s
가스 가격: 50 gwei
비용: 1,600,000 × 50 × 10^-9 = 0.08 ETH/s
일일 비용: 0.08 × 86,400 = 6,912 ETH/day
```

#### Alt-DA 방식
```
커밋먼트 크기: 32 bytes (해시)
L1 가스: 32 bytes × 16 gas/byte = 512 gas/s
가스 가격: 50 gwei
비용: 512 × 50 × 10^-9 = 0.0000256 ETH/s
일일 비용: 0.0000256 × 86,400 = 2.2 ETH/day

절감액: 6,912 - 2.2 = 6,909.8 ETH/day (99.97% 절감)
```

**추가 비용 (Alt-DA):**
- DA 서버 운영: 인프라, 스토리지, 대역폭
- 모니터링 및 유지보수

### 보안 고려사항

#### Calldata 방식의 보안 보장

1. **데이터 가용성 보장**
   - L1 블록체인에 영구 저장
   - 모든 풀노드가 데이터 보유
   - 네트워크 다운 시에도 데이터 복구 가능

2. **검증 가능성**
   - 누구나 L2 상태를 독립적으로 재구성 가능
   - Fraud proof 생성에 필요한 모든 데이터 접근 가능

3. **검열 저항**
   - L1의 탈중앙화 특성 상속
   - 단일 주체가 데이터 접근을 막을 수 없음

#### Alt-DA/Plasma의 보안 위험

1. **데이터 보류 공격 (Data Withholding)**
   ```
   악의적 시퀀서:
   1. 무효한 상태 전이 생성
   2. DA 서버에 데이터 제출하지 않음
   3. L1에는 유효한 커밋먼트만 제출
   4. 검증자가 fraud proof를 생성할 수 없음
   ```

2. **DA 서버 단일 장애점**
   - 서버 다운 시 데이터 접근 불가
   - DDoS 공격에 취약
   - 운영자의 검열 가능

3. **완화 전략**
   - **데이터 가용성 챌린지**: 주기적으로 데이터 제공 증명 요구
   - **다중 DA 서버**: 여러 독립적인 DA 서버 운영
   - **탈출 해치(Escape Hatch)**: 데이터 미제공 시 사용자 자금 인출 메커니즘

---

## Alt-DA 활성화 방법

Optimism에서 Alt-DA를 사용하고 싶다면 다음과 같이 설정할 수 있습니다.

### 1. DA 서버 빌드

```bash
cd /path/to/optimism/op-alt-da

# Makefile 사용
make daserver

# 또는 just 사용
just build

# 바이너리 확인
ls -la bin/
# daserver 실행 파일 생성됨
```

### 2. DA 서버 실행 (로컬 개발)

#### LevelDB 백엔드 (로컬 파일)

```bash
./bin/daserver \
  --addr=0.0.0.0 \
  --port=3100 \
  --db.type=leveldb \
  --db.path=/tmp/da-data \
  --log.level=debug
```

#### S3 백엔드 (프로덕션)

```bash
# AWS 인증 설정
export AWS_ACCESS_KEY_ID=YOUR_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=YOUR_SECRET_ACCESS_KEY
export AWS_REGION=us-east-1

# DA 서버 실행
./bin/daserver \
  --addr=0.0.0.0 \
  --port=3100 \
  --db.type=s3 \
  --db.bucket=my-da-bucket \
  --log.level=info
```

#### Google Cloud Storage 백엔드

```bash
# GCS 인증 설정
export AWS_ENDPOINT_URL="https://storage.googleapis.com"
export AWS_ACCESS_KEY_ID=YOUR_GOOGLE_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=YOUR_GOOGLE_ACCESS_KEY_SECRET

# DA 서버 실행
./bin/daserver \
  --addr=0.0.0.0 \
  --port=3100 \
  --db.type=s3 \
  --db.bucket=my-gcs-bucket \
  --log.level=info
```

### 3. Docker Compose 설정

`docker-compose.altda.yml` 생성:

```yaml
version: '3.8'

services:
  da-server:
    build:
      context: .
      dockerfile: op-alt-da/Dockerfile
    ports:
      - "3100:3100"
    volumes:
      - da_data:/data
    environment:
      - LOG_LEVEL=debug
    command: |
      daserver \
        --addr=0.0.0.0 \
        --port=3100 \
        --db.type=leveldb \
        --db.path=/data \
        --log.level=debug
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:3100/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  op-batcher:
    # 기존 설정에 추가
    environment:
      - OP_BATCHER_DA_TYPE=altda
      - OP_BATCHER_ALTDA_SERVER=http://da-server:3100
    depends_on:
      da-server:
        condition: service_healthy

volumes:
  da_data:
    driver: local
```

**실행:**
```bash
docker compose -f docker-compose.yml -f docker-compose.altda.yml up -d
```

### 4. Kurtosis Devnet 설정

`kurtosis-devnet/altda.yaml` 생성:

```yaml
optimism_package:
  chains:
    op-kurtosis:
      batcher_params:
        image: {{ localDockerImage "op-batcher" }}
        extra_params:
          - "--da-type=altda"
          - "--altda-server=http://da-server:3100"

      # Alt-DA 서버 추가 (커스텀 서비스)
      additional_services:
        - name: da-server
          image: {{ localDockerImage "op-alt-da" }}
          ports:
            - "3100:3100"
          command:
            - "daserver"
            - "--addr=0.0.0.0"
            - "--port=3100"
            - "--db.type=leveldb"
            - "--db.path=/data"
```

**실행:**
```bash
just devnet altda.yaml
```

### 5. 검증

#### DA 서버 헬스 체크

```bash
curl http://localhost:3100/health
# {"status": "healthy"}
```

#### 데이터 저장 테스트

```bash
# 데이터 저장
curl -X POST http://localhost:3100/put \
  -H "Content-Type: application/octet-stream" \
  --data-binary "test data" \
  -v

# 응답: 커밋먼트 해시
# commitment: 0x1234...

# 데이터 조회
curl http://localhost:3100/get/0x1234...
# test data
```

#### op-batcher 로그 확인

```bash
# Docker Compose
docker compose logs -f op-batcher | grep -i "alt-da\|da-server"

# Kurtosis
kurtosis service logs my-devnet op-batcher -f | grep -i "alt-da"
```

**성공적인 설정 시 로그:**
```
INFO [01-17|12:00:00.000] Connected to Alt-DA server  url=http://da-server:3100
INFO [01-17|12:00:01.000] Submitted batch to Alt-DA   commitment=0x1234... size=1024
```

---

## 권장사항

### 언제 Calldata를 사용해야 하나?

✅ **다음 경우에 Calldata 사용 (Optimism 기본값):**

1. **프로덕션 메인넷**
   - 사용자 자금이 실제로 위험에 노출
   - 최대 보안 및 탈중앙화 필요
   - 예: Optimism Mainnet, Base, Zora

2. **퍼블릭 테스트넷**
   - 커뮤니티에 공개된 환경
   - 신뢰 최소화 원칙 유지

3. **감사 및 컴플라이언스가 중요한 경우**
   - 규제 요구사항
   - 데이터 영구성 보장 필요

4. **장기 운영 계획**
   - 수년간 지속될 체인
   - 데이터 가용성 보장 필수

### 언제 Alt-DA를 사용해야 하나?

✅ **다음 경우에 Alt-DA 사용:**

1. **로컬 개발 환경**
   ```bash
   # 개발자 로컬 머신
   make devnet-up-altda
   ```
   - L1 가스 비용 절감
   - 빠른 반복 개발

2. **내부 테스트넷**
   - 팀 내부용
   - 제한된 사용자
   - 예: 스테이징 환경

3. **단기 실험 체인**
   - 프로토타입 검증
   - 기능 테스트
   - 수명: 며칠~몇 주

4. **비용이 주요 제약인 경우**
   - 예산이 제한된 프로젝트
   - 높은 TPS 요구 (테스트용)
   - DA 서버 운영 역량 보유

### Tokamak Thanos vs Optimism: 어느 것을 선택해야 하나?

#### Tokamak Thanos 선택 시나리오

✅ **Tokamak Thanos를 선택하세요:**

1. **비용 효율성이 최우선**
   - L1 가스 비용이 주요 장벽
   - 대규모 트랜잭션 처리 (테스트 환경)

2. **신뢰할 수 있는 환경**
   - 컨소시엄 체인
   - 내부 네트워크
   - 중앙화된 검증자 세트

3. **인프라 운영 역량 보유**
   - DA 서버 관리 가능
   - 24/7 모니터링 체계
   - 백업 및 복구 계획 수립

4. **단기~중기 프로젝트**
   - 1-2년 운영 계획
   - 나중에 Calldata로 마이그레이션 가능

#### Optimism 선택 시나리오

✅ **Optimism을 선택하세요:**

1. **최대 보안 및 탈중앙화**
   - 퍼블릭 메인넷
   - 신뢰 최소화 원칙
   - 장기 운영 계획

2. **규제 준수**
   - 금융 서비스
   - 엔터프라이즈 애플리케이션
   - 감사 요구사항

3. **커뮤니티 신뢰 구축**
   - 투명성 중요
   - 검증 가능성 필수
   - 데이터 영구성 보장

4. **L1 비용 감당 가능**
   - 충분한 예산
   - 낮은~중간 TPS
   - 높은 트랜잭션 가치

### 하이브리드 접근법

**개발 단계별 전략:**

```
1. 로컬 개발 → Alt-DA
   ├─ 빠른 반복
   └─ 비용 제로

2. 내부 테스트넷 → Alt-DA
   ├─ 팀 내부 검증
   └─ 스테이징 환경

3. 퍼블릭 테스트넷 → Calldata
   ├─ 커뮤니티 참여
   └─ 실제 환경 시뮬레이션

4. 메인넷 → Calldata
   └─ 프로덕션 배포
```

---

## 기술 상세

### Commitment 구조

#### Calldata Commitment
```go
// L1에 전체 데이터 저장
type CalldataCommitment struct {
    Data []byte  // 실제 트랜잭션 데이터
}

// L1 트랜잭션
tx.Data = batchData  // 전체 데이터 포함
```

#### Alt-DA Commitment
```go
// L1에 해시만 저장
type AltDACommitment struct {
    CommitmentType uint8   // 1 = Keccak256
    Commitment     [32]byte // 데이터 해시
}

// L1 트랜잭션
tx.Data = encodeCommitment(commitment)  // 32 바이트만
```

### DA 서버 API

#### PUT 엔드포인트
```http
POST /put HTTP/1.1
Content-Type: application/octet-stream

<binary-data>

Response:
{
  "commitment": "0x1234567890abcdef..."
}
```

#### GET 엔드포인트
```http
GET /get/0x1234567890abcdef... HTTP/1.1

Response:
<binary-data>
```

#### 헬스 체크
```http
GET /health HTTP/1.1

Response:
{
  "status": "healthy",
  "version": "1.0.0",
  "storage": "s3"
}
```

### 스토리지 백엔드 비교

| 백엔드 | 용도 | 비용 | 내구성 | 성능 |
|--------|------|------|--------|------|
| **LevelDB** | 로컬 개발 | 무료 | 낮음 | 높음 |
| **AWS S3** | 프로덕션 | 중간 | 높음 (99.999999999%) | 중간 |
| **Google Cloud Storage** | 프로덕션 | 중간 | 높음 | 중간 |
| **IPFS** | 탈중앙화 | 낮음 | 중간 | 낮음 |

---

## 마이그레이션 가이드

### Alt-DA → Calldata 마이그레이션

**시나리오**: 테스트넷(Alt-DA)에서 메인넷(Calldata)로 전환

#### 1. 준비 단계

```bash
# 기존 Alt-DA 체인 중지
docker compose down

# 설정 백업
cp .env .env.altda.backup
cp rollup.json rollup.json.backup
```

#### 2. 설정 변경

```bash
# .env 파일 수정
# 삭제: Alt-DA 관련 설정
# OP_BATCHER_DA_TYPE=altda
# OP_BATCHER_ALTDA_SERVER=http://da-server:3100

# 추가: Calldata 설정 (기본값이므로 명시적 설정 불필요)
# OP_BATCHER_DA_TYPE=calldata  # 또는 제거
```

#### 3. 재배포

```bash
# 새로운 제네시스로 시작 (체인 리셋)
make devnet-clean
make devnet-up

# 또는 기존 상태 유지 (권장하지 않음)
docker compose up -d
```

#### 4. 데이터 마이그레이션 (필요 시)

```bash
# Alt-DA 서버에서 모든 데이터 내보내기
./scripts/export-altda-data.sh > altda-export.jsonl

# Calldata로 재제출
./scripts/resubmit-to-calldata.sh altda-export.jsonl
```

**주의사항:**
- 체인 ID 변경 필요 (테스트넷 → 메인넷)
- 컨트랙트 주소 변경
- 사용자 자산 마이그레이션 계획 수립

### Calldata → Alt-DA 마이그레이션

**일반적으로 권장하지 않음** (보안 다운그레이드)

특수한 경우에만 고려:
- 메인넷 → 테스트넷 복제
- 비용 제약으로 인한 불가피한 전환

---

## 참고 자료

### 공식 문서
- [Optimism Alt-DA Specs](https://specs.optimism.io/experimental/alt-da.html)
- [Plasma Mode Documentation](https://specs.optimism.io/experimental/plasma.html)
- [Data Availability 이론](https://ethereum.org/en/developers/docs/data-availability/)

### 관련 파일
- `op-alt-da/`: Optimism Alt-DA 구현
- `op-alt-da/cmd/daserver/README.md`: DA 서버 설정 가이드
- `op-batcher/`: Batcher 구현 (DA 통합)
- `kurtosis-devnet/`: Devnet 설정 예시

### 추가 학습 자료
- [Celestia: Modular Data Availability](https://celestia.org)
- [EigenDA: Data Availability as a Service](https://www.eigenlayer.xyz/eigenda)
- [Rollup Economics](https://vitalik.eth.limo/general/2021/01/05/rollup.html)

---

## 요약

### 핵심 포인트

1. **Optimism ≠ DA 서버 제거**
   - DA 서버가 사라진 것이 아님
   - 선택적 컴포넌트로 전환 (`op-alt-da`)

2. **설계 철학 차이**
   - **Optimism**: 보안 우선 → Calldata 기본
   - **Tokamak Thanos**: 비용 우선 → Plasma DA 기본

3. **두 방식 모두 유효**
   - Calldata: 프로덕션, 메인넷
   - Alt-DA: 개발, 테스트, 비용 제약 환경

4. **필요에 따라 선택**
   - 보안 vs 비용 트레이드오프 이해
   - 프로젝트 단계별 적절한 선택
   - 하이브리드 접근 가능

### 의사결정 체크리스트

- [ ] 메인넷 배포 계획? → Calldata
- [ ] 테스트넷 또는 내부용? → Alt-DA 고려
- [ ] L1 비용 감당 가능? → Calldata
- [ ] DA 서버 운영 역량 보유? → Alt-DA 가능
- [ ] 최대 보안 필요? → Calldata
- [ ] 규제 준수 필요? → Calldata
- [ ] 단기 실험? → Alt-DA 적합
- [ ] 장기 운영 계획? → Calldata

---

**문서 버전**: 1.0
**작성일**: 2025-01-17
**저자**: Optimism Korea Team
**관련 문서**: `deployment-guide-ko.md`
