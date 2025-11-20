package faultproofs

import (
	"context"
	"fmt"
	"strconv"
	"testing"

	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/trace/utils"
	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/types"
	gameTypes "github.com/ethereum-optimism/optimism/op-challenger/game/types"
	"github.com/ethereum-optimism/optimism/op-e2e/config"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/challenger"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/disputegame"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/disputegame/preimage"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/wait"
	oppreimage "github.com/ethereum-optimism/optimism/op-preimage"
	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/require"
)

func TestOutputAsteriscGame(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscGame)
}

func testOutputAsteriscGame(t *testing.T, allocType config.AllocType) {
	ctx := context.Background()
	sys, _ := StartFaultDisputeSystem(t, WithAllocType(allocType))
	t.Cleanup(sys.Close)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
	game := disputeGameFactory.StartOutputAsteriscGame(ctx, "sequencer", 4, common.Hash{0x01})
	arena := createOutputGameArena(t, sys, game)
	testCannonGame(t, ctx, arena, &game.SplitGameHelper)
}

func TestOutputAsterisc_ChallengeAllZeroClaim(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscChallengeAllZeroClaim)
}

func testOutputAsteriscChallengeAllZeroClaim(t *testing.T, allocType config.AllocType) {
	// The dishonest actor always posts claims with all zeros.
	ctx := context.Background()
	sys, _ := StartFaultDisputeSystem(t, WithAllocType(allocType))
	t.Cleanup(sys.Close)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
	game := disputeGameFactory.StartOutputAsteriscGame(ctx, "sequencer", 3, common.Hash{})
	arena := createOutputGameArena(t, sys, game)
	testCannonChallengeAllZeroClaim(t, ctx, arena, &game.SplitGameHelper)
}

func TestOutputAsterisc_PublishAsteriscRootClaim(t *testing.T) {
	type TestCase struct {
		disputeL2BlockNumber uint64
	}
	testName := func(vm string, test TestCase) string {
		return fmt.Sprintf("Dispute_%v_%v", test.disputeL2BlockNumber, vm)
	}
	tests := []TestCase{
		{7}, // Post-state output root is invalid
		{8}, // Post-state output root is valid
	}

	RunTestsAcrossVmTypes(t, tests, func(t *testing.T, allocType config.AllocType, test TestCase) {
		ctx := context.Background()
		sys, _ := StartFaultDisputeSystem(t, WithAllocType(allocType))

		disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
		game := disputeGameFactory.StartOutputAsteriscGame(ctx, "sequencer", test.disputeL2BlockNumber, common.Hash{0x01})
		game.DisputeLastBlock(ctx)
		game.LogGameData(ctx)

		game.StartChallenger(ctx, "Challenger",
			challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
			challenger.WithAsterisc(t, sys))

		splitDepth := game.SplitDepth(ctx)
		game.WaitForClaimAtDepth(ctx, splitDepth+1)
	}, WithTestName(testName))
}

func TestOutputAsteriscDisputeGame(t *testing.T) {
	type TestCase struct {
		name             string
		defendClaimDepth types.Depth
	}
	testName := func(vm string, test TestCase) string {
		return fmt.Sprintf("%v-%v", test.name, vm)
	}
	tests := []TestCase{
		{"StepFirst", 0},
		{"StepMiddle", 28},
		{"StepInExtension", 1},
	}

	RunTestsAcrossVmTypes(t, tests, func(t *testing.T, allocType config.AllocType, test TestCase) {
		ctx := context.Background()
		sys, l1Client := StartFaultDisputeSystem(t, WithAllocType(allocType))
		t.Cleanup(sys.Close)

		disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
		game := disputeGameFactory.StartOutputAsteriscGame(ctx, "sequencer", 1, common.Hash{0x01, 0xaa})
		require.NotNil(t, game)
		game.LogGameData(ctx)

		outputClaim := game.DisputeLastBlock(ctx)
		splitDepth := game.SplitDepth(ctx)

		game.StartChallenger(ctx, "Challenger",
			challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
			challenger.WithAsterisc(t, sys))

		game.DefendClaim(
			ctx,
			outputClaim,
			func(claim *disputegame.ClaimHelper) *disputegame.ClaimHelper {
				if claim.Depth()+1 == splitDepth+test.defendClaimDepth {
					return claim.Defend(ctx, common.Hash{byte(claim.Depth())})
				} else {
					return claim.Attack(ctx, common.Hash{byte(claim.Depth())})
				}
			})

		sys.TimeTravelClock.AdvanceTime(game.MaxClockDuration(ctx))
		require.NoError(t, wait.ForNextBlock(ctx, l1Client))

		game.LogGameData(ctx)
		game.WaitForGameStatus(ctx, gameTypes.GameStatusChallengerWon)
	}, WithTestName(testName))
}

func TestOutputAsteriscDefendStep(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscDefendStep)
}

