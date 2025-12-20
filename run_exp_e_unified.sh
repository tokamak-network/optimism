#!/bin/bash
set -e

# --- Configuration ---
# Mode: test (3 blocks) or full (10 blocks, 30 validators with regional latency)
MODE="test"
if [ "$1" == "--full" ]; then
    MODE="full"
fi

echo "🚀 Starting Unified Experiment E (Global Scale) - Mode: $MODE"

# Constants - adjusted per mode
if [ "$MODE" == "test" ]; then
    NUM_VALIDATORS=3
    NUM_SPAMMERS=1                # Enable spammer for test mode too
    LIMIT=3
else
    # Full mode: 30 validators with regional latency simulation
    NUM_VALIDATORS=30
    NUM_SPAMMERS=1                # Enable spammer for realistic workload
    LIMIT=300                     # ~10 minutes of blocks (2 sec/block)
    # Regional Latency Configuration (mean, jitter in ms)
    LATENCY_US=20
    JITTER_US=5
    LATENCY_EU=100
    JITTER_EU=20
    LATENCY_ASIA=220
    JITTER_ASIA=30
fi

# --- Auto-detect RPC ports from Kurtosis ---
detect_rpc_ports() {
    echo "🔍 Detecting RPC ports from Kurtosis..."

    KURTOSIS_OUTPUT=$(kurtosis enclave inspect op-devnet 2>/dev/null || echo "")

    if [ -z "$KURTOSIS_OUTPUT" ]; then
        echo "⚠️  Kurtosis enclave 'op-devnet' not found. Using defaults."
        L1_RPC="http://127.0.0.1:8545"
        L2_RPC="http://127.0.0.1:9545"
        L1_BEACON="http://127.0.0.1:4000"
        return
    fi

    # Extract L1 RPC port
    L1_LINE=$(echo "$KURTOSIS_OUTPUT" | grep -A10 "el-1-geth-lighthouse" | grep "rpc:" | grep -v "engine-rpc" | head -1)
    if [ -n "$L1_LINE" ]; then
        L1_PORT=$(echo "$L1_LINE" | sed -E 's/.*127\.0\.0\.1:([0-9]+).*/\1/')
    fi

    if [ -n "$L1_PORT" ]; then
        L1_RPC="http://127.0.0.1:$L1_PORT"
        echo "   ✅ L1 RPC: $L1_RPC"
    else
        L1_RPC="http://127.0.0.1:8545"
        echo "   ⚠️  L1 RPC not found, using default: $L1_RPC"
    fi

    # Extract L2 RPC port
    L2_SERVICE=$(echo "$KURTOSIS_OUTPUT" | grep "op-el-" | head -1)
    # If using multiple lines?
    # Trying simplified grep for op-el
    L2_LINE=$(echo "$KURTOSIS_OUTPUT" | grep -A5 "op-el-" | grep -v "engine-rpc" | grep "rpc:" | head -1)
    if [ -n "$L2_LINE" ]; then
        L2_PORT=$(echo "$L2_LINE" | sed -E 's/.*127\.0\.0\.1:([0-9]+).*/\1/')
    fi

    if [ -n "$L2_PORT" ]; then
        L2_RPC="http://127.0.0.1:$L2_PORT"
    else
        L2_RPC="http://127.0.0.1:9545"
        echo "   ⚠️  L2 RPC not found, using default: $L2_RPC"
    fi

    # Extract L1 Beacon Port
    CL_LINE=$(echo "$KURTOSIS_OUTPUT" | grep -A5 "cl-1-" | grep "http:" | grep -v "metrics" | head -1)
    if [ -n "$CL_LINE" ]; then
        CL_PORT=$(echo "$CL_LINE" | sed -E 's/.*127\.0\.0\.1:([0-9]+).*/\1/')
        if [ -n "$CL_PORT" ]; then
            L1_BEACON="http://127.0.0.1:$CL_PORT"
            echo "   ✅ L1 Beacon: $L1_BEACON"
        else
            L1_BEACON="http://127.0.0.1:4000"
        fi
    else
        L1_BEACON="http://127.0.0.1:4000"
    fi
}

# Detect RPC ports
detect_rpc_ports

