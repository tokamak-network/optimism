#!/bin/bash
# create-genesis-pair.sh
# EL과 CL용 동기화된 genesis 파일들을 생성하는 스크립트

set -e

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/genesis-pair"

echo "🔍 프로젝트 루트: $PROJECT_ROOT"
echo "📁 제네시스 출력 디렉토리: $OUTPUT_DIR"

# 디렉토리 생성
mkdir -p "$OUTPUT_DIR"

# 현재 시간을 기반으로 제네시스 생성 (고정된 시간 사용)
CURRENT_TIMESTAMP=$(date +%s)
echo "🕐 현재 타임스탬프: $CURRENT_TIMESTAMP"

# EL용 genesis.json 생성 (NewL1GenesisMinimal 기반)
cat > "$OUTPUT_DIR/genesis.json" <<EOF
{
  "config": {
    "chainId": 31337,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "muirGlacierBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "arrowGlacierBlock": 0,
    "grayGlacierBlock": 0,
    "mergeNetsplitBlock": 0,
    "shanghaiTime": 0,
    "cancunTime": 0,
    "terminalTotalDifficulty": 0
  },
  "nonce": "0x0",
  "timestamp": "0x$(printf '%x' $CURRENT_TIMESTAMP)",
  "gasLimit": "0x1c9c380",
  "difficulty": "0x0",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "number": "0x0",
  "gasUsed": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "baseFeePerGas": "0x3b9aca00",
  "alloc": {
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": {
      "balance": "0x21e19e0c9bab2400000"
    },
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8": {
      "balance": "0x21e19e0c9bab2400000"
    },
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC": {
      "balance": "0x21e19e0c9bab2400000"
    },
    "0x4e59b44847b379578588920cA78FbF26c0B4956C": {
      "balance": "0x0",
      "code": "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3",
      "storage": {},
      "nonce": "0x1"
    }
  }
}
EOF

echo "✅ EL Genesis 생성 완료: $OUTPUT_DIR/genesis.json"

# ethereum-genesis-generator로 동일한 설정의 CL genesis.ssz 생성
echo "🔄 CL용 genesis.ssz 생성 중..."

# config.yaml 생성 (동일한 설정)
cat > "$OUTPUT_DIR/config.yaml" <<EOF
# Ethereum 2.0 Consensus Config
# Same configuration as EL genesis for synchronization

# Network and Fork Configuration
CONFIG_NAME: 'devnet'
PRESET_BASE: 'mainnet'

# Network Identifiers  
DEPOSIT_CHAIN_ID: 31337
DEPOSIT_NETWORK_ID: 31337

# Time parameters (match EL genesis timestamp)
GENESIS_TIME: $CURRENT_TIMESTAMP
GENESIS_DELAY: 0

# Ethereum 1.0 Configuration
DEPOSIT_CONTRACT_ADDRESS: '0x4e59b44847b379578588920cA78FbF26c0B4956C'

# Misc
ETH1_FOLLOW_DISTANCE: 1024
TARGET_AGGREGATORS_PER_COMMITTEE: 16
RANDOM_SUBNETS_PER_VALIDATOR: 1
EPOCHS_PER_RANDOM_SUBNET_SUBSCRIPTION: 256
SECONDS_PER_ETH1_BLOCK: 14
TARGET_COMMITTEE_SIZE: 128
MIN_PER_EPOCH_CHURN_LIMIT: 4
CHURN_LIMIT_QUOTIENT: 65536
SHUFFLE_ROUND_COUNT: 90
MIN_GENESIS_ACTIVE_VALIDATOR_COUNT: 64
MIN_GENESIS_TIME: $CURRENT_TIMESTAMP

# Fork configuration (enable Cancun/Deneb at genesis like EL)
CAPELLA_FORK_VERSION: '0x03000000'  
CAPELLA_FORK_EPOCH: 0
DENEB_FORK_VERSION: '0x04000000'
DENEB_FORK_EPOCH: 0

# Phase 0
GENESIS_FORK_VERSION: '0x00000000'
BLS_WITHDRAWAL_PREFIX: '0x00'

# Altair
ALTAIR_FORK_VERSION: '0x01000000'
ALTAIR_FORK_EPOCH: 0

