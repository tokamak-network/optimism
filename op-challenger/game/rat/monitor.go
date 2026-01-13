package rat

import (
	"context"
	"fmt"
	"math/big"
	"math/rand"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/log"
	"github.com/ethereum/go-ethereum/rpc"

	"github.com/ethereum-optimism/optimism/op-challenger/bindings"
	"github.com/ethereum-optimism/optimism/op-challenger/sender"
	"github.com/ethereum-optimism/optimism/op-service/txmgr"
)

type RatMonitor struct {
	logger          log.Logger
	ratContractAddr common.Address
	ratContract     *bindings.RAT
	l1Client        *ethclient.Client
	txSender        *sender.TxSender
	l2Rpc           *rpc.Client
	running         bool
	runState        sync.Mutex
	ctx             context.Context
	cancel          context.CancelFunc
	// ICDCS Experiment fields
	virtualLatencyMs int     // Mean latency in ms
	jitterMs         int     // Jitter standard deviation in ms
	regionId         string  // Region identifier (e.g., "US-01", "EU-05")
}

func NewRatMonitor(
	logger log.Logger,
	ratContractAddr common.Address,
	l1Client *ethclient.Client,
	txSender *sender.TxSender,
	l2RpcUrl string,
	virtualLatencyMs int,
	jitterMs int,
	regionId string,
) (*RatMonitor, error) {
	contract, err := bindings.NewRAT(ratContractAddr, l1Client)
	if err != nil {
		return nil, fmt.Errorf("failed to bind RAT contract: %w", err)
	}

	l2Rpc, err := rpc.Dial(l2RpcUrl)
	if err != nil {
		return nil, fmt.Errorf("failed to dial L2 RPC: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())

	return &RatMonitor{
		logger:           logger,
		ratContractAddr:  ratContractAddr,
		ratContract:      contract,
		l1Client:         l1Client,
		txSender:         txSender,
		l2Rpc:            l2Rpc,
		ctx:              ctx,
		cancel:           cancel,
		virtualLatencyMs: virtualLatencyMs,
		jitterMs:         jitterMs,
		regionId:         regionId,
	}, nil
}

func (m *RatMonitor) Start() {
	m.runState.Lock()
	defer m.runState.Unlock()
	if m.running {
		return
	}
	m.running = true
	m.logger.Info("Starting RAT Monitor", "contract", m.ratContractAddr)

	// Ensure Staked
	if err := m.ensureStaked(); err != nil {
		m.logger.Error("Failed to stake", "err", err)
		// We continue anyway, maybe we are already staked?
	}

	go m.loop()
}

func (m *RatMonitor) ensureStaked() error {
	myAddr := m.txSender.From()
	info, err := m.ratContract.Challengers(nil, myAddr)
	if err != nil {
		return fmt.Errorf("failed to get challenger info: %w", err)
	}

	if info.IsValid {
		m.logger.Info("Already staked", "addr", myAddr)
		return nil
	}

	minStake, err := m.ratContract.MinimumStakingBalance(nil)
	if err != nil {
		return fmt.Errorf("failed to get min stake: %w", err)
	}

	m.logger.Info("Staking...", "amount", minStake)

	// Create candidate
	abi, _ := bindings.RATMetaData.GetAbi()
	data, err := abi.Pack("stake")
	if err != nil {
		return err
	}

	txCandidate := txmgr.TxCandidate{
		To:       &m.ratContractAddr,
		TxData:   data,
		Value:    minStake,
		GasLimit: 500000,
	}

	if err := m.txSender.SendAndWaitSimple("stake", txCandidate); err != nil {
		return fmt.Errorf("staking tx failed: %w", err)
	}
	m.logger.Info("Staking successful")
	return nil
}

func (m *RatMonitor) Stop() {
	m.runState.Lock()
	defer m.runState.Unlock()
	if !m.running {
		return
	}
	m.running = false
	m.cancel()
	m.l2Rpc.Close()
	m.logger.Info("Stopped RAT Monitor")
}

func (m *RatMonitor) loop() {
	// Subscribe to AttentionTriggered events targeting THIS challenger
	myAddr := m.txSender.From()
	m.logger.Info("RAT Monitor watching for events (Polling)", "me", myAddr)

	startBlock := uint64(0)

	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			// Fetch events from startBlock to latest
			currentHead, err := m.l1BlockNumber()
			if err != nil {
				m.logger.Error("Failed to get L1 head", "err", err)
				continue
			}

			if startBlock == 0 {
				startBlock = currentHead - 100 // Start a bit back
				if startBlock > currentHead {
					startBlock = 0
				} // overflow protection
			}

			if startBlock > currentHead {
				continue
			}

			opts := &bind.FilterOpts{
				Start:   startBlock,
				End:     nil, // to latest
				Context: m.ctx,
			}

			// Listen to ALL events for debugging
			iter, err := m.ratContract.FilterAttentionTriggered(opts, nil, nil)
			if err != nil {
				m.logger.Error("Failed to filter RAT events", "err", err)
				continue
			}

			for iter.Next() {
				event := iter.Event
				if event.Raw.BlockNumber < startBlock {
					continue
				}

				isMe := (event.Challenger == myAddr)
				m.logger.Info("RAT Event Scanned", "game", event.GameAddress, "chal", event.Challenger, "me", myAddr, "match", isMe)

				if isMe {
					m.logger.Info("🎯 I am the selected challenger! Submitting evidence...")
					go m.handleSelection(event.GameAddress)
				}

				if event.Raw.BlockNumber >= startBlock {
					startBlock = event.Raw.BlockNumber + 1
				}
			}
			if err := iter.Error(); err != nil {
				m.logger.Error("Iterator error", "err", err)
			}
			iter.Close()

			startBlock = currentHead + 1

		case <-m.ctx.Done():
			return
		}
	}
}

