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
PREFUNDED_KEY=${PREFUNDED_KEY:-0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31}
WAIT_ATTEMPTS=${WAIT_ATTEMPTS:-90}
WAIT_SLEEP=${WAIT_SLEEP:-2}

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing dependency: jq (required for log parsing)" >&2
  exit 1
fi

_cleanup_ran=0
cleanup_on_exit() {
  if [[ "${_cleanup_ran}" == "1" ]]; then
    return 0
  fi
  _cleanup_ran=1
  if [[ "${AUTO_CLEANUP}" == "1" ]]; then
    echo ""
    echo "== Cleanup Kurtosis (trap) =="
    scripts/cleanup_kurtosis.sh || true
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
  PRIVATE_KEY="$PREFUNDED_KEY"
  echo "PRIVATE_KEY not set; using prefunded key."
fi

deployer_addr=$(cast wallet address --private-key "$PRIVATE_KEY")
if [[ -z "${GAME_ADDR:-}" ]]; then
  GAME_ADDR="$deployer_addr"
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
  deploy_out=$(forge script scripts/DeployRAT.s.sol:DeployRAT --broadcast --rpc-url "$L1_RPC" --private-key "$PRIVATE_KEY" 2>&1 || true)
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

if [[ "$AUTO_STAKE" == "1" ]]; then
  if [[ -z "${SECONDARY_KEY:-}" ]]; then
    SECONDARY_KEY="0x$(openssl rand -hex 32)"
  fi
  secondary_addr=$(cast wallet address --private-key "$SECONDARY_KEY")

  send_and_wait "$L1_RPC" "$PRIVATE_KEY" "$secondary_addr" --value 2ether >/dev/null
  send_and_wait "$L1_RPC" "$PRIVATE_KEY" "$RAT_ADDR" "stake()" --value 1ether >/dev/null
  send_and_wait "$L1_RPC" "$SECONDARY_KEY" "$RAT_ADDR" "stake()" --value 1ether >/dev/null
fi

echo "== Ensure trigger probability =="
send_and_wait "$L1_RPC" "$PRIVATE_KEY" "$RAT_ADDR" "setRatTriggerProbability(uint256)" "100000" >/dev/null

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

echo ""
echo "== Step D: submitCandidate (auto) =="
candidate_key="$closest_key"
if [[ "$CHEAT_NON_INCLUSION" == "1" ]]; then
  # Use a random address encoded as bytes32 (low 20 bytes) to keep the proof semantics consistent.
  rand_addr="0x$(openssl rand -hex 20)"
  candidate_key=$(bytes32_from_address "$rand_addr")
  echo "CHEAT_NON_INCLUSION=1: submitting random candidate key (to exercise non-inclusion dispute)."
fi
att_data=$(cast call --rpc-url "$L1_RPC" --data "$(cast calldata "getAttentionTest(address)" "$GAME_ADDR")" "$RAT_ADDR")
att_info=$(cast decode-abi "getAttentionTest(address)(bytes32,bytes32,uint96,address,address,uint64,uint64,uint8)" "$att_data")
mapfile -t att_lines <<<"$att_info"
_out_root="${att_lines[0]:-}"
_seed="${att_lines[1]:-}"
_bond="${att_lines[2]:-}"
_candidate_addr="${att_lines[3]:-}"
selected_challenger="${att_lines[4]:-}"
_deadline="${att_lines[5]:-}"
_l2block="${att_lines[6]:-}"
_status="${att_lines[7]:-}"
_bond="${_bond%% *}"

if [[ "$selected_challenger" == "0x0000000000000000000000000000000000000000" || -z "$selected_challenger" ]]; then
  echo "No challenger selected. Re-triggering once..."
  tx_json=$(cast send --json "$RAT_ADDR" \
    "triggerAttentionTest(address,bytes32,bytes32,uint64)" \
    "$GAME_ADDR" "$OUTPUT_ROOT" "0x0000000000000000000000000000000000000000000000000000000000000000" "$L2_BLOCK" \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$L1_RPC")
  tx_hash=$(echo "$tx_json" | jq -r '.transactionHash')
  receipt_json=$(cast receipt "$tx_hash" --json --rpc-url "$L1_RPC")
  status=$(echo "$receipt_json" | jq -r '.status')
  if [[ "$status" != "0x1" && "$status" != "1" ]]; then
    echo "triggerAttentionTest transaction failed: $tx_hash" >&2
    echo "$receipt_json" >&2
    exit 1
  fi
  att_data=$(cast call --rpc-url "$L1_RPC" --data "$(cast calldata "getAttentionTest(address)" "$GAME_ADDR")" "$RAT_ADDR")
  att_info=$(cast decode-abi "getAttentionTest(address)(bytes32,bytes32,uint96,address,address,uint64,uint64,uint8)" "$att_data")
  mapfile -t att_lines <<<"$att_info"
  _out_root="${att_lines[0]:-}"
  _seed="${att_lines[1]:-}"
  _bond="${att_lines[2]:-}"
  _candidate_addr="${att_lines[3]:-}"
  selected_challenger="${att_lines[4]:-}"
  _deadline="${att_lines[5]:-}"
  _l2block="${att_lines[6]:-}"
  _status="${att_lines[7]:-}"
  _bond="${_bond%% *}"
fi

submit_key="$PRIVATE_KEY"
if [[ "$selected_challenger" == "$secondary_addr" ]]; then
  submit_key="$SECONDARY_KEY"
elif [[ "$selected_challenger" != "$deployer_addr" ]]; then
  echo "Selected challenger not found in local keys: $selected_challenger" >&2
  exit 1
fi

send_and_wait "$L1_RPC" "$submit_key" "$RAT_ADDR" \
  "submitCandidate(address,bytes32,bytes32,bytes32,bytes32,bytes32)" \
  "$GAME_ADDR" "$candidate_key" "$STATE_ROOT" "$version" "$MESSAGE_PASSER_ROOT" "$BLOCK_HASH" >/dev/null

echo ""
echo "== Step E: disputeByNonInclusion (optional, requires real MPT proof) =="
if [[ "$AUTO_DISPUTE_NON_INCLUSION" != "1" ]]; then
  echo "Skipping non-inclusion dispute (set AUTO_DISPUTE_NON_INCLUSION=1 to run)."
else
  dispute_key="$SECONDARY_KEY"
  if [[ "$submit_key" == "$SECONDARY_KEY" ]]; then
    dispute_key="$PRIVATE_KEY"
  fi

  # Candidate is interpreted as address(uint160(uint256(candidate_key))).
  candidate_addr="0x${candidate_key: -40}"
  candidate_addr=$(cast to-checksum "$candidate_addr")
  proof_obj=$(get_account_proof_obj "$candidate_addr") || true
  print_proof_summary "non-inclusion candidate" "$candidate_addr" "${proof_obj:-null}"
  account_proof_inner=$(echo "${proof_obj:-null}" | jq -r '.accountProof | join(",")')
  account_proof="[$account_proof_inner]"
  if [[ -z "${account_proof:-}" || "$account_proof" == "[]" ]]; then
    echo "Failed to fetch accountProof for candidate address $candidate_addr" >&2
    exit 1
  fi

  # If CHEAT_NON_INCLUSION=1, we expect the dispute to succeed (candidate likely absent).
  # Otherwise, for an honest candidate, the dispute should typically revert (KeyExists).
  set +e
  dispute_tx_json=$(cast send --json --gas-limit 3000000 --rpc-url "$L1_RPC" --private-key "$dispute_key" "$RAT_ADDR" \
    "disputeByNonInclusion(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])" \
    "$GAME_ADDR" "$candidate_key" "$STATE_ROOT" "$version" "$MESSAGE_PASSER_ROOT" "$BLOCK_HASH" "$account_proof")
  send_rc=$?
  set -e

  if [[ $send_rc -ne 0 ]]; then
    echo "disputeByNonInclusion submission failed (RPC error)."
    echo "$dispute_tx_json"
    exit 1
  fi

  dispute_tx=$(echo "$dispute_tx_json" | jq -r '.transactionHash')
  echo "Dispute tx: $dispute_tx"
  dispute_receipt=$(cast receipt "$dispute_tx" --json --rpc-url "$L1_RPC")
  dispute_status=$(echo "$dispute_receipt" | jq -r '.status')

  if [[ "$dispute_status" != "0x1" && "$dispute_status" != "1" ]]; then
    echo "Dispute reverted (expected when candidate exists / proof shows inclusion)."
    echo "$dispute_receipt" | jq '.'
  else
    dispute_block=$(echo "$dispute_receipt" | jq -r '.blockNumber')
    dispute_logs=$(cast logs --address "$RAT_ADDR" \
      "DisputeSuccessful(address,address,bytes32,uint256,string)" \
      --rpc-url "$L1_RPC" \
      --from-block "$dispute_block" \
      --to-block "$dispute_block" \
      --json)
    echo "$dispute_logs" | jq '.'
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
