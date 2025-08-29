# Game Type Configuration Guide

## 개요

Optimism devnet에서 Game Type 설정을 변경하는 방법과 설정 불일치 해결 방법을 설명합니다.

## Game Type 구조

### Game Type Constants
```go
// op-challenger/game/fault/types/types.go
const (
    CannonGameType            GameType = 0    // Fault Game (Cannon VM)
    PermissionedGameType      GameType = 1    // Permissioned Game
    AsteriscGameType          GameType = 2    // Asterisc VM
    AsteriscKonaGameType      GameType = 3    // Asterisc + Kona
    SuperCannonGameType       GameType = 4    // Super Cannon
    SuperPermissionedGameType GameType = 5    // Super Permissioned
    OPSuccinctGameType        GameType = 6    // OP Succinct
    SuperAsteriscKonaGameType GameType = 7    // Super Asterisc + Kona
    FastGameType              GameType = 254  // Fast (Testing)
    AlphabetGameType          GameType = 255  // Alphabet (Testing)
    KailuaGameType            GameType = 1337 // RISC Zero Kailua
)
```

## 설정 위치별 Game Type

### 1. Devnet 빌드 설정
**파일**: `/optimism/kurtosis-devnet/simple.yaml`
```yaml
proposer_params:
  image: {{ localDockerImage "op-proposer" }}
  extra_params: []
  game_type: 1              # ← OP-Proposer가 생성할 게임 타입
  proposal_interval: 10m
```

### 2. 컨트랙트 배포 상태
**파일**: devnet 실행 후 생성되는 `state.json`
```json
{
  "dangerousAdditionalDisputeGames": [
    {
      "respectedGameType": 0,    # ← OptimismPortal이 인정하는 게임 타입
      "faultGameAbsolutePrestate": "0x000...",
      "makeRespected": false
    }
  ]
}
```

## 설정 불일치 문제

### 문제 상황
```bash
# OP-Proposer 설정 (simple.yaml)
game_type: 1                    # Permissioned 게임 생성

# 컨트랙트 설정 (state.json) 
"respectedGameType": 0          # Cannon 게임만 인정 ❌ 불일치!

# 실제 생성된 게임들
Type 1 (Permissioned)          # OP-Proposer가 생성한 게임들

# 챌린저 자동 감지
permissioned trace-type         # 올바른 판단이지만 혼란 초래
```

### 영향
- 챌린저 자동 감지 시 잘못된 respectedGameType 참조
- 시스템 일관성 부족
- 디버깅 시 혼란 야기

## 해결 방법

### 방법 1: 런타임에 respectedGameType 수정 (권장)

#### Guardian을 통한 설정 변경
```bash
# 1. Guardian 주소 확인
grep -A 3 -B 3 "Guardian" /tmp/current-devnet-config/state.json
# SuperchainGuardian: "0x589a698b7b7da0bec545177d3963a2741105c7c9"

# 2. AnchorStateRegistry 주소 확인  
grep "AnchorStateRegistryProxy" /tmp/current-devnet-config/state.json
# "AnchorStateRegistryProxy": "0x92b92fbfdb9c688d204062900de9d1fb624540a4"

# 3. Guardian으로 respectedGameType 변경 (cast 사용)
cast send 0x92b92fbfdb9c688d204062900de9d1fb624540a4 \
  "setRespectedGameType(uint32)" 1 \
  --private-key 0x[GUARDIAN_PRIVATE_KEY] \
  --rpc-url http://localhost:65502
```

#### OptimismPortal2를 통한 설정 변경
```bash  
# 1. OptimismPortal 주소 확인
grep "OptimismPortalProxy" /tmp/current-devnet-config/state.json

# 2. Guardian으로 OptimismPortal의 respectedGameType 변경
cast send [OPTIMISM_PORTAL_PROXY_ADDRESS] \
  "setRespectedGameType(uint32)" 1 \
  --private-key 0x[GUARDIAN_PRIVATE_KEY] \
  --rpc-url http://localhost:65502
```

### 방법 2: Devnet 재빌드 (근본적 해결)

#### simple.yaml 수정
```yaml
# /optimism/kurtosis-devnet/simple.yaml
optimism_package:
  chains:
    op-kurtosis:
      # 추가 설정으로 respectedGameType 명시
      additional_dispute_games:
        - respected_game_type: 1    # Permissioned을 respected로 설정
          make_respected: true      # 이를 기본값으로 만들기
      proposer_params:
        game_type: 1               # 기존 설정 유지
```

