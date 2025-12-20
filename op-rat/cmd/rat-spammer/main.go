package main

import (
	"context"
	"crypto/ecdsa"
	"flag"
	"fmt"
	"log"
	"math/big"
	"math/rand"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/rpc"
)

var AdminPrivateKeyHex = ""

type ChildWallet struct {
	PrivateKey *ecdsa.PrivateKey
	Address    common.Address
	Nonce      uint64
	Balance    *big.Int
}

// Statistics tracking
type Stats struct {
	TotalTxs      int64
	TotalBursts   int64
	StartTime     time.Time
	mu            sync.Mutex
}

func (s *Stats) Add(txs int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.TotalTxs += int64(txs)
	s.TotalBursts++
}

func (s *Stats) Print() {
	s.mu.Lock()
	defer s.mu.Unlock()
	duration := time.Since(s.StartTime).Seconds()
	if duration > 0 {
		avgTPS := float64(s.TotalTxs) / duration
		log.Printf("═══════════════════════════════════════════════════════")
		log.Printf("📊 SPAMMER STATISTICS")
		log.Printf("   Total Transactions: %d", s.TotalTxs)
		log.Printf("   Total Bursts: %d", s.TotalBursts)
		log.Printf("   Duration: %.1f seconds", duration)
		log.Printf("   Average TPS: %.2f", avgTPS)
		log.Printf("═══════════════════════════════════════════════════════")
	}
}

