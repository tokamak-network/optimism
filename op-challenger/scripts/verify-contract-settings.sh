#!/bin/bash

# 4단계: 컨트랙트 설정 검증 스크립트
# Usage: ./verify-contract-settings.sh [enclave_name]
# Default enclave: simple-devnet

set -e

ENCLAVE_NAME=${1:-simple-devnet}
TEMP_DIR="/tmp/devnet-desc"

echo "🚀 컨트랙트 설정 검증 시작 (Enclave: $ENCLAVE_NAME)"
echo "=================================================="

# 환경 파일 다운로드
echo "📥 환경 파일 다운로드..."
rm -rf $TEMP_DIR
kurtosis files download $ENCLAVE_NAME devnet-descriptor-0 $TEMP_DIR

if [ ! -f "$TEMP_DIR/env.json" ]; then
    echo "❌ 오류: env.json 파일을 찾을 수 없습니다!"
    exit 1
fi

# RPC 및 컨트랙트 주소 추출
echo "🔍 RPC 및 컨트랙트 주소 추출..."

# jq가 설치되어 있는지 확인
if ! command -v jq &> /dev/null; then
    echo "❌ 오류: jq가 설치되어 있지 않습니다. 'brew install jq' 명령으로 설치하세요."
    exit 1
fi

# L1 RPC 추출
L1_RPC_PORT=$(jq -r '.l1.nodes[0].services.el.endpoints.rpc.port' $TEMP_DIR/env.json)
L1_RPC="http://127.0.0.1:${L1_RPC_PORT}"

# OptimismPortal 주소 추출
OP_PORTAL=$(jq -r '.l2[0].l1_addresses.OptimismPortalProxy' $TEMP_DIR/env.json)

# OPContractsManager는 선택사항
OPCM_ADDRESS=$(jq -r '.l1.addresses.OpcmImpl // empty' $TEMP_DIR/env.json 2>/dev/null || echo "")

# 기본 컨트랙트 설정 검증
echo ""
echo "🔍 기본 컨트랙트 설정 검증"
echo "L1 RPC: $L1_RPC"
echo "OptimismPortal: $OP_PORTAL"
echo "OPContractsManager: $OPCM_ADDRESS"

if [ -z "$L1_RPC" ] || [ -z "$OP_PORTAL" ]; then
    echo "❌ 오류: 필수 주소를 추출할 수 없습니다!"
    exit 1
fi

# L1 RPC 연결 테스트
echo ""
echo "🌐 L1 RPC 연결 테스트..."
if ! curl -s "$L1_RPC" >/dev/null; then
    echo "❌ 오류: L1 RPC에 연결할 수 없습니다!"
    exit 1
fi
echo "✅ L1 RPC 연결 성공"

# 4.1 OptimismPortal 설정 확인
echo ""
echo "🎯 OptimismPortal 설정 확인"
RESPECTED_GAME_TYPE=$(cast call $OP_PORTAL "respectedGameType()(uint32)" --rpc-url $L1_RPC)
echo "   respectedGameType: $RESPECTED_GAME_TYPE"

# DisputeGameFactory에서 실제 게임 확인
DISPUTE_GAME_FACTORY=$(jq -r '.l2[0].l1_addresses.DisputeGameFactoryProxy' $TEMP_DIR/env.json)
GAME_COUNT=$(cast call $DISPUTE_GAME_FACTORY "gameCount()(uint256)" --rpc-url $L1_RPC 2>/dev/null || echo "0")

echo "   DisputeGameFactory: $DISPUTE_GAME_FACTORY"
echo "   생성된 게임 수: $GAME_COUNT"

if [ "$GAME_COUNT" != "0" ]; then
    # 최신 게임의 타입 확인
    LATEST_GAME_INDEX=$((GAME_COUNT - 1))
    LATEST_GAME_INFO=$(cast call $DISPUTE_GAME_FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $LATEST_GAME_INDEX --rpc-url $L1_RPC)
    ACTUAL_GAME_TYPE=$(echo "$LATEST_GAME_INFO" | head -1)
    LATEST_GAME_ADDR=$(echo "$LATEST_GAME_INFO" | tail -1)

    echo "   최신 게임 타입: $ACTUAL_GAME_TYPE (기대: 0 = CANNON)"
    echo "   최신 게임 주소: $LATEST_GAME_ADDR"

    if [ "$ACTUAL_GAME_TYPE" = "0" ]; then
        echo "✅ 실제 생성된 게임이 CANNON 타입입니다"
    else
        echo "❌ 오류: 실제 생성된 게임이 CANNON 타입이 아닙니다!"
        VERIFICATION_FAILED=true
    fi
else
    echo "⚠️  경고: 아직 게임이 생성되지 않았습니다"
fi

