# build-devnet.sh Process Documentation

## Overview

The `build-devnet.sh` script is a comprehensive tool for building and deploying Optimism devnet with all required services. It handles the complete deployment lifecycle from Docker image building to service verification.

## Sequential Execution Steps

### 1. **초기화 및 설정** (Initialization)
- Parse command line arguments (`--game-type`, `--help`)
- Set environment variables and paths
- Clean up existing enclaves
- Initialize build log files

### 2. **시스템 요구사항 검사** (System Requirements Check)
- Verify Go version
- Check Docker installation and running status
- Verify Kurtosis installation

### 3. **Docker 이미지 빌드** (Docker Image Building)
- Build 6 service images:
  - op-node, op-batcher, op-proposer
  - op-faucet, op-challenger, op-deployer
- Include Git commit information for reproducible builds
- Track build success/failure for each service

### 4. **컨트랙트 아티팩트 준비** (Contract Artifacts Preparation)
- Copy contract artifacts from forge-artifacts directory
- Create L1/L2 artifacts directories
- Verify critical artifacts (OptimismPortal2, DisputeGameFactory, etc.)
- Create tar files for Kurtosis upload

### 5. **데브넷 배포** (Devnet Deployment)

The deployment phase is the most complex part, consisting of 6 detailed sub-steps with specific timelines:

#### Step 1/6: Configuration Setup (~30 seconds)
- **YAML Template Processing**: Convert `simple.yaml` to `simple-processed.yaml`
  - Substitute Docker image references: `{{ localDockerImage "op-node" }}` → `op-node:devnet`
  - Replace contract artifact paths: `{{ localContractArtifacts "l1" }}` → `artifact://l1-artifacts`
  - Set prestate URLs and hashes for fault proof system
- **Template Variables Processed**:
  - Docker image tags for all services
  - Contract artifact locations
  - Prestate file paths and hashes
  - Configuration parameters

#### Step 2/6: Docker Image Preparation (~2-3 minutes)
- **Environment Cleanup**: Remove existing enclaves to prevent conflicts
- **Enclave Preparation**: Clean up previous deployment artifacts
- **Docker Image Verification**: Ensure all built images are available
- **Network Setup**: Prepare Kurtosis networking environment

#### Step 3/6: L1 Chain & Contract Deployment (~5-8 minutes) ⚠️ **Critical Phase**
- **Pre-deployment Safety Check**: Execute `ultra-simple-check.sh` to validate environment
- **Kurtosis Enclave Creation**: Create isolated deployment environment
- **Contract Artifacts Upload**:
  - Upload L1 artifacts (OptimismPortal2, DisputeGameFactory, SystemConfig)
  - Upload L2 artifacts (L2OutputOracle, L2CrossDomainMessenger)
- **L1 Chain Startup**:
  - Start Ethereum execution layer (Geth)
  - Start Ethereum consensus layer (Lighthouse/Teku)
  - Genesis block creation and initial state
- **Smart Contract Deployment**:
  - Deploy core Optimism contracts to L1
  - Configure dispute game parameters
  - Set up withdrawal and deposit systems

#### Step 4/6: L2 Chain Startup (~2-4 minutes)
- **L2 Execution Layer (op-geth)**:
  - Initialize L2 genesis state
  - Start op-geth with L1 connection
  - Configure sequencer parameters
- **L2 Consensus Layer (op-node)**:
  - Start op-node rollup driver
  - Establish L1 data synchronization
  - Begin block production

#### Step 5/6: Core Services Deployment (~2-4 minutes)
- **op-batcher Service**:
  - Start batch submission to L1
  - Configure transaction batching parameters
  - Establish L1 submission intervals
- **op-proposer Service**:
  - Start state root proposal system
  - Configure dispute game creation
  - Set proposal intervals and parameters
- **op-challenger Service** (if enabled):
  - Start dispute game monitoring
  - Initialize fault proof system
  - Configure challenge participation rules

#### Step 6/6: Service Verification (~1-2 minutes)
- **Service Health Checks**: Verify all containers are running
- **RPC Connection Tests**: Test L1, L2, and Rollup RPC endpoints
- **Network Connectivity**: Verify inter-service communication
- **Final Status Report**: Display connection information and management commands

## Advanced Retry Logic

### GRPC Communication Error Handling (Up to 3 attempts)
The deployment includes sophisticated error recovery:

**Error Pattern Detection**:
- `grpc: error while marshaling.*UTF-8`: Communication encoding issues
- `Unexpected error happened reading the stream`: Network connectivity problems
- GRPC connection timeouts and marshaling failures

**Retry Process**:
1. **Attempt 1**: Initial deployment
2. **Error Detection**: Parse logs for specific GRPC error patterns
3. **Cleanup**: Complete enclave removal and cleanup (5-second wait)
4. **Attempt 2**: Full re-deployment with fresh environment
5. **Final Attempt**: If needed, attempt 3 with extended waiting periods

**Non-Retriable Errors**: Configuration errors, missing files, and permission issues bypass retry logic

### Timeout Management (20-minute timeout)
**Intelligent Success Detection**: Even if timeout occurs, check for success indicators:
- `"L1 Chain has started"`: L1 blockchain operational
- `"L1 Chain is starting up"`: L1 initialization in progress
- `"RUNNING.*cl-1-lighthouse-geth"`: Consensus layer active
- `"RUNNING.*el-1-geth-lighthouse"`: Execution layer active

**Exit Code Analysis**:
- `0`: Complete success
- `124`: Timeout, but check for partial success in logs
- Other codes: Check logs for success indicators before failing

### 6. **서비스 상태 검증** (Service Verification)
- Wait 60 seconds for stabilization
- Verify L1/L2 chain services
- Check core L2 service status

### 7. **RPC 연결 테스트** (RPC Connection Testing)
- Extract L1/L2 RPC endpoint ports
- Test HTTP JSON-RPC connections
- Retry up to 12 times each (60 seconds total)

### 8. **완료 메시지 출력** (Completion Message)
- Display connection information (L1/L2/Rollup RPC ports)
- Provide management commands guide
- Show next steps instructions (`run-challenger-devnet.sh`)

## Key Features

### Docker Image Building
- Builds all required services: op-node, op-batcher, op-proposer, op-faucet, op-challenger, op-deployer
- Handles Git commit information for reproducible builds
- Provides detailed build progress and error reporting

### Devnet Deployment
- Uses `simple.yaml` configuration (includes RAT settings)
- Deploys via `optimism-package-trampoline`
- Includes retry logic for GRPC communication issues
- 10-minute timeout with intelligent success detection

### Service Verification
- Verifies L1/L2 chain services are running
- Tests RPC connections (L1, L2, Rollup RPC)
- Provides connection information and management commands

### Error Recovery
- Automatic cleanup of failed deployments
- Detailed logging to `/tmp/devnet-build.log`
- Pre-deployment safety checks

## Technical Details

- **Total Duration**: 5-15 minutes (depending on cache status)
- **Retry Logic**: Automatic recovery from GRPC communication errors
- **Detailed Logging**: Step-by-step progress tracking and error reporting
- **Flexible Configuration**: Supports various modes via game_type parameter

## Game Types

- `0` - CANNON: Complete fault proof (requires cannon binaries)
- `1` - PERMISSIONED: Fast development/testing (default)
- `2` - ASTERISC: Asterisc VM (requires asterisc binaries)

## Usage Examples

```bash
# Build with default game type (PERMISSIONED)
./build-devnet.sh

# Build with CANNON game type
./build-devnet.sh --game-type=0

# Build with verbose output
./build-devnet.sh --verbose
```

## Management Commands

After successful deployment:

```bash
# Check devnet status
kurtosis enclave inspect simple-devnet

# Stop devnet
kurtosis enclave rm --force simple-devnet

# View logs
kurtosis enclave logs simple-devnet
cat /tmp/devnet-build.log
```

---

## RAT Deployment Implementation Progress (2025-09-24)

### 현재 상태 (Current Status)
**Status**: Step 3/6에서 중단 - L1 Chain & Contract Deployment 단계에서 op-deployer가 스마트 컨트랙트 배포를 시작하지 않음

### 완료된 작업 (Completed Tasks)
1. ✅ **RAT 구성 설정 완료** - `simple-processed.yaml`에 RAT 파라미터 설정
   - `minimumStakingBalance: "1000000000000000000"` (1 ETH)
   - `perTestBondAmount: "100000000000000"` (0.0001 ETH)
   - `ratTriggerProbability: "100000"` (100%)
   - `deployRAT: true`

