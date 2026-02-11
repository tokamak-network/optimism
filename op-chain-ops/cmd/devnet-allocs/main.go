package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/ethereum-optimism/optimism/op-chain-ops/addresses"
	"github.com/ethereum-optimism/optimism/op-chain-ops/foundry"
	"github.com/ethereum-optimism/optimism/op-chain-ops/genesis"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/artifacts"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/inspect"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/pipeline"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/state"
	"github.com/ethereum-optimism/optimism/op-node/rollup"
	op_service "github.com/ethereum-optimism/optimism/op-service"
	oplog "github.com/ethereum-optimism/optimism/op-service/log"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/log"
	"golang.org/x/exp/maps"
)

var (
	outDir      = flag.String("outdir", ".devnet", "Output directory for allocs files")
	l1ChainID   = flag.Uint64("l1-chain-id", 900, "L1 chain ID")
	l2ChainID   = flag.Uint64("l2-chain-id", 901, "L2 chain ID")
	fundDevAccs = flag.Bool("fund-dev-accounts", true, "Fund dev accounts with ETH")
)

// Default test secrets (matching op-e2e/config/secrets)
var defaultSecrets = struct {
	Deployer      string
	Batcher       string
	Proposer      string
	SequencerP2P  string
	Challenger    string
}{
	Deployer:     "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
	Batcher:      "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
	Proposer:     "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
	SequencerP2P: "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba",
	Challenger:   "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a",
}

type prestateFile struct {
	Pre string `json:"pre"`
}

