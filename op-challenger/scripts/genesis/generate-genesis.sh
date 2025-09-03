#!/bin/bash
# generate-genesis.sh
# EL과 동일한 방식으로 제네시스 파일들을 생성하는 스크립트

set -e

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GENESIS_DIR="$PROJECT_ROOT/genesis"

echo "🔍 프로젝트 루트: $PROJECT_ROOT"
echo "📁 제네시스 출력 디렉토리: $GENESIS_DIR"

# 디렉토리 생성
echo "📁 디렉토리 생성 중..."
mkdir -p "$GENESIS_DIR"

# 현재 시간을 기반으로 제네시스 생성 (EL과 동일)
CURRENT_TIMESTAMP=$(date +%s)
echo "🕐 현재 타임스탬프: $CURRENT_TIMESTAMP"

# 기본 설정으로 제네시스 생성 (EL과 동일한 방식)
echo "🔄 L1 제네시스 생성 중 (JSON)..."
op-node genesis l1 \
    --deploy-config <(cat <<EOF
{
  "l1ChainID": 31337,
  "l2ChainID": 2151908,
  "l2GenesisBlockNumber": 0,
  "l2GenesisBlockTimestamp": $CURRENT_TIMESTAMP,
  "l2GenesisBlockGasLimit": 30000000,
  "l2GenesisBlockBaseFeePerGas": "1000000000",
  "l2GenesisBlockDifficulty": "0",
  "l2GenesisBlockNonce": "0",
  "l2GenesisBlockGasUsed": "0",
  "l2GenesisBlockParentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "l2GenesisBlockMixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "l1GenesisBlockTimestamp": $CURRENT_TIMESTAMP,
  "l1GenesisBlockGasLimit": 30000000,
  "l1GenesisBlockBaseFeePerGas": "1000000000",
  "l1GenesisBlockDifficulty": "0"
}
EOF
) \
    --l1-allocs <(cat <<EOF
{
  "0x4e59b44847b379578588920cA78FbF26c0B4956C": {
    "balance": "0x0",
    "code": "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3",
    "storage": {},
    "nonce": "0x1"
  }
}
EOF
) \
    --l1-deployments <(cat <<EOF
{
  "SystemConfig": "0x4e59b44847b379578588920cA78FbF26c0B4956C",
  "OptimismPortal": "0x4e59b44847b379578588920cA78FbF26c0B4956C",
  "L1StandardBridge": "0x4e59b44847b379578588920cA78FbF26c0B4956C"
}
EOF
) \
    --outfile.l1 "$GENESIS_DIR/genesis.json"

echo "✅ L1 제네시스 생성 완료: $GENESIS_DIR/genesis.json"

# CL용 SSZ 제네시스 생성 (동일한 설정으로)
echo "🔄 CL용 SSZ 제네시스 생성 중..."
op-node genesis l1 \
    --deploy-config <(cat <<EOF
{
  "l1ChainID": 31337,
  "l2ChainID": 2151908,
  "l2GenesisBlockNumber": 0,
  "l2GenesisBlockTimestamp": $CURRENT_TIMESTAMP,
  "l2GenesisBlockGasLimit": 30000000,
  "l2GenesisBlockBaseFeePerGas": "1000000000",
  "l2GenesisBlockDifficulty": "0",
  "l2GenesisBlockNonce": "0",
  "l2GenesisBlockGasUsed": "0",
  "l2GenesisBlockParentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "l2GenesisBlockMixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "l1GenesisBlockTimestamp": $CURRENT_TIMESTAMP,
  "l1GenesisBlockGasLimit": 30000000,
  "l1GenesisBlockBaseFeePerGas": "1000000000",
  "l1GenesisBlockDifficulty": "0"
}
EOF
) \
    --l1-allocs <(cat <<EOF
{
  "0x4e59b44847b379578588920cA78FbF26c0B4956C": {
    "balance": "0x0",
    "code": "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3",
    "storage": {},
    "nonce": "0x1"
  }
}
EOF
) \
    --l1-deployments <(cat <<EOF
{
  "SystemConfig": "0x4e59b44847b379578588920cA78FbF26c0B4956C",
  "OptimismPortal": "0x4e59b44847b379578588920cA78FbF26c0B4956C",
  "L1StandardBridge": "0x4e59b44847b379578588920cA78FbF26c0B4956C"
}
EOF
) \
    --outfile.cl "$GENESIS_DIR/genesis.ssz"

echo "✅ CL용 SSZ 제네시스 생성 완료: $GENESIS_DIR/genesis.ssz"

echo ""
echo "🎉 EL과 동일한 방식으로 제네시스 파일 생성 완료!"
echo "📁 생성된 파일들:"
ls -la "$GENESIS_DIR"

echo ""
echo "📋 사용 방법:"
echo "1. genesis/genesis.json - EL (Geth)용"
echo "2. genesis/genesis.ssz - CL (Teku)용"
echo ""
echo "🔍 EL과 동일한 설정:"
echo "- 체인 ID: 31337 (L1), 2151908 (L2)"
echo "- 타임스탬프: $CURRENT_TIMESTAMP (현재 시간)"
echo "- 가스 한도: 30,000,000"
echo "- 기본 가스비: 1,000,000,000 wei"