ADMIN_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
DEPLOYER_KEY="0x1861eb6d6c8eb73da758d2a24a44313abab04649dfdacc3aade57a7f94e5508f"
DGF_CONTRACT=""
RAT_CONTRACT=""
RESULTS_DIR="results/exp_e_$(date +%Y%m%d_%H%M%S)"
mkdir -p $RESULTS_DIR

# Load Deployed Config if exists
if [ -f deployed_config.env ]; then
    echo "📄 Loading deployed configuration..."
    source deployed_config.env
fi

# --- ethereum-package Pre-funded Accounts (1 billion ETH each) ---
# Source: github.com/ethpandaops/ethereum-package genesis_constants
PREFUNDED_KEY="bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"
PREFUNDED_ADDR="0x8943545177806ED17B9F23F0a21ee5948eCaa776"
CAST=/home/jazz/.foundry/bin/cast
MIN_ADMIN_BALANCE=10000000000000000000  # 10 ETH minimum
REFILL_AMOUNT=100000000000000000000     # 100 ETH refill

# --- Auto-Refill Function ---
refill_admin_if_needed() {
    echo "🔍 Checking Admin balance..."

    # Get Admin address from key
    ADMIN_ADDR=$($CAST wallet address --private-key $ADMIN_KEY 2>/dev/null)
    ADMIN_BAL=$($CAST balance --rpc-url $L1_RPC $ADMIN_ADDR 2>/dev/null || echo "0")

    echo "   Admin ($ADMIN_ADDR): $ADMIN_BAL wei"
    echo "   Minimum required: $MIN_ADMIN_BALANCE wei"

    # Use bc for large number comparison (bash -lt overflows on big ints)
    NEED_REFILL=$(echo "$ADMIN_BAL < $MIN_ADMIN_BALANCE" | bc)

    if [ "$NEED_REFILL" -eq 1 ]; then
        echo "⚠️  Admin balance low! Refilling from prefunded account..."

        # Check prefunded balance
        PREFUNDED_BAL=$($CAST balance --rpc-url $L1_RPC $PREFUNDED_ADDR 2>/dev/null || echo "0")
        echo "   Prefunded ($PREFUNDED_ADDR): $PREFUNDED_BAL wei"

        HAS_FUNDS=$(echo "$PREFUNDED_BAL > $REFILL_AMOUNT" | bc)

        if [ "$HAS_FUNDS" -eq 1 ]; then
            echo "💸 Transferring 100 ETH to Admin..."
            $CAST send --rpc-url $L1_RPC --private-key $PREFUNDED_KEY $ADMIN_ADDR --value $REFILL_AMOUNT --legacy

            NEW_BAL=$($CAST balance --rpc-url $L1_RPC $ADMIN_ADDR 2>/dev/null || echo "0")
            echo "✅ Admin new balance: $NEW_BAL wei (~$(echo "scale=2; $NEW_BAL / 1000000000000000000" | bc) ETH)"
        else
            echo "❌ Prefunded account also empty! Consider Kurtosis reset."
            exit 1
        fi
    else
        echo "✅ Admin balance sufficient (~$(echo "scale=2; $ADMIN_BAL / 1000000000000000000" | bc) ETH)"
    fi
}

# --- 0. Ensure Admin has funds ---
refill_admin_if_needed

