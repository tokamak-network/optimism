#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:51618}"

# Allow explicit override via --addr-file or ADDR_FILE env
ADDR_FILE="${ADDR_FILE:-}"
if [[ ${1:-} == "--addr-file" && ${2:-} ]]; then
  ADDR_FILE="$2"
  shift 2
fi

# Auto-detect common locations if not provided
if [[ -z "${ADDR_FILE}" ]]; then
  for f in ".devnet/addresses.json" "/tmp/devnet-desc/env.json" "packages/contracts-bedrock/deployments/31337-deploy.json"; do
    if [[ -f "$f" ]]; then ADDR_FILE="$f"; break; fi
  done
fi

if [[ -z "${ADDR_FILE}" ]]; then
  echo "addresses file not found. Provide --addr-file /path/to/file.json or set ADDR_FILE." 1>&2
  exit 1
fi

# Robustly find AnchorStateRegistryProxy anywhere in the JSON
ANCHOR_STATE_REGISTRY=$(jq -r '.. | objects | .AnchorStateRegistryProxy? // empty' "$ADDR_FILE" | head -n1)
if [[ -z "${ANCHOR_STATE_REGISTRY}" || "${ANCHOR_STATE_REGISTRY}" == "null" ]]; then
  echo "AnchorStateRegistryProxy not found in $ADDR_FILE" 1>&2
  exit 1
fi

CURRENT_ANCHOR=$(cast call "$ANCHOR_STATE_REGISTRY" "getAnchorRoot()" --rpc-url "$RPC_URL")
CURRENT_ROOT=$(echo "$CURRENT_ANCHOR" | cut -c1-66)

if [[ "$CURRENT_ROOT" == "0xdead000000000000000000000000000000000000000000000000000000000000" ]]; then
  echo "⚠️  AnchorStateRegistry is using default 0xdead value!"
else
  echo "✅ AnchorStateRegistry already has a valid anchor state"
fi
