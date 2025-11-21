package disputegame

import (
	"context"
	"errors"
	"io"
	"math/big"
	"path/filepath"
	"testing"

	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/trace"
	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/trace/asterisc"
	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/trace/outputs"
	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/trace/split"
	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/trace/utils"
	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/types"
	"github.com/ethereum-optimism/optimism/op-challenger/metrics"
	"github.com/ethereum-optimism/optimism/op-e2e/bindings"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/challenger"
	"github.com/ethereum-optimism/optimism/op-e2e/e2eutils/transactions"
	"github.com/ethereum-optimism/optimism/op-service/sources/batching"
	"github.com/ethereum-optimism/optimism/op-service/sources/batching/rpcblock"
	"github.com/ethereum-optimism/optimism/op-service/testlog"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/log"
	"github.com/stretchr/testify/require"
)

type AsteriscTraceProviderFunc func() (*asterisc.AsteriscTraceProviderForTest, common.Hash, *ClaimHelper)

// NewMemoizedAsteriscTraceProvider returns a function that will generate an asterisc trace provider once, memoize it
// and return the same trace provider on subsequent calls
func (g *CannonHelper) NewMemoizedAsteriscTraceProvider(ctx context.Context, l2Node string, outputRootClaim *ClaimHelper, options ...challenger.Option) AsteriscTraceProviderFunc {
	var provider *asterisc.AsteriscTraceProviderForTest
	var localContext common.Hash
	return func() (*asterisc.AsteriscTraceProviderForTest, common.Hash, *ClaimHelper) {
		if provider == nil {
			provider, localContext = g.createAsteriscTraceProvider(ctx, l2Node, outputRootClaim, options...)
		}
		return provider, localContext, outputRootClaim
	}
}

func (g *CannonHelper) createAsteriscTraceProvider(ctx context.Context, l2Node string, outputRootClaim *ClaimHelper, options ...challenger.Option) (*asterisc.AsteriscTraceProviderForTest, common.Hash) {
	splitDepth := g.splitGame.SplitDepth(ctx)
	g.require.EqualValues(outputRootClaim.Depth(), splitDepth+1, "outputRootClaim must be the root of an execution game")

	logger := testlog.Logger(g.t, log.LevelInfo).New("role", "AsteriscTraceProvider", "game", g.splitGame.Addr)
	opt := g.defaultChallengerOptions()
	opt = append(opt, options...)
	cfg := challenger.NewChallengerConfig(g.t, g.system, l2Node, opt...)

	l2Client := g.system.NodeClient(l2Node)

	prestateBlock, poststateBlock, err := g.splitGame.Game.GetGameRange(ctx)
	g.require.NoError(err, "Failed to load block range")
	rollupClient := g.system.RollupClient(l2Node)
	prestateProvider := outputs.NewPrestateProvider(rollupClient, prestateBlock)
	l1Head := g.splitGame.GetL1Head(ctx)
	outputProvider := outputs.NewTraceProvider(logger, prestateProvider, rollupClient, l2Client, l1Head, splitDepth, prestateBlock, poststateBlock)

	var localContext common.Hash
	selector := split.NewSplitProviderSelector(outputProvider, splitDepth, func(ctx context.Context, depth types.Depth, pre types.Claim, post types.Claim) (types.TraceProvider, error) {
		agreed, disputed, err := outputs.FetchProposals(ctx, outputProvider, pre, post)
		g.require.NoError(err)
		g.t.Logf("Using trace between blocks %v and %v\n", agreed.L2BlockNumber, disputed.L2BlockNumber)
		localInputs, err := utils.FetchLocalInputsFromProposals(ctx, l1Head.Hash, l2Client, agreed, disputed)
		g.require.NoError(err, "Failed to fetch local inputs")
		localContext = split.CreateLocalContext(pre, post)
		dir := filepath.Join(cfg.Datadir, "asterisc-trace")
		subdir := filepath.Join(dir, localContext.Hex())
		return asterisc.NewTraceProviderForTest(logger, metrics.NoopMetrics.ToTypedVmMetrics(types.TraceTypeAsterisc.String()), cfg, localInputs, subdir, g.splitGame.MaxDepth(ctx)-splitDepth-1), nil
	})

	claims, err := g.splitGame.Game.GetAllClaims(ctx, rpcblock.Latest)
	g.require.NoError(err)
	game := types.NewGameState(claims, g.splitGame.MaxDepth(ctx))

	provider, err := selector(ctx, game, game.Claims()[outputRootClaim.ParentIndex], outputRootClaim.Position)
	g.require.NoError(err)
	translatingProvider := provider.(*trace.TranslatingProvider)
	return translatingProvider.Original().(*asterisc.AsteriscTraceProviderForTest), localContext
}

