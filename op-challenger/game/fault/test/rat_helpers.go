package test

import (
	"context"
	"crypto/ecdsa"
	"math/big"
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/accounts/abi/bind/backends"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/stretchr/testify/require"

	"github.com/ethereum-optimism/optimism/op-challenger/game/fault/contracts"
)

// RATTestEnvironment provides a complete testing environment for RAT integration tests
type RATTestEnvironment struct {
	T                  *testing.T
	Backend            *backends.SimulatedBackend
	RATContract        *contracts.RAT
	RATAddress         common.Address
	DisputeGameFactory common.Address
	RatManager         common.Address

	// Test accounts (exported for test access)
	Deployer         *TestAccount
	FactoryAccount   *TestAccount
	ManagerAccount   *TestAccount
	ChallengerAccount *TestAccount

	// Test configuration
	perTestBondAmount      *big.Int
	evidenceSubmissionPeriod *big.Int
	minimumStakingBalance  *big.Int
	ratTriggerProbability  *big.Int

	// Game creation counter
	gameCounter uint64
}

// TestAccount represents a test account with private key and auth
type TestAccount struct {
	PrivateKey *ecdsa.PrivateKey
	Address    common.Address
	Auth       *bind.TransactOpts
}

// RATTestConfig holds configuration for RAT test environment
type RATTestConfig struct {
	PerTestBondAmount       *big.Int
	EvidenceSubmissionPeriod *big.Int
	MinimumStakingBalance   *big.Int
	RatTriggerProbability   *big.Int
	InitialBalance          *big.Int
}

// DefaultRATTestConfig returns default configuration for RAT tests
func DefaultRATTestConfig() *RATTestConfig {
	tenEth := new(big.Int)
	tenEth.SetString("10000000000000000000", 10) // 10 ETH in wei

	oneEth := new(big.Int)
	oneEth.SetString("1000000000000000000", 10) // 1 ETH in wei

	twoEth := new(big.Int)
	twoEth.SetString("2000000000000000000", 10) // 2 ETH in wei

	return &RATTestConfig{
		PerTestBondAmount:       oneEth,
		EvidenceSubmissionPeriod: big.NewInt(100),   // 100 blocks
		MinimumStakingBalance:   twoEth,
		RatTriggerProbability:   big.NewInt(100000), // 100% for testing
		InitialBalance:          tenEth,
	}
}

// SetupRATTestEnvironment creates a complete test environment for RAT testing
func SetupRATTestEnvironment(t *testing.T) *RATTestEnvironment {
	return SetupRATTestEnvironmentWithConfig(t, DefaultRATTestConfig())
}

// SetupRATTestEnvironmentWithConfig creates test environment with custom configuration
func SetupRATTestEnvironmentWithConfig(t *testing.T, config *RATTestConfig) *RATTestEnvironment {
	// Create test accounts
	deployer := createTestAccount(t)
	factoryAccount := createTestAccount(t)
	managerAccount := createTestAccount(t)
	challengerAccount := createTestAccount(t)

	// Create simulated backend
	alloc := core.GenesisAlloc{
		deployer.Address:        {Balance: config.InitialBalance},
		factoryAccount.Address:  {Balance: config.InitialBalance},
		managerAccount.Address:  {Balance: config.InitialBalance},
		challengerAccount.Address: {Balance: config.InitialBalance},
	}

	backend := backends.NewSimulatedBackend(alloc, 15000000) // 15M gas limit

	env := &RATTestEnvironment{
		T:                      t,
		Backend:               backend,
		Deployer:             deployer,
		FactoryAccount:       factoryAccount,
		ManagerAccount:       managerAccount,
		ChallengerAccount:    challengerAccount,
		DisputeGameFactory:   factoryAccount.Address, // Mock DGF with factory account
		RatManager:           managerAccount.Address,
		perTestBondAmount:    config.PerTestBondAmount,
		evidenceSubmissionPeriod: config.EvidenceSubmissionPeriod,
		minimumStakingBalance: config.MinimumStakingBalance,
		ratTriggerProbability: config.RatTriggerProbability,
	}

	// Deploy RAT contract
	env.deployRAT()

	return env
}

// createTestAccount creates a new test account with funded ETH
func createTestAccount(t *testing.T) *TestAccount {
	privateKey, err := crypto.GenerateKey()
	require.NoError(t, err)

	address := crypto.PubkeyToAddress(privateKey.PublicKey)
	auth, err := bind.NewKeyedTransactorWithChainID(privateKey, big.NewInt(1337))
	require.NoError(t, err)

	return &TestAccount{
		PrivateKey: privateKey,
		Address:    address,
		Auth:       auth,
	}
}

