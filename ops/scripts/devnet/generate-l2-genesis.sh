#!/bin/bash
set -euo pipefail

# Generate L2 genesis.json from devnet allocs
# Usage: ./generate-l2-genesis.sh [--allocs-dir <path>] [--output <path>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Default values
ALLOCS_DIR="${REPO_ROOT}/.devnet"
OUTPUT_DIR="${ALLOCS_DIR}"
L1_RPC="http://localhost:8545"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --allocs-dir)
            ALLOCS_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --l1-rpc)
            L1_RPC="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check required files
ALLOCS_L2="${ALLOCS_DIR}/allocs-l2.json"
DEPLOY_CONFIG="${ALLOCS_DIR}/devnetL1.json"
ADDRESSES="${ALLOCS_DIR}/addresses.json"

for file in "$ALLOCS_L2" "$DEPLOY_CONFIG" "$ADDRESSES"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: Required file not found: ${file}"
        echo "Run 'just devnet-allocs' first to generate allocs files."
        exit 1
    fi
done

echo "Generating L2 genesis..."
echo "  Allocs L2: ${ALLOCS_L2}"
echo "  Deploy Config: ${DEPLOY_CONFIG}"
echo "  Addresses: ${ADDRESSES}"
echo "  L1 RPC: ${L1_RPC}"

# Wait for L1 to be ready
echo "Waiting for L1 to be ready..."
for i in {1..30}; do
    if cast block-number --rpc-url "${L1_RPC}" &>/dev/null; then
        echo "L1 is ready!"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "Error: L1 not ready after 30 seconds"
        exit 1
    fi
    sleep 1
done

# Get L1 block info for genesis
L1_BLOCK_NUMBER=$(cast block-number --rpc-url "${L1_RPC}")
L1_BLOCK_HASH=$(cast block "${L1_BLOCK_NUMBER}" --rpc-url "${L1_RPC}" -f hash)
L1_BLOCK_TIMESTAMP=$(cast block "${L1_BLOCK_NUMBER}" --rpc-url "${L1_RPC}" -f timestamp)

echo "L1 Block Info:"
echo "  Number: ${L1_BLOCK_NUMBER}"
echo "  Hash: ${L1_BLOCK_HASH}"
echo "  Timestamp: ${L1_BLOCK_TIMESTAMP}"

# Generate L2 genesis using op-node
OUTPUT_FILE="${OUTPUT_DIR}/genesis-l2.json"
ROLLUP_FILE="${OUTPUT_DIR}/rollup.json"

go run "${REPO_ROOT}/op-node/cmd/main.go" genesis l2 \
    --l1-rpc "${L1_RPC}" \
    --deploy-config "${DEPLOY_CONFIG}" \
    --l1-deployments "${ADDRESSES}" \
    --l2-allocs "${ALLOCS_L2}" \
    --outfile.l2 "${OUTPUT_FILE}" \
    --outfile.rollup "${ROLLUP_FILE}"

echo ""
echo "L2 genesis generated successfully!"
echo "  Genesis: ${OUTPUT_FILE}"
echo "  Rollup config: ${ROLLUP_FILE}"
