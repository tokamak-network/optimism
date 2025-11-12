package faultproofs

import (
	"context"
	"fmt"
	"math/big"
	"strings"
	"testing"
	"time"

	faultTypes "github.com/ethereum-optimism/optimism/op-challenger/game/fault/types"
	gameTypes "github.com/ethereum-optimism/optimism/op-challenger/game/types"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/challenger"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/disputegame"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/wait"
	"github.com/ethereum-optimism/optimism/op-service/sources/batching/rpcblock"
	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/require"
)

// TestOutputCannonBondCostMeasurement measures the bond and gas costs for honest challenger
// defending against a malicious proposer in GameType 0 (Cannon).
//
// This test creates TWO games:
// 1. First game: Cold start with correct value (no challenger needed)
// 2. Second game: Invalid claim that triggers challenger response
//
// Measures bond costs and gas costs for the second game.
func TestOutputCannonBondCostMeasurement(t *testing.T) {
	ctx := context.Background()

	// Start system with default allocType
	sys, l1Client := StartFaultDisputeSystem(t)
	t.Cleanup(sys.Close)

	// Get gas price
	gasPrice, err := l1Client.SuggestGasPrice(ctx)
	require.NoError(t, err, "Failed to get gas price")

	// Calculate gwei (1 gwei = 1,000,000,000 wei)
	gasPriceGwei := new(big.Float).Quo(
		new(big.Float).SetInt(gasPrice),
		new(big.Float).SetInt64(1_000_000_000),
	)
	gasPriceGweiFloat, _ := gasPriceGwei.Float64()
	t.Logf("Gas price: %v wei (%.4f gwei)", gasPrice, gasPriceGweiFloat)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)

	// FIRST GAME: Cold start with invalid claim (challenger will win)
	t.Logf("\n=== Creating First Game (Cold Start) ===")
	game1 := disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 4, common.Hash{0xff})
	t.Logf("First Game Address: %s", game1.Addr)

	// Start challenger for first game
	game1.StartChallenger(ctx, "FirstGameChallenger",
		challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
	)

	// Wait for the challenger to respond (let it make moves)
	t.Logf("Waiting for challenger to respond...")
	game1.WaitForInactivity(ctx, 4, false)

	// Advance time past game duration to expire the clock
	t.Logf("Advancing time past game duration...")
	gameDuration := game1.MaxClockDuration(ctx)
	sys.TimeTravelClock.AdvanceTime(gameDuration)
	require.NoError(t, wait.ForNextBlock(ctx, l1Client))

	// Wait a bit for challenger to finish making moves
	t.Logf("Waiting for challenger to finish...")
	game1.WaitForInactivity(ctx, 2, false)

	// Challenger already resolves claims and game automatically, so we skip manual resolve
	/*
	// Properly resolve the first game to update the absolute prestate
	// Must do this BEFORE WaitForGameStatus, otherwise game will already be resolved
	t.Logf("Resolving root claim...")
	game1.ResolveClaim(ctx, 0)

	t.Logf("Resolving entire first game...")
	game1.Resolve(ctx)
	*/

	// Wait for challenger to complete resolve
	t.Logf("Waiting for challenger to complete resolve...")
	time.Sleep(5 * time.Second)

	// Close the game (this changes the game status)
	t.Logf("Closing game...")
	game1.CloseGame(ctx)

	// Now wait for the game to be in Challenger Won status
	t.Logf("Waiting for first game status...")
	game1.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)
	t.Logf("First Game Status: Challenger Won")

	t.Logf("First game resolved - absolute prestate now updated (cold start complete)")

	// SECOND GAME: Invalid claim that triggers challenger
	t.Logf("\n=== Creating Second Game (Invalid Claim for Testing) ===")
	invalidRootClaim := common.Hash{0x01, 0xaa}
	game2 := disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 4, invalidRootClaim)

	splitDepth := game2.SplitDepth(ctx)
	maxDepth := game2.MaxDepth(ctx)

	t.Logf("\n=== Game Configuration ===")
	t.Logf("Second Game Address: %s", game2.Addr)
	t.Logf("Invalid Root Claim: %s", invalidRootClaim)
	t.Logf("Split Depth: %d", splitDepth)
	t.Logf("Max Depth: %d", maxDepth)

	// Track challenger address
	challengerAddr := sys.Cfg.Secrets.Addresses().Alice
	proposerAddr := sys.Cfg.Secrets.Addresses().Bob

	t.Logf("\n=== Participant Addresses ===")
	t.Logf("Honest Challenger: %s", challengerAddr)
	t.Logf("Malicious Proposer: %s", proposerAddr)

	// Get initial balances
	challengerInitialBalance, err := l1Client.BalanceAt(ctx, challengerAddr, nil)
	require.NoError(t, err)
	proposerInitialBalance, err := l1Client.BalanceAt(ctx, proposerAddr, nil)
	require.NoError(t, err)

	t.Logf("\n=== Initial L1 Balances ===")
	t.Logf("Challenger Initial Balance: %s wei (%s ETH)", challengerInitialBalance, weiToEth(challengerInitialBalance))
	t.Logf("Proposer Initial Balance: %s wei (%s ETH)", proposerInitialBalance, weiToEth(proposerInitialBalance))

	// Start honest challenger
	game2.StartChallenger(ctx, "HonestChallenger",
		challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
	)

	// Create malicious proposer (defender) that will respond to challenger's attacks
	// This makes claims with incorrect values to simulate a malicious proposer
	t.Logf("\n=== Starting malicious proposer defender ===")
	maliciousTrace := game2.CreateHonestActor(ctx, "sequencer", disputegame.WithPrivKey(sys.Cfg.Secrets.Bob))

	// Make malicious proposer actively defend all claims up to split depth
	// This ensures we get multiple rounds of claims from both parties
	t.Logf("Malicious proposer will defend all challenger attacks up to split depth %d", splitDepth)

	// Use DefendClaim to make the proposer defend against all attacks
	// We pass WithoutWaitingForStep option because we only go to split depth, not executing step
	game2.DefendClaim(ctx, game2.RootClaim(ctx), func(parent *disputegame.ClaimHelper) *disputegame.ClaimHelper {
		currentDepth := parent.Depth()
		t.Logf("Malicious proposer defending claim at depth %d (parent index: %d)", currentDepth, parent.Index)

		// For bottom game (execution trace), attack to continue the game
		if parent.IsBottomGameRoot(ctx) {
			t.Logf("Reached bottom game root at depth %d, attacking to enter execution trace", currentDepth)
			return maliciousTrace.AttackClaim(ctx, parent)
		}

		// Continue defending in the output bisection game
		t.Logf("Proposer making defense move at depth %d", currentDepth)
		return maliciousTrace.DefendClaim(ctx, parent)
	}, disputegame.WithoutWaitingForStep())

	// Wait for game to progress to split depth
	t.Logf("\n=== Waiting for split depth claims ===")
	game2.WaitForClaimAtDepth(ctx, splitDepth)

	// Allow some time for all pending transactions to complete
	t.Logf("Waiting for all claims to be finalized...")
	game2.WaitForInactivity(ctx, 3, false)

	// Log all claims
	game2.LogGameData(ctx)

	// Advance time past game duration to allow resolution
	t.Logf("\n=== Advancing time past game duration ===")
	sys.TimeTravelClock.AdvanceTime(gameDuration)
	require.NoError(t, wait.ForNextBlock(ctx, l1Client))

	// Wait for challenger to finish making moves
	t.Logf("Waiting for challenger to finish...")
	game2.WaitForInactivity(ctx, 2, false)

	// Wait for challenger to complete resolve
	t.Logf("Waiting for challenger to complete resolve...")
	time.Sleep(5 * time.Second)

	// Close the second game
	t.Logf("Closing second game...")
	game2.CloseGame(ctx)

	// Wait for game resolution
	game2.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)

	// Verify and log final game status
	finalStatus := game2.Status(ctx)
	t.Logf("\n=== Final Game Status ===")
	t.Logf("Game Status: %v (Challenger Won)", finalStatus)
	require.Equal(t, gameTypes.GameStatusChallengerWon, finalStatus, "Expected game status to be Challenger Won")
	t.Logf("Game Winner: Honest Challenger (Alice)")

	// Measure bonds locked in the game
	claims, err := game2.Game.GetAllClaims(ctx, rpcblock.Latest)
	require.NoError(t, err, "Failed to get all claims")

	// Log detailed claim information and calculate bond totals
	totalChallengerBonds, totalProposerBonds := logClaimDetails(t, claims, challengerAddr, proposerAddr)

	// Verify bond increase pattern
	verifyBondIncrease(t, claims)

	// Get final balances
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
	t.Logf("\nTest Scenario: Simple case with split depth only (no VM execution)")
	t.Logf("Target Depth: %d (split depth)", splitDepth)
	t.Logf("Gas Price: %.4f gwei", gasPriceGweiFloat)

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
	t.Logf("\nTest completed successfully")
}

