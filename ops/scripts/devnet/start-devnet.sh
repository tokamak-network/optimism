#!/bin/bash
set -euo pipefail

# Start full devnet environment (L1 + L2 + services)
# Usage: ./start-devnet.sh [--allocs-dir <path>] [--data-dir <path>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Default values
ALLOCS_DIR="${REPO_ROOT}/.devnet"
DATA_DIR="${REPO_ROOT}/.devnet/data"
L1_PORT=8545
L2_PORT=9545
L1_CHAIN_ID=900
L2_CHAIN_ID=901

# Test accounts (Hardhat/Foundry default)
DEPLOYER_KEY="ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
BATCHER_KEY="59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
PROPOSER_KEY="5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
SEQUENCER_KEY="8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --allocs-dir)
            ALLOCS_DIR="$2"
            shift 2
            ;;
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        --l1-port)
            L1_PORT="$2"
            shift 2
            ;;
        --l2-port)
            L2_PORT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

L1_RPC="http://localhost:${L1_PORT}"
L2_RPC="http://localhost:${L2_PORT}"

# Check required files
echo "Checking required files..."
for file in "allocs-l1.json" "allocs-l2.json" "devnetL1.json" "addresses.json"; do
    if [[ ! -f "${ALLOCS_DIR}/${file}" ]]; then
        echo "Error: ${file} not found in ${ALLOCS_DIR}"
        echo "Run 'just devnet-allocs' first to generate allocs files."
        exit 1
    fi
done
echo "All required files found!"

# Create data directory
mkdir -p "${DATA_DIR}"

# Generate JWT secret if not exists
JWT_SECRET="${DATA_DIR}/jwt.txt"
if [[ ! -f "${JWT_SECRET}" ]]; then
    openssl rand -hex 32 > "${JWT_SECRET}"
    echo "Generated JWT secret: ${JWT_SECRET}"
fi

# Cleanup function
cleanup() {
    echo ""
    echo "Shutting down devnet..."

    # Kill all background processes
    if [[ -f "${DATA_DIR}/l1.pid" ]]; then
        kill "$(cat "${DATA_DIR}/l1.pid")" 2>/dev/null || true
        rm -f "${DATA_DIR}/l1.pid"
    fi
    if [[ -f "${DATA_DIR}/l2.pid" ]]; then
        kill "$(cat "${DATA_DIR}/l2.pid")" 2>/dev/null || true
        rm -f "${DATA_DIR}/l2.pid"
    fi
    if [[ -f "${DATA_DIR}/op-node.pid" ]]; then
        kill "$(cat "${DATA_DIR}/op-node.pid")" 2>/dev/null || true
        rm -f "${DATA_DIR}/op-node.pid"
    fi
    if [[ -f "${DATA_DIR}/op-batcher.pid" ]]; then
        kill "$(cat "${DATA_DIR}/op-batcher.pid")" 2>/dev/null || true
        rm -f "${DATA_DIR}/op-batcher.pid"
    fi
    if [[ -f "${DATA_DIR}/op-proposer.pid" ]]; then
        kill "$(cat "${DATA_DIR}/op-proposer.pid")" 2>/dev/null || true
        rm -f "${DATA_DIR}/op-proposer.pid"
    fi

    echo "Devnet stopped."
}

trap cleanup EXIT INT TERM

echo ""
echo "========================================="
echo "  Starting Devnet Environment"
echo "========================================="
echo "  L1 RPC: ${L1_RPC}"
echo "  L2 RPC: ${L2_RPC}"
echo "  Allocs: ${ALLOCS_DIR}"
echo "  Data: ${DATA_DIR}"
echo "========================================="
echo ""

# Step 1: Start L1
echo "[1/5] Starting L1 (Anvil)..."
anvil \
    --host 0.0.0.0 \
    --port "${L1_PORT}" \
    --chain-id "${L1_CHAIN_ID}" \
    --block-time 2 \
    --init "${ALLOCS_DIR}/allocs-l1.json" \
    --accounts 10 \
    --balance 10000 \
    --mnemonic "test test test test test test test test test test test junk" \
    > "${DATA_DIR}/l1.log" 2>&1 &
echo $! > "${DATA_DIR}/l1.pid"

# Wait for L1
echo "Waiting for L1 to be ready..."
for i in {1..30}; do
    if cast block-number --rpc-url "${L1_RPC}" &>/dev/null; then
        echo "L1 is ready! (Block: $(cast block-number --rpc-url "${L1_RPC}"))"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "Error: L1 not ready after 30 seconds"
        cat "${DATA_DIR}/l1.log"
        exit 1
    fi
    sleep 1