func main() {
	rpcUrl := flag.String("rpc", "http://localhost:8545", "L2 RPC URL")
	targetTPS := flag.Int("tps", 100, "Target transactions per second (average)")
	variance := flag.Float64("variance", 0.3, "TPS variance (0.3 = ±30%)")
	privateKeyFlag := flag.String("private-key", "", "Admin private key for funding")
	accountCount := flag.Int("accounts", 1000, "Number of child accounts to simulate")
	batchSize := flag.Int("batch-size", 100, "RPC Batch size for submitting transactions")

	flag.Parse()

	if *privateKeyFlag == "" {
		log.Fatal("Please provide --private-key for the Admin account")
	}
	AdminPrivateKeyHex = *privateKeyFlag

	log.Printf("Starting RAT Spammer (Variable TPS Mode)...")
	log.Printf("Target TPS: %d ± %.0f%%, Accounts: %d, BatchSize: %d",
		*targetTPS, *variance*100, *accountCount, *batchSize)

	// Standard Client for setup
	client, err := ethclient.Dial(*rpcUrl)
	if err != nil {
		log.Fatalf("Failed to connect to RPC: %v", err)
	}
	defer client.Close()

	// RPC Client for Batching
	rpcClient, err := rpc.Dial(*rpcUrl)
	if err != nil {
		log.Fatalf("Failed to dial raw RPC: %v", err)
	}
	defer rpcClient.Close()

	// Setup Admin Account
	adminKey, err := crypto.HexToECDSA(CleanKey(AdminPrivateKeyHex))
	if err != nil {
		log.Fatalf("Invalid admin key: %v", err)
	}
	adminAddr := crypto.PubkeyToAddress(adminKey.PublicKey)

	chainID, err := client.ChainID(context.Background())
	if err != nil { log.Fatal(err) }

	adminNonce, err := client.PendingNonceAt(context.Background(), adminAddr)
	if err != nil { log.Fatal(err) }

	log.Printf("Admin: %s (Nonce: %d)", adminAddr.Hex(), adminNonce)

	// Generate Child Wallets
	log.Printf("Generating %d child wallets...", *accountCount)
	wallets := make([]*ChildWallet, *accountCount)
	for i := 0; i < *accountCount; i++ {
		seed := fmt.Sprintf("%s-%d", AdminPrivateKeyHex, i)
		hash := crypto.Keccak256([]byte(seed))
		privKey, _ := crypto.ToECDSA(hash)
		addr := crypto.PubkeyToAddress(privKey.PublicKey)

		wallets[i] = &ChildWallet{
			PrivateKey: privKey,
			Address:    addr,
		}
	}

	// Funding Phase
	firstBal, _ := client.BalanceAt(context.Background(), wallets[0].Address, nil)
	lastBal, _ := client.BalanceAt(context.Background(), wallets[*accountCount-1].Address, nil)
	minBalance := big.NewInt(10000000000000000) // 0.01 ETH

	if firstBal.Cmp(minBalance) < 0 || lastBal.Cmp(minBalance) < 0 {
		log.Printf("Funding child wallets...")
		fundAmount := big.NewInt(10000000000000000)
		gasPrice, _ := client.SuggestGasPrice(context.Background())

		for i, w := range wallets {
			bal, _ := client.BalanceAt(context.Background(), w.Address, nil)
			if bal.Cmp(minBalance) >= 0 { continue }

			tx := types.NewTransaction(adminNonce, w.Address, fundAmount, 21000, gasPrice, nil)
			signedTx, _ := types.SignTx(tx, types.NewEIP155Signer(chainID), adminKey)

			err := client.SendTransaction(context.Background(), signedTx)
			if err != nil {
				log.Printf("Funding failed for %d: %v", i, err)
				time.Sleep(100 * time.Millisecond)
				continue
			}
			adminNonce++
			if i % 100 == 0 { log.Printf("Funded %d/%d...", i, *accountCount); time.Sleep(100*time.Millisecond) }
		}
		log.Printf("Funding done. Waiting 5s...")
		time.Sleep(5 * time.Second)
	} else {
		log.Printf("Wallets appear already funded.")
	}

	// Initialize Nonces
	log.Printf("Syncing child nonces...")
	var wg sync.WaitGroup
	sem := make(chan struct{}, 50)
	for _, w := range wallets {
		wg.Add(1)
		sem <- struct{}{}
		go func(cw *ChildWallet) {
			defer wg.Done()
			defer func() { <-sem }()
			n, err := client.PendingNonceAt(context.Background(), cw.Address)
			if err == nil { cw.Nonce = n }
		}(w)
	}
	wg.Wait()
	log.Printf("Ready to Spam!")

	// Setup signal handler for clean shutdown
	stats := &Stats{StartTime: time.Now()}
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Printf("\n🛑 Shutting down...")
		stats.Print()
		os.Exit(0)
	}()

	// Spam Loop - 1 second interval
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		sentCount := 0
		gasPrice, err := client.SuggestGasPrice(context.Background())
		if err != nil { continue }

		var batchElems []rpc.BatchElem

		// Calculate actual TPS with variance: target ± variance%
		// e.g., 100 TPS with 30% variance = 70-130 TPS
		varianceFactor := 1.0 + (rand.Float64()*2-1) * (*variance)
		actualTxs := int(float64(*targetTPS) * varianceFactor)
		if actualTxs < 1 { actualTxs = 1 }

		for i := 0; i < actualTxs; i++ {
			senderIdx := rand.Intn(*accountCount)
			receiverIdx := rand.Intn(*accountCount)
			if senderIdx == receiverIdx { receiverIdx = (receiverIdx + 1) % *accountCount }
			sender := wallets[senderIdx]
			receiver := wallets[receiverIdx]

			dataLen := rand.Intn(128)
			data := make([]byte, dataLen)
			rand.Read(data)

			tx := types.NewTransaction(sender.Nonce, receiver.Address, big.NewInt(1), 100000, gasPrice, data)
			signedTx, _ := types.SignTx(tx, types.NewEIP155Signer(chainID), sender.PrivateKey)

			txBytes, _ := signedTx.MarshalBinary()
			txHex := hexutil.Encode(txBytes)

			batchElems = append(batchElems, rpc.BatchElem{
				Method: "eth_sendRawTransaction",
				Args:   []interface{}{txHex},
				Result: new(string),
			})

			sender.Nonce++
			sentCount++

			// Flush Batch if Full or End of Burst
			if len(batchElems) >= *batchSize || i == actualTxs-1 {
				err := rpcClient.BatchCall(batchElems)
				if err != nil {
					log.Printf("Batch Error: %v", err)
				}
				batchElems = batchElems[:0]
			}
		}

		stats.Add(sentCount)
		log.Printf("Burst: Sent %d txs (target: %d ±%.0f%%, pool: %d)",
			sentCount, *targetTPS, *variance*100, *accountCount)
	}
}

func CleanKey(k string) string {
	if len(k) > 2 && k[:2] == "0x" { return k[2:] }
	return k
}
