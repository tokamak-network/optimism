#!/usr/bin/env bash
set -euo pipefail

# Experiment knobs
ROUNDS=${ROUNDS:-30}
START_ROUND=${START_ROUND:-1}
VALIDATOR_COUNT=${VALIDATOR_COUNT:-5}
L2_TX_PER_ROUND=${L2_TX_PER_ROUND:-5}
EVIDENCE_PERIOD=${EVIDENCE_PERIOD:-3}
HONEST_DISPUTE_PROB=${HONEST_DISPUTE_PROB:-25} # percent
MESSAGE_PASSER_ADDR=${MESSAGE_PASSER_ADDR:-0x4200000000000000000000000000000000000016}
MIN_STAKE_WEI=${MIN_STAKE_WEI:-1000000000000000000}         # 1.0 ETH
BOND_WEI=${BOND_WEI:-300000000000000000}                    # bond (also liveness loss per missed submit in this experiment)
OFFLINE_PENALTY_BPS=${OFFLINE_PENALTY_BPS:-0}               # accounting-only in current design
STAKE_OFFLINE_WEI=${STAKE_OFFLINE_WEI:-1500000000000000000} # 1.5 ETH
STAKE_BYZ_WEI=${STAKE_BYZ_WEI:-1800000000000000000}         # 1.8 ETH
STAKE_HONEST_WEI=${STAKE_HONEST_WEI:-2000000000000000000}   # 2.0 ETH
TRIGGER_PROBABILITY=${TRIGGER_PROBABILITY:-50000} # 50% of MAX_PROBABILITY=100000

# Runtime integration knobs
AUTO_DISCOVER=${AUTO_DISCOVER:-1}
AUTO_RUNTIME_UPGRADE=${AUTO_RUNTIME_UPGRADE:-1}
AUTO_DEPLOY_RAT=${AUTO_DEPLOY_RAT:-1}
REUSE_RAT_ADDR=${REUSE_RAT_ADDR:-0}
AUTO_CLEANUP=${AUTO_CLEANUP:-0}
RESUME=${RESUME:-0}
PLOT=${PLOT:-1}