func testOutputAsteriscDefendStep(t *testing.T, allocType config.AllocType) {
	ctx := context.Background()
	sys, _ := StartFaultDisputeSystem(t, WithAllocType(allocType))
	t.Cleanup(sys.Close)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
	game := disputeGameFactory.StartOutputAsteriscGame(ctx, "sequencer", 1, common.Hash{0x01, 0xaa})
	arena := createOutputGameArena(t, sys, game)
	testCannonDefendStep(t, ctx, arena, &game.SplitGameHelper)
}

func TestOutputAsteriscStepWithLargePreimage(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscStepWithLargePreimage)
}

func testOutputAsteriscStepWithLargePreimage(t *testing.T, allocType config.AllocType) {
	ctx := context.Background()
	sys, _ := StartFaultDisputeSystem(t, WithBatcherStopped(), WithAllocType(allocType))
	t.Cleanup(sys.Close)

	// Manually send a tx from the correct batcher key to the batcher input with very large (invalid) data
	// This forces op-program to load a large preimage.
	sys.BatcherHelper().SendLargeInvalidBatch(ctx)

	require.NoError(t, sys.BatchSubmitter.Start(ctx))

	safeHead, err := wait.ForNextSafeBlock(ctx, sys.NodeClient("sequencer"))
	require.NoError(t, err, "Batcher should resume submitting valid batches")

	l2BlockNumber := safeHead.NumberU64()
	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
	// Dispute any block - it will have to read the L1 batches to see if the block is reached
	game := disputeGameFactory.StartOutputAsteriscGame(ctx, "sequencer", l2BlockNumber, common.Hash{0x01, 0xaa})
	require.NotNil(t, game)
	outputRootClaim := game.DisputeBlock(ctx, l2BlockNumber)
	game.LogGameData(ctx)

	game.StartChallenger(ctx, "Challenger",
		challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
		challenger.WithAsterisc(t, sys))

	// Wait for the honest challenger to dispute the outputRootClaim.
	// This creates a root of an execution game that we challenge by
	// coercing a step at a preimage trace index.
	outputRootClaim = outputRootClaim.WaitForCounterClaim(ctx)

	game.LogGameData(ctx)
	// Now the honest challenger is positioned as the defender of the
	// execution game. We then move to challenge it to induce a large preimage load.
	sender := sys.Cfg.Secrets.Addresses().Alice
	preimageLoadCheck := game.CreateStepLargePreimageLoadCheck(ctx, sender)
	providerFunc := game.NewMemoizedAsteriscTraceProvider(ctx, "sequencer", outputRootClaim, challenger.WithPrivKey(sys.Cfg.Secrets.Alice))
	game.ChallengeToAsteriscPreimageLoad(ctx, providerFunc, utils.PreimageLargerThan(preimage.MinPreimageSize), preimageLoadCheck, false)
	// The above method already verified the image was uploaded and step called successfully
	// So we don't waste time resolving the game - that's tested elsewhere.
}

func TestOutputAsteriscStepWithPreimage_nonExistingPreimage(t *testing.T) {
	type TestCase struct {
		name         string
		preimageType oppreimage.KeyType
		opts         []disputegame.FindPreimageStepOpt
	}
	testName := func(vm string, test TestCase) string {
		return fmt.Sprintf("%v-%v", test.name, vm)
	}
	tests := []TestCase{
		{name: "keccak", preimageType: oppreimage.Keccak256KeyType},
		// Sha256 preimages are relatively rare, so allow fallback to even step to avoid flakes
		{name: "sha256", preimageType: oppreimage.Sha256KeyType, opts: []disputegame.FindPreimageStepOpt{disputegame.AllowEvenFallback()}},
	}

	RunTestsAcrossVmTypes(t, tests, func(t *testing.T, allocType config.AllocType, testcase TestCase) {
		conf := utils.PreimageOptConfigForType(oppreimage.Keccak256KeyType)
		testAsteriscPreimageStep(t, allocType, conf, false, testcase.opts...)
	}, WithTestName(testName))
}

func TestOutputAsteriscStepWithPreimage_nonExistingBlobPreimage(t *testing.T) {
	type TestCase struct {
		blobOffset    uint32
		blobSkipCount int
	}
	testName := func(vm string, test TestCase) string {
		return fmt.Sprintf("non-existing preimage-blob-%v skip-%v [%v]", strconv.Itoa(int(test.blobOffset)), test.blobSkipCount, vm)
	}

	testCases := make([]TestCase, 0)
	blobOffsets := []uint32{0, 8, 16, 24, 32}
	skipCounts := []int{0, 1, 2, 11}
	for _, offset := range blobOffsets {
		for _, skip := range skipCounts {
			testCases = append(testCases, TestCase{blobOffset: offset, blobSkipCount: skip})
		}
	}

	RunTestsAcrossVmTypes(t, testCases, func(t *testing.T, allocType config.AllocType, testcase TestCase) {
		conf := utils.PreimageOptConfigForType(oppreimage.BlobKeyType)
		conf.Offset = testcase.blobOffset

		// In order to target non-zero blob field indices, skip some preimage load steps.
		// Because field elements are retrieved sequentially, this should ensure we advance to
		// a field element at an index >= skip
		testAsteriscPreimageStep(t, allocType, conf, false, disputegame.SkipNPreimageLoads(testcase.blobSkipCount))
	}, WithTestName(testName))
}

