// Code generated - DO NOT EDIT.
// This file is a generated binding and any manual changes will be lost.

package contracts

import (
	"errors"
	"math/big"
	"strings"

	ethereum "github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/event"
)

// Reference imports to suppress errors if they are not otherwise used.
var (
	_ = errors.New
	_ = big.NewInt
	_ = strings.NewReader
	_ = ethereum.NotFound
	_ = bind.Bind
	_ = common.Big1
	_ = types.BloomLookup
	_ = event.NewSubscription
	_ = abi.ConvertType
)

// RATChallengerInfo is an auto generated low-level Go binding around an user-defined struct.
type RATChallengerInfo struct {
	StakingAmount      *big.Int
	TotalSlashedAmount *big.Int
	ValidatorIndex     uint32
	IsValid            bool
}

// RATMetaData contains all meta data concerning the RAT contract.
var RATMetaData = &bind.MetaData{
	ABI: "[{\"type\":\"constructor\",\"inputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"attentionTests\",\"inputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"stateRoot\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"},{\"name\":\"bondAmount\",\"type\":\"uint96\",\"internalType\":\"uint96\"},{\"name\":\"challengerAddress\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"l1BlockNumber\",\"type\":\"uint64\",\"internalType\":\"uint64\"},{\"name\":\"evidenceSubmitted\",\"type\":\"bool\",\"internalType\":\"bool\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"challengers\",\"inputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"stakingAmount\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"totalSlashedAmount\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"validatorIndex\",\"type\":\"uint32\",\"internalType\":\"uint32\"},{\"name\":\"isValid\",\"type\":\"bool\",\"internalType\":\"bool\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"disputeGameFactory\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"contractIDisputeGameFactory\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"evidenceSubmissionPeriod\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"getChallengerInfo\",\"inputs\":[{\"name\":\"_challenger\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[{\"name\":\"\",\"type\":\"tuple\",\"internalType\":\"structRAT.ChallengerInfo\",\"components\":[{\"name\":\"stakingAmount\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"totalSlashedAmount\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"validatorIndex\",\"type\":\"uint32\",\"internalType\":\"uint32\"},{\"name\":\"isValid\",\"type\":\"bool\",\"internalType\":\"bool\"}]}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"getValidChallengerCount\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"initVersion\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"uint8\",\"internalType\":\"uint8\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"initialize\",\"inputs\":[{\"name\":\"_disputeGameFactory\",\"type\":\"address\",\"internalType\":\"contractIDisputeGameFactory\"},{\"name\":\"_perTestBondAmount\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"_evidenceSubmissionPeriod\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"_minimumStakingBalance\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"_ratTriggerProbability\",\"type\":\"uint256\",\"internalType\":\"uint256\"},{\"name\":\"_manager\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[],\"stateMutability\":\"payable\"},{\"type\":\"function\",\"name\":\"minimumStakingBalance\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"perTestBondAmount\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"proxyAdmin\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"contractIProxyAdmin\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"proxyAdminOwner\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"ratManager\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"ratTriggerProbability\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"resolveClaim\",\"inputs\":[{\"name\":\"_claimant\",\"type\":\"address\",\"internalType\":\"address\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"setEvidenceSubmissionPeriod\",\"inputs\":[{\"name\":\"_period\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"setMinimumStakingBalance\",\"inputs\":[{\"name\":\"_balance\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"setPerTestBondAmount\",\"inputs\":[{\"name\":\"_amount\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"setRatTriggerProbability\",\"inputs\":[{\"name\":\"_probability\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"stake\",\"inputs\":[],\"outputs\":[],\"stateMutability\":\"payable\"},{\"type\":\"function\",\"name\":\"submitCorrectEvidence\",\"inputs\":[{\"name\":\"_gameAddress\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"_proofLV\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"},{\"name\":\"_proofRV\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"triggerAttentionTest\",\"inputs\":[{\"name\":\"_gameAddress\",\"type\":\"address\",\"internalType\":\"address\"},{\"name\":\"_stateRoot\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"},{\"name\":\"_blockHash\",\"type\":\"bytes32\",\"internalType\":\"bytes32\"}],\"outputs\":[],\"stateMutability\":\"nonpayable\"},{\"type\":\"function\",\"name\":\"validChallengers\",\"inputs\":[{\"name\":\"\",\"type\":\"uint256\",\"internalType\":\"uint256\"}],\"outputs\":[{\"name\":\"\",\"type\":\"address\",\"internalType\":\"address\"}],\"stateMutability\":\"view\"},{\"type\":\"function\",\"name\":\"version\",\"inputs\":[],\"outputs\":[{\"name\":\"\",\"type\":\"string\",\"internalType\":\"string\"}],\"stateMutability\":\"view\"},{\"type\":\"event\",\"name\":\"AttentionTriggered\",\"inputs\":[{\"name\":\"gameAddress\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"challenger\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"}],\"anonymous\":false},{\"type\":\"event\",\"name\":\"BondRefunded\",\"inputs\":[{\"name\":\"gameAddress\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"challenger\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"refundedAmount\",\"type\":\"uint256\",\"indexed\":false,\"internalType\":\"uint256\"}],\"anonymous\":false},{\"type\":\"event\",\"name\":\"ChallengerStaked\",\"inputs\":[{\"name\":\"challenger\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"amount\",\"type\":\"uint256\",\"indexed\":false,\"internalType\":\"uint256\"}],\"anonymous\":false},{\"type\":\"event\",\"name\":\"CorrectEvidenceSubmitted\",\"inputs\":[{\"name\":\"gameAddress\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"challenger\",\"type\":\"address\",\"indexed\":true,\"internalType\":\"address\"},{\"name\":\"restoredAmount\",\"type\":\"uint256\",\"indexed\":false,\"internalType\":\"uint256\"}],\"anonymous\":false},{\"type\":\"event\",\"name\":\"Initialized\",\"inputs\":[{\"name\":\"version\",\"type\":\"uint8\",\"indexed\":false,\"internalType\":\"uint8\"}],\"anonymous\":false},{\"type\":\"error\",\"name\":\"AttentionTestNotExists\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"ChallengerNotExists\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"EvidenceAlreadySubmitted\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"EvidenceSubmissionExpired\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"InsufficientStakingAmount\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"InvalidChallengerAddress\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"NoValidChallengers\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"NotDisputeGameFactory\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"NotRatManager\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"ProofVerificationFailed\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"ProxyAdminOwnedBase_NotProxyAdmin\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"ProxyAdminOwnedBase_NotProxyAdminOrProxyAdminOwner\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"ProxyAdminOwnedBase_NotProxyAdminOwner\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"ProxyAdminOwnedBase_NotResolvedDelegateProxy\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"ProxyAdminOwnedBase_NotSharedProxyAdminOwner\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"ProxyAdminOwnedBase_ProxyAdminNotFound\",\"inputs\":[]},{\"type\":\"error\",\"name\":\"ReinitializableBase_ZeroInitVersion\",\"inputs\":[]}]",
}

// RATABI is the input ABI used to generate the binding from.
// Deprecated: Use RATMetaData.ABI instead.
var RATABI = RATMetaData.ABI

