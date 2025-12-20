#!/bin/bash
set -e

# Run RAT Mini Sensitivity Test
# Iterates through probabilities to test robustness

PROBABILITIES=(0 1000 10000 100000) # 0%, 1%, 10%, 100%
MODE="mini"

echo "Starting RAT Mini Sensitivity Analysis..."

for PROB in "${PROBABILITIES[@]}"; do
    echo "------------------------------------------------"
    echo " RUNNING MINI TEST WITH PROBABILITY: $PROB / 100000"
    echo "------------------------------------------------"

    # Needs a way to inject probability into the experiment runner
    # Currently run_experiment.sh uses hardcoded/default.
    # I will modify run_experiment.sh to accept PROBABILITY argument first.

    echo "Starting experiment with probability $PROB..."
    # Execute the experiment with the specific probability
    # We use 'mini' mode but override the probability
    ./op-rat/scripts/run_experiment.sh --mode=mini --probability=$PROB

    # Store results for this probability
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    mkdir -p "op-rat/results/sensitivity_${PROB}_${TIMESTAMP}"
    mv op-rat/results/mini_*/* "op-rat/results/sensitivity_${PROB}_${TIMESTAMP}/" 2>/dev/null || true

    echo "Completed experiment for probability $PROB."
    echo "Results stored in op-rat/results/sensitivity_${PROB}_${TIMESTAMP}"
    sleep 2
done

