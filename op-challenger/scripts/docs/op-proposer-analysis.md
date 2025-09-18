# op-proposer 코드 분석

## 개요

op-proposer는 Optimism의 L2 Output Proposer 서비스로, L2 상태를 L1에 제안하는 경량화된 서비스입니다. 이 문서는 op-proposer의 코드 구조와 동작 방식을 상세히 분석합니다.

## 🏗️ 전체 아키텍처

op-proposer는 다음과 같은 주요 구성 요소로 이루어져 있습니다:

### 디렉토리 구조
```
op-proposer/
├── cmd/                    # 메인 애플리케이션 진입점
├── proposer/              # 핵심 서비스 로직
│   ├── service.go         # 메인 서비스 구조체
│   ├── driver.go          # L2 Output 제안 드라이버
│   ├── config.go          # 설정 관리
│   ├── source/            # 데이터 소스 추상화
│   └── rpc/               # RPC API
├── flags/                 # CLI 플래그 정의
├── metrics/               # 메트릭스 및 모니터링
├── bindings/              # 스마트 컨트랙트 바인딩
└── contracts/             # 컨트랙트 인터페이스
```

### 핵심 컴포넌트

1. **ProposerService** (`proposer/service.go`)
2. **L2OutputSubmitter** (`proposer/driver.go`)
3. **설정 관리** (`proposer/config.go`, `flags/flags.go`)
4. **메트릭스** (`metrics/metrics.go`)
5. **소스 추상화** (`proposer/source/`)

## 🔧 핵심 기능

### 1. L2 Output 제안
- L2 체인의 상태 루트를 L1에 정기적으로 제안
- 두 가지 모드 지원:
  - **L2OutputOracle 모드**: 기존 pre-fault-proof 방식
  - **DisputeGameFactory 모드**: 새로운 fault-proof 방식

### 2. 주요 구조체

#### ProposerService
```go
type ProposerService struct {
    Log     log.Logger
    Metrics metrics.Metricer
    ProposerConfig
    TxManager      txmgr.TxManager
    L1Client       *ethclient.Client
    ProposalSource source.ProposalSource
    driver *L2OutputSubmitter
    // ... 기타 구성 요소
}
```

#### L2OutputSubmitter
- 실제 제안 로직을 담당하는 핵심 드라이버
- 폴링 기반으로 L2 상태를 확인하고 제안

## 📋 설정 옵션

### 필수 설정
- `--l1-eth-rpc`: L1 RPC 엔드포인트
- `--rollup-rpc` 또는 `--supervisor-rpcs`: L2 데이터 소스

### 선택적 설정
- `--l2oo-address`: L2OutputOracle 컨트랙트 주소
- `--game-factory-address`: DisputeGameFactory 컨트랙트 주소
- `--poll-interval`: 폴링 간격 (기본값: 12초)
- `--proposal-interval`: 제안 간격 (DGF 모드용)
- `--allow-non-finalized`: 비최종화된 블록 제안 허용
- `--game-type`: Dispute Game 타입
- `--wait-node-sync`: 시작 시 노드 동기화 대기

### 설정 검증
```go
func (c *CLIConfig) Check() error {
    // L2OO와 DGF 주소 중 하나만 설정되어야 함
    if c.DGFAddress == "" && c.L2OOAddress == "" {
        return errors.New("neither the `DisputeGameFactory` nor `L2OutputOracle` address was provided")
    }
    if c.DGFAddress != "" && c.L2OOAddress != "" {
        return errors.New("both the `DisputeGameFactory` and `L2OutputOracle` addresses were provided")
    }
    // ... 기타 검증 로직
}
```

## 🔄 동작 흐름

### 1. 초기화 과정
```go
func (ps *ProposerService) initFromCLIConfig(ctx context.Context, version string, cfg *CLIConfig, log log.Logger) error {
    // 1. 메트릭스 초기화
    ps.initMetrics(cfg)

    // 2. RPC 클라이언트 초기화
    if err := ps.initRPCClients(ctx, cfg); err != nil {
        return err
    }

    // 3. 트랜잭션 매니저 초기화
    if err := ps.initTxManager(cfg); err != nil {
        return err
    }

    // 4. 드라이버 초기화
    if err := ps.initDriver(); err != nil {
        return err
    }

    // 5. RPC 서버 초기화
    if err := ps.initRPCServer(cfg); err != nil {
        return err
    }
}
```

### 2. 메인 루프
```go
func (l *L2OutputSubmitter) loop() {
    ticker := time.NewTicker(l.Cfg.PollInterval)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            // L2OO 또는 DGF 모드에 따라 제안 가져오기
            var proposal source.Proposal
            var shouldPropose bool
            var err error

            if l.dgfContract == nil {
                proposal, shouldPropose, err = l.FetchL2OOOutput(ctx)
            } else {
                proposal, shouldPropose, err = l.FetchDGFOutput(ctx)
            }

            if err != nil {
                l.Log.Warn("Error getting proposal", "err", err)
                continue
            } else if !shouldPropose {
                continue
            }

            l.proposeOutput(ctx, proposal)
        case <-l.done:
            return
        }
    }
}
```