// RAT is an auto generated Go binding around an Ethereum contract.
type RAT struct {
	RATCaller     // Read-only binding to the contract
	RATTransactor // Write-only binding to the contract
	RATFilterer   // Log filterer for contract events
}

// RATCaller is an auto generated read-only Go binding around an Ethereum contract.
type RATCaller struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// RATTransactor is an auto generated write-only Go binding around an Ethereum contract.
type RATTransactor struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// RATFilterer is an auto generated log filtering Go binding around an Ethereum contract events.
type RATFilterer struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// RATSession is an auto generated Go binding around an Ethereum contract,
// with pre-set call and transact options.
type RATSession struct {
	Contract     *RAT              // Generic contract binding to set the session for
	CallOpts     bind.CallOpts     // Call options to use throughout this session
	TransactOpts bind.TransactOpts // Transaction auth options to use throughout this session
}

// RATCallerSession is an auto generated read-only Go binding around an Ethereum contract,
// with pre-set call options.
type RATCallerSession struct {
	Contract *RATCaller    // Generic contract caller binding to set the session for
	CallOpts bind.CallOpts // Call options to use throughout this session
}

// RATTransactorSession is an auto generated write-only Go binding around an Ethereum contract,
// with pre-set transact options.
type RATTransactorSession struct {
	Contract     *RATTransactor    // Generic contract transactor binding to set the session for
	TransactOpts bind.TransactOpts // Transaction auth options to use throughout this session
}

// RATRaw is an auto generated low-level Go binding around an Ethereum contract.
type RATRaw struct {
	Contract *RAT // Generic contract binding to access the raw methods on
}

// RATCallerRaw is an auto generated low-level read-only Go binding around an Ethereum contract.
type RATCallerRaw struct {
	Contract *RATCaller // Generic read-only contract binding to access the raw methods on
}

// RATTransactorRaw is an auto generated low-level write-only Go binding around an Ethereum contract.
type RATTransactorRaw struct {
	Contract *RATTransactor // Generic write-only contract binding to access the raw methods on
}

// NewRAT creates a new instance of RAT, bound to a specific deployed contract.
func NewRAT(address common.Address, backend bind.ContractBackend) (*RAT, error) {
	contract, err := bindRAT(address, backend, backend, backend)
	if err != nil {
		return nil, err
	}
	return &RAT{RATCaller: RATCaller{contract: contract}, RATTransactor: RATTransactor{contract: contract}, RATFilterer: RATFilterer{contract: contract}}, nil
}

// NewRATCaller creates a new read-only instance of RAT, bound to a specific deployed contract.
func NewRATCaller(address common.Address, caller bind.ContractCaller) (*RATCaller, error) {
	contract, err := bindRAT(address, caller, nil, nil)
	if err != nil {
		return nil, err
	}
	return &RATCaller{contract: contract}, nil
}

// NewRATTransactor creates a new write-only instance of RAT, bound to a specific deployed contract.
func NewRATTransactor(address common.Address, transactor bind.ContractTransactor) (*RATTransactor, error) {
	contract, err := bindRAT(address, nil, transactor, nil)
	if err != nil {
		return nil, err
	}
	return &RATTransactor{contract: contract}, nil
}

// NewRATFilterer creates a new log filterer instance of RAT, bound to a specific deployed contract.
func NewRATFilterer(address common.Address, filterer bind.ContractFilterer) (*RATFilterer, error) {
	contract, err := bindRAT(address, nil, nil, filterer)
	if err != nil {
		return nil, err
	}
	return &RATFilterer{contract: contract}, nil
}

// bindRAT binds a generic wrapper to an already deployed contract.
func bindRAT(address common.Address, caller bind.ContractCaller, transactor bind.ContractTransactor, filterer bind.ContractFilterer) (*bind.BoundContract, error) {
	parsed, err := RATMetaData.GetAbi()
	if err != nil {
		return nil, err
	}
	return bind.NewBoundContract(address, *parsed, caller, transactor, filterer), nil
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_RAT *RATRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _RAT.Contract.RATCaller.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_RAT *RATRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _RAT.Contract.RATTransactor.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_RAT *RATRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _RAT.Contract.RATTransactor.contract.Transact(opts, method, params...)
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_RAT *RATCallerRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _RAT.Contract.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_RAT *RATTransactorRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _RAT.Contract.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_RAT *RATTransactorRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _RAT.Contract.contract.Transact(opts, method, params...)
}

// AttentionTests is a free data retrieval call binding the contract method 0xfba1d220.
//
// Solidity: function attentionTests(address ) view returns(bytes32 stateRoot, uint96 bondAmount, address challengerAddress, uint64 l1BlockNumber, bool evidenceSubmitted)
func (_RAT *RATCaller) AttentionTests(opts *bind.CallOpts, arg0 common.Address) (struct {
	StateRoot         [32]byte
	BondAmount        *big.Int
	ChallengerAddress common.Address
	L1BlockNumber     uint64
	EvidenceSubmitted bool
}, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "attentionTests", arg0)

	outstruct := new(struct {
		StateRoot         [32]byte
		BondAmount        *big.Int
		ChallengerAddress common.Address
		L1BlockNumber     uint64
		EvidenceSubmitted bool
	})
	if err != nil {
		return *outstruct, err
	}

	outstruct.StateRoot = *abi.ConvertType(out[0], new([32]byte)).(*[32]byte)
	outstruct.BondAmount = *abi.ConvertType(out[1], new(*big.Int)).(**big.Int)
	outstruct.ChallengerAddress = *abi.ConvertType(out[2], new(common.Address)).(*common.Address)
	outstruct.L1BlockNumber = *abi.ConvertType(out[3], new(uint64)).(*uint64)
	outstruct.EvidenceSubmitted = *abi.ConvertType(out[4], new(bool)).(*bool)

	return *outstruct, err

}

// AttentionTests is a free data retrieval call binding the contract method 0xfba1d220.
//
// Solidity: function attentionTests(address ) view returns(bytes32 stateRoot, uint96 bondAmount, address challengerAddress, uint64 l1BlockNumber, bool evidenceSubmitted)
func (_RAT *RATSession) AttentionTests(arg0 common.Address) (struct {
	StateRoot         [32]byte
	BondAmount        *big.Int
	ChallengerAddress common.Address
	L1BlockNumber     uint64
	EvidenceSubmitted bool
}, error) {
	return _RAT.Contract.AttentionTests(&_RAT.CallOpts, arg0)
}

// AttentionTests is a free data retrieval call binding the contract method 0xfba1d220.
//
// Solidity: function attentionTests(address ) view returns(bytes32 stateRoot, uint96 bondAmount, address challengerAddress, uint64 l1BlockNumber, bool evidenceSubmitted)
func (_RAT *RATCallerSession) AttentionTests(arg0 common.Address) (struct {
	StateRoot         [32]byte
	BondAmount        *big.Int
	ChallengerAddress common.Address
	L1BlockNumber     uint64
	EvidenceSubmitted bool
}, error) {
	return _RAT.Contract.AttentionTests(&_RAT.CallOpts, arg0)
}

