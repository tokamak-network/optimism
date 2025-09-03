# 배포 검증 및 수정 가이드

## 문제 상황
- OPContractsManager에서 `disputeGameType` 설정을 수정했지만 배포에서 여전히 `respectedGameType = 1`
- 수정사항이 실제 배포에 반영되지 않는 문제

## 해결 방법

### 1. 배포 검증용 뷰 함수 추가

OPContractsManager.sol 파일 끝에 다음 함수 추가:

```solidity
/// @notice Test function to verify deployment version
/// @return The deployment version string to verify our changes are deployed
function getDeploymentVersion() external pure returns (string memory) {
    return "v2.0-fixed-disputeGameType";
}
```

### 2. 컨트랙트 재빌드

```bash
cd /Users/zena/tokamak-projects/optimism/packages/contracts-bedrock
forge build --force
```

### 3. Docker 이미지 재빌드

컨트랙트 변경사항이 Docker 이미지에 포함되도록:

```bash
cd /Users/zena/tokamak-projects/optimism
just build-contracts
```

### 4. 데브넷 재배포

새로운 바이너리로 데브넷 재배포:

```bash
cd /Users/zena/tokamak-projects/optimism/kurtosis-devnet
just devnet
```

### 5. 배포 검증

배포 완료 후 다음 명령으로 검증:

```bash
# 1. 새 환경 변수 설정
kurtosis files download simple-devnet devnet-descriptor-0 /tmp/new-devnet-desc
L1_RPC=$(grep -o '"rpc":"http://[^"]*' /tmp/new-devnet-desc/env.json | cut -d'"' -f4)
OPCM_ADDRESS=$(grep -o 'OPContractsManager[^"]*":"[^"]*' /tmp/new-devnet-desc/env.json | cut -d'"' -f3)
OP_PORTAL=$(grep -o 'OptimismPortalProxy[^"]*":"[^"]*' /tmp/new-devnet-desc/env.json | cut -d'"' -f3)

# 2. 배포 버전 확인 (새 함수 호출)
cast call $OPCM_ADDRESS "getDeploymentVersion()(string)" --rpc-url $L1_RPC

# 3. respectedGameType 확인 (0이어야 함)
cast call $OP_PORTAL "respectedGameType()(uint32)" --rpc-url $L1_RPC

# 4. challenger 로그 확인 (prestate 오류 없어야 함)
docker logs $(docker ps | grep challenger | awk '{print $1}') --tail 10
```

### 6. 예상 결과

성공적으로 배포되었다면:
- `getDeploymentVersion()` → `"v2.0-fixed-disputeGameType"`
- `respectedGameType()` → `0`
- Challenger 로그에서 prestate 오류 없음

### 7. 문제 해결

만약 여전히 문제가 있다면:

```bash
# Kurtosis 캐시 클리어 후 재배포
kurtosis clean -a
cd /Users/zena/tokamak-projects/optimism/kurtosis-devnet
just devnet
```

## 핵심 수정사항

### line 1385 수정
```solidity
// 수정 전
GameTypes.PERMISSIONED_CANNON

// 수정 후  
_input.disputeGameType
```

### 추가된 검증 함수
```solidity
function getDeploymentVersion() external pure returns (string memory) {
    return "v2.0-fixed-disputeGameType";
}
```

이를 통해 배포된 컨트랙트가 실제로 우리 수정사항을 포함하는지 명확히 확인할 수 있습니다.