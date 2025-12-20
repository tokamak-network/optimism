#!/bin/bash
set -e

# RAT Experiment Orchestrator (Top-Tier Standard)
# Directory: op-rat/scripts/run_experiment.sh
# Usage:
#   Simulation: ./op-rat/scripts/run_experiment.sh --mode=[mini|full]
#   Live RPC:   ./op-rat/scripts/run_experiment.sh --mode=live --rpc=...
#   Auto Devnet: ./op-rat/scripts/run_experiment.sh --mode=auto[-mini]
#   Live L1:    ./op-rat/scripts/run_experiment.sh --mode=live-l1

MODE="mini"
RPC_URL="http://127.0.0.1:8545"
ENCLAVE_NAME="rat-kurtosis"
RUN_SIMULATION_LOOP=true
LIMIT=0

for arg in "$@"
do
    case $arg in
        --mode=*)
        MODE="${arg#*=}"
        shift
        ;;
        --rpc=*)
        RPC_URL="${arg#*=}"
        shift
        ;;
        --probability=*)
        PROBABILITY="${arg#*=}"
        shift
        ;;
    esac
done

if [ -z "$PROBABILITY" ]; then
    PROBABILITY=1000 # Default 1%
fi

echo "Starting RAT Advanced Experiment (Mode: $MODE)..."

# Navigate to Monorepo Root
cd "$(dirname "$0")/../.."
ROOT_KEY=$(pwd)

# 1. Build Components
echo "[1/4] Building Components..."
go build -o bin/rat-validator ./op-rat/cmd/rat-validator

if [[ "$MODE" != "live" && "$MODE" != "live-mini" && "$MODE" != "live-l1" && "$MODE" != "auto" && "$MODE" != "auto-mini" ]]; then
    go build -o bin/rat-proposer ./op-rat/cmd/rat-proposer
else
    RUN_SIMULATION_LOOP=false
fi



echo "[1.5/4] Building Spammer..."
go build -o bin/rat-spammer ./op-rat/cmd/rat-spammer
if [ ! -f "bin/rat-spammer" ]; then
    echo "Spammer Build failed!"
    exit 1
fi

# ==========================================
# SETUP: PREPARE ENVIRONMENT
# ==========================================

# AUTO SETUP
if [[ "$MODE" == "auto" || "$MODE" == "auto-mini" ]]; then
    echo "=========================================="
    echo " WRAPPING UP KURTOSIS DEVNET..."
    echo "=========================================="

    if ! command -v kurtosis &> /dev/null; then
        echo "Error: 'kurtosis' command not found."
        exit 1
    fi

    # Start Enclave
    if kurtosis enclave inspect "$ENCLAVE_NAME" >/dev/null 2>&1; then
        echo "Enclave '$ENCLAVE_NAME' already exists. Reusing it."
    else
        echo "Creating new enclave..."
        if ! kurtosis run --enclave "$ENCLAVE_NAME" github.com/ethpandaops/optimism-package; then
            echo "ERROR: KURTOSIS FAILED TO START. Try 'kurtosis clean -a'"
            exit 1
        fi
    fi

    # Fetch Port
    echo "Fetching RPC Port..."
    # 1. Find the accurate Service Name for L2 Geth
    L2_SERVICE_NAME=$(kurtosis enclave inspect "$ENCLAVE_NAME" | grep "op-el-.*-op-geth" | awk '{print $2}' | head -n 1)

    if [ ! -z "$L2_SERVICE_NAME" ]; then
        echo "Found L2 Service: $L2_SERVICE_NAME"
        # 2. Get RPC Port for this service
        RPC_PORT=$(kurtosis port print "$ENCLAVE_NAME" "$L2_SERVICE_NAME" rpc 2>/dev/null || echo "")
        if [ -z "$RPC_PORT" ]; then
             # Try 'http' if rpc fails
             RPC_PORT=$(kurtosis port print "$ENCLAVE_NAME" "$L2_SERVICE_NAME" http 2>/dev/null || echo "")
        fi
    fi

    if [ -z "$RPC_PORT" ]; then
        # Last Resort: Fallback to L1 (but warn user)
        echo "Warning: Could not find L2 RPC. Trying L1 (el-1)..."
        RPC_PORT=$(kurtosis port print "$ENCLAVE_NAME" el-1-geth-lighthouse rpc | head -n 1)
    fi

    if [ -z "$RPC_PORT" ]; then
         echo "Failed to detect RPC port."
         exit 1
    fi

    # Smart URL Construction - kurtosis port print usually returns full http://url, but sometimes just port
    if [[ "$RPC_PORT" == http* ]]; then
        RPC_URL="$RPC_PORT"
    elif [[ "$RPC_PORT" == *":"* ]]; then
        RPC_URL="http://$RPC_PORT"
    else
        RPC_URL="http://127.0.0.1:$RPC_PORT"
    fi
    echo "Detected RPC URL: $RPC_URL"

    # Configure Limits
    if [ "$MODE" == "auto-mini" ]; then
        LIMIT=10
        echo " TEST MODE: Stopping after 10 blocks."
    fi

    # Start Spammer in Background for Load Generation
    echo "Starting Traffic Generator (Spammer)..."
    # Use L2 RPC for Spammer
    ./bin/rat-spammer --rpc="$RPC_URL" --txs=5 --interval=2s > "$RESULT_DIR/logs/rat_spammer.log" 2>&1 &
    SPAMMER_PID=$!
    echo "Spammer PID: $SPAMMER_PID"