// Challengers is a free data retrieval call binding the contract method 0xcfea71c0.
//
// Solidity: function challengers(address ) view returns(uint256 stakingAmount, uint256 totalSlashedAmount, uint32 validatorIndex, bool isValid)
func (_RAT *RATCaller) Challengers(opts *bind.CallOpts, arg0 common.Address) (struct {
	StakingAmount      *big.Int
	TotalSlashedAmount *big.Int
	ValidatorIndex     uint32
	IsValid            bool
}, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "challengers", arg0)

	outstruct := new(struct {
		StakingAmount      *big.Int
		TotalSlashedAmount *big.Int
		ValidatorIndex     uint32
		IsValid            bool
	})
	if err != nil {
		return *outstruct, err
	}

	outstruct.StakingAmount = *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)
	outstruct.TotalSlashedAmount = *abi.ConvertType(out[1], new(*big.Int)).(**big.Int)
	outstruct.ValidatorIndex = *abi.ConvertType(out[2], new(uint32)).(*uint32)
	outstruct.IsValid = *abi.ConvertType(out[3], new(bool)).(*bool)

	return *outstruct, err

}

// Challengers is a free data retrieval call binding the contract method 0xcfea71c0.
//
// Solidity: function challengers(address ) view returns(uint256 stakingAmount, uint256 totalSlashedAmount, uint32 validatorIndex, bool isValid)
func (_RAT *RATSession) Challengers(arg0 common.Address) (struct {
	StakingAmount      *big.Int
	TotalSlashedAmount *big.Int
	ValidatorIndex     uint32
	IsValid            bool
}, error) {
	return _RAT.Contract.Challengers(&_RAT.CallOpts, arg0)
}

// Challengers is a free data retrieval call binding the contract method 0xcfea71c0.
//
// Solidity: function challengers(address ) view returns(uint256 stakingAmount, uint256 totalSlashedAmount, uint32 validatorIndex, bool isValid)
func (_RAT *RATCallerSession) Challengers(arg0 common.Address) (struct {
	StakingAmount      *big.Int
	TotalSlashedAmount *big.Int
	ValidatorIndex     uint32
	IsValid            bool
}, error) {
	return _RAT.Contract.Challengers(&_RAT.CallOpts, arg0)
}

// DisputeGameFactory is a free data retrieval call binding the contract method 0xf2b4e617.
//
// Solidity: function disputeGameFactory() view returns(address)
func (_RAT *RATCaller) DisputeGameFactory(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "disputeGameFactory")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// DisputeGameFactory is a free data retrieval call binding the contract method 0xf2b4e617.
//
// Solidity: function disputeGameFactory() view returns(address)
func (_RAT *RATSession) DisputeGameFactory() (common.Address, error) {
	return _RAT.Contract.DisputeGameFactory(&_RAT.CallOpts)
}

// DisputeGameFactory is a free data retrieval call binding the contract method 0xf2b4e617.
//
// Solidity: function disputeGameFactory() view returns(address)
func (_RAT *RATCallerSession) DisputeGameFactory() (common.Address, error) {
	return _RAT.Contract.DisputeGameFactory(&_RAT.CallOpts)
}

// EvidenceSubmissionPeriod is a free data retrieval call binding the contract method 0xacccb08f.
//
// Solidity: function evidenceSubmissionPeriod() view returns(uint256)
func (_RAT *RATCaller) EvidenceSubmissionPeriod(opts *bind.CallOpts) (*big.Int, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "evidenceSubmissionPeriod")

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// EvidenceSubmissionPeriod is a free data retrieval call binding the contract method 0xacccb08f.
//
// Solidity: function evidenceSubmissionPeriod() view returns(uint256)
func (_RAT *RATSession) EvidenceSubmissionPeriod() (*big.Int, error) {
	return _RAT.Contract.EvidenceSubmissionPeriod(&_RAT.CallOpts)
}

// EvidenceSubmissionPeriod is a free data retrieval call binding the contract method 0xacccb08f.
//
// Solidity: function evidenceSubmissionPeriod() view returns(uint256)
func (_RAT *RATCallerSession) EvidenceSubmissionPeriod() (*big.Int, error) {
	return _RAT.Contract.EvidenceSubmissionPeriod(&_RAT.CallOpts)
}

// GetChallengerInfo is a free data retrieval call binding the contract method 0x18350f22.
//
// Solidity: function getChallengerInfo(address _challenger) view returns((uint256,uint256,uint32,bool))
func (_RAT *RATCaller) GetChallengerInfo(opts *bind.CallOpts, _challenger common.Address) (RATChallengerInfo, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "getChallengerInfo", _challenger)

	if err != nil {
		return *new(RATChallengerInfo), err
	}

	out0 := *abi.ConvertType(out[0], new(RATChallengerInfo)).(*RATChallengerInfo)

	return out0, err

}

// GetChallengerInfo is a free data retrieval call binding the contract method 0x18350f22.
//
// Solidity: function getChallengerInfo(address _challenger) view returns((uint256,uint256,uint32,bool))
func (_RAT *RATSession) GetChallengerInfo(_challenger common.Address) (RATChallengerInfo, error) {
	return _RAT.Contract.GetChallengerInfo(&_RAT.CallOpts, _challenger)
}

// GetChallengerInfo is a free data retrieval call binding the contract method 0x18350f22.
//
// Solidity: function getChallengerInfo(address _challenger) view returns((uint256,uint256,uint32,bool))
func (_RAT *RATCallerSession) GetChallengerInfo(_challenger common.Address) (RATChallengerInfo, error) {
	return _RAT.Contract.GetChallengerInfo(&_RAT.CallOpts, _challenger)
}

// GetValidChallengerCount is a free data retrieval call binding the contract method 0xcc57f42b.
//
// Solidity: function getValidChallengerCount() view returns(uint256)
func (_RAT *RATCaller) GetValidChallengerCount(opts *bind.CallOpts) (*big.Int, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "getValidChallengerCount")

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// GetValidChallengerCount is a free data retrieval call binding the contract method 0xcc57f42b.
//
// Solidity: function getValidChallengerCount() view returns(uint256)
func (_RAT *RATSession) GetValidChallengerCount() (*big.Int, error) {
	return _RAT.Contract.GetValidChallengerCount(&_RAT.CallOpts)
}

// GetValidChallengerCount is a free data retrieval call binding the contract method 0xcc57f42b.
//
// Solidity: function getValidChallengerCount() view returns(uint256)
func (_RAT *RATCallerSession) GetValidChallengerCount() (*big.Int, error) {
	return _RAT.Contract.GetValidChallengerCount(&_RAT.CallOpts)
}

// InitVersion is a free data retrieval call binding the contract method 0x38d38c97.
//
// Solidity: function initVersion() view returns(uint8)
func (_RAT *RATCaller) InitVersion(opts *bind.CallOpts) (uint8, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "initVersion")

	if err != nil {
		return *new(uint8), err
	}

	out0 := *abi.ConvertType(out[0], new(uint8)).(*uint8)

	return out0, err

}

// InitVersion is a free data retrieval call binding the contract method 0x38d38c97.
//
// Solidity: function initVersion() view returns(uint8)
func (_RAT *RATSession) InitVersion() (uint8, error) {
	return _RAT.Contract.InitVersion(&_RAT.CallOpts)
}