KURTOSIS_ENCLAVE=${KURTOSIS_ENCLAVE:-}
DEVNET_TMP_BASE=${DEVNET_TMP_BASE:-results}
RUN_ID=${RUN_ID:-}
RUN_DIR=${RUN_DIR:-}
REFRESH_ADDR_CACHE=${REFRESH_ADDR_CACHE:-0}

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing dependency: jq" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Normalize output dirs to absolute paths (pushd into subdirs happens later).
if [[ "${DEVNET_TMP_BASE}" != /* ]]; then
  DEVNET_TMP_BASE="$REPO_ROOT/$DEVNET_TMP_BASE"
fi
if [[ -n "${RUN_DIR:-}" && "${RUN_DIR}" != /* ]]; then
  RUN_DIR="$REPO_ROOT/$RUN_DIR"
fi

cleanup_on_exit() {
  if [[ "${AUTO_CLEANUP}" == "1" ]]; then
    "$SCRIPT_DIR/cleanup_kurtosis.sh" || true
  fi
}
trap cleanup_on_exit EXIT

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

bytes32_from_address() {
  local addr="$1"
  addr="${addr#0x}"
  addr="${addr,,}"
  printf "0x%064s" "$addr" | tr ' ' '0'
}

if [[ "$AUTO_DISCOVER" == "1" ]]; then
  if [[ -z "$KURTOSIS_ENCLAVE" ]]; then
    KURTOSIS_ENCLAVE=$(kurtosis enclave ls | awk 'NR>1 {print $2}' | tail -1)
  fi
  if [[ -z "$KURTOSIS_ENCLAVE" ]]; then
    echo "Missing KURTOSIS_ENCLAVE (set it or start a devnet first)." >&2
    exit 1
  fi

  inspect_out=$(kurtosis enclave inspect "$KURTOSIS_ENCLAVE")
  L1_RPC=${L1_RPC:-$(echo "$inspect_out" | grep -A10 "el-1-geth" | grep "rpc: 8545" | head -1 | sed -E 's/.*127\.0\.0\.1:([0-9]+).*/http:\/\/127.0.0.1:\1/')}
  L2_RPC=${L2_RPC:-$(echo "$inspect_out" | grep -A8 "op-el-" | grep "rpc: 8545" | head -1 | sed -E 's/.*127\.0\.0\.1:([0-9]+).*/http:\/\/127.0.0.1:\1/')}
fi

if [[ -z "${L1_RPC:-}" || -z "${L2_RPC:-}" ]]; then
  echo "Missing L1_RPC/L2_RPC." >&2
  exit 1
fi

if [[ "$RESUME" == "1" ]]; then
  if [[ -z "${RUN_DIR:-}" ]]; then
    echo "RESUME=1 requires RUN_DIR to be set (e.g., RUN_DIR=results/20260117-213758)." >&2
    exit 1
  fi
  tmp_dir="$RUN_DIR"
  mkdir -p "$tmp_dir"
else
  if [[ -z "${RUN_DIR:-}" ]]; then
    if [[ -z "${RUN_ID:-}" ]]; then
      RUN_ID="$(date +%Y%m%d-%H%M%S)"
    fi
    tmp_dir="$DEVNET_TMP_BASE/$RUN_ID"
  else
    tmp_dir="$RUN_DIR"
  fi
  mkdir -p "$tmp_dir"
fi

state_file="$tmp_dir/experiment_state.json"

# Fetch devnet deployment descriptor (op-deployer-configs) for keys + addresses.
if [[ -n "${KURTOSIS_ENCLAVE:-}" ]]; then
  kurtosis files download "$KURTOSIS_ENCLAVE" op-deployer-configs "$tmp_dir/op-deployer-configs" >/dev/null 2>&1 || true
fi

STATE_JSON="$tmp_dir/op-deployer-configs/state.json"
WALLETS_JSON="$tmp_dir/op-deployer-configs/wallets.json"

DISPUTE_GAME_FACTORY=${DISPUTE_GAME_FACTORY:-}
if [[ -z "$DISPUTE_GAME_FACTORY" && -f "$STATE_JSON" ]]; then
  DISPUTE_GAME_FACTORY=$(grep -o '"DisputeGameFactoryProxy": *"[^"]*"' "$STATE_JSON" | head -1 | cut -d'"' -f4)
fi
if [[ -z "$DISPUTE_GAME_FACTORY" ]]; then
  echo "Missing DISPUTE_GAME_FACTORY (could not auto-detect)." >&2
  exit 1
fi

OWNER_PK=${OWNER_PK:-}
if [[ -z "$OWNER_PK" && -f "$WALLETS_JSON" ]]; then
  # systemConfigOwnerPrivateKey is stored without 0x in some configs.
  raw=$(jq -r '.[keys[0]].systemConfigOwnerPrivateKey // empty' "$WALLETS_JSON" 2>/dev/null || true)
  if [[ -n "$raw" && "$raw" != "null" ]]; then
    if [[ "$raw" == 0x* ]]; then
      OWNER_PK="$raw"
    else
      OWNER_PK="0x$raw"
    fi
  fi
fi
if [[ -z "$OWNER_PK" ]]; then
  echo "Missing OWNER_PK (need DisputeGameFactory/ProxyAdmin owner key)." >&2
  exit 1
fi

OWNER_ADDR=$(cast wallet address --private-key "$OWNER_PK")
OWNER_ADDR="${OWNER_ADDR,,}"

echo "L1_RPC=$L1_RPC"
echo "L2_RPC=$L2_RPC"
echo "DGF=$DISPUTE_GAME_FACTORY"
echo "OWNER=$OWNER_ADDR"

# Determine current DGF proxy admin & impl.
DGF_ADMIN=$(cast call --rpc-url "$L1_RPC" --from 0x0000000000000000000000000000000000000000 "$DISPUTE_GAME_FACTORY" "admin()(address)")
DGF_IMPL=$(cast call --rpc-url "$L1_RPC" --from 0x0000000000000000000000000000000000000000 "$DISPUTE_GAME_FACTORY" "implementation()(address)")
echo "DGF_ADMIN=$DGF_ADMIN"
echo "DGF_IMPL=$DGF_IMPL"

has_rat_slot=0
if cast call --rpc-url "$L1_RPC" "$DISPUTE_GAME_FACTORY" "rat()(address)" >/dev/null 2>&1; then
  has_rat_slot=1
fi

if [[ "$AUTO_RUNTIME_UPGRADE" == "1" && "$has_rat_slot" != "1" ]]; then
  echo "== Runtime upgrade: DisputeGameFactory impl =="
  pushd "$SCRIPT_DIR/../packages/contracts-bedrock" >/dev/null
  NEW_DGF_IMPL=$(forge create --broadcast --rpc-url "$L1_RPC" --private-key "$OWNER_PK" src/dispute/DisputeGameFactory.sol:DisputeGameFactory | awk '/Deployed to:/ {print $3}' | tail -1)
  popd >/dev/null
  echo "NEW_DGF_IMPL=$NEW_DGF_IMPL"
  cast send --rpc-url "$L1_RPC" --private-key "$OWNER_PK" --gas-limit 1500000 "$DGF_ADMIN" "upgrade(address,address)" "$DISPUTE_GAME_FACTORY" "$NEW_DGF_IMPL" >/dev/null
fi

# Ensure CANNON impl supports 64-byte extraData by swapping gameImpls(0) to a compat impl from our repo.
if [[ "$AUTO_RUNTIME_UPGRADE" == "1" ]]; then
  echo "== Runtime upgrade: FaultDisputeGame impl (CANNON) =="
  OLD_FDG_IMPL=$(cast call --rpc-url "$L1_RPC" "$DISPUTE_GAME_FACTORY" "gameImpls(uint32)(address)" 0)
  echo "OLD_FDG_IMPL=$OLD_FDG_IMPL"
  pushd "$SCRIPT_DIR/../packages/contracts-bedrock" >/dev/null
  EXISTING_FDG_IMPL="$OLD_FDG_IMPL" forge script scripts/DeployFaultDisputeGameCompat.s.sol:DeployFaultDisputeGameCompat \
    --broadcast --rpc-url "$L1_RPC" --private-key "$OWNER_PK" 2>&1 | tee "$tmp_dir/fdg_deploy.log"
  NEW_FDG_IMPL=$(grep -oE '0x[a-fA-F0-9]{40}' "$tmp_dir/fdg_deploy.log" | head -1)
  popd >/dev/null
  echo "NEW_FDG_IMPL=$NEW_FDG_IMPL"
  cast send --rpc-url "$L1_RPC" --private-key "$OWNER_PK" --gas-limit 1500000 "$DISPUTE_GAME_FACTORY" "setImplementation(uint32,address)" 0 "$NEW_FDG_IMPL" >/dev/null
fi

if [[ "$RESUME" == "1" ]]; then
  if [[ ! -f "$state_file" ]]; then
    echo "RESUME=1 but state file not found: $state_file" >&2
    exit 1
  fi
  RAT_ADDR=$(jq -r '.ratAddr' "$state_file")
  if [[ -z "${RAT_ADDR:-}" || "$RAT_ADDR" == "null" ]]; then
    echo "Invalid ratAddr in state file." >&2
    exit 1
  fi
fi

if [[ "$AUTO_DEPLOY_RAT" == "1" && "$REUSE_RAT_ADDR" != "1" && "$RESUME" != "1" ]]; then
  echo "== Deploy RAT (proxy) =="
  pushd "$SCRIPT_DIR/../packages/contracts-bedrock" >/dev/null
  RAT_FACTORY="$DISPUTE_GAME_FACTORY" RAT_TRIGGER_PROBABILITY=100000 forge script scripts/DeployRAT.s.sol:DeployRAT \
    --broadcast --rpc-url "$L1_RPC" --private-key "$OWNER_PK" 2>&1 | tee "$tmp_dir/rat_deploy.log"
  popd >/dev/null
  RAT_ADDR=$(grep -oE 'RAT Proxy initialized and ready at: 0x[a-fA-F0-9]+' "$tmp_dir/rat_deploy.log" | awk '{print $7}' | tail -1)
fi
if [[ -z "$RAT_ADDR" ]]; then
  echo "Missing RAT_ADDR (set RAT_ADDR or enable AUTO_DEPLOY_RAT=1)." >&2
  exit 1
fi

echo "RAT_ADDR=$RAT_ADDR"

echo "== Link RAT into DGF =="
cast send --rpc-url "$L1_RPC" --private-key "$OWNER_PK" --gas-limit 1000000 "$DISPUTE_GAME_FACTORY" "setRAT(address)" "$RAT_ADDR" >/dev/null

echo "== Configure RAT params for experiment =="
cast send --rpc-url "$L1_RPC" --private-key "$OWNER_PK" --gas-limit 1000000 "$RAT_ADDR" "setMinimumStakingBalance(uint256)" "$MIN_STAKE_WEI" >/dev/null
cast send --rpc-url "$L1_RPC" --private-key "$OWNER_PK" --gas-limit 1000000 "$RAT_ADDR" "setPerTestBondAmount(uint256)" "$BOND_WEI" >/dev/null
cast send --rpc-url "$L1_RPC" --private-key "$OWNER_PK" --gas-limit 1000000 "$RAT_ADDR" "setOfflinePenaltyRate(uint256)" "$OFFLINE_PENALTY_BPS" >/dev/null
cast send --rpc-url "$L1_RPC" --private-key "$OWNER_PK" --gas-limit 1000000 "$RAT_ADDR" "setEvidenceSubmissionPeriod(uint256)" "$EVIDENCE_PERIOD" >/dev/null
cast send --rpc-url "$L1_RPC" --private-key "$OWNER_PK" --gas-limit 1000000 "$RAT_ADDR" "setRatTriggerProbability(uint256)" "$TRIGGER_PROBABILITY" >/dev/null

L2_FAUCET_PK=${L2_FAUCET_PK:-}
if [[ -z "$L2_FAUCET_PK" && -f "$WALLETS_JSON" ]]; then
  raw=$(jq -r '.[keys[0]].l2FaucetPrivateKey // empty' "$WALLETS_JSON" 2>/dev/null || true)
  if [[ -n "$raw" && "$raw" != "null" ]]; then
    L2_FAUCET_PK="$raw"
  fi
fi
if [[ -z "$L2_FAUCET_PK" ]]; then
  echo "Missing L2_FAUCET_PK (needed to send random L2 txs)." >&2
  exit 1
fi

echo "== Create 5 validators and stake =="
validators=()
validator_pks=()
declare -A PK_BY_ADDR
declare -A PRIZE_WEI_BY_ADDR

ROLE_LIVENESS=""
ROLE_SAFETY_DIST=""
ROLE_SAFETY_EXIST=""
ROLE_HONEST_1=""
ROLE_HONEST_2=""

if [[ "$RESUME" == "1" ]]; then
  mapfile -t validators < <(jq -r '.validators[]' "$state_file")
  mapfile -t validator_pks < <(jq -r '.validatorPks[]' "$state_file")
  for i in "${!validators[@]}"; do
    PK_BY_ADDR["${validators[$i]}"]="${validator_pks[$i]}"
  done
  ROLE_LIVENESS=$(jq -r '.roles.liveness' "$state_file")
  ROLE_SAFETY_DIST=$(jq -r '.roles.safetyDistance' "$state_file")
  ROLE_SAFETY_EXIST=$(jq -r '.roles.safetyExistence' "$state_file")
  ROLE_HONEST_1=$(jq -r '.roles.honest1' "$state_file")
  ROLE_HONEST_2=$(jq -r '.roles.honest2' "$state_file")
  for a in "${validators[@]}"; do PRIZE_WEI_BY_ADDR["$a"]=$(jq -r --arg a "$a" '.prizeWeiByAddr[$a] // "0"' "$state_file"); done
else
  for i in $(seq 1 "$VALIDATOR_COUNT"); do
    pk="0x$(openssl rand -hex 32)"
    addr=$(cast wallet address --private-key "$pk")
    addr="${addr,,}"
    validators+=("$addr")
    validator_pks+=("$pk")
    PK_BY_ADDR["$addr"]="$pk"
    PRIZE_WEI_BY_ADDR["$addr"]=0
    # fund + stake (experiment config)
    cast send --rpc-url "$L1_RPC" --private-key "$OWNER_PK" --gas-limit 1000000 "$addr" --value 3ether >/dev/null
    if [[ "$i" -eq 1 ]]; then
      cast send --rpc-url "$L1_RPC" --private-key "$pk" --gas-limit 1000000 "$RAT_ADDR" "stake()" --value "$STAKE_OFFLINE_WEI" >/dev/null
    elif [[ "$i" -eq 2 || "$i" -eq 3 ]]; then
      cast send --rpc-url "$L1_RPC" --private-key "$pk" --gas-limit 1000000 "$RAT_ADDR" "stake()" --value "$STAKE_BYZ_WEI" >/dev/null
    else
      cast send --rpc-url "$L1_RPC" --private-key "$pk" --gas-limit 1000000 "$RAT_ADDR" "stake()" --value "$STAKE_HONEST_WEI" >/dev/null
    fi
  done

  ROLE_LIVENESS="${validators[0]}"       # offline / no-submit
  ROLE_SAFETY_DIST="${validators[1]}"    # byzantine(distance)
  ROLE_SAFETY_EXIST="${validators[2]}"   # byzantine(non-existence)
  ROLE_HONEST_1="${validators[3]}"
  ROLE_HONEST_2="${validators[4]}"

  # Persist state for resuming (note: contains private keys; stored under /tmp by default).
  jq -n \
    --arg ratAddr "$RAT_ADDR" \
    --argjson validators "$(printf '%s\n' "${validators[@]}" | jq -R . | jq -s .)" \
    --argjson pks "$(printf '%s\n' "${validator_pks[@]}" | jq -R . | jq -s .)" \
    --arg l "$ROLE_LIVENESS" \
    --arg sd "$ROLE_SAFETY_DIST" \
    --arg se "$ROLE_SAFETY_EXIST" \
    --arg h1 "$ROLE_HONEST_1" \
    --arg h2 "$ROLE_HONEST_2" \
    --argjson prize "$(printf '%s\n' "${validators[@]}" | while read -r a; do echo "$a ${PRIZE_WEI_BY_ADDR[$a]}"; done | jq -Rn '
      [inputs | select(length>0) | split(" ") | {(.[0]): .[1]}] | add
    ')" \
    '{
      ratAddr: $ratAddr,
      validators: $validators,
      validatorPks: $pks,
      roles: { liveness: $l, safetyDistance: $sd, safetyExistence: $se, honest1: $h1, honest2: $h2 },
      prizeWeiByAddr: $prize
    }' > "$state_file"
fi

echo "Roles:"
echo "  byzantine(offline/no submit)=$ROLE_LIVENESS"
echo "  byzantine(distance)=$ROLE_SAFETY_DIST"
echo "  byzantine(non-existence)=$ROLE_SAFETY_EXIST"
echo "  honest=$ROLE_HONEST_1"
echo "  honest=$ROLE_HONEST_2"

echo "== Prepare CSV log =="
csv_path="$tmp_dir/staking.csv"
png_path="$tmp_dir/staking.pdf"
roles_path="$tmp_dir/roles.json"
if [[ "$RESUME" != "1" ]]; then
  rm -f "$csv_path"
  {
    echo -n "round"
    for a in "${validators[@]}"; do echo -n ",stake_${a},valid_${a},prize_${a}"; done
    echo ""
  } >> "$csv_path"

  jq -n \
    --arg off "$ROLE_LIVENESS" \
    --arg bd "$ROLE_SAFETY_DIST" \
    --arg be "$ROLE_SAFETY_EXIST" \
    --arg h1 "$ROLE_HONEST_1" \
    --arg h2 "$ROLE_HONEST_2" \
    '{
      ($off): "byzantine (offline)",
      ($bd): "byzantine (distance)",
      ($be): "byzantine (non-existence)",
      ($h1): "honest",
      ($h2): "honest"
    }' > "$roles_path"
fi

get_challenger_info() {
  local addr="$1"
  local out stake valid
  out=$(cast call --rpc-url "$L1_RPC" "$RAT_ADDR" "getChallengerInfo(address)(uint256,uint256,uint32,bool)" "$addr")
  # cast prints 4 lines (each line may include a trailing scientific-notation hint in brackets).
  stake=$(echo "$out" | awk 'NR==1 {print $1}')
  valid=$(echo "$out" | awk 'NR==4 {print $1}')
  echo "$stake $valid"
}

log_round() {
  local r="$1"
  echo -n "$r" >> "$csv_path"
  for a in "${validators[@]}"; do
    info=$(get_challenger_info "$a")
    stake=$(echo "$info" | awk '{print $1}')
    valid=$(echo "$info" | awk '{print $2}')
    prize="${PRIZE_WEI_BY_ADDR[$a]:-0}"
    echo -n ",$stake,$valid,$prize" >> "$csv_path"
  done
  echo "" >> "$csv_path"
}

persist_prize_state() {
  # Keep the resume state in sync with prize accumulation.
  if [[ -f "$state_file" ]]; then
    prize_json=$(printf '%s\n' "${validators[@]}" | while read -r a; do echo "$a ${PRIZE_WEI_BY_ADDR[$a]:-0}"; done | jq -Rn '
      [inputs | select(length>0) | split(" ") | {(.[0]): .[1]}] | add
    ')
    tmp="${state_file}.tmp"
    jq --argjson prize "$prize_json" '.prizeWeiByAddr = $prize' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  fi
}

echo "== Build cached L2 address list (debug_dumpBlock) =="
addr_cache="$tmp_dir/l2_addrs.json"
if [[ "$REFRESH_ADDR_CACHE" == "1" || ! -f "$addr_cache" ]]; then
  dump_raw=$(cast rpc --rpc-url "$L2_RPC" debug_dumpBlock latest)
  dump_obj=$(parse_result_object "$dump_raw")
  # Prefer .accounts keys when available.
  echo "$dump_obj" | jq -r '
    if (.accounts? != null) then
      (.accounts | keys)
    else
      (keys)
    end
  ' > "$addr_cache"
fi
echo "addr_cache=$addr_cache"

if [[ "$RESUME" != "1" ]]; then
  # Round 0 snapshot (initial staking + prizes) for plots.
  log_round 0
  persist_prize_state
fi

echo "== Run rounds ($START_ROUND..$((START_ROUND + ROUNDS - 1))) =="
for r in $(seq "$START_ROUND" "$((START_ROUND + ROUNDS - 1))"); do
  echo ""
  echo "-- Round $r/$ROUNDS"

  # L2 random txs to mutate state.
  for j in $(seq 1 "$L2_TX_PER_ROUND"); do
    to="0x$(openssl rand -hex 20)"
    cast send --rpc-url "$L2_RPC" --private-key "$L2_FAUCET_PK" --gas-limit 1000000 "$to" --value 1wei >/dev/null || true
  done

  l2_block_raw=$(cast rpc --rpc-url "$L2_RPC" eth_blockNumber)
  l2_block_hex=$(parse_hex_result "$l2_block_raw")
  l2_block_dec=$(cast to-dec "$l2_block_hex")
  block_json_raw=$(cast rpc --rpc-url "$L2_RPC" eth_getBlockByNumber "$l2_block_hex" false)
  block_json=$(parse_result_object "$block_json_raw")
  state_root=$(echo "$block_json" | jq -r '.stateRoot')
  block_hash=$(echo "$block_json" | jq -r '.hash')

  proof_raw=$(cast rpc --rpc-url "$L2_RPC" eth_getProof "$MESSAGE_PASSER_ADDR" "[]" "$l2_block_hex")
  proof_obj=$(parse_result_object "$proof_raw")
  msg_passer_root=$(echo "$proof_obj" | jq -r '.storageHash')
  version="0x0000000000000000000000000000000000000000000000000000000000000000"
  encoded=$(cast abi-encode "f(bytes32,bytes32,bytes32,bytes32)" "$version" "$state_root" "$msg_passer_root" "$block_hash")
  output_root=$(cast keccak "$encoded")

  l2_word=$(printf "0x%064x" "$l2_block_dec")
  extra_data="0x${l2_word#0x}${block_hash#0x}"

  tx_json=$(cast send --json --gas-limit 3000000 --rpc-url "$L1_RPC" --private-key "$OWNER_PK" "$DISPUTE_GAME_FACTORY" \
    "create(uint32,bytes32,bytes)" 0 "$output_root" "$extra_data")
  tx_hash=$(echo "$tx_json" | jq -r '.transactionHash')
  receipt=$(cast receipt --rpc-url "$L1_RPC" --json "$tx_hash")
  bn=$(echo "$receipt" | jq -r '.blockNumber')

  dgf_logs=$(cast logs --rpc-url "$L1_RPC" --from-block "$bn" --to-block "$bn" --address "$DISPUTE_GAME_FACTORY" "DisputeGameCreated(address,uint32,bytes32)" --json)
  game_topic=$(echo "$dgf_logs" | jq -r '.[0].topics[1]')
  game_addr="0x${game_topic: -40}"
  game_addr=$(cast to-checksum "$game_addr")

  rat_logs=$(cast logs --rpc-url "$L1_RPC" --from-block "$bn" --to-block "$bn" --address "$RAT_ADDR" "AttentionTriggered(address,address,bytes32)" --json)
  selected=$(echo "$rat_logs" | jq -r --arg g "${game_addr,,}" '.[] | select(("0x"+(.topics[1][26:66]))==$g) | ("0x"+(.topics[2][26:66]))' | head -1)
  seed=$(echo "$rat_logs" | jq -r --arg g "${game_addr,,}" '.[] | select(("0x"+(.topics[1][26:66]))==$g) | .data' | head -1)
  selected="${selected,,}"

  if [[ -z "${selected:-}" || "$selected" == "null" ]]; then
    echo "  game=$game_addr RAT not triggered (p=$TRIGGER_PROBABILITY/100000) l2Block=$l2_block_dec"
    log_round "$r"
    persist_prize_state
    continue
  fi

  echo "  game=$game_addr selected=$selected l2Block=$l2_block_dec"

  # Compute closest/farthest from cached address set (fast; avoids debug_dumpBlock per round).
  closest_json=$(node "$SCRIPT_DIR/closest_key_from_addrs.js" "$seed" "$addr_cache" 2>/dev/null)
  close_key=$(echo "$closest_json" | jq -r '.closestKey')
  close_addr=$(echo "$closest_json" | jq -r '.closestAddress')
  far_key=$(echo "$closest_json" | jq -r '.farthestKey')
  far_addr=$(echo "$closest_json" | jq -r '.farthestAddress')
  if [[ -z "${close_key:-}" || "$close_key" == "null" || -z "${close_addr:-}" || "$close_addr" == "null" ]]; then
    echo "Failed to compute closest key/address from cached addr set for seed=$seed" >&2
    echo "$closest_json" >&2
    exit 1
  fi
  if [[ -z "${far_key:-}" || "$far_key" == "null" || -z "${far_addr:-}" || "$far_addr" == "null" ]]; then
    echo "Failed to compute farthest key/address from cached addr set for seed=$seed" >&2
    echo "$closest_json" >&2
    exit 1
  fi
  close_addr=$(cast to-checksum "$close_addr")
  far_addr=$(cast to-checksum "$far_addr")

  submit_pk="${PK_BY_ADDR[$selected]:-}"
  if [[ -z "$submit_pk" ]]; then
    echo "Selected not in our validator set (skipping round)."
    log_round "$r"
    persist_prize_state
    continue
  fi

  # Decide behavior by role.
  if [[ "$selected" == "$ROLE_LIVENESS" ]]; then
    echo "  role=liveness (no submit)"
  else
    if [[ "$selected" == "$ROLE_SAFETY_DIST" ]]; then
      candidate_key="$far_key"
      echo "  role=safety(distance) submit=farthest"
    elif [[ "$selected" == "$ROLE_SAFETY_EXIST" ]]; then
      rnd_addr=$(cast to-checksum "0x$(openssl rand -hex 20)")
      candidate_key=$(bytes32_from_address "$rnd_addr")
      echo "  role=safety(existence) submit=random_missing"
    else
      candidate_key="$close_key"
      echo "  role=honest submit=closest"
    fi

    cast send --rpc-url "$L1_RPC" --private-key "$submit_pk" --gas-limit 1500000 "$RAT_ADDR" \
      "submitCandidate(address,bytes32,bytes32,bytes32,bytes32,bytes32)" \
      "$game_addr" "$candidate_key" "$state_root" "$version" "$msg_passer_root" "$block_hash" >/dev/null

    # Choose a disputer (prefer an honest validator, random among honest set).
    disputer_addr=""
    disputer_pk=""
    honest_candidates=()
    if [[ "${ROLE_HONEST_1,,}" != "$selected" ]]; then honest_candidates+=("${ROLE_HONEST_1,,}"); fi
    if [[ "${ROLE_HONEST_2,,}" != "$selected" ]]; then honest_candidates+=("${ROLE_HONEST_2,,}"); fi
    if [[ "${#honest_candidates[@]}" -gt 0 ]]; then
      pick=$((RANDOM % ${#honest_candidates[@]}))
      disputer_addr="${honest_candidates[$pick]}"
      disputer_pk="${PK_BY_ADDR[$disputer_addr]}"
    else
      for a in "${validators[@]}"; do
        if [[ "$a" != "$selected" ]]; then
          disputer_addr="$a"
          disputer_pk="${PK_BY_ADDR[$a]}"
          break
        fi
      done
    fi

    SIG_DISPUTE=$(cast keccak "DisputeSuccessful(address,address,bytes32,uint256,string)")

    if [[ "$selected" == "$ROLE_SAFETY_DIST" ]]; then
      # closer-key success
      pobj_raw=$(cast rpc --rpc-url "$L2_RPC" eth_getProof "$close_addr" "[]" "$l2_block_hex")
      pobj=$(parse_result_object "$pobj_raw")
      proof_inner=$(echo "$pobj" | jq -r '.accountProof | join(",")')
      proof="[$proof_inner]"
      dtx=$(cast send --json --rpc-url "$L1_RPC" --private-key "$disputer_pk" --gas-limit 3000000 "$RAT_ADDR" \
        "disputeByCloserKey(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])" \
        "$game_addr" "$close_key" "$state_root" "$version" "$msg_passer_root" "$block_hash" "$proof")
      dtxh=$(echo "$dtx" | jq -r '.transactionHash')
      drec=$(cast receipt --rpc-url "$L1_RPC" --json "$dtxh")
      ds=$(echo "$drec" | jq -r '.status')
      [[ "$ds" == "0x1" || "$ds" == "1" ]] || { echo "Expected closer-key SUCCESS but reverted"; echo "$drec" | jq '.'; exit 1; }
      # parse DisputeSuccessful.amount and accumulate prize
      data=$(echo "$drec" | jq -r --arg rat "${RAT_ADDR,,}" --arg sig "$SIG_DISPUTE" '.logs[] | select((.address|ascii_downcase)==$rat and .topics[0]==$sig) | .data' | head -1)
      if [[ -n "${data:-}" && "$data" != "null" ]]; then
        hex="${data#0x}"
        amt_hex="0x${hex:64:64}"
        amt_dec=$(cast to-dec "$amt_hex")
        PRIZE_WEI_BY_ADDR["$disputer_addr"]=$(( ${PRIZE_WEI_BY_ADDR["$disputer_addr"]:-0} + amt_dec ))
      fi
      echo "  dispute=closer-key (expected success)"
    elif [[ "$selected" == "$ROLE_SAFETY_EXIST" ]]; then
      # non-inclusion success on missing addr
      cand_addr="0x${candidate_key: -40}"
      cand_addr=$(cast to-checksum "$cand_addr")
      pobj_raw=$(cast rpc --rpc-url "$L2_RPC" eth_getProof "$cand_addr" "[]" "$l2_block_hex")
      pobj=$(parse_result_object "$pobj_raw")
      proof_inner=$(echo "$pobj" | jq -r '.accountProof | join(",")')
      proof="[$proof_inner]"
      dtx=$(cast send --json --rpc-url "$L1_RPC" --private-key "$disputer_pk" --gas-limit 3000000 "$RAT_ADDR" \
        "disputeByNonInclusion(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])" \
        "$game_addr" "$candidate_key" "$state_root" "$version" "$msg_passer_root" "$block_hash" "$proof")
      dtxh=$(echo "$dtx" | jq -r '.transactionHash')
      drec=$(cast receipt --rpc-url "$L1_RPC" --json "$dtxh")
      ds=$(echo "$drec" | jq -r '.status')
      [[ "$ds" == "0x1" || "$ds" == "1" ]] || { echo "Expected non-inclusion SUCCESS but reverted"; echo "$drec" | jq '.'; exit 1; }
      data=$(echo "$drec" | jq -r --arg rat "${RAT_ADDR,,}" --arg sig "$SIG_DISPUTE" '.logs[] | select((.address|ascii_downcase)==$rat and .topics[0]==$sig) | .data' | head -1)
      if [[ -n "${data:-}" && "$data" != "null" ]]; then
        hex="${data#0x}"
        amt_hex="0x${hex:64:64}"
        amt_dec=$(cast to-dec "$amt_hex")
        PRIZE_WEI_BY_ADDR["$disputer_addr"]=$(( ${PRIZE_WEI_BY_ADDR["$disputer_addr"]:-0} + amt_dec ))
      fi
      echo "  dispute=non-inclusion (expected success)"
    else
      # honest: optionally try an incorrect dispute (expected failure)
      roll=$((RANDOM % 100))
      if [[ "$roll" -lt "$HONEST_DISPUTE_PROB" ]]; then
        if [[ $((RANDOM % 2)) -eq 0 ]]; then
          pobj_raw=$(cast rpc --rpc-url "$L2_RPC" eth_getProof "$close_addr" "[]" "$l2_block_hex")
          pobj=$(parse_result_object "$pobj_raw")
          proof_inner=$(echo "$pobj" | jq -r '.accountProof | join(",")')
          proof="[$proof_inner]"
          dtx=$(cast send --json --rpc-url "$L1_RPC" --private-key "$disputer_pk" --gas-limit 3000000 "$RAT_ADDR" \
            "disputeByNonInclusion(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])" \
            "$game_addr" "$close_key" "$state_root" "$version" "$msg_passer_root" "$block_hash" "$proof")
          dtxh=$(echo "$dtx" | jq -r '.transactionHash')
          drec=$(cast receipt --rpc-url "$L1_RPC" --json "$dtxh")
          ds=$(echo "$drec" | jq -r '.status')
          [[ "$ds" != "0x1" && "$ds" != "1" ]] || { echo "Expected honest non-inclusion dispute to FAIL but succeeded"; echo "$drec" | jq '.'; exit 1; }
          echo "  honest dispute tried: non-inclusion (expected revert)"
        else
          pobj_raw=$(cast rpc --rpc-url "$L2_RPC" eth_getProof "$far_addr" "[]" "$l2_block_hex")
          pobj=$(parse_result_object "$pobj_raw")
          proof_inner=$(echo "$pobj" | jq -r '.accountProof | join(",")')
          proof="[$proof_inner]"
          dtx=$(cast send --json --rpc-url "$L1_RPC" --private-key "$disputer_pk" --gas-limit 3000000 "$RAT_ADDR" \
            "disputeByCloserKey(address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes[])" \
            "$game_addr" "$far_key" "$state_root" "$version" "$msg_passer_root" "$block_hash" "$proof")
          dtxh=$(echo "$dtx" | jq -r '.transactionHash')
          drec=$(cast receipt --rpc-url "$L1_RPC" --json "$dtxh")
          ds=$(echo "$drec" | jq -r '.status')
          [[ "$ds" != "0x1" && "$ds" != "1" ]] || { echo "Expected honest closer-key dispute to FAIL but succeeded"; echo "$drec" | jq '.'; exit 1; }
          echo "  honest dispute tried: closer-key (expected revert)"
        fi
      fi
    fi
  fi

  log_round "$r"
  persist_prize_state
done

echo ""
echo "== Plot staking graph (matplotlib) =="
echo "CSV: $csv_path"
echo "PNG: $png_path"

# Fetch threshold for plotting.
threshold=$(cast call --rpc-url "$L1_RPC" "$RAT_ADDR" "minimumStakingBalance()(uint256)" | awk '{print $1}')

if [[ "$PLOT" == "1" ]]; then
  if [[ ! -d "$SCRIPT_DIR/../.venv" ]]; then
    echo "Creating venv at .venv"
    python3 -m venv "$SCRIPT_DIR/../.venv"
  fi

  source "$SCRIPT_DIR/../.venv/bin/activate"
  python3 -m pip install --upgrade pip >/dev/null
  python3 -m pip install matplotlib >/dev/null
  python3 "$SCRIPT_DIR/plot_staking.py" "$csv_path" "$png_path" "$threshold" "$roles_path"
fi

echo "Done."

