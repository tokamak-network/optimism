# RAT Additional Solidity Unit Tests

## 📋 개요

현재 RAT 컨트랙트의 Solidity 단위 테스트를 분석한 결과, 추가할 수 있는 중요한 테스트 시나리오들이 많이 있습니다. 이 문서는 현재 누락된 테스트들을 제안합니다.

## 🔍 현재 테스트 커버리지 분석

### ✅ 이미 구현된 테스트들:
- **초기화 테스트**: 기본 초기화, 버전 확인
- **Staking 테스트**: 기본 staking, 최소 금액 이하 staking
- **Attention Test 테스트**: 기본 트리거, 권한 검증
- **Evidence 테스트**: 올바른 증거 제출, 잘못된 증거, 권한 검증
- **Refund 테스트**: Bond 반환
- **Admin 테스트**: 권한 검증

### ❌ 누락된 중요한 테스트들:

## 🚀 추가할 수 있는 Solidity 단위 테스트

### A. Edge Cases 및 Boundary Tests

#### 1. RAT_EdgeCases_Test

```solidity
/// @title RAT_EdgeCases_Test
/// @notice Tests edge cases and boundary conditions
contract RAT_EdgeCases_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);
    address public constant CHALLENGER_2 = address(0x3456);

    function setUp() public override {
        super.setUp();
        vm.deal(CHALLENGER_1, 10 ether);
        vm.deal(CHALLENGER_2, 10 ether);
    }

    /// @notice Tests staking with exact minimum amount
    function test_stake_exactMinimum_succeeds() public {
        uint256 exactMinimum = MINIMUM_STAKE_AMOUNT;

        vm.prank(CHALLENGER_1);
        rat.stake{value: exactMinimum}();

        ChallengerInfo memory info = rat.getChallengerInfo(CHALLENGER_1);
        assertEq(info.stakingAmount, exactMinimum);
        assertTrue(info.isValid);
    }

    /// @notice Tests staking with maximum uint256 value
    function test_stake_maxValue_succeeds() public {
        uint256 maxValue = type(uint256).max;
        vm.deal(CHALLENGER_1, maxValue);

        vm.prank(CHALLENGER_1);
        rat.stake{value: maxValue}();

        ChallengerInfo memory info = rat.getChallengerInfo(CHALLENGER_1);
        assertEq(info.stakingAmount, maxValue);
        assertTrue(info.isValid);
    }

    /// @notice Tests staking with zero value reverts
    function test_stake_zeroValue_reverts() public {
        vm.expectRevert("Must stake positive amount");
        vm.prank(CHALLENGER_1);
        rat.stake{value: 0}();
    }

    /// @notice Tests trigger attention test with no valid challengers
    function test_triggerAttentionTest_noValidChallengers_succeeds() public {
        // No challengers staked, only dummy address(0) in validChallengers
        address gameAddress = makeAddr("game");
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        // Should not revert, but should not create attention test
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        // Verify no attention test was created
        (bytes32 storedStateRoot, , , , ) = rat.attentionTests(gameAddress);
        assertEq(storedStateRoot, bytes32(0));
    }

    /// @notice Tests trigger attention test with only one valid challenger
    function test_triggerAttentionTest_singleChallenger_succeeds() public {
        // Stake one challenger
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        address gameAddress = makeAddr("game");
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        // Verify attention test was created for the single challenger
        (, , address selectedChallenger, , ) = rat.attentionTests(gameAddress);
        assertEq(selectedChallenger, CHALLENGER_1);
    }
}
```

#### 2. RAT_Probability_Test

```solidity
/// @title RAT_Probability_Test
/// @notice Tests RAT trigger probability functionality
contract RAT_Probability_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);

    function setUp() public override {
        super.setUp();
        vm.deal(CHALLENGER_1, 10 ether);

        // Stake challenger
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();
    }

    /// @notice Tests probability 0 (never trigger)
    function test_triggerAttentionTest_probabilityZero_neverTriggers() public {
        // Set probability to 0
        vm.prank(address(1)); // manager
        rat.setRatTriggerProbability(0);

        address gameAddress = makeAddr("game");
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        // Verify no attention test was created
        (bytes32 storedStateRoot, , , , ) = rat.attentionTests(gameAddress);
        assertEq(storedStateRoot, bytes32(0));
    }

    /// @notice Tests probability 100000 (always trigger)
    function test_triggerAttentionTest_probabilityMax_alwaysTriggers() public {
        // Set probability to maximum
        vm.prank(address(1)); // manager
        rat.setRatTriggerProbability(100000);

        address gameAddress = makeAddr("game");
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        // Verify attention test was created
        (bytes32 storedStateRoot, , , , ) = rat.attentionTests(gameAddress);
        assertEq(storedStateRoot, stateRoot);
    }

    /// @notice Tests setting invalid probability reverts
    function test_setRatTriggerProbability_invalidProbability_reverts() public {
        vm.expectRevert("Invalid probability");
        vm.prank(address(1)); // manager
        rat.setRatTriggerProbability(100001); // > MAX_PROBABILITY
    }

    /// @notice Tests setting probability by non-manager reverts
    function test_setRatTriggerProbability_notManager_reverts() public {
        vm.expectRevert(RAT.NotRatManager.selector);
        vm.prank(CHALLENGER_1); // not manager
        rat.setRatTriggerProbability(50000);
    }
}
```

