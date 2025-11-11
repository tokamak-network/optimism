# DeployImplementations.s.sol 설명서

## 개요

`DeployImplementations.s.sol`은 Optimism OP Stack의 핵심 인프라 구현체(implementation) 컨트랙트들을 배포하는 Foundry 스크립트입니다. 이 스크립트는 Superchain 내에서 공유되는 구현체 컨트랙트들을 결정론적으로 배포하며, 이후 개별 OP Chain들이 이 구현체들을 프록시 패턴을 통해 참조하게 됩니다.

## 주요 역할

### 1. 구현체 배포 오케스트레이션

`run()` 함수는 모든 구현체 배포를 순차적으로 실행합니다:

```solidity
function run(Input memory _input) public returns (Output memory output_) {
    assertValidInput(_input);

    // Deploy the implementations.
    deploySuperchainConfigImpl(output_);
    deployProtocolVersionsImpl(output_);
    deploySystemConfigImpl(output_);
    deployL1CrossDomainMessengerImpl(output_);
    deployL1ERC721BridgeImpl(output_);
    deployL1StandardBridgeImpl(output_);
    deployOptimismMintableERC20FactoryImpl(output_);
    deployOptimismPortalImpl(_input, output_);
    deployETHLockboxImpl(output_);
    deployDelayedWETHImpl(_input, output_);
    deployPreimageOracleSingleton(_input, output_);
    deployMipsSingleton(_input, output_);
    deployDisputeGameFactoryImpl(output_);
    deployAnchorStateRegistryImpl(_input, output_);
    deployRATImpl(output_);

    // Deploy the OP Contracts Manager with the new implementations set.
    deployOPContractsManager(_input, output_);

    assertValidOutput(_input, output_);
}
```

## 배포되는 컨트랙트 카테고리

### A. 코어 컨트랙트 (Core Contracts)

#### 1. Superchain 레벨 컨트랙트
- **SuperchainConfig**: Superchain 전체의 설정을 관리
- **ProtocolVersions**: 프로토콜 버전 정보를 관리

#### 2. L1 브릿지 컨트랙트
- **L1CrossDomainMessenger**: L1과 L2 간 메시지 전달
- **L1StandardBridge**: 표준 토큰 브릿지
- **L1ERC721Bridge**: NFT 브릿지
- **OptimismMintableERC20Factory**: L2에서 발행 가능한 ERC20 토큰 팩토리

#### 3. 시스템 설정
- **SystemConfig**: OP Chain의 시스템 설정 관리
- **ETHLockbox**: 인터롭 마이그레이션을 위한 ETH 잠금 컨트랙트

### B. Fault Proof 시스템

Fault Proof 시스템은 L2의 상태를 L1에서 검증하는 핵심 메커니즘입니다:

| 컨트랙트 | 프록시 여부 | 배포 방식 | MCP Ready |
|---------|----------|---------|-----------|
| DisputeGameFactory | Yes | Bespoke | Yes |
| AnchorStateRegistry | Yes | Bespoke | Yes |
| FaultDisputeGame | No | Bespoke | No |
| PermissionedDisputeGame | No | Bespoke | No |
| DelayedWETH | Yes | Bespoke (2개) | Yes* |
| PreimageOracle | No | Shared | N/A |
| MIPS64 | No | Shared | N/A |
| OptimismPortal2 | Yes | Shared | Yes* |

#### 주요 컴포넌트:

**1. OptimismPortal2**
```solidity
function deployOptimismPortalImpl(Input memory _input, Output memory _output) private {
    uint256 proofMaturityDelaySeconds = _input.proofMaturityDelaySeconds;
    IOptimismPortal impl = IOptimismPortal(
        DeployUtils.createDeterministic({
            _name: "OptimismPortal2",
            _args: DeployUtils.encodeConstructor(
                abi.encodeCall(IOptimismPortal.__constructor__, (proofMaturityDelaySeconds))
            ),
            _salt: _salt
        })
    );
    vm.label(address(impl), "OptimismPortalImpl");
    _output.optimismPortalImpl = impl;
}
```
- L2에서 L1으로의 인출(withdrawal) 처리
- Fault Proof 시스템과 통합

**2. DisputeGameFactory**
- 다양한 타입의 분쟁 게임(dispute game) 생성 및 관리
- Fault Proof의 핵심 팩토리 컨트랙트

