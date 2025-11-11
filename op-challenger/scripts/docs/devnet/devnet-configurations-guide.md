# Devnet 설정 가이드

## 개요

Optimism Kurtosis devnet은 다양한 개발 및 테스트 시나리오에 맞춰 여러 설정 파일을 제공합니다. 각 설정은 서로 다른 목적과 복잡도를 가지고 있어, 용도에 맞는 선택이 중요합니다.

## 🎯 사용 가능한 Devnet 설정

### 📋 설정 파일 개요

| 설정 파일 | 크기 | 복잡도 | 주요 용도 | 빌드 시간 |
|-----------|------|--------|-----------|----------|
| **simple.yaml** | 87줄 | ⭐ | 기본 개발 환경 | ~5분 |
| **interop.yaml** | 173줄 | ⭐⭐⭐ | 멀티체인 테스트 | ~15분 |
| **isthmus.yaml** | 99줄 | ⭐⭐ | 프로토콜 업그레이드 | ~7분 |

## 🔧 각 설정별 상세 설명

### 1. Simple.yaml - 기본 개발 환경

**파일**: `/kurtosis-devnet/simple.yaml`

**구성 요소**:
```yaml
optimism_package:
  faucet:
    enabled: true
  chains:
    op-kurtosis:      # 단일 L2 체인
      participants:
        node0:        # 1개 노드
  proposer_params:
    game_type: 1      # PERMISSIONED
    proposal_interval: 10m
```

**특징**:
- ✅ **가장 단순한 구성**: L1 + L2 단일 체인
- ✅ **빠른 빌드**: 약 5분 내 완료
- ✅ **리소스 효율적**: 최소한의 컨테이너
- ✅ **개발 친화적**: 빠른 반복 개발 가능

**적합한 작업**:
- Challenger 개발 및 테스트
- Proposer 기능 검증
- 기본 fault proof 메커니즘 학습
- 스크립트 및 도구 개발

**실행 명령**:
```bash
just simple-devnet
# 또는
./build-devnet.sh
```

### 2. Interop.yaml - 멀티체인 환경

**파일**: `/kurtosis-devnet/interop.yaml`

**구성 요소**:
```yaml
optimism_package:
  superchains:
    superchain:
      enabled: true
  supervisors:
    supervisor:       # Superchain 감독자
  chains:
    op-kurtosis1:     # 첫 번째 L2 체인
    op-kurtosis2:     # 두 번째 L2 체인
```

**특징**:
- 🔗 **멀티체인 아키텍처**: 2개 이상의 L2 체인
- 🔗 **Superchain 지원**: 체인 간 상호 운용성
- 🔗 **Supervisor 컴포넌트**: 크로스체인 조정
- 🔗 **복잡한 인프라**: 더 많은 리소스 필요

**적합한 작업**:
- 크로스체인 메시지 전송 테스트
- Superchain 기능 검증
- 체인 간 자산 이동 테스트
- Interoperability 프로토콜 개발

**실행 명령**:
```bash
just interop-devnet
```

### 3. Isthmus.yaml - 프로토콜 업그레이드 환경

**파일**: `/kurtosis-devnet/isthmus.yaml`

**구성 요소**:
```yaml
optimism_package:
  chains:
    op-kurtosis:
      network_params:
        isthmus_time_offset: 0   # Isthmus 업그레이드 활성화
```

**특징**:
- 🚀 **Isthmus 프로토콜**: 최신 프로토콜 업그레이드
- 🚀 **업그레이드 테스트**: 프로토콜 전환 시나리오
- 🚀 **Simple 기반**: 단일 체인 + 업그레이드 기능
- 🚀 **최신 기능**: 새로운 프로토콜 기능 포함

**적합한 작업**:
- 프로토콜 업그레이드 검증
- 새로운 프로토콜 기능 테스트
- 업그레이드 호환성 확인
- 최신 스펙 개발

**실행 명령**:
```bash
just isthmus-devnet
```

## 🎯 설정 선택 가이드

### 🔰 초보자 / 기본 개발
```bash
# 추천: simple.yaml
just simple-devnet
```
**이유**: 빠르고 간단하며 대부분의 개발 작업에 충분

### 🔗 크로스체인 개발
```bash
# 추천: interop.yaml  
just interop-devnet
```
**이유**: 멀티체인 환경이 필요한 작업

### 🚀 최신 기능 테스트
```bash
# 추천: isthmus.yaml
just isthmus-devnet
```
**이유**: 최신 프로토콜 기능 검증 필요

## ⚙️ 공통 설정 요소

### Game Type 설정
모든 devnet 설정에서 **동일한 게임 타입** 사용:

```yaml
proposer_params:
  game_type: 1              # PERMISSIONED (개발용)
  proposal_interval: 10m    # 10분 간격
```