// InitVersion is a free data retrieval call binding the contract method 0x38d38c97.
//
// Solidity: function initVersion() view returns(uint8)
func (_RAT *RATCallerSession) InitVersion() (uint8, error) {
	return _RAT.Contract.InitVersion(&_RAT.CallOpts)
}

// MinimumStakingBalance is a free data retrieval call binding the contract method 0xe3478659.
//
// Solidity: function minimumStakingBalance() view returns(uint256)
func (_RAT *RATCaller) MinimumStakingBalance(opts *bind.CallOpts) (*big.Int, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "minimumStakingBalance")

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// MinimumStakingBalance is a free data retrieval call binding the contract method 0xe3478659.
//
// Solidity: function minimumStakingBalance() view returns(uint256)
func (_RAT *RATSession) MinimumStakingBalance() (*big.Int, error) {
	return _RAT.Contract.MinimumStakingBalance(&_RAT.CallOpts)
}

// MinimumStakingBalance is a free data retrieval call binding the contract method 0xe3478659.
//
// Solidity: function minimumStakingBalance() view returns(uint256)
func (_RAT *RATCallerSession) MinimumStakingBalance() (*big.Int, error) {
	return _RAT.Contract.MinimumStakingBalance(&_RAT.CallOpts)
}

// PerTestBondAmount is a free data retrieval call binding the contract method 0xcf60203e.
//
// Solidity: function perTestBondAmount() view returns(uint256)
func (_RAT *RATCaller) PerTestBondAmount(opts *bind.CallOpts) (*big.Int, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "perTestBondAmount")

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// PerTestBondAmount is a free data retrieval call binding the contract method 0xcf60203e.
//
// Solidity: function perTestBondAmount() view returns(uint256)
func (_RAT *RATSession) PerTestBondAmount() (*big.Int, error) {
	return _RAT.Contract.PerTestBondAmount(&_RAT.CallOpts)
}

// PerTestBondAmount is a free data retrieval call binding the contract method 0xcf60203e.
//
// Solidity: function perTestBondAmount() view returns(uint256)
func (_RAT *RATCallerSession) PerTestBondAmount() (*big.Int, error) {
	return _RAT.Contract.PerTestBondAmount(&_RAT.CallOpts)
}

// ProxyAdmin is a free data retrieval call binding the contract method 0x3e47158c.
//
// Solidity: function proxyAdmin() view returns(address)
func (_RAT *RATCaller) ProxyAdmin(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "proxyAdmin")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// ProxyAdmin is a free data retrieval call binding the contract method 0x3e47158c.
//
// Solidity: function proxyAdmin() view returns(address)
func (_RAT *RATSession) ProxyAdmin() (common.Address, error) {
	return _RAT.Contract.ProxyAdmin(&_RAT.CallOpts)
}

// ProxyAdmin is a free data retrieval call binding the contract method 0x3e47158c.
//
// Solidity: function proxyAdmin() view returns(address)
func (_RAT *RATCallerSession) ProxyAdmin() (common.Address, error) {
	return _RAT.Contract.ProxyAdmin(&_RAT.CallOpts)
}

// ProxyAdminOwner is a free data retrieval call binding the contract method 0xdad544e0.
//
// Solidity: function proxyAdminOwner() view returns(address)
func (_RAT *RATCaller) ProxyAdminOwner(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "proxyAdminOwner")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// ProxyAdminOwner is a free data retrieval call binding the contract method 0xdad544e0.
//
// Solidity: function proxyAdminOwner() view returns(address)
func (_RAT *RATSession) ProxyAdminOwner() (common.Address, error) {
	return _RAT.Contract.ProxyAdminOwner(&_RAT.CallOpts)
}

// ProxyAdminOwner is a free data retrieval call binding the contract method 0xdad544e0.
//
// Solidity: function proxyAdminOwner() view returns(address)
func (_RAT *RATCallerSession) ProxyAdminOwner() (common.Address, error) {
	return _RAT.Contract.ProxyAdminOwner(&_RAT.CallOpts)
}

// RatManager is a free data retrieval call binding the contract method 0x1ecbb09c.
//
// Solidity: function ratManager() view returns(address)
func (_RAT *RATCaller) RatManager(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "ratManager")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// RatManager is a free data retrieval call binding the contract method 0x1ecbb09c.
//
// Solidity: function ratManager() view returns(address)
func (_RAT *RATSession) RatManager() (common.Address, error) {
	return _RAT.Contract.RatManager(&_RAT.CallOpts)
}

// RatManager is a free data retrieval call binding the contract method 0x1ecbb09c.
//
// Solidity: function ratManager() view returns(address)
func (_RAT *RATCallerSession) RatManager() (common.Address, error) {
	return _RAT.Contract.RatManager(&_RAT.CallOpts)
}

// RatTriggerProbability is a free data retrieval call binding the contract method 0x51567bc2.
//
// Solidity: function ratTriggerProbability() view returns(uint256)
func (_RAT *RATCaller) RatTriggerProbability(opts *bind.CallOpts) (*big.Int, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "ratTriggerProbability")

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// RatTriggerProbability is a free data retrieval call binding the contract method 0x51567bc2.
//
// Solidity: function ratTriggerProbability() view returns(uint256)
func (_RAT *RATSession) RatTriggerProbability() (*big.Int, error) {
	return _RAT.Contract.RatTriggerProbability(&_RAT.CallOpts)
}

// RatTriggerProbability is a free data retrieval call binding the contract method 0x51567bc2.
//
// Solidity: function ratTriggerProbability() view returns(uint256)
func (_RAT *RATCallerSession) RatTriggerProbability() (*big.Int, error) {
	return _RAT.Contract.RatTriggerProbability(&_RAT.CallOpts)
}

// ValidChallengers is a free data retrieval call binding the contract method 0x74343de8.
//
// Solidity: function validChallengers(uint256 ) view returns(address)
func (_RAT *RATCaller) ValidChallengers(opts *bind.CallOpts, arg0 *big.Int) (common.Address, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "validChallengers", arg0)

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// ValidChallengers is a free data retrieval call binding the contract method 0x74343de8.
//
// Solidity: function validChallengers(uint256 ) view returns(address)
func (_RAT *RATSession) ValidChallengers(arg0 *big.Int) (common.Address, error) {
	return _RAT.Contract.ValidChallengers(&_RAT.CallOpts, arg0)
}

// ValidChallengers is a free data retrieval call binding the contract method 0x74343de8.
//
// Solidity: function validChallengers(uint256 ) view returns(address)
func (_RAT *RATCallerSession) ValidChallengers(arg0 *big.Int) (common.Address, error) {
	return _RAT.Contract.ValidChallengers(&_RAT.CallOpts, arg0)
}

// Version is a free data retrieval call binding the contract method 0x54fd4d50.
//
// Solidity: function version() view returns(string)
func (_RAT *RATCaller) Version(opts *bind.CallOpts) (string, error) {
	var out []interface{}
	err := _RAT.contract.Call(opts, &out, "version")

	if err != nil {
		return *new(string), err
	}

	out0 := *abi.ConvertType(out[0], new(string)).(*string)

	return out0, err

}