func TestOutputAsteriscStepWithPreimage_existingPreimage(t *testing.T) {
	// Only test pre-existing images with one type to save runtime
	RunTestAcrossVmTypes(t, func(t *testing.T, allocType config.AllocType) {
		conf := utils.PreimageOptConfigForType(oppreimage.Keccak256KeyType)
		testAsteriscPreimageStep(t, allocType, conf, true)
	})
}

func testAsteriscPreimageStep(t *testing.T, allocType config.AllocType, preimageOptConfig utils.PreimageOptConfig, preloadPreimage bool, opts ...disputegame.FindPreimageStepOpt) {
	ctx := context.Background()
	sys, _ := StartFaultDisputeSystem(t, WithBlobBatches(), WithAllocType(allocType))
	t.Cleanup(sys.Close)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
	game := disputeGameFactory.StartOutputAsteriscGame(ctx, "sequencer", 1, common.Hash{0x01, 0xaa})
	require.NotNil(t, game)
	outputRootClaim := game.DisputeLastBlock(ctx)
	game.LogGameData(ctx)

	game.StartChallenger(ctx, "Challenger",
		challenger.WithPrivKey(sys.Cfg.Secrets.Alice),
		challenger.WithAsterisc(t, sys))

	// Wait for the honest challenger to dispute the outputRootClaim. This creates a root of an execution game that we challenge by coercing
	// a step at a preimage trace index.
	outputRootClaim = outputRootClaim.WaitForCounterClaim(ctx)

	// Now the honest challenger is positioned as the defender of the execution game
	// We then move to challenge it to induce a preimage load
	// Check that the preimage is loaded into the oracle with data matching our expectation
	getExpectedData := func(p *types.PreimageOracleData) (bool, [32]byte) { return true, game.GetPreimageAtOffset(p) }
	preimageLoadCheck := game.CreateStepPreimageLoadStrictCheck(ctx, getExpectedData)
	// We need the honest challenger to step-defend the STF from A -> B such that A loads the preimage
	// The ChallengeToPreimageLoadAtTarget method will induce a step-defend on odd numbered trace index from the honest challenger.
	providerFunc := game.NewMemoizedCannonTraceProvider(ctx, "sequencer", outputRootClaim, challenger.WithPrivKey(sys.Cfg.Secrets.Alice))
	step := game.FindOddStepForPreimageLoad(ctx, providerFunc, preimageOptConfig, opts...)
	game.ChallengeToPreimageLoadAtTarget(ctx, providerFunc, step, preimageLoadCheck, preloadPreimage)
	// The above method already verified the image was uploaded and step called successfully
	// So we don't waste time resolving the game - that's tested elsewhere.

	// Finally, validate that we can manually invoke step at this point in the game and produce the expected post-state
	game.VerifyPreimageAtTarget(ctx, providerFunc, step, game.GetOracleKeyPrefixValidator(preimageOptConfig.KeyPrefix), false)
}

func TestOutputAsteriscProposedOutputRootValid(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscProposedOutputRootValid_AttackWithCorrectTrace)
}

func testOutputAsteriscProposedOutputRootValid_AttackWithCorrectTrace(t *testing.T, allocType config.AllocType) {
	ctx := context.Background()
	sys, _ := StartFaultDisputeSystem(t, WithAllocType(allocType))
	t.Cleanup(sys.Close)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
	game := disputeGameFactory.StartOutputAsteriscGameWithCorrectRoot(ctx, "sequencer", 1)
	arena := createOutputGameArena(t, sys, game)
	testCannonProposalValid_AttackWithCorrectTrace(t, ctx, arena, &game.SplitGameHelper)
}

func TestOutputAsteriscProposedOutputRootValid_DefendWithCorrectTrace(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscProposedOutputRootValid_DefendWithCorrectTrace)
}

func testOutputAsteriscProposedOutputRootValid_DefendWithCorrectTrace(t *testing.T, allocType config.AllocType) {
	ctx := context.Background()
	sys, _ := StartFaultDisputeSystem(t, WithAllocType(allocType))
	t.Cleanup(sys.Close)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
	game := disputeGameFactory.StartOutputAsteriscGameWithCorrectRoot(ctx, "sequencer", 1)
	arena := createOutputGameArena(t, sys, game)
	testCannonProposalValid_DefendWithCorrectTrace(t, ctx, arena, &game.SplitGameHelper)
}

func TestOutputAsteriscPoisonedPostState(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscPoisonedPostState)
}

func testOutputAsteriscPoisonedPostState(t *testing.T, allocType config.AllocType) {
	ctx := context.Background()
	sys, _ := StartFaultDisputeSystem(t, WithAllocType(allocType))
	t.Cleanup(sys.Close)

	disputeGameFactory := disputegame.NewFactoryHelper(t, ctx, sys)
	// Root claim is dishonest
	game := disputeGameFactory.StartOutputAsteriscGame(ctx, "sequencer", 1, common.Hash{0xaa})
	arena := createOutputGameArena(t, sys, game)
	testCannonPoisonedPostState(t, ctx, arena, &game.SplitGameHelper)
}
