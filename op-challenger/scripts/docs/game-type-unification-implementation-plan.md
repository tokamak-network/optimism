# Game Type 통합 구현 계획

## 목표
모든 컴포넌트가 rollup-config.json의 단일 `game_type` 값을 일관되게 사용하도록 시스템 통합

## 관련 문서
- [Game Type Configuration: Complete Analysis and Solution](./game-type-configuration-complete-analysis.md) - 전체 분석 및 솔루션 상세 내용
- [Local Devnet Setup Checklist](./local-devnet-setup-checklist.md) - 구축 전 환경설정 체크리스트
- [Challenger Testing Scenarios](./challenger-testing-scenarios.md) - 챌린저 동작 확인 및 테스트 시나리오

## 구현 해야 할 작업들

### 1. rollup-config.json 스키마 업데이트

**파일**: `/tmp/current-devnet-config/rollup-2151908.json`

**작업**:
```json
{
  "genesis": { ... },
  "block_time": 2,
  "l1_chain_id": 3151908,  
  "l2_chain_id": 2151908,
  "game_type": 1,
  "_comment": "게임 타입: 0=Cannon, 1=Permissioned"
}
```

**구현 단계**:
- [ ] 기존 rollup-config.json에 `game_type` 필드 추가
- [ ] 검증 로직 추가 (0 또는 1만 허용)
- [ ] 기본값 설정 (1 = Permissioned)

### 2. Kurtosis 패키지 업데이트

**파일**: Kurtosis optimism-package 템플릿

**현재 문제**:
```yaml
respectedGameType: 0  # 하드코딩됨
```

**해결 방안**:
```yaml  
respectedGameType: {{ .GameType }}  # rollup-config에서 읽음
```

**구현 단계**:
- [ ] Kurtosis 패키지가 rollup-config.json을 읽도록 수정
- [ ] intent.yaml 템플릿에서 하드코딩 제거
- [ ] 동적 `respectedGameType` 생성 로직 추가

### 3. op-deployer 하드코딩 제거

**파일**: `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/standard/standard.go:29`

**현재 문제**:
```go
DisputeGameType uint32 = 1 // 하드코딩됨
```

**해결 방안**:
```go
// 상수 제거하고 intent.yaml에서 읽도록 변경
```

**파일**: `/Users/zena/tokamak-projects/optimism/op-deployer/pkg/deployer/pipeline/opchain.go:78`

**현재**:
```go
DisputeGameType: standard.DisputeGameType,
```

**수정 후**:
```go
DisputeGameType: intent.RespectedGameType,
```

**구현 단계**:
- [ ] `standard.DisputeGameType` 상수 제거
- [ ] intent.yaml의 `respectedGameType` 값 사용하도록 수정
- [ ] 에러 핸들링 추가 (잘못된 게임 타입 시)

### 4. Kurtosis 설정 파일들 수정

**파일들**: 
- `/Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml:53`
- `/Users/zena/tokamak-projects/optimism/kurtosis-devnet/pectra.yaml:102`
- `/Users/zena/tokamak-projects/optimism/kurtosis-devnet/interop.yaml:102,128`

**현재**:
```yaml
proposer_params:
  game_type: 1  # 하드코딩
```

**수정 후**:
```yaml
proposer_params:
  game_type: {{ .GameType }}  # rollup-config에서 읽음
```

**구현 단계**:
- [ ] 모든 kurtosis 설정 파일에서 하드코딩된 `game_type: 1` 제거
- [ ] rollup-config 값을 참조하는 템플릿으로 변경
- [ ] devnet-sdk 파라미터 구조체 업데이트

### 5. devnet-sdk 파라미터 구조체 업데이트

**파일**: `/Users/zena/tokamak-projects/optimism/devnet-sdk/kt/params.go:60-63`

**현재**:
```go
type ProposerParams struct {
    Image            string `yaml:"image"`
    GameType         int    `yaml:"game_type"`
    ProposalInterval string `yaml:"proposal_interval"`
}
```

**구현 단계**:
- [ ] GameType 필드가 rollup-config에서 올바르게 매핑되는지 확인
- [ ] 유효성 검사 로직 추가 (0 또는 1만 허용)

### 6. op-chain-ops/genesis 설정 확인

**파일**: `/Users/zena/tokamak-projects/optimism/op-chain-ops/genesis/config.go:854`

**현재**:
```go
RespectedGameType uint32 `json:"respectedGameType"`
```

**구현 단계**:
- [ ] 이 구조체가 rollup-config 값을 올바르게 받는지 확인
- [ ] genesis 설정 생성 시 game_type 전달 로직 확인

### 7. OP-Proposer 플래그 확인  

**파일**: `/Users/zena/tokamak-projects/optimism/op-proposer/flags/flags.go:68-70`

**현재**:
```go
DisputeGameTypeFlag = &cli.UintFlag{
    Name:    "game-type",
    Usage:   "Dispute game type to create via the configured DisputeGameFactory",
```

**구현 단계**:
- [ ] OP-Proposer가 설정된 game_type을 올바르게 사용하는지 확인
- [ ] CLI 플래그와 rollup-config 값의 일관성 보장

### 8. E2E 테스트 설정 수정

**파일**: `/Users/zena/tokamak-projects/optimism/op-e2e/config/init.go`

**구현 단계**:
- [ ] E2E 테스트에서 사용하는 게임 타입 하드코딩 확인
- [ ] 테스트 설정이 rollup-config 값을 사용하도록 수정
- [ ] 다양한 게임 타입으로 테스트 케이스 추가

### 9. Devstack Proof 설정 수정