# --- 1. Deploy Contracts (if needed) ---
deploy_contracts_if_needed() {
    FORGE=/home/jazz/.foundry/bin/forge
    ADMIN_ADDR=$($CAST wallet address --private-key $ADMIN_KEY)

    # Check if DGF.rat() is properly set
    if [ -n "$DGF_CONTRACT" ] && [ -n "$RAT_CONTRACT" ]; then
        DGF_RAT=$($CAST call --rpc-url $L1_RPC $DGF_CONTRACT "rat()" 2>/dev/null | tail -c 41)
        RAT_LOWER=$(echo $RAT_CONTRACT | tr '[:upper:]' '[:lower:]' | sed 's/0x//')

        if [[ "$DGF_RAT" == *"$RAT_LOWER"* ]]; then
            echo "✅ Contracts already deployed and linked"
            return 0
        fi
    fi

    echo "🔧 Deploying new contracts with ADMIN_KEY as owner..."
    cd /home/jazz/git/optimism/packages/contracts-bedrock

    # Check if compiled artifacts exist (instead of compiling)
    DGF_ARTIFACT="forge-artifacts/DisputeGameFactory.sol/DisputeGameFactory.json"
    RAT_ARTIFACT="forge-artifacts/RAT.sol/RAT.json"

    if [ ! -f "$DGF_ARTIFACT" ] || [ ! -f "$RAT_ARTIFACT" ]; then
        echo "❌ Compiled artifacts not found!"
        echo "   Please run 'forge build' first before running this script."
        echo "   Missing:"
        [ ! -f "$DGF_ARTIFACT" ] && echo "   - $DGF_ARTIFACT"
        [ ! -f "$RAT_ARTIFACT" ] && echo "   - $RAT_ARTIFACT"
        exit 1
    fi
    echo "  ✅ Compiled artifacts found, proceeding with deployment..."

    # Deploy DGF
    echo "  📦 Deploying DisputeGameFactory..."
    DGF_DEPLOY=$($FORGE create src/dispute/DisputeGameFactory.sol:DisputeGameFactory \
        --rpc-url $L1_RPC --private-key $ADMIN_KEY --legacy --broadcast 2>&1)

    # Parse deployed address from forge output (format: Deployed to: 0x...)
    NEW_DGF=$(echo "$DGF_DEPLOY" | grep -oP 'Deployed to: \K0x[a-fA-F0-9]+' | head -1)

    if [ -z "$NEW_DGF" ]; then
        echo "❌ DGF deployment failed"
        echo "$DGF_DEPLOY"
        exit 1
    fi
    echo "  ✅ DGF deployed: $NEW_DGF"

    # Initialize DGF with ADMIN as owner
    echo "  🔑 Initializing DGF..."
    # Try initialize, but ignore error if already initialized (check owner later)
    # Redirect output to /dev/null to keep console clean, errors captured if needed via owner check
    $CAST send --rpc-url $L1_RPC --private-key $ADMIN_KEY $NEW_DGF "initialize(address)" $ADMIN_ADDR --legacy > /dev/null 2>&1 || true

    # Verify DGF Owner
    OWNER=$($CAST call --rpc-url $L1_RPC $NEW_DGF "owner()(address)")
    # Normalize addresses to lowercase for comparison (simple grep check)
    if ! echo "$OWNER" | grep -qi "${ADMIN_ADDR:2}"; then
        echo "❌ DGF Owner mismatch! Expected $ADMIN_ADDR, Got $OWNER"
        echo "   DGF Initialization failed."
        exit 1
    fi
    echo "  ✅ DGF Owner Verified: $OWNER"

    # Deploy MinimalGame (Mock Game)
    echo "  📦 Deploying MinimalGame Game..."
    FAKE_LOG="deploy_fake.log"
    FAKE_DEPLOY=$($FORGE create src/L1/MinimalGame.sol:MinimalGame \
        --rpc-url $L1_RPC --private-key $ADMIN_KEY --legacy --broadcast 2>&1 | tee $FAKE_LOG)
    NEW_FAKE=$(echo "$FAKE_DEPLOY" | grep -oP 'Deployed to: \K0x[a-fA-F0-9]+' | head -1)

    if [ -z "$NEW_FAKE" ]; then
        echo "❌ MinimalGame deployment failed. See $FAKE_LOG for details."
        exit 1
    fi
    echo "  ✅ MinimalGame deployed: $NEW_FAKE"

    # Set Implementation (GameType 0)
    echo "  ⚙️ Setting Game Implementation (Type 0)..."
    $CAST send --rpc-url $L1_RPC --private-key $ADMIN_KEY $NEW_DGF "setImplementation(uint32,address)" 0 $NEW_FAKE --legacy > /dev/null 2>&1

    # Set Init Bond (0)
    $CAST send --rpc-url $L1_RPC --private-key $ADMIN_KEY $NEW_DGF "setInitBond(uint32,uint256)" 0 0 --legacy > /dev/null 2>&1

    # Deploy RAT (Hide verbose output)
    echo "  📦 Deploying RAT..."
    RAT_LOG="deploy_rat.log"
    RAT_DEPLOY=$($FORGE create src/L1/RAT.sol:RAT \
        --rpc-url $L1_RPC --private-key $ADMIN_KEY --legacy --broadcast 2>&1 | tee $RAT_LOG)
    NEW_RAT=$(echo "$RAT_DEPLOY" | grep -oP 'Deployed to: \K0x[a-fA-F0-9]+' | head -1)

    if [ -z "$NEW_RAT" ]; then
        echo "❌ RAT deployment failed. See $RAT_LOG for details."
        exit 1
    fi
    echo "  ✅ RAT deployed: $NEW_RAT"

    # Initialize RAT with 6 parameters:
    # - _disputeGameFactory: NEW_DGF
    # - _perTestBondAmount: 0.1 ether (100000000000000000 wei)
    # - _evidenceSubmissionPeriod: 250 blocks
    # - _minimumStakingBalance: 0.1 ether
    # - _ratTriggerProbability: 100000 (100%)
    # - _ratManager: ADMIN_ADDR
    echo "  🔑 Initializing RAT..."
    BOND_AMOUNT=100000000000000000        # 0.1 ether
    EVIDENCE_PERIOD=250                    # blocks
    MIN_STAKE=1000000000000000000          # 1 ether (increased for long experiments)
    RAT_PROBABILITY=100000                 # 100% (MAX_PROBABILITY = 100000)

    $CAST send --rpc-url $L1_RPC --private-key $ADMIN_KEY $NEW_RAT \
        "initialize(address,uint256,uint256,uint256,uint256,address)" \
        $NEW_DGF $BOND_AMOUNT $EVIDENCE_PERIOD $MIN_STAKE $RAT_PROBABILITY $ADMIN_ADDR --legacy > /dev/null 2>&1

    # Link DGF -> RAT
    echo "  🔗 Linking DGF to RAT (setRAT)..."
    $CAST send --rpc-url $L1_RPC --private-key $ADMIN_KEY $NEW_DGF "setRAT(address)" $NEW_RAT --legacy > /dev/null 2>&1

    # Verify RAT setup in DGF
    VERIFY_RAT=$($CAST call --rpc-url $L1_RPC $NEW_DGF "rat()(address)")
    if ! echo "$VERIFY_RAT" | grep -qi "${NEW_RAT:2}"; then
         echo "❌ Link Verification Failed! DGF.rat() = $VERIFY_RAT, Expected $NEW_RAT"
         exit 1
    fi
    echo "  ✅ DGF linked to RAT successfully"

    # Update config
    DGF_CONTRACT=$NEW_DGF
    RAT_CONTRACT=$NEW_RAT

    # Save to deployed_config.env
    cd /home/jazz/git/optimism
    cat > deployed_config.env << EOF
L1_RPC=$L1_RPC
L2_RPC=$L2_RPC
ADMIN_KEY=$ADMIN_KEY
DEPLOYER_KEY=$DEPLOYER_KEY
DGF_CONTRACT=$NEW_DGF
RAT_CONTRACT=$NEW_RAT
EOF
    echo "  💾 Updated deployed_config.env"

    echo "✅ Contracts deployed and linked successfully!"
}

