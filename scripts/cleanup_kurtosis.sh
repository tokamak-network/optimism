#!/usr/bin/env bash
set -euo pipefail

if ! command -v kurtosis >/dev/null 2>&1; then
  echo "Kurtosis CLI not found; nothing to clean." >&2
  exit 0
fi

echo "Cleaning Kurtosis enclaves and engine..."
kurtosis clean -a || true
kurtosis engine stop || true
echo "Cleanup complete."
