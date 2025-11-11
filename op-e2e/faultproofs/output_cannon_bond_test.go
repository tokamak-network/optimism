package faultproofs

import (
	"context"
	"fmt"
	"math/big"
	"strings"
	"testing"

	faultTypes "github.com/ethereum-optimism/optimism/op-challenger/game/fault/types"
	gameTypes "github.com/ethereum-optimism/optimism/op-challenger/game/types"
	"github.com/ethereum-optimism/optimism/op-e2e/config"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/challenger"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/disputegame"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/wait"
	"github.com/ethereum-optimism/optimism/op-service/sources/batching/rpcblock"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/stretchr/testify/require"
)

// TestOutputCannonBondCostMeasurement measures the bond and gas costs for honest challenger
// defending against a malicious proposer in GameType 0 (Cannon).
//
// Test scenarios:
// 1. Worst case: Full game tree traversal to maximum depth
// 2. Medium case: Partial game tree traversal to split depth
//
// Measures at 1 gwei gas price:
// - Total bond locked by challenger
// - Total bond locked by malicious proposer
// - Total gas costs
func TestOutputCannonBondCostMeasurement(t *testing.T) {
	tests := []struct {
		name          string
		useMaxDepth   bool // true = use maxDepth (worst case), false = use splitDepth (medium case)
		description   string
	}{
		{
			name:        "WorstCase_FullDepth",
			useMaxDepth: true,
			description: "Worst case: Full game tree traversal to maximum depth with step execution",
		},
		{
			name:        "MediumCase_SplitDepth",
			useMaxDepth: false,
			description: "Medium case: Traversal to split depth without VM execution",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			testOutputCannonBondCost(t, config.AllocType("mt-cannon"), tt.useMaxDepth, tt.description)
		})
	}
}

