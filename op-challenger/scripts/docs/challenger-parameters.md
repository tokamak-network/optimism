# OP-Challenger Parameters

## Parameter Categories

### Network Configuration
| Parameter | Value | Description |
|-----------|-------|-------------|
| `--network` | `op-sepolia` | Network configuration |
| `--l1-eth-rpc` | Auto-configured | L1 RPC endpoint |
| `--l1-beacon` | Auto-configured | L1 Beacon API endpoint |
| `--l2-eth-rpc` | Auto-configured | L2 RPC endpoint |
| `--rollup-rpc` | Auto-configured | Rollup RPC endpoint |

### Game Configuration
| Parameter | Value | Description |
|-----------|-------|-------------|
| `--game-factory-address` | Auto-configured | Dispute Game Factory address |
| `--trace-type` | `cannon` | Trace type |

### Binary Configuration
| Parameter | Value | Description |
|-----------|-------|-------------|
| `--cannon-bin` | `/cannon-bin/cannon` | Cannon executable path |
| `--cannon-server` | `/op-program-bin/op-program` | OP-Program server path |
| `--cannon-prestates-url` | Auto-configured | Base URL for prestate files (hash-based download) |

### Wallet Configuration
| Parameter | Value | Description |
|-----------|-------|-------------|
| `--mnemonic` | `"test test test test test test test test test test test junk"` | Development mnemonic |
| `--hd-path` | `"m/44'/60'/0'/0/0"` | HD wallet path |

### Transaction Management
| Parameter | Value | Description |
|-----------|-------|-------------|
| `--num-confirmations` | `3` | Number of transaction confirmations |
| `--safe-abort-nonce-too-low-count` | `3` | Nonce error tolerance count |
| `--fee-limit-multiplier` | `5` | Fee limit multiplier |
| `--fee-limit-threshold` | `100.0` | Fee limit threshold (GWei) |
| `--min-tip-cap` | `1.0` | Minimum tip cap (GWei) |
| `--min-basefee` | `1.0` | Minimum base fee (GWei) |
| `--resubmission-timeout` | `24s` | Transaction resubmission timeout |
| `--network-timeout` | `10s` | Network request timeout |
| `--retry-interval` | `1s` | Retry interval |
| `--max-retries` | `10` | Maximum retry attempts |
| `--tx-send-timeout` | `2m` | Transaction send timeout |
| `--tx-not-in-mempool-timeout` | `1m` | Mempool entry timeout |
| `--receipt-query-interval` | `12s` | Receipt query interval |

### Other Settings
| Parameter | Value | Description |
|-----------|-------|-------------|
| `--datadir` | `/data` | Data directory |
| `--log.level` | `INFO` | Log level |

## Parameter Modification

To modify script parameters:

1. Edit the script file directly
2. Remove existing container: `docker rm -f op-challenger`
3. Re-run script: `./run-challenger-devnet.sh`

## Important Notes

⚠️ **For development and testing purposes only**
- Mnemonic and keys are for testing - do not use in production
- Network settings are configured for local devnet
- Transaction management parameters use challenger default values