### 3. 제안 생성 및 전송
1. L2 상태 루트 계산
2. 트랜잭션 데이터 생성
3. L1에 트랜잭션 전송

## 🎯 두 가지 제안 모드

### L2OutputOracle 모드
```go
func (l *L2OutputSubmitter) FetchL2OOOutput(ctx context.Context) (source.Proposal, bool, error) {
    // 1. 다음 체크포인트 블록 번호 조회
    nextCheckpointBlockBig, err := l.l2ooContract.NextBlockNumber(callOpts)

    // 2. 현재 L2 헤드 확인
    currentBlockNumber, err := l.FetchCurrentBlockNumber(ctx)

    // 3. 제안할 블록이 준비되었는지 확인
    if currentBlockNumber < nextCheckpointBlock {
        return source.Proposal{}, false, nil
    }

    // 4. 출력 가져오기
    output, err := l.FetchOutput(ctx, nextCheckpointBlock)

    // 5. 최종화 상태 확인
    if output.SequenceNum > output.Legacy.FinalizedL2.Number &&
       (!l.Cfg.AllowNonFinalized || output.SequenceNum > output.Legacy.SafeL2.Number) {
        return output, false, nil
    }

    return output, true, nil
}
```

**특징:**
- 기존 pre-fault-proof 방식
- `nextBlockNumber()`를 확인하여 제안할 블록 결정
- 최종화된 L2 블록만 제안 (기본값)

### DisputeGameFactory 모드
```go
func (l *L2OutputSubmitter) FetchDGFOutput(ctx context.Context) (source.Proposal, bool, error) {
    // 1. 최근 제안 확인
    cutoff := time.Now().Add(-l.Cfg.ProposalInterval)
    proposedRecently, proposalTime, claim, err := l.dgfContract.HasProposedSince(
        ctx, l.Txmgr.From(), cutoff, l.Cfg.DisputeGameType)

    if proposedRecently {
        return source.Proposal{}, false, nil
    }

    // 2. 현재 L2 헤드 가져오기
    currentBlockNumber, err := l.FetchCurrentBlockNumber(ctx)

    // 3. 출력 가져오기
    output, err := l.FetchOutput(ctx, currentBlockNumber)

    // 4. 출력 루트 변경 확인
    if claim == output.Root {
        return source.Proposal{}, false, nil
    }

    return output, true, nil
}
```

**특징:**
- 새로운 fault-proof 방식
- 제안 간격 기반으로 제안 생성
- Dispute Game을 통한 검증 가능
- **게임 타입에 따라 다른 RPC 사용**:
  - 게임 타입 0: Rollup RPC + Output Root
  - 게임 타입 4,5: Supervisor RPC + Super Root

## 📊 메트릭스 및 모니터링

### 메트릭스 인터페이스
```go
type Metricer interface {
    RecordInfo(version string)
    RecordUp()
    RecordL2Proposal(sequenceNum uint64)
    RecordL2BlocksProposed(l2ref eth.L2BlockRef)
    StartBalanceMetrics(l log.Logger, client *ethclient.Client, account common.Address) io.Closer
    // ... 기타 메트릭스
}
```

### 주요 메트릭스
- **proposed_sequence_number**: 최신 제안의 시퀀스 번호
- **info**: 버전 및 설정 정보
- **up**: 서비스 상태 (1: 실행 중)
- **balance**: Proposer 계정 잔액
- **tx_metrics**: 트랜잭션 관련 메트릭스

## 🔒 보안 고려사항

### 1. Finality 보장
- 기본적으로 최종화된 L2 블록만 제안
- `AllowNonFinalized` 옵션으로 Safe 블록도 제안 가능

### 2. L1 블록 해시 검증
```go
func (l *L2OutputSubmitter) waitForL1Head(ctx context.Context, blockNum uint64) error {
    // L1 헤드가 지정된 블록 번호를 넘을 때까지 대기
    for l1head <= blockNum {
        l1head, err = l.Txmgr.BlockNumber(ctx)
        // ...
    }
}
```

### 3. 권한 관리
- Proposer 권한이 있는 주소만 제안 가능
- 컨트랙트 레벨에서 권한 검증

## 🚀 사용 예시

### L2OutputOracle 모드
```bash
go run ./op-proposer/cmd \
    --l1-eth-rpc http://l1:8545 \
    --rollup-rpc http://op-node:8545 \
    --l2oo-address 0x... \
    --poll-interval 12s
```

### DisputeGameFactory 모드

