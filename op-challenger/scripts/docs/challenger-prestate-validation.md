# Challenger Prestate 및 State Root 검증 과정

## 개요

op-challenger가 dispute game에 참여할 때 prestate와 state root를 어떻게 검증하는지에 대한 상세한 분석입니다.

## 검증 과정 개요

챌린저는 두 가지 핵심 값을 검증합니다:
1. **absolutePrestate**: VM의 절대 prestate 해시
2. **startingRootHash**: L2 output root (starting state root)

## Prestate 및 State Root Validation 과정

### 1. Validator 생성 

**파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/register_task.go:336-338`

```go
if !e.skipPrestateValidation {
    validators = append(validators, NewPrestateValidator(e.gameType.String(), contract.GetAbsolutePrestateHash, vmPrestateProvider))
    validators = append(validators, NewPrestateValidator("output root", contract.GetStartingRootHash, prestateProvider))
}
```

두 개의 validator가 생성됩니다:
- **absolutePrestate validator**: VM의 절대 prestate 해시 검증 (vmPrestateProvider 사용)
- **output root validator**: L2 starting state root 검증 (prestateProvider 사용)

### 2. Contract에서 값 조회

#### GetAbsolutePrestateHash()
- FaultDisputeGame 컨트랙트의 `absolutePrestate()` 함수 호출
- 게임 생성 시 설정된 VM의 절대 prestate 해시 반환

#### GetStartingRootHash()  
- FaultDisputeGame 컨트랙트의 `startingRootHash()` 함수 호출
- `startingOutputRoot.root` 값 반환
- 이 값은 게임 초기화 시 `AnchorStateRegistry.getAnchorRoot()`에서 가져온 값

### 3. Provider에서 값 계산

#### vmPrestateProvider (absolutePrestate)
- MultiPrestateProvider를 통해 prestate 파일 다운로드
- 파일에서 실제 prestate 해시 계산
- 파일서버에서 `{hash}.json.gz` 형태로 다운로드

#### prestateProvider (starting state root)
- L2 genesis 블록의 output root 계산
- 실제 L2 체인의 genesis 상태 root와 비교
- 이 값이 게임의 시작 상태로 사용되는 state root

### 4. 검증 과정

```go
func (v *PrestateValidator) Validate(ctx context.Context) error {
    // Contract에서 값 가져오기
    contractHash, err := v.contractGetter(ctx)
    
    // Provider에서 값 계산하기  
    providerHash, err := v.prestateProvider.PrestatePath(ctx, contractHash)
    
    // 두 값 비교
    if contractHash != calculatedProviderHash {
        return fmt.Errorf("%s absolute prestate does not match: Provider: %s | Contract: %s", 
            v.name, calculatedProviderHash, contractHash)
    }
}
```

## MultiPrestateProvider 동작 과정

**파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/trace/prestates/multi.go`

### 1. 파일 다운로드 시도

```go
// PrestatePath 함수 (라인 40-65)
func (m *MultiPrestateProvider) PrestatePath(ctx context.Context, hash common.Hash) (string, error) {
    // 1. 로컬 캐시에서 찾기 (라인 42-50)
    for _, fileType := range supportedFileTypes {
        path := filepath.Join(m.dataDir, hash.Hex()+fileType)
        if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
            continue // File doesn't exist, try the next file type
        } else if err != nil {
            return "", fmt.Errorf("error checking for existing prestate %v in file %v: %w", hash, path, err)
        }
        return path, nil // Found an existing file so use it
    }
    
    // 2. 파일서버에서 다운로드 (라인 52-65)
    for _, fileType := range supportedFileTypes {
        path := filepath.Join(m.dataDir, hash.Hex()+fileType)
        if err := m.fetchPrestate(ctx, hash, fileType, path); errors.Is(err, ErrPrestateUnavailable) {
            combinedErr = errors.Join(combinedErr, err)
            continue // Didn't find prestate in this format, try the next
        } else if err != nil {
            return "", fmt.Errorf("error downloading prestate %v to file %v: %w", hash, path, err)
        }
        return path, nil // Successfully downloaded a prestate so use it
    }
    return "", errors.Join(ErrPrestateUnavailable, combinedErr)
}
```

### 2. 지원되는 파일 형식