func main() {
	flag.Parse()

	// Setup logger
	oplog.SetGlobalLogHandler(log.NewTerminalHandler(os.Stderr, true))
	lgr := log.New()

	// Find monorepo root
	cwd, err := os.Getwd()
	if err != nil {
		lgr.Crit("Failed to get working directory", "err", err)
	}
	root, err := op_service.FindMonorepoRoot(cwd)
	if err != nil {
		lgr.Crit("Failed to find monorepo root", "err", err)
	}

	lgr.Info("Generating devnet allocs", "root", root, "outdir", *outDir)

	// Create output directory
	outPath := filepath.Join(root, *outDir)
	if err := os.MkdirAll(outPath, 0755); err != nil {
		lgr.Crit("Failed to create output directory", "err", err)
	}

	// Get deployer private key
	pk, err := crypto.HexToECDSA(defaultSecrets.Deployer[2:])
	if err != nil {
		lgr.Crit("Failed to parse deployer private key", "err", err)
	}
	deployerAddr := crypto.PubkeyToAddress(pk.PublicKey)

	// Get other addresses
	batcherPk, _ := crypto.HexToECDSA(defaultSecrets.Batcher[2:])
	batcherAddr := crypto.PubkeyToAddress(batcherPk.PublicKey)
	proposerPk, _ := crypto.HexToECDSA(defaultSecrets.Proposer[2:])
	proposerAddr := crypto.PubkeyToAddress(proposerPk.PublicKey)
	sequencerP2PPk, _ := crypto.HexToECDSA(defaultSecrets.SequencerP2P[2:])
	sequencerP2PAddr := crypto.PubkeyToAddress(sequencerP2PPk.PublicKey)
	challengerPk, _ := crypto.HexToECDSA(defaultSecrets.Challenger[2:])
	challengerAddr := crypto.PubkeyToAddress(challengerPk.PublicKey)

	lgr.Info("Using addresses",
		"deployer", deployerAddr.Hex(),
		"batcher", batcherAddr.Hex(),
		"proposer", proposerAddr.Hex(),
		"sequencerP2P", sequencerP2PAddr.Hex(),
		"challenger", challengerAddr.Hex(),
	)

	// Setup artifacts locator
	artifactsPath := filepath.Join(root, "packages", "contracts-bedrock", "forge-artifacts")
	loc, err := artifacts.NewFileLocator(artifactsPath)
	if err != nil {
		lgr.Crit("Failed to create artifacts locator", "err", err)
	}

	// Get cannon prestate hash
	cannonPrestate := getCannonPrestate(root, lgr)
	asteriscPrestate := getAsteriscPrestate(root, lgr)

	// Define allocs modes to generate
	allocModes := []genesis.L2AllocsMode{
		genesis.L2AllocsGranite, // Current default
	}

	var wg sync.WaitGroup
	var mtx sync.Mutex
	var l1Allocs *foundry.ForgeAllocs
	var l1Deployments *genesis.L1Deployments
	var deployConfig *genesis.DeployConfig
	l2Allocs := make(map[genesis.L2AllocsMode]*foundry.ForgeAllocs)

	for _, mode := range allocModes {
		wg.Add(1)
		go func(mode genesis.L2AllocsMode) {
			defer wg.Done()

			intent := createIntent(loc, deployerAddr, batcherAddr, proposerAddr, sequencerP2PAddr, challengerAddr, cannonPrestate, asteriscPrestate)

			// Set upgrade schedule
			baseUpgradeSchedule := map[string]any{
				"l2GenesisRegolithTimeOffset": nil,
				"l2GenesisCanyonTimeOffset":   nil,
				"l2GenesisDeltaTimeOffset":    nil,
				"l2GenesisEcotoneTimeOffset":  nil,
				"l2GenesisFjordTimeOffset":    nil,
				"l2GenesisGraniteTimeOffset":  nil,
				"l2GenesisHoloceneTimeOffset": nil,
				"l2GenesisIsthmusTimeOffset":  nil,
			}

			upgradeSchedule := new(genesis.UpgradeScheduleDeployConfig)
			upgradeSchedule.ActivateForkAtGenesis(rollup.ForkName(mode))
			upgradeOverridesJSON, err := json.Marshal(upgradeSchedule)
			if err != nil {
				lgr.Crit("Failed to marshal upgrade schedule", "err", err)
			}
			var upgradeOverrides map[string]any
			if err := json.Unmarshal(upgradeOverridesJSON, &upgradeOverrides); err != nil {
				lgr.Crit("Failed to unmarshal upgrade schedule", "err", err)
			}
			maps.Copy(baseUpgradeSchedule, upgradeOverrides)
			maps.Copy(intent.GlobalDeployOverrides, baseUpgradeSchedule)

			st := &state.State{
				Version: 1,
			}

			lgr.Info("Applying pipeline", "mode", mode)

			if err := deployer.ApplyPipeline(
				context.Background(),
				deployer.ApplyPipelineOpts{
					DeploymentTarget:   deployer.DeploymentTargetGenesis,
					L1RPCUrl:           "",
					DeployerPrivateKey: pk,
					Intent:             intent,
					State:              st,
					Logger:             lgr,
					StateWriter:        pipeline.NoopStateWriter(),
				},
			); err != nil {
				lgr.Crit("Failed to apply pipeline", "err", err, "mode", mode)
			}

			mtx.Lock()
			l2Allocs[mode] = st.Chains[0].Allocs.Data

			// Get L1 allocs and config from the Granite mode (current default)
			if mode == genesis.L2AllocsGranite {
				dc, err := inspect.DeployConfig(st, intent.Chains[0].ID)
				if err != nil {
					lgr.Crit("Failed to inspect deploy config", "err", err)
				}

				l1Contracts, err := inspect.L1(st, intent.Chains[0].ID)
				if err != nil {
					lgr.Crit("Failed to inspect L1", "err", err)
				}

				dc.L1GenesisBlockTimestamp = hexutil.Uint64(time.Now().Unix())
				dc.FundDevAccounts = *fundDevAccs
				dc.L1BlockTime = 2
				dc.L2BlockTime = 1
				dc.SetContracts(l1Contracts)

				deployConfig = dc
				l1Allocs = st.L1StateDump.Data
				l1Deployments = genesis.CreateL1DeploymentsFromContracts(l1Contracts)
			}
			mtx.Unlock()

			lgr.Info("Generated allocs", "mode", mode)
		}(mode)
	}

	wg.Wait()

	// Write output files
	lgr.Info("Writing output files")

	// Write L1 allocs
	if l1Allocs != nil {
		if err := writeJSON(filepath.Join(outPath, "allocs-l1.json"), l1Allocs); err != nil {
			lgr.Crit("Failed to write L1 allocs", "err", err)
		}
		lgr.Info("Wrote L1 allocs", "file", "allocs-l1.json")
	}

	// Write L1 deployments
	if l1Deployments != nil {
		if err := writeJSON(filepath.Join(outPath, "addresses.json"), l1Deployments); err != nil {
			lgr.Crit("Failed to write L1 deployments", "err", err)
		}
		lgr.Info("Wrote L1 deployments", "file", "addresses.json")
	}

	// Write deploy config
	if deployConfig != nil {
		if err := writeJSON(filepath.Join(outPath, "devnetL1.json"), deployConfig); err != nil {
			lgr.Crit("Failed to write deploy config", "err", err)
		}
		lgr.Info("Wrote deploy config", "file", "devnetL1.json")
	}

	// Write L2 allocs for each mode
	for mode, allocs := range l2Allocs {
		filename := fmt.Sprintf("allocs-l2-%s.json", mode)
		if err := writeJSON(filepath.Join(outPath, filename), allocs); err != nil {
			lgr.Crit("Failed to write L2 allocs", "err", err, "mode", mode)
		}
		lgr.Info("Wrote L2 allocs", "file", filename)

		// Also write as default allocs-l2.json for Granite
		if mode == genesis.L2AllocsGranite {
			if err := writeJSON(filepath.Join(outPath, "allocs-l2.json"), allocs); err != nil {
				lgr.Crit("Failed to write default L2 allocs", "err", err)
			}
			lgr.Info("Wrote default L2 allocs", "file", "allocs-l2.json")
		}
	}

	lgr.Info("Devnet allocs generation complete", "outdir", outPath)
}

