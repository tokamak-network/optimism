// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { RAT } from "src/L1/RAT.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";

// Mock RAT to avoid needing real Merkle Proofs for Unit Test
contract RATMock is RAT {
    mapping(bytes32 => bool) public validKeys; // Stores keccak256(keyBlob) => exists

    function setKeyExists(bytes memory keyBlob, bool exists) external {
        validKeys[keccak256(keyBlob)] = exists;
    }

    // Override internal helper for Existence Check
    function _verifyExistence(bytes memory _keyBlob, bytes[] calldata, bytes32) internal view override {
        if (!validKeys[keccak256(_keyBlob)]) {
            revert("MockTrie: Key not found");
        }
    }

    // Override internal helper for Non-Inclusion Check
    function _verifyNonInclusion(address _keyAddr, bytes[] calldata, bytes32) internal view override {
         // Check if key exists in our 'validKeys' map
         bytes32 keyHash = keccak256(abi.encodePacked(_keyAddr));
         if (validKeys[keyHash]) {
             revert KeyExists();
         }
         // If not found, Non-Inclusion is valid.
    }
}

contract RAT_Paper_Verification is Test {
    RATMock rat;
    address factory;
    address validatorA; // Watchdog
    address validatorB; // Victim / Submitter

    function setUp() public {
        factory = makeAddr("factory");
        address manager = makeAddr("manager");
        validatorA = makeAddr("validatorA");
        validatorB = makeAddr("validatorB");

        RATMock impl = new RATMock();
        Proxy proxy = new Proxy(address(this));
        proxy.upgradeTo(address(impl));

        rat = RATMock(payable(address(proxy)));

        rat.initialize(
            IDisputeGameFactory(factory),
            0.1 ether, // Bond
            100, // Submission Period
            1 ether,   // Min Stake
            100000, // Trigger Prob (100% for test)
            5000,      // 50% Penalty
            manager
        );

        // Stake Validators
        vm.deal(validatorA, 10 ether);
        vm.prank(validatorA);
        rat.stake{value: 1 ether}();

        vm.deal(validatorB, 10 ether);
        vm.prank(validatorB);
        rat.stake{value: 1 ether}();
    }

    function _distance(bytes32 a, bytes32 b) internal pure returns (uint256) {
        uint256 x = uint256(a);
        uint256 y = uint256(b);
        return x >= y ? x - y : y - x;
    }

    // ==========================================
    // 1. Happy Path (Optimistic Refund)
    // ==========================================
    function test_HappyPath_OptimisticRefund() public {
        vm.roll(100);

        // 1. Trigger
        address gameAddr = makeAddr("gameHappy");
        bytes32 outputRoot = keccak256(abi.encode(bytes32(0), bytes32(0), bytes32(0), bytes32(0)));

        // Listen for events to verify deduction/refund
        vm.prank(factory);
        rat.triggerAttentionTest(gameAddr, outputRoot, bytes32(0), 1234);

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddr);
        address selected = info.challengerAddress;

        // Verify Upfront Deduction
        RAT.ChallengerInfo memory challenger = rat.getChallengerInfo(selected);
        assertEq(challenger.stakingAmount, 0.9 ether, "Bond not deducted upfront");

        // 2. Submit (Optimistic)
        bytes32 candidate = bytes32(uint256(0x1234));
        vm.prank(selected);
        rat.submitCandidate(gameAddr, candidate, bytes32(0), bytes32(0), bytes32(0), bytes32(0));

        // Verify Refund
        challenger = rat.getChallengerInfo(selected);
        assertEq(challenger.stakingAmount, 1.0 ether, "Bond not refunded on submission");

        info = rat.getAttentionTest(gameAddr);
        assertEq(uint256(info.status), 1, "Status should be SUBMITTED");

        console.log("Happy Path Verified: Upfront Slash -> Submit -> Refund");
    }

    // ==========================================
    // 2. Dispute: Suboptimal Key Liar
    // ==========================================
    function test_Dispute_SuboptimalKeyLiar() public {
        // Setup Keys and Seed with Block Scoping
        bytes32 seed;
        bytes32 keyClose;
        bytes32 keyFar;
        {
            vm.roll(200);
            vm.warp(2000);
            seed = keccak256(abi.encodePacked(blockhash(199), uint256(2000)));

            // Find distinct keys (Search logic)
             uint256 minDist = type(uint256).max;
            uint256 maxDist = 0;
            for(uint256 i=0; i<50; i++) {
                address r = address(uint160(uint256(keccak256(abi.encode(i, seed)))));
                bytes32 k = bytes32(uint256(uint160(r)));
                uint256 d = _distance(k, seed);
                if(d < minDist) { minDist=d; keyClose=k; }
                if(d > maxDist) { maxDist=d; keyFar=k; }
            }
            // Register in Mock
            rat.setKeyExists(abi.encodePacked(address(uint160(uint256(keyClose)))), true);
            rat.setKeyExists(abi.encodePacked(address(uint160(uint256(keyFar)))), true);
        }

        // Trigger
        address gameAddr = makeAddr("gameSuboptimal");
        bytes32 outputRoot = keccak256(abi.encode(bytes32(0), bytes32(0), bytes32(0), bytes32(0)));

        vm.prank(factory);
        rat.triggerAttentionTest(gameAddr, outputRoot, bytes32(0), 1234);

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddr);
        address victim = info.challengerAddress;
        address watchdog = victim == validatorA ? validatorB : validatorA;

        // Victim submits Suboptimal (Far)
        vm.prank(victim);
        rat.submitCandidate(gameAddr, keyFar, bytes32(0), bytes32(0), bytes32(0), bytes32(0));

        // Watchdog disputes with Closer
        vm.prank(watchdog);
        rat.disputeByCloserKey(gameAddr, keyClose, bytes32(0), bytes32(0), bytes32(0), bytes32(0), new bytes[](0));

        // Verify Slash (1.0 -> 0.9)
        RAT.ChallengerInfo memory vInfo = rat.getChallengerInfo(victim);
        assertEq(vInfo.stakingAmount, 0.9 ether, "Victim not slashed");

        // Disputer Reward
        assertEq(watchdog.balance, 9.1 ether, "Disputer not rewarded correctly");

        console.log("Scenario 'Suboptimal Key Liar' Verified");
    }

    // ==========================================
    // 3. Dispute: Fake Key Liar
    // ==========================================
    function test_Dispute_FakeKeyLiar() public {
        bytes32 fakeKey = bytes32(uint256(0xDEADBEEF));

        // Trigger
        address gameAddr = makeAddr("gameFake");
        bytes32 outputRoot = keccak256(abi.encode(bytes32(0), bytes32(0), bytes32(0), bytes32(0)));

        vm.prank(factory);
        rat.triggerAttentionTest(gameAddr, outputRoot, bytes32(0), 1234);

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddr);
        address victim = info.challengerAddress;
        address watchdog = victim == validatorA ? validatorB : validatorA;

        // Victim submits Fake Key
        // Optimistic submission accepts it (no verification)
        vm.prank(victim);
        rat.submitCandidate(gameAddr, fakeKey, bytes32(0), bytes32(0), bytes32(0), bytes32(0));

        // Watchdog Disputes Non-Inclusion
        // Providing the fakeKey as the target to disprove
        vm.prank(watchdog);
        rat.disputeByNonInclusion(gameAddr, fakeKey, bytes32(0), bytes32(0), bytes32(0), bytes32(0), new bytes[](0));

        // Verify Slash
        RAT.ChallengerInfo memory vInfo = rat.getChallengerInfo(victim);
        assertEq(vInfo.stakingAmount, 0.9 ether, "Victim not slashed for Fake Key");

        assertEq(watchdog.balance, 9.1 ether, "Disputer not rewarded correctly");

        console.log("Scenario 'Fake Key Liar' Verified");
    }
}
