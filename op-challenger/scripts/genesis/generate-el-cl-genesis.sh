#!/bin/bash
# generate-el-cl-genesis.sh
# EL과 동일한 설정으로 CL용 genesis.ssz를 생성하는 스크립트

set -e

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/genesis-sync"

echo "🔍 프로젝트 루트: $PROJECT_ROOT"
echo "📁 제네시스 출력 디렉토리: $OUTPUT_DIR"

# 디렉토리 생성
echo "📁 디렉토리 생성 중..."
mkdir -p "$OUTPUT_DIR"

# 현재 시간을 기반으로 제네시스 생성 (EL과 동일)
CURRENT_TIMESTAMP=$(date +%s)
echo "🕐 현재 타임스탬프: $CURRENT_TIMESTAMP"

# DeployConfig 기반 설정 (simple.yaml과 동일한 값들)
L1_CHAIN_ID=31337
L2_CHAIN_ID=2151908  
L1_GENESIS_GAS_LIMIT=30000000
L1_GENESIS_BASE_FEE="1000000000"  # 1 gwei
L1_GENESIS_DIFFICULTY="0"

echo "⚙️  설정 정보:"
echo "- L1 체인 ID: $L1_CHAIN_ID"
echo "- L2 체인 ID: $L2_CHAIN_ID"
echo "- 가스 한도: $L1_GENESIS_GAS_LIMIT"
echo "- 기본 가스비: $L1_GENESIS_BASE_FEE wei"
echo "- 난이도: $L1_GENESIS_DIFFICULTY"

# 기본 계정 allocs (개발용 계정들)
DEV_ACCOUNTS_JSON=$(cat <<EOF
{
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
EOF
)

# 기본 L1 deployments (placeholder)
L1_DEPLOYMENTS_JSON=$(cat <<EOF
{
  "SystemConfig": "0x4e59b44847b379578588920cA78FbF26c0B4956C",
  "OptimismPortal": "0x4e59b44847b379578588920cA78FbF26c0B4956C",
  "L1StandardBridge": "0x4e59b44847b379578588920cA78FbF26c0B4956C"
}
EOF
)

# Deploy config 생성 (NewL1GenesisMinimal과 동일한 구조)
DEPLOY_CONFIG_JSON=$(cat <<EOF
{
  "l1ChainID": $L1_CHAIN_ID,
  "l2ChainID": $L2_CHAIN_ID,
  "l2GenesisBlockNumber": 0,
  "l2GenesisBlockTimestamp": $CURRENT_TIMESTAMP,
  "l2GenesisBlockGasLimit": $L1_GENESIS_GAS_LIMIT,
  "l2GenesisBlockBaseFeePerGas": "$L1_GENESIS_BASE_FEE",
  "l2GenesisBlockDifficulty": "$L1_GENESIS_DIFFICULTY",
  "l2GenesisBlockNonce": "0",
  "l2GenesisBlockGasUsed": "0",
  "l2GenesisBlockParentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "l2GenesisBlockMixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "l1GenesisBlockTimestamp": $CURRENT_TIMESTAMP,
  "l1GenesisBlockGasLimit": $L1_GENESIS_GAS_LIMIT,
  "l1GenesisBlockBaseFeePerGas": "$L1_GENESIS_BASE_FEE",
  "l1GenesisBlockDifficulty": "$L1_GENESIS_DIFFICULTY",
  "l1CancunTimeOffset": 0,
  "l1PragueTimeOffset": null,
  "fundDevAccounts": true
}
EOF
)

# Go 프로그램으로 genesis 생성 (NewL1GenesisMinimal 로직 구현)
echo "🔄 EL/CL 동기화된 제네시스 생성 중..."

cat > "$OUTPUT_DIR/gen_genesis.go" <<'GOLANG_EOF'
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"math/big"
	"os"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/params"
)

type Config struct {
	L1ChainID                     uint64 `json:"l1ChainID"`
	L2ChainID                     uint64 `json:"l2ChainID"`
	L1GenesisBlockTimestamp       uint64 `json:"l1GenesisBlockTimestamp"`
	L1GenesisBlockGasLimit        uint64 `json:"l1GenesisBlockGasLimit"`
	L1GenesisBlockBaseFeePerGas   string `json:"l1GenesisBlockBaseFeePerGas"`
	L1GenesisBlockDifficulty      string `json:"l1GenesisBlockDifficulty"`
	L1CancunTimeOffset            uint64 `json:"l1CancunTimeOffset"`
	FundDevAccounts               bool   `json:"fundDevAccounts"`
}