**3. AnchorStateRegistry**
- 각 게임 타입별 신뢰할 수 있는 루트 클레임 저장
- Fault Proof의 시작점 역할

**4. DelayedWETH**
```solidity
function deployDelayedWETHImpl(Input memory _input, Output memory _output) private {
    uint256 withdrawalDelaySeconds = _input.withdrawalDelaySeconds;
    IDelayedWETH impl = IDelayedWETH(
        DeployUtils.createDeterministic({
            _name: "DelayedWETH",
            _args: DeployUtils.encodeConstructor(
                abi.encodeCall(IDelayedWETH.__constructor__, (withdrawalDelaySeconds))
            ),
            _salt: _salt
        })
    );
    vm.label(address(impl), "DelayedWETHImpl");
    _output.delayedWETHImpl = impl;
}
```
- 분쟁 게임 참가자의 담보(bond) 관리
- 인출 지연 메커니즘 구현

**5. PreimageOracle & MIPS64**
```solidity
function deployPreimageOracleSingleton(Input memory _input, Output memory _output) private {
    uint256 minProposalSizeBytes = _input.minProposalSizeBytes;
    uint256 challengePeriodSeconds = _input.challengePeriodSeconds;
    IPreimageOracle singleton = IPreimageOracle(
        DeployUtils.createDeterministic({
            _name: "PreimageOracle",
            _args: DeployUtils.encodeConstructor(
                abi.encodeCall(IPreimageOracle.__constructor__,
                    (minProposalSizeBytes, challengePeriodSeconds))
            ),
            _salt: _salt
        })
    );
    vm.label(address(singleton), "PreimageOracleSingleton");
    _output.preimageOracleSingleton = singleton;
}

function deployMipsSingleton(Input memory _input, Output memory _output) private {
    uint256 mipsVersion = _input.mipsVersion;
    IPreimageOracle preimageOracle = IPreimageOracle(address(_output.preimageOracleSingleton));

    // Mainnet과 Sepolia에서는 MIPS64만 배포
    if (mipsVersion < 2) {
        if (block.chainid == Chains.Mainnet || block.chainid == Chains.Sepolia) {
            revert("DeployImplementations: Only Mips64 should be deployed on Mainnet or Sepolia");
        }
    }

    IMIPS64 singleton = IMIPS64(
        DeployUtils.createDeterministic({
            _name: "MIPS64",
            _args: DeployUtils.encodeConstructor(
                abi.encodeCall(IMIPS64.__constructor__, (preimageOracle, mipsVersion))
            ),
            _salt: DeployUtils.DEFAULT_SALT
        })
    );
    vm.label(address(singleton), "MIPSSingleton");
    _output.mipsSingleton = singleton;
}
```
- **PreimageOracle**: 온체인에서 preimage 데이터 제공
- **MIPS64**: MIPS64 ISA를 온체인에서 에뮬레이션
- Fault Proof 검증의 기반이 되는 싱글톤 컨트랙트

### C. RAT (Resource Accounting Token) 구현체

```solidity
function deployRATImpl(Output memory _output) private {
    IRAT impl = IRAT(
        DeployUtils.createDeterministic({
            _name: "RAT",
            _args: DeployUtils.encodeConstructor(abi.encodeCall(IRAT.__constructor__, ())),
            _salt: _salt
        })
    );
    vm.label(address(impl), "RATImpl");
    _output.ratImpl = impl;
}
```

RAT는 Optimism의 리소스 계정(resource accounting) 시스템을 담당하는 새로운 컴포넌트입니다.

### D. OPContractsManager 및 서브 컴포넌트

OPContractsManager는 모든 구현체와 Blueprint를 관리하는 중앙 컨트랙트 매니저입니다:

```solidity
struct Output {
    IOPContractsManager opcm;
    IOPContractsManagerContractsContainer opcmContractsContainer;
    IOPContractsManagerGameTypeAdder opcmGameTypeAdder;
    IOPContractsManagerDeployer opcmDeployer;
    IOPContractsManagerUpgrader opcmUpgrader;
    IOPContractsManagerInteropMigrator opcmInteropMigrator;
    IOPContractsManagerStandardValidator opcmStandardValidator;
    // ... 기타 구현체들
}
```

#### 서브 컴포넌트 역할:

1. **OPContractsManagerContractsContainer**
   - Blueprint와 구현체 주소를 저장하는 컨테이너