fi

# LIVE SETUP
if [[ "$MODE" == "live" || "$MODE" == "live-mini" ]]; then
    echo "=========================================="
    echo " CONNECTING TO LIVE NETWORK ($RPC_URL)"
    echo "=========================================="
    if [ "$MODE" == "live-mini" ]; then
        LIMIT=10
        echo " TEST MODE: Stopping after 10 blocks."
    fi
fi

# LIVE L1 SETUP (Requires Kurtosis)
if [[ "$MODE" == "live-l1" ]]; then
    echo "=========================================="
    echo " CONFIGURING LIVE L1 INTEGRATION"
    echo "=========================================="

    # 1. Detect L1 RPC
    L1_RPC_PORT=$(kurtosis port print "$ENCLAVE_NAME" el-1-geth-lighthouse rpc | head -n 1)
     if [[ "$L1_RPC_PORT" == http* ]]; then
        L1_RPC_URL="$L1_RPC_PORT"
     elif [[ "$L1_RPC_PORT" == *":"* ]]; then
        L1_RPC_URL="http://$L1_RPC_PORT"
    else
        L1_RPC_URL="http://127.0.0.1:$L1_RPC_PORT"
    fi
    echo " Detected L1 RPC: $L1_RPC_URL"

    # 2. Detect L2 RPC (Re-use logic if needed, or assume default/user provided)
    # If user didn't provide --rpc, try to auto-detect L2 as well
    if [ "$RPC_URL" == "http://127.0.0.1:8545" ]; then
         L2_RPC_PORT=$(kurtosis port print "$ENCLAVE_NAME" op-el-2151908-node0-op-geth rpc | head -n 1)
         if [[ "$L2_RPC_PORT" == http* ]]; then
             RPC_URL="$L2_RPC_PORT"
         elif [[ "$L2_RPC_PORT" == *":"* ]]; then
            RPC_URL="http://$L2_RPC_PORT"
        else
            RPC_URL="http://127.0.0.1:$L2_RPC_PORT"
        fi
        echo " Auto-Detected L2 RPC: $RPC_URL"
    fi

    # 3. Credentials (Hardcoded for Experiment)
    RAT_CONTRACT="0xd20d4d6918cf1f71f066f40c13e4c6d33b7fb134"
    # Batcher Private Key (No 0x)
    L1_PRIV_KEY="b3d2d558e3491a3709b7c451100a0366b5872520c7aa020c17a0e7fa35b6a8df"

    LIMIT=5
    echo " L1 Mode Active. Limit: $LIMIT blocks."
fi

# ==========================================
# CONFIGURATION
# ==========================================