// Version is a free data retrieval call binding the contract method 0x54fd4d50.
//
// Solidity: function version() view returns(string)
func (_RAT *RATSession) Version() (string, error) {
	return _RAT.Contract.Version(&_RAT.CallOpts)
}

// Version is a free data retrieval call binding the contract method 0x54fd4d50.
//
// Solidity: function version() view returns(string)
func (_RAT *RATCallerSession) Version() (string, error) {
	return _RAT.Contract.Version(&_RAT.CallOpts)
}

// Initialize is a paid mutator transaction binding the contract method 0x5df5f96f.
//
// Solidity: function initialize(address _disputeGameFactory, uint256 _perTestBondAmount, uint256 _evidenceSubmissionPeriod, uint256 _minimumStakingBalance, uint256 _ratTriggerProbability, address _manager) payable returns()
func (_RAT *RATTransactor) Initialize(opts *bind.TransactOpts, _disputeGameFactory common.Address, _perTestBondAmount *big.Int, _evidenceSubmissionPeriod *big.Int, _minimumStakingBalance *big.Int, _ratTriggerProbability *big.Int, _manager common.Address) (*types.Transaction, error) {
	return _RAT.contract.Transact(opts, "initialize", _disputeGameFactory, _perTestBondAmount, _evidenceSubmissionPeriod, _minimumStakingBalance, _ratTriggerProbability, _manager)
}

// Initialize is a paid mutator transaction binding the contract method 0x5df5f96f.
//
// Solidity: function initialize(address _disputeGameFactory, uint256 _perTestBondAmount, uint256 _evidenceSubmissionPeriod, uint256 _minimumStakingBalance, uint256 _ratTriggerProbability, address _manager) payable returns()
func (_RAT *RATSession) Initialize(_disputeGameFactory common.Address, _perTestBondAmount *big.Int, _evidenceSubmissionPeriod *big.Int, _minimumStakingBalance *big.Int, _ratTriggerProbability *big.Int, _manager common.Address) (*types.Transaction, error) {
	return _RAT.Contract.Initialize(&_RAT.TransactOpts, _disputeGameFactory, _perTestBondAmount, _evidenceSubmissionPeriod, _minimumStakingBalance, _ratTriggerProbability, _manager)
}

// Initialize is a paid mutator transaction binding the contract method 0x5df5f96f.
//
// Solidity: function initialize(address _disputeGameFactory, uint256 _perTestBondAmount, uint256 _evidenceSubmissionPeriod, uint256 _minimumStakingBalance, uint256 _ratTriggerProbability, address _manager) payable returns()
func (_RAT *RATTransactorSession) Initialize(_disputeGameFactory common.Address, _perTestBondAmount *big.Int, _evidenceSubmissionPeriod *big.Int, _minimumStakingBalance *big.Int, _ratTriggerProbability *big.Int, _manager common.Address) (*types.Transaction, error) {
	return _RAT.Contract.Initialize(&_RAT.TransactOpts, _disputeGameFactory, _perTestBondAmount, _evidenceSubmissionPeriod, _minimumStakingBalance, _ratTriggerProbability, _manager)
}

// ResolveClaim is a paid mutator transaction binding the contract method 0x94d645a8.
//
// Solidity: function resolveClaim(address _claimant) returns()
func (_RAT *RATTransactor) ResolveClaim(opts *bind.TransactOpts, _claimant common.Address) (*types.Transaction, error) {
	return _RAT.contract.Transact(opts, "resolveClaim", _claimant)
}

// ResolveClaim is a paid mutator transaction binding the contract method 0x94d645a8.
//
// Solidity: function resolveClaim(address _claimant) returns()
func (_RAT *RATSession) ResolveClaim(_claimant common.Address) (*types.Transaction, error) {
	return _RAT.Contract.ResolveClaim(&_RAT.TransactOpts, _claimant)
}

// ResolveClaim is a paid mutator transaction binding the contract method 0x94d645a8.
//
// Solidity: function resolveClaim(address _claimant) returns()
func (_RAT *RATTransactorSession) ResolveClaim(_claimant common.Address) (*types.Transaction, error) {
	return _RAT.Contract.ResolveClaim(&_RAT.TransactOpts, _claimant)
}

// SetEvidenceSubmissionPeriod is a paid mutator transaction binding the contract method 0x36c63d46.
//
// Solidity: function setEvidenceSubmissionPeriod(uint256 _period) returns()
func (_RAT *RATTransactor) SetEvidenceSubmissionPeriod(opts *bind.TransactOpts, _period *big.Int) (*types.Transaction, error) {
	return _RAT.contract.Transact(opts, "setEvidenceSubmissionPeriod", _period)
}

// SetEvidenceSubmissionPeriod is a paid mutator transaction binding the contract method 0x36c63d46.
//
// Solidity: function setEvidenceSubmissionPeriod(uint256 _period) returns()
func (_RAT *RATSession) SetEvidenceSubmissionPeriod(_period *big.Int) (*types.Transaction, error) {
	return _RAT.Contract.SetEvidenceSubmissionPeriod(&_RAT.TransactOpts, _period)
}

// SetEvidenceSubmissionPeriod is a paid mutator transaction binding the contract method 0x36c63d46.
//
// Solidity: function setEvidenceSubmissionPeriod(uint256 _period) returns()
func (_RAT *RATTransactorSession) SetEvidenceSubmissionPeriod(_period *big.Int) (*types.Transaction, error) {
	return _RAT.Contract.SetEvidenceSubmissionPeriod(&_RAT.TransactOpts, _period)
}

// SetMinimumStakingBalance is a paid mutator transaction binding the contract method 0xfd5f97e1.
//
// Solidity: function setMinimumStakingBalance(uint256 _balance) returns()
func (_RAT *RATTransactor) SetMinimumStakingBalance(opts *bind.TransactOpts, _balance *big.Int) (*types.Transaction, error) {
	return _RAT.contract.Transact(opts, "setMinimumStakingBalance", _balance)
}

// SetMinimumStakingBalance is a paid mutator transaction binding the contract method 0xfd5f97e1.
//
// Solidity: function setMinimumStakingBalance(uint256 _balance) returns()
func (_RAT *RATSession) SetMinimumStakingBalance(_balance *big.Int) (*types.Transaction, error) {
	return _RAT.Contract.SetMinimumStakingBalance(&_RAT.TransactOpts, _balance)
}

// SetMinimumStakingBalance is a paid mutator transaction binding the contract method 0xfd5f97e1.
//
// Solidity: function setMinimumStakingBalance(uint256 _balance) returns()
func (_RAT *RATTransactorSession) SetMinimumStakingBalance(_balance *big.Int) (*types.Transaction, error) {
	return _RAT.Contract.SetMinimumStakingBalance(&_RAT.TransactOpts, _balance)
}

// SetPerTestBondAmount is a paid mutator transaction binding the contract method 0xcc447906.
//
// Solidity: function setPerTestBondAmount(uint256 _amount) returns()
func (_RAT *RATTransactor) SetPerTestBondAmount(opts *bind.TransactOpts, _amount *big.Int) (*types.Transaction, error) {
	return _RAT.contract.Transact(opts, "setPerTestBondAmount", _amount)
}