# Merge
BELLATRIX_FORK_VERSION: '0x02000000'
BELLATRIX_FORK_EPOCH: 0
TERMINAL_TOTAL_DIFFICULTY: 0
TERMINAL_BLOCK_HASH: '0x0000000000000000000000000000000000000000000000000000000000000000'
TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH: 0

# Time parameters
SECONDS_PER_SLOT: 12
SLOTS_PER_EPOCH: 32
EPOCHS_PER_ETH1_VOTING_PERIOD: 64
SLOTS_PER_HISTORICAL_ROOT: 8192
MIN_VALIDATOR_WITHDRAWABILITY_DELAY: 256
SHARD_COMMITTEE_PERIOD: 256
MIN_EPOCHS_TO_INACTIVITY_PENALTY: 4

# State list lengths
EPOCHS_PER_HISTORICAL_VECTOR: 65536
EPOCHS_PER_SLASHINGS_VECTOR: 8192
HISTORICAL_ROOTS_LIMIT: 16777216
VALIDATOR_REGISTRY_LIMIT: 1099511627776

# Reward and penalty quotients
BASE_REWARD_FACTOR: 64
WHISTLEBLOWER_REWARD_QUOTIENT: 512
PROPOSER_REWARD_QUOTIENT: 8
INACTIVITY_PENALTY_QUOTIENT: 67108864
MIN_SLASHING_PENALTY_QUOTIENT: 128
PROPORTIONAL_SLASHING_MULTIPLIER: 1

# Max operations per block
MAX_PROPOSER_SLASHINGS: 16
MAX_ATTESTER_SLASHINGS: 2
MAX_ATTESTATIONS: 128
MAX_DEPOSITS: 16
MAX_VOLUNTARY_EXITS: 16

# Signature domains
DOMAIN_BEACON_PROPOSER: '0x00000000'
DOMAIN_BEACON_ATTESTER: '0x01000000'
DOMAIN_RANDAO: '0x02000000'
DOMAIN_DEPOSIT: '0x03000000'
DOMAIN_VOLUNTARY_EXIT: '0x04000000'
DOMAIN_SELECTION_PROOF: '0x05000000'
DOMAIN_AGGREGATE_AND_PROOF: '0x06000000'
EOF

echo "✅ CL Config 생성 완료: $OUTPUT_DIR/config.yaml"

# mnemonics.yaml 생성 (validator keys)
cat > "$OUTPUT_DIR/mnemonics.yaml" <<EOF
- mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
  count: 64
EOF

echo "✅ Validator keys config 생성 완료: $OUTPUT_DIR/mnemonics.yaml"

# Docker를 사용하여 ethereum-genesis-generator 실행
echo "🔄 ethereum-genesis-generator로 genesis.ssz 생성 중..."

docker run --rm -it \
  -v "$OUTPUT_DIR:/data" \
  ethpandaops/ethereum-genesis-generator:latest \
  all \
  --config-file /data/config.yaml \
  --mnemonics /data/mnemonics.yaml \
  --eth1-config /data/genesis.json \
  --output-dir /data

if [ -f "$OUTPUT_DIR/genesis.ssz" ]; then
    echo "✅ CL Genesis 생성 완료: $OUTPUT_DIR/genesis.ssz"
else
    echo "❌ CL Genesis 생성 실패"
    exit 1
fi

echo ""
echo "🎉 EL과 CL용 동기화된 Genesis 파일 생성 완료!"
echo "📁 생성된 파일들:"
ls -la "$OUTPUT_DIR"/{genesis.json,genesis.ssz,config.yaml}

echo ""
echo "📋 사용 방법:"
echo "1. genesis.json - EL (Geth)용 genesis 파일"  
echo "2. genesis.ssz - CL (Teku)용 genesis 파일"
echo "3. 두 파일은 동일한 설정으로 생성되어 블록 해시가 일치합니다"
echo ""
echo "🔍 생성된 genesis 설정:"
echo "- 체인 ID: 31337"
echo "- 타임스탬프: $CURRENT_TIMESTAMP ($(date -d @$CURRENT_TIMESTAMP 2>/dev/null || date -r $CURRENT_TIMESTAMP 2>/dev/null || echo 'N/A'))"
echo "- 가스 한도: 30,000,000"
echo "- 기본 가스비: 1,000,000,000 wei"
echo "- Terminal Total Difficulty: 0 (Merge 활성화)"
echo "- Cancun/Deneb: Genesis에서 활성화"