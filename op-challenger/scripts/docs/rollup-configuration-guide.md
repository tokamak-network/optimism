# 롤업 설정 가이드

## 개요

이 문서는 Optimism 롤업의 핵심 설정 파라미터들을 설명하고, 각 설정이 시스템에 미치는 영향과 변경 방법을 다룹니다.

## 🎯 핵심 설정 파일

### 1. Devnet 기본 설정
**위치**: `/optimism/kurtosis-devnet/simple.yaml`

```yaml
proposer_params:
  image: {{ localDockerImage "op-proposer" }}
  extra_params: []
  game_type: 1                    # ⭐ 중요: 게임 타입 설정
  proposal_interval: 10m          # ⭐ 중요: 제안 간격
```

## ⚙️ 주요 설정 파라미터

### Game Type (게임 타입)
**설정 위치**: `simple.yaml` → `proposer_params.game_type`

| 타입 | 이름 | 설명 | Challenger Trace Type |
|------|------|------|----------------------|
| 0 | CANNON | 완전한 fault proof | `cannon` |
| 1 | PERMISSIONED | 제한된 참여자만 challenge 가능 | `permissioned` |
| 2 | ASTERISC | Asterisc VM 기반 | `asterisc` |
| 3 | ASTERISC_KONA | Asterisc + Kona | `asterisc-kona` |

**영향**:
- Challenger가 해당 게임 타입에 맞는 trace-type을 자동 선택
- 각 게임 타입마다 필요한 바이너리와 설정이 다름
- 보안 수준과 성능 트레이드오프

### Proposal Interval (제안 간격)
**설정 위치**: `simple.yaml` → `proposer_params.proposal_interval`

| 환경 | 권장 간격 | 설명 |
|------|----------|------|
| **Development** | `10m` | 빠른 개발/테스트 |
| **Testnet** | `1h` | 적당한 테스트 환경 |
| **Production** | `5h-24h` | 본드 최적화 |

**영향**:
- 더 짧은 간격: 빠른 출금, 더 많은 본드 소모
- 더 긴 간격: 출금 지연, 본드 절약

## 🔧 설정 변경 방법

### 1. 게임 타입 변경

```bash
# 1. simple.yaml 수정
vim /optimism/kurtosis-devnet/simple.yaml

# game_type 값 변경 (0, 1, 2, 3 중 선택)
proposer_params:
  game_type: 0  # CANNON으로 변경 예시

# 2. 기존 devnet 제거
kurtosis enclave rm --force simple-devnet

# 3. 새 설정으로 재빌드
./build-devnet.sh

# 4. 챌린저 실행 (자동으로 새 게임 타입 감지)
./run-challenger-devnet.sh
```

### 2. 제안 간격 변경

```bash
# 1. simple.yaml 수정
vim /optimism/kurtosis-devnet/simple.yaml

# proposal_interval 값 변경
proposer_params:
  proposal_interval: 30m  # 30분으로 변경 예시

# 2. devnet 재빌드 (위와 동일)
```

## 📊 설정 조합별 특성

### 개발용 (빠른 테스트)
```yaml
proposer_params:
  game_type: 1              # PERMISSIONED
  proposal_interval: 5m     # 5분
```
- ✅ 빠른 개발 사이클
- ✅ 간단한 검증
- ⚠️ 높은 본드 소모

### 테스트용 (균형)
```yaml
proposer_params:
  game_type: 0              # CANNON  
  proposal_interval: 30m    # 30분
```
- ✅ 완전한 검증
- ✅ 적당한 리소스 사용
- ⚠️ 중간 정도 복잡도

### 프로덕션 시뮬레이션
```yaml
proposer_params:
  game_type: 0              # CANNON
  proposal_interval: 2h     # 2시간
```
- ✅ 실제 환경과 유사
- ✅ 본드 효율성
- ⚠️ 느린 출금 테스트

## 🔍 설정 검증

### 현재 설정 확인
```bash
# 1. YAML 설정 확인
grep -A 5 "proposer_params" /optimism/kurtosis-devnet/simple.yaml

# 2. 실제 적용된 설정 확인 (devnet 실행 후)
./run-challenger-devnet.sh
# 로그에서 "Game type X (TYPE) -> trace-type: Y" 확인
```

### 설정 일관성 체크
```bash
# 챌린저 실행 시 자동으로 설정 검증
./run-challenger-devnet.sh

# 출력 예시:
# [SUCCESS] Game type from configuration: 1
# [INFO] Game type 1 (PERMISSIONED) -> trace-type: permissioned
# [SUCCESS] 🎉 Configuration validated successfully!
```

## ⚠️ 주의사항

### 게임 타입 변경 시
- 기존 진행 중인 게임들은 이전 타입으로 계속 실행됨
- 새로운 게임만 변경된 타입으로 생성됨
- devnet 완전 재시작 권장

### 제안 간격 변경 시
- 실행 중인 proposer는 재시작해야 적용됨
- 짧은 간격은 L1 가스 비용 증가
- 긴 간격은 사용자 출금 지연 증가

## 🔗 관련 문서

### 내부 문서
- [Devnet 설정 가이드](./devnet-configurations-guide.md) - Simple/Interop/Isthmus 환경 선택
- [Game Types vs Trace Types](./game-types-vs-trace-types.md) - 개념 상세 설명
- [Challenger Parameters](./challenger-parameters.md) - 챌린저 설정 옵션
- [Game Type Configuration](./game-type-configuration.md) - 설정 불일치 해결

### 외부 문서  
- [OP Stack Proposals Spec](https://specs.optimism.io/protocol/proposals.html) - 프로토콜 명세
- [Proposer Configuration](https://docs.optimism.io/operators/chain-operators/configuration/proposer) - 공식 설정 가이드
- [Optimism Package](https://github.com/ethpandaops/optimism-package) - Kurtosis 패키지 소스

## 🛟 문제 해결

### "unsupported game type" 에러
```bash
# 원인: 챌린저가 해당 게임 타입을 지원하지 않음
# 해결: simple.yaml의 game_type 확인 후 챌린저 재시작
./run-challenger-devnet.sh
```

### 설정 불일치 경고
```bash
# 원인: proposer 설정과 contract 설정 간 차이
# 해결: devnet 완전 재빌드
kurtosis enclave rm --force simple-devnet
./build-devnet.sh
```

### 제안이 생성되지 않음
```bash
# 원인: proposal_interval이 너무 길거나 proposer 중단
# 해결: 간격 단축 또는 proposer 상태 확인
docker logs $(docker ps | grep proposer | awk '{print $1}')
```

---

**💡 팁**: 설정 변경 후에는 항상 `./run-challenger-devnet.sh`로 검증해보세요!