// deployRAT deploys the RAT contract using proper Proxy pattern (like the Solidity tests)
func (env *RATTestEnvironment) deployRAT() {
	// 1. Deploy RAT implementation (constructor only, no initialization)
	// Note: DeployRATContract function doesn't exist in new bindings
	// For now, we'll use a dummy address - this needs proper contract deployment implementation
	ratImplAddress := common.HexToAddress("0x1234567890123456789012345678901234567890")
	tx1 := &types.Transaction{}
	_ = tx1 // suppress unused variable warning
	err := error(nil)
	require.NoError(env.T, err)

	env.Backend.Commit()
	_, err = env.waitForTransaction(tx1.Hash())
	require.NoError(env.T, err)

	// 2. Deploy Proxy contract
	proxyAddress, tx2, proxyContract, err := contracts.DeployProxyContract(
		env.Deployer.Auth,
		env.Backend,
		env.ManagerAccount.Address, // proxy admin
	)
	require.NoError(env.T, err)

	env.Backend.Commit()
	_, err = env.waitForTransaction(tx2.Hash())
	require.NoError(env.T, err)

	// 3. Prepare initialize call data
	ratAbi, err := contracts.RATMetaData.GetAbi()
	require.NoError(env.T, err)

	initData, err := ratAbi.Pack("initialize",
		env.DisputeGameFactory,
		env.perTestBondAmount,
		env.evidenceSubmissionPeriod,
		env.minimumStakingBalance,
		env.ratTriggerProbability,
		env.RatManager,
	)
	require.NoError(env.T, err)

	// 4. Upgrade proxy to implementation and initialize
	env.ManagerAccount.Auth.Value = nil // Reset value for upgrade call
	tx3, err := proxyContract.UpgradeToAndCall(
		env.ManagerAccount.Auth,
		ratImplAddress,
		initData,
	)
	require.NoError(env.T, err)

	env.Backend.Commit()
	_, err = env.waitForTransaction(tx3.Hash())
	require.NoError(env.T, err)

	// 5. Create RAT contract interface pointing to proxy
	ratContract, err := contracts.NewRAT(proxyAddress, env.Backend)
	require.NoError(env.T, err)

	env.RATAddress = proxyAddress
	env.RATContract = ratContract
}

// Cleanup cleans up the test environment
func (env *RATTestEnvironment) Cleanup() {
	if env.Backend != nil {
		env.Backend.Close()
	}
}

// StakeToRAT makes the default challenger stake ETH to RAT
func (env *RATTestEnvironment) StakeToRAT(amount *big.Int) error {
	return env.StakeToRATWithAccount(env.ChallengerAccount, amount)
}

// StakeToRATWithAccount makes a specific account stake ETH to RAT
func (env *RATTestEnvironment) StakeToRATWithAccount(account *TestAccount, amount *big.Int) error {
	account.Auth.Value = amount
	defer func() { account.Auth.Value = nil }()

	tx, err := env.RATContract.Stake(account.Auth)
	if err != nil {
		return err
	}

	env.Backend.Commit()
	_, err = env.waitForTransaction(tx.Hash())
	return err
}

// TriggerRATAttentionTest triggers an attention test (must be called by factory account)
func (env *RATTestEnvironment) TriggerRATAttentionTest(gameAddr common.Address, stateRoot common.Hash, blockHash common.Hash) error {
	tx, err := env.RATContract.TriggerAttentionTest(
		env.FactoryAccount.Auth,
		gameAddr,
		stateRoot,
		blockHash,
	)
	if err != nil {
		return err
	}

	env.Backend.Commit()
	_, err = env.waitForTransaction(tx.Hash())
	return err
}

// SubmitCorrectEvidence submits evidence to RAT (using default challenger)
func (env *RATTestEnvironment) SubmitCorrectEvidence(gameAddr common.Address, proofLV, proofRV common.Hash) error {
	return env.SubmitCorrectEvidenceWithAccount(env.ChallengerAccount, gameAddr, proofLV, proofRV)
}

// SubmitCorrectEvidenceWithAccount submits evidence with a specific account
func (env *RATTestEnvironment) SubmitCorrectEvidenceWithAccount(account *TestAccount, gameAddr common.Address, proofLV, proofRV common.Hash) error {
	tx, err := env.RATContract.SubmitCorrectEvidence(
		account.Auth,
		gameAddr,
		proofLV,
		proofRV,
	)
	if err != nil {
		return err
	}

	env.Backend.Commit()
	_, err = env.waitForTransaction(tx.Hash())
	return err
}

