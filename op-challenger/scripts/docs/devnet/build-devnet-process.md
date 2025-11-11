# build-devnet.sh Script Internal Process Analysis

**Last Updated**: September 25, 2025
**Version**: 2.0
**Target**: build-devnet.sh debugging and troubleshooting

## Overview

This document provides a detailed analysis of the internal operation process of the `build-devnet.sh` script, helping to identify error points that may occur during deployment and resolve issues.

**Purpose**:
- Identify which stage problems occur when deployment fails
- Compare expected vs actual time for each stage
- Understand specific error patterns like GRPC errors, timeouts
- Diagnose root causes through log analysis

## 🚀 Quick Start

### Basic Deployment (CANNON Game Type)
```bash
cd /Users/zena/tokamak-projects/optimism
./op-challenger/scripts/build-devnet.sh
```

### CANNON Game Type Deployment (Fault Proof System)
```bash
cd /Users/zena/tokamak-projects/optimism
./op-challenger/scripts/build-devnet.sh --game-type=0
```

### Skip Build (Use Already Built Images)
```bash
./op-challenger/scripts/build-devnet.sh --skip-build --game-type=0
```

## 📋 Prerequisites

- **Go**: v1.21 or higher
- **Docker**: Running state
- **Kurtosis**: Latest version (v1.8 or higher)
- **Disk Space**: Minimum 10GB free space

## ⚙️ Detailed Deployment Process

### Stage 1: Initialization and Setup (~10 seconds)
- Parse command line arguments (`--game-type`, `--skip-build`, `--help`)
- Set environment variables and paths
- Clean up existing enclaves
- Initialize build log files

### 2단계: 시스템 요구사항 검사 (~5초)
- Go 버전 확인 (v1.21+ 필요)
- Docker 설치 및 실행 상태 확인
- Kurtosis 설치 확인

### Stage 3: Docker Image Building (~3-5 minutes)
Build Docker images for all required services:
- **op-node**: L2 consensus layer
- **op-batcher**: Transaction batch submission service
- **op-proposer**: State root proposal service
- **op-faucet**: Test token supply service
- **op-challenger**: Dispute game challenger
- **op-deployer**: Smart contract deployment tool

**Skip Build**: Use `--skip-build` option to reuse already built images

### Stage 4: Contract Artifacts Preparation (~30 seconds)
- Copy contract artifacts from forge-artifacts directory
- Create L1/L2 artifacts directories
- Verify critical artifacts (OptimismPortal2, DisputeGameFactory, etc.)
- Create tar files for Kurtosis upload

### Stage 5: Devnet Deployment (~10-15 minutes)

The most complex stage, consisting of 6 detailed sub-stages:

#### 5-1단계: 구성 설정 (~30초)
- **YAML 템플릿 처리**: `simple.yaml`을 `simple-processed.yaml`로 변환
  - Docker 이미지 참조 치환: `{{ localDockerImage "op-node" }}` → `op-node:devnet`
  - 컨트랙트 아티팩트 경로 치환: `{{ localContractArtifacts "l1" }}` → `artifact://l1-artifacts`
  - Fault proof 시스템용 prestate URL 및 해시 설정
- **처리되는 템플릿 변수들**:
  - 모든 서비스의 Docker 이미지 태그
  - 컨트랙트 아티팩트 위치
  - Prestate 파일 경로 및 해시
  - 구성 파라미터

#### 5-2단계: Docker 이미지 준비 (~2-3분)
- **환경 정리**: 충돌 방지를 위한 기존 엔클레이브 제거
- **엔클레이브 준비**: 이전 배포 아티팩트 정리
- **Docker 이미지 검증**: 빌드된 모든 이미지 가용성 확인
- **네트워크 설정**: Kurtosis 네트워킹 환경 준비

#### 5-3단계: L1 체인 & 컨트랙트 배포 (~5-8분) ⚠️ **중요 단계**
- **배포 전 안전성 검사**: `ultra-simple-check.sh` 실행으로 환경 검증
- **Kurtosis 엔클레이브 생성**: 격리된 배포 환경 생성
- **컨트랙트 아티팩트 업로드**:
  - L1 아티팩트 업로드 (OptimismPortal2, DisputeGameFactory, SystemConfig)
  - L2 아티팩트 업로드 (L2OutputOracle, L2CrossDomainMessenger)
