# Devnet Allocs

devnet-allocs는 e2e 테스트를 위한 L1/L2 genesis allocs 파일을 생성하는 도구입니다.

## 개요

이 도구는 op-deployer를 사용하여 로컬 개발 네트워크(devnet)에 필요한 모든 genesis 파일을 생성합니다. 생성된 파일들은 다른 프로젝트(예: ton-staking-v2)에서 e2e 테스트 환경을 구축할 때 사용할 수 있습니다.

## 사용법

### 기본 사용법

```bash
# .devnet 디렉토리에 allocs 파일 생성
just devnet-allocs
```

### 커스텀 출력 디렉토리

```bash
# 커스텀 출력 디렉토리 지정
just devnet-allocs-outdir my-devnet
```

### Go 명령 직접 실행

```bash
# 기본 옵션으로 실행
go run ./op-chain-ops/cmd/devnet-allocs

# 옵션 지정
go run ./op-chain-ops/cmd/devnet-allocs \
  --outdir=.devnet \
  --l1-chain-id=900 \
  --l2-chain-id=901 \
  --fund-dev-accounts=true
```

## 생성되는 파일

| 파일명 | 설명 | 크기 (대략) |
|--------|------|------------|
| `addresses.json` | L1 컨트랙트 주소 목록 | ~2KB |
| `allocs-l1.json` | L1 genesis 상태 (계정, 코드, 스토리지) | ~1.3MB |
| `allocs-l2.json` | L2 genesis 상태 (기본, Granite fork) | ~9.4MB |
| `allocs-l2-granite.json` | L2 genesis 상태 (Granite fork) | ~9.4MB |
| `devnetL1.json` | Deploy config (체인 설정) | ~5KB |

### addresses.json 예시

```json
{
  "AddressManager": "0xa2dc5ca3f40788d1abe20318d7a7dd0cb4e3c50a",
  "DisputeGameFactory": "0x0298dd8babce73e3211da1a3582fbf0d400b97ab",
  "DisputeGameFactoryProxy": "0x22b82825a3d88cabf27fc4d21a859306b22324fa",
  "L1CrossDomainMessenger": "0xd26bb3aaaa4cb5638a8581a4c4b1d937d8e05c54",
  "L1CrossDomainMessengerProxy": "0x5be89624d52b618ba956e4a866c4898ee19e8c6d",
  "L1StandardBridge": "0x44afb7722af276a601d524f429016a18b6923df0",
  "L1StandardBridgeProxy": "0xd2de008b1545b69cb5dcacf1a083f92b5604aa8f",
  "OptimismPortal": "0x8ca9651e4d2497c9060c8f4b7a04cf10fd75d976",
  "OptimismPortalProxy": "0xa5fc72052dfdf9b733f70c44d737571a765eda81",
  "SystemConfig": "0xfaa660bf783cbaa55e1b7f3475c20db74a53b9fa",
  "SystemConfigProxy": "0xaeff771968785e279632dd6ed0af1f6c1bfedced",
  ...
}
```

### devnetL1.json 주요 설정

```json
{
  "l1ChainID": 900,
  "l2ChainID": 901,
  "l1BlockTime": 2,
  "l2BlockTime": 1,
  "finalizationPeriodSeconds": 2,
  "maxSequencerDrift": 300,
  "sequencerWindowSize": 200,
  "fundDevAccounts": true,
  ...
}
```

## 테스트 계정

devnet-allocs는 Hardhat/Foundry의 기본 테스트 계정을 사용합니다:

| 역할 | 주소 | 개인키 |
|------|------|--------|
| Deployer | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| Batcher | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| Proposer | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |
| SequencerP2P | `0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc` | `0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba` |
| Challenger | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | `0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a` |

## 사전 요구사항

1. **Forge artifacts**: `packages/contracts-bedrock/forge-artifacts` 디렉토리에 컴파일된 컨트랙트가 필요합니다.

```bash
# forge artifacts 빌드
cd packages/contracts-bedrock && forge build
```

2. **Prestate 파일** (선택사항): Cannon/Asterisc prestate 파일이 있으면 해당 해시를 사용합니다.
   - `op-program/bin/prestate-proof-mt64.json` (Cannon)
   - `op-program/bin/prestate-asterisc.json` (Asterisc)

3. **Devnet 실행을 위한 추가 요구사항**:
   - `just` (명령어 러너)
   - `anvil` (Foundry 포함)
   - `cast` (Foundry 포함)
   - `op-geth` (L2 실행용, 선택사항)
   - `openssl` (JWT secret 생성용)

```bash
# just 설치 (macOS)
brew install just

# just 설치 (Linux)
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin

# Foundry 설치
curl -L https://foundry.paradigm.xyz | bash
foundryup

# op-geth 설치 (선택사항)
go install github.com/ethereum-optimism/op-geth@latest
```

## 다른 프로젝트에서 사용하기

### ton-staking-v2 예시 (L1만 사용)

```bash
# 터미널 1: optimism 레포에서 L1 시작
cd /path/to/optimism
just devnet-allocs   # allocs 파일 생성 (최초 1회)
just devnet-l1       # L1 시작 (포그라운드에서 실행됨)

# 터미널 2: ton-staking-v2에서 테스트 실행
cd /path/to/ton-staking-v2
forge test --fork-url http://localhost:8545

# 터미널 1에서 Ctrl+C로 L1 중지
```

### ton-staking-v2에서 컨트랙트 주소 사용하기

생성된 `addresses.json`에서 Optimism 컨트랙트 주소를 참조할 수 있습니다:

```solidity
// test/MyTest.t.sol
import {Test} from "forge-std/Test.sol";

contract MyTest is Test {
    // addresses.json의 주소들
    address constant OPTIMISM_PORTAL_PROXY = 0xa5fc72052dfdf9b733f70c44d737571a765eda81;
    address constant DISPUTE_GAME_FACTORY_PROXY = 0x22b82825a3d88cabf27fc4d21a859306b22324fa;
    address constant SYSTEM_CONFIG_PROXY = 0xaeff771968785e279632dd6ed0af1f6c1bfedced;

    function setUp() public {
        // L1 devnet에 fork
        vm.createSelectFork("http://localhost:8545");
    }

    function testExample() public {
        // Optimism 컨트랙트와 상호작용
    }
}
```

또는 JSON 파일에서 동적으로 로드:

```solidity
// test/MyTest.t.sol
import {Test} from "forge-std/Test.sol";

contract MyTest is Test {
    address optimismPortalProxy;

    function setUp() public {
        vm.createSelectFork("http://localhost:8545");

        // addresses.json에서 주소 로드
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/../optimism/.devnet/addresses.json");
        string memory json = vm.readFile(path);
        optimismPortalProxy = vm.parseJsonAddress(json, ".OptimismPortalProxy");
    }
}
```

### ton-staking-v2 .env 설정 예시

```bash
# ton-staking-v2/.env
L1_RPC_URL=http://localhost:8545
L1_CHAIN_ID=900

# Optimism 컨트랙트 주소 (addresses.json에서 복사)
OPTIMISM_PORTAL_PROXY=0xa5fc72052dfdf9b733f70c44d737571a765eda81
DISPUTE_GAME_FACTORY_PROXY=0x22b82825a3d88cabf27fc4d21a859306b22324fa
SYSTEM_CONFIG_PROXY=0xaeff771968785e279632dd6ed0af1f6c1bfedced

# 테스트 계정 (Hardhat 기본 계정)
DEPLOYER_PRIVATE_KEY=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 백그라운드에서 L1 실행하기

```bash
# 백그라운드 실행 (nohup 사용)
cd /path/to/optimism
nohup just devnet-l1 > .devnet/l1.log 2>&1 &
echo $! > .devnet/l1.pid

# 로그 확인
tail -f .devnet/l1.log

# 중지
kill $(cat .devnet/l1.pid)
```

### 환경 변수로 경로 지정

```bash
export DEVNET_ALLOCS_PATH=/path/to/optimism/.devnet
```

## Devnet 실행

### 빠른 시작

```bash
# 1. allocs 생성 + devnet 시작 (L1 + L2)
just devnet-up

# 2. 테스트 완료 후 종료
just devnet-down
```

### 개별 명령

```bash
# L1만 시작 (allocs가 이미 생성된 경우)
just devnet-l1

# L2 genesis 생성 (L1이 실행 중이어야 함)
just devnet-l2-genesis

# 전체 devnet 시작
just devnet-up

# devnet 중지
just devnet-down

# 모든 devnet 파일 삭제
just devnet-clean
```

### Devnet 환경 정보

| 항목 | 값 |
|------|-----|
| L1 RPC | `http://localhost:8545` |
| L2 RPC | `http://localhost:9545` |
| L1 Chain ID | 900 |
| L2 Chain ID | 901 |
| L1 Block Time | 2초 |
| L2 Block Time | 1초 |

### 스크립트 직접 실행

```bash
# L1 시작 (커스텀 옵션)
./ops/scripts/devnet/start-l1.sh --port 8545 --chain-id 900

# L2 genesis 생성
./ops/scripts/devnet/generate-l2-genesis.sh --l1-rpc http://localhost:8545

# 전체 devnet 시작
./ops/scripts/devnet/start-devnet.sh --allocs-dir .devnet
```

## 명령줄 옵션

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `--outdir` | `.devnet` | 출력 디렉토리 |
| `--l1-chain-id` | `900` | L1 체인 ID |
| `--l2-chain-id` | `901` | L2 체인 ID |
| `--fund-dev-accounts` | `true` | 개발 계정에 ETH 충전 여부 |

## 포함된 Dispute Game 타입

생성된 allocs에는 다음 Dispute Game들이 포함됩니다:

| Game Type | 설명 |
|-----------|------|
| 254 | Fast Game (Alphabet VM, 빠른 테스트용) |
| 255 | Alphabet Game (Alphabet VM) |
| 0 | Cannon Game (MIPS VM) |
| 2 | Asterisc Game (RISC-V VM) |

## TON Staking V3 통합

devnet-allocs는 TON Staking V3 RAT(Random Audit Test) 통합을 위한 설정도 포함합니다:

```json
{
  "deployRAT": true,
  "perTestBondAmount": "0x5af3107a4000",
  "evidenceSubmissionPeriod": 600,
  "minimumStakingBalance": "0xde0b6b3a7640000",
  "ratTriggerProbability": "0x186a0",
  "ratManager": "<deployer address>"
}
```

## 문제 해결

### Forge artifacts가 없는 경우

```
panic: failed to create artifacts locator: ...
```

해결: `just forge-build` 또는 `cd packages/contracts-bedrock && forge build` 실행

### Prestate 파일 경고

```
WARN Cannon prestate file not found, using default
```

이는 경고일 뿐이며, 기본 prestate 해시가 사용됩니다. Cannon 테스트가 필요한 경우 prestate 파일을 빌드하세요.

## 관련 문서

- [TON Staking V3 RAT Integration](./ton-staking-v3-rat-integration.md)
- [op-deployer Documentation](../op-deployer/README.md)
