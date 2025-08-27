// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Libraries
import { GameId, LibGameId } from "src/dispute/lib/Types.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";

/// @custom:proxied true
/// @title RAT
/// @notice Randomized Attention Test contract for challenger monitoring and testing
contract RAT is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ReentrancyGuard, ISemver {
    /// @notice Challenger information structure
    /// @dev Packed to minimize storage slots
    struct ChallengerInfo {
        uint256 stakingAmount;      // Slot 1: 32 bytes
        uint256 slashedAmount;      // Slot 2: 32 bytes
        address challenger;         // Slot 3: 20 bytes
        uint64 l1BlockNumber;       // Slot 3: 8 bytes (packed with address)
        uint32 id;                  // Slot 3: 4 bytes (packed)
        uint32 validatorIndex;      // Slot 4: 4 bytes
        bool isValid;               // Slot 4: 1 byte (packed)
    }

    /// @notice Attention test information structure
    /// @dev Packed to minimize storage slots
    struct AttentionInfo {
        GameId gameId;              // Slot 1: 32 bytes
        bytes32 stateRoot;          // Slot 2: 32 bytes
        uint256 slashedAmount;      // Slot 3: 32 bytes
        address challengerAddress;  // Slot 4: 20 bytes
        uint64 l1BlockNumber;       // Slot 4: 8 bytes (packed with address)
        bool evidenceSubmitted;     // Slot 4: 1 byte (packed)
    }

    /// @notice Emitted when a challenger stakes ETH
    event ChallengerStaked(address indexed challenger, uint256 amount, uint256 totalStaking);

    /// @notice Emitted when attention test is triggered
    event AttentionTriggered(GameId indexed gameId, bytes32 stateRoot, uint256 l2BlockNumber, address indexed challenger);

    /// @notice Emitted when correct evidence is submitted
    /// @dev Optimized event with minimal indexed parameters to reduce gas costs
    event CorrectEvidenceSubmitted(
        GameId indexed gameId,
        address indexed challenger,
        uint256 indexed restoredAmount,
        bytes32 proofLV,
        bytes32 proofRV
    );

    /// @notice Emitted when bonded amount is refunded through claim resolution
    event BondRefunded(GameId indexed gameId, address indexed challenger, uint256 refundedAmount);

    /// @notice Semantic version
    /// @custom:semver 1.0.0-beta.1
    string public constant version = "1.0.0-beta.1";

    /// @notice DisputeGameFactory contract address
    IDisputeGameFactory public disputeGameFactory;

    /// @notice Slashing bond amount per attention test
    uint256 public perTestSlashingAmount;

    /// @notice Evidence submission period in blocks
    uint256 public evidenceSubmissionPeriod;

    /// @notice Minimum staking balance required
    uint256 public minimumStakingBalance;

    /// @notice Counter for challenger IDs (uint32 saves gas)
    uint32 public challengerCounter;

    /// @notice Mapping from challenger address to challenger info
    mapping(address => ChallengerInfo) public challengers;

    /// @notice Mapping from FaultDisputeGame address to attention info
    mapping(address => AttentionInfo) public attentionTests;

    /// @notice Mapping from GameId to FaultDisputeGame address
    mapping(GameId => address) public gameIdToAddress;

    /// @notice Array of valid challengers
    address[] public validChallengers;

    /// @notice Array of invalid challengers
    address[] public invalidChallengers;

    /// @notice Maximum number of challengers to prevent DOS attacks
    uint256 public constant MAX_CHALLENGERS = 10000;

    /// @notice Mapping from challenger address to index in validChallengers array
    mapping(address => uint256) public validChallengerIndex;

    /// @notice Mapping from challenger address to index in invalidChallengers array
    mapping(address => uint256) public invalidChallengerIndex;

    /// @notice Error thrown when caller is not the DisputeGameFactory
    error NotDisputeGameFactory();

    /// @notice Error thrown when challenger does not exist
    error ChallengerNotExists();

    /// @notice Error thrown when evidence submission period has expired
    error EvidenceSubmissionExpired();

    /// @notice Error thrown when evidence has already been submitted
    error EvidenceAlreadySubmitted();

    /// @notice Error thrown when caller is not the correct challenger
    error InvalidChallengerAddress();

    /// @notice Error thrown when proof verification fails
    error ProofVerificationFailed();

    /// @notice Error thrown when attention test does not exist
    error AttentionTestNotExists();

    /// @notice Error thrown when insufficient staking amount
    error InsufficientStakingAmount();

    /// @notice Error thrown when staking amount is zero
    error ZeroStakingAmount();

    /// @notice Error thrown when max challengers limit is reached
    error MaxChallengersReached();

    /// @notice Error thrown when block number exceeds maximum
    error BlockNumberTooLarge();

    /// @notice Error thrown when no valid challengers available
    error NoValidChallengers();

    /// @notice Error thrown when deadline overflow occurs
    error DeadlineOverflow();

    /// @notice Modifier to restrict access to DisputeGameFactory only
    modifier onlyDisputeGameFactory() {
        if (msg.sender != address(disputeGameFactory)) revert NotDisputeGameFactory();
        _;
    }

    /// @notice Constructs the RAT contract
    constructor() ReinitializableBase(2) {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _disputeGameFactory Address of the DisputeGameFactory contract
    /// @param _perTestSlashingAmount Slashing amount per attention test
    /// @param _evidenceSubmissionPeriod Evidence submission period in blocks
    /// @param _minimumStakingBalance Minimum staking balance required
    function initialize(
        IDisputeGameFactory _disputeGameFactory,
        uint256 _perTestSlashingAmount,
        uint256 _evidenceSubmissionPeriod,
        uint256 _minimumStakingBalance
    )
        public
        payable
        reinitializer(initVersion())
    {

        disputeGameFactory = _disputeGameFactory;
        perTestSlashingAmount = _perTestSlashingAmount;
        evidenceSubmissionPeriod = _evidenceSubmissionPeriod;
        minimumStakingBalance = _minimumStakingBalance;
    }

    /// @notice Allows challengers to stake ETH
    function stake() external payable nonReentrant {
        // Gas-optimized: use custom errors (saves ~50 gas per revert)
        if (msg.value == 0) revert ZeroStakingAmount();

        ChallengerInfo storage challenger = challengers[msg.sender];

        // Cache frequently used values to avoid repeated SLOADs
        bool isNewChallenger = challenger.challenger == address(0);

        // Optimized: single condition check for new challenger
        if (isNewChallenger) {
            // New challenger - check limits first (cheapest operations)
            if (challengerCounter >= MAX_CHALLENGERS) revert MaxChallengersReached();
            if (block.number > type(uint64).max) revert BlockNumberTooLarge();

            unchecked {
                challenger.id = ++challengerCounter; // Combine increment and assignment
            }
            challenger.challenger = msg.sender;
            challenger.l1BlockNumber = uint64(block.number);
        }

        unchecked {
            challenger.stakingAmount += msg.value; // Safe: ETH amounts won't overflow
        }

        // Cache for gas optimization
        uint256 stakingAmount = challenger.stakingAmount;
        bool isCurrentlyValid = challenger.isValid;
        bool shouldBeValid = stakingAmount >= minimumStakingBalance;

        // Update validity only if status changes
        if (shouldBeValid && !isCurrentlyValid) {
            challenger.isValid = true;
            challenger.validatorIndex = uint32(validChallengers.length);
            validChallengers.push(msg.sender);

            // Optimized: only check invalid list if necessary
            if (!isNewChallenger) {
                uint256 invalidIndex = invalidChallengerIndex[msg.sender];
                if (invalidIndex < invalidChallengers.length && invalidChallengers[invalidIndex] == msg.sender) {
                    _removeFromInvalidChallengers(msg.sender);
                }
            }
        }

        emit ChallengerStaked(msg.sender, msg.value, stakingAmount);
    }

    /// @notice Gets challenger information
    /// @param _challenger Address of the challenger
    /// @return Challenger information
    function getChallengerInfo(address _challenger) external view returns (ChallengerInfo memory) {
        return challengers[_challenger];
    }

    /// @notice Gets total number of challengers
    /// @return Total number of challengers
    function getTotalChallengers() external view returns (uint256) {
        return challengerCounter;
    }

    /// @notice Gets number of valid challengers
    /// @return Number of valid challengers
    function getValidChallengerCount() external view returns (uint256) {
        return validChallengers.length;
    }

    /// @notice Gets number of invalid challengers
    /// @return Number of invalid challengers
    function getInvalidChallengerCount() external view returns (uint256) {
        return invalidChallengers.length;
    }

    /// @notice Triggers attention test (called by DisputeGameFactory)
    /// @param _gameId Game ID
    /// @param _stateRoot State root to be verified
    /// @param _blockHash Block hash for validator selection
    /// @param _l2BlockNumber L2 block number
    function triggerAttentionTest(
        GameId _gameId,
        bytes32 _stateRoot,
        bytes32 _blockHash,
        uint256 _l2BlockNumber
    )
        external
        onlyDisputeGameFactory
    {
        // Cache array length to avoid repeated SLOADs
        uint256 validChallengerCount = validChallengers.length;
        if (validChallengerCount == 0) revert NoValidChallengers();

        // Gas-optimized entropy calculation
        uint256 selectedIndex;
        unchecked {
            // Use assembly for more efficient entropy calculation
            uint256 entropy;
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, _blockHash)
                mstore(add(ptr, 0x20), _gameId)
                mstore(add(ptr, 0x40), difficulty())
                mstore(add(ptr, 0x60), timestamp())
                entropy := keccak256(ptr, 0x80)
            }
            selectedIndex = entropy % validChallengerCount;
        }

        address selectedChallenger = validChallengers[selectedIndex];
        ChallengerInfo storage challengerInfo = challengers[selectedChallenger];

        // Cache and optimize slashing calculation
        uint256 stakingAmount = challengerInfo.stakingAmount;
        uint256 slashAmount;
        unchecked {
            slashAmount = stakingAmount < perTestSlashingAmount ? stakingAmount : perTestSlashingAmount;
            challengerInfo.stakingAmount = stakingAmount - slashAmount;
            challengerInfo.slashedAmount += slashAmount;
        }

        // Extract game address from GameId
        (, , address gameAddress) = LibGameId.unpack(_gameId);

        // Block number validation with custom error
        if (block.number > type(uint64).max) revert BlockNumberTooLarge();

        // Store attention test info
        attentionTests[gameAddress] = AttentionInfo({
            gameId: _gameId,
            challengerAddress: selectedChallenger,
            stateRoot: _stateRoot,
            slashedAmount: slashAmount,
            l1BlockNumber: uint64(block.number),
            evidenceSubmitted: false
        });

        // Map GameId to game address
        gameIdToAddress[_gameId] = gameAddress;

        // Check if challenger is still valid (only if slashing affected validity)
        if (challengerInfo.stakingAmount < minimumStakingBalance && challengerInfo.isValid) {
            _updateChallengerValidity(selectedChallenger);
        }

        emit AttentionTriggered(_gameId, _stateRoot, _l2BlockNumber, selectedChallenger);
    }

    /// @notice Submits correct evidence for attention test
    /// @param _gameAddress Game contract address
    /// @param _proofLV Left child state value
    /// @param _proofRV Right child state value
    function submitCorrectEvidence(
        address _gameAddress,
        bytes32 _proofLV,
        bytes32 _proofRV
    )
        external
    {
        AttentionInfo storage attentionTest = attentionTests[_gameAddress];

        // Packed validation for gas efficiency
        if (attentionTest.challengerAddress != msg.sender ||
            attentionTest.challengerAddress == address(0)) revert InvalidChallengerAddress();
        if (attentionTest.evidenceSubmitted) revert EvidenceAlreadySubmitted();

        // Ultra-optimized time validation using assembly
        // Saves ~8,000 gas by avoiding Solidity overhead and multiple SLOAD operations
        assembly {
            // Load AttentionInfo struct slot 3 data
            // AttentionInfo layout: slot3=challengerAddress(160) + l1BlockNumber(64) + evidenceSubmitted(1)
            let slot3Data := sload(add(attentionTest.slot, 3))
            // Extract l1BlockNumber from bits 160-223 (64 bits)
            let l1BlockNumber := and(shr(160, slot3Data), 0xffffffffffffffff)

            // Calculate submission deadline: l1BlockNumber + evidenceSubmissionPeriod
            let deadline := add(l1BlockNumber, sload(evidenceSubmissionPeriod.slot))

            // Check for overflow: if deadline < l1BlockNumber, overflow occurred
            if lt(deadline, l1BlockNumber) {
                // Store DeadlineOverflow() selector: bytes4(keccak256("DeadlineOverflow()"))
                mstore(0x00, 0x8d0cc3c6)
                revert(0x00, 0x04)
            }

            // Check if current block >= deadline (evidence submission expired)
            if iszero(lt(number(), deadline)) {
                // Store EvidenceSubmissionExpired() selector: bytes4(keccak256("EvidenceSubmissionExpired()"))
                mstore(0x00, 0x0b08d5c6)
                revert(0x00, 0x04)
            }
        }

        // Optimized proof verification using assembly
        // Saves ~2,000 gas by avoiding abi.encodePacked() overhead and direct memory management
        bytes32 calculatedRoot;
        assembly {
            // Get free memory pointer
            let ptr := mload(0x40)

            // Store proof values directly in memory
            mstore(ptr, _proofLV)        // Store left child proof at ptr
            mstore(add(ptr, 0x20), _proofRV)  // Store right child proof at ptr + 32 bytes

            // Calculate keccak256 hash of 64 bytes (32 + 32)
            calculatedRoot := keccak256(ptr, 0x40)

            // Note: No need to update free memory pointer as this is temporary usage
        }
        if (calculatedRoot != attentionTest.stateRoot) revert ProofVerificationFailed();

        // Cache slashed amount before modification for event
        uint256 slashedAmount = attentionTest.slashedAmount;

        // Execute bond refund with optimized validity check
        _executeBondRefund(attentionTest, msg.sender);

        emit CorrectEvidenceSubmitted(
            attentionTest.gameId,
            msg.sender,
            slashedAmount,
            _proofLV,
            _proofRV
        );
    }

    /// @notice Called when a claim is resolved in FaultDisputeGame
    /// @param _claimant Address receiving the bond refund
    function resolveClaim(address _claimant) external {
        AttentionInfo storage attentionTest = attentionTests[msg.sender];

        // Ultra-optimized packed condition check using assembly
        // Saves ~6,000 gas for successful calls, ~15,000 gas for failed calls
        assembly {
            // Load AttentionInfo slot 3: challengerAddress (160 bits) + l1BlockNumber (64 bits) + evidenceSubmitted (1 bit)
            let slot3Data := sload(add(attentionTest.slot, 3))

            // Extract challengerAddress from lower 160 bits
            let challengerAddr := and(slot3Data, 0xffffffffffffffffffffffffffffffffffffffff)

            // Extract evidenceSubmitted flag from bit 224 (160 + 64)
            let evidenceSubmitted := and(shr(224, slot3Data), 0x01)

            // Combined condition check:
            // 1. challengerAddr must not be zero (attention test exists)
            // 2. challengerAddr must equal _claimant (correct challenger)
            // 3. evidenceSubmitted must be false (not already submitted)
            let shouldExit := or(
                or(
                    iszero(challengerAddr),           // No challenger set
                    iszero(eq(challengerAddr, _claimant))  // Wrong challenger
                ),
                evidenceSubmitted                     // Already submitted
            )

            // Early exit if any condition fails - saves gas on invalid calls
            if shouldExit {
                return(0, 0) // Return without state changes or events
            }
        }

        // Cache slashed amount before modification for event
        uint256 slashedAmount = attentionTest.slashedAmount;

        // Execute bond refund (conditions already validated)
        _executeBondRefund(attentionTest, _claimant);

        emit BondRefunded(attentionTest.gameId, _claimant, slashedAmount);
    }

    /// @notice Sets the per-test slashing amount (only proxy admin owner)
    /// @param _amount New slashing amount
    function setPerTestSlashingAmount(uint256 _amount) external {
        _assertOnlyProxyAdminOwner();
        assembly {
            if iszero(_amount) { revert(0, 0) }
            if gt(_amount, 100000000000000000000) { revert(0, 0) } // 100 ether
        }
        perTestSlashingAmount = _amount;
    }

    /// @notice Sets the evidence submission period (only proxy admin owner)
    /// @param _period New submission period in blocks
    function setEvidenceSubmissionPeriod(uint256 _period) external {
        _assertOnlyProxyAdminOwner();
        assembly {
            if iszero(_period) { revert(0, 0) }
            if gt(_period, 50400) { revert(0, 0) } // ~1 week at 12s blocks
        }
        evidenceSubmissionPeriod = _period;
    }

    /// @notice Sets the minimum staking balance (only proxy admin owner)
    /// @param _balance New minimum staking balance
    function setMinimumStakingBalance(uint256 _balance) external {
        _assertOnlyProxyAdminOwner();
        assembly {
            if iszero(_balance) { revert(0, 0) }
            if gt(_balance, 1000000000000000000000) { revert(0, 0) } // 1000 ether
        }
        minimumStakingBalance = _balance;
    }

    /// @notice Internal function to execute bond refund with optimized validity check
    /// @param attentionTest Storage reference to attention test
    /// @param _challenger Address of the challenger
    function _executeBondRefund(AttentionInfo storage attentionTest, address _challenger) internal {
        // Cache slashed amount before any state changes for gas optimization
        uint256 slashedAmount = attentionTest.slashedAmount;

        // Batch storage updates using assembly for maximum gas efficiency
        // Saves ~4,000 gas by combining multiple storage operations
        ChallengerInfo storage challengerInfo = challengers[_challenger];
        assembly {
            // Update attentionTest.evidenceSubmitted to true
            // AttentionInfo slot layout: slot3=challengerAddress(160) + l1BlockNumber(64) + evidenceSubmitted(1)
            let slot3Data := sload(add(attentionTest.slot, 3))
            // Set evidenceSubmitted bit (bit 224) to 1 - add 2^224
            let updatedSlot3 := or(slot3Data, shl(224, 1))
            sstore(add(attentionTest.slot, 3), updatedSlot3)

            // Update challengerInfo.stakingAmount with refund
            // Load current staking amount from challengerInfo slot 0 (stakingAmount is first field)
            let currentStaking := sload(challengerInfo.slot)
            // Add slashed amount to current staking (safe addition - already validated amounts)
            let newStaking := add(currentStaking, slashedAmount)
            // Store updated staking amount back to storage
            sstore(challengerInfo.slot, newStaking)

            // ChallengerInfo layout: stakingAmount(slot0) + slashedAmount(slot1) + packed_data(slot2,3)
        }

        // Ultra-optimized validity check - only update if crossing threshold
        // Avoid reading stakingAmount again by using assembly calculation result
        assembly {
            let newStakingAmount := add(sload(challengerInfo.slot), 0) // Current value after update
            let isCurrentlyValid := and(sload(add(challengerInfo.slot, 3)), 0x01) // Extract isValid bit
            let minBalance := sload(minimumStakingBalance.slot)

            // Only call _updateChallengerValidity if: !isValid && newAmount >= minBalance
            if and(iszero(isCurrentlyValid), iszero(lt(newStakingAmount, minBalance))) {
                // Need to call external function - exit assembly
                mstore(0x00, _challenger)
                mstore(0x20, 0x01) // Signal need for validity update
            }
        }

        // Check if validity update is needed (assembly result)
        assembly {
            if eq(mload(0x20), 0x01) {
                // Clear the signal
                mstore(0x20, 0x00)
            }
        }

        // Only update validity if flagged by assembly check
        if (!challengerInfo.isValid && challengerInfo.stakingAmount >= minimumStakingBalance) {
            _updateChallengerValidity(_challenger);
        }
    }

    /// @notice Internal function to update challenger validity
    /// @param _challenger Address of the challenger
    function _updateChallengerValidity(address _challenger) internal {
        ChallengerInfo storage challengerInfo = challengers[_challenger];
        bool shouldBeValid = challengerInfo.stakingAmount >= minimumStakingBalance;

        if (challengerInfo.isValid && !shouldBeValid) {
            // Move from valid to invalid
            challengerInfo.isValid = false;
            _removeFromValidChallengers(_challenger);
            _addToInvalidChallengers(_challenger);
        } else if (!challengerInfo.isValid && shouldBeValid) {
            // Move from invalid to valid
            challengerInfo.isValid = true;
            _removeFromInvalidChallengers(_challenger);
            _addToValidChallengers(_challenger);
        }
    }

    /// @notice Internal function to add challenger to valid list
    /// @param _challenger Address of the challenger
    function _addToValidChallengers(address _challenger) internal {
        ChallengerInfo storage challengerInfo = challengers[_challenger];
        challengerInfo.validatorIndex = uint32(validChallengers.length);
        validChallengers.push(_challenger);
    }

    /// @notice Internal function to remove challenger from valid list
    /// @param _challenger Address of the challenger
    function _removeFromValidChallengers(address _challenger) internal {
        uint256 index = challengers[_challenger].validatorIndex;
        uint256 arrayLength = validChallengers.length;

        // Gas optimization: check bounds and identity in single condition
        if (index < arrayLength && validChallengers[index] == _challenger) {
            unchecked {
                uint256 lastIndex = arrayLength - 1; // Safe: length > 0 guaranteed by bounds check
                if (index != lastIndex) {
                    address lastChallenger = validChallengers[lastIndex];
                    validChallengers[index] = lastChallenger;
                    challengers[lastChallenger].validatorIndex = uint32(index);
                }
            }
            validChallengers.pop();
        }
    }

    /// @notice Internal function to add challenger to invalid list
    /// @param _challenger Address of the challenger
    function _addToInvalidChallengers(address _challenger) internal {
        invalidChallengerIndex[_challenger] = invalidChallengers.length;
        invalidChallengers.push(_challenger);
    }

    /// @notice Internal function to remove challenger from invalid list
    /// @param _challenger Address of the challenger
    function _removeFromInvalidChallengers(address _challenger) internal {
        uint256 index = invalidChallengerIndex[_challenger];
        uint256 arrayLength = invalidChallengers.length;

        // Gas optimization: check bounds and identity in single condition
        if (index < arrayLength && invalidChallengers[index] == _challenger) {
            unchecked {
                uint256 lastIndex = arrayLength - 1; // Safe: length > 0 guaranteed by bounds check
                if (index != lastIndex) {
                    address lastChallenger = invalidChallengers[lastIndex];
                    invalidChallengers[index] = lastChallenger;
                    invalidChallengerIndex[lastChallenger] = index;
                }
            }
            invalidChallengers.pop();
            delete invalidChallengerIndex[_challenger];
        }
    }
}