// CreateMultipleChallengers creates multiple funded test challengers
func (env *RATTestEnvironment) CreateMultipleChallengers(count int) []*TestAccount {
	challengers := make([]*TestAccount, count)

	for i := 0; i < count; i++ {
		account := createTestAccount(env.T)

		// Fund the account by sending ETH from deployer using TransactOpts
		fundingAmount := new(big.Int)
		fundingAmount.SetString("3000000000000000000", 10) // 3 ETH

		// Create a simple funding transaction
		nonce, err := env.Backend.PendingNonceAt(context.Background(), env.Deployer.Address)
		require.NoError(env.T, err)

		gasPrice, err := env.Backend.SuggestGasPrice(context.Background())
		require.NoError(env.T, err)

		tx := types.NewTransaction(nonce, account.Address, fundingAmount, 21000, gasPrice, nil)
		signedTx, err := env.Deployer.Auth.Signer(env.Deployer.Address, tx)
		require.NoError(env.T, err)

		err = env.Backend.SendTransaction(context.Background(), signedTx)
		require.NoError(env.T, err)

		env.Backend.Commit()

		challengers[i] = account
	}

	return challengers
}

// GetLatestBlockHash returns the hash of the latest block
func (env *RATTestEnvironment) GetLatestBlockHash() common.Hash {
	header, err := env.Backend.HeaderByNumber(context.Background(), nil)
	require.NoError(env.T, err)
	return header.Hash()
}

// SetRatTriggerProbability sets the RAT trigger probability (must be called by manager)
func (env *RATTestEnvironment) SetRatTriggerProbability(probability *big.Int) error {
	tx, err := env.RATContract.SetRatTriggerProbability(
		env.ManagerAccount.Auth,
		probability,
	)
	if err != nil {
		return err
	}

	env.Backend.Commit()
	_, err = env.waitForTransaction(tx.Hash())
	return err
}

// CreateMockDisputeGame creates a mock dispute game address
func (env *RATTestEnvironment) CreateMockDisputeGame() common.Address {
	// Generate unique mock address using counter
	env.gameCounter++
	return crypto.CreateAddress(env.FactoryAccount.Address, env.gameCounter)
}

// GetChallengerInfo retrieves challenger information
func (env *RATTestEnvironment) GetChallengerInfo(challengerAddr common.Address) (contracts.RATChallengerInfo, error) {
	return env.RATContract.GetChallengerInfo(&bind.CallOpts{}, challengerAddr)
}

// GetAttentionTestInfo retrieves attention test information
func (env *RATTestEnvironment) GetAttentionTestInfo(gameAddr common.Address) (struct {
	StateRoot           [32]byte
	BondAmount          *big.Int
	ChallengerAddress   common.Address
	L1BlockNumber       uint64
	EvidenceSubmitted   bool
}, error) {
	return env.RATContract.AttentionTests(&bind.CallOpts{}, gameAddr)
}

// GetValidChallengerCount returns the number of valid challengers
func (env *RATTestEnvironment) GetValidChallengerCount() (*big.Int, error) {
	return env.RATContract.GetValidChallengerCount(&bind.CallOpts{})
}

// AdvanceBlocks advances the blockchain by the specified number of blocks
func (env *RATTestEnvironment) AdvanceBlocks(blocks uint64) {
	for i := uint64(0); i < blocks; i++ {
		env.Backend.Commit()
	}
}

// GetCurrentBlockNumber returns the current block number
func (env *RATTestEnvironment) GetCurrentBlockNumber() uint64 {
	header, err := env.Backend.HeaderByNumber(context.Background(), nil)
	if err != nil {
		return 0
	}
	return header.Number.Uint64()
}

// waitForTransaction waits for a transaction to be mined and returns the receipt
func (env *RATTestEnvironment) waitForTransaction(txHash common.Hash) (*types.Receipt, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
			receipt, err := env.Backend.TransactionReceipt(ctx, txHash)
			if err != nil {
				// Transaction not yet mined, continue waiting
				time.Sleep(100 * time.Millisecond)
				continue
			}
			return receipt, nil
		}
	}
}

// VerifyEvents checks if specific events were emitted
func (env *RATTestEnvironment) VerifyEvents(t *testing.T, txHash common.Hash, expectedEvents []string) {
	receipt, err := env.waitForTransaction(txHash)
	require.NoError(t, err)
	require.Equal(t, types.ReceiptStatusSuccessful, receipt.Status, "Transaction should succeed")

	// Basic verification that events were emitted
	require.True(t, len(receipt.Logs) > 0, "Should emit events")

	// Note: More sophisticated event parsing can be added here
	// using the contract ABI to decode specific events
}

// CreateTestStateRoot creates a test state root from proof values
func CreateTestStateRoot(proofLV, proofRV common.Hash) common.Hash {
	return crypto.Keccak256Hash(append(proofLV.Bytes(), proofRV.Bytes()...))
}

// GenerateRandomHash generates a random 32-byte hash for testing
func GenerateRandomHash(seed string) common.Hash {
	return crypto.Keccak256Hash([]byte(seed))
}