#### 재빌드 실행
```bash
# 1. 기존 devnet 중지
kurtosis enclave rm --force simple-devnet

# 2. 설정 수정 후 재빌드
./build-devnet.sh

# 3. 챌린저 자동 실행
./run-challenger-devnet.sh
```

### 방법 3: 챌린저 스크립트 개선

#### 실제 게임 타입 감지 로직 추가
```bash
# detect_trace_type() 함수 개선
detect_trace_type() {
    log_info "Auto-detecting trace type from devnet configuration..."
    
    # 실제 생성된 게임들의 타입 확인 (더 정확한 방법)
    local actual_game_types=$(docker exec op-challenger op-challenger list-games \
        --game-factory-address $GAME_FACTORY_ADDRESS \
        --l1-eth-rpc http://localhost:$L1_RPC_PORT 2>/dev/null | \
        awk 'NR>1 {print $3}' | sort -u)
    
    if echo "$actual_game_types" | grep -q "1"; then
        TRACE_TYPE="permissioned"
        log_success "Auto-detected trace type: permissioned (actual games: type 1)"
    elif echo "$actual_game_types" | grep -q "0"; then
        TRACE_TYPE="cannon"
        log_success "Auto-detected trace type: cannon (actual games: type 0)"
    else
        # 기존 state.json 기반 감지로 fallback
        # ... 기존 로직
    fi
}
```

## 설정 확인 방법

### 현재 respectedGameType 확인
```bash
# AnchorStateRegistry에서 확인
cast call 0x92b92fbfdb9c688d204062900de9d1fb624540a4 \
  "respectedGameType()(uint32)" \
  --rpc-url http://localhost:65502

# OptimismPortal에서 확인  
cast call [OPTIMISM_PORTAL_PROXY_ADDRESS] \
  "respectedGameType()(uint32)" \
  --rpc-url http://localhost:65502
```

### 실제 게임 타입 확인
```bash
# 생성된 게임들의 타입 확인
docker exec op-challenger op-challenger list-games \
  --game-factory-address $GAME_FACTORY_ADDRESS \
  --l1-eth-rpc http://localhost:65502
```

### OP-Proposer 설정 확인
```bash  
# OP-Proposer 컨테이너의 명령줄 인수 확인
docker inspect $(docker ps | grep proposer | awk '{print $1}') \
  --format='{{.Config.Cmd}}'
```

## 모범 사례

### 1. 일관된 설정 유지
- devnet 빌드 시 `game_type`과 `respectedGameType` 일치
- 모든 컴포넌트가 동일한 게임 타입 사용

### 2. 설정 검증 스크립트
```bash
#!/bin/bash
# validate-game-types.sh

echo "=== Game Type Configuration Validation ==="

# OP-Proposer 설정
PROPOSER_GAME_TYPE=$(docker inspect $(docker ps | grep proposer | awk '{print $1}') \
  --format='{{.Config.Cmd}}' | grep -o 'game-type=[0-9]*' | cut -d'=' -f2)

# 실제 게임 타입들  
ACTUAL_GAME_TYPES=$(docker exec op-challenger op-challenger list-games \
  --game-factory-address $GAME_FACTORY_ADDRESS \
  --l1-eth-rpc http://localhost:65502 2>/dev/null | \
  awk 'NR>1 {print $3}' | sort -u)

# respectedGameType
RESPECTED_GAME_TYPE=$(cast call 0x92b92fbfdb9c688d204062900de9d1fb624540a4 \
  "respectedGameType()(uint32)" --rpc-url http://localhost:65502)

echo "OP-Proposer game_type: $PROPOSER_GAME_TYPE"
echo "Actual game types: $ACTUAL_GAME_TYPES"  
echo "Respected game type: $RESPECTED_GAME_TYPE"

# 일치 여부 확인
if [ "$PROPOSER_GAME_TYPE" = "$RESPECTED_GAME_TYPE" ]; then
    echo "✅ Configuration consistent"
else
    echo "❌ Configuration mismatch - needs fixing"
fi
```

## 관련 문서

- [Game Types vs Trace Types](./game-types-vs-trace-types.md) - 개념 구분
- [OP-Challenger 실행 가이드](./challenger-guide.md) - 기본 사용법
- [트러블슈팅 가이드](./troubleshooting.md) - 문제 해결 방법