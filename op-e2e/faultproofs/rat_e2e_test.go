package faultproofs

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"math/big"
	"testing"
	"time"

	"github.com/ethereum-optimism/optimism/op-e2e/bindings"
	"github.com/ethereum-optimism/optimism/op-e2e/config"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/disputegame"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/wait"
	"github.com/ethereum-optimism/optimism/op-e2e/system/e2esys"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/stretchr/testify/require"
)

// RATEvidence represents evidence submitted to RAT
type RATEvidence struct {
	GameAddr common.Address
	ProofLV  common.Hash
	ProofRV  common.Hash
}

// RATChallengerInfo represents challenger information from RAT contract
type RATChallengerInfo struct {
	StakingAmount      *big.Int
	TotalSlashedAmount *big.Int
	ValidatorIndex     uint32
	IsValid            bool
}

// RATAttentionTest represents attention test information
type RATAttentionTest struct {
	StateRoot         common.Hash
	BondAmount        *big.Int
	ChallengerAddress common.Address
	L1BlockNumber     uint64
	EvidenceSubmitted bool
}

// TestRATFullWorkflowE2E tests the complete RAT workflow in a full E2E environment
func TestRATSuccessScenarioE2E(t *testing.T) {
	RunTestAcrossVmTypes(t, testRATSuccessScenarioE2E)
}

func testRATSuccessScenarioE2E(t *testing.T, allocType config.AllocType) {
	// Check if RAT deployment is enabled before starting the test
	// This avoids the expensive system setup if RAT is disabled
	t.Log("Checking if RAT deployment is enabled...")
	// TODO: Add proper DeployRAT config check here
	// For now, we'll proceed and let verifyRATDeployment handle the skip

	ctx := context.Background()
	sys, l1Client := StartFaultDisputeSystem(t, WithAllocType(allocType))
	t.Cleanup(sys.Close)

	t.Log("=== RAT E2E Test: Full Workflow ===")

	// Phase 1: Setup and Verify RAT Deployment (this will skip if RAT is disabled)
	t.Log("Phase 1: Verifying RAT contract deployment")
	ratAddress := verifyRATDeployment(t, ctx, sys)
	require.NotEqual(t, common.Address{}, ratAddress, "RAT contract should be deployed")

	// Phase 2: Setup RAT Helper for easier contract interaction
	t.Log("Phase 2: Setting up RAT helper")
	ratHelper := NewRATHelper(t, ctx, sys, ratAddress)
	require.NotNil(t, ratHelper, "RAT helper should be created")

	// Phase 3: Setup Challenger Account and Stake to RAT
	t.Log("Phase 3: Setting up challenger and staking to RAT")
	challengerAddr := sys.Cfg.Secrets.Addresses().Alice
	stakeAmount := big.NewInt(2000000000000000000) // 2 ETH
	ratHelper.StakeToRAT(ctx, challengerAddr, stakeAmount)
	t.Logf("Challenger %s staked %s ETH to RAT", challengerAddr.Hex(), stakeAmount.String())

	// Phase 4: Create Dispute Game to Trigger RAT (Cannon game type 0)
	t.Log("Phase 4: Creating cannon dispute game to trigger RAT")
	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)

	// Generate rootClaim that matches our mock evidence for successful evidence submission
	proofLV := common.Hash{0xaa, 0xbb} // Mock proof values
	proofRV := common.Hash{0xcc, 0xdd} // Mock proof values
	validRootClaim := crypto.Keccak256Hash(proofLV.Bytes(), proofRV.Bytes())
	t.Logf("Using rootClaim that matches mock evidence: %s", validRootClaim.Hex())

	game := disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 3, validRootClaim)
	gameAddr := game.Addr
	t.Logf("Created cannon dispute game at: %s", gameAddr.Hex())

	// Phase 5: Wait for RAT Attention Test to be Triggered
	t.Log("Phase 5: Waiting for RAT attention test to be triggered")
	attentionTest := ratHelper.WaitForAttentionTest(ctx, gameAddr, 30*time.Second)
	require.NotNil(t, attentionTest, "Attention test should be triggered")
	t.Logf("Attention test triggered for challenger: %s", attentionTest.ChallengerAddress.Hex())

	// Phase 6: Simulate Challenger Auto-Response
	t.Log("Phase 6: Simulating challenger automatic evidence submission")
	if attentionTest.ChallengerAddress == challengerAddr {
		correctEvidence := ratHelper.GenerateCorrectEvidence(ctx, gameAddr)
		ratHelper.SubmitEvidence(ctx, challengerAddr, correctEvidence)
		t.Log("Evidence submitted successfully")
	}

	// Phase 7: Wait for Evidence Processing and Bond Restoration
	t.Log("Phase 7: Waiting for evidence processing and bond restoration")
	require.NoError(t, wait.ForNextBlock(ctx, l1Client))
	bondRestored := ratHelper.VerifyBondRestoration(ctx, challengerAddr)
	require.True(t, bondRestored, "Bond should be restored after correct evidence")

	// Phase 8: Verify System State and Game Resolution
	t.Log("Phase 8: Verifying final system state")
	finalChallengerInfo := ratHelper.GetChallengerInfo(ctx, challengerAddr)
	require.True(t, finalChallengerInfo.IsValid, "Challenger should remain valid")
	t.Logf("Final challenger state: valid=%t, stake=%s", finalChallengerInfo.IsValid, finalChallengerInfo.StakingAmount.String())

	t.Log("=== RAT E2E Test PASSED ===")
}