func (g *CannonHelper) FindOddStepForAsteriscPreimageLoad(ctx context.Context, asteriscTraceProviderFunc AsteriscTraceProviderFunc, poConfig utils.PreimageOptConfig, opts ...FindPreimageStepOpt) uint64 {
	config := &FindPreimageStepConfig{}
	for _, opt := range opts {
		opt(config)
	}

	provider, _, _ := asteriscTraceProviderFunc()

	var preimageOpt utils.PreimageOpt
	var lastStep uint64 = 0
	// First, if requested, skip some number of preimage loads
	for i := 0; i < config.skipNPreimageLoads; i++ {
		preimageOpt = poConfig.PreimageLoad()
		g.t.Logf("Skipping preimage load %v: %#v", i, poConfig)
		step, err := provider.FindStep(ctx, lastStep, preimageOpt)
		g.require.NoError(err)

		lastStep = step
		poConfig.AfterStep = step + 1
	}

	lastSkippedStep := lastStep
	for {
		preimageOpt = poConfig.PreimageLoad()
		g.t.Logf("Finding step with preimage load config %#v", poConfig)
		step, err := provider.FindStep(ctx, lastStep, preimageOpt)
		if errors.Is(err, io.EOF) {
			// Unlikely to happen if many preimage loads of the target type occur
			// Can cause flakes if the target preimage type is not used often
			if config.allowEvenFallback && lastStep > lastSkippedStep {
				// If we have advanced the last step past the last skipped step, then the lastStep must be even.
				// Otherwise, the last step was odd and we should have returned it.
				g.t.Log("Unable to find odd step that matches the specified preimage load - falling back to an even step")
				return lastStep
			} else {
				g.t.Fatalf("Trace does not contain an odd step that matches the specified preimage load")
			}
		}
		g.require.NoError(err, "Find step failed")
		if step%2 == 1 {
			return step
		}
		lastStep = step
		poConfig.AfterStep = step + 1
	}
}

// ChallengeToPreimageLoad challenges the supplied execution root claim by inducing a step that requires a preimage to be loaded for Asterisc
func (g *CannonHelper) ChallengeToAsteriscPreimageLoad(ctx context.Context, asteriscTraceProviderFunc AsteriscTraceProviderFunc, preimage utils.PreimageOpt, preimageCheck PreimageLoadCheck, preloadPreimage bool) {
	// Identifying the first state transition that loads a global preimage
	provider, _, _ := asteriscTraceProviderFunc()
	targetTraceIndex, err := provider.FindStep(ctx, 0, preimage)
	g.require.NoError(err)
	g.ChallengeToAsteriscPreimageLoadAtTarget(ctx, asteriscTraceProviderFunc, targetTraceIndex, preimageCheck, preloadPreimage)
}