**파일**: `/Users/zena/tokamak-projects/optimism/op-devstack/presets/proof.go`

**구현 단계**:
- [ ] Devstack에서 사용하는 proof 설정의 게임 타입 확인
- [ ] 하드코딩된 값들을 설정 기반으로 변경
- [ ] Proof 생성 시 올바른 게임 타입 사용 보장

### 10. Interop 설정 수정

**파일**: `/Users/zena/tokamak-projects/optimism/op-chain-ops/interopgen/configs.go`

**구현 단계**:
- [ ] Interoperability 설정에서 게임 타입 처리 확인
- [ ] 멀티체인 환경에서 각 체인별 게임 타입 설정 지원
- [ ] rollup-config 기반 설정 생성 로직 구현

### 11. Superchain 검증 파라미터 수정

**파일**: `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/lib/superchain-registry/validation/params.go`

**구현 단계**:
- [ ] Superchain 검증에서 게임 타입 관련 파라미터 확인
- [ ] 게임 타입별 검증 로직이 올바른지 확인
- [ ] rollup-config 기반 검증 규칙 적용

### 12. 추가로 발견된 37개 파일 검토

**Grep 결과로 발견된 파일들**:
```
Found 37 files with game_type|respectedGameType|DisputeGameType
```

**우선순위별 검토 대상**:

**높은 우선순위 (즉시 수정 필요)**:
- [ ] `op-devstack/sysgo/l2_proposer.go` - L2 Proposer 시스템 설정
- [ ] `op-deployer/pkg/deployer/manage/add_game_type.go` - 게임 타입 추가 관리
- [ ] `op-proposer/proposer/service.go` - Proposer 서비스 코어 로직
- [ ] `op-proposer/proposer/driver.go` - Proposer 드라이버
- [ ] `op-proposer/proposer/config.go` - Proposer 설정

**중간 우선순위 (Phase 2에서 수정)**:
- [ ] `op-e2e/system/e2esys/setup.go` - E2E 시스템 설정
- [ ] `op-e2e/actions/proposer/l2_proposer_test.go` - Proposer 테스트
- [ ] `op-e2e/actions/helpers/l2_proposer.go` - Proposer 헬퍼
- [ ] `op-node/withdrawals/utils.go` - 출금 유틸리티
- [ ] `op-fetcher/pkg/fetcher/fetch/script/script.go` - Fetcher 스크립트

**낮은 우선순위 (Phase 3에서 수정)**:
- [ ] 각종 바인딩 파일들 (`bindings/*.go`)
- [ ] 테스트 파일들 (`*_test.go`)
- [ ] 통합 테스트 파일들

### 9. 검증 시스템 구축

**구현 단계**:
- [ ] rollup-config.json 유효성 검사 스크립트 작성
- [ ] 배포 전 설정 일관성 확인 도구 개발
- [ ] 배포 후 컨트랙트 게임 타입 검증 스크립트 작성

### 6. 테스트 및 문서화

**테스트 케이스**:
- [ ] Game Type 0 (Cannon) 설정으로 전체 파이프라인 테스트
- [ ] Game Type 1 (Permissioned) 설정으로 전체 파이프라인 테스트
- [ ] 잘못된 게임 타입 (2, 3 등) 설정 시 에러 처리 확인
- [ ] 기존 네트워크에서 새 설정으로 마이그레이션 테스트

**문서화**:
- [ ] 새로운 설정 방법 가이드 작성
- [ ] 마이그레이션 가이드 작성
- [ ] 트러블슈팅 가이드 업데이트

## 우선순위 작업 순서

### Phase 1: 설정 통합
1. rollup-config.json 스키마 업데이트
2. Kurtosis 패키지 수정
3. simple.yaml 템플릿 수정

### Phase 2: 하드코딩 제거  
4. op-deployer 하드코딩 제거
5. 검증 시스템 구축

### Phase 3: 테스트 및 배포
6. 전체 파이프라인 테스트
7. 문서화 완료
8. 프로덕션 배포

## 각 작업의 영향도

| 작업 | 영향 컴포넌트 | 위험도 | 필수도 |
|------|-------------|--------|-------|
| rollup-config 스키마 | 모든 컴포넌트 | 낮음 | 높음 |
| Kurtosis 수정 | devnet 생성 | 중간 | 높음 |
| op-deployer 수정 | 컨트랙트 배포 | 높음 | 높음 |
| simple.yaml 수정 | OP-Proposer | 낮음 | 중간 |
| 검증 시스템 | 전체 시스템 | 낮음 | 중간 |

## 완료 기준

모든 작업 완료 후 다음이 가능해야 함:

1. **단일 설정**: rollup-config.json의 `game_type` 값만 변경
2. **자동 전파**: 모든 컴포넌트가 자동으로 새 게임 타입 사용
3. **일관성 보장**: 생성된 모든 설정 파일이 동일한 게임 타입 사용
4. **검증 가능**: 배포된 컨트랙트가 설정된 게임 타입과 일치함을 확인 가능

## 마이그레이션 전략

### 기존 네트워크
1. 현재 배포된 컨트랙트의 `respectedGameType` 확인
2. 해당 값을 rollup-config.json에 기록
3. 새로운 설정 시스템으로 점진적 전환

### 새 네트워크  
1. rollup-config.json에 원하는 `game_type` 설정
2. 새로운 통합 파이프라인으로 배포
3. 자동으로 일관된 설정 적용

이 계획을 통해 게임 타입 설정의 복잡성을 제거하고 모든 컴포넌트가 단일 소스에서 일관된 값을 사용하도록 할 수 있습니다.