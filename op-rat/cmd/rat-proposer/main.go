package main

import (
	"context"
	"flag"
	"log"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/rpc"
)

// DisputeGameFactory ABI for create()
const dgfABI = `[{"type":"function","name":"create","inputs":[{"name":"_gameType","type":"uint32","internalType":"GameType"},{"name":"_rootClaim","type":"bytes32","internalType":"Claim"},{"name":"_extraData","type":"bytes","internalType":"bytes"}],"outputs":[{"name":"proxy_","type":"address","internalType":"contract IDisputeGame"}],"stateMutability":"payable"}]`

// L2ToL1MessagePasser predeploy address
var messagePasserAddr = common.HexToAddress("0x4200000000000000000000000000000000000016")

func main() {
	l1Rpc := flag.String("l1-rpc", "", "L1 RPC URL")
	l2Rpc := flag.String("l2-rpc", "", "L2 RPC URL")
	dgfContract := flag.String("dgf-contract", "", "DisputeGameFactory Contract Address")
	privateKeyHex := flag.String("private-key", "", "Proposer Private Key")
	limit := flag.Int("limit", 10, "Number of blocks to commit")
	flag.Parse()

	if *l1Rpc == "" || *l2Rpc == "" || *dgfContract == "" || *privateKeyHex == "" {
		log.Fatal("All flags required: --l1-rpc, --l2-rpc, --dgf-contract, --private-key")
	}

	// 1. Connect to L1
	l1Client, err := ethclient.Dial(*l1Rpc)
	if err != nil {
		log.Fatalf("Failed to connect to L1: %v", err)
	}
	defer l1Client.Close()

	chainID, _ := l1Client.ChainID(context.Background())
	pk, _ := crypto.HexToECDSA(strings.TrimPrefix(*privateKeyHex, "0x"))
	auth, _ := bind.NewKeyedTransactorWithChainID(pk, chainID)

	parsedABI, _ := abi.JSON(strings.NewReader(dgfABI))
	dgfAddr := common.HexToAddress(*dgfContract)
	dgfBoundContract := bind.NewBoundContract(dgfAddr, parsedABI, l1Client, l1Client, l1Client)

	// 2. Connect to L2 (both ethclient and raw rpc for eth_getProof)
	l2Client, err := ethclient.Dial(*l2Rpc)
	if err != nil {
		log.Fatalf("Failed to connect to L2: %v", err)
	}
	defer l2Client.Close()

	l2RpcClient, err := rpc.Dial(*l2Rpc)
	if err != nil {
		log.Fatalf("Failed to dial L2 RPC: %v", err)
	}
	defer l2RpcClient.Close()

	l2ChainID, err := l2Client.ChainID(context.Background())
	if err != nil {
		log.Fatalf("Failed to get L2 ChainID: %v", err)
	}
	log.Printf("L2 ChainID: %s", l2ChainID.String())

	lastBlock := uint64(0)
	count := 0

	log.Printf("Starting Proposer (Production Mode). Target: %d blocks", *limit)

	for count < *limit {
		// Fetch Full Block
		block, err := l2Client.BlockByNumber(context.Background(), nil)
		if err != nil {
			time.Sleep(500 * time.Millisecond)
			continue
		}

		if block.NumberU64() <= lastBlock {
			time.Sleep(500 * time.Millisecond)
			continue
		}

		lastBlock = block.NumberU64()

		// Fetch messagePasserStorageRoot from L2
		msgPasserRoot, err := getMessagePasserStorageRoot(l2RpcClient, block.Number())
		if err != nil {
			log.Printf("[Block %d] ⚠️ Failed to get messagePasserStorageRoot: %v (using zero)", lastBlock, err)
			msgPasserRoot = common.Hash{}
		}

		// Compute OutputRoot (Production - using real values)
		var zeroHash [32]byte
		outputRootBytes, _ := abi.Arguments{
			{Type: mustParseType("bytes32")},
			{Type: mustParseType("bytes32")},
			{Type: mustParseType("bytes32")},
			{Type: mustParseType("bytes32")},
		}.Pack(
			zeroHash,        // version (always 0)
			block.Root(),    // stateRoot (Real L2 State Root)
			msgPasserRoot,   // messagePasserStorageRoot (Real)
			block.Hash(),    // latestBlockhash (Real L2 Block Hash)
		)

		finalRoot := crypto.Keccak256Hash(outputRootBytes)

		log.Printf("[Block %d] StateRoot=%s MsgPasser=%s BlockHash=%s -> OutputRoot=%s",
			lastBlock,
			block.Root().Hex()[:10],
			msgPasserRoot.Hex()[:10],
			block.Hash().Hex()[:10],
			finalRoot.Hex()[:10])

		// Submit to DGF
		nonce, _ := l1Client.PendingNonceAt(context.Background(), auth.From)
		auth.Nonce = big.NewInt(int64(nonce))
		auth.Value = big.NewInt(0)
		auth.GasLimit = 500000

		tx, err := dgfBoundContract.Transact(auth, "create", uint32(0), finalRoot, common.BigToHash(block.Number()).Bytes())
		if err != nil {
			log.Printf("[Block %d] ❌ Create FAILED: %v", lastBlock, err)
			time.Sleep(1 * time.Second)
			continue
		}

		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		receipt, err := bind.WaitMined(ctx, l1Client, tx)
		if err != nil {
			log.Printf("[Block %d] Wait FAILED: %v", lastBlock, err)
			continue
		}

		status := "FAILED"
		if receipt.Status == 1 {
			status = "SUCCESS"
		}
		log.Printf("[Block %d] ✅ Game Created. Status=%s, TxHash=%s", lastBlock, status, tx.Hash().Hex()[:10])

		count++
	}
	log.Println("Proposer finished.")
}

// getMessagePasserStorageRoot fetches the storage root of L2ToL1MessagePasser contract
func getMessagePasserStorageRoot(l2Rpc *rpc.Client, blockNum *big.Int) (common.Hash, error) {
	type accountResult struct {
		StorageHash common.Hash `json:"storageHash"`
	}

	var res accountResult
	blk := "latest"
	if blockNum != nil {
		blk = hexutil.EncodeBig(blockNum)
	}

	err := l2Rpc.CallContext(context.Background(), &res, "eth_getProof", messagePasserAddr, []string{}, blk)
	if err != nil {
		return common.Hash{}, err
	}

	return res.StorageHash, nil
}

func mustParseType(t string) abi.Type {
	parsed, err := abi.NewType(t, "", nil)
	if err != nil {
		log.Fatalf("Parse type error: %v", err)
	}
	return parsed
}
