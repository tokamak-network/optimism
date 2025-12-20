package main

import (
	"context"
	// "crypto/ecdsa" -- Removed
	"encoding/hex"
	"encoding/json"
	"flag"
	// "fmt" -- Removed
	"log"
	"math/big"
	"os"
	"strings"
	"time"

	// "github.com/ethereum/go-ethereum/common" -- Removed
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

type AccountConfig struct {
    Proposer   string   `json:"proposer"`   // Hex Private Key
	Validators []string `json:"validators"` // Hex Private Keys
	Spammers   []string `json:"spammers"`   // Hex Private Keys
}

func main() {
	outputFile := flag.String("out", "accounts.json", "Output JSON file for generated accounts")
	adminKeyHex := flag.String("admin-key", "", "Admin Private Key for funding")
	l1Rpc := flag.String("l1-rpc", "http://127.0.0.1:8545", "L1 RPC URL")
	numValidators := flag.Int("validators", 30, "Number of validator accounts")
	numSpammers := flag.Int("spammers", 1000, "Number of spammer accounts")
	fundAmount := flag.String("fund", "1000000000000000000", "Amount to fund in Wei (default 1 ETH)")
	flag.Parse()

	if *adminKeyHex == "" {
		log.Fatal("Admin key required: --admin-key")
	}

	// 1. Generate Accounts
	log.Printf("Generating Proposer, %d Validators and %d Spammers...", *numValidators, *numSpammers)

	config := AccountConfig{
        Proposer:   "",
		Validators: make([]string, *numValidators),
		Spammers:   make([]string, *numSpammers),
	}

    // Generate Proposer Key
    pKey, _ := crypto.GenerateKey()
    config.Proposer = hex.EncodeToString(crypto.FromECDSA(pKey))

	for i := 0; i < *numValidators; i++ {
		key, _ := crypto.GenerateKey()
		config.Validators[i] = hex.EncodeToString(crypto.FromECDSA(key))
	}

	for i := 0; i < *numSpammers; i++ {
		key, _ := crypto.GenerateKey()
		config.Spammers[i] = hex.EncodeToString(crypto.FromECDSA(key))
	}

	// Save to JSON
	file, _ := os.Create(*outputFile)
	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	encoder.Encode(config)
	file.Close()
	log.Printf("Accounts saved to %s", *outputFile)

	// 2. Fund Accounts
	log.Println("Connecting to L1 for funding...")
	client, err := ethclient.Dial(*l1Rpc)
	if err != nil {
		log.Fatalf("Failed to connect to L1: %v", err)
	}
	defer client.Close()

	adminKey, _ := crypto.HexToECDSA(strings.TrimPrefix(*adminKeyHex, "0x"))
	adminAddr := crypto.PubkeyToAddress(adminKey.PublicKey)

	nonce, err := client.PendingNonceAt(context.Background(), adminAddr)
	if err != nil {
		log.Fatal(err)
	}

	chainID, _ := client.ChainID(context.Background())
	amount, _ := new(big.Int).SetString(*fundAmount, 10)
	gasLimit := uint64(21000)
	gasPrice, _ := client.SuggestGasPrice(context.Background())

	// Funding Loop: Fund Proposer, then Validators, then Spammers
    // Proposer gets FULL amount (for many game creations)
    // Validators get FULL amount (for bond)
    // Spammers get 5%

    // Prepend Proposer key to list
	allKeys := append([]string{config.Proposer}, config.Validators...)
    allKeys = append(allKeys, config.Spammers...)

	log.Printf("Funding %d accounts from %s (Nonce: %d)...", len(allKeys), adminAddr.Hex(), nonce)

	for i, keyHex := range allKeys {
		privateKey, _ := crypto.HexToECDSA(keyHex)
		toAddr := crypto.PubkeyToAddress(privateKey.PublicKey)

        // Determine Amount
        currentAmount := amount
        // Index 0 is Proposer (Full)
        // Index 1..N is Validators (Full)
        // Index >N is Spammers (Small)
        if i > len(config.Validators) {
            currentAmount = new(big.Int).Div(amount, big.NewInt(20)) // 0.05 ETH
        }

		// Throttle: wait before sending to prevent "address already reserved"
		if i > 0 {
			time.Sleep(500 * time.Millisecond)
		}

		tx := types.NewTransaction(nonce, toAddr, currentAmount, gasLimit, gasPrice, nil)
		signedTx, _ := types.SignTx(tx, types.NewEIP155Signer(chainID), adminKey)

		err = client.SendTransaction(context.Background(), signedTx)
		if err != nil {
			log.Printf("Failed to fund %s: %v", toAddr.Hex(), err)
		}

		nonce++
		if i%5 == 0 {
			log.Printf("Funded %d/%d accounts...", i, len(allKeys))
		}
	}

	log.Println("Funding complete.")
}
