#!/bin/bash

# All Dispute Games Status Checker
# Usage: ./check-all-games.sh [enclave_name] [l1_rpc_url]

set -e

ENCLAVE_NAME=${1:-simple-devnet}
L1_RPC=${2}
TEMP_DIR="/tmp/devnet-desc"

echo "🎮 전체 Dispute Games 상태 확인"
echo "==============================="
echo "Enclave: $ENCLAVE_NAME"
echo ""

# Download environment file if L1_RPC not provided
if [[ -z "$L1_RPC" ]]; then
    echo "📥 환경 파일 다운로드..."
    rm -rf $TEMP_DIR
    kurtosis files download $ENCLAVE_NAME devnet-descriptor-0 $TEMP_DIR

    if [ ! -f "$TEMP_DIR/env.json" ]; then
        echo "❌ 오류: env.json 파일을 찾을 수 없습니다!"
        exit 1
    fi

    # Extract L1 RPC
    L1_RPC_PORT=$(jq -r '.l1.nodes[0].services.el.endpoints.rpc.port' $TEMP_DIR/env.json)
    L1_RPC="http://127.0.0.1:${L1_RPC_PORT}"
fi

echo "🌐 L1 RPC: $L1_RPC"
echo ""

# Get DisputeGameFactory address
DISPUTE_GAME_FACTORY=$(jq -r '.l2[0].l1_addresses.DisputeGameFactoryProxy' $TEMP_DIR/env.json 2>/dev/null || echo "")

if [[ -z "$DISPUTE_GAME_FACTORY" ]] || [[ "$DISPUTE_GAME_FACTORY" == "null" ]]; then
    echo "❌ 오류: DisputeGameFactory 주소를 찾을 수 없습니다!"
    exit 1
fi

echo "🏭 DisputeGameFactory: $DISPUTE_GAME_FACTORY"

# Get total game count
GAME_COUNT=$(cast call --rpc-url $L1_RPC $DISPUTE_GAME_FACTORY "gameCount()(uint256)" 2>/dev/null || echo "0")
echo "📊 총 생성된 게임 수: $GAME_COUNT"
echo ""

if [[ "$GAME_COUNT" == "0" ]]; then
    echo "⚠️  아직 생성된 dispute game이 없습니다."
    exit 0
fi

# Show recent games (last 5 or all if less than 5)
SHOW_COUNT=5
if [[ $GAME_COUNT -lt $SHOW_COUNT ]]; then
    SHOW_COUNT=$GAME_COUNT
fi

echo "🕐 최신 $SHOW_COUNT개 게임 상태:"
echo "================================"

for ((i=$((GAME_COUNT-SHOW_COUNT)); i<$GAME_COUNT; i++)); do
    echo ""
    echo "🎯 게임 #$i:"

    # Get game info
    GAME_INFO=$(cast call --rpc-url $L1_RPC $DISPUTE_GAME_FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $i 2>/dev/null || echo "ERROR")

    if [[ "$GAME_INFO" == "ERROR" ]]; then
        echo "   ❌ 게임 정보를 가져올 수 없습니다"
        continue
    fi

    GAME_TYPE=$(echo "$GAME_INFO" | head -1)
    GAME_TIMESTAMP_RAW=$(echo "$GAME_INFO" | sed -n '2p')
    GAME_ADDRESS=$(echo "$GAME_INFO" | tail -1)

    # Parse timestamp
    if [[ "$GAME_TIMESTAMP_RAW" =~ \[.*\] ]]; then
        GAME_TIMESTAMP=$(echo "$GAME_TIMESTAMP_RAW" | awk '{print $1}')
    else
        GAME_TIMESTAMP="$GAME_TIMESTAMP_RAW"
    fi

    if [[ "$GAME_TIMESTAMP" =~ e ]]; then
        GAME_TIMESTAMP=$(printf "%.0f" "$GAME_TIMESTAMP")
    fi

    echo "   📍 주소: $GAME_ADDRESS"
    echo "   🏷️  타입: $GAME_TYPE (0=CANNON)"
    echo "   📅 생성: $(date -r $GAME_TIMESTAMP '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $GAME_TIMESTAMP)"

    # Get game status
    GAME_STATUS=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "status() returns (uint8)" 2>/dev/null || echo "255")
    case $GAME_STATUS in
        0) echo "   🟡 상태: IN_PROGRESS" ;;
        1) echo "   🔴 상태: CHALLENGER_WINS" ;;
        2) echo "   🟢 상태: DEFENDER_WINS" ;;
        *) echo "   ❓ 상태: UNKNOWN ($GAME_STATUS)" ;;
    esac

    # Get claim count
    CLAIM_COUNT=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "claimDataLen() returns (uint256)" 2>/dev/null || echo "N/A")
    echo "   🌳 클레임 수: $CLAIM_COUNT"

    # Get L2 block number
    L2_BLOCK=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "l2BlockNumber() returns (uint256)" 2>/dev/null || echo "N/A")
    echo "   📦 L2 블록: $L2_BLOCK"

    # Calculate age
    CURRENT_TIME=$(date +%s)
    AGE=$((CURRENT_TIME - GAME_TIMESTAMP))
    echo "   ⏰ 경과시간: ${AGE}초 ($(($AGE/60))분)"
done

echo ""
echo "================================"

# Summary statistics
IN_PROGRESS=0
CHALLENGER_WINS=0
DEFENDER_WINS=0
UNKNOWN=0

echo ""
echo "📈 전체 게임 통계:"
for ((i=0; i<$GAME_COUNT; i++)); do
    GAME_INFO=$(cast call --rpc-url $L1_RPC $DISPUTE_GAME_FACTORY "gameAtIndex(uint256)(uint32,uint64,address)" $i 2>/dev/null || echo "ERROR")
    if [[ "$GAME_INFO" != "ERROR" ]]; then
        GAME_ADDRESS=$(echo "$GAME_INFO" | tail -1)
        STATUS=$(cast call --rpc-url $L1_RPC $GAME_ADDRESS "status() returns (uint8)" 2>/dev/null || echo "255")
        case $STATUS in
            0) ((IN_PROGRESS++)) ;;
            1) ((CHALLENGER_WINS++)) ;;
            2) ((DEFENDER_WINS++)) ;;
            *) ((UNKNOWN++)) ;;
        esac
    fi
done

echo "   🟡 진행 중: $IN_PROGRESS"
echo "   🔴 Challenger 승리: $CHALLENGER_WINS"
echo "   🟢 Defender 승리: $DEFENDER_WINS"
echo "   ❓ 알 수 없음: $UNKNOWN"

echo ""
echo "✅ 전체 게임 상태 확인 완료!"