**변경 방법**:
```bash
# 원하는 설정 파일 편집
vim /kurtosis-devnet/simple.yaml

# game_type 변경 (0=CANNON, 1=PERMISSIONED)
proposer_params:
  game_type: 0

# 재빌드
kurtosis enclave rm --force simple-devnet
just simple-devnet
```

### Challenger 설정
모든 devnet에서 challenger 자동 구성:

```yaml
challengers:
  challenger:
    enabled: true
    participants: "*"       # 모든 게임에 참여
```

## 🚀 실행 방법

### 기본 실행
```bash
cd op-challenger/scripts

# 1. 원하는 devnet 선택 및 빌드
just simple-devnet         # 가장 일반적
# just interop-devnet      # 멀티체인 필요시
# just isthmus-devnet      # 최신 기능 필요시

# 2. Challenger 실행 (자동으로 설정 감지)
./run-challenger-devnet.sh
```

### 고급 사용
```bash
# 특정 설정으로 직접 빌드
kurtosis run github.com/ethpandaops/optimism-package simple.yaml

# 설정 검증
grep "game_type" kurtosis-devnet/simple.yaml

# 실행 중인 devnet 확인
kurtosis enclave ls
```

## 📊 성능 및 리소스 비교

### 빌드 시간
| 설정 | 첫 빌드 | 재빌드 | Docker 이미지 |
|------|---------|--------|---------------|
| Simple | ~5분 | ~2분 | ~6개 |
| Interop | ~15분 | ~8분 | ~12개 |
| Isthmus | ~7분 | ~3분 | ~8개 |

### 메모리 사용량
| 설정 | RAM 사용량 | 디스크 공간 | 컨테이너 수 |
|------|------------|-------------|-------------|
| Simple | ~4GB | ~8GB | ~10개 |
| Interop | ~8GB | ~15GB | ~20개 |
| Isthmus | ~5GB | ~10GB | ~12개 |

## 🔧 개발 워크플로우 권장사항

### Phase 1: 개발 시작
```bash
# Simple devnet으로 시작
just simple-devnet
./run-challenger-devnet.sh

# 기본 기능 개발 및 테스트
```

### Phase 2: 고급 기능
```bash  
# 필요에 따라 더 복잡한 환경으로 전환
just interop-devnet        # 멀티체인 필요시
just isthmus-devnet        # 최신 기능 필요시
```

### Phase 3: 프로덕션 준비
```bash
# 모든 환경에서 테스트
for config in simple interop isthmus; do
    just ${config}-devnet
    ./run-challenger-devnet.sh
    # 테스트 실행
done
```

## 🛠️ 커스터마이징

### 새로운 설정 파일 생성
```bash
# 기존 설정을 기반으로 복사
cp kurtosis-devnet/simple.yaml kurtosis-devnet/my-custom.yaml

# justfile에 타겟 추가
echo "my-custom-devnet: (devnet \"my-custom.yaml\")" >> kurtosis-devnet/justfile

# 실행
just my-custom-devnet
```

### 설정 파라미터 오버라이드
```yaml
# my-custom.yaml 예시
proposer_params:
  game_type: 0              # CANNON으로 변경
  proposal_interval: 5m     # 더 빈번한 제안

# 추가 체인 설정
chains:
  my-chain:
    participants:
      node0: { ... }
```

## 🔍 문제 해결

### 설정 파일 선택 실수
```bash
# 잘못된 설정으로 빌드한 경우
kurtosis enclave rm --force [devnet-name]

# 올바른 설정으로 재빌드
just simple-devnet
```

### 리소스 부족
```bash
# 가벼운 설정으로 변경
just simple-devnet

# 또는 Docker 리소스 정리
docker system prune -a
```

### 설정 검증
```bash
# 현재 devnet 설정 확인
kurtosis enclave inspect simple-devnet

# Challenger 설정 검증
./run-challenger-devnet.sh
# 로그에서 "Game type X (TYPE) -> trace-type: Y" 확인
```

## 🔗 관련 문서

### 설정 관련
- [롤업 설정 가이드](./rollup-configuration-guide.md) - 게임 타입 및 파라미터 설정
- [Game Types vs Trace Types](./game-types-vs-trace-types.md) - 개념 구분

### 실행 관련  
- [OP-Challenger 실행 가이드](./challenger-guide.md) - 스크립트 사용법
- [트러블슈팅 가이드](./troubleshooting.md) - 문제 해결 방법

### 외부 문서
- [Kurtosis Devnet Book](https://devdocs.optimism.io/kurtosis-devnet/) - 공식 문서
- [Optimism Package](https://github.com/ethpandaops/optimism-package) - 소스 코드

---

**💡 권장사항**: 처음 시작하시는 분은 `simple.yaml`로 시작하여 기본기를 익힌 후, 필요에 따라 더 복잡한 환경으로 확장하세요!