### B. Challenger Management Tests

#### 3. RAT_ChallengerManagement_Test

```solidity
/// @title RAT_ChallengerManagement_Test
/// @notice Tests challenger validity management
contract RAT_ChallengerManagement_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);
    address public constant CHALLENGER_2 = address(0x3456);
    address public constant CHALLENGER_3 = address(0x4567);

    function setUp() public override {
        super.setUp();
        vm.deal(CHALLENGER_1, 10 ether);
        vm.deal(CHALLENGER_2, 10 ether);
        vm.deal(CHALLENGER_3, 10 ether);
    }

    /// @notice Tests challenger becomes invalid after bond slashing
    function test_challengerBecomesInvalid_afterBondSlashing() public {
        // Stake challenger with exact bond amount
        vm.prank(CHALLENGER_1);
        rat.stake{value: SLASH_BOND_AMOUNT}();

        // Verify challenger is valid
        ChallengerInfo memory info = rat.getChallengerInfo(CHALLENGER_1);
        assertTrue(info.isValid);

        // Trigger attention test to slash bond
        address gameAddress = makeAddr("game");
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        // Verify challenger becomes invalid
        info = rat.getChallengerInfo(CHALLENGER_1);
        assertFalse(info.isValid);
        assertEq(info.stakingAmount, 0);
        assertEq(info.totalSlashedAmount, SLASH_BOND_AMOUNT);
    }

    /// @notice Tests challenger becomes valid again after additional staking
    function test_challengerBecomesValid_afterAdditionalStaking() public {
        // Stake challenger with exact bond amount
        vm.prank(CHALLENGER_1);
        rat.stake{value: SLASH_BOND_AMOUNT}();

        // Trigger attention test to slash bond
        address gameAddress = makeAddr("game");
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        // Verify challenger is invalid
        ChallengerInfo memory info = rat.getChallengerInfo(CHALLENGER_1);
        assertFalse(info.isValid);

        // Stake additional amount to become valid again
        vm.prank(CHALLENGER_1);
        rat.stake{value: SLASH_BOND_AMOUNT}();

        // Verify challenger becomes valid again
        info = rat.getChallengerInfo(CHALLENGER_1);
        assertTrue(info.isValid);
        assertEq(info.stakingAmount, SLASH_BOND_AMOUNT);
    }

    /// @notice Tests multiple challengers and selection
    function test_multipleChallengers_selection() public {
        // Stake multiple challengers
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        vm.prank(CHALLENGER_2);
        rat.stake{value: 2.5 ether}();

        vm.prank(CHALLENGER_3);
        rat.stake{value: 2.5 ether}();

        // Verify all challengers are valid
        assertEq(rat.getValidChallengerCount(), 4); // 3 challengers + dummy address(0)

        // Trigger attention test multiple times and verify selection
        address gameAddress1 = makeAddr("game1");
        address gameAddress2 = makeAddr("game2");
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress1, stateRoot, blockHash);

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress2, stateRoot, blockHash);

        // Verify both attention tests were created
        (, , address selectedChallenger1, , ) = rat.attentionTests(gameAddress1);
        (, , address selectedChallenger2, , ) = rat.attentionTests(gameAddress2);

        assertTrue(selectedChallenger1 != address(0));
        assertTrue(selectedChallenger2 != address(0));
    }
}
```

### C. Evidence Submission Edge Cases

#### 4. RAT_EvidenceEdgeCases_Test

