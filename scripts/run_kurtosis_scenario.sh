#!/usr/bin/env bash
set -euo pipefail

AUTO_CLEANUP=${AUTO_CLEANUP:-1}
AUTO_DISCOVER=${AUTO_DISCOVER:-1}
AUTO_DEPLOY_RAT=${AUTO_DEPLOY_RAT:-1}
AUTO_STAKE=${AUTO_STAKE:-1}
AUTO_DISPUTE_NON_INCLUSION=${AUTO_DISPUTE_NON_INCLUSION:-0}
CHEAT_NON_INCLUSION=${CHEAT_NON_INCLUSION:-0}
AUTO_E2E_DISPUTE_CHECKS=${AUTO_E2E_DISPUTE_CHECKS:-1}
PRINT_PROOFS=${PRINT_PROOFS:-0}
PROOF_NODE_LIMIT=${PROOF_NODE_LIMIT:-6}
MESSAGE_PASSER_ADDR=${MESSAGE_PASSER_ADDR:-0x4200000000000000000000000000000000000016}
# Default prefunded key depends on the devnet package; we auto-detect if PRIVATE_KEY is not set.
PREFUNDED_KEY=${PREFUNDED_KEY:-0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31}
ALT_PREFUNDED_KEY=${ALT_PREFUNDED_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
USE_INTEGRATED_DGF=${USE_INTEGRATED_DGF:-1}
VALIDATOR_COUNT=${VALIDATOR_COUNT:-10}
DEVNET_ENV_JSON=${DEVNET_ENV_JSON:-/tmp/devnet-desc/env.json}
DISPUTE_GAME_FACTORY=${DISPUTE_GAME_FACTORY:-}
WAIT_ATTEMPTS=${WAIT_ATTEMPTS:-90}
WAIT_SLEEP=${WAIT_SLEEP:-2}

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing dependency: jq (required for log parsing)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_cleanup_ran=0
cleanup_on_exit() {
  if [[ "${_cleanup_ran}" == "1" ]]; then
    return 0
  fi
  _cleanup_ran=1
  if [[ "${AUTO_CLEANUP}" == "1" ]]; then
    echo ""
    echo "== Cleanup Kurtosis (trap) =="
    "$SCRIPT_DIR/cleanup_kurtosis.sh" || true
  fi
}

# Opt-out friendly: by default we cleanup even on failures.
trap cleanup_on_exit EXIT

parse_hex_result() {
  local raw="$1"
  if [[ "$raw" == 0x* ]]; then
    echo "$raw"
  elif [[ "$raw" == \"0x*\" ]]; then
    echo "${raw//\"/}"
  else
    echo "$raw" | jq -r '.result'
  fi
}

parse_result_object() {
  local raw="$1"
  if [[ "$raw" == \{* ]]; then
    if echo "$raw" | jq -e 'has("result")' >/dev/null 2>&1; then
      echo "$raw" | jq -r '.result'
    else
      echo "$raw"
    fi
  else
    echo "$raw"
  fi
}

bytes32_from_address() {
  local addr="$1"
  addr="${addr#0x}"
  addr="${addr,,}"
  printf "0x%064s" "$addr" | tr ' ' '0'
}

print_proof_summary() {
  local label="$1"
  local addr="$2"
  local proof_obj="$3"

  if [[ "$PRINT_PROOFS" != "1" ]]; then
    return 0
  fi

  echo ""
  echo "---- proof summary: $label ----"
  echo "address: $addr"
  echo "l2_block: $l2_block_hex"
  echo "state_root: $STATE_ROOT"
  echo "nonce: $(echo "$proof_obj" | jq -r '.nonce')"
  echo "balance: $(echo "$proof_obj" | jq -r '.balance')"
  echo "codeHash: $(echo "$proof_obj" | jq -r '.codeHash')"
  echo "storageHash: $(echo "$proof_obj" | jq -r '.storageHash')"
  echo "accountProof nodes: $(echo "$proof_obj" | jq '.accountProof | length')"

  # Print a small preview of the first few proof nodes (length + prefix).
  echo "$proof_obj" | jq -r --argjson n "$PROOF_NODE_LIMIT" '
    .accountProof
    | to_entries
    | .[0:$n][]
    | "  - [\(.key)] len=\((.value|length-2)/2) bytes prefix=\(.value[0:18])..."'
}

get_account_proof_arg() {
  local addr="$1"
  local raw obj inner
  raw=$(cast rpc --rpc-url "$L2_RPC" eth_getProof "$addr" "[]" "$l2_block_hex")
  obj=$(parse_result_object "$raw")
  inner=$(echo "$obj" | jq -r '.accountProof | join(",")')
  if [[ -z "$inner" || "$inner" == "null" ]]; then
    echo "" >&2
    return 1
  fi
  echo "[$inner]"
}

get_account_proof_obj() {
  local addr="$1"
  local raw obj
  raw=$(cast rpc --rpc-url "$L2_RPC" eth_getProof "$addr" "[]" "$l2_block_hex")
  obj=$(parse_result_object "$raw")
  if [[ -z "$obj" || "$obj" == "null" ]]; then
    return 1
  fi
  echo "$obj"
}

send_and_receipt() {
  local rpc="$1"
  local pk="$2"
  shift 2
  local tx_json
  tx_json=$(cast send --json --rpc-url "$rpc" --private-key "$pk" "$@")
  local tx_hash
  tx_hash=$(echo "$tx_json" | jq -r '.transactionHash')
  if [[ -z "$tx_hash" || "$tx_hash" == "null" ]]; then
    echo "$tx_json" >&2
    return 1
  fi
  cast receipt "$tx_hash" --json --rpc-url "$rpc"
}

send_and_wait() {
  local rpc="$1"
  local pk="$2"
  shift 2
  local tx_json
  tx_json=$(cast send --json --rpc-url "$rpc" --private-key "$pk" "$@")
  local tx_hash
  tx_hash=$(echo "$tx_json" | jq -r '.transactionHash')
  if [[ -z "$tx_hash" || "$tx_hash" == "null" ]]; then
    echo "Failed to parse transaction hash." >&2
    echo "$tx_json" >&2
    exit 1
  fi
  local receipt
  receipt=$(cast receipt "$tx_hash" --json --rpc-url "$rpc")
  local status
  status=$(echo "$receipt" | jq -r '.status')
  if [[ "$status" != "0x1" && "$status" != "1" ]]; then
    echo "Transaction failed: $tx_hash" >&2
    echo "$receipt" >&2
    exit 1
  fi
  echo "$tx_hash"
}

wait_for_block_hex() {
  local rpc="$1"
  local label="$2"
  for i in $(seq 1 "$WAIT_ATTEMPTS"); do
    local raw
    raw=$(cast rpc --rpc-url "$rpc" eth_blockNumber 2>/dev/null || true)
    local hex
    hex=$(parse_hex_result "$raw" 2>/dev/null || true)
    if [[ "$hex" == 0x* ]]; then
      echo "$hex"
      return 0
    fi
    echo "Waiting for $label RPC to respond... ($i/$WAIT_ATTEMPTS)"
    sleep "$WAIT_SLEEP"
  done
  echo "Failed to get block number from $label RPC." >&2
  return 1
}

if [[ "$AUTO_DISCOVER" == "1" ]]; then
  if [[ -z "${KURTOSIS_ENCLAVE:-}" ]]; then
    KURTOSIS_ENCLAVE=$(kurtosis enclave ls | awk 'NR>1 {print $1}' | tail -1)
  fi

  if [[ -n "${KURTOSIS_ENCLAVE:-}" ]]; then
    inspect_out=$(kurtosis enclave inspect "$KURTOSIS_ENCLAVE" 2>/dev/null || true)
    if [[ -n "$inspect_out" ]]; then
      if [[ -z "${L1_RPC:-}" ]]; then
        l1_line=$(echo "$inspect_out" | grep -A10 "el-1-geth" | grep "rpc:" | grep -v "engine-rpc" | head -1 || true)
        l1_port=$(echo "$l1_line" | sed -E 's/.*127\.0\.0\.1:([0-9]+).*/\1/' || true)
        if [[ -n "$l1_port" ]]; then
          L1_RPC="http://127.0.0.1:$l1_port"
        fi
      fi

      if [[ -z "${L2_RPC:-}" ]]; then
        l2_line=$(echo "$inspect_out" | grep -A5 "op-el-" | grep -v "engine-rpc" | grep "rpc:" | head -1 || true)
        l2_port=$(echo "$l2_line" | sed -E 's/.*127\.0\.0\.1:([0-9]+).*/\1/' || true)
        if [[ -n "$l2_port" ]]; then
          L2_RPC="http://127.0.0.1:$l2_port"
        fi
      fi
    fi
  fi
fi

if [[ -z "${L1_RPC:-}" || -z "${L2_RPC:-}" ]]; then
  echo "Missing required RPCs. Set L1_RPC/L2_RPC or enable AUTO_DISCOVER with a running Kurtosis enclave." >&2
  exit 1
fi

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  pick_key() {
    local pk="$1"
    local addr bal
    addr=$(cast wallet address --private-key "$pk" 2>/dev/null || true)
    if [[ -z "${addr:-}" ]]; then
      return 1
    fi
    bal=$(cast balance "$addr" --rpc-url "$L1_RPC" 2>/dev/null || echo "0")
    # Require at least 1 ETH.
    if [[ "$bal" != "0" && "$bal" != "0.0" && "$bal" != "0 ETH" ]]; then
      echo "$pk"
      return 0
    fi
    return 1
  }

  if picked=$(pick_key "$PREFUNDED_KEY"); then
    PRIVATE_KEY="$picked"
  elif picked=$(pick_key "$ALT_PREFUNDED_KEY"); then
    PRIVATE_KEY="$picked"
  else
    echo "PRIVATE_KEY not set and could not auto-detect a funded prefunded key." >&2
    echo "Set PRIVATE_KEY explicitly (must be funded on L1)." >&2
    exit 1
  fi
  echo "PRIVATE_KEY not set; auto-selected a funded prefunded key."
fi

deployer_addr=$(cast wallet address --private-key "$PRIVATE_KEY")
deployer_addr="${deployer_addr,,}"
if [[ -z "${GAME_ADDR:-}" ]]; then
  GAME_ADDR="$deployer_addr"
fi

# Discover DisputeGameFactoryProxy from devnet descriptor if available.
if [[ -z "${DISPUTE_GAME_FACTORY:-}" && -f "$DEVNET_ENV_JSON" ]]; then
  dgf=$(jq -r '.DisputeGameFactoryProxy // empty' "$DEVNET_ENV_JSON" 2>/dev/null || true)
  if [[ -n "${dgf:-}" && "$dgf" != "null" ]]; then
    DISPUTE_GAME_FACTORY="$dgf"
  fi
fi

# Fallback: discover DisputeGameFactoryProxy from the enclave's op-deployer-configs artifact.
if [[ -z "${DISPUTE_GAME_FACTORY:-}" && -n "${KURTOSIS_ENCLAVE:-}" ]]; then
  tmp_dir="/tmp/rat-e2e/${KURTOSIS_ENCLAVE}"
  mkdir -p "$tmp_dir" || true
  if kurtosis files download "$KURTOSIS_ENCLAVE" op-deployer-configs "$tmp_dir/op-deployer-configs" >/dev/null 2>&1; then
    dgf=$(grep -o '"DisputeGameFactoryProxy": *"[^"]*"' "$tmp_dir/op-deployer-configs/state.json" 2>/dev/null | head -1 | cut -d'"' -f4)
    if [[ -n "${dgf:-}" ]]; then
      DISPUTE_GAME_FACTORY="$dgf"
    fi
  fi
fi

if [[ -z "${L2_BLOCK:-}" ]]; then
  l2_block_hex=$(wait_for_block_hex "$L2_RPC" "L2")
  L2_BLOCK=$(cast to-dec "$l2_block_hex")
else
  l2_block_hex=$(cast to-hex "$L2_BLOCK")
fi

block_json=""
for i in $(seq 1 "$WAIT_ATTEMPTS"); do
  block_raw=$(cast rpc --rpc-url "$L2_RPC" eth_getBlockByNumber "$l2_block_hex" false 2>/dev/null || true)
  block_json=$(parse_result_object "$block_raw" 2>/dev/null || true)
  if [[ "$block_json" != "null" && -n "$block_json" ]]; then
    break
  fi
  echo "Waiting for L2 block data... ($i/$WAIT_ATTEMPTS)"
  sleep "$WAIT_SLEEP"
done
if [[ "$block_json" == "null" || -z "$block_json" ]]; then
  echo "Failed to fetch L2 block data." >&2
  exit 1
fi
state_root=$(echo "$block_json" | jq -r '.stateRoot')
block_hash=$(echo "$block_json" | jq -r '.hash')

proof_json=""
for i in $(seq 1 "$WAIT_ATTEMPTS"); do
  proof_raw=$(cast rpc --rpc-url "$L2_RPC" eth_getProof "$MESSAGE_PASSER_ADDR" "[]" "$l2_block_hex" 2>/dev/null || true)
  proof_json=$(parse_result_object "$proof_raw" 2>/dev/null || true)
  if [[ "$proof_json" != "null" && -n "$proof_json" ]]; then
    break
  fi
  echo "Waiting for L2 proof data... ($i/$WAIT_ATTEMPTS)"
  sleep "$WAIT_SLEEP"
done
if [[ "$proof_json" == "null" || -z "$proof_json" ]]; then
  echo "Failed to fetch L2 proof data." >&2
  exit 1
fi
message_passer_root=$(echo "$proof_json" | jq -r '.storageHash')
version="0x0000000000000000000000000000000000000000000000000000000000000000"
encoded=$(cast abi-encode "f(bytes32,bytes32,bytes32,bytes32)" "$version" "$state_root" "$message_passer_root" "$block_hash")
computed_output_root=$(cast keccak "$encoded")
OUTPUT_ROOT=${OUTPUT_ROOT:-$computed_output_root}
STATE_ROOT="$state_root"
MESSAGE_PASSER_ROOT="$message_passer_root"
BLOCK_HASH="$block_hash"

if [[ -z "${RAT_ADDR:-}" && "$AUTO_DEPLOY_RAT" == "1" ]]; then
  echo "== Deploy RAT (DeployRAT.s.sol) =="
  pushd packages/contracts-bedrock >/dev/null
  if [[ "$USE_INTEGRATED_DGF" == "1" && -z "${DISPUTE_GAME_FACTORY:-}" ]]; then
    echo "Missing DISPUTE_GAME_FACTORY. Set DISPUTE_GAME_FACTORY or provide $DEVNET_ENV_JSON." >&2
    exit 1
  fi
  # Deploy RAT initialized against the real DisputeGameFactory when using the integrated path.
  # Default trigger probability is set to 50% at deploy time; we override to 100% below for deterministic checks.
  if [[ "$USE_INTEGRATED_DGF" == "1" ]]; then
    deploy_out=$(RAT_FACTORY="$DISPUTE_GAME_FACTORY" forge script scripts/DeployRAT.s.sol:DeployRAT \
      --broadcast --rpc-url "$L1_RPC" --private-key "$PRIVATE_KEY" 2>&1 || true)
  else
    deploy_out=$(forge script scripts/DeployRAT.s.sol:DeployRAT --broadcast --rpc-url "$L1_RPC" --private-key "$PRIVATE_KEY" 2>&1 || true)
  fi
  popd >/dev/null
  RAT_ADDR=$(echo "$deploy_out" | grep -oE 'RAT Proxy initialized and ready at: 0x[a-fA-F0-9]+' | awk '{print $7}' | tail -1)
  if [[ -z "$RAT_ADDR" ]]; then
    echo "Failed to parse RAT address from DeployRAT output." >&2
    echo "$deploy_out" >&2
    exit 1
  fi
fi

if [[ -z "${RAT_ADDR:-}" ]]; then
  echo "Missing RAT_ADDR (set RAT_ADDR or enable AUTO_DEPLOY_RAT=1)." >&2
  exit 1
fi

if [[ "$USE_INTEGRATED_DGF" == "1" ]]; then
  if [[ -z "${DISPUTE_GAME_FACTORY:-}" ]]; then
    echo "Missing DISPUTE_GAME_FACTORY. Set DISPUTE_GAME_FACTORY or provide $DEVNET_ENV_JSON." >&2
    exit 1
  fi

  echo "== Configure DisputeGameFactory RAT hook =="
  # Requires DisputeGameFactory owner privileges *and* a factory implementation that exposes `setRAT`.
  set +e
  set_rat_json=$(cast send --json --rpc-url "$L1_RPC" --private-key "$PRIVATE_KEY" --gas-limit 1000000 \
    "$DISPUTE_GAME_FACTORY" "setRAT(address)" "$RAT_ADDR" 2>&1)
  set_rat_rc=$?
  set -e
  if [[ $set_rat_rc -ne 0 ]]; then
    echo "Failed to call DisputeGameFactory.setRAT(address)." >&2
    echo "This usually means the devnet is running a DisputeGameFactory implementation that does not include the RAT hook (stock optimism-package), or the caller is not the owner." >&2
    echo "DISPUTE_GAME_FACTORY=$DISPUTE_GAME_FACTORY" >&2
    echo "caller=$deployer_addr" >&2
    echo "raw: $set_rat_json" >&2
    exit 1
  fi
fi

declare -A PK_BY_ADDR

if [[ "$AUTO_STAKE" == "1" ]]; then
  echo "== Stake validators =="
  # Build a validator set we fully control (so whichever address is selected, we have its key).
  # First validator is the deployer.
  PK_BY_ADDR["$deployer_addr"]="$PRIVATE_KEY"
  validators=("$deployer_addr")
  validator_pks=("$PRIVATE_KEY")

  # Generate additional validators.
  for i in $(seq 2 "$VALIDATOR_COUNT"); do
    pk="0x$(openssl rand -hex 32)"
    addr=$(cast wallet address --private-key "$pk")
    addr="${addr,,}"
    PK_BY_ADDR["$addr"]="$pk"
    validators+=("$addr")
    validator_pks+=("$pk")
  done

  # Fund + stake each validator.
  for i in "${!validators[@]}"; do
    addr="${validators[$i]}"
    pk="${validator_pks[$i]}"
    # Fund each validator from deployer.
    send_and_wait "$L1_RPC" "$PRIVATE_KEY" "$addr" --value 2ether >/dev/null
    send_and_wait "$L1_RPC" "$pk" "$RAT_ADDR" "stake()" --value 1ether >/dev/null
  done
fi

echo "== Ensure trigger probability =="
send_and_wait "$L1_RPC" "$PRIVATE_KEY" "$RAT_ADDR" "setRatTriggerProbability(uint256)" "100000" >/dev/null

if [[ "$USE_INTEGRATED_DGF" != "1" ]]; then
  echo "== Step A: triggerAttentionTest =="
  tx_json=$(cast send --json "$RAT_ADDR" \
    "triggerAttentionTest(address,bytes32,bytes32,uint64)" \
    "$GAME_ADDR" "$OUTPUT_ROOT" "0x0000000000000000000000000000000000000000000000000000000000000000" "$L2_BLOCK" \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$L1_RPC")
  tx_hash=$(echo "$tx_json" | jq -r '.transactionHash')
  if [[ -z "$tx_hash" || "$tx_hash" == "null" ]]; then
    echo "Failed to parse transaction hash from cast send output." >&2
    exit 1
  fi

  echo ""
  echo "== Step B: fetch AttentionTriggered seed =="
  receipt_json=$(cast receipt "$tx_hash" --json --rpc-url "$L1_RPC")
  status=$(echo "$receipt_json" | jq -r '.status')
  if [[ "$status" != "0x1" && "$status" != "1" ]]; then
    echo "triggerAttentionTest transaction failed: $tx_hash" >&2
    echo "$receipt_json" >&2
    exit 1
  fi
  block_number=$(echo "$receipt_json" | jq -r '.blockNumber')
  if [[ -z "$block_number" || "$block_number" == "null" ]]; then
    echo "Failed to parse block number from receipt." >&2
    exit 1
  fi

  logs_json=$(cast logs --address "$RAT_ADDR" \
    "AttentionTriggered(address,address,bytes32)" \
    --rpc-url "$L1_RPC" \
    --from-block "$block_number" \
    --to-block "$block_number" \
    --json)

  log_count=$(echo "$logs_json" | jq 'length')
  if [[ "$log_count" -eq 0 ]]; then
    echo "No AttentionTriggered logs found in block $block_number." >&2
    exit 1
  fi

  seed=$(echo "$logs_json" | jq -r '.[0].data')
  if [[ -z "$seed" || "$seed" == "null" ]]; then
    echo "Failed to parse seed from logs." >&2
    exit 1
  fi

  echo "Seed: $seed"
  echo ""
  echo "== Step C: compute closest key =="
  closest_json=$(RPC_URL="$L2_RPC" node scripts/find_closest_key.js "$seed" 2>/dev/null)
  echo "$closest_json"
  closest_key=$(echo "$closest_json" | jq -r '.closestKey')
  closest_addr=$(echo "$closest_json" | jq -r '.closestAddress')
  farthest_key=$(echo "$closest_json" | jq -r '.farthestKey')
  farthest_addr=$(echo "$closest_json" | jq -r '.farthestAddress')
  if [[ -z "$closest_key" || "$closest_key" == "null" ]]; then
    echo "Failed to parse closestKey from discovery output." >&2
    exit 1
  fi
  if [[ -z "$closest_addr" || "$closest_addr" == "null" ]]; then
    echo "Failed to parse closestAddress from discovery output." >&2
    exit 1
  fi
  if [[ -z "$farthest_key" || "$farthest_key" == "null" || -z "$farthest_addr" || "$farthest_addr" == "null" ]]; then
    echo "Failed to parse farthestKey/farthestAddress from discovery output." >&2
    exit 1
  fi
fi

echo ""
echo "== Step D: dispute (manual) =="
echo "Use the closestKey from Step C:"
echo "  cast send $RAT_ADDR \"disputeByCloserKey(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])\" \\"
echo "    $GAME_ADDR <CLOSER_KEY> <STATE_ROOT> <VERSION> <MESSAGE_PASSER_ROOT> <BLOCK_HASH> <PROOF_JSON> \\"
echo "    --private-key $PRIVATE_KEY --rpc-url $L1_RPC"
echo ""
echo "If you have the dispute tx hash, export DISPUTE_TX_HASH and re-run to verify."

if [[ -n "${DISPUTE_TX_HASH:-}" ]]; then
  echo ""
  echo "== Step E: verify dispute logs =="
  dispute_receipt=$(cast receipt "$DISPUTE_TX_HASH" --json --rpc-url "$L1_RPC")
  dispute_block=$(echo "$dispute_receipt" | jq -r '.blockNumber')
  if [[ -z "$dispute_block" || "$dispute_block" == "null" ]]; then
    echo "Failed to parse dispute block number." >&2
    exit 1
  fi

  dispute_logs=$(cast logs --address "$RAT_ADDR" \
    "DisputeSuccessful(address,address,bytes32,uint256,string)" \
    --rpc-url "$L1_RPC" \
    --from-block "$dispute_block" \
    --to-block "$dispute_block" \
    --json)

  if [[ "$(echo "$dispute_logs" | jq 'length')" -eq 0 ]]; then
    echo "No DisputeSuccessful logs found in block $dispute_block."
    exit 1
  fi

  echo "$dispute_logs" | jq '.'
fi

if [[ "$AUTO_E2E_DISPUTE_CHECKS" == "1" ]]; then
  echo ""
  echo "== E2E Dispute checks (non-inclusion + closer-key, success + failure) =="

  if [[ "$USE_INTEGRATED_DGF" == "1" ]]; then
    if [[ -z "${DISPUTE_GAME_FACTORY:-}" ]]; then
      echo "Missing DISPUTE_GAME_FACTORY. Set DISPUTE_GAME_FACTORY or provide $DEVNET_ENV_JSON." >&2
      exit 1
    fi

    # Read required init bond for CANNON (game type 0).
    init_bond_hex=$(cast call --rpc-url "$L1_RPC" "$DISPUTE_GAME_FACTORY" "initBonds(uint32)(uint256)" 0)
    init_bond_dec=$(cast to-dec "$init_bond_hex" 2>/dev/null || echo "0")

    # Helper: (re)compute L2 components for a given block number.
    set_l2_context() {
      local l2_num_dec="$1"
      l2_block_hex=$(cast to-hex "$l2_num_dec")

      local block_json_local=""
      for i in $(seq 1 "$WAIT_ATTEMPTS"); do
        local block_raw_local
        block_raw_local=$(cast rpc --rpc-url "$L2_RPC" eth_getBlockByNumber "$l2_block_hex" false 2>/dev/null || true)
        block_json_local=$(parse_result_object "$block_raw_local" 2>/dev/null || true)
        if [[ "$block_json_local" != "null" && -n "$block_json_local" ]]; then
          break
        fi
        echo "Waiting for L2 block data (block=$l2_num_dec)... ($i/$WAIT_ATTEMPTS)"
        sleep "$WAIT_SLEEP"
      done
      if [[ "$block_json_local" == "null" || -z "$block_json_local" ]]; then
        echo "Failed to fetch L2 block data for $l2_num_dec." >&2
        exit 1
      fi

      STATE_ROOT=$(echo "$block_json_local" | jq -r '.stateRoot')
      BLOCK_HASH=$(echo "$block_json_local" | jq -r '.hash')

      local proof_json_local=""
      for i in $(seq 1 "$WAIT_ATTEMPTS"); do
        local proof_raw_local
        proof_raw_local=$(cast rpc --rpc-url "$L2_RPC" eth_getProof "$MESSAGE_PASSER_ADDR" "[]" "$l2_block_hex" 2>/dev/null || true)
        proof_json_local=$(parse_result_object "$proof_raw_local" 2>/dev/null || true)
        if [[ "$proof_json_local" != "null" && -n "$proof_json_local" ]]; then
          break
        fi
        echo "Waiting for L2 proof data (block=$l2_num_dec)... ($i/$WAIT_ATTEMPTS)"
        sleep "$WAIT_SLEEP"
      done
      if [[ "$proof_json_local" == "null" || -z "$proof_json_local" ]]; then
        echo "Failed to fetch L2 proof data for $l2_num_dec." >&2
        exit 1
      fi

      MESSAGE_PASSER_ROOT=$(echo "$proof_json_local" | jq -r '.storageHash')
      version="0x0000000000000000000000000000000000000000000000000000000000000000"
      encoded=$(cast abi-encode "f(bytes32,bytes32,bytes32,bytes32)" "$version" "$STATE_ROOT" "$MESSAGE_PASSER_ROOT" "$BLOCK_HASH")
      OUTPUT_ROOT=$(cast keccak "$encoded")
      L2_BLOCK="$l2_num_dec"
    }

    # Helper: create a dispute game via factory (this should trigger RAT via integrated hook).
    create_game_and_get_seed() {
      local label="$1"
      local l2_num_dec="$2"
      set_l2_context "$l2_num_dec"

      # extraData = bytes32(l2BlockNumber) || bytes32(l2BlockHash)
      local l2_word
      l2_word=$(printf "0x%064x" "$l2_num_dec")
      extra_data="0x${l2_word#0x}${BLOCK_HASH#0x}"

      echo ""
      echo "-- Case: $label"
      echo "Creating DisputeGame via factory (integrated trigger)"
      echo "  DGF: $DISPUTE_GAME_FACTORY"
      echo "  initBond: $init_bond_dec"
      echo "  l2Block: $L2_BLOCK"

      if [[ "$init_bond_dec" == "0" ]]; then
        tx_json=$(cast send --json --gas-limit 3000000 --rpc-url "$L1_RPC" --private-key "$PRIVATE_KEY" "$DISPUTE_GAME_FACTORY" \
          "create(uint32,bytes32,bytes)" 0 "$OUTPUT_ROOT" "$extra_data")
      else
        tx_json=$(cast send --json --gas-limit 3000000 --rpc-url "$L1_RPC" --private-key "$PRIVATE_KEY" --value "$init_bond_dec" "$DISPUTE_GAME_FACTORY" \
          "create(uint32,bytes32,bytes)" 0 "$OUTPUT_ROOT" "$extra_data")
      fi

      tx_hash=$(echo "$tx_json" | jq -r '.transactionHash')
      receipt_json=$(cast receipt "$tx_hash" --json --rpc-url "$L1_RPC")
      status=$(echo "$receipt_json" | jq -r '.status')
      if [[ "$status" != "0x1" && "$status" != "1" ]]; then
        echo "create() failed: $tx_hash" >&2
        echo "$receipt_json" | jq '.' >&2
        exit 1
      fi
      block_number=$(echo "$receipt_json" | jq -r '.blockNumber')

      # Find the created game address.
      dgf_logs=$(cast logs --address "$DISPUTE_GAME_FACTORY" "DisputeGameCreated(address,uint32,bytes32)" \
        --rpc-url "$L1_RPC" --from-block "$block_number" --to-block "$block_number" --json)
      # Some cast versions return raw topics without decoded args. DisputeGameCreated has indexed disputeProxy.
      game_topic=$(echo "$dgf_logs" | jq -r '.[0].topics[1] // empty')
      game_addr=""
      if [[ -n "${game_topic:-}" && "$game_topic" != "null" ]]; then
        game_addr="0x${game_topic: -40}"
      else
        game_addr=$(echo "$dgf_logs" | jq -r '.[0].args.disputeProxy // empty')
      fi
      if [[ -z "${game_addr:-}" ]]; then
        echo "Failed to parse DisputeGameCreated.disputeProxy from logs." >&2
        echo "$dgf_logs" | jq '.' >&2
        exit 1
      fi
      game_addr=$(cast to-checksum "$game_addr")

      # Find the AttentionTriggered event emitted by RAT during factory create().
      rat_logs=$(cast logs --address "$RAT_ADDR" "AttentionTriggered(address,address,bytes32)" \
        --rpc-url "$L1_RPC" --from-block "$block_number" --to-block "$block_number" --json)
      # AttentionTriggered has indexed gameAddress and challenger, and seed in data.
      seed=$(echo "$rat_logs" | jq -r --arg g "${game_addr,,}" '
        .[] | select(("0x"+(.topics[1][26:66]))==$g) | .data' | head -1)
      selected_challenger=$(echo "$rat_logs" | jq -r --arg g "${game_addr,,}" '
        .[] | select(("0x"+(.topics[1][26:66]))==$g) | ("0x"+(.topics[2][26:66]))' | head -1)
      selected_challenger="${selected_challenger,,}"
      if [[ -z "${seed:-}" || "$seed" == "null" || -z "${selected_challenger:-}" || "$selected_challenger" == "null" ]]; then
        echo "Failed to find AttentionTriggered for game=$game_addr in block $block_number" >&2
        echo "$rat_logs" | jq '.' >&2
        exit 1
      fi

      echo "  game: $game_addr"
      echo "  selected: $selected_challenger"
      echo "  seed: $seed"
    }

    # Helper to run a full case with integrated create().
    run_case_integrated() {
      local label="$1"
      local l2_num_dec="$2"
      local submit_mode="$3"   # random-missing | closest | farthest
      local dispute_kind="$4"  # non-inclusion | closer-key
      local dispute_mode="$5"  # closest | farthest (for closer-key)
      local expect_success="$6" # 1 or 0

      create_game_and_get_seed "$label" "$l2_num_dec"

      # Discover closest/farthest keys for this seed.
      closest_json=$(RPC_URL="$L2_RPC" node scripts/find_closest_key.js "$seed" 2>/dev/null)
      close_key=$(echo "$closest_json" | jq -r '.closestKey')
      close_addr=$(echo "$closest_json" | jq -r '.closestAddress')
      far_key=$(echo "$closest_json" | jq -r '.farthestKey')
      far_addr=$(echo "$closest_json" | jq -r '.farthestAddress')
      if [[ -z "${close_key:-}" || "$close_key" == "null" || -z "${close_addr:-}" || "$close_addr" == "null" ]]; then
        echo "Failed to compute closest key for $label" >&2
        echo "$closest_json" >&2
        exit 1
      fi
      if [[ -z "${far_key:-}" || "$far_key" == "null" || -z "${far_addr:-}" || "$far_addr" == "null" ]]; then
        echo "Failed to compute farthest key for $label" >&2
        echo "$closest_json" >&2
        exit 1
      fi
      close_addr=$(cast to-checksum "$close_addr")
      far_addr=$(cast to-checksum "$far_addr")

      submit_pk="${PK_BY_ADDR[$selected_challenger]:-}"
      if [[ -z "${submit_pk:-}" ]]; then
        echo "Selected challenger not found in local validator set: $selected_challenger" >&2
        exit 1
      fi

      # Choose candidate key.
      if [[ "$submit_mode" == "random-missing" ]]; then
        rnd_addr=$(cast to-checksum "0x$(openssl rand -hex 20)")
        candidate_key=$(bytes32_from_address "$rnd_addr")
        candidate_addr="$rnd_addr"
      elif [[ "$submit_mode" == "closest" ]]; then
        candidate_key="$close_key"
        candidate_addr="$close_addr"
      else
        candidate_key="$far_key"
        candidate_addr="$far_addr"
      fi

      # Choose disputer (any other validator).
      disputer_pk=""
      for addr in "${validators[@]}"; do
        if [[ "$addr" != "$selected_challenger" ]]; then
          disputer_pk="${PK_BY_ADDR[$addr]}"
          break
        fi
      done
      if [[ -z "${disputer_pk:-}" ]]; then
        echo "Failed to pick a disputer key." >&2
        exit 1
      fi

      # Submit candidate to RAT (on the game address created by DGF).
      send_and_wait "$L1_RPC" "$submit_pk" "$RAT_ADDR" \
        "submitCandidate(address,bytes32,bytes32,bytes32,bytes32,bytes32)" \
        "$game_addr" "$candidate_key" "$STATE_ROOT" "$version" "$MESSAGE_PASSER_ROOT" "$BLOCK_HASH" >/dev/null

      if [[ "$dispute_kind" == "non-inclusion" ]]; then
        pobj=$(get_account_proof_obj "$candidate_addr") || true
        print_proof_summary "$label (non-inclusion proof target)" "$candidate_addr" "${pobj:-null}"
        proof_inner=$(echo "${pobj:-null}" | jq -r '.accountProof | join(",")')
        proof="[$proof_inner]"
        if [[ -z "${proof_inner:-}" || "$proof" == "[]" ]]; then
          echo "Failed to get accountProof for $candidate_addr" >&2
          exit 1
        fi
        dispute_receipt=$(send_and_receipt "$L1_RPC" "$disputer_pk" --gas-limit 3000000 "$RAT_ADDR" \
          "disputeByNonInclusion(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])" \
          "$game_addr" "$candidate_key" "$STATE_ROOT" "$version" "$MESSAGE_PASSER_ROOT" "$BLOCK_HASH" "$proof")
      else
        if [[ "$dispute_mode" == "closest" ]]; then
          dispute_key="$close_key"
          dispute_addr="$close_addr"
        else
          dispute_key="$far_key"
          dispute_addr="$far_addr"
        fi
        pobj=$(get_account_proof_obj "$dispute_addr") || true
        print_proof_summary "$label (closer-key proof target)" "$dispute_addr" "${pobj:-null}"
        proof_inner=$(echo "${pobj:-null}" | jq -r '.accountProof | join(",")')
        proof="[$proof_inner]"
        if [[ -z "${proof_inner:-}" || "$proof" == "[]" ]]; then
          echo "Failed to get accountProof for $dispute_addr" >&2
          exit 1
        fi
        dispute_receipt=$(send_and_receipt "$L1_RPC" "$disputer_pk" --gas-limit 3000000 "$RAT_ADDR" \
          "disputeByCloserKey(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])" \
          "$game_addr" "$dispute_key" "$STATE_ROOT" "$version" "$MESSAGE_PASSER_ROOT" "$BLOCK_HASH" "$proof")
      fi

      ds=$(echo "$dispute_receipt" | jq -r '.status')
      gas_used=$(echo "$dispute_receipt" | jq -r '.gasUsed')
      gas_used_dec=$(cast to-dec "$gas_used" 2>/dev/null || echo "")
      proof_nodes=$(echo "${pobj:-null}" | jq -r '.accountProof | length')

      if [[ "$expect_success" == "1" ]]; then
        if [[ "$ds" != "0x1" && "$ds" != "1" ]]; then
          echo "Expected dispute SUCCESS but reverted for $label" >&2
          echo "$dispute_receipt" | jq '.' >&2
          exit 1
        fi
        dblock=$(echo "$dispute_receipt" | jq -r '.blockNumber')
        dlogs=$(cast logs --address "$RAT_ADDR" "DisputeSuccessful(address,address,bytes32,uint256,string)" \
          --rpc-url "$L1_RPC" --from-block "$dblock" --to-block "$dblock" --json)
        if [[ "$(echo "$dlogs" | jq 'length')" -eq 0 ]]; then
          echo "Expected DisputeSuccessful log but none found for $label" >&2
          exit 1
        fi
        if [[ -n "${gas_used_dec}" ]]; then
          echo "PASS: $label (success) gasUsed=$gas_used_dec accountProofNodes=$proof_nodes"
        else
          echo "PASS: $label (success) gasUsed=$gas_used accountProofNodes=$proof_nodes"
        fi
      else
        if [[ "$ds" == "0x1" || "$ds" == "1" ]]; then
          echo "Expected dispute FAILURE but succeeded for $label" >&2
          echo "$dispute_receipt" | jq '.' >&2
          exit 1
        fi
        if [[ -n "${gas_used_dec}" ]]; then
          echo "PASS: $label (failure) gasUsed=$gas_used_dec accountProofNodes=$proof_nodes"
        else
          echo "PASS: $label (failure) gasUsed=$gas_used accountProofNodes=$proof_nodes"
        fi
      fi
    }

    # Use different L2 blocks per case to avoid DisputeGameFactory UUID collisions (extraData includes l2BlockNumber).
    base_l2="$L2_BLOCK"
    run_case_integrated "non-inclusion SUCCESS (missing addr)" "$base_l2" "random-missing" "non-inclusion" "closest" 1
    run_case_integrated "non-inclusion FAILURE (existing addr -> KeyExists)" "$((base_l2 - 1))" "closest" "non-inclusion" "closest" 0
    run_case_integrated "closer-key SUCCESS (closer exists)" "$((base_l2 - 2))" "farthest" "closer-key" "closest" 1
    run_case_integrated "closer-key FAILURE (not closer)" "$((base_l2 - 3))" "closest" "closer-key" "farthest" 0

    # Integrated path ends here (avoid running the legacy direct-trigger flow below).
    exit 0
  fi

  # Legacy (direct trigger) path below.
  # Helper to run a full flow on a fresh game address.
  run_case() {
    local label="$1"
    local game_addr="$2"
    local submit_key_bytes32="$3"
    local submit_key_addr="$4"
    local dispute_kind="$5" # non-inclusion | closer-key
    local dispute_key_bytes32="$6"
    local dispute_key_addr="$7"
    local expect_success="$8" # 1 or 0

    echo ""
    echo "-- Case: $label"

    # Trigger
    tx_json=$(cast send --json --gas-limit 1000000 "$RAT_ADDR" \
      "triggerAttentionTest(address,bytes32,bytes32,uint64)" \
      "$game_addr" "$OUTPUT_ROOT" "0x0000000000000000000000000000000000000000000000000000000000000000" "$L2_BLOCK" \
      --private-key "$PRIVATE_KEY" \
      --rpc-url "$L1_RPC")
    tx_hash=$(echo "$tx_json" | jq -r '.transactionHash')
    receipt_json=$(cast receipt "$tx_hash" --json --rpc-url "$L1_RPC")
    status=$(echo "$receipt_json" | jq -r '.status')
    if [[ "$status" != "0x1" && "$status" != "1" ]]; then
      echo "triggerAttentionTest failed: $tx_hash" >&2
      echo "$receipt_json" >&2
      exit 1
    fi
    block_number=$(echo "$receipt_json" | jq -r '.blockNumber')
    logs_json=$(cast logs --address "$RAT_ADDR" "AttentionTriggered(address,address,bytes32)" \
      --rpc-url "$L1_RPC" --from-block "$block_number" --to-block "$block_number" --json)
    if [[ "$(echo "$logs_json" | jq 'length')" -eq 0 ]]; then
      echo "No AttentionTriggered log for $label" >&2
      exit 1
    fi

    # Determine selected challenger for this game
    att_data=$(cast call --rpc-url "$L1_RPC" --data "$(cast calldata "getAttentionTest(address)" "$game_addr")" "$RAT_ADDR")
    att_info=$(cast decode-abi "getAttentionTest(address)(bytes32,bytes32,uint96,address,address,uint64,uint64,uint8)" "$att_data")
    mapfile -t att_lines <<<"$att_info"
    selected_challenger="${att_lines[4]:-}"

    submit_pk="$PRIVATE_KEY"
    if [[ "$selected_challenger" == "$secondary_addr" ]]; then
      submit_pk="$SECONDARY_KEY"
    elif [[ "$selected_challenger" != "$deployer_addr" ]]; then
      echo "Selected challenger not found in local keys: $selected_challenger" >&2
      exit 1
    fi

    # Submit candidate
    send_and_wait "$L1_RPC" "$submit_pk" "$RAT_ADDR" \
      "submitCandidate(address,bytes32,bytes32,bytes32,bytes32,bytes32)" \
      "$game_addr" "$submit_key_bytes32" "$STATE_ROOT" "$version" "$MESSAGE_PASSER_ROOT" "$BLOCK_HASH" >/dev/null

    # Choose disputer key (other challenger)
    disputer_pk="$SECONDARY_KEY"
    if [[ "$submit_pk" == "$SECONDARY_KEY" ]]; then
      disputer_pk="$PRIVATE_KEY"
    fi

    if [[ "$dispute_kind" == "non-inclusion" ]]; then
      pobj=$(get_account_proof_obj "$submit_key_addr") || true
      print_proof_summary "$label (non-inclusion proof target)" "$submit_key_addr" "${pobj:-null}"
      proof_inner=$(echo "${pobj:-null}" | jq -r '.accountProof | join(",")')
      proof="[$proof_inner]"
      if [[ -z "${proof_inner:-}" || "$proof" == "[]" ]]; then
        echo "Failed to get accountProof for $submit_key_addr" >&2
        exit 1
      fi
      dispute_receipt=$(send_and_receipt "$L1_RPC" "$disputer_pk" --gas-limit 3000000 "$RAT_ADDR" \
        "disputeByNonInclusion(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])" \
        "$game_addr" "$submit_key_bytes32" "$STATE_ROOT" "$version" "$MESSAGE_PASSER_ROOT" "$BLOCK_HASH" "$proof")
    else
      pobj=$(get_account_proof_obj "$dispute_key_addr") || true
      print_proof_summary "$label (closer-key proof target)" "$dispute_key_addr" "${pobj:-null}"
      proof_inner=$(echo "${pobj:-null}" | jq -r '.accountProof | join(",")')
      proof="[$proof_inner]"
      if [[ -z "${proof_inner:-}" || "$proof" == "[]" ]]; then
        echo "Failed to get accountProof for $dispute_key_addr" >&2
        exit 1
      fi
      dispute_receipt=$(send_and_receipt "$L1_RPC" "$disputer_pk" --gas-limit 3000000 "$RAT_ADDR" \
        "disputeByCloserKey(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])" \
        "$game_addr" "$dispute_key_bytes32" "$STATE_ROOT" "$version" "$MESSAGE_PASSER_ROOT" "$BLOCK_HASH" "$proof")
    fi

    ds=$(echo "$dispute_receipt" | jq -r '.status')
    gas_used=$(echo "$dispute_receipt" | jq -r '.gasUsed')
    gas_used_dec=$(cast to-dec "$gas_used" 2>/dev/null || echo "")
    if [[ "$dispute_kind" == "non-inclusion" ]]; then
      proof_nodes=$(echo "${pobj:-null}" | jq -r '.accountProof | length')
    else
      proof_nodes=$(echo "${pobj:-null}" | jq -r '.accountProof | length')
    fi
    if [[ "$expect_success" == "1" ]]; then
      if [[ "$ds" != "0x1" && "$ds" != "1" ]]; then
        echo "Expected dispute SUCCESS but reverted for $label" >&2
        echo "$dispute_receipt" | jq '.' >&2
        exit 1
      fi
      dblock=$(echo "$dispute_receipt" | jq -r '.blockNumber')
      dlogs=$(cast logs --address "$RAT_ADDR" "DisputeSuccessful(address,address,bytes32,uint256,string)" \
        --rpc-url "$L1_RPC" --from-block "$dblock" --to-block "$dblock" --json)
      if [[ "$(echo "$dlogs" | jq 'length')" -eq 0 ]]; then
        echo "Expected DisputeSuccessful log but none found for $label" >&2
        exit 1
      fi
      if [[ -n "${gas_used_dec}" ]]; then
        echo "PASS: $label (success) gasUsed=$gas_used_dec accountProofNodes=$proof_nodes"
      else
        echo "PASS: $label (success) gasUsed=$gas_used accountProofNodes=$proof_nodes"
      fi
    else
      if [[ "$ds" == "0x1" || "$ds" == "1" ]]; then
        echo "Expected dispute FAILURE but succeeded for $label" >&2
        echo "$dispute_receipt" | jq '.' >&2
        exit 1
      fi
      if [[ -n "${gas_used_dec}" ]]; then
        echo "PASS: $label (failure) gasUsed=$gas_used_dec accountProofNodes=$proof_nodes"
      else
        echo "PASS: $label (failure) gasUsed=$gas_used accountProofNodes=$proof_nodes"
      fi
    fi
  }

  # Build some addresses/keys.
  # Closest/farthest are guaranteed to exist (from debug_dumpBlock) and thus have valid proofs.
  close_addr=$(cast to-checksum "$closest_addr")
  far_addr=$(cast to-checksum "$farthest_addr")
  close_key="$closest_key"
  far_key="$farthest_key"

  # Random non-existent candidate (very likely absent) for non-inclusion success.
  rnd_addr=$(cast to-checksum "0x$(openssl rand -hex 20)")
  rnd_key=$(bytes32_from_address "$rnd_addr")

  run_case "non-inclusion SUCCESS (missing addr)" "0x00000000000000000000000000000000000000a1" "$rnd_key" "$rnd_addr" "non-inclusion" "0x0" "0x0000000000000000000000000000000000000000" 1
  run_case "non-inclusion FAILURE (existing addr -> KeyExists)" "0x00000000000000000000000000000000000000a2" "$close_key" "$close_addr" "non-inclusion" "0x0" "0x0000000000000000000000000000000000000000" 0

  run_case "closer-key SUCCESS (closer exists)" "0x00000000000000000000000000000000000000a3" "$far_key" "$far_addr" "closer-key" "$close_key" "$close_addr" 1
  run_case "closer-key FAILURE (not closer)" "0x00000000000000000000000000000000000000a4" "$close_key" "$close_addr" "closer-key" "$far_key" "$far_addr" 0
fi

if [[ "$AUTO_CLEANUP" == "1" ]]; then
  # handled by EXIT trap
  true
fi