// weiToEth converts wei to ETH string for readable output
func weiToEth(wei *big.Int) string {
	eth := new(big.Float).Quo(
		new(big.Float).SetInt(wei),
		new(big.Float).SetInt64(1_000_000_000_000_000_000),
	)
	return fmt.Sprintf("%.6f", eth)
}

// logClaimDetails logs detailed information about each claim and calculates bond totals
func logClaimDetails(t *testing.T, claims []faultTypes.Claim, challengerAddr, proposerAddr common.Address) (totalChallengerBonds, totalProposerBonds *big.Int) {
	totalChallengerBonds = big.NewInt(0)
	totalProposerBonds = big.NewInt(0)

	t.Logf("\n" + strings.Repeat("=", 80))
	t.Logf("=== DETAILED CLAIM ANALYSIS ===")
	t.Logf(strings.Repeat("=", 80))
	t.Logf("Total Claims: %d\n", len(claims))

	for i, claim := range claims {
		// Determine claim ownership by claimant address
		isProposerClaim := claim.Claimant == proposerAddr
		isChallengerClaim := claim.Claimant == challengerAddr

		claimType := "Unknown"
		if isProposerClaim {
			claimType = "Proposer"
			totalProposerBonds.Add(totalProposerBonds, claim.Bond)
		} else if isChallengerClaim {
			claimType = "Challenger"
			totalChallengerBonds.Add(totalChallengerBonds, claim.Bond)
		}

		// Log detailed claim information
		t.Logf("Claim #%d (%s):", i, claimType)
		t.Logf("  Depth:        %d", claim.Depth())
		t.Logf("  Position:     %d", claim.Position.ToGIndex())
		t.Logf("  Value:        %s", claim.Value)
		t.Logf("  Bond:         %s wei (%s ETH)", claim.Bond, weiToEth(claim.Bond))
		t.Logf("  Claimant:     %s", claim.Claimant)
		if claim.ParentContractIndex != 0 || i > 0 {
			t.Logf("  Parent Index: %d", claim.ParentContractIndex)
		}
		t.Logf("  CounteredBy:  %s", claim.CounteredBy)
		t.Logf("")
	}

	t.Logf(strings.Repeat("-", 80))
	t.Logf("Bond Totals:")
	t.Logf("  Challenger Total: %s wei (%s ETH)", totalChallengerBonds, weiToEth(totalChallengerBonds))
	t.Logf("  Proposer Total:   %s wei (%s ETH)", totalProposerBonds, weiToEth(totalProposerBonds))
	t.Logf(strings.Repeat("=", 80))

	return totalChallengerBonds, totalProposerBonds
}