// ChallengeToAsteriscPreimageLoadAtTarget challenges the supplied execution root claim by inducing a step that requires a preimage to be loaded at a specific target for Asterisc
func (g *CannonHelper) ChallengeToAsteriscPreimageLoadAtTarget(ctx context.Context, asteriscTraceProviderFunc AsteriscTraceProviderFunc, targetTraceIndex uint64, preimageCheck PreimageLoadCheck, preloadPreimage bool) {
	provider, _, outputRootClaim := asteriscTraceProviderFunc()
	splitDepth := g.splitGame.SplitDepth(ctx)
	execDepth := g.splitGame.ExecDepth(ctx)
	g.require.NotEqual(outputRootClaim.Position.TraceIndex(execDepth).Uint64(), targetTraceIndex, "cannot move to defend a terminal trace index")
	g.require.EqualValues(splitDepth+1, outputRootClaim.Depth(), "supplied claim must be the root of an execution game")
	g.require.EqualValues(execDepth%2, 1, "execution game depth must be odd") // since we're challenging the execution root claim

	if preloadPreimage {
		g.t.Logf("🔍 Getting step data for target trace index %d (this may take several minutes)...", targetTraceIndex)
		_, _, preimageData, err := provider.GetStepData(ctx, types.NewPosition(execDepth, big.NewInt(int64(targetTraceIndex))))
		g.require.NoError(err)
		g.t.Logf("✅ Step data retrieved successfully, now uploading preimage...")
		g.UploadPreimage(ctx, preimageData)
		g.WaitForPreimageInOracle(ctx, preimageData)
	}

	bisectTraceIndex := func(claim *ClaimHelper) *ClaimHelper {
		return traceBisectionAsterisc(g.t, ctx, claim, splitDepth, execDepth, targetTraceIndex, provider)
	}
	// Initial bisect to put us on defense
	mover := bisectTraceIndex(outputRootClaim)
	// Descending the execution game tree to reach the step that loads the preimage
	leafClaim := g.splitGame.DefendClaim(ctx, mover, bisectTraceIndex, WithoutWaitingForStep())

	// Validate that the preimage was loaded correctly
	g.require.NoError(preimageCheck(provider, targetTraceIndex))

	// Now the preimage is available wait for the step call to succeed.
	leafClaim.WaitForCountered(ctx)
	g.splitGame.LogGameData(ctx)
}

func traceBisectionAsterisc(
	t *testing.T,
	ctx context.Context,
	claim *ClaimHelper,
	splitDepth types.Depth,
	execDepth types.Depth,
	targetTraceIndex uint64,
	provider *asterisc.AsteriscTraceProviderForTest,
) *ClaimHelper {
	execClaimPosition, err := claim.Position.RelativeToAncestorAtDepth(splitDepth + 1)
	require.NoError(t, err)

	claimTraceIndex := execClaimPosition.TraceIndex(execDepth).Uint64()
	t.Logf("Bisecting: Into targetTraceIndex %v: claimIndex=%v at depth=%v. claimPosition=%v execClaimPosition=%v claimTraceIndex=%v",
		targetTraceIndex, claim.Index, claim.Depth(), claim.Position, execClaimPosition, claimTraceIndex)

	// We always want to position ourselves such that the challenger generates proofs for the targetTraceIndex as prestate
	if execClaimPosition.Depth() == execDepth-1 {
		if execClaimPosition.TraceIndex(execDepth).Uint64() == targetTraceIndex {
			newPosition := execClaimPosition.Attack()
			correct, err := provider.Get(ctx, newPosition)
			require.NoError(t, err)
			t.Logf("Bisecting: Attack correctly for step at newPosition=%v execIndexAtDepth=%v", newPosition, newPosition.TraceIndex(execDepth))
			return claim.Attack(ctx, correct)
		} else if execClaimPosition.TraceIndex(execDepth).Uint64() > targetTraceIndex {
			t.Logf("Bisecting: Attack incorrectly for step")
			return claim.Attack(ctx, common.Hash{0xdd})
		} else if execClaimPosition.TraceIndex(execDepth).Uint64()+1 == targetTraceIndex {
			t.Logf("Bisecting: Defend incorrectly for step")
			return claim.Defend(ctx, common.Hash{0xcc})
		} else {
			newPosition := execClaimPosition.Defend()
			correct, err := provider.Get(ctx, newPosition)
			require.NoError(t, err)
			t.Logf("Bisecting: Defend correctly for step at newPosition=%v execIndexAtDepth=%v", newPosition, newPosition.TraceIndex(execDepth))
			return claim.Defend(ctx, correct)
		}
	}

	// Attack or Defend depending on whether the claim we're responding to is to the left or right of the trace index
	// Induce the honest challenger to attack or defend depending on whether our new position will be to the left or right of the trace index
	if execClaimPosition.TraceIndex(execDepth).Uint64() < targetTraceIndex && claim.Depth() != splitDepth+1 {
		newPosition := execClaimPosition.Defend()
		if newPosition.TraceIndex(execDepth).Uint64() < targetTraceIndex {
			t.Logf("Bisecting: Defend correct. newPosition=%v execIndexAtDepth=%v", newPosition, newPosition.TraceIndex(execDepth))
			correct, err := provider.Get(ctx, newPosition)
			require.NoError(t, err)
			return claim.Defend(ctx, correct)
		} else {
			t.Logf("Bisecting: Defend incorrect. newPosition=%v execIndexAtDepth=%v", newPosition, newPosition.TraceIndex(execDepth))
			return claim.Defend(ctx, common.Hash{0xaa})
		}
	} else {
		newPosition := execClaimPosition.Attack()
		if newPosition.TraceIndex(execDepth).Uint64() < targetTraceIndex {
			t.Logf("Bisecting: Attack correct. newPosition=%v execIndexAtDepth=%v", newPosition, newPosition.TraceIndex(execDepth))
			correct, err := provider.Get(ctx, newPosition)
			require.NoError(t, err)
			return claim.Attack(ctx, correct)
		} else {
			t.Logf("Bisecting: Attack incorrect. newPosition=%v execIndexAtDepth=%v", newPosition, newPosition.TraceIndex(execDepth))
			return claim.Attack(ctx, common.Hash{0xbb})
		}
	}
}