2. ✅ **JSON 직렬화 타입 변환 문제 해결**
   - `op-deployer/pkg/deployer/opcm/opchain.go:47-53` - RAT 필드를 `*hexutil.Big`에서 `*big.Int`로 변경
   - `op-deployer/pkg/deployer/state/deploy_config.go:41-60` - `preprocessRATOverrides()` 함수 추가하여 문자열을 *big.Int로 변환

3. ✅ **Docker 이미지 빌드 성공** (7/7 서비스)
   - op-node, op-batcher, op-proposer, op-faucet, op-challenger, op-deployer 모두 성공

4. ✅ **아티팩트 생성 및 업로드**
   - l1-artifacts (384M), l2-artifacts (385M) 생성 완료
   - trampoline 패키지에 artifact upload 로직 통합

5. ✅ **trampoline 패키지 설정 완료**
   - `kurtosis-devnet/optimism-package-trampoline/main.star` - `github.com/tokamak-network/optimism-package` 사용하도록 수정
   - `kurtosis-devnet/optimism-package-trampoline/kurtosis.yml` - 의존성 추가

### 발견된 문제점 (Identified Issues)

#### 1. **Step 3/6에서 배포 중단**
- **위치**: L1 Chain & Contract Deployment 단계
- **증상**: op-deployer-apply 서비스가 L1 데이터베이스 초기화 후 멈춤
- **로그**: `"State snapshot generator is not found"`, `"Initialized path database"` 후 무응답

#### 2. **아티팩트 누락 에러 재발**
```
Error while validating instruction get_files_artifact(name="l1-artifacts")
Caused by: Files artifact 'l1-artifacts' required by 'get_files_artifact' instruction doesn't exist
```

#### 3. **Multiple 백그라운드 프로세스**
- 16개의 백그라운드 build-devnet.sh 및 kurtosis run 프로세스가 병렬 실행 중
- 리소스 경합 및 엔클레이브 충돌 가능성

### 수행된 디버깅 (Debugging Performed)

1. **op-deployer 컨테이너 검사**
   ```bash
   kurtosis service exec simple-devnet op-deployer-apply "ps aux"
   # 결과: 실제 배포 프로세스 없음, tail 프로세스만 실행 중
   ```

2. **서비스 상태 확인**
   ```bash
   kurtosis enclave inspect simple-devnet
   # 결과: L1 체인(Geth+Teku) 정상 실행, op-deployer-apply RUNNING 상태이지만 비활성
   ```

3. **패키지 의존성 문제 확인**
   - `github.com/tokamak-network/optimism-package` vs `github.com/ethpandaops/optimism-package` 불일치 해결

### 다음 단계 (Next Steps)

#### 즉시 수행 필요
1. **모든 백그라운드 프로세스 정리**
   ```bash
   pkill -f "op-challenger/scripts/build-devnet.sh"
   pkill -f "kurtosis run"
   kurtosis enclave rm --force simple-devnet
   ```

2. **단일 인스턴스로 재시작**
   ```bash
   cd /Users/zena/tokamak-projects/optimism
   ./op-challenger/scripts/build-devnet.sh --skip-build --game-type=0
   ```

#### 근본 원인 조사 필요
1. **op-deployer 배포 로직 확인**
   - op-deployer apply 명령어가 실제로 실행되는지 확인
   - L1 RPC 연결 상태 및 스마트 컨트랙트 배포 프로세스 디버깅

2. **아티팩트 업로드 검증**
   - trampoline 패키지의 artifact upload가 올바르게 작동하는지 확인
   - kurtosis 내에서 l1-artifacts, l2-artifacts 접근 가능성 검증

3. **RAT 관련 배포 스크립트 점검**
   - tokamak-network/optimism-package의 RAT 배포 로직 확인
   - RAT 파라미터가 올바르게 전달되는지 검증

### 파일 변경 이력 (File Changes)
- `op-deployer/pkg/deployer/opcm/opchain.go` - RAT 필드 타입 변경
- `op-deployer/pkg/deployer/state/deploy_config.go` - 문자열 변환 함수 추가
- `kurtosis-devnet/optimism-package-trampoline/main.star` - 패키지 참조 수정
- `kurtosis-devnet/optimism-package-trampoline/kurtosis.yml` - 의존성 추가
- `kurtosis-devnet/simple-processed.yaml` - RAT 구성 파라미터 설정

### 예상 해결 시간
- **즉시 정리 작업**: 5분
- **단일 재시작 및 모니터링**: 15-20분
- **근본 원인 해결**: 추가 조사 필요

**마지막 업데이트**: 2025-09-24 22:20 KST