# Check and deploy contracts
deploy_contracts_if_needed

# --- 2. Build Binaries ---
echo "🔨 Building binaries..."
make op-challenger > /dev/null 2>&1 && echo "  ✅ op-challenger built" || { echo "  ❌ op-challenger build failed"; exit 1; }
go build -o bin/rat-proposer ./op-rat/cmd/rat-proposer > /dev/null 2>&1 && echo "  ✅ rat-proposer built"
go build -o bin/rat-spammer ./op-rat/cmd/rat-spammer > /dev/null 2>&1 && echo "  ✅ rat-spammer built"
go build -o bin/generate_accounts op-rat/cmd/generate_accounts.go > /dev/null 2>&1 && echo "  ✅ generate_accounts built"

# --- 2. Generate & Fund Accounts ---
echo "💰 Generating funding for $NUM_VALIDATORS Validators & $NUM_SPAMMERS Spammers..."
# Use PREFUNDED_KEY for funding (clean nonce history, no tx pool conflicts)
# Fund 3 ETH per validator (covers 1 ETH stake + gas + bond deductions)
./bin/generate_accounts --validators=$NUM_VALIDATORS --spammers=$NUM_SPAMMERS --admin-key=$PREFUNDED_KEY --l1-rpc=$L1_RPC --fund=3000000000000000000 --out="accounts.json"