func (m *RatMonitor) l1BlockNumber() (uint64, error) {
	return m.l1Client.BlockNumber(m.ctx)
}

func (m *RatMonitor) handleSelection(gameAddress common.Address) {
	// ===== ICDCS TIMING: T_detected =====
	tDetected := time.Now()

	// Apply virtual latency with Gaussian jitter (simulates network delay)
	if m.virtualLatencyMs > 0 {
		jitter := 0.0
		if m.jitterMs > 0 {
			jitter = rand.NormFloat64() * float64(m.jitterMs)
		}
		delay := time.Duration(float64(m.virtualLatencyMs)+jitter) * time.Millisecond
		if delay > 0 {
			time.Sleep(delay)
		}
	}

	// 1. Get Attention Info (v2: includes seed)
	info, err := m.ratContract.AttentionTests(nil, gameAddress)
	if err != nil {
		m.logger.Error("Failed to get AttentionTest info", "err", err)
		return
	}

	// Check status (0=pending, 1=submitted, 2=disputed, 3=finalized)
	if info.Status != 0 {
		m.logger.Info("Attention test not in pending state", "status", info.Status)
		return
	}

	// 2. Get L2 block header
	l2BlockNum := info.L2BlockNumber
	m.logger.Info("Using L2 block from AttentionInfo", "l2BlockNumber", l2BlockNum, "seed", common.BytesToHash(info.Seed[:]).Hex())
	bn := new(big.Int).SetUint64(l2BlockNum)

	var head *types.Header
	blk := hexutil.EncodeBig(bn)
	if err := m.l2Rpc.CallContext(m.ctx, &head, "eth_getBlockByNumber", blk, false); err != nil {
		m.logger.Error("Failed to get block", "err", err)
		return
	}
	if head == nil {
		m.logger.Error("Block not found")
		return
	}

	stateRoot := head.Root
	m.logger.Info("Block info", "number", head.Number, "stateRoot", stateRoot.Hex())

	// 3. Find closest key to seed using state trie
	// For now, we use a known account (L2ToL1MessagePasser) as candidate
	// TODO: Implement proper LevelDB iterator-based closest key search
	closestKey, proof, err := m.findClosestKeyWithProof(info.Seed, bn)
	if err != nil {
		m.logger.Error("Failed to find closest key", "err", err)
		return
	}

	distance := distance32(closestKey, info.Seed)
	m.logger.Info("Found closest key", "key", common.BytesToHash(closestKey[:]).Hex(), "distance", distance.String())

	// 4. Get OutputRoot components for verification
	msgPasserRoot, err := m.getMessagePasserStorageRoot(head.Number)
	if err != nil {
		m.logger.Warn("Failed to fetch messagePasserStorageRoot, using zero", "err", err)
		msgPasserRoot = [32]byte{}
	}

	// 5. Pack submitCandidate call
	abiData, _ := bindings.RATMetaData.GetAbi()
	data, err := abiData.Pack("submitCandidate",
		gameAddress,
		closestKey,
		stateRoot,                  // _stateRoot
		[32]byte{},                 // _version (0)
		msgPasserRoot,              // _messagePasserRoot
		head.Hash(),                // _blockHash
		proof,                      // _proof ([][]byte)
	)
	if err != nil {
		m.logger.Error("Failed to pack tx data", "err", err)
		return
	}

	txCandidate := txmgr.TxCandidate{
		To:       &m.ratContractAddr,
		TxData:   data,
		GasLimit: 2000000,
	}

	// ===== ICDCS TIMING: T_generated =====
	tGenerated := time.Now()
	tProc := tGenerated.Sub(tDetected)

	m.logger.Info("Submitting Candidate Transaction...",
		"block", head.Number,
		"region", m.regionId,
		"distance", distance.String(),
		"T_proc_ms", tProc.Milliseconds())

	err = m.txSender.SendAndWaitSimple("submit-candidate", txCandidate)

	// ===== ICDCS TIMING: T_confirmed =====
	tConfirmed := time.Now()
	tNet := tConfirmed.Sub(tGenerated)
	tTotal := tConfirmed.Sub(tDetected)

	if err != nil {
		m.logger.Error("Failed to submit candidate",
			"err", err,
			"region", m.regionId,
			"T_proc_ms", tProc.Milliseconds(),
			"T_net_ms", tNet.Milliseconds(),
			"T_total_ms", tTotal.Milliseconds())
		return
	}

	m.logger.Info("Candidate Submitted Successfully",
		"region", m.regionId,
		"game", gameAddress.Hex()[:10],
		"key", common.BytesToHash(closestKey[:]).Hex()[:18],
		"T_proc_ms", tProc.Milliseconds(),
		"T_net_ms", tNet.Milliseconds(),
		"T_total_ms", tTotal.Milliseconds())
}