2. **OPContractsManagerGameTypeAdder**
   - DisputeGameFactory에 새로운 게임 타입 추가

3. **OPContractsManagerDeployer**
   - 새로운 OP Chain 배포 로직

4. **OPContractsManagerUpgrader**
   - 기존 OP Chain 업그레이드 로직

5. **OPContractsManagerInteropMigrator**
   - 인터롭(interoperability) 마이그레이션 로직

6. **OPContractsManagerStandardValidator**
   - 배포 설정 검증 로직

## 결정론적 배포 (CREATE2)

모든 컨트랙트는 동일한 salt를 사용하여 결정론적으로 배포됩니다:

```solidity
bytes32 internal _salt = DeployUtils.DEFAULT_SALT;
```

이를 통해:
- **재현 가능한 배포**: 동일한 입력으로 동일한 주소에 배포
- **크로스체인 일관성**: 여러 체인에서 동일한 주소 사용 가능
- **예측 가능성**: 배포 전에 주소를 계산 가능

## Blueprint 시스템

Blueprint는 프록시 컨트랙트의 템플릿 역할을 합니다:

```solidity
IOPContractsManager.Blueprints memory blueprints;
vm.startBroadcast(msg.sender);
address checkAddress;
(blueprints.addressManager, checkAddress) = DeployUtils.createDeterministicBlueprint(
    vm.getCode("AddressManager"), _salt
);
(blueprints.proxy, checkAddress) = DeployUtils.createDeterministicBlueprint(
    vm.getCode("Proxy"), _salt
);
(blueprints.proxyAdmin, checkAddress) = DeployUtils.createDeterministicBlueprint(
    vm.getCode("ProxyAdmin"), _salt
);
// ... 기타 Blueprint들
```

Blueprint로 배포되는 컨트랙트:
- AddressManager
- Proxy
- ProxyAdmin
- L1ChugSplashProxy
- ResolvedDelegateProxy
- PermissionedDisputeGame
- FaultDisputeGame (Permissionless)
- SuperPermissionedDisputeGame
- SuperFaultDisputeGame (Super Permissionless)

## 입력 파라미터 (Input)

```solidity
struct Input {
    uint256 withdrawalDelaySeconds;           // DelayedWETH 인출 지연 시간
    uint256 minProposalSizeBytes;            // PreimageOracle 최소 제안 크기
    uint256 challengePeriodSeconds;          // PreimageOracle 챌린지 기간
    uint256 proofMaturityDelaySeconds;       // OptimismPortal 증명 성숙 지연
    uint256 disputeGameFinalityDelaySeconds; // AnchorStateRegistry 최종성 지연
    uint256 mipsVersion;                     // MIPS 버전 (2 = MIPS64)
    // DeploySuperchain.s.sol 출력값
    ISuperchainConfig superchainConfigProxy;
    IProtocolVersions protocolVersionsProxy;
    IProxyAdmin superchainProxyAdmin;
    address upgradeController;
    address challenger;
}
```

### 파라미터 설명:

- **withdrawalDelaySeconds**: 분쟁 게임의 담보 인출 지연 시간 (일반적으로 7일)
- **minProposalSizeBytes**: PreimageOracle의 최소 preimage 크기
- **challengePeriodSeconds**: PreimageOracle preimage에 대한 챌린지 기간
- **proofMaturityDelaySeconds**: Fault Proof가 성숙하는 데 필요한 시간
- **disputeGameFinalityDelaySeconds**: 분쟁 게임이 최종화되기까지의 시간
- **mipsVersion**: MIPS 에뮬레이터 버전 (프로덕션에서는 2 = MIPS64 사용)

## 검증 (Validation)

### 입력 검증
```solidity
function assertValidInput(Input memory _input) private pure {
    require(_input.withdrawalDelaySeconds != 0, "withdrawalDelaySeconds not set");
    require(_input.minProposalSizeBytes != 0, "minProposalSizeBytes not set");
    require(_input.challengePeriodSeconds != 0, "challengePeriodSeconds not set");
    require(_input.challengePeriodSeconds <= type(uint64).max,
        "challengePeriodSeconds too large");
    require(_input.proofMaturityDelaySeconds != 0, "proofMaturityDelaySeconds not set");
    require(_input.disputeGameFinalityDelaySeconds != 0,
        "disputeGameFinalityDelaySeconds not set");
    require(_input.mipsVersion != 0, "mipsVersion not set");
    require(address(_input.superchainConfigProxy) != address(0),
        "superchainConfigProxy not set");
    require(address(_input.protocolVersionsProxy) != address(0),
        "protocolVersionsProxy not set");
    require(address(_input.superchainProxyAdmin) != address(0),
        "superchainProxyAdmin not set");
    require(address(_input.upgradeController) != address(0),
        "upgradeController not set");
}
```