**게임 타입 0 (Pre-interop):**
```bash
go run ./op-proposer/cmd \
    --l1-eth-rpc http://l1:8545 \
    --rollup-rpc http://op-node:8545 \
    --game-factory-address 0x... \
    --game-type 0 \
    --proposal-interval 1h \
    --poll-interval 12s
```

**게임 타입 4,5 (Post-interop):**
```bash
go run ./op-proposer/cmd \
    --l1-eth-rpc http://l1:8545 \
    --supervisor-rpcs http://supervisor:8545 \
    --game-factory-address 0x... \
    --game-type 4 \
    --proposal-interval 1h \
    --poll-interval 12s
```

### 테스트 환경 (비최종화 허용)
```bash
go run ./op-proposer/cmd \
    --l1-eth-rpc http://l1:8545 \
    --rollup-rpc http://op-node:8545 \
    --l2oo-address 0x... \
    --allow-non-finalized \
    --wait-node-sync
```

## 🎨 설계 원칙

### 1. 단순성 우선
- 안전성 > 성능
- 제안은 시간당 1회 정도로 빈도가 낮음
- 복잡성 최소화로 버그 위험 감소

### 2. 재사용성
- 공통 트랜잭션 관리 로직 활용 (`op-service/txmgr`)
- 표준화된 메트릭스 및 로깅

### 3. 모듈화
- 소스 추상화를 통한 유연한 데이터 소스 지원
- Rollup RPC와 Supervisor RPC 모두 지원
- 게임 타입에 따른 동적 RPC 선택

### 4. 모니터링
- 포괄적인 메트릭스 및 로깅
- Prometheus 기반 모니터링

## 🔧 소스 추상화

### ProposalSource 인터페이스
```go
type ProposalSource interface {
    ProposalAtSequenceNum(ctx context.Context, seqNum uint64) (Proposal, error)
    SyncStatus(ctx context.Context) (SyncStatus, error)
    Close()
}
```

### 지원하는 소스
1. **RollupProposalSource**: 단일 rollup 노드 (L2OutputOracle 모드, 게임 타입 0)
2. **SupervisorProposalSource**: supervisor 노드들 (게임 타입 4,5)
3. **ActiveL2RollupProvider**: 활성 sequencer 자동 감지

**게임 타입별 RPC 요구사항:**
- **게임 타입 0,1,2,3,6,254,255,1337**: Rollup RPC 필요 (Pre-interop)
- **게임 타입 4,5**: Supervisor RPC 필요 (Post-interop)

## 📈 성능 특성

### 최적화 대상
- **단순성**: 복잡한 로직보다는 안전성 우선
- **제안 빈도**: 일반적으로 1시간 간격
- **실행 속도**: 테스트 환경에서만 중요

### 비용 구조
- 대부분의 비용은 컨트랙트 실행에서 발생
- op-proposer 자체의 운영 비용은 미미

## 🚨 실패 모드

### 1. 과도한 제안
- `AllowNonFinalized` 옵션으로 인한 위험
- 비최종화된 L2 상태 제안 시 잘못된 클레임 가능성

### 2. 가용성 실패
- L1 RPC 실패 (중복 RPC로 완화)
- 로컬 임시 실패 (알림으로 완화)
- 트랜잭션 포함 문제 (재시작으로 완화)

## 🔮 향후 계획

### 1. Legacy 코드 제거
- pre-fault-proof 제안 기능은 곧 제거 예정
- 대안 증명 시스템 개발 진행 중

### 2. Isthmus 업그레이드
- withdrawals-root 기능으로 op-node 요구사항 감소
- 아카이브 노드 불필요

### 3. 테스트 개선
- 스케줄링과 처리 로직 분리
- op-e2e 액션 테스트와의 통합 개선

## 📚 관련 문서

- [Proposer Configuration docs](https://docs.optimism.io/builders/chain-operators/configuration/proposer)
- [proposals.md](https://github.com/ethereum-optimism/specs/blob/main/specs/protocol/proposals.md)
- [withdrawals](https://github.com/ethereum-optimism/specs/blob/main/specs/protocol/withdrawals.md)
- [fault-proof/stage-one/bridge-integration.md](https://github.com/ethereum-optimism/specs/blob/main/specs/fault-proof/stage-one/bridge-integration.md)

## 🧪 테스트

op-proposer 통합 테스트는 `op-e2e` 시스템 테스트에서 다뤄집니다.

## 📖 관련 상세 문서

- **[DisputeGameFactory 모드 제안 제출 흐름](./op-proposer-dgf-proposal-flow.md)**: DGF 모드에서의 제안 제출 과정과 코드 구현 상세 분석

---

이 문서는 op-proposer의 코드 구조와 동작 방식을 종합적으로 분석한 것입니다. Optimism 생태계에서 L2 상태를 L1에 안전하게 제안하는 핵심 컴포넌트로, fault-proof 시스템으로의 전환을 지원하면서도 기존 시스템과의 호환성을 유지하는 잘 설계된 서비스입니다.