done

# Step 2: Generate L2 genesis if not exists
GENESIS_L2="${ALLOCS_DIR}/genesis-l2.json"
ROLLUP_CONFIG="${ALLOCS_DIR}/rollup.json"

if [[ ! -f "${GENESIS_L2}" ]] || [[ ! -f "${ROLLUP_CONFIG}" ]]; then
    echo ""
    echo "[2/5] Generating L2 genesis..."
    "${SCRIPT_DIR}/generate-l2-genesis.sh" \
        --allocs-dir "${ALLOCS_DIR}" \
        --l1-rpc "${L1_RPC}"
else
    echo ""
    echo "[2/5] Using existing L2 genesis..."
fi

# Step 3: Start L2 (op-geth)
echo ""
echo "[3/5] Starting L2 (op-geth)..."

# Initialize op-geth if needed
L2_DATA="${DATA_DIR}/l2-geth"
if [[ ! -d "${L2_DATA}/geth" ]]; then
    mkdir -p "${L2_DATA}"

    # Check if op-geth exists
    if ! command -v op-geth &>/dev/null && [[ ! -f "${REPO_ROOT}/op-geth/build/bin/geth" ]]; then
        echo "Warning: op-geth not found. Please install op-geth or build it."
        echo "You can use: go install github.com/ethereum-optimism/op-geth@latest"
        echo ""
        echo "Skipping L2 startup. L1 is running at ${L1_RPC}"
        echo ""
        echo "To continue manually:"
        echo "  1. Install op-geth"
        echo "  2. Initialize: op-geth init --datadir ${L2_DATA} ${GENESIS_L2}"
        echo "  3. Start: op-geth --datadir ${L2_DATA} ..."
        echo ""

        # Keep L1 running
        echo "Press Ctrl+C to stop L1..."
        wait
        exit 0
    fi

    OP_GETH="${REPO_ROOT}/op-geth/build/bin/geth"
    if command -v op-geth &>/dev/null; then
        OP_GETH="op-geth"
    fi

    echo "Initializing op-geth..."
    "${OP_GETH}" init --datadir "${L2_DATA}" "${GENESIS_L2}"
fi

# Get sequencer address from key
SEQUENCER_ADDR=$(cast wallet address --private-key "0x${SEQUENCER_KEY}")

OP_GETH="${REPO_ROOT}/op-geth/build/bin/geth"
if command -v op-geth &>/dev/null; then
    OP_GETH="op-geth"
fi

"${OP_GETH}" \
    --datadir "${L2_DATA}" \
    --http \
    --http.addr 0.0.0.0 \
    --http.port "${L2_PORT}" \
    --http.api "eth,net,web3,debug,txpool,engine" \
    --http.corsdomain "*" \
    --ws \
    --ws.addr 0.0.0.0 \
    --ws.port $((L2_PORT + 1)) \
    --ws.api "eth,net,web3,debug,txpool,engine" \
    --syncmode full \
    --gcmode archive \
    --nodiscover \
    --maxpeers 0 \
    --networkid "${L2_CHAIN_ID}" \
    --authrpc.addr 0.0.0.0 \
    --authrpc.port $((L2_PORT + 2)) \
    --authrpc.vhosts "*" \
    --authrpc.jwtsecret "${DATA_DIR}/jwt.txt" \
    --rollup.disabletxpoolgossip=true \
    --rollup.sequencerhttp "${L2_RPC}" \
    > "${DATA_DIR}/l2.log" 2>&1 &
echo $! > "${DATA_DIR}/l2.pid"

# Wait for L2
echo "Waiting for L2 to be ready..."
for i in {1..30}; do
    if cast block-number --rpc-url "${L2_RPC}" &>/dev/null; then
        echo "L2 is ready! (Block: $(cast block-number --rpc-url "${L2_RPC}"))"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "Warning: L2 not ready after 30 seconds"
        echo "Check ${DATA_DIR}/l2.log for details"
    fi
    sleep 1
done

echo ""
echo "========================================="
echo "  Devnet is running!"
echo "========================================="
echo "  L1 RPC: ${L1_RPC}"
echo "  L2 RPC: ${L2_RPC}"
echo ""
echo "  Logs:"
echo "    L1: ${DATA_DIR}/l1.log"
echo "    L2: ${DATA_DIR}/l2.log"
echo ""
echo "  Addresses: ${ALLOCS_DIR}/addresses.json"
echo "========================================="
echo ""
echo "Press Ctrl+C to stop the devnet..."

# Wait for signals
wait