### 출력 검증
`assertValidOutput()` 함수는 배포된 모든 컨트랙트의 유효성을 검증합니다:
- 주소가 제로 주소가 아닌지 확인
- 각 컨트랙트의 초기화 상태 확인
- ChainAssertions를 통한 세부 검증

## 배포 순서의 중요성

배포는 의존성 순서를 고려하여 진행됩니다:

1. **기본 구현체** (SuperchainConfig, ProtocolVersions, SystemConfig 등)
2. **브릿지 컨트랙트** (L1CrossDomainMessenger, Bridges 등)
3. **Fault Proof 기반 컨트랙트** (PreimageOracle → MIPS → Portal → DelayedWETH)
4. **게임 팩토리 및 레지스트리** (DisputeGameFactory, AnchorStateRegistry)
5. **RAT 구현체**
6. **OPContractsManager 및 서브 컴포넌트**

## 사용 예시

```solidity
// 1. 입력 파라미터 준비
DeployImplementations.Input memory input = DeployImplementations.Input({
    withdrawalDelaySeconds: 604800,              // 7일
    minProposalSizeBytes: 126000,                // ~126KB
    challengePeriodSeconds: 86400,               // 1일
    proofMaturityDelaySeconds: 604800,           // 7일
    disputeGameFinalityDelaySeconds: 302400,     // 3.5일
    mipsVersion: 2,                              // MIPS64
    superchainConfigProxy: ISuperchainConfig(superchainConfigAddr),
    protocolVersionsProxy: IProtocolVersions(protocolVersionsAddr),
    superchainProxyAdmin: IProxyAdmin(proxyAdminAddr),
    upgradeController: upgradeControllerAddr,
    challenger: challengerAddr
});

// 2. 스크립트 실행
DeployImplementations deployer = new DeployImplementations();
DeployImplementations.Output memory output = deployer.run(input);

// 3. 배포된 주소 사용
address opcm = address(output.opcm);
address portalImpl = address(output.optimismPortalImpl);
// ...
```

## 다음 단계

이 스크립트로 구현체를 배포한 후:

1. **DeployOPChain.s.sol** 실행
   - 개별 OP Chain의 프록시 배포
   - 프록시가 이 구현체들을 참조하도록 설정

2. **DisputeGame 설정**
   - DisputeGameFactory에 게임 타입 추가
   - 각 게임 타입에 맞는 설정 적용

3. **검증 및 모니터링**
   - 배포된 컨트랙트의 동작 확인
   - 업그레이드 권한 및 접근 제어 검증

## 보안 고려사항

1. **업그레이드 권한**
   - `upgradeController`가 모든 업그레이드를 제어
   - Safe 멀티시그 사용 권장

2. **결정론적 배포**
   - Salt가 노출되어도 배포자만 동일 주소에 배포 가능
   - 다른 체인에 배포 시 주의 필요

3. **초기화 보호**
   - 모든 구현체는 생성자에서 `_disableInitializers()` 호출
   - 프록시를 통해서만 사용되도록 보장

4. **검증 필수**
   - 배포 후 반드시 `assertValidOutput()` 통과 확인
   - Etherscan 등에서 소스 코드 검증

## 관련 파일

- **DeployOPChain.s.sol**: 개별 OP Chain 배포
- **DeploySuperchain.s.sol**: Superchain 레벨 컨트랙트 배포
- **DeployUtils.sol**: 배포 유틸리티 함수
- **ChainAssertions.sol**: 배포 검증 함수
- **StandardConstants.sol**: 표준 설정 상수

## 버전 정보

이 문서는 v1.16.0 마이그레이션을 위한 DeployImplementations.s.sol을 기준으로 작성되었습니다.

주요 변경사항:
- RAT 구현체 추가
- MIPS64 지원
- OPContractsManager 아키텍처 개선
- ETHLockbox 추가 (인터롭 마이그레이션용)