```solidity
/// @title RAT_EvidenceEdgeCases_Test
/// @notice Tests evidence submission edge cases
contract RAT_EvidenceEdgeCases_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);
    address public constant CHALLENGER_2 = address(0x3456);

    GameId public gameId;
    bytes32 public stateRoot;
    bytes32 public proofLV;
    bytes32 public proofRV;
    address public gameAddress;

    function setUp() public override {
        super.setUp();
        vm.deal(CHALLENGER_1, 10 ether);
        vm.deal(CHALLENGER_2, 10 ether);

        // Stake challenger
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        // Setup test data
        proofLV = keccak256("left_value");
        proofRV = keccak256("right_value");
        stateRoot = keccak256(abi.encodePacked(proofLV, proofRV));

        gameId = LibGameId.pack(GameTypes.CANNON, Timestamp.wrap(uint64(block.timestamp)), mockFaultDisputeGame);
        (, , gameAddress) = LibGameId.unpack(gameId);
    }

    /// @notice Tests evidence submission after deadline expires
    function test_submitCorrectEvidence_afterDeadline_reverts() public {
        // Trigger attention test
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));

        // Fast forward past deadline
        vm.roll(block.number + EVIDENCE_SUBMISSION_PERIOD + 1);

        // Try to submit evidence
        vm.expectRevert(RAT.EvidenceSubmissionExpired.selector);
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(gameAddress, proofLV, proofRV);
    }

    /// @notice Tests evidence submission at exact deadline
    function test_submitCorrectEvidence_atDeadline_succeeds() public {
        // Trigger attention test
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));

        // Fast forward to exact deadline
        vm.roll(block.number + EVIDENCE_SUBMISSION_PERIOD);

        // Submit evidence should succeed
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(gameAddress, proofLV, proofRV);

        // Verify evidence was submitted
        (, , , , bool evidenceSubmitted) = rat.attentionTests(gameAddress);
        assertTrue(evidenceSubmitted);
    }

    /// @notice Tests evidence submission with empty proofs
    function test_submitCorrectEvidence_emptyProofs_reverts() public {
        // Trigger attention test
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));

        // Try to submit with empty proofs
        vm.expectRevert(RAT.ProofVerificationFailed.selector);
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(gameAddress, bytes32(0), bytes32(0));
    }

    /// @notice Tests evidence submission with same proof values
    function test_submitCorrectEvidence_sameProofValues_succeeds() public {
        // Use same value for both proofs
        bytes32 sameProof = keccak256("same_value");
        bytes32 sameStateRoot = keccak256(abi.encodePacked(sameProof, sameProof));

        // Trigger attention test with same state root
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, sameStateRoot, blockhash(block.number - 1));

        // Submit evidence with same proofs
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(gameAddress, sameProof, sameProof);

        // Verify evidence was submitted
        (, , , , bool evidenceSubmitted) = rat.attentionTests(gameAddress);
        assertTrue(evidenceSubmitted);
    }

    /// @notice Tests evidence submission with maximum uint256 values
    function test_submitCorrectEvidence_maxValues_succeeds() public {
        // Use maximum uint256 values
        bytes32 maxProof = bytes32(type(uint256).max);
        bytes32 maxStateRoot = keccak256(abi.encodePacked(maxProof, maxProof));

        // Trigger attention test
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, maxStateRoot, blockhash(block.number - 1));

        // Submit evidence
        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(gameAddress, maxProof, maxProof);

        // Verify evidence was submitted
        (, , , , bool evidenceSubmitted) = rat.attentionTests(gameAddress);
        assertTrue(evidenceSubmitted);
    }
}
```

### D. Admin Function Tests

#### 5. RAT_AdminAdvanced_Test

