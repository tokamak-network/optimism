#!/bin/bash
set -euo pipefail

# Start L1 with devnet allocs
# Usage: ./start-l1.sh [--allocs-dir <path>] [--port <port>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Default values
ALLOCS_DIR="${REPO_ROOT}/.devnet"
L1_PORT=8545
L1_CHAIN_ID=900

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --allocs-dir)
            ALLOCS_DIR="$2"
            shift 2
            ;;
        --port)
            L1_PORT="$2"
            shift 2
            ;;
        --chain-id)
            L1_CHAIN_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if allocs file exists
ALLOCS_FILE="${ALLOCS_DIR}/allocs-l1.json"
if [[ ! -f "$ALLOCS_FILE" ]]; then
    echo "Error: L1 allocs file not found at ${ALLOCS_FILE}"
    echo "Run 'just devnet-allocs' first to generate allocs files."
    exit 1
fi

echo "Starting L1 Anvil with devnet allocs..."
echo "  Allocs: ${ALLOCS_FILE}"
echo "  Port: ${L1_PORT}"
echo "  Chain ID: ${L1_CHAIN_ID}"

# Start Anvil with the allocs file
exec anvil \
    --host 0.0.0.0 \
    --port "${L1_PORT}" \
    --chain-id "${L1_CHAIN_ID}" \
    --block-time 2 \
    --init "${ALLOCS_FILE}" \
    --accounts 10 \
    --balance 10000 \
    --mnemonic "test test test test test test test test test test test junk"