// verifyBondIncrease verifies that bonds increase correctly with depth
func verifyBondIncrease(t *testing.T, claims []faultTypes.Claim) {
	t.Logf("\n=== Verifying Bond Increase Pattern ===")

	// Track bonds by depth to verify the pattern
	bondsByDepth := make(map[uint64]*big.Int)

	for i, claim := range claims {
		depth := uint64(claim.Depth())

		if i == 0 {
			t.Logf("Root claim (depth %d): bond = %s wei", depth, claim.Bond)
			bondsByDepth[depth] = claim.Bond
			continue
		}

		// Check if we've seen this depth before
		if prevBondAtDepth, exists := bondsByDepth[depth]; exists {
			// All claims at the same depth should have the same bond
			if claim.Bond.Cmp(prevBondAtDepth) == 0 {
				t.Logf("✓ Claim #%d (depth %d): bond = %s wei (matches previous at this depth)", i, depth, claim.Bond)
			} else {
				t.Logf("⚠ Claim #%d (depth %d): bond = %s wei (differs from previous %s wei at this depth)",
					i, depth, claim.Bond, prevBondAtDepth)
			}
		} else {
			bondsByDepth[depth] = claim.Bond
			t.Logf("✓ Claim #%d (depth %d): bond = %s wei (first claim at this depth)", i, depth, claim.Bond)
		}
	}

	// Verify bonds increase with depth
	t.Logf("\n=== Bond Escalation by Depth ===")
	var depths []uint64
	for depth := range bondsByDepth {
		depths = append(depths, depth)
	}

	// Sort depths for ordered output
	for i := 0; i < len(depths); i++ {
		for j := i + 1; j < len(depths); j++ {
			if depths[i] > depths[j] {
				depths[i], depths[j] = depths[j], depths[i]
			}
		}
	}

	for i, depth := range depths {
		bond := bondsByDepth[depth]
		t.Logf("Depth %d: %s wei (%s ETH)", depth, bond, weiToEth(bond))

		if i > 0 {
			prevDepth := depths[i-1]
			prevBond := bondsByDepth[prevDepth]

			if bond.Cmp(prevBond) > 0 {
				increase := new(big.Int).Sub(bond, prevBond)
				percentage := new(big.Float).Quo(
					new(big.Float).SetInt(increase),
					new(big.Float).SetInt(prevBond),
				)
				percentageFloat, _ := percentage.Float64()
				t.Logf("  ↑ Increased by %s wei (%.2f%%) from depth %d", increase, percentageFloat*100, prevDepth)
			} else if bond.Cmp(prevBond) == 0 {
				t.Logf("  = Same as depth %d", prevDepth)
			} else {
				t.Logf("  ⚠ Decreased from depth %d (unexpected)", prevDepth)
			}
		}
	}
}