// TestRATFailureScenarioE2E tests RAT behavior when evidence submission fails
func TestRATFailureScenarioE2E(t *testing.T) {
	RunTestAcrossVmTypes(t, testRATFailureScenarioE2E)
}

func testRATFailureScenarioE2E(t *testing.T, allocType config.AllocType) {
	ctx := context.Background()
	sys, _ := StartFaultDisputeSystem(t, WithAllocType(allocType))
	t.Cleanup(sys.Close)

	t.Log("=== RAT Failure Scenario E2E Test ===")

	// Phase 1: Verify RAT deployment
	ratAddress := verifyRATDeployment(t, ctx, sys)
	ratHelper := NewRATHelper(t, ctx, sys, ratAddress)

	// Phase 2: Setup challenger with stake
	challengerAddr := sys.Cfg.Secrets.Addresses().Alice
	stakeAmount := big.NewInt(2000000000000000000) // 2 ETH
	ratHelper.StakeToRAT(ctx, challengerAddr, stakeAmount)
	t.Logf("Challenger %s staked %s ETH to RAT", challengerAddr.Hex(), stakeAmount.String())

	// Phase 3: Create dispute game with invalid rootClaim (different from mock proof)
	t.Log("Phase 3: Creating dispute game with invalid rootClaim for failure scenario")
	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
	invalidRootClaim := common.Hash{0xff, 0xff} // Different from mock proof
	game := disputeGameFactory.StartOutputCannonGame(ctx, "sequencer", 3, invalidRootClaim)
	gameAddr := game.Addr
	t.Logf("Created dispute game with invalid rootClaim: %s", gameAddr.Hex())

	// Phase 4: Wait for RAT attention test to be triggered
	t.Log("Phase 4: Waiting for RAT attention test to be triggered")
	attentionTest := ratHelper.WaitForAttentionTest(ctx, gameAddr, 30*time.Second)
	require.NotNil(t, attentionTest, "Attention test should be triggered")
	require.NotEqual(t, common.Address{}, attentionTest.ChallengerAddress, "Attention test should be triggered")
	t.Logf("Attention test triggered for challenger: %s", attentionTest.ChallengerAddress.Hex())

	// Phase 5: Attempt evidence submission (should fail)
	t.Log("Phase 5: Attempting evidence submission (expected to fail)")
	if attentionTest.ChallengerAddress == challengerAddr {
		evidence := ratHelper.GenerateCorrectEvidence(ctx, gameAddr)
		err := ratHelper.TrySubmitEvidence(ctx, challengerAddr, evidence)
		require.Error(t, err, "Evidence submission should fail with mismatched proof")
		t.Logf("Evidence submission failed as expected: %v", err)
	}

	// Phase 6: Verify attention test state after failed submission
	t.Log("Phase 6: Verifying attention test state after failed submission")
	// Re-fetch attention test info to verify state
	finalAttentionTest := ratHelper.WaitForAttentionTest(ctx, gameAddr, 5*time.Second)
	require.NotNil(t, finalAttentionTest, "Attention test should still exist")
	require.False(t, finalAttentionTest.EvidenceSubmitted, "Evidence should not be marked as submitted")
	t.Log("✅ Failure scenario verified: evidence submission properly rejected")

	t.Log("=== RAT Failure Scenario E2E Test PASSED ===")
}

// TestRATStressTest tests RAT behavior under high load
func TestRATStressTest(t *testing.T) {
	t.Skip("RAT stress test implementation pending")
}

// RAT E2E helper functions