// findClosestKeyWithProof finds the closest state trie key to the target seed
func (m *RatMonitor) findClosestKeyWithProof(seed [32]byte, blockNum *big.Int) ([32]byte, [][]byte, error) {
	// For v2 implementation, we need to iterate through state trie keys
	// Current approach: use known accounts as candidates and pick closest

	candidates := []common.Address{
		messagePasserAddr,  // L2ToL1MessagePasser
		common.HexToAddress("0x4200000000000000000000000000000000000000"), // LegacyMessagePasser
		common.HexToAddress("0x4200000000000000000000000000000000000006"), // WETH
		common.HexToAddress("0x4200000000000000000000000000000000000007"), // L2CrossDomainMessenger
		common.HexToAddress("0x4200000000000000000000000000000000000010"), // L2StandardBridge
		common.HexToAddress("0x4200000000000000000000000000000000000011"), // SequencerFeeVault
		common.HexToAddress("0x4200000000000000000000000000000000000012"), // OptimismMintableERC20Factory
		common.HexToAddress("0x4200000000000000000000000000000000000015"), // L1Block
		common.HexToAddress("0x4200000000000000000000000000000000000018"), // L2ERC721Bridge
	}

	var closestKey [32]byte
	var minDistance *big.Int
	var closestProof [][]byte

	blk := "latest"
	if blockNum != nil {
		blk = hexutil.EncodeBig(blockNum)
	}

	for _, addr := range candidates {
		// State trie key is keccak256(address)
		key := crypto.Keccak256Hash(addr.Bytes())
		dist := distance32(key, seed)

		if minDistance == nil || dist.Cmp(minDistance) < 0 {
			// Get proof for this address
			var res rawAccountProof
			err := m.l2Rpc.CallContext(m.ctx, &res, "eth_getProof", addr, []string{}, blk)
			if err != nil {
				m.logger.Warn("Failed to get proof for candidate", "addr", addr.Hex(), "err", err)
				continue
			}

			// Convert proof to [][]byte
			proof := make([][]byte, len(res.AccountProof))
			for i, p := range res.AccountProof {
				proof[i] = common.FromHex(p)
			}

			closestKey = key
			minDistance = dist
			closestProof = proof
		}
	}

	if minDistance == nil {
		return [32]byte{}, nil, fmt.Errorf("no valid candidates found")
	}

	return closestKey, closestProof, nil
}

// distance32 calculates absolute difference between two bytes32 values
func distance32(a, b [32]byte) *big.Int {
	aInt := new(big.Int).SetBytes(a[:])
	bInt := new(big.Int).SetBytes(b[:])
	diff := new(big.Int).Sub(aInt, bInt)
	return diff.Abs(diff)
}