func createIntent(
	loc *artifacts.Locator,
	deployerAddr, batcherAddr, proposerAddr, sequencerP2PAddr, challengerAddr common.Address,
	cannonPrestate, asteriscPrestate common.Hash,
) *state.Intent {
	defaultPrestate := common.HexToHash("0x03c7ae758795765c6664a5d39bf63841c71ff191e9189522bad8ebff5d4eca98")
	genesisOutputRoot := common.HexToHash("0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF")

	if cannonPrestate != (common.Hash{}) {
		defaultPrestate = cannonPrestate
	}

	return &state.Intent{
		ConfigType: state.IntentTypeCustom,
		L1ChainID:  *l1ChainID,
		SuperchainRoles: &addresses.SuperchainRoles{
			SuperchainProxyAdminOwner: deployerAddr,
			ProtocolVersionsOwner:     deployerAddr,
			SuperchainGuardian:        deployerAddr,
			Challenger:                challengerAddr,
		},
		FundDevAccounts:    *fundDevAccs,
		L1ContractsLocator: loc,
		L2ContractsLocator: loc,
		GlobalDeployOverrides: map[string]any{
			"maxSequencerDrift":                         300,
			"sequencerWindowSize":                       200,
			"channelTimeout":                            120,
			"l2OutputOracleSubmissionInterval":          10,
			"l2OutputOracleStartingTimestamp":           0,
			"l2OutputOracleProposer":                    proposerAddr,
			"l2OutputOracleChallenger":                  challengerAddr,
			"l2GenesisBlockGasLimit":                    "0x1c9c380",
			"l1BlockTime":                               6,
			"baseFeeVaultMinimumWithdrawalAmount":       "0x8ac7230489e80000",
			"l1FeeVaultMinimumWithdrawalAmount":         "0x8ac7230489e80000",
			"sequencerFeeVaultMinimumWithdrawalAmount":  "0x8ac7230489e80000",
			"baseFeeVaultWithdrawalNetwork":             0,
			"l1FeeVaultWithdrawalNetwork":               0,
			"sequencerFeeVaultWithdrawalNetwork":        0,
			"finalizationPeriodSeconds":                 2,
			"l2GenesisBlockBaseFeePerGas":               "0x1",
			"gasPriceOracleOverhead":                    2100,
			"gasPriceOracleScalar":                      1000000,
			"gasPriceOracleBaseFeeScalar":               1368,
			"gasPriceOracleBlobBaseFeeScalar":           810949,
			"gasPriceOracleOperatorFeeScalar":           0,
			"gasPriceOracleOperatorFeeConstant":         0,
			"l1CancunTimeOffset":                        "0x0",
			"faultGameAbsolutePrestate":                 defaultPrestate.Hex(),
			"faultGameMaxDepth":                         50,
			"faultGameClockExtension":                   0,
			"faultGameMaxClockDuration":                 1200,
			"faultGameGenesisBlock":                     0,
			"faultGameGenesisOutputRoot":                genesisOutputRoot.Hex(),
			"faultGameSplitDepth":                       14,
			"dangerouslyAllowCustomDisputeParameters":   true,
			"faultGameWithdrawalDelay":                  604800,
			"preimageOracleMinProposalSize":             10000,
			"preimageOracleChallengePeriod":             120,
			"proofMaturityDelaySeconds":                 6000,
			"disputeGameFinalityDelaySeconds":           600,
			"deployRAT":                                 true,
			"perTestBondAmount":                         "0x5af3107a4000",
			"evidenceSubmissionPeriod":                  600,
			"minimumStakingBalance":                     "0xde0b6b3a7640000",
			"ratTriggerProbability":                     "0x186a0",
			"ratManager":                                deployerAddr.Hex(),
		},
		Chains: []*state.ChainIntent{
			{
				ID:                         common.BigToHash(big.NewInt(int64(*l2ChainID))),
				BaseFeeVaultRecipient:      common.HexToAddress("0x14dC79964da2C08b23698B3D3cc7Ca32193d9955"),
				L1FeeVaultRecipient:        common.HexToAddress("0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f"),
				SequencerFeeVaultRecipient: common.HexToAddress("0xa0Ee7A142d267C1f36714E4a8F75612F20a79720"),
				Eip1559Denominator:         250,
				Eip1559DenominatorCanyon:   250,
				Eip1559Elasticity:          6,
				Roles: state.ChainRoles{
					L1ProxyAdminOwner: deployerAddr,
					L2ProxyAdminOwner: deployerAddr,
					SystemConfigOwner: deployerAddr,
					UnsafeBlockSigner: sequencerP2PAddr,
					Batcher:           batcherAddr,
					Proposer:          proposerAddr,
					Challenger:        challengerAddr,
				},
				AdditionalDisputeGames: []state.AdditionalDisputeGame{
					{
						ChainProofParams: state.ChainProofParams{
							DisputeGameType:         254,
							DisputeAbsolutePrestate: defaultPrestate,
							DisputeMaxGameDepth:     14 + 3 + 1,
							DisputeSplitDepth:       14,
							DisputeClockExtension:   0,
							DisputeMaxClockDuration: 0,
						},
						VMType:                       state.VMTypeAlphabet,
						UseCustomOracle:              true,
						OracleMinProposalSize:        10000,
						OracleChallengePeriodSeconds: 0,
						MakeRespected:                true,
					},
					{
						ChainProofParams: state.ChainProofParams{
							DisputeGameType:         255,
							DisputeAbsolutePrestate: defaultPrestate,
							DisputeMaxGameDepth:     14 + 3 + 1,
							DisputeSplitDepth:       14,
							DisputeClockExtension:   0,
							DisputeMaxClockDuration: 1200,
						},
						VMType: state.VMTypeAlphabet,
					},
					{
						ChainProofParams: state.ChainProofParams{
							DisputeGameType:         0,
							DisputeAbsolutePrestate: cannonPrestate,
							DisputeMaxGameDepth:     50,
							DisputeSplitDepth:       14,
							DisputeClockExtension:   0,
							DisputeMaxClockDuration: 1200,
						},
						VMType: state.VMTypeCannon,
					},
					{
						ChainProofParams: state.ChainProofParams{
							DisputeGameType:         2,
							DisputeAbsolutePrestate: asteriscPrestate,
							DisputeMaxGameDepth:     50,
							DisputeSplitDepth:       14,
							DisputeClockExtension:   0,
							DisputeMaxClockDuration: 1200,
						},
						VMType: state.VMTypeAsterisc,
					},
				},
			},
		},
	}
}

