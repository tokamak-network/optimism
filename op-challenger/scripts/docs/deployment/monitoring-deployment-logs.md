# Devnet Deployment 로그 모니터링 가이드

devnet 배포 중에는 build-devnet.sh 화면에서 상세한 로그를 볼 수 없습니다. 다음 명령어들을 사용해서 실시간으로 배포 진행상황을 모니터링하세요.

## 🔍 실시간 로그 모니터링

### 1. 개별 서비스 로그 모니터링

```bash
# L1 geth (실행 레이어) 실시간 로그
kurtosis service logs simple-devnet el-1-geth-teku --follow

# L1 consensus layer (teku) 실시간 로그
kurtosis service logs simple-devnet cl-1-teku-geth --follow

# op-deployer contract deployment 로그 (시작된 후)
kurtosis service logs simple-devnet op-deployer-apply --follow

# L2 op-node 로그 (L2 시작된 후)
kurtosis service logs simple-devnet op-kurtosis-op-node --follow

# L2 op-geth 로그 (L2 시작된 후)
kurtosis service logs simple-devnet op-kurtosis-el-1-op-geth-op-node --follow

# op-challenger 로그 (분쟁 해결 서비스)
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow
```


### 2. 모든 서비스 로그 한번에 보기

```bash
# 모든 서비스의 로그를 한번에 실시간으로 보기
kurtosis service logs simple-devnet --follow
```

## 📊 서비스 상태 모니터링

### 1. 현재 실행 중인 서비스 목록 보기

```bash
# 서비스 상태 한번 확인
kurtosis enclave inspect simple-devnet | grep -A 30 "User Services"

# 1초마다 서비스 상태 자동 업데이트
watch -n 1 "kurtosis enclave inspect simple-devnet | grep -A 30 'User Services'"
```

### 2. 특정 서비스 상세 정보

```bash
# 특정 서비스 상세 정보 보기
kurtosis service inspect simple-devnet op-deployer-apply
kurtosis service inspect simple-devnet el-1-geth-teku
```

## 🚨 배포 단계별 모니터링 포인트

### Step 1-2: Docker 이미지 빌드
- build-devnet.sh 화면에서 진행상황 표시됨

### Step 3: L1 체인 시작 (~2-3분)
```bash
# L1 geth가 블록을 생성하는지 확인
kurtosis service logs simple-devnet el-1-geth-teku --follow | grep "Imported new potential chain segment"

# L1 consensus layer가 정상 동작하는지 확인
kurtosis service logs simple-devnet cl-1-teku-geth --follow | grep "Slot Event"
```

### Step 4: Contract Deployment (~3-5분)
```bash
# op-deployer 서비스가 시작되었는지 확인
kurtosis enclave inspect simple-devnet | grep op-deployer-apply

# contract deployment 진행상황 (시작된 후)
kurtosis service logs simple-devnet op-deployer-apply --follow
```

### Step 5: L2 체인 시작 (~2-4분)
```bash
# L2 서비스들이 시작되었는지 확인
kurtosis enclave inspect simple-devnet | grep op-kurtosis

# L2 블록 생성 확인
kurtosis service logs simple-devnet op-kurtosis-el-1-op-geth-op-node --follow | grep "Imported new potential chain segment"
```

### Step 6: 서비스 검증 (~1-2분)
```bash
# challenger 서비스 확인 (정확한 서비스명 사용)
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow

# 모든 서비스 최종 상태 확인
kurtosis enclave inspect simple-devnet
```

## 🎯 Challenger 서비스 전용 모니터링

### 1. Challenger 로그 명령어
```bash
# 기본 로그 확인
kurtosis service logs simple-devnet op-challenger-challenger-2151908

# 실시간 로그 팔로우 (추천)
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow=true

# 최근 100줄만 보기
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --num-log-lines=100

# 실시간 + 제한된 히스토리
kurtosis service logs simple-devnet op-challenger-challenger-2151908 --follow=true --num-log-lines=50
```

### 2. Challenger 로그 패턴 이해
```bash
# 정상 작동 패턴
# t=2025-08-31T13:56:35+0000 lvl=info msg="challenger game service start completed"
# t=2025-08-31T13:57:35+0000 lvl=info msg="Game info" game=0x... claims=1 status="In Progress"

# 동기화 경고 (정상적)
# t=2025-08-31T13:57:24+0000 lvl=warn msg="Local node not sufficiently up to date"

# 에러만 필터링
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep "lvl=error"

# 경고와 에러 필터링
kurtosis service logs simple-devnet op-challenger-challenger-2151908 | grep -E "(lvl=warn|lvl=error)"
```

### 3. Challenger 메트릭스 확인
```bash
# Challenger 메트릭스 엔드포인트 접근
curl http://127.0.0.1:56838/metrics

# Grafana 대시보드에서 Challenger 메트릭스 확인
# URL: http://127.0.0.1:56947
```

### 4. 서비스명 찾기
```bash
# Challenger 서비스명 확인
kurtosis enclave inspect simple-devnet | grep challenger

# 모든 op- 서비스 확인
kurtosis enclave inspect simple-devnet | grep -E "(challenger|batcher|proposer|op-node|op-geth)"
```

## 💡 유용한 팁

### 1. 백그라운드에서 로그 모니터링
```bash
# 새 터미널을 열고 실시간 로그 모니터링
kurtosis service logs simple-devnet el-1-geth-teku --follow &
kurtosis service logs simple-devnet op-deployer-apply --follow &
```

### 2. 로그를 파일로 저장
```bash
# 로그를 파일로 저장하면서 동시에 화면에 출력
kurtosis service logs simple-devnet el-1-geth-teku --follow | tee l1-geth.log
```

### 3. 특정 키워드만 필터링
```bash
# ERROR 로그만 보기
kurtosis service logs simple-devnet op-deployer-apply --follow | grep ERROR

# 블록 생성 로그만 보기
kurtosis service logs simple-devnet el-1-geth-teku --follow | grep "Imported new potential chain segment"
```

## 🔧 문제 해결

### op-deployer 로그가 안 보이는 경우
```bash
# 서비스가 존재하는지 먼저 확인
kurtosis enclave inspect simple-devnet | grep op-deployer

# 서비스가 없다면 L1 체인이 아직 준비 중
kurtosis service logs simple-devnet el-1-geth-teku --follow | grep "Chain head was updated"
```

### 로그 스트림이 끊어지는 경우
```bash
# Ctrl+C로 중단하고 다시 시작
kurtosis service logs simple-devnet [SERVICE_NAME] --follow
```

이 명령어들을 사용하면 devnet 배포 과정을 실시간으로 모니터링할 수 있습니다!