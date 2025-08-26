
which forge && forge --version


1. mise 신뢰 설정
mise trust

2. 의존성 설치
mise install

3. 컨트랙 빌드
cd /optimism/packages/contracts-bedrock
forge build


3. go-ffi 빌드 (테스트에 필요)
cd  optimism/packages/contracts-bedrock
cd scripts/go-ffi && go build

4. 컨트랙트 컴파일
cd  optimism/packages/contracts-bedrock
forge build
/// forge build src/L1/RAT.sol

5. 테스트
cd  optimism/packages/contracts-bedrock
forge test

forge test --junit > test-results.xml


//==================================
 forge test 결과를 파일로 저장하는 방법들
1. JUnit XML 형식 (권장)

forge test --junit > test-results.xml

장점: CI/CD 시스템과 호환, 구조화된 데이터
용도: Jenkins, GitHub Actions 등에서 사용

2. 기본 텍스트 출력
forge test > test-results.txt 2>&1
장점: 간단하고 읽기 쉬움
용도: 로그 분석, 디버깅

3. 상세한 요약 포함
forge test --detailed > test-results-detailed.txt 2>&1
장점: 더 자세한 정보 포함
용도: 상세한 분석이 필요할 때

4. 가스 리포트 포함
forge test --gas-report > test-results-with-gas.txt 2>&1

장점: 가스 사용량 정보 포함
용도: 성능 최적화 분석

5. 특정 테스트만 실행
forge test --match-test "testName" > specific-test-results.txt 2>&1
장점: 특정 테스트만 실행하여 빠름
용도: 특정 기능 테스트

6. 실시간 출력과 파일 저장 (tee 사용)
forge test --junit | tee test-results.xml
장점: 화면에도 출력하면서 파일로도 저장
용도: 실시간 모니터링과 저장을 동시에

�� 추천 방법
일반적인 경우: forge test --junit > test-results.xml
디버깅 시: forge test > test-results.txt 2>&1
성능 분석: forge test --gas-report > test-results-with-gas.txt 2>&1
실시간 모니터링: forge test --junit | tee test-results.xml