# Wait for funding transactions to be mined
echo "⏳ Waiting for funding transactions to be mined (5s)..."
sleep 5

# --- 3. Start Proposer (Single Instance) ---
LIMIT=3
if [ "$MODE" == "full" ]; then
    LIMIT=50
fi

# Extract Proposer Key from accounts.json
PROPOSER_KEY=$(python3 -c "import json; print(json.load(open('accounts.json'))['proposer'])")
PROPOSER_ADDR=$($CAST wallet address --private-key $PROPOSER_KEY)

# Wait for Proposer Funding
echo "  💰 Checking Proposer balance: $PROPOSER_ADDR"
for i in {1..30}; do
    BAL=$($CAST balance --rpc-url $L1_RPC $PROPOSER_ADDR)
    if [ "$BAL" != "0" ]; then
        echo "  ✅ Funding confirmed: $BAL wei"
        break
    fi
    echo "  ⏳ Waiting for funding... (Attempt $i/30)"
    sleep 2
done

if [ "$BAL" == "0" ]; then
   echo "❌ Proposer not funded! Check L1 node or Admin balance."
   exit 1
fi
# Proposer start moved to after Validators

# --- 3. Start Proposer (Initial Game for Staking) ---
echo "🎬 Starting Proposer (Initial Game for Staking)..."
./bin/rat-proposer \
    --l1-rpc=$L1_RPC \
    --l2-rpc=$L2_RPC \
    --dgf-contract=$DGF_CONTRACT \
    --private-key=$PROPOSER_KEY \
    --limit=1 2>&1 | tee $RESULTS_DIR/proposer_init.log | grep --line-buffered -E "✅|❌|Game Created|Create FAILED|finished" &
INITIAL_PID=$!
wait $INITIAL_PID
echo "✅ Initial Game Created. Allowing Validators to Stake..."

# --- 4. Start Validators (Multi-Region) ---
echo "🌍 Starting $NUM_VALIDATORS Validators..."
cp accounts.json $RESULTS_DIR/accounts.json

# Launch in background using python to parse keys
for i in $(seq 0 $(($NUM_VALIDATORS - 1))); do
    KEY=$(python3 -c "import json; print(json.load(open('accounts.json'))['validators'][$i])")

    # Assign Region and Latency
    if [ $i -lt 10 ]; then
        REGION="US"
        LATENCY=${LATENCY_US:-0}
        JITTER=${JITTER_US:-0}
    elif [ $i -lt 20 ]; then
        REGION="EU"
        LATENCY=${LATENCY_EU:-0}
        JITTER=${JITTER_EU:-0}
    else
        REGION="ASIA"
        LATENCY=${LATENCY_ASIA:-0}
        JITTER=${JITTER_ASIA:-0}
    fi

    ID=$(printf "VAL-%s-%02d" $REGION $((i % 10)))

    # Run op-challenger with latency flags
    ./op-challenger/bin/op-challenger \
        --l1-eth-rpc "$L1_RPC" \
        --l1-beacon "$L1_BEACON" \
        --l2-eth-rpc "$L2_RPC" \
        --rollup-rpc "$L1_RPC" \
        --game-factory-address "$DGF_CONTRACT" \
        --rat-contract "$RAT_CONTRACT" \
        --datadir "val_db_$i" \
        --trace-type "alphabet" \
        --private-key "$KEY" \
        --num-confirmations 1 \
        --virtual-latency $LATENCY \
        --jitter $JITTER \
        --region-id "$ID" \
        > "$RESULTS_DIR/validator_$ID.log" 2>&1 &

    # echo "  Started $ID (latency=${LATENCY}ms, jitter=${JITTER}ms)"
done

# Wait for Validators to Stake
echo "⏳ Waiting for Validators to Stake (20s)..."
sleep 20

# --- 5. Start Proposer (Main Run) ---
echo "🎬 Starting Proposer (Main Run: $LIMIT blocks) with Key: ${PROPOSER_KEY:0:10}..."
./bin/rat-proposer \
    --l1-rpc=$L1_RPC \
    --l2-rpc=$L2_RPC \
    --dgf-contract=$DGF_CONTRACT \
    --private-key=$PROPOSER_KEY \
    --limit=$LIMIT 2>&1 | tee $RESULTS_DIR/proposer.log | grep --line-buffered -E "✅|❌|Game Created|Create FAILED|finished" &