func getCannonPrestate(root string, lgr log.Logger) common.Hash {
	f, err := os.Open(filepath.Join(root, "op-program", "bin", "prestate-proof-mt64.json"))
	if err != nil {
		lgr.Warn("Cannon prestate file not found, using default", "err", err)
		return common.Hash{}
	}
	defer f.Close()

	var prestate prestateFile
	if err := json.NewDecoder(f).Decode(&prestate); err != nil {
		lgr.Warn("Failed to decode cannon prestate", "err", err)
		return common.Hash{}
	}

	return common.HexToHash(prestate.Pre)
}

func getAsteriscPrestate(root string, lgr log.Logger) common.Hash {
	f, err := os.Open(filepath.Join(root, "op-program", "bin", "prestate-asterisc.json"))
	if err != nil {
		lgr.Warn("Asterisc prestate file not found, using default", "err", err)
		return common.Hash{}
	}
	defer f.Close()

	var prestate prestateFile
	if err := json.NewDecoder(f).Decode(&prestate); err != nil {
		lgr.Warn("Failed to decode asterisc prestate", "err", err)
		return common.Hash{}
	}

	return common.HexToHash(prestate.Pre)
}

func writeJSON(path string, data any) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	enc := json.NewEncoder(f)
	enc.SetIndent("", "  ")
	return enc.Encode(data)
}
