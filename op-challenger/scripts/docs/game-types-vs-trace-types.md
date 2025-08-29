# Game Types vs Trace Types 이해하기

## 개념 구분

OP-Challenger에서 **Game Type**과 **Trace Type**은 서로 다른 레벨에서 작동하는 개별 개념입니다.

## 📋 Game Types (게임 타입)

### 정의
- **블록체인 컨트랙트 레벨**에서 정의되는 dispute game의 종류
- `DisputeGameFactory`에서 관리
- devnet 배포 시 결정되며 런타임에 변경 불가

### 종류
```json
// devnet state.json에서 확인
{
  "respectedGameType": 0,           // PermissionedDisputeGame
  "respectedGameType": 1,           // FaultDisputeGame  
  "respectedGameType": 2,           // 향후 확장 가능
}
```

### 컨트랙트 구현체
```bash
# Devnet 설정에서 확인 가능
"PermissionedDisputeGameImpl": "0x2bd35f9b72b30d254d53af35b2c2900b4ad63e3c"
"FaultDisputeGameImpl": "0x0000000000000000000000000000000000000000"  # 미배포
```

### 특징
- ✅ **컨트랙트 레벨**: L1 스마트 컨트랙트에서 정의
- ✅ **불변성**: devnet 재구축 없이 변경 불가
- ✅ **게임 규칙**: dispute 해결 메커니즘 정의
- ✅ **권한 관리**: 누가 게임에 참여할 수 있는지 결정

## 🔧 Trace Types (트레이스 타입)

### 정의  
- **챌린저 클라이언트**에서 사용하는 검증 방식
- dispute 발생 시 proof 생성 방법 결정
- 런타임에 챌린저 설정으로 변경 가능

### 종류
```bash
--trace-type=permissioned    # 간소화된 검증
--trace-type=cannon          # Cannon VM 기반 fault proof
--trace-type=asterisc        # Asterisc VM 기반 (향후)
--trace-type=asterisc-kona   # Kona + Asterisc (향후)
```

### 바이너리 요구사항
```bash
# Permissioned
❌ 추가 바이너리 불필요

# Cannon  
✅ /cannon/bin/cannon
✅ /op-program/bin/op-program
✅ /op-program/bin/prestate-mt64Next.bin.gz

# Asterisc (향후)
✅ /asterisc/bin/asterisc
✅ 관련 prestate 파일들
```

### 특징
- ✅ **클라이언트 레벨**: 챌린저 실행 시 선택
- ✅ **가변성**: 컨테이너 재시작으로 변경 가능
- ✅ **검증 방식**: proof 생성 알고리즘 정의
- ✅ **성능/정확도**: 트레이드오프 선택

## 🔄 상호관계

### 호환성 매트릭스

| Game Type | 지원 Trace Types | 설명 |
|-----------|------------------|------|
| **0 (Permissioned)** | `permissioned` | 빠른 개발/테스트용 |
| **1 (Fault)** | `cannon`, `asterisc` | 완전한 fault proof |
| **2 (향후)** | `custom`, `experimental` | 새로운 검증 방식 |

### 자동 매칭 로직
```bash
# 스크립트의 자동 감지 시스템
if [ "$respected_game_type" = "0" ]; then
    TRACE_TYPE="permissioned"
elif [ "$respected_game_type" = "1" ]; then  
    TRACE_TYPE="cannon"
fi
```

## 🔄 완전 자동화된 실행 과정

### 1. 컨트랙트 설정 자동 확인
스크립트 실행 시 다음 과정이 자동으로 진행됩니다:

```bash
# 사용자 실행
./run-challenger-devnet.sh

# 내부적으로 자동 실행되는 과정:
kurtosis files download simple-devnet op-deployer-configs /tmp/
grep "respectedGameType" /tmp/state.json
# → "respectedGameType": 0 확인
```

### 2. 자동 trace-type 선택
```bash
# detect_trace_type() 함수가 자동 실행
case "$respected_game_type" in
    0)
        TRACE_TYPE="permissioned"
        log_success "Auto-detected trace type: permissioned (game type 0)"
        ;;
    1)  
        TRACE_TYPE="cannon"
        log_success "Auto-detected trace type: cannon (game type 1)"
        ;;
    *)
        log_warning "Unknown game type: $respected_game_type. Defaulting to permissioned"
        TRACE_TYPE="permissioned"
        ;;
esac
```

### 3. 최적화된 설정 자동 적용

**현재 devnet (Game Type 0 → Permissioned):**
```bash
✅ 자동 선택: --trace-type=permissioned
✅ 바이너리 체크 생략 (빠른 실행)
✅ Volume 마운트 최소화
✅ 즉시 실행 가능
```