// SetPerTestBondAmount is a paid mutator transaction binding the contract method 0xcc447906.
//
// Solidity: function setPerTestBondAmount(uint256 _amount) returns()
func (_RAT *RATSession) SetPerTestBondAmount(_amount *big.Int) (*types.Transaction, error) {
	return _RAT.Contract.SetPerTestBondAmount(&_RAT.TransactOpts, _amount)
}

// SetPerTestBondAmount is a paid mutator transaction binding the contract method 0xcc447906.
//
// Solidity: function setPerTestBondAmount(uint256 _amount) returns()
func (_RAT *RATTransactorSession) SetPerTestBondAmount(_amount *big.Int) (*types.Transaction, error) {
	return _RAT.Contract.SetPerTestBondAmount(&_RAT.TransactOpts, _amount)
}

// SetRatTriggerProbability is a paid mutator transaction binding the contract method 0xd2e5bc72.
//
// Solidity: function setRatTriggerProbability(uint256 _probability) returns()
func (_RAT *RATTransactor) SetRatTriggerProbability(opts *bind.TransactOpts, _probability *big.Int) (*types.Transaction, error) {
	return _RAT.contract.Transact(opts, "setRatTriggerProbability", _probability)
}

// SetRatTriggerProbability is a paid mutator transaction binding the contract method 0xd2e5bc72.
//
// Solidity: function setRatTriggerProbability(uint256 _probability) returns()
func (_RAT *RATSession) SetRatTriggerProbability(_probability *big.Int) (*types.Transaction, error) {
	return _RAT.Contract.SetRatTriggerProbability(&_RAT.TransactOpts, _probability)
}

// SetRatTriggerProbability is a paid mutator transaction binding the contract method 0xd2e5bc72.
//
// Solidity: function setRatTriggerProbability(uint256 _probability) returns()
func (_RAT *RATTransactorSession) SetRatTriggerProbability(_probability *big.Int) (*types.Transaction, error) {
	return _RAT.Contract.SetRatTriggerProbability(&_RAT.TransactOpts, _probability)
}

// Stake is a paid mutator transaction binding the contract method 0x3a4b66f1.
//
// Solidity: function stake() payable returns()
func (_RAT *RATTransactor) Stake(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _RAT.contract.Transact(opts, "stake")
}

// Stake is a paid mutator transaction binding the contract method 0x3a4b66f1.
//
// Solidity: function stake() payable returns()
func (_RAT *RATSession) Stake() (*types.Transaction, error) {
	return _RAT.Contract.Stake(&_RAT.TransactOpts)
}

// Stake is a paid mutator transaction binding the contract method 0x3a4b66f1.
//
// Solidity: function stake() payable returns()
func (_RAT *RATTransactorSession) Stake() (*types.Transaction, error) {
	return _RAT.Contract.Stake(&_RAT.TransactOpts)
}

// SubmitCorrectEvidence is a paid mutator transaction binding the contract method 0xaacff5f9.
//
// Solidity: function submitCorrectEvidence(address _gameAddress, bytes32 _proofLV, bytes32 _proofRV) returns()
func (_RAT *RATTransactor) SubmitCorrectEvidence(opts *bind.TransactOpts, _gameAddress common.Address, _proofLV [32]byte, _proofRV [32]byte) (*types.Transaction, error) {
	return _RAT.contract.Transact(opts, "submitCorrectEvidence", _gameAddress, _proofLV, _proofRV)
}

// SubmitCorrectEvidence is a paid mutator transaction binding the contract method 0xaacff5f9.
//
// Solidity: function submitCorrectEvidence(address _gameAddress, bytes32 _proofLV, bytes32 _proofRV) returns()
func (_RAT *RATSession) SubmitCorrectEvidence(_gameAddress common.Address, _proofLV [32]byte, _proofRV [32]byte) (*types.Transaction, error) {
	return _RAT.Contract.SubmitCorrectEvidence(&_RAT.TransactOpts, _gameAddress, _proofLV, _proofRV)
}

// SubmitCorrectEvidence is a paid mutator transaction binding the contract method 0xaacff5f9.
//
// Solidity: function submitCorrectEvidence(address _gameAddress, bytes32 _proofLV, bytes32 _proofRV) returns()
func (_RAT *RATTransactorSession) SubmitCorrectEvidence(_gameAddress common.Address, _proofLV [32]byte, _proofRV [32]byte) (*types.Transaction, error) {
	return _RAT.Contract.SubmitCorrectEvidence(&_RAT.TransactOpts, _gameAddress, _proofLV, _proofRV)
}

// TriggerAttentionTest is a paid mutator transaction binding the contract method 0x96e9b641.
//
// Solidity: function triggerAttentionTest(address _gameAddress, bytes32 _stateRoot, bytes32 _blockHash) returns()
func (_RAT *RATTransactor) TriggerAttentionTest(opts *bind.TransactOpts, _gameAddress common.Address, _stateRoot [32]byte, _blockHash [32]byte) (*types.Transaction, error) {
	return _RAT.contract.Transact(opts, "triggerAttentionTest", _gameAddress, _stateRoot, _blockHash)
}

// TriggerAttentionTest is a paid mutator transaction binding the contract method 0x96e9b641.
//
// Solidity: function triggerAttentionTest(address _gameAddress, bytes32 _stateRoot, bytes32 _blockHash) returns()
func (_RAT *RATSession) TriggerAttentionTest(_gameAddress common.Address, _stateRoot [32]byte, _blockHash [32]byte) (*types.Transaction, error) {
	return _RAT.Contract.TriggerAttentionTest(&_RAT.TransactOpts, _gameAddress, _stateRoot, _blockHash)
}

// TriggerAttentionTest is a paid mutator transaction binding the contract method 0x96e9b641.
//
// Solidity: function triggerAttentionTest(address _gameAddress, bytes32 _stateRoot, bytes32 _blockHash) returns()
func (_RAT *RATTransactorSession) TriggerAttentionTest(_gameAddress common.Address, _stateRoot [32]byte, _blockHash [32]byte) (*types.Transaction, error) {
	return _RAT.Contract.TriggerAttentionTest(&_RAT.TransactOpts, _gameAddress, _stateRoot, _blockHash)
}