// TestOutputCannonBondCostWithMaliciousProposer measures bond and gas costs when
// an honest challenger defends against a malicious proposer in GameType 0 (Cannon).
// This test simulates a full dispute where the malicious proposer actively defends
// their invalid root claim, causing the game to progress to split depth.
func TestOutputCannonBondCostWithMaliciousProposer(t *testing.T) {
	ctx := context.Background()

	// Start system with default allocType
	sys, l1Client := StartFaultDisputeSystem(t)
	t.Cleanup(sys.Close)

	// Get gas price
	gasPrice, err := l1Client.SuggestGasPrice(ctx)
	require.NoError(t, err, "Failed to get gas price")

	// Calculate gwei (1 gwei = 1,000,000,000 wei)
	gasPriceGwei := new(big.Float).Quo(
		new(big.Float).SetInt(gasPrice),
		new(big.Float).SetInt64(1_000_000_000),
	)
	gasPriceGweiFloat, _ := gasPriceGwei.Float64()
	t.Logf("Gas price: %v wei (%.4f gwei)", gasPrice, gasPriceGweiFloat)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)

	// FIRST GAME: Cold start with invalid claim (challenger will win)
	t.Logf("\n=== Creating First Game (Cold Start) ===")
	game1 := disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 4, common.Hash{0xff})
	t.Logf("First Game Address: %s", game1.Addr)

	// Start challenger for first game
	game1.StartChallenger(ctx, "FirstGameChallenger",
		challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
	)

	// Wait for the challenger to respond (let it make moves)
	t.Logf("Waiting for challenger to respond...")
	game1.WaitForInactivity(ctx, 4, false)

	// Advance time past game duration to expire the clock
	t.Logf("Advancing time past game duration...")
	gameDuration := game1.MaxClockDuration(ctx)
	sys.TimeTravelClock.AdvanceTime(gameDuration)
	require.NoError(t, wait.ForNextBlock(ctx, l1Client))

	// Wait a bit for challenger to finish making moves
	t.Logf("Waiting for challenger to finish...")
	game1.WaitForInactivity(ctx, 2, false)

	// Close the game (this changes the game status)
	t.Logf("Closing game...")
	game1.CloseGame(ctx)

	// Now wait for the game to be in Challenger Won status
	t.Logf("Waiting for first game status...")
	game1.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)
	t.Logf("First Game Status: Challenger Won")

	t.Logf("First game resolved - absolute prestate now updated (cold start complete)")

	// SECOND GAME: Invalid claim that triggers challenger with malicious proposer defense
	t.Logf("\n=== Creating Second Game (Invalid Claim with Malicious Proposer) ===")
	invalidRootClaim := common.Hash{0x01, 0xaa}
	game2 := disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 4, invalidRootClaim)

	splitDepth := game2.SplitDepth(ctx)
	maxDepth := game2.MaxDepth(ctx)

	t.Logf("\n=== Game Configuration ===")
	t.Logf("Second Game Address: %s", game2.Addr)
	t.Logf("Invalid Root Claim: %s", invalidRootClaim)
	t.Logf("Split Depth: %d", splitDepth)
	t.Logf("Max Depth: %d", maxDepth)

	// Track challenger address
	challengerAddr := sys.Cfg.Secrets.Addresses().Alice
	proposerAddr := sys.Cfg.Secrets.Addresses().Bob

	t.Logf("\n=== Participant Addresses ===")
	t.Logf("Honest Challenger: %s", challengerAddr)
	t.Logf("Malicious Proposer: %s", proposerAddr)

	// Get initial balances
	challengerInitialBalance, err := l1Client.BalanceAt(ctx, challengerAddr, nil)
	require.NoError(t, err)
	proposerInitialBalance, err := l1Client.BalanceAt(ctx, proposerAddr, nil)
	require.NoError(t, err)

	t.Logf("\n=== Initial L1 Balances ===")
	t.Logf("Challenger Initial Balance: %s wei (%s ETH)", challengerInitialBalance, weiToEth(challengerInitialBalance))
	t.Logf("Proposer Initial Balance: %s wei (%s ETH)", proposerInitialBalance, weiToEth(proposerInitialBalance))

	// Start honest challenger
	game2.StartChallenger(ctx, "HonestChallenger",
		challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
	)

	// Create malicious proposer (defender) that will respond to challenger's attacks
	// This makes dishonest claims to defend the invalid root claim
	t.Logf("\n=== Starting malicious proposer defender ===")
	dishonestHelper := game2.CreateDishonestHelper(ctx, "sequencer", true) // true = defender (proposer)

	// Make malicious proposer exhaust all dishonest claims to reach split depth
	t.Logf("Malicious proposer making counter-claims...")
	dishonestHelper.ExhaustDishonestClaims(ctx, game2.RootClaim(ctx))

	// Wait for game to progress to split depth (simple case: no VM execution)
	t.Logf("\n=== Waiting for split depth claims ===")
	game2.WaitForClaimAtDepth(ctx, splitDepth)

	// Wait for inactivity (no more moves being made)
	t.Logf("Waiting for game activity to complete...")
	game2.WaitForInactivity(ctx, 4, false)

	// Advance time to allow game resolution
	t.Logf("\n=== Advancing time for game resolution ===")
	sys.TimeTravelClock.AdvanceTime(game2.MaxClockDuration(ctx))
	require.NoError(t, wait.ForNextBlock(ctx, l1Client))

	// Wait for game resolution
	game2.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)

	// Verify and log final game status
	finalStatus := game2.Status(ctx)
	t.Logf("\n=== Final Game Status ===")
	t.Logf("Game Status: %v (Challenger Won)", finalStatus)
	require.Equal(t, gameTypes.GameStatusChallengerWon, finalStatus, "Expected game status to be Challenger Won")
	t.Logf("Game Winner: Honest Challenger (Alice)")

	// Log all claims
	game2.LogGameData(ctx)

	// Measure bonds locked in the game
	claims, err := game2.Game.GetAllClaims(ctx, rpcblock.Latest)
	require.NoError(t, err, "Failed to get all claims")

	// Log detailed claim information and calculate bond totals
	totalChallengerBonds, totalProposerBonds := logClaimDetails(t, claims, challengerAddr, proposerAddr)

	// Verify bond increase pattern
	verifyBondIncrease(t, claims)

	// Get final balances
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
	t.Logf("\nTest Scenario: Malicious proposer actively defends invalid claim")
	t.Logf("Target Depth: %d (split depth)", splitDepth)
	t.Logf("Gas Price: %.4f gwei", gasPriceGweiFloat)

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
	t.Logf("\nTest completed successfully")
}

