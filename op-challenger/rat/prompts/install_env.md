
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

4. 특정 컨트랙트만 컴파일
forge build src/L1/RAT.sol