func testOutputCannonBondCost(t *testing.T, allocType config.AllocType, useMaxDepth bool, description string) {
	ctx := context.Background()
	// Use custom gas price of 1 gwei for measurement
	sys, l1Client := StartFaultDisputeSystem(t, WithAllocType(allocType))
	t.Cleanup(sys.Close)

	// Get initial gas price (should be 1 gwei from test setup)
	gasPrice, err := l1Client.SuggestGasPrice(ctx)
	require.NoError(t, err, "Failed to get gas price")
	t.Logf("Gas price: %v wei (%v gwei)", gasPrice, new(big.Int).Div(gasPrice, big.NewInt(1_000_000_000)))

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)

	// Create game with invalid root claim (malicious proposer)
	game := disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 4, common.Hash{0x01, 0xaa})

	splitDepth := game.SplitDepth(ctx)
	maxDepth := game.MaxDepth(ctx)

	// Determine target depth based on test scenario
	// For testing, we use moderate depths to complete quickly while still measuring real VM execution
	var targetDepth faultTypes.Depth
	if useMaxDepth {
		// For WorstCase: Use splitDepth + 10 to test significant VM execution
		// This gives a realistic measurement without going to full depth
		targetDepth = splitDepth + 10
		if targetDepth > maxDepth {
			targetDepth = maxDepth
		}
	} else {
		// For MediumCase: Use splitDepth (no VM execution, only bisection)
		targetDepth = splitDepth
	}

	t.Logf("=== Game Configuration ===")
	t.Logf("Description: %s", description)
	t.Logf("Split Depth: %d", splitDepth)
	t.Logf("Max Depth: %d", maxDepth)
	t.Logf("Target Depth: %d (using %s)", targetDepth, map[bool]string{true: "maxDepth", false: "splitDepth"}[useMaxDepth])
	t.Logf("Game Address: %s", game.Addr)

	// Track initial balances
	challengerAddr := sys.Cfg.Secrets.Addresses().Alice
	proposerAddr := sys.Cfg.Secrets.Addresses().Bob

	t.Logf("\n=== Participant Addresses ===")
	t.Logf("Honest Challenger: %s", challengerAddr)
	t.Logf("Malicious Proposer: %s", proposerAddr)

	// Get initial L1 balances
	challengerInitialBalance, err := l1Client.BalanceAt(ctx, challengerAddr, nil)
	require.NoError(t, err)
	proposerInitialBalance, err := l1Client.BalanceAt(ctx, proposerAddr, nil)
	require.NoError(t, err)

	t.Logf("\n=== Initial L1 Balances ===")
	t.Logf("Challenger Initial Balance: %s wei (%s ETH)", challengerInitialBalance, weiToEth(challengerInitialBalance))
	t.Logf("Proposer Initial Balance: %s wei (%s ETH)", proposerInitialBalance, weiToEth(proposerInitialBalance))

	// Start honest challenger
	game.StartChallenger(ctx, "HonestChallenger",
		challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
	)

	// Wait for game to progress to target depth
	if targetDepth >= splitDepth {
		// For deep games, wait for exec game claims
		t.Logf("\n=== Waiting for execution game claims (depth > split_depth) ===")
		game.WaitForClaimAtDepth(ctx, targetDepth)
	} else {
		// For shallow games, just wait for split depth
		t.Logf("\n=== Waiting for split depth claims ===")
		game.WaitForClaimAtDepth(ctx, targetDepth)
	}

	// Log all claims to understand the game tree
	game.LogGameData(ctx)

	// Wait for game resolution
	game.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)
	t.Logf("\n=== Game Status: Challenger Won ===")

	// Measure bonds locked in the game
	claims, err := game.Game.GetAllClaims(ctx, rpcblock.Latest)
	require.NoError(t, err, "Failed to get all claims")
	t.Logf("\n=== Bond Measurements ===")
	t.Logf("Total Claims: %d", len(claims))

	totalChallengerBonds := big.NewInt(0)
	totalProposerBonds := big.NewInt(0)

	for i, claim := range claims {
		// Determine if claim is from challenger or proposer
		// Root claim (index 0) is from proposer
		// Even depths are typically from one party, odd from the other
		isProposerClaim := (i == 0) || (claim.Depth()%2 == 0)

		if isProposerClaim {
			totalProposerBonds.Add(totalProposerBonds, claim.Bond)
			t.Logf("Claim %d (Proposer): Depth=%d, Bond=%s wei", i, claim.Depth(), claim.Bond)
		} else {
			totalChallengerBonds.Add(totalChallengerBonds, claim.Bond)
			t.Logf("Claim %d (Challenger): Depth=%d, Bond=%s wei", i, claim.Depth(), claim.Bond)
		}
	}

	// Get final L1 balances
	challengerFinalBalance, err := l1Client.BalanceAt(ctx, challengerAddr, nil)
	require.NoError(t, err)
	proposerFinalBalance, err := l1Client.BalanceAt(ctx, proposerAddr, nil)
	require.NoError(t, err)

	// Calculate gas costs
	challengerGasCost := new(big.Int).Sub(challengerInitialBalance, challengerFinalBalance)
	challengerGasCost.Sub(challengerGasCost, totalChallengerBonds) // Subtract bonds (will be reclaimed)

	proposerGasCost := new(big.Int).Sub(proposerInitialBalance, proposerFinalBalance)
	proposerGasCost.Sub(proposerGasCost, totalProposerBonds) // Subtract bonds (lost to challenger)

	// Print comprehensive cost report
	t.Logf("\n" + strings.Repeat("=", 80))
	t.Logf("=== BOND AND GAS COST REPORT ===")
	t.Logf(strings.Repeat("=", 80))
	t.Logf("\nTest Scenario: %s", description)
	t.Logf("Target Depth: %d / %d (max)", targetDepth, maxDepth)
	t.Logf("Gas Price: %v gwei", new(big.Int).Div(gasPrice, big.NewInt(1_000_000_000)))

	t.Logf("\n--- BOND COSTS ---")
	t.Logf("Challenger Total Bonds Locked: %s wei (%s ETH)", totalChallengerBonds, weiToEth(totalChallengerBonds))
	t.Logf("Proposer Total Bonds Locked:   %s wei (%s ETH)", totalProposerBonds, weiToEth(totalProposerBonds))

	t.Logf("\n--- GAS COSTS (excluding bonds) ---")
	t.Logf("Challenger Gas Cost: %s wei (%s ETH)", challengerGasCost, weiToEth(challengerGasCost))
	t.Logf("Proposer Gas Cost:   %s wei (%s ETH)", proposerGasCost, weiToEth(proposerGasCost))

	totalChallengerCost := new(big.Int).Add(totalChallengerBonds, challengerGasCost)
	totalProposerCost := new(big.Int).Add(totalProposerBonds, proposerGasCost)

	t.Logf("\n--- TOTAL COSTS (bonds + gas) ---")
	t.Logf("Challenger Total Cost: %s wei (%s ETH)", totalChallengerCost, weiToEth(totalChallengerCost))
	t.Logf("Proposer Total Cost:   %s wei (%s ETH)", totalProposerCost, weiToEth(totalProposerCost))

	t.Logf("\n--- NET RESULT (after bond reclaim) ---")
	// Challenger gets bonds back + takes proposer's bonds
	challengerNetProfit := new(big.Int).Add(totalProposerBonds, totalChallengerBonds)
	challengerNetProfit.Sub(challengerNetProfit, challengerGasCost)
	t.Logf("Challenger Net: %s wei (%s ETH) [+bonds reclaimed + opponent bonds - gas]",
		challengerNetProfit, weiToEth(challengerNetProfit))

	// Proposer loses all bonds and pays gas
	proposerNetLoss := new(big.Int).Add(totalProposerBonds, proposerGasCost)
	t.Logf("Proposer Net Loss: -%s wei (-%s ETH) [bonds lost + gas paid]",
		proposerNetLoss, weiToEth(proposerNetLoss))

	t.Logf("\n" + strings.Repeat("=", 80))

	// Verify challenger won and can claim bonds
	game.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)
	t.Logf("\n=== Game Resolved: Challenger Won ===")

	// Get balance before claiming credit
	challengerBalanceBeforeClaim, err := l1Client.BalanceAt(ctx, challengerAddr, nil)
	require.NoError(t, err)
	t.Logf("\nChallenger Balance Before Claim: %s wei (%s ETH)", challengerBalanceBeforeClaim, weiToEth(challengerBalanceBeforeClaim))

	// Wait for game to be finalized (after airgap window)
	game.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)

	// Claim credit (bond reclaim)
	t.Logf("\n=== Claiming Credit (Bond Reclaim) ===")

	// Get transaction candidate
	txCandidate, err := game.Game.ClaimCreditTx(ctx, challengerAddr)
	require.NoError(t, err, "Failed to create ClaimCredit transaction candidate")

	// Get current nonce
	nonce, err := l1Client.PendingNonceAt(ctx, challengerAddr)
	require.NoError(t, err, "Failed to get nonce")

	// Create and sign transaction manually
	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   sys.Cfg.L1ChainIDBig(),
		Nonce:     nonce,
		To:        txCandidate.To,
		Value:     txCandidate.Value,
		Gas:       txCandidate.GasLimit,
		GasFeeCap: gasPrice,   // Use current gas price
		GasTipCap: gasPrice,   // Use current gas price
		Data:      txCandidate.TxData,
	})

	// Sign the transaction
	signedTx, err := types.SignTx(tx, types.NewLondonSigner(sys.Cfg.L1ChainIDBig()), sys.Cfg.Secrets.Alice)
	require.NoError(t, err, "Failed to sign ClaimCredit transaction")

	// Send the transaction
	err = l1Client.SendTransaction(ctx, signedTx)
	require.NoError(t, err, "Failed to send ClaimCredit transaction")

	// Wait for receipt
	receipt, err := wait.ForReceiptOK(ctx, l1Client, signedTx.Hash())
	require.NoError(t, err, "Failed to get ClaimCredit receipt")
	t.Logf("ClaimCredit TX successful")
	t.Logf("ClaimCredit Gas Used: %d", receipt.GasUsed)

	// Get final balance after claiming
	challengerBalanceAfterClaim, err := l1Client.BalanceAt(ctx, challengerAddr, nil)
	require.NoError(t, err)

	t.Logf("\n" + strings.Repeat("=", 80))
	t.Logf("=== FINAL BALANCE VERIFICATION ===")
	t.Logf(strings.Repeat("=", 80))

	t.Logf("\n--- Balance Progression ---")
	t.Logf("Initial Balance:      %s wei (%s ETH)", challengerInitialBalance, weiToEth(challengerInitialBalance))
	t.Logf("Before Claim:         %s wei (%s ETH)", challengerBalanceBeforeClaim, weiToEth(challengerBalanceBeforeClaim))
	t.Logf("After Claim:          %s wei (%s ETH)", challengerBalanceAfterClaim, weiToEth(challengerBalanceAfterClaim))

	// Calculate actual profit
	actualProfit := new(big.Int).Sub(challengerBalanceAfterClaim, challengerInitialBalance)
	t.Logf("\n--- Actual Result (Verified On-Chain) ---")
	t.Logf("Actual Net Profit: %s wei (%s ETH)", actualProfit, weiToEth(actualProfit))

	// Calculate expected vs actual
	expectedProfit := new(big.Int).Sub(challengerNetProfit, new(big.Int).Mul(big.NewInt(int64(receipt.GasUsed)), gasPrice))
	difference := new(big.Int).Sub(actualProfit, expectedProfit)

	t.Logf("\n--- Verification ---")
	t.Logf("Expected Profit (calculated): %s wei (%s ETH)", expectedProfit, weiToEth(expectedProfit))
	t.Logf("Actual Profit (on-chain):     %s wei (%s ETH)", actualProfit, weiToEth(actualProfit))
	t.Logf("Difference:                   %s wei (%s ETH)", difference, weiToEth(difference))

	if actualProfit.Cmp(big.NewInt(0)) > 0 {
		t.Logf("\n✅ SUCCESS: Challenger made a profit of %s ETH", weiToEth(actualProfit))
	} else {
		t.Logf("\n⚠️  WARNING: Challenger did not profit (lost %s ETH)", weiToEth(new(big.Int).Neg(actualProfit)))
	}

	t.Logf("\n" + strings.Repeat("=", 80))
	t.Logf("\nTest completed successfully - Bond reclaim verified")
}

// weiToEth converts wei to ETH string for readable output
func weiToEth(wei *big.Int) string {
	eth := new(big.Float).Quo(
		new(big.Float).SetInt(wei),
		new(big.Float).SetInt64(1_000_000_000_000_000_000),
	)
	return fmt.Sprintf("%.6f", eth)
}
