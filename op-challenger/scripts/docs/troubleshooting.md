# 트러블슈팅 가이드

## 일반적인 문제들

### 1. Devnet이 실행되지 않음

**에러 메시지:**
```
[ERROR] Devnet is not running.
[INFO] Please start Devnet first:
[INFO]   ./build-devnet.sh
```

**해결방법:**
```bash
./build-devnet.sh  # devnet을 먼저 시작
```

### 2. Docker 이미지가 없음

**에러 메시지:**
```
[ERROR] op-challenger Docker image not found.
```

**해결방법:**
```bash
./build-devnet.sh  # 이미지를 다시 빌드
```

### 3. 바이너리 파일이 없음

**에러 메시지:**
```
[ERROR] Cannon binary not found: /path/to/cannon/bin/cannon
[ERROR] op-program binary not found: /path/to/op-program/bin/op-program
```

**해결방법:**
```bash
# cannon 빌드
cd $OPTIMISM_ROOT/cannon && make cannon

# op-program 빌드
cd $OPTIMISM_ROOT/op-program && make op-program
```

### 4. 포트 충돌

**증상:**
- 컨테이너가 시작되지 않음
- 포트 관련 에러 메시지

**해결방법:**
```bash
# 기존 컨테이너 확인 및 제거
docker ps -a | grep challenger
docker rm -f op-challenger

# 포트 사용 상황 확인
netstat -tulpn | grep :9876
```

### 5. 컨테이너 시작 실패

**해결 단계:**
```bash
# 1. 상세 로그 확인
docker logs op-challenger

# 2. 컨테이너 재시작 시도
docker restart op-challenger

# 3. 완전히 제거 후 재시작
docker rm -f op-challenger
./run-challenger-devnet.sh
```

## 빌드 관련 문제

### 시스템 요구사항 확인

**문제가 발생했을 때 먼저 확인할 것들:**

1. **Docker 서비스 실행 상태**
   ```bash
   docker --version
   docker ps
   ```

2. **Go 버전 확인**
   ```bash
   go version  # 1.23+ 필요
   ```

3. **필수 도구 설치 확인**
   ```bash
   ./install-tools.sh
   ```

4. **빌드 로그 확인**
   ```bash
   cat /tmp/devnet-build.log
   ```

### Kurtosis 관련 문제

**Kurtosis 서비스 재시작:**
```bash
# Kurtosis 엔클레이브 제거
kurtosis enclave rm --force simple-devnet

# 모든 Kurtosis 리소스 정리
kurtosis clean -a

# 다시 시작
./build-devnet.sh
```

## 네트워크 관련 문제

### RPC 연결 실패

**진단:**
```bash
# L1 RPC 테스트
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:53620

# L2 RPC 테스트
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:56781
```

### 포트 정보 확인

**Devnet 포트 정보 조회:**
```bash
kurtosis enclave inspect simple-devnet
```

## 데이터 관련 문제

### 데이터 초기화

**완전한 초기화:**
```bash
# 컨테이너 제거
docker rm -f op-challenger

# 데이터 볼륨 제거
docker volume rm challenger-data

# 다시 시작
./run-challenger-devnet.sh
```

### 디스크 공간 부족

**정리 명령어:**
```bash
# Docker 시스템 정리
docker system prune -af

# 사용하지 않는 볼륨 제거
docker volume prune -f
```

## 로그 분석

### 유용한 로그 명령어

```bash
# 실시간 로그 모니터링
docker logs -f op-challenger

# 최근 100줄 로그
docker logs --tail 100 op-challenger

# 특정 시간대 로그
docker logs --since="2024-01-01T00:00:00" op-challenger

# 에러만 필터링 (간단한 grep 사용)
docker logs op-challenger 2>&1 | grep -i error
```

### 일반적인 로그 패턴

**정상 시작:**
```
INFO [12-01|10:00:00.000] Starting op-challenger
INFO [12-01|10:00:00.001] Connected to L1 RPC
INFO [12-01|10:00:00.002] Connected to L2 RPC
```

**연결 문제:**
```
ERROR [12-01|10:00:00.000] Failed to connect to L1 RPC
ERROR [12-01|10:00:00.001] dial tcp: connection refused
```

## 성능 관련 문제

### 리소스 모니터링

```bash
# 컨테이너 리소스 사용량
docker stats op-challenger

# 시스템 리소스 확인
top -p $(docker inspect --format '{{.State.Pid}}' op-challenger)
```

### 메모리 부족

**증상:**
- 컨테이너가 자동으로 종료됨
- Out of Memory 에러

**해결:**
```bash
# Docker 메모리 제한 확인
docker inspect op-challenger | grep -i memory

# 시스템 메모리 확인
free -h
```

## 추가 도움

문제가 계속 발생하면:

1. **로그 수집**: `docker logs op-challenger > challenger.log`
2. **시스템 정보 수집**: `./check-system.sh`
3. **GitHub Issues**: 문제 보고 및 도움 요청