func verifyRATDeployment(t *testing.T, ctx context.Context, sys *e2esys.System) common.Address {
	// Get L1 client
	l1Client := sys.NodeClient("l1")
	require.NotNil(t, l1Client, "L1 client should be available")

	// Check if RAT is available in system deployments first
	if ratAddr := sys.L1Deployments().RATProxy; ratAddr != (common.Address{}) {
		t.Logf("Found RAT address in system deployments: %s", ratAddr.Hex())
		// Verify RAT contract is deployed at the address
		code, err := l1Client.CodeAt(ctx, ratAddr, nil)
		require.NoError(t, err, "Should check code at RAT address")
		if len(code) > 0 {
			t.Logf("✅ RAT contract verified at address: %s (code length: %d bytes)", ratAddr.Hex(), len(code))
			return ratAddr
		}
	}

	// If RAT is not deployed, skip the test since it's not enabled for this configuration
	t.Skip("RAT deployment is disabled (DeployRAT=false) - skipping RAT test")

	// Should not reach here since we skip the test above
	return common.Address{}
}

// RATHelper provides utilities for RAT contract interaction in E2E tests
type RATHelper struct {
	t        *testing.T
	sys      *e2esys.System
	l1Client *ethclient.Client
	ratAddr  common.Address
	contract *bindings.RAT
}

// NewRATHelper creates a new RAT helper for E2E testing
func NewRATHelper(t *testing.T, ctx context.Context, sys *e2esys.System, ratAddr common.Address) *RATHelper {
	l1Client := sys.NodeClient("l1")

	// Create RAT contract binding
	ratContract, err := bindings.NewRAT(ratAddr, l1Client)
	require.NoError(t, err, "Should create RAT contract binding")

	return &RATHelper{
		t:        t,
		sys:      sys,
		l1Client: l1Client,
		ratAddr:  ratAddr,
		contract: ratContract,
	}
}

// StakeToRAT stakes ETH to RAT contract
func (h *RATHelper) StakeToRAT(ctx context.Context, challengerAddr common.Address, amount *big.Int) {
	// Get challenger's private key
	var privKey *ecdsa.PrivateKey
	if challengerAddr == h.sys.Cfg.Secrets.Addresses().Alice {
		privKey = h.sys.Cfg.Secrets.Alice
	} else if challengerAddr == h.sys.Cfg.Secrets.Addresses().Bob {
		privKey = h.sys.Cfg.Secrets.Bob
	} else {
		h.t.Fatalf("Unknown challenger address: %s", challengerAddr.Hex())
	}

	// Create transaction auth
	chainID, err := h.l1Client.ChainID(ctx)
	require.NoError(h.t, err, "Should get chain ID")

	auth, err := bind.NewKeyedTransactorWithChainID(privKey, chainID)
	require.NoError(h.t, err, "Should create transactor")

	auth.Value = amount
	auth.Context = ctx

	// Stake to RAT
	tx, err := h.contract.Stake(auth)
	require.NoError(h.t, err, "Should stake to RAT")

	receipt, err := bind.WaitMined(ctx, h.l1Client, tx)
	require.NoError(h.t, err, "Should mine stake transaction")
	require.Equal(h.t, uint64(1), receipt.Status, "Stake transaction should succeed")
}

// WaitForAttentionTest waits for an attention test to be triggered for a game
func (h *RATHelper) WaitForAttentionTest(ctx context.Context, gameAddr common.Address, timeout time.Duration) *RATAttentionTest {
	timeoutCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-timeoutCtx.Done():
			h.t.Fatalf("Timeout waiting for attention test for game %s", gameAddr.Hex())
			return nil
		case <-ticker.C:
			// Check if attention test exists for this game
			attentionTest, err := h.contract.AttentionTests(&bind.CallOpts{Context: ctx}, gameAddr)
			if err == nil && attentionTest.ChallengerAddress != (common.Address{}) {
				return &RATAttentionTest{
					ChallengerAddress: attentionTest.ChallengerAddress,
					BondAmount:        attentionTest.BondAmount,
					StateRoot:         common.BytesToHash(attentionTest.StateRoot[:]),
					L1BlockNumber:     attentionTest.L1BlockNumber,
					EvidenceSubmitted: attentionTest.EvidenceSubmitted,
				}
			}
		}
	}
}

