# RAT Protocol Experiment

Randomized Attention Test (RAT) protocol implementation on Optimism L2 rollup.

## Overview

RAT is a cryptoeconomic mechanism for randomly selecting and verifying validators in an L2 rollup environment. This branch contains the complete experiment infrastructure for testing RAT protocol performance.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                         KURTOSIS (Infrastructure)                  │
│   ┌───────────────────────────────────────────────────────────┐   │
│   │                        L1 (Geth)                          │   │
│   │   ┌─────────────────┐   ┌─────────────────────────────┐   │   │
│   │   │ DisputeGame     │   │         RAT Contract        │   │   │
│   │   │   Factory       │──►│  • triggerAttentionTest()   │   │   │
│   │   │ • create()      │   │  • submitCorrectEvidence()  │   │   │
│   │   └────────▲────────┘   └──────────────▲──────────────┘   │   │
│   └────────────┼───────────────────────────┼──────────────────┘   │
│   ┌────────────┼───────────────────────────┼──────────────────┐   │
│   │   L2 (op-geth + op-node) + op-batcher                     │   │
│   └───────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
         │                                   │
═════════╪═══════════════════════════════════╪════════════════════════
         │      EXPERIMENT COMPONENTS        │
         │                                   │
   ┌─────┴─────┐                       ┌─────┴─────┐
   │  rat-     │ create game           │  rat-     │ L2 transactions
   │ proposer  │───────────►           │  spammer  │──────────────►
   └───────────┘                       │ (100 TPS) │
         │                             └───────────┘
         │ AttentionTriggered event
         ▼
   ┌─────────────────────────────────────────────────────┐
   │              rat-validators (op-challenger ×30)     │
   │     US (10)          EU (10)         ASIA (10)      │
   │   20±5ms latency   100±20ms         220±30ms        │
   └─────────────────────────────────────────────────────┘
```

## Prerequisites

- Docker
- [Kurtosis](https://docs.kurtosis.com/install/)
- Go 1.21+
- Python 3.10+ (for visualization)

## Quick Start

### 1. Start Kurtosis Environment

```bash
./start_kurtosis.sh
```

### 2. Run Full Experiment

```bash
# Full mode: 50 blocks, 30 validators, 100 TPS
./run_exp_e_unified.sh --full

# Test mode: 3 blocks, 3 validators (quick validation)
./run_exp_e_unified.sh
```

### 3. Visualize Results

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install pandas matplotlib seaborn numpy

python3 visualize_results.py --input results/exp_e_YYYYMMDD_HHMMSS/
```

## Experiment Parameters

| Parameter | Test Mode | Full Mode |
|-----------|-----------|-----------|
| Validators | 3 | 30 |
| Blocks | 3 | 50 |
| Spammer TPS | 50±30% | 100±30% |
| Regions | US only | US, EU, ASIA |

## Output

### Experiment Results
```
results/exp_e_YYYYMMDD_HHMMSS/
├── proposer.log
├── validator_VAL-*.log
├── spammer.log
├── timing_metrics.csv
└── figures/
    ├── fig_a_processing_time.pdf
    ├── fig_b_timing_breakdown.pdf
    ├── fig_c_proof_timeline.pdf
    └── fig_d_l2_load.pdf
```

### Key Metrics
- **T_proc**: Processing time (network latency simulation)
- **T_net**: Network time (L1 transaction confirmation)
- **T_total**: Total response time

## Core Components

| Component | Path | Description |
|-----------|------|-------------|
| RAT Contract | `packages/contracts-bedrock/src/L1/RAT.sol` | On-chain RAT logic |
| Proposer | `op-rat/cmd/rat-proposer/` | Creates dispute games |
| Validator | `op-challenger/game/rat/` | Monitors and responds to RAT |
| Spammer | `op-rat/cmd/rat-spammer/` | L2 transaction load generator |

## License

MIT License - See original Optimism repository for details.