func (g *CannonHelper) VerifyAsteriscPreimageAtTarget(ctx context.Context, asteriscTraceProviderFunc AsteriscTraceProviderFunc, targetTraceIndex uint64, oracleDataValidator OracleDataValidator, uploadOracleData bool) {
	execDepth := g.splitGame.ExecDepth(ctx)
	provider, localContext, outputRootClaim := asteriscTraceProviderFunc()

	pos := types.NewPosition(execDepth, new(big.Int).SetUint64(targetTraceIndex))
	g.require.Equal(targetTraceIndex, pos.TraceIndex(execDepth).Uint64())

	prestate, proof, oracleData, err := provider.GetStepData(ctx, pos)
	g.require.NoError(err, "Failed to get step data")
	g.require.NotNil(oracleData, "Should have had required preimage oracle data")
	oracleDataValidator(oracleData)

	if uploadOracleData {
		txCandidate, err := g.splitGame.Game.UpdateOracleTx(ctx, uint64(outputRootClaim.Index), oracleData)
		g.require.NoError(err, "failed to get oracle")
		transactions.RequireSendTx(g.t, ctx, g.client, txCandidate, g.privKey)
	}

	expectedPostState, err := provider.Get(ctx, pos)
	g.require.NoError(err, "Failed to get expected post state")

	vm, err := g.splitGame.Game.Vm(ctx)
	g.require.NoError(err, "Failed to get VM address")

	// TODO: Use RISCV ABI instead of MIPS ABI once bindings are generated
	// The step() function signature is identical between MIPS and RISCV, so this works for now
	// but should be changed to bindings.RISCVMetaData.GetAbi() for correctness
	abi, err := bindings.MIPSMetaData.GetAbi()
	g.require.NoError(err, "Failed to load VM ABI")
	caller := batching.NewMultiCaller(g.client.Client(), batching.DefaultBatchSize)
	result, err := caller.SingleCall(ctx, rpcblock.Latest, &batching.ContractCall{
		Abi:    abi,
		Addr:   vm.Addr(),
		Method: "step",
		Args: []interface{}{
			prestate, proof, localContext,
		},
		From: g.splitGame.Addr,
	})
	g.require.NoError(err, "Failed to call step")
	actualPostState := result.GetBytes32(0)
	g.require.Equal(expectedPostState, common.Hash(actualPostState))
}