- **L1 체인 시작**:
  - 이더리움 실행 레이어 시작 (Geth)
  - 이더리움 합의 레이어 시작 (Lighthouse/Teku)
  - 제네시스 블록 생성 및 초기 상태 설정
- **스마트 컨트랙트 배포**:
  - 핵심 Optimism 컨트랙트를 L1에 배포
  - Dispute game 파라미터 구성
  - 출금 및 입금 시스템 설정

#### 5-4단계: L2 체인 시작 (~2-4분)
- **L2 실행 레이어 (op-geth)**:
  - L2 제네시스 상태 초기화
  - L1 연결과 함께 op-geth 시작
  - 시퀀서 파라미터 구성
- **L2 합의 레이어 (op-node)**:
  - op-node 롤업 드라이버 시작
  - L1 데이터 동기화 설정
  - 블록 생산 시작

#### 5-5단계: 핵심 서비스 배포 (~2-4분)
- **op-batcher 서비스**:
  - L1에 배치 제출 시작
  - 트랜잭션 배치 파라미터 구성
  - L1 제출 간격 설정
- **op-proposer 서비스**:
  - 상태 루트 제안 시스템 시작
  - Dispute game 생성 구성
  - 제안 간격 및 파라미터 설정
- **op-challenger 서비스** (활성화된 경우):
  - Dispute game 모니터링 시작
  - Fault proof 시스템 초기화
  - 챌린지 참여 규칙 구성

#### 5-6단계: 서비스 검증 (~1-2분)
- **서비스 상태 검사**: 모든 컨테이너가 실행 중인지 확인
- **RPC 연결 테스트**: L1, L2, Rollup RPC 엔드포인트 테스트
- **네트워크 연결성**: 서비스 간 통신 확인
- **최종 상태 보고서**: 연결 정보 및 관리 명령어 표시

### 6단계: 서비스 상태 검증 (~1분)
- 60초 대기로 시스템 안정화
- L1/L2 체인 서비스 상태 확인
- 핵심 L2 서비스 상태 검사

### 7단계: RPC 연결 테스트 (~1분)
- L1/L2 RPC 엔드포인트 포트 추출
- HTTP JSON-RPC 연결 테스트
- 각각 최대 12회 재시도 (총 60초)

### 8단계: 완료 메시지 출력
- 연결 정보 표시 (L1/L2/Rollup RPC 포트)
- 관리 명령어 가이드 제공

## ⚙️ 고급 기능

### 자동 재시도 로직 (최대 3회 시도)
배포 과정에서 발생할 수 있는 오류를 자동으로 복구합니다:

**오류 패턴 감지**:
- `grpc: error while marshaling.*UTF-8`: 통신 인코딩 문제
- `Unexpected error happened reading the stream`: 네트워크 연결 문제
- GRPC 연결 타임아웃 및 마샬링 실패

**재시도 과정**:
1. **1차 시도**: 초기 배포 시도
2. **오류 감지**: 로그에서 특정 GRPC 오류 패턴 확인
3. **정리**: 완전한 엔클레이브 제거 및 정리 (5초 대기)
4. **2차 시도**: 새로운 환경에서 전체 재배포
5. **최종 시도**: 필요시 확장된 대기 시간으로 3차 시도

### 타임아웃 관리 (20분 제한)
**지능형 성공 감지**: 타임아웃이 발생해도 성공 지표를 확인합니다:
- `"L1 Chain has started"`: L1 블록체인 작동
- `"L1 Chain is starting up"`: L1 초기화 진행 중
- `"RUNNING.*cl-1-lighthouse-geth"`: 합의 레이어 활성
- `"RUNNING.*el-1-geth-lighthouse"`: 실행 레이어 활성

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

## 📚 Related Documents

- **[Deployment Guide](../README.md)**: User-facing quick deployment guide
- **[Post-deployment Verification Guide](post-deployment-verification-guide.md)**: How to verify configuration after deployment
- **[RAT Development History](rat-development-history.md)**: RAT system development process and resolved issues

---

*This document serves as a technical reference for understanding build-devnet.sh internals and troubleshooting issues.*