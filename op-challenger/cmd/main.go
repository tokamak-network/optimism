package main

import (
	"context"
	"os"

	"github.com/ethereum-optimism/optimism/op-challenger/metrics"
	"github.com/urfave/cli/v2"

	"github.com/ethereum/go-ethereum/log"

	challenger "github.com/ethereum-optimism/optimism/op-challenger"
	"github.com/ethereum-optimism/optimism/op-challenger/config"
	"github.com/ethereum-optimism/optimism/op-challenger/flags"
	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/types"
	"github.com/ethereum-optimism/optimism/op-challenger/version"
	opservice "github.com/ethereum-optimism/optimism/op-service"
	"github.com/ethereum-optimism/optimism/op-service/cliapp"
	"github.com/ethereum-optimism/optimism/op-service/ctxinterrupt"
	oplog "github.com/ethereum-optimism/optimism/op-service/log"
)

var (
	GitCommit = ""
	GitDate   = ""
)

// VersionWithMeta holds the textual version string including the metadata.
var VersionWithMeta = opservice.FormatVersion(version.Version, GitCommit, GitDate, version.Meta)

func main() {
	args := os.Args
	ctx := ctxinterrupt.WithSignalWaiterMain(context.Background())
	if err := run(ctx, args, func(ctx context.Context, l log.Logger, config *config.Config) (cliapp.Lifecycle, error) {
		return challenger.Main(ctx, l, config, metrics.NewMetrics())
	}); err != nil {
		log.Crit("Application failed", "err", err)
	}
}

type ConfiguredLifecycle func(ctx context.Context, log log.Logger, config *config.Config) (cliapp.Lifecycle, error)

func run(ctx context.Context, args []string, action ConfiguredLifecycle) error {
	oplog.SetupDefaults()

	app := cli.NewApp()
	app.Version = VersionWithMeta
	app.Flags = cliapp.ProtectFlags(flags.Flags)
	app.Name = "op-challenger"
	app.Usage = "Challenge outputs"
	app.Description = "Ensures that on chain outputs are correct."
	app.Commands = []*cli.Command{
		ListGamesCommand,
		ListClaimsCommand,
		ListCreditsCommand,
		CreateGameCommand,
		MoveCommand,
		ResolveCommand,
		ResolveClaimCommand,
		RunTraceCommand,
	}
	app.Action = cliapp.LifecycleCmd(func(ctx *cli.Context, close context.CancelCauseFunc) (cliapp.Lifecycle, error) {
		logger, err := setupLogging(ctx)
		if err != nil {
			return nil, err
		}
		logger.Info("Starting op-challenger", "version", VersionWithMeta)

		cfg, err := flags.NewConfigFromCLI(ctx, logger)
		if err != nil {
			return nil, err
		}

		// 설정 파라미터들을 로그에 기록
		logConfiguration(logger, cfg)

		return action(ctx.Context, logger, cfg)
	})
	return app.RunContext(ctx, args)
}

func setupLogging(ctx *cli.Context) (log.Logger, error) {
	logCfg := oplog.ReadCLIConfig(ctx)
	logger := oplog.NewLogger(oplog.AppOut(ctx), logCfg)
	oplog.SetGlobalLogHandler(logger.Handler())
	return logger, nil
}

// 설정 파라미터들을 로그에 기록하는 함수
func logConfiguration(logger log.Logger, cfg *config.Config) {
	logger.Info("Challenger configuration loaded",
		"l1EthRpc", cfg.L1EthRpc,
		"l1Beacon", cfg.L1Beacon,
		"gameFactoryAddress", cfg.GameFactoryAddress.Hex(),
		"datadir", cfg.Datadir,
		"maxConcurrency", cfg.MaxConcurrency,
		"traceTypes", cfg.TraceTypes,
		"gameWindow", cfg.GameWindow,
		"pollInterval", cfg.PollInterval,
		"maxPendingTx", cfg.MaxPendingTx,
		"rollupRpc", cfg.RollupRpc,
		"supervisorRpc", cfg.SupervisorRPC,
		"l2Rpcs", cfg.L2Rpcs,
		"gameAllowlist", cfg.GameAllowlist,
		"additionalBondClaimants", cfg.AdditionalBondClaimants,
		"selectiveClaimResolution", cfg.SelectiveClaimResolution,
		"allowInvalidPrestate", cfg.AllowInvalidPrestate,
	)

	// Cannon VM 설정 로깅
	if len(cfg.TraceTypes) > 0 && cfg.TraceTypes[0] == types.TraceTypeCannon {
		logger.Info("Cannon VM configuration",
			"vmBin", cfg.Cannon.VmBin,
			"server", cfg.Cannon.Server,
			"l2Custom", cfg.Cannon.L2Custom,
			"snapshotFreq", cfg.Cannon.SnapshotFreq,
			"infoFreq", cfg.Cannon.InfoFreq,
			"absolutePrestate", cfg.CannonAbsolutePreState,
			"prestatesBaseURL", cfg.CannonAbsolutePreStateBaseURL,
		)
	}

	// Asterisc VM 설정 로깅
	if len(cfg.TraceTypes) > 0 && cfg.TraceTypes[0] == types.TraceTypeAsterisc {
		logger.Info("Asterisc VM configuration",
			"vmBin", cfg.Asterisc.VmBin,
			"server", cfg.Asterisc.Server,
			"snapshotFreq", cfg.Asterisc.SnapshotFreq,
			"infoFreq", cfg.Asterisc.InfoFreq,
		)
	}
}