PROPOSER_PID=$!

# --- 6. Start Spammer Load ---
echo "🔥 Starting Spammer Load (TPS Target: Scaling)..."
# We run spammer with ADMIN key for now to ensure reliability (since generate_accounts funds random keys but rat-spammer uses mnemonic)
# To simulate "1000 accounts", rat-spammer usually derives them from mnemonic.
# We'll rely on rat-spammer's internal derivation.
# NOTE: Accounts derived by rat-spammer might not be funded if they differ from generate_accounts logic.
# CRITICAL: generate_accounts funded RANDOM keys. rat-spammer uses MNEMONIC. They trace to DIFFERENT accounts.
# HOTFIX: We will run rat-spammer with --private-key ADMIN and rely on its internal nonce management for HIGH TPS.
# For true 1000-account simulation, we would need to feed keys to spammer, but rat-spammer code modification is out of scope for Exp E speed.
# We prioritize TPS Load over Account Diversity for the spammer side. (Validator side diversity is key).

# Spammer with variable TPS: 100 TPS ± 30%
TARGET_TPS=100
VARIANCE=0.3
if [ "$MODE" == "test" ]; then TARGET_TPS=50; fi  # Lower for test mode

./bin/rat-spammer \
    --rpc=$L2_RPC \
    --private-key=$ADMIN_KEY \
    --tps=$TARGET_TPS \
    --variance=$VARIANCE \
    --accounts=1000 \
    --batch-size=100 > $RESULTS_DIR/spammer.log 2>&1 &
SPAMMER_PID=$!

# --- 6. Wait & Cleanup ---
echo "⏳ Waiting for Proposer to finish $LIMIT blocks..."
wait $PROPOSER_PID

# Wait for Validators to process the last game
echo "⏳ Waiting for Validators to process last game (15s)..."
sleep 15

echo "🛑 Stopping experiment..."
kill $(jobs -p) 2>/dev/null || true

# Summary
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "📊 EXPERIMENT RESULTS SUMMARY"
echo "══════════════════════════════════════════════════════════════"
echo ""

# Proposer Results
CREATES_SUCCESS=$(grep -c "✅ Game Created. Status=SUCCESS" $RESULTS_DIR/proposer.log 2>/dev/null || echo "0")
CREATES_FAILED=$(grep -c "❌ Create FAILED" $RESULTS_DIR/proposer.log 2>/dev/null || echo "0")
echo "📤 PROPOSER:"
echo "   ✅ Games Created (SUCCESS): $CREATES_SUCCESS"
echo "   ❌ Games Failed: $CREATES_FAILED"

# Show RAT Selections from On-Chain
echo ""
echo "🎯 RAT SELECTIONS (On-Chain):"
for vlog in $RESULTS_DIR/validator_*.log; do
    if [ -f "$vlog" ]; then
        VNAME=$(basename $vlog .log | sed 's/validator_//')
        VADDR=$(grep "RAT Monitor watching" "$vlog" | grep -oP 'me=\K0x[a-fA-F0-9]+' | head -1)
        # Find games this validator was selected for
        SELECTED=$(grep "🎯 I am the selected challenger" -B1 "$vlog" | grep "RAT Event Scanned" | grep -oP 'game=\K0x[a-fA-F0-9]+' | head -5)
        for GAME in $SELECTED; do
            # Check if evidence was submitted for this game (use short address for matching)
            GAME_SHORT=${GAME:0:10}
            EVIDENCE_OK=$(grep "$GAME_SHORT" "$vlog" | grep -c "Evidence Submitted Successfully" 2>/dev/null || echo "0")
            EVIDENCE_OK=$(echo "$EVIDENCE_OK" | tr -d '\n' | tr -d ' ')
            if [ -z "$EVIDENCE_OK" ]; then EVIDENCE_OK=0; fi
            if [ "$EVIDENCE_OK" -gt 0 ] 2>/dev/null; then
                echo "   🎮 Game: ${GAME:0:10}... -> $VNAME: ✅ Evidence Submitted"
            else
                EVIDENCE_ERR=$(grep -A10 "$GAME_SHORT" "$vlog" | grep -oP 'Failed to submit evidence.*err="\K[^"]+' | head -1)
                if [ -n "$EVIDENCE_ERR" ]; then
                    echo "   🎮 Game: ${GAME:0:10}... -> $VNAME: ❌ Failed ($EVIDENCE_ERR)"
                else
                    echo "   🎮 Game: ${GAME:0:10}... -> $VNAME: ⚠️ Pending/Unknown"
                fi
            fi
        done
    fi
