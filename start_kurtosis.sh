#!/bin/bash
# ============================================================
# Start Kurtosis (Simple Version - No Custom Genesis)
# ============================================================

set -e

ENCLAVE_NAME="rat-kurtosis"

echo "=============================================="
echo " Starting Kurtosis Enclave"
echo "=============================================="

# Check if already running
if kurtosis enclave inspect $ENCLAVE_NAME > /dev/null 2>&1; then
    echo "⚠️  Enclave '$ENCLAVE_NAME' is already running."
    echo ""
    echo "To restart:"
    echo "  bash cleanup_kurtosis.sh"
    echo "  bash start_kurtosis.sh"
    echo ""
    exit 0
fi

echo "Starting enclave (default config)..."
kurtosis run --enclave $ENCLAVE_NAME github.com/ethpandaops/optimism-package

echo ""
echo "=============================================="
echo " ✅ Kurtosis Started"
echo "=============================================="
echo ""
echo " Next: bash quick_setup.sh"
echo "=============================================="
