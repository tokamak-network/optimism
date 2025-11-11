# Prestate Hash 이해하기

## 🎯 **Prestate 해시란 무엇인가?**

**Prestate 해시**는 Optimism의 fault proof 시스템에서 **L2 상태의 초기값을 나타내는 고유한 식별자**입니다. 이는 Cannon VM이 실행되기 전의 초기 상태를 해시로 표현한 것입니다.

### **핵심 개념**
- **초기 상태**: L2 체인의 특정 시점에서의 전체 상태
- **결정론적**: 동일한 입력으로는 항상 동일한 해시 생성
- **고유성**: 각 상태마다 고유한 해시값 보장
- **검증 가능**: 해시를 통해 상태의 무결성 검증 가능

## 🔧 **Prestate 해시 계산 과정**

### **1단계: ELF 파일 로드**
```bash
cannon load-elf --type multithreaded64-4 --path op-program-client64.elf --out prestate.bin.gz --meta meta.json
```

**세부 과정:**
1. **ELF 파일 파싱**: MIPS ELF 파일을 읽어서 프로그램 구조 분석
2. **메모리 매핑**: 프로그램의 코드와 데이터를 가상 메모리에 매핑
3. **초기 상태 생성**: VM의 초기 상태(레지스터, 메모리, 스택 등) 설정
4. **압축 저장**: 초기 상태를 `.bin.gz` 형식으로 압축 저장

### **2단계: Prestate 증명 생성**
```bash
cannon run --proof-at '=0' --stop-at '=1' --input prestate.bin.gz --proof-fmt '%d.json' --output ""
```

**세부 과정:**
1. **VM 초기화**: 저장된 초기 상태로 VM 시작
2. **0단계 실행**: VM을 1단계만 실행 (초기 상태 → 첫 번째 상태)
3. **증명 생성**: 초기 상태에서 첫 번째 상태로의 전환 증명 생성
4. **해시 계산**: 초기 상태의 해시값 계산

## 📊 **해시 계산 방식**

### **VM 상태 해시 계산**
```go
// op-challenger/game/fault/trace/vm/prestate.go
func (p *PrestateProvider) AbsolutePreStateCommitment(ctx context.Context) (common.Hash, error) {
    proof, _, _, err := p.stateConverter.ConvertStateToProof(ctx, p.prestate)
    if err != nil {
        return common.Hash{}, fmt.Errorf("cannot load absolute pre-state: %w", err)
    }
    return proof.ClaimValue, nil
}
```

### **해시 구성 요소**
1. **메모리 상태**: 모든 메모리 위치의 값들
2. **레지스터 상태**: 모든 CPU 레지스터 값들
3. **스택 상태**: 스택 포인터와 스택 내용
4. **프로그램 카운터**: 실행할 다음 명령어 주소
5. **기타 VM 상태**: VM의 내부 상태 정보들

### **최종 해시 생성**
```go
// 모든 상태 정보를 직렬화하여 Keccak256 해시 계산
hash := crypto.Keccak256(stateData)
// VM 상태 표시를 위해 첫 번째 바이트 수정
hash[0] = mipsevm.VMStatusUnfinished
```

## 🏗️ **Prestate 생성 과정**

### **전체 워크플로우**
```bash
# 1. op-program 빌드 (MIPS ELF 생성)
make op-program-client-mips

# 2. Cannon 빌드
make cannon

# 3. Prestate 생성
just _prestate-build ./prestate-build
```

### **내부 과정**
1. **ELF → 초기 상태**: `cannon load-elf` 명령으로 ELF 파일을 VM 초기 상태로 변환
2. **상태 압축**: 초기 상태를 `.bin.gz` 형식으로 압축 저장
3. **증명 생성**: `cannon run` 명령으로 초기 상태의 증명 생성
4. **해시 추출**: 증명 파일에서 초기 상태의 해시값 추출

## 🔍 **실제 해시 예시**

### **증명 파일 구조**
```json
// prestate-proof-mt64.json
{
  "pre": "0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195",
  "post": "0x...",
  "stateData": "..."
}
```

### **해시 구성**
- `pre`: 초기 상태의 해시 (Prestate 해시)
- `post`: 첫 번째 단계 실행 후 상태의 해시
- `stateData`: 실제 VM 상태 데이터

## 📁 **생성되는 파일들**

### **주요 파일들**
- `prestate-mt64.bin.gz`: 압축된 초기 상태 파일
- `prestate-proof-mt64.json`: 초기 상태 증명 및 해시
- `meta-mt64.json`: 디버깅을 위한 메타데이터

### **파일 용도**
- **`.bin.gz`**: VM이 로드할 수 있는 압축된 상태 데이터
- **`.json`**: 해시값과 증명 데이터
- **`meta.json`**: 심볼 정보와 디버깅 데이터

## ⚠️ **중요한 점들**

### **1. 결정론적 생성**
- 동일한 ELF 파일과 설정으로는 항상 동일한 prestate 해시 생성
- 빌드 환경이나 시간에 관계없이 일관된 결과
- 재현 가능한 빌드 보장

### **2. 버전별 차이**
- `mt64`: 64비트 멀티스레드 버전
- `interop`: 상호운용성 버전
- `mt64Next`: 실험적 64비트 버전
- 각 버전마다 다른 prestate 해시 생성

### **3. 동기화의 중요성**
- Proposer와 Challenger가 정확히 동일한 prestate 해시 사용해야 함
- 해시가 다르면 fault proof 게임이 올바르게 작동하지 않음
- 네트워크 전체의 일관성 보장

## 🔧 **검증 과정**

### **PrestateValidator 동작**
```go
func (v *PrestateValidator) Validate(ctx context.Context) error {
    // 1. 컨트랙트에서 prestate 해시 가져오기
    prestateHash, err := v.load(ctx)

    // 2. 로컬 제공자에서 prestate 해시 가져오기
    prestateCommitment, err := v.provider.AbsolutePreStateCommitment(ctx)

    // 3. 두 해시 비교
    if !bytes.Equal(prestateCommitment[:], prestateHash[:]) {
        return fmt.Errorf("prestate mismatch: Provider: %s | Contract: %s",
            prestateCommitment.Hex(), prestateHash.Hex())
    }
    return nil
}
```

### **검증 실패 시나리오**
1. **로컬 코드 변경**: 컨트랙트 코드 수정 후 새로운 prestate 필요
2. **빌드 환경 차이**: 다른 환경에서 빌드된 ELF 파일
3. **버전 불일치**: 다른 VM 버전 사용
4. **동기화 오류**: 네트워크에서 prestate 업데이트 누락

## 🛠️ **문제 해결**

### **일반적인 문제들**
1. **Prestate 불일치**: `AUTOFIX=true just simple-devnet` 사용
2. **빌드 오류**: `make cannon` 및 `make op-program` 재실행
3. **동기화 문제**: prestate 파일 재생성 및 배포

### **디버깅 방법**
```bash
# Prestate 해시 확인
cat op-program/bin/prestate-proof-mt64.json | jq -r .pre

# 파일 존재 확인
ls -la op-program/bin/prestate*.bin.gz

# 빌드 상태 확인
make cannon-prestates
```

## 📚 **관련 문서**

- [Prestate Synchronization Guide](./prestate-synchronization.md)
- [Troubleshooting Guide](../operations/troubleshooting-guide.md)
- [Game Type Configuration](../dispute-games/dispute-game-configuration-guide.md)

---

**참고**: 이 문서는 Optimism의 fault proof 시스템에서 prestate 해시의 생성과 검증 과정을 설명합니다. 실제 구현은 코드베이스의 변경에 따라 달라질 수 있습니다.