done

# Validator Results - count RAT selections (I am the selected challenger) and proof submissions
echo ""
echo "📥 VALIDATORS:"
TOTAL_RAT_SELECTED=0
TOTAL_PROOFS_SUCCESS=0
for vlog in $RESULTS_DIR/validator_*.log; do
    if [ -f "$vlog" ]; then
        VNAME=$(basename $vlog .log)
        # Count RAT events detected (scanned)
        GAMES_DETECTED=$(grep -c "RAT Event Scanned" "$vlog" 2>/dev/null | tr -d '\n' || echo "0")
        # RAT selected = when I am the chosen challenger
        RAT_SELECTED=$(grep -c "🎯 I am the selected challenger" "$vlog" 2>/dev/null | tr -d '\n' || echo "0")
        PROOFS_SUCCESS=$(grep -ci "Evidence Submitted Successfully\|CONTRACT VALID" "$vlog" 2>/dev/null | tr -d '\n' || echo "0")
        # Ensure clean integers
        RAT_SELECTED=${RAT_SELECTED:-0}
        PROOFS_SUCCESS=${PROOFS_SUCCESS:-0}
        TOTAL_RAT_SELECTED=$((TOTAL_RAT_SELECTED + RAT_SELECTED))
        TOTAL_PROOFS_SUCCESS=$((TOTAL_PROOFS_SUCCESS + PROOFS_SUCCESS))
        echo "   $VNAME: Detected=$GAMES_DETECTED, Selected=$RAT_SELECTED, Proofs=$PROOFS_SUCCESS"
        # Show which games this validator was selected for
        if [ "$RAT_SELECTED" -gt 0 ]; then
            SELECTED_GAMES=$(grep "🎯 I am the selected challenger" -B1 "$vlog" | grep "RAT Event Scanned" | sed 's/.*game=\([^ ]*\).*/     -> Game: \1/')
            echo "$SELECTED_GAMES"
        fi
    fi
done

echo ""

# --- RAT Debug Analysis (On-Chain) ---
echo "🔍 RAT ON-CHAIN DEBUG DIAGNOSTICS:"
# Hex signatures for debug messages
# "Event Emitted": 4576656e7420456d6974746564
# "Len Check Fail": 4c656e20436865636b204661696c
# "ShouldTrigger Failed": 53686f756c6454726967676572204661696c6564
# "No Participants": 4e6f205061727469636970616e7473

# Fetch logs from start
DEBUG_LOGS=$(cast logs --rpc-url $L1_RPC --address $RAT_CONTRACT --from-block 0 "DebugRAT(string,uint256)" 2>/dev/null)

ONCHAIN_SEL=$(echo "$DEBUG_LOGS" | grep -i "4576656e7420456d6974746564" | wc -l)
LEN_FAIL=$(echo "$DEBUG_LOGS" | grep -i "4c656e20436865636b204661696c" | wc -l)
PROB_FAIL=$(echo "$DEBUG_LOGS" | grep -i "53686f756c6454726967676572204661696c6564" | wc -l)
NO_PART=$(echo "$DEBUG_LOGS" | grep -i "4e6f205061727469636970616e7473" | wc -l)

echo "   ✅ Actual Selections (On-Chain): $ONCHAIN_SEL"
if [ "$ONCHAIN_SEL" == "0" ]; then
    echo "   ⚠️  FAILURE REASONS:"
    echo "      - No Participants: $NO_PART"
    echo "      - Probability Check Failed: $PROB_FAIL"
    echo "      - Participant Length Check Failed: $LEN_FAIL"
else
    echo "   🎉 RAT Logic is Working correctly on L1!"
    if [ "$TOTAL_RAT_SELECTED" == "0" ]; then
            echo "   ⚠️  Note: Validators missed detection (likely Client Binding/ABI mismatch). Trust On-Chain count."
    fi