func main() {
	if len(os.Args) < 4 {
		log.Fatal("Usage: go run gen_genesis.go <config.json> <allocs.json> <output_dir>")
	}

	configFile := os.Args[1]
	allocsFile := os.Args[2]
	outputDir := os.Args[3]

	// Read config
	configData, err := ioutil.ReadFile(configFile)
	if err != nil {
		log.Fatalf("Failed to read config: %v", err)
	}

	var config Config
	if err := json.Unmarshal(configData, &config); err != nil {
		log.Fatalf("Failed to parse config: %v", err)
	}

	// Read allocs
	allocsData, err := ioutil.ReadFile(allocsFile)
	if err != nil {
		log.Fatalf("Failed to read allocs: %v", err)
	}

	var allocs map[common.Address]types.Account
	if err := json.Unmarshal(allocsData, &allocs); err != nil {
		log.Fatalf("Failed to parse allocs: %v", err)
	}

	// Create L1 genesis (same as NewL1GenesisMinimal)
	chainConfig := params.ChainConfig{
		ChainID:             new(big.Int).SetUint64(config.L1ChainID),
		HomesteadBlock:      big.NewInt(0),
		DAOForkBlock:        nil,
		DAOForkSupport:      false,
		EIP150Block:         big.NewInt(0),
		EIP155Block:         big.NewInt(0),
		EIP158Block:         big.NewInt(0),
		ByzantiumBlock:      big.NewInt(0),
		ConstantinopleBlock: big.NewInt(0),
		PetersburgBlock:     big.NewInt(0),
		IstanbulBlock:       big.NewInt(0),
		MuirGlacierBlock:    big.NewInt(0),
		BerlinBlock:         big.NewInt(0),
		LondonBlock:         big.NewInt(0),
		ArrowGlacierBlock:   big.NewInt(0),
		GrayGlacierBlock:    big.NewInt(0),
		ShanghaiTime:        &[]uint64{0}[0],
		CancunTime:          &[]uint64{0}[0],
		MergeNetsplitBlock:  big.NewInt(0),
		TerminalTotalDifficulty: big.NewInt(0),
	}

	baseFee, _ := new(big.Int).SetString(config.L1GenesisBlockBaseFeePerGas, 10)
	difficulty, _ := new(big.Int).SetString(config.L1GenesisBlockDifficulty, 10)

	genesis := &core.Genesis{
		Config:     &chainConfig,
		Nonce:      0,
		Timestamp:  config.L1GenesisBlockTimestamp,
		GasLimit:   config.L1GenesisBlockGasLimit,
		Difficulty: difficulty,
		Mixhash:    common.Hash{},
		Coinbase:   common.Address{},
		Number:     0,
		GasUsed:    0,
		ParentHash: common.Hash{},
		BaseFee:    baseFee,
		Alloc:      allocs,
	}

	// 블록 생성하여 해시 계산 
	block := genesis.ToBlock()
	fmt.Printf("Generated genesis block hash: %s\n", block.Hash().Hex())

	// JSON genesis 저장
	genesisJSON, err := json.MarshalIndent(genesis, "", "  ")
	if err != nil {
		log.Fatalf("Failed to marshal genesis: %v", err)
	}

	jsonFile := outputDir + "/genesis.json"
	if err := ioutil.WriteFile(jsonFile, genesisJSON, 0644); err != nil {
		log.Fatalf("Failed to write genesis.json: %v", err)
	}
	fmt.Printf("✅ EL Genesis saved to: %s\n", jsonFile)

	// TODO: CL용 SSZ genesis 생성 - 동일한 설정 사용
	fmt.Printf("🔄 CL용 genesis.ssz는 동일한 설정으로 ethereum-genesis-generator에서 생성 필요\n")
}
GOLANG_EOF

# 설정 파일들 저장
echo "$DEPLOY_CONFIG_JSON" > "$OUTPUT_DIR/config.json"
echo "$DEV_ACCOUNTS_JSON" > "$OUTPUT_DIR/allocs.json"

# Genesis 생성 실행
cd "$OUTPUT_DIR"
echo "🔄 Genesis 생성 실행 중..."
go mod init genesis-gen 2>/dev/null || true
go get github.com/ethereum/go-ethereum@latest 2>/dev/null || true

if go run gen_genesis.go config.json allocs.json .; then
    echo ""
    echo "🎉 EL Genesis 생성 완료!"
    echo "📁 생성된 파일들:"
    ls -la "$OUTPUT_DIR"/*.json
    
    echo ""
    echo "📋 사용 방법:"
    echo "1. genesis.json - EL (Geth)용 genesis 파일"  
    echo "2. 이 설정으로 ethereum-genesis-generator를 실행하여 동일한 genesis.ssz 생성 필요"
    echo ""
    echo "🔍 생성된 genesis 설정:"
    echo "- 체인 ID: $L1_CHAIN_ID"
    echo "- 타임스탬프: $CURRENT_TIMESTAMP ($(date -d @$CURRENT_TIMESTAMP))"
    echo "- 가스 한도: $L1_GENESIS_GAS_LIMIT"
    echo "- 기본 가스비: $L1_GENESIS_BASE_FEE wei"
    
else
    echo "❌ Genesis 생성 실패"
    exit 1
fi