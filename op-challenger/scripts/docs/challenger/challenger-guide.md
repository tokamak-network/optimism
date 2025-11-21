# OP-Challenger 실행 가이드

## 개요

`run-challenger-devnet.sh` 스크립트는 로컬 devnet 환경에서 OP-Challenger를 실행하는 도구입니다.

## 기본 사용법

```bash
# 1. 먼저 devnet을 시작
./build-devnet.sh

# 2. challenger 실행 (자동 trace-type 감지)
./run-challenger-devnet.sh
```

### Trace Type 선택 옵션

스크립트는 devnet 설정을 자동으로 감지하여 적절한 trace type을 선택합니다:

```bash
# 자동 감지 (권장)
./run-challenger-devnet.sh

# 수동 지정
./run-challenger-devnet.sh permissioned
./run-challenger-devnet.sh cannon

# 명시적 자동 감지
./run-challenger-devnet.sh auto
```

#### Trace Type 별 차이점

**Permissioned 타입:**
- ✅ 빠른 실행 (cannon 바이너리 불필요)
- ✅ 테스트 및 개발에 적합
- ✅ 바이너리 빌드 과정 생략

**Cannon 타입:**
- ✅ 완전한 fault proof 검증
- ✅ cannon, op-program 바이너리 필요
- ✅ prestate 파일 필요 (자동 빌드)

## 자동 Trace Type 감지

스크립트는 devnet의 `respectedGameType` 설정을 자동으로 확인합니다:

```bash
# Devnet 설정 확인
kurtosis files download simple-devnet op-deployer-configs /tmp/
grep "respectedGameType" /tmp/state.json

# 결과:
# "respectedGameType": 0  → cannon 자동 선택
# "respectedGameType": 1  → permissioned 자동 선택
```

### Trace Type별 상세 비교

| 항목 | Permissioned | Cannon |
|------|-------------|---------|
| **실행 속도** | ⚡ 즉시 | 🐌 바이너리 빌드 후 (4-5분) |
| **바이너리 요구사항** | ❌ 없음 | ✅ 3개 파일 필요 |
| **용도** | 🚀 개발/테스트 | 🎯 프로덕션 |
| **검증 수준** | 🧪 기본 | 🔒 완전 검증 |

### 바이너리 요구사항

**Permissioned:**
- ✅ 바이너리 체크 생략
- ✅ 즉시 실행 가능

**Cannon:**
- ✅ `/optimism/cannon/bin/cannon`
- ✅ `/optimism/op-program/bin/op-program` 
- ✅ `/optimism/op-program/bin/prestate-mt64Next.bin.gz`
- 📝 없으면 `./build-binaries-for-challenger.sh` 실행 안내

## 스크립트 기능

### 1. 스마트 환경 검증
- Kurtosis devnet 실행 상태 확인
- OP-Challenger Docker 이미지 존재 확인
- **Trace type별 필수 바이너리 조건부 확인**
  - Permissioned: 바이너리 체크 생략
  - Cannon: cannon, op-program, prestate 파일 확인

### 2. 자동 구성
- **Devnet 설정 기반 trace-type 자동 감지**
- Devnet 포트 정보 자동 추출
- Game Factory 주소 자동 추출
- 컨테이너 상태 관리 (기존 컨테이너 재사용)
- **Trace type별 최적화된 파라미터 적용**

### 3. 서비스 검증
- RPC 연결 테스트
- 컨테이너 상태 확인

## 관리 명령어

실행 후 다음 명령어들로 관리할 수 있습니다:

```bash
# 상태 확인
docker ps | grep challenger

# 로그 확인
docker logs op-challenger

# 실시간 로그 모니터링
docker logs -f op-challenger

# 중지
docker stop op-challenger

# 제거
docker rm op-challenger

# 데이터 볼륨 확인
docker volume ls | grep challenger
```

## 개발 팁

1. **로그 모니터링**: 개발 중에는 `docker logs -f op-challenger`로 실시간 로그를 확인하세요.

2. **설정 변경**: 파라미터를 변경하려면 스크립트를 수정하거나 컨테이너를 제거하고 다시 실행하세요.

3. **데이터 초기화**: 완전히 초기화하려면 `docker rm op-challenger && docker volume rm challenger-data`를 실행하세요.

4. **성능 모니터링**: `docker stats op-challenger`로 리소스 사용량을 모니터링할 수 있습니다.

## 관련 문서

- [Challenger Parameters](./challenger-parameters.md)
- [트러블슈팅 가이드](./troubleshooting.md)