**파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/trace/prestates/multi.go:23`

```go
// supportedFileTypes lists, in preferred order, the prestate file types to attempt to download
supportedFileTypes = []string{".bin.gz", ".json.gz", ".json"}
```

- `.bin.gz` (바이너리 압축) - 우선순위 1
- `.json.gz` (JSON 압축) - 우선순위 2  
- `.json` (일반 JSON) - 우선순위 3

### 3. 파일서버 구조
```
http://fileserver/
├── 0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195.json.gz
├── 0x0383d8cf3feb2989ac49ba58e92c69cbf26dd82ea6b650d09efbda7b9a1b29c7.json.gz
└── ...
```

## Cold Game vs Warm Game 검증

### Cold Game (새로 생성된 게임)
- `claimCount == 1` (root claim만 존재)
- `gameStatus == InProgress`
- **startingRootHash가 초기화되지 않음** (`0xdead...`)
- Prestate validation **실패 예상**

### Warm Game (진행 중인 게임)
- 여러 claim들이 존재
- startingRootHash가 올바른 값으로 설정됨
- Prestate validation **성공**

## AnchorStateRegistry와의 관계

### startingAnchorRoot 설정 과정

1. **게임 생성 시**: `FaultDisputeGame.initialize()`
2. **AnchorStateRegistry 조회**: `getAnchorRoot()` 호출
3. **fallback 값 사용**: anchorGame이 없으면 `startingAnchorRoot` 사용
4. **게임에 설정**: `startingOutputRoot = Proposal({...})`

### 현재 문제 상황

```solidity
// AnchorStateRegistry.getAnchorRoot()
if (address(anchorGame) == address(0)) {
    return (startingAnchorRoot.root, startingAnchorRoot.l2SequenceNumber);
    // ❌ startingAnchorRoot.root = 0xdead... (잘못된 값)
}
```

## 검증 실패 시나리오

### 1. absolutePrestate 검증
- **Contract**: `0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195` ✅
- **Provider**: `0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195` ✅  
- **결과**: **성공**

### 2. starting state root 검증 (Cold Game)
- **Contract**: `0xdead0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000` ❌
- **Provider**: `0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195` ✅
- **결과**: **실패** - "output root absolute prestate does not match"

## 해결 방안

### 1. skipPrestateValidation 플래그 (현재 구현)

**파일**: `/Users/zena/tokamak-projects/optimism/op-challenger/game/fault/register_task.go`

```go
// NewCannonRegisterTask 함수 (라인 97)
skipPrestateValidation: gameType == faultTypes.PermissionedGameType,

// NewSuperCannonRegisterTask 함수 (라인 58)  
skipPrestateValidation: gameType == faultTypes.SuperPermissionedGameType,

// NewSuperAsteriscKonaRegisterTask 함수 (라인 200)
skipPrestateValidation: gameType == faultTypes.SuperPermissionedGameType,

// validator 생성 시 체크 (라인 336-338)
if !e.skipPrestateValidation {
    validators = append(validators, NewPrestateValidator(e.gameType.String(), contract.GetAbsolutePrestateHash, vmPrestateProvider))
    validators = append(validators, NewPrestateValidator("output root", contract.GetStartingRootHash, prestateProvider))
}
```

**현재 동작**: 
- **PermissionedGameType**, **SuperPermissionedGameType**: prestate validation 건너뜀
- **기타 게임 타입**: prestate validation 수행

### 1-1. Cold Game 예외 처리 (제안된 개선 방안)
```go
// 게임 상태 기반 예외 처리 (아직 구현되지 않음)
if gameStatus == InProgress && claimCount == 1 {
    skipPrestateValidation = true
}
```

### 2. AnchorStateRegistry 수정
- `startingAnchorRoot`를 올바른 L2 genesis root로 설정
- 새로운 게임들이 올바른 starting root를 가지도록 함

### 3. --allow-invalid-prestate 플래그
- Cold game 검증을 우회
- 개발/테스트 환경에서만 사용 권장

## 결론

Challenger는 두 가지 핵심 값을 검증합니다:

1. **VM absolutePrestate 검증**: 
   - 파일서버에서 다운로드한 prestate 해시와 컨트랙트 값 비교
   - VM 실행의 초기 상태 검증

2. **Starting state root 검증**: 
   - L2 genesis output root와 게임의 starting root 비교  
   - 게임이 올바른 L2 상태에서 시작하는지 검증

Cold game에서는 starting root가 초기화되지 않아 state root validation이 실패하는 것이 정상이며, 이를 해결하려면 AnchorStateRegistry의 startingAnchorRoot를 올바른 L2 genesis root 값으로 설정해야 합니다.