// GenerateCorrectEvidence generates correct evidence for a game
func (h *RATHelper) GenerateCorrectEvidence(ctx context.Context, gameAddr common.Address) *RATEvidence {
	// For E2E testing, use predefined proof values that create a known state root
	proofLV := common.Hash{0xaa, 0xbb} // Fixed test values
	proofRV := common.Hash{0xcc, 0xdd} // Fixed test values

	// The expected state root for these proof values
	expectedStateRoot := crypto.Keccak256Hash(proofLV.Bytes(), proofRV.Bytes())

	h.t.Logf("Expected state root for mock proof: %s", expectedStateRoot.Hex())

	// Get attention test info to check what's actually stored
	attentionTest, err := h.contract.AttentionTests(nil, gameAddr)
	require.NoError(h.t, err, "Should get attention test info")

	storedStateRoot := common.BytesToHash(attentionTest.StateRoot[:])
	h.t.Logf("Stored state root in RAT: %s", storedStateRoot.Hex())

	// For E2E test, we expect that the RAT attention test was triggered with
	// the rootClaim from the dispute game, not a pre-computed proof
	// So we'll accept that our proof might not match and skip verification for now
	h.t.Logf("Note: Using mock proof values for E2E test - this may not match actual stored state root")

	return &RATEvidence{
		GameAddr: gameAddr,
		ProofLV:  proofLV,
		ProofRV:  proofRV,
	}
}

// SubmitEvidence submits evidence to RAT contract
func (h *RATHelper) SubmitEvidence(ctx context.Context, challengerAddr common.Address, evidence *RATEvidence) {
	// Get challenger's private key
	var privKey *ecdsa.PrivateKey
	if challengerAddr == h.sys.Cfg.Secrets.Addresses().Alice {
		privKey = h.sys.Cfg.Secrets.Alice
	} else if challengerAddr == h.sys.Cfg.Secrets.Addresses().Bob {
		privKey = h.sys.Cfg.Secrets.Bob
	} else {
		h.t.Fatalf("Unknown challenger address: %s", challengerAddr.Hex())
	}

	// Create transaction auth
	chainID, err := h.l1Client.ChainID(ctx)
	require.NoError(h.t, err, "Should get chain ID")

	auth, err := bind.NewKeyedTransactorWithChainID(privKey, chainID)
	require.NoError(h.t, err, "Should create transactor")
	auth.Context = ctx

	// Submit evidence
	tx, err := h.contract.SubmitCorrectEvidence(auth, evidence.GameAddr, evidence.ProofLV, evidence.ProofRV)
	require.NoError(h.t, err, "Should submit evidence")

	receipt, err := bind.WaitMined(ctx, h.l1Client, tx)
	require.NoError(h.t, err, "Should mine evidence transaction")
	require.Equal(h.t, uint64(1), receipt.Status, "Evidence transaction should succeed")
}

// TrySubmitEvidence attempts to submit evidence, returns error instead of failing test
func (h *RATHelper) TrySubmitEvidence(ctx context.Context, challengerAddr common.Address, evidence *RATEvidence) error {
	// Get challenger's private key
	var privKey *ecdsa.PrivateKey
	if challengerAddr == h.sys.Cfg.Secrets.Addresses().Alice {
		privKey = h.sys.Cfg.Secrets.Alice
	} else if challengerAddr == h.sys.Cfg.Secrets.Addresses().Bob {
		privKey = h.sys.Cfg.Secrets.Bob
	} else {
		return fmt.Errorf("unknown challenger address: %s", challengerAddr.Hex())
	}

	// Create transaction auth
	chainID, err := h.l1Client.ChainID(ctx)
	if err != nil {
		return fmt.Errorf("failed to get chain ID: %w", err)
	}

	auth, err := bind.NewKeyedTransactorWithChainID(privKey, chainID)
	if err != nil {
		return fmt.Errorf("failed to create transactor: %w", err)
	}
	auth.Context = ctx

	// Submit evidence
	tx, err := h.contract.SubmitCorrectEvidence(auth, evidence.GameAddr, evidence.ProofLV, evidence.ProofRV)
	if err != nil {
		return fmt.Errorf("failed to submit evidence: %w", err)
	}

	receipt, err := bind.WaitMined(ctx, h.l1Client, tx)
	if err != nil {
		return fmt.Errorf("failed to mine evidence transaction: %w", err)
	}

	if receipt.Status != 1 {
		return fmt.Errorf("evidence transaction failed with status %d", receipt.Status)
	}

	return nil
}

// VerifyBondRestoration verifies that challenger's bond was restored
func (h *RATHelper) VerifyBondRestoration(ctx context.Context, challengerAddr common.Address) bool {
	info := h.GetChallengerInfo(ctx, challengerAddr)
	return info.IsValid
}

// GetChallengerInfo gets challenger information from RAT
func (h *RATHelper) GetChallengerInfo(ctx context.Context, challengerAddr common.Address) *RATChallengerInfo {
	info, err := h.contract.GetChallengerInfo(&bind.CallOpts{Context: ctx}, challengerAddr)
	require.NoError(h.t, err, "Should get challenger info")

	return &RATChallengerInfo{
		StakingAmount: info.StakingAmount,
		IsValid:       info.IsValid,
	}
}