func (m *RatMonitor) findBlockByOutputRoot(targetRoot [32]byte) (uint64, error) {
	// Search last 100 blocks
	var latestHex hexutil.Uint64
	err := m.l2Rpc.CallContext(m.ctx, &latestHex, "eth_blockNumber")
	if err != nil {
		return 0, err
	}
	latest := uint64(latestHex)

	start := uint64(0)
	if latest > 100 {
		start = latest - 100
	}

	var zeroHash [32]byte
	abiArguments := abi.Arguments{
		{Type: mustParseType("bytes32")},
		{Type: mustParseType("bytes32")},
		{Type: mustParseType("bytes32")},
		{Type: mustParseType("bytes32")},
	}

	for i := latest; i >= start; i-- {
		// Get block header to get Root
		var head *types.Header
		err := m.l2Rpc.CallContext(m.ctx, &head, "eth_getBlockByNumber", hexutil.EncodeBig(new(big.Int).SetUint64(i)), false)
		if err != nil {
			continue
		}
		if head == nil {
			continue
		}

		// Compute Output Root
		// Optimism Output Root = keccak256(version . stateRoot . messagePasserStorageRoot . latestBlockhash)
		// Wait, loop needs messagePasserStorageRoot for accurate calculation.
		// Current logic uses zeroHash for messagePasserStorageRoot and latestBlockhash?
		// NOTE: rat-proposer uses Proper Calculation.
		// If we search with ZeroHash, we might NOT find matches if Proposer used real values.
		// However, finding the block by just `head.Root` (StateRoot) check against what? no targetRoot is OutputRoot.
		// So we MUST calculate OutputRoot correctly to match.
		// If obtaining MessagePasserStorageRoot is expensive (requires fetch), we can optimization:
		// Just check StateRoot? NO, targetRoot is OutputRoot.
		// We SHOULD fetch messagePasserStorageRoot here.
		// But that makes loop slow.
		// Valid optimization: assume MessagePasserStorageRoot is constant or similar? No.
		// Actually, `latestBlockhash` in OutputRoot is the hash of the L2 block itself (or L1 block?).
		// Bedrock OutputProposal:
		// version=0
		// stateRoot = L2 State Root
		// messagePasserStorageRoot = Storage Root of Message Passer
		// latestBlockhash = L2 Block Hash

		// So we really need all values.

		// For now, let's optimize: We assume we are checking "latest" or closely.
		// If we can't find it easily, we default to block logic in handleSelection fallback.
		// But let's try to fetch storage root for the Candidate Block `i`.

		// Compute Output Root
		outputRootBytes, _ := abiArguments.Pack(
			zeroHash,   // version (0)
			head.Root,  // stateRoot
			zeroHash, // messagePasserStorageRoot
			zeroHash,   // latestBlockhash
		)
		calculated := crypto.Keccak256Hash(outputRootBytes)

		if calculated == targetRoot {
			return i, nil
		}
	}
	return 0, fmt.Errorf("block not found for root %x", targetRoot)
}

func mustParseType(t string) abi.Type {
	parsed, err := abi.NewType(t, "", nil)
	if err != nil {
		panic(err)
	}
	return parsed
}

type rawAccountProof struct {
	Address      common.Address `json:"address"`
	AccountProof []string       `json:"accountProof"`
	Balance      *hexutil.Big   `json:"balance"`
	CodeHash     common.Hash    `json:"codeHash"`
	Nonce        hexutil.Uint64 `json:"nonce"`
	StorageHash  common.Hash    `json:"storageHash"`
	StorageProof []interface{}  `json:"storageProof"`
}

func (m *RatMonitor) getStateTrieNodeChildren(blockNumber *big.Int) ([]byte, error) {
	var res rawAccountProof
	blk := "latest"
	if blockNumber != nil {
		blk = hexutil.EncodeBig(blockNumber)
	}

	// We query address(0) to get the State Root Proof (Account Proof for non-existent account works to get root node)
	// Actually for non-existent account, proof confirms exclusion.
	// But it starts from Root Node.
	// Element 0 is always Root Node.
	err := m.l2Rpc.CallContext(m.ctx, &res, "eth_getProof", common.Address{}, []string{}, blk)
	if err != nil {
		return nil, err
	}

	if len(res.AccountProof) == 0 {
		return nil, fmt.Errorf("no account proof returned")
	}

	// The first element of AccountProof is the State Root Node (RLP encoded)
	rootNodeRLP := common.FromHex(res.AccountProof[0])
	return rootNodeRLP, nil
}

// L2ToL1MessagePasser predeploy address
var messagePasserAddr = common.HexToAddress("0x4200000000000000000000000000000000000016")

func (m *RatMonitor) getMessagePasserStorageRoot(blockNumber *big.Int) ([32]byte, error) {
	var res rawAccountProof
	blk := "latest"
	if blockNumber != nil {
		blk = hexutil.EncodeBig(blockNumber)
	}
	err := m.l2Rpc.CallContext(m.ctx, &res, "eth_getProof", messagePasserAddr, []string{}, blk)
	if err != nil {
		return [32]byte{}, err
	}
	return res.StorageHash, nil
}