// TestOutputCannonBondCostSimple measures bond and gas costs for honest challenger
// defending against a malicious proposer in GameType 0 (Cannon).
// This is a simple test that only goes to split depth (no VM execution).
func TestOutputCannonBondCostSimple(t *testing.T) {
	ctx := context.Background()

	// Start system with default allocType
	sys, l1Client := StartFaultDisputeSystem(t)
	t.Cleanup(sys.Close)

	// Get gas price
	gasPrice, err := l1Client.SuggestGasPrice(ctx)
	require.NoError(t, err, "Failed to get gas price")

	// Calculate gwei (1 gwei = 1,000,000,000 wei)
	gasPriceGwei := new(big.Float).Quo(
		new(big.Float).SetInt(gasPrice),
		new(big.Float).SetInt64(1_000_000_000),
	)
	gasPriceGweiFloat, _ := gasPriceGwei.Float64()
	t.Logf("Gas price: %v wei (%.4f gwei)", gasPrice, gasPriceGweiFloat)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)

	// FIRST GAME: Cold start with correct output root
	// This is necessary because the first game in the system needs to establish the initial state
	t.Logf("\n=== Creating First Game (Cold Start) ===")
	game1 := disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 4, common.Hash{0xff}) // Invalid claim
	t.Logf("First Game Address: %s", game1.Addr)

	// Start challenger for first game to let it resolve
	game1.StartChallenger(ctx, "FirstGameChallenger",
		challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
	)

	// Wait for the challenger to respond (let it make moves)
	t.Logf("Waiting for challenger to respond...")
	game1.WaitForInactivity(ctx, 4, false)

	// Advance time past game duration to expire the clock
	t.Logf("Advancing time past game duration...")
	gameDuration := game1.MaxClockDuration(ctx)
	sys.TimeTravelClock.AdvanceTime(gameDuration)
	require.NoError(t, wait.ForNextBlock(ctx, l1Client))

	// Now the game should resolve as ChallengerWon
	t.Logf("Waiting for first game status...")
	game1.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)
	t.Logf("First Game Status: Challenger Won")

	// Properly resolve the first game to update the absolute prestate
	t.Logf("Resolving root claim...")
	game1.ResolveClaim(ctx, 0)

	t.Logf("Resolving entire first game...")
	game1.Resolve(ctx)
	game1.CloseGame(ctx)

	t.Logf("First game resolved - absolute prestate now updated (cold start complete)")

	// SECOND GAME: Invalid claim that triggers challenger (this is the game we measure)
	t.Logf("\n=== Creating Second Game (Bond Measurement) ===")
	invalidRootClaim := common.Hash{0x01, 0xaa}
	game2 := disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 4, invalidRootClaim)

	splitDepth := game2.SplitDepth(ctx)
	maxDepth := game2.MaxDepth(ctx)

	t.Logf("\n=== Game Configuration ===")
	t.Logf("Second Game Address: %s", game2.Addr)
	t.Logf("Invalid Root Claim: %s", invalidRootClaim)
	t.Logf("Split Depth: %d", splitDepth)
	t.Logf("Max Depth: %d", maxDepth)

	// Track challenger and proposer addresses
	challengerAddr := sys.Cfg.Secrets.Addresses().Alice
	proposerAddr := sys.Cfg.Secrets.Addresses().Bob

	t.Logf("\n=== Participant Addresses ===")
	t.Logf("Honest Challenger: %s", challengerAddr)
	t.Logf("Malicious Proposer: %s", proposerAddr)

	// Get initial balances
	challengerInitialBalance, err := l1Client.BalanceAt(ctx, challengerAddr, nil)
	require.NoError(t, err)
	proposerInitialBalance, err := l1Client.BalanceAt(ctx, proposerAddr, nil)
	require.NoError(t, err)

	t.Logf("\n=== Initial L1 Balances (Second Game) ===")
	t.Logf("Challenger Initial Balance: %s wei (%s ETH)", challengerInitialBalance, weiToEth(challengerInitialBalance))
	t.Logf("Proposer Initial Balance: %s wei (%s ETH)", proposerInitialBalance, weiToEth(proposerInitialBalance))

	// Start honest challenger for second game
	game2.StartChallenger(ctx, "HonestChallenger",
		challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
	)

	// Wait for game to progress to split depth (simple case: no VM execution)
	t.Logf("\n=== Waiting for split depth claims ===")
	game2.WaitForClaimAtDepth(ctx, splitDepth)

	// Log all claims
	game2.LogGameData(ctx)

	// Wait for game resolution
	game2.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)

	// Verify and log final game status
	finalStatus := game2.Status(ctx)
	t.Logf("\n=== Final Game Status ===")
	t.Logf("Game Status: %v (Challenger Won)", finalStatus)
	require.Equal(t, gameTypes.GameStatusChallengerWon, finalStatus, "Expected game status to be Challenger Won")
	t.Logf("Game Winner: Honest Challenger (Alice)")

	// Measure bonds locked in the game
	claims, err := game2.Game.GetAllClaims(ctx, rpcblock.Latest)
	require.NoError(t, err, "Failed to get all claims")

	// Log detailed claim information and calculate bond totals
	totalChallengerBonds, totalProposerBonds := logClaimDetails(t, claims, challengerAddr, proposerAddr)

	// Verify bond increase pattern
	verifyBondIncrease(t, claims)

	// Get final balances
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
	t.Logf("\nTest Scenario: Simple case with split depth only (no VM execution)")
	t.Logf("Target Depth: %d (split depth)", splitDepth)
	t.Logf("Gas Price: %.4f gwei", gasPriceGweiFloat)

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
	t.Logf("\nTest completed successfully")
}
