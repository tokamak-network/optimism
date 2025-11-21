package faultproofs

import (
	"context"
	"fmt"
	"testing"

	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/types"
	gameTypes "github.com/ethereum-optimism/optimism/op-challenger/game/types"
	"github.com/ethereum-optimism/optimism/op-e2e/config"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/challenger"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/disputegame"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/wait"
	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/require"
)

func TestOutputAsteriscGame(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscGame, WithAsteriscVMOnly[any]())
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
	RunTestAcrossVmTypes(t, testOutputAsteriscChallengeAllZeroClaim, WithAsteriscVMOnly[any]())
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
	}, WithTestName(testName), WithAsteriscVMOnly[TestCase]())
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
	}, WithTestName(testName), WithAsteriscVMOnly[TestCase]())
}

func TestOutputAsteriscDefendStep(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscDefendStep, WithAsteriscVMOnly[any]())
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

func TestOutputAsteriscProposedOutputRootValid(t *testing.T) {
	RunTestAcrossVmTypes(t, testOutputAsteriscProposedOutputRootValid_AttackWithCorrectTrace, WithAsteriscVMOnly[any]())
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
	RunTestAcrossVmTypes(t, testOutputAsteriscProposedOutputRootValid_DefendWithCorrectTrace, WithAsteriscVMOnly[any]())
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
	RunTestAcrossVmTypes(t, testOutputAsteriscPoisonedPostState, WithAsteriscVMOnly[any]())
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