// RATAttentionTriggeredIterator is returned from FilterAttentionTriggered and is used to iterate over the raw logs and unpacked data for AttentionTriggered events raised by the RAT contract.
type RATAttentionTriggeredIterator struct {
	Event *RATAttentionTriggered // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *RATAttentionTriggeredIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(RATAttentionTriggered)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(RATAttentionTriggered)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *RATAttentionTriggeredIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *RATAttentionTriggeredIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// RATAttentionTriggered represents a AttentionTriggered event raised by the RAT contract.
type RATAttentionTriggered struct {
	GameAddress common.Address
	Challenger  common.Address
	Raw         types.Log // Blockchain specific contextual infos
}

// FilterAttentionTriggered is a free log retrieval operation binding the contract event 0x8f5f18c2fab75f3bb8637c4702468685d73e9414ddfa43f842ffb1a63e6dd57a.
//
// Solidity: event AttentionTriggered(address indexed gameAddress, address indexed challenger)
func (_RAT *RATFilterer) FilterAttentionTriggered(opts *bind.FilterOpts, gameAddress []common.Address, challenger []common.Address) (*RATAttentionTriggeredIterator, error) {

	var gameAddressRule []interface{}
	for _, gameAddressItem := range gameAddress {
		gameAddressRule = append(gameAddressRule, gameAddressItem)
	}
	var challengerRule []interface{}
	for _, challengerItem := range challenger {
		challengerRule = append(challengerRule, challengerItem)
	}

	logs, sub, err := _RAT.contract.FilterLogs(opts, "AttentionTriggered", gameAddressRule, challengerRule)
	if err != nil {
		return nil, err
	}
	return &RATAttentionTriggeredIterator{contract: _RAT.contract, event: "AttentionTriggered", logs: logs, sub: sub}, nil
}

// WatchAttentionTriggered is a free log subscription operation binding the contract event 0x8f5f18c2fab75f3bb8637c4702468685d73e9414ddfa43f842ffb1a63e6dd57a.
//
// Solidity: event AttentionTriggered(address indexed gameAddress, address indexed challenger)
func (_RAT *RATFilterer) WatchAttentionTriggered(opts *bind.WatchOpts, sink chan<- *RATAttentionTriggered, gameAddress []common.Address, challenger []common.Address) (event.Subscription, error) {

	var gameAddressRule []interface{}
	for _, gameAddressItem := range gameAddress {
		gameAddressRule = append(gameAddressRule, gameAddressItem)
	}
	var challengerRule []interface{}
	for _, challengerItem := range challenger {
		challengerRule = append(challengerRule, challengerItem)
	}

	logs, sub, err := _RAT.contract.WatchLogs(opts, "AttentionTriggered", gameAddressRule, challengerRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(RATAttentionTriggered)
				if err := _RAT.contract.UnpackLog(event, "AttentionTriggered", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseAttentionTriggered is a log parse operation binding the contract event 0x8f5f18c2fab75f3bb8637c4702468685d73e9414ddfa43f842ffb1a63e6dd57a.
//
// Solidity: event AttentionTriggered(address indexed gameAddress, address indexed challenger)
func (_RAT *RATFilterer) ParseAttentionTriggered(log types.Log) (*RATAttentionTriggered, error) {
	event := new(RATAttentionTriggered)
	if err := _RAT.contract.UnpackLog(event, "AttentionTriggered", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// RATBondRefundedIterator is returned from FilterBondRefunded and is used to iterate over the raw logs and unpacked data for BondRefunded events raised by the RAT contract.
type RATBondRefundedIterator struct {
	Event *RATBondRefunded // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *RATBondRefundedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(RATBondRefunded)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(RATBondRefunded)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *RATBondRefundedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *RATBondRefundedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// RATBondRefunded represents a BondRefunded event raised by the RAT contract.
type RATBondRefunded struct {
	GameAddress    common.Address
	Challenger     common.Address
	RefundedAmount *big.Int
	Raw            types.Log // Blockchain specific contextual infos
}

// FilterBondRefunded is a free log retrieval operation binding the contract event 0x4fac74d6b4ed45cb641c8e730951b01c4dbcae0565cf330e909230492bd07d78.
//
// Solidity: event BondRefunded(address indexed gameAddress, address indexed challenger, uint256 refundedAmount)
func (_RAT *RATFilterer) FilterBondRefunded(opts *bind.FilterOpts, gameAddress []common.Address, challenger []common.Address) (*RATBondRefundedIterator, error) {

	var gameAddressRule []interface{}
	for _, gameAddressItem := range gameAddress {
		gameAddressRule = append(gameAddressRule, gameAddressItem)
	}
	var challengerRule []interface{}
	for _, challengerItem := range challenger {
		challengerRule = append(challengerRule, challengerItem)
	}

	logs, sub, err := _RAT.contract.FilterLogs(opts, "BondRefunded", gameAddressRule, challengerRule)
	if err != nil {
		return nil, err
	}
	return &RATBondRefundedIterator{contract: _RAT.contract, event: "BondRefunded", logs: logs, sub: sub}, nil
}

// WatchBondRefunded is a free log subscription operation binding the contract event 0x4fac74d6b4ed45cb641c8e730951b01c4dbcae0565cf330e909230492bd07d78.
//
// Solidity: event BondRefunded(address indexed gameAddress, address indexed challenger, uint256 refundedAmount)
func (_RAT *RATFilterer) WatchBondRefunded(opts *bind.WatchOpts, sink chan<- *RATBondRefunded, gameAddress []common.Address, challenger []common.Address) (event.Subscription, error) {

	var gameAddressRule []interface{}
	for _, gameAddressItem := range gameAddress {
		gameAddressRule = append(gameAddressRule, gameAddressItem)
	}
	var challengerRule []interface{}
	for _, challengerItem := range challenger {
		challengerRule = append(challengerRule, challengerItem)
	}

	logs, sub, err := _RAT.contract.WatchLogs(opts, "BondRefunded", gameAddressRule, challengerRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(RATBondRefunded)
				if err := _RAT.contract.UnpackLog(event, "BondRefunded", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseBondRefunded is a log parse operation binding the contract event 0x4fac74d6b4ed45cb641c8e730951b01c4dbcae0565cf330e909230492bd07d78.
//
// Solidity: event BondRefunded(address indexed gameAddress, address indexed challenger, uint256 refundedAmount)
func (_RAT *RATFilterer) ParseBondRefunded(log types.Log) (*RATBondRefunded, error) {
	event := new(RATBondRefunded)
	if err := _RAT.contract.UnpackLog(event, "BondRefunded", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// RATChallengerStakedIterator is returned from FilterChallengerStaked and is used to iterate over the raw logs and unpacked data for ChallengerStaked events raised by the RAT contract.
type RATChallengerStakedIterator struct {
	Event *RATChallengerStaked // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *RATChallengerStakedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(RATChallengerStaked)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(RATChallengerStaked)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *RATChallengerStakedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *RATChallengerStakedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// RATChallengerStaked represents a ChallengerStaked event raised by the RAT contract.
type RATChallengerStaked struct {
	Challenger common.Address
	Amount     *big.Int
	Raw        types.Log // Blockchain specific contextual infos
}

// FilterChallengerStaked is a free log retrieval operation binding the contract event 0x6f50cc7a01f21c217b2ae66736754596de2004562a26fcc850e70031e5985e8d.
//
// Solidity: event ChallengerStaked(address indexed challenger, uint256 amount)
func (_RAT *RATFilterer) FilterChallengerStaked(opts *bind.FilterOpts, challenger []common.Address) (*RATChallengerStakedIterator, error) {

	var challengerRule []interface{}
	for _, challengerItem := range challenger {
		challengerRule = append(challengerRule, challengerItem)
	}

	logs, sub, err := _RAT.contract.FilterLogs(opts, "ChallengerStaked", challengerRule)
	if err != nil {
		return nil, err
	}
	return &RATChallengerStakedIterator{contract: _RAT.contract, event: "ChallengerStaked", logs: logs, sub: sub}, nil
}

// WatchChallengerStaked is a free log subscription operation binding the contract event 0x6f50cc7a01f21c217b2ae66736754596de2004562a26fcc850e70031e5985e8d.
//
// Solidity: event ChallengerStaked(address indexed challenger, uint256 amount)
func (_RAT *RATFilterer) WatchChallengerStaked(opts *bind.WatchOpts, sink chan<- *RATChallengerStaked, challenger []common.Address) (event.Subscription, error) {

	var challengerRule []interface{}
	for _, challengerItem := range challenger {
		challengerRule = append(challengerRule, challengerItem)
	}

	logs, sub, err := _RAT.contract.WatchLogs(opts, "ChallengerStaked", challengerRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(RATChallengerStaked)
				if err := _RAT.contract.UnpackLog(event, "ChallengerStaked", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseChallengerStaked is a log parse operation binding the contract event 0x6f50cc7a01f21c217b2ae66736754596de2004562a26fcc850e70031e5985e8d.
//
// Solidity: event ChallengerStaked(address indexed challenger, uint256 amount)
func (_RAT *RATFilterer) ParseChallengerStaked(log types.Log) (*RATChallengerStaked, error) {
	event := new(RATChallengerStaked)
	if err := _RAT.contract.UnpackLog(event, "ChallengerStaked", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// RATCorrectEvidenceSubmittedIterator is returned from FilterCorrectEvidenceSubmitted and is used to iterate over the raw logs and unpacked data for CorrectEvidenceSubmitted events raised by the RAT contract.
type RATCorrectEvidenceSubmittedIterator struct {
	Event *RATCorrectEvidenceSubmitted // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *RATCorrectEvidenceSubmittedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(RATCorrectEvidenceSubmitted)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(RATCorrectEvidenceSubmitted)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *RATCorrectEvidenceSubmittedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *RATCorrectEvidenceSubmittedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// RATCorrectEvidenceSubmitted represents a CorrectEvidenceSubmitted event raised by the RAT contract.
type RATCorrectEvidenceSubmitted struct {
	GameAddress    common.Address
	Challenger     common.Address
	RestoredAmount *big.Int
	Raw            types.Log // Blockchain specific contextual infos
}

// FilterCorrectEvidenceSubmitted is a free log retrieval operation binding the contract event 0x7954ca3465b792ac0a46ec18f1ed49a20399c01cc510fab6eab44a7f6679f877.
//
// Solidity: event CorrectEvidenceSubmitted(address indexed gameAddress, address indexed challenger, uint256 restoredAmount)
func (_RAT *RATFilterer) FilterCorrectEvidenceSubmitted(opts *bind.FilterOpts, gameAddress []common.Address, challenger []common.Address) (*RATCorrectEvidenceSubmittedIterator, error) {

	var gameAddressRule []interface{}
	for _, gameAddressItem := range gameAddress {
		gameAddressRule = append(gameAddressRule, gameAddressItem)
	}
	var challengerRule []interface{}
	for _, challengerItem := range challenger {
		challengerRule = append(challengerRule, challengerItem)
	}

	logs, sub, err := _RAT.contract.FilterLogs(opts, "CorrectEvidenceSubmitted", gameAddressRule, challengerRule)
	if err != nil {
		return nil, err
	}
	return &RATCorrectEvidenceSubmittedIterator{contract: _RAT.contract, event: "CorrectEvidenceSubmitted", logs: logs, sub: sub}, nil
}

// WatchCorrectEvidenceSubmitted is a free log subscription operation binding the contract event 0x7954ca3465b792ac0a46ec18f1ed49a20399c01cc510fab6eab44a7f6679f877.
//
// Solidity: event CorrectEvidenceSubmitted(address indexed gameAddress, address indexed challenger, uint256 restoredAmount)
func (_RAT *RATFilterer) WatchCorrectEvidenceSubmitted(opts *bind.WatchOpts, sink chan<- *RATCorrectEvidenceSubmitted, gameAddress []common.Address, challenger []common.Address) (event.Subscription, error) {

	var gameAddressRule []interface{}
	for _, gameAddressItem := range gameAddress {
		gameAddressRule = append(gameAddressRule, gameAddressItem)
	}
	var challengerRule []interface{}
	for _, challengerItem := range challenger {
		challengerRule = append(challengerRule, challengerItem)
	}

	logs, sub, err := _RAT.contract.WatchLogs(opts, "CorrectEvidenceSubmitted", gameAddressRule, challengerRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(RATCorrectEvidenceSubmitted)
				if err := _RAT.contract.UnpackLog(event, "CorrectEvidenceSubmitted", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseCorrectEvidenceSubmitted is a log parse operation binding the contract event 0x7954ca3465b792ac0a46ec18f1ed49a20399c01cc510fab6eab44a7f6679f877.
//
// Solidity: event CorrectEvidenceSubmitted(address indexed gameAddress, address indexed challenger, uint256 restoredAmount)
func (_RAT *RATFilterer) ParseCorrectEvidenceSubmitted(log types.Log) (*RATCorrectEvidenceSubmitted, error) {
	event := new(RATCorrectEvidenceSubmitted)
	if err := _RAT.contract.UnpackLog(event, "CorrectEvidenceSubmitted", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// RATInitializedIterator is returned from FilterInitialized and is used to iterate over the raw logs and unpacked data for Initialized events raised by the RAT contract.
type RATInitializedIterator struct {
	Event *RATInitialized // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *RATInitializedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(RATInitialized)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(RATInitialized)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *RATInitializedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *RATInitializedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// RATInitialized represents a Initialized event raised by the RAT contract.
type RATInitialized struct {
	Version uint8
	Raw     types.Log // Blockchain specific contextual infos
}

// FilterInitialized is a free log retrieval operation binding the contract event 0x7f26b83ff96e1f2b6a682f133852f6798a09c465da95921460cefb3847402498.
//
// Solidity: event Initialized(uint8 version)
func (_RAT *RATFilterer) FilterInitialized(opts *bind.FilterOpts) (*RATInitializedIterator, error) {

	logs, sub, err := _RAT.contract.FilterLogs(opts, "Initialized")
	if err != nil {
		return nil, err
	}
	return &RATInitializedIterator{contract: _RAT.contract, event: "Initialized", logs: logs, sub: sub}, nil
}

// WatchInitialized is a free log subscription operation binding the contract event 0x7f26b83ff96e1f2b6a682f133852f6798a09c465da95921460cefb3847402498.
//
// Solidity: event Initialized(uint8 version)
func (_RAT *RATFilterer) WatchInitialized(opts *bind.WatchOpts, sink chan<- *RATInitialized) (event.Subscription, error) {

	logs, sub, err := _RAT.contract.WatchLogs(opts, "Initialized")
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(RATInitialized)
				if err := _RAT.contract.UnpackLog(event, "Initialized", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseInitialized is a log parse operation binding the contract event 0x7f26b83ff96e1f2b6a682f133852f6798a09c465da95921460cefb3847402498.
//
// Solidity: event Initialized(uint8 version)
func (_RAT *RATFilterer) ParseInitialized(log types.Log) (*RATInitialized, error) {
	event := new(RATInitialized)
	if err := _RAT.contract.UnpackLog(event, "Initialized", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}