```solidity
/// @title RAT_AdminAdvanced_Test
/// @notice Tests advanced admin functionality
contract RAT_AdminAdvanced_Test is RAT_TestInit {
    /// @notice Tests setting bond amount to maximum uint96
    function test_setPerTestBondAmount_maxUint96_succeeds() public {
        uint256 maxUint96 = type(uint96).max;

        vm.prank(address(1)); // proxy admin owner
        rat.setPerTestBondAmount(maxUint96);

        assertEq(rat.perTestBondAmount(), maxUint96);
    }

    /// @notice Tests setting bond amount exceeding uint96 reverts
    function test_setPerTestBondAmount_exceedsUint96_reverts() public {
        uint256 exceedsUint96 = type(uint96).max + 1;

        vm.expectRevert("Bond amount exceeds uint96 maximum");
        vm.prank(address(1)); // proxy admin owner
        rat.setPerTestBondAmount(exceedsUint96);
    }

    /// @notice Tests setting bond amount exceeding minimum staking balance reverts
    function test_setPerTestBondAmount_exceedsMinimumStaking_reverts() public {
        uint256 exceedsMinimum = MINIMUM_STAKE_AMOUNT + 1;

        vm.expectRevert("Bond amount cannot exceed minimum staking balance");
        vm.prank(address(1)); // proxy admin owner
        rat.setPerTestBondAmount(exceedsMinimum);
    }

    /// @notice Tests setting evidence submission period to maximum
    function test_setEvidenceSubmissionPeriod_max_succeeds() public {
        uint256 maxPeriod = 50400;

        vm.prank(address(1)); // proxy admin owner
        rat.setEvidenceSubmissionPeriod(maxPeriod);

        assertEq(rat.evidenceSubmissionPeriod(), maxPeriod);
    }

    /// @notice Tests setting evidence submission period exceeding maximum reverts
    function test_setEvidenceSubmissionPeriod_exceedsMax_reverts() public {
        uint256 exceedsMax = 50401;

        vm.expectRevert("Period too long");
        vm.prank(address(1)); // proxy admin owner
        rat.setEvidenceSubmissionPeriod(exceedsMax);
    }

    /// @notice Tests setting minimum staking balance to maximum
    function test_setMinimumStakingBalance_max_succeeds() public {
        uint256 maxBalance = 1000 ether;

        vm.prank(address(1)); // proxy admin owner
        rat.setMinimumStakingBalance(maxBalance);

        assertEq(rat.minimumStakingBalance(), maxBalance);
    }

    /// @notice Tests setting minimum staking balance exceeding maximum reverts
    function test_setMinimumStakingBalance_exceedsMax_reverts() public {
        uint256 exceedsMax = 1000 ether + 1;

        vm.expectRevert("Balance too large");
        vm.prank(address(1)); // proxy admin owner
        rat.setMinimumStakingBalance(exceedsMax);
    }

    /// @notice Tests setting zero values revert
    function test_setParameters_zeroValues_revert() public {
        vm.expectRevert("Bond amount must be positive");
        vm.prank(address(1));
        rat.setPerTestBondAmount(0);

        vm.expectRevert("Period must be positive");
        vm.prank(address(1));
        rat.setEvidenceSubmissionPeriod(0);

        vm.expectRevert("Balance must be positive");
        vm.prank(address(1));
        rat.setMinimumStakingBalance(0);
    }
}
```

### E. Reentrancy and Security Tests

#### 6. RAT_Security_Test

```solidity
/// @title RAT_Security_Test
/// @notice Tests security aspects including reentrancy
contract RAT_Security_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);

    function setUp() public override {
        super.setUp();
        vm.deal(CHALLENGER_1, 10 ether);
    }

    /// @notice Tests reentrancy protection on stake function
    function test_stake_reentrancyProtection() public {
        // Create a malicious contract that tries to reenter
        MaliciousContract malicious = new MaliciousContract(address(rat));
        vm.deal(address(malicious), 10 ether);

        // Try to reenter during stake
        vm.expectRevert("ReentrancyGuard: reentrant call");
        malicious.attemptReentrancy();
    }

    /// @notice Tests that challenger info is properly isolated
    function test_challengerInfo_isolation() public {
        // Stake from challenger 1
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        // Verify challenger 1 info
        ChallengerInfo memory info1 = rat.getChallengerInfo(CHALLENGER_1);
        assertEq(info1.stakingAmount, 2.5 ether);
        assertTrue(info1.isValid);

        // Verify challenger 2 info is empty
        ChallengerInfo memory info2 = rat.getChallengerInfo(address(0x9999));
        assertEq(info2.stakingAmount, 0);
        assertFalse(info2.isValid);
    }

    /// @notice Tests that attention tests are properly isolated
    function test_attentionTest_isolation() public {
        address gameAddress1 = makeAddr("game1");
        address gameAddress2 = makeAddr("game2");
        bytes32 stateRoot1 = keccak256("state1");
        bytes32 stateRoot2 = keccak256("state2");

        // Stake challenger
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        // Trigger attention test for game 1
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress1, stateRoot1, blockhash(block.number - 1));

        // Verify game 1 has attention test
        (bytes32 storedStateRoot1, , , , ) = rat.attentionTests(gameAddress1);
        assertEq(storedStateRoot1, stateRoot1);

        // Verify game 2 has no attention test
        (bytes32 storedStateRoot2, , , , ) = rat.attentionTests(gameAddress2);
        assertEq(storedStateRoot2, bytes32(0));
    }
}

/// @notice Malicious contract for reentrancy testing
contract MaliciousContract {
    RAT public rat;
    bool public reentered = false;

    constructor(address _rat) {
        rat = RAT(_rat);
    }

    function attemptReentrancy() external payable {
        rat.stake{value: 1 ether}();
    }

    receive() external payable {
        if (!reentered) {
            reentered = true;
            rat.stake{value: 1 ether}();
        }
    }
}
```