**만약 Game Type 1 devnet (Fault Game):**
```bash  
✅ 자동 선택: --trace-type=cannon
✅ 필수 바이너리 자동 체크:
  - /optimism/cannon/bin/cannon
  - /optimism/op-program/bin/op-program  
  - /optimism/op-program/bin/prestate-mt64Next.bin.gz
✅ Volume 마운트 자동 추가
✅ Cannon 전용 파라미터 적용
```

## 🏗️ 새로운 타입 추가하기

### 1. 새로운 Game Type 추가

**요구사항:**
- L1 스마트 컨트랙트 개발
- DisputeGameFactory 업데이트  
- devnet 배포 스크립트 수정

**예시:**
```solidity
// 새로운 게임 컨트랙트
contract CustomDisputeGame is IDisputeGame {
    // 새로운 게임 로직 구현
}

// Factory에 등록
disputeGameFactory.setGameType(2, customDisputeGameImpl);
```

### 2. 새로운 Trace Type 추가

**요구사항:**
- 챌린저 클라이언트 코드 수정
- 새로운 바이너리/도구 (선택사항)
- 실행 스크립트 업데이트

**예시:**
```bash
# run-challenger-devnet.sh에 추가
case "$TRACE_TYPE" in
    "custom")
        trace_args+=(
            --custom-prover=/path/to/custom-prover
            --custom-config=/path/to/config
        )
        log_info "Using custom trace type"
        ;;
esac
```

### 4. 사용자 확인 방법

**자동 감지 과정 확인:**
```bash
# 1. 현재 devnet Game Type 직접 확인
kurtosis files download simple-devnet op-deployer-configs /tmp/
grep "respectedGameType" /tmp/state.json

# 2. 스크립트 실행하여 자동 감지 로그 확인
./run-challenger-devnet.sh
# 출력 예시:
# [INFO] Auto-detecting trace type from devnet configuration...  
# [SUCCESS] Auto-detected trace type: permissioned (game type 0)
```

**실행 중 설정 확인:**
```bash
# 챌린저 실행 로그에서 사용된 trace-type 확인
docker logs op-challenger 2>&1 | head -10
# 또는 
./challenger-healthcheck.sh
```

## 📊 실전 예제

### 현재 devnet 상태 확인
```bash
# 1. Game Type 확인 (컨트랙트 레벨)
kurtosis files download simple-devnet op-deployer-configs /tmp/
grep "respectedGameType" /tmp/state.json
# → "respectedGameType": 0

# 2. 사용 가능한 게임 구현체 확인
grep "DisputeGameImpl" /tmp/state.json
# → PermissionedDisputeGameImpl: "0x2bd..."
# → FaultDisputeGameImpl: "0x0000..."  (미배포)
```

### 챌린저 실행 시나리오

**시나리오 1: 빠른 개발**
```bash
# Game Type 0 (Permissioned) + Trace Type permissioned
./run-challenger-devnet.sh permissioned
# → 즉시 실행, 바이너리 불필요
```

**시나리오 2: 완전한 검증** 
```bash
# 먼저 Game Type 1 지원 devnet 구축 필요
# devnet 설정에서 respectedGameType: 1로 변경 후
./build-devnet.sh

# Game Type 1 (Fault) + Trace Type cannon  
./run-challenger-devnet.sh cannon
# → cannon 바이너리 필요, 완전한 fault proof
```

## 🚀 향후 확장 가능성

### Game Type 확장
- **Multi-Chain Games**: 여러 체인 간 dispute
- **ZK Games**: Zero-knowledge proof 기반
- **Economic Games**: 경제적 인센티브 최적화

### Trace Type 확장  
- **Parallel Tracing**: 병렬 proof 생성
- **Optimized Provers**: 특화된 검증기
- **Hybrid Methods**: 여러 방식 조합

## 🔍 문제 해결

### "unsupported game type" 에러
```bash
# 원인: Game Type과 Trace Type 불일치
# 해결: 자동 감지 사용
./run-challenger-devnet.sh  # 파라미터 없이 실행
```

### 새로운 타입 테스트
```bash
# 1. 기존 컨테이너 제거
docker rm -f op-challenger

# 2. 새 설정으로 실행
./run-challenger-devnet.sh [새로운_타입]

# 3. 로그 확인
docker logs -f op-challenger
```

## 📚 관련 문서

- [OP-Challenger 실행 가이드](./challenger-guide.md) - 기본 사용법
- [Challenger Parameters](./challenger-parameters.md) - 설정 옵션
- [챌린저 기능 테스트 가이드](./challenger-testing.md) - 테스트 방법
- [트러블슈팅 가이드](./troubleshooting.md) - 문제 해결

---

**요약:** Game Type은 블록체인 컨트랙트가 정의하는 게임 규칙이고, Trace Type은 챌린저 클라이언트가 선택하는 검증 방식입니다.