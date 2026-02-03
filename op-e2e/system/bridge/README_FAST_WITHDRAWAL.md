# Fast Withdrawal E2E Tests

This directory contains End-to-End tests for the Fast Withdrawal feature integrated with OptimismPortal2.

## Test Files

### 1. `fast_withdrawal_test.go`
Full E2E test for the Fast Withdrawal flow including:
- Deposit ETH to L2
- Initiate withdrawal with `proveAndRequestFastWithdrawal`
- RAT validator signature aggregation (simulated)
- Fast finalization without 7-day delay

**Status**: Requires full RAT validator setup for complete testing.

### 2. `fast_withdrawal_portal_test.go`
Deployment verification test for OptimismPortal2 with Fast Withdrawal support:
- Verifies OptimismPortal2 is deployed
- Checks code size is under 24KB limit (EIP-170)
- Verifies Fast Withdrawal function selectors in bytecode

**Status**: Ready to run (requires prestate files - see Setup below).

## Changes Made to OptimismPortal2

The following Fast Withdrawal functions have been added to OptimismPortal2:

### New Storage Variables
- `address public ratContract` - RAT contract address for signature verification
- `mapping(bytes32 => bool) public withdrawalVerified` - Tracks RAT-verified withdrawals
- `mapping(bytes32 => bool) public fastFinalizedWithdrawals` - Tracks fast-finalized withdrawals
- `uint256 public fastWithdrawalResponsePeriod` - Timeout period for fast withdrawal

### New Functions
- `setRatContract(address)` - Set RAT contract address (owner only)
- `setFastWithdrawalResponsePeriod(uint256)` - Set response period (owner only)
- `proveAndRequestFastWithdrawal(...)` - Prove withdrawal and request fast finalization
- `setWithdrawalVerified(bytes32)` - Mark withdrawal as verified by RAT (RAT contract only)
- `fastWithdrawalFinalize(...)` - Finalize withdrawal immediately (RAT contract only)

### Code Optimizations Applied
To fit under the 24KB contract size limit:
1. Refactored `proveAndRequestFastWithdrawal` to reuse `proveWithdrawalTransaction`
2. Extracted common withdrawal execution logic into `_executeWithdrawal` internal function
3. Reduced `optimizer_runs` from 5000 to 200 for size optimization
4. Changed `proveWithdrawalTransaction` from `external` to `public` for internal calls

**Result**: ~45 lines of duplicate code removed, contract size reduced by ~10-15%.

## Running Tests

### Setup

1. Build prestate files:
```bash
cd /Users/zena/tokamak-projects/optimism
make cannon-prestates
```

2. Build contracts:
```bash
cd packages/contracts-bedrock
forge build
```

3. Generate devnet allocs:
```bash
cd /Users/zena/tokamak-projects/optimism
rm -rf .devnet
go run ./op-chain-ops/cmd/devnet-allocs
```

### Run Tests

```bash
cd op-e2e

# Run deployment verification
go test -v ./system/bridge -run TestOptimismPortal2_FastWithdrawalDeployment

# Run full Fast Withdrawal test (requires RAT setup)
go test -v ./system/bridge -run TestFastWithdrawal_Default
```

## Integration with RAT

For complete Fast Withdrawal functionality, the following components are needed:

1. **RAT Contract** - Deployed and configured with validators
2. **Validators** - Registered with BLS public keys
3. **Aggregator Service** - Off-chain service to collect and aggregate BLS signatures
4. **Portal Configuration** - RAT contract address set in OptimismPortal2

The current tests verify that:
- ✅ OptimismPortal2 is deployed with Fast Withdrawal functions
- ✅ Code size is under 24KB limit
- ✅ Function selectors are present in bytecode
- ⏳ Full RAT integration requires additional setup

## Related Documentation

- OptimismPortal2 source: `packages/contracts-bedrock/src/L1/OptimismPortal2.sol`
- RAT documentation: `https://github.com/tokamak-network/ton-staking-v2/tree/ton-staking-v3/rat-fast-withdrawal/docs/rat-fast-withdrawal`
- Integration guide: `RAT_FAST_WITHDRAWAL_INTEGRATION.md`

## Test Status

- [x] OptimismPortal2 code optimization completed
- [x] Contract size under 24KB limit verified
- [x] Genesis files generated successfully
- [x] Deployment test created
- [ ] Prestate files setup (in progress)
- [ ] Full E2E test with RAT (requires validator setup)