# 4.2 컨트랙트 버전 확인 (선택사항 - OPCM_ADDRESS가 있는 경우만)
if [ -n "$OPCM_ADDRESS" ] && [ "$OPCM_ADDRESS" != "null" ]; then
    echo ""
    echo "🏷️  컨트랙트 버전 확인"
    DEPLOYMENT_VERSION=$(cast call $OPCM_ADDRESS "getDeploymentVersion()(string)" --rpc-url $L1_RPC 2>/dev/null || echo "N/A")
    echo "   배포 버전: $DEPLOYMENT_VERSION"

    if [[ "$DEPLOYMENT_VERSION" == *"fixed-disputeGameType"* ]]; then
        echo "✅ 컨트랙트 버전 검증 통과"
    else
        echo "⚠️  경고: 컨트랙트 버전을 확인할 수 없거나 예상과 다릅니다"
    fi
fi

# 4.3 Dispute Game 타이밍 설정 확인
if [ -n "$LATEST_GAME_ADDR" ]; then
    echo ""
    echo "⏰ Dispute Game 타이밍 설정 확인"
    MAX_CLOCK_DURATION=$(cast call $LATEST_GAME_ADDR "maxClockDuration() returns (uint64)" --rpc-url $L1_RPC 2>/dev/null || echo "0")
    CLOCK_EXTENSION=$(cast call $LATEST_GAME_ADDR "clockExtension() returns (uint64)" --rpc-url $L1_RPC 2>/dev/null || echo "0")
    GAME_STATUS=$(cast call $LATEST_GAME_ADDR "status() returns (uint8)" --rpc-url $L1_RPC 2>/dev/null || echo "N/A")

    echo "   maxClockDuration: ${MAX_CLOCK_DURATION}초 (예상: 1200 = 20분)"
    echo "   clockExtension: ${CLOCK_EXTENSION}초 (예상: 300 = 5분)"
    echo "   게임 상태: $GAME_STATUS (0=IN_PROGRESS, 1=CHALLENGER_WINS, 2=DEFENDER_WINS)"

    # 검증
    if [ "$MAX_CLOCK_DURATION" = "1200" ] && [ "$CLOCK_EXTENSION" = "300" ]; then
        echo "✅ Dispute Game 타이밍 설정 검증 통과"
    else
        echo "❌ 오류: Dispute Game 타이밍 설정이 올바르지 않습니다!"
        echo "   설정된 값 - maxClockDuration: $MAX_CLOCK_DURATION, clockExtension: $CLOCK_EXTENSION"
        echo "   예상 값 - maxClockDuration: 1200, clockExtension: 300"
        VERIFICATION_FAILED=true
    fi
elif [ "$GAME_COUNT" = "0" ]; then
    echo ""
    echo "⚠️  경고: 아직 dispute game이 생성되지 않았습니다"
    echo "   10분 proposal_interval이므로 시간이 좀 더 필요할 수 있습니다"
fi

# 계정 잔고 확인
echo ""
echo "💰 테스트 계정 잔고 확인"

# 주요 테스트 계정들
ACCOUNTS=(
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"  # Account 0
    "0x70997970C51812dc3A010C7d01b50e0d17dc79c8"  # Account 1
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"  # Account 2
)

# 잔고 확인
MAX_BALANCE=0
SELECTED_ACCOUNT=""
HAS_FUNDED_ACCOUNT=false

for i in "${!ACCOUNTS[@]}"; do
    ACCOUNT=${ACCOUNTS[$i]}
    BALANCE=$(cast balance $ACCOUNT --rpc-url $L1_RPC 2>/dev/null || echo "0")
    BALANCE_ETH=$(cast --to-unit $BALANCE ether 2>/dev/null || echo "0")

    echo "   계정 $i ($ACCOUNT): ${BALANCE_ETH} ETH"

    # 0이 아닌 잔고가 있는지 확인
    if [ "$BALANCE" != "0" ]; then
        HAS_FUNDED_ACCOUNT=true
        if [ $(echo "$BALANCE > $MAX_BALANCE" | bc -l 2>/dev/null || echo "0") = "1" ]; then
            MAX_BALANCE=$BALANCE
            SELECTED_ACCOUNT=$ACCOUNT
        fi
    fi
done

if [ "$HAS_FUNDED_ACCOUNT" = "true" ]; then
    echo "✅ 자금이 있는 계정 발견: $SELECTED_ACCOUNT"
    echo "   최대 잔고: $(cast --to-unit $MAX_BALANCE ether) ETH"
else
    echo "❌ 오류: 모든 계정의 잔고가 0입니다!"
    echo "   simple.yaml에 prefunded_accounts 설정을 확인하세요"
    VERIFICATION_FAILED=true
fi

# 최종 결과
echo ""
echo "=================================================="
if [ "$VERIFICATION_FAILED" = "true" ]; then
    echo "❌ 컨트랙트 설정 검증 실패!"
    echo "위의 오류들을 수정한 후 다시 시도하세요."
    exit 1
else
    echo "✅ 컨트랙트 설정 검증 성공!"
    echo "모든 설정이 올바르게 구성되었습니다."
fi