### F. Gas Optimization Tests

#### 7. RAT_GasOptimization_Test

```solidity
/// @title RAT_GasOptimization_Test
/// @notice Tests gas optimization aspects
contract RAT_GasOptimization_Test is RAT_TestInit {
    address public constant CHALLENGER_1 = address(0x2345);

    function setUp() public override {
        super.setUp();
        vm.deal(CHALLENGER_1, 10 ether);
    }

    /// @notice Tests gas usage for staking
    function test_stake_gasUsage() public {
        uint256 gasStart = gasleft();

        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        uint256 gasUsed = gasStart - gasleft();

        // Verify gas usage is reasonable (adjust threshold as needed)
        assertLt(gasUsed, 100000, "Stake function uses too much gas");
    }

    /// @notice Tests gas usage for attention test trigger
    function test_triggerAttentionTest_gasUsage() public {
        // Stake challenger first
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        address gameAddress = makeAddr("game");
        bytes32 stateRoot = keccak256("test_state_root");
        bytes32 blockHash = blockhash(block.number - 1);

        uint256 gasStart = gasleft();

        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockHash);

        uint256 gasUsed = gasStart - gasleft();

        // Verify gas usage is reasonable
        assertLt(gasUsed, 150000, "Trigger attention test uses too much gas");
    }

    /// @notice Tests gas usage for evidence submission
    function test_submitCorrectEvidence_gasUsage() public {
        // Setup
        vm.prank(CHALLENGER_1);
        rat.stake{value: 2.5 ether}();

        bytes32 proofLV = keccak256("left_value");
        bytes32 proofRV = keccak256("right_value");
        bytes32 stateRoot = keccak256(abi.encodePacked(proofLV, proofRV));

        address gameAddress = makeAddr("game");
        vm.prank(mockDisputeGameFactory);
        rat.triggerAttentionTest(gameAddress, stateRoot, blockhash(block.number - 1));

        uint256 gasStart = gasleft();

        vm.prank(CHALLENGER_1);
        rat.submitCorrectEvidence(gameAddress, proofLV, proofRV);

        uint256 gasUsed = gasStart - gasleft();

        // Verify gas usage is reasonable
        assertLt(gasUsed, 100000, "Submit evidence uses too much gas");
    }
}
```

## 📊 테스트 실행 방법

### 1. 개별 테스트 실행

```bash
# Edge cases 테스트
forge test --match-contract "RAT_EdgeCases_Test" -vv

# Probability 테스트
forge test --match-contract "RAT_Probability_Test" -vv

# Challenger management 테스트
forge test --match-contract "RAT_ChallengerManagement_Test" -vv

# Evidence edge cases 테스트
forge test --match-contract "RAT_EvidenceEdgeCases_Test" -vv

# Admin advanced 테스트
forge test --match-contract "RAT_AdminAdvanced_Test" -vv

# Security 테스트
forge test --match-contract "RAT_Security_Test" -vv

# Gas optimization 테스트
forge test --match-contract "RAT_GasOptimization_Test" -vv
```

### 2. 전체 RAT 테스트 실행

```bash
# 모든 RAT 테스트 실행
forge test --match-path "test/L1/RAT.t.sol" -vv

# 특정 패턴 테스트
forge test --match-test "*RAT*" -vv
```

## 🎯 테스트 우선순위

### Phase 1: 핵심 Edge Cases
1. **RAT_EdgeCases_Test** - 기본 경계 조건 및 예외 상황
2. **RAT_Probability_Test** - 확률 기반 트리거 로직
3. **RAT_ChallengerManagement_Test** - Challenger 유효성 관리

### Phase 2: 고급 기능
4. **RAT_EvidenceEdgeCases_Test** - Evidence 제출 경계 조건
5. **RAT_AdminAdvanced_Test** - Admin 함수 고급 테스트

### Phase 3: 보안 및 최적화
6. **RAT_Security_Test** - 보안 및 재진입 방어
7. **RAT_GasOptimization_Test** - 가스 사용량 최적화

## 🔗 관련 문서

- [RAT Testing Implementation Plan](./rat-testing-implementation-plan.md) - 통합 및 E2E 테스트 시나리오
- [Proposer State Root Challenge Tests](../proposer/proposer-state-root-challenge-tests.md) - 기본 fault proof 테스트
- [RAT 배포 구현](./rat-deployment-implementation.md) - RAT 컨트랙트 배포 가이드

---

**📝 작성일**: 2024년 12월
**🔄 최종 업데이트**: RAT 컨트랙트 분석 완료 후
**👥 작성자**: Optimism 개발팀