fi

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "📊 FINAL SCORE:"
echo "   Games Created: $CREATES_SUCCESS"
echo "   RAT Selections (Total): $TOTAL_RAT_SELECTED"
echo "   Proofs Submitted (Total): $TOTAL_PROOFS_SUCCESS"
echo ""

# PASS criteria: Games created > 0 AND (RAT selections == Proofs OR no selections yet)
if [ "$CREATES_SUCCESS" -gt 0 ] && [ "$TOTAL_RAT_SELECTED" -gt 0 ] && [ "$TOTAL_RAT_SELECTED" -eq "$TOTAL_PROOFS_SUCCESS" ]; then
    echo "✅ Experiment E ($MODE) PASSED - All RAT challenges verified!"
elif [ "$CREATES_SUCCESS" -gt 0 ] && [ "$TOTAL_RAT_SELECTED" -eq 0 ]; then
    echo "⚠️  Experiment E ($MODE) PARTIAL - Games created but no RAT selections yet"
else
    echo "❌ Experiment E ($MODE) FAILED"
    echo "   - Games: $CREATES_SUCCESS, RAT Selected: $TOTAL_RAT_SELECTED, Proofs: $TOTAL_PROOFS_SUCCESS"
fi
echo "   Full Logs: $RESULTS_DIR/"
echo "══════════════════════════════════════════════════════════════"

# --- Spammer TPS Summary ---
if [ -f "$RESULTS_DIR/spammer.log" ]; then
    TOTAL_BURSTS=$(grep -c "Burst: Sent" $RESULTS_DIR/spammer.log 2>/dev/null || echo "0")
    if [ "$TOTAL_BURSTS" -gt 0 ]; then
        TOTAL_TXS=$(grep "Burst: Sent" $RESULTS_DIR/spammer.log | grep -oP 'Sent \K\d+' | paste -sd+ | bc)
        AVG_TPS=$(echo "scale=2; $TOTAL_TXS / $TOTAL_BURSTS" | bc)
        echo ""
        echo "📊 SPAMMER STATISTICS:"
        echo "   Total Transactions: $TOTAL_TXS"
        echo "   Total Bursts: $TOTAL_BURSTS (~${TOTAL_BURSTS}s)"
        echo "   Average TPS: $AVG_TPS"
    fi
fi

# --- RAT Experiment Timing Metrics Extraction ---
if [ "$MODE" == "full" ]; then
    echo ""
    echo "📈 RAT Experiment TIMING METRICS:"
    echo "region,T_proc_ms,T_net_ms,T_total_ms" > "$RESULTS_DIR/timing_metrics.csv"

    for vlog in $RESULTS_DIR/validator_*.log; do
        if [ -f "$vlog" ]; then
            # Extract timing metrics from log: "Evidence Submitted Successfully" lines with T_proc_ms, T_net_ms, T_total_ms
            grep "Evidence Submitted Successfully" "$vlog" | while read -r line; do
                REGION=$(echo "$line" | grep -oP 'region=\K[^ ]+' | tr -d '"')
                T_PROC=$(echo "$line" | grep -oP 'T_proc_ms=\K[0-9]+')
                T_NET=$(echo "$line" | grep -oP 'T_net_ms=\K[0-9]+')
                T_TOTAL=$(echo "$line" | grep -oP 'T_total_ms=\K[0-9]+')
                if [ -n "$REGION" ] && [ -n "$T_PROC" ]; then
                    echo "$REGION,$T_PROC,$T_NET,$T_TOTAL" >> "$RESULTS_DIR/timing_metrics.csv"
                fi
            done
        fi
    done

    # Display summary statistics
    if [ -f "$RESULTS_DIR/timing_metrics.csv" ]; then
        echo "   📊 Timing metrics saved to: $RESULTS_DIR/timing_metrics.csv"
        echo ""
        echo "   Region Summary (avg T_total_ms):"
        for region in US EU ASIA; do
            AVG=$(grep "^VAL-$region" "$RESULTS_DIR/timing_metrics.csv" | awk -F, '{sum+=$4; count++} END {if(count>0) print int(sum/count); else print "N/A"}')
            echo "      $region: ${AVG}ms"
        done
    fi
fi