# Create Result Directory (Timestamped)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULT_DIR="op-rat/results/${MODE}_${TIMESTAMP}"
mkdir -p "$RESULT_DIR/da_data"
mkdir -p "$RESULT_DIR/logs"

# ==========================================
# EXECUTION
# ==========================================

if [ "$RUN_SIMULATION_LOOP" = false ]; then
    # --- LIVE Execution Path ---
    echo ">>> Running Live Validator (Limit: $LIMIT) <<<"

    # Run Validator directly (Wait for it to finish)
    if [ "$MODE" == "live-l1" ]; then
         ./bin/rat-validator --source=rpc --rpc="$RPC_URL" --region="us-east" --limit=$LIMIT \
            --use-l1 --l1-rpc="$L1_RPC_URL" --rat-contract="$RAT_CONTRACT" --private-key="$L1_PRIV_KEY"
    else
         ./bin/rat-validator --source=rpc --rpc="$RPC_URL" --region="us-east" --limit=$LIMIT --probability=$PROBABILITY
    fi

    # Check if CSV was created
    if ls rat_validator_result_*.csv 1> /dev/null 2>&1; then
        echo "Data collected successfully."
    else
        echo "Warning: No CSV data found. Did the validator run long enough?"
    fi

else
    # --- SIMULATION Execution Path ---
    if [ "$MODE" == "full" ]; then
        BATCH_SIZES=(50 2000 10000); ITERATIONS=1000
        REGIONS=("us-east" "us-west" "eu-central" "sa-east" "ap-northeast")
    else
        BATCH_SIZES=(10); ITERATIONS=10
        REGIONS=("us-east" "eu-central")
    fi

    for BATCH_SIZE in "${BATCH_SIZES[@]}"; do
        echo ">>> Running Scale Scenario: Batch Size = $BATCH_SIZE Txs <<<"

        # Start Proposer
        ./bin/rat-proposer -txs=$BATCH_SIZE -da="$RESULT_DIR/da_data" > "$RESULT_DIR/logs/rat_proposer.log" 2>&1 &
        PROPOSER_PID=$!
        sleep 5

        # Start Validators
        PIDS=()
        for REGION in "${REGIONS[@]}"; do
            ./bin/rat-validator -region=$REGION -da="$RESULT_DIR/da_data" -probability=$PROBABILITY >> "$RESULT_DIR/logs/rat_validator_$REGION.log" 2>&1 &
            PIDS+=($!)
        done

        # Wait
        WAIT_TIME=$((ITERATIONS * 1 + 10))
        if [ "$MODE" == "mini" ]; then WAIT_TIME=15; fi
        echo "    Collecting data for $WAIT_TIME seconds..."
        sleep $WAIT_TIME

        # Cleanup
        kill $PROPOSER_PID 2>/dev/null
        for PID in "${PIDS[@]}"; do kill $PID 2>/dev/null; done
        wait
    done
fi

# ==========================================
# CLEANUP & VISUALIZATION (Unified)
# ==========================================

# Kill Spammer if running
if [ ! -z "$SPAMMER_PID" ]; then
    echo "Stopping Spammer..."
    kill $SPAMMER_PID 2>/dev/null || true
fi

# Move generated CSVs to Result Dir
mv rat_validator_result_*.csv "$RESULT_DIR/" 2>/dev/null || true

echo "[4/4] Generating Plots..."
if [ ! -d ".venv" ]; then
    echo "Creating python venv..."
    python3 -m venv .venv
    source .venv/bin/activate
    pip install pandas matplotlib seaborn > /dev/null 2>&1
else
    source .venv/bin/activate
fi

cp op-rat/scripts/plot_results.py "$RESULT_DIR/"
cd "$RESULT_DIR"

# Run Plot Script
# echo "Running Python Plotter..."
# if python3 plot_results.py --output=rat_performance_graphs.pdf; then
#     echo "=========================================="
#     echo " SUCCESS! Experiment Complete."
#     echo " Graph: $RESULT_DIR/rat_performance_graphs.pdf"
#     echo "=========================================="
# else
#     echo "Warning: Plot generation failed (maybe insufficient data?)"
# fi
