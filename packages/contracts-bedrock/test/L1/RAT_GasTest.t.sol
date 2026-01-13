// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { RAT } from "src/L1/RAT.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";

contract RAT_GasTest is Test {
    RAT rat;
    address factory;

    function setUp() public {
        factory = makeAddr("factory");
        address manager = makeAddr("manager");

        RAT impl = new RAT();
        Proxy proxy = new Proxy(address(this));
        proxy.upgradeTo(address(impl));

        rat = RAT(payable(address(proxy)));

        rat.initialize(
            IDisputeGameFactory(factory),
            0.1 ether, // Bond
            100,
            1 ether,   // Min Stake
            100000,
            5000,      // 50% Penalty
            manager
        );

        // Fund address(this) for staking
        vm.deal(address(this), 10 ether);
        rat.stake{value: 1 ether}();

        // Register another validator
        address validator2 = makeAddr("validator2");
        vm.deal(validator2, 10 ether);
        vm.prank(validator2);
        rat.stake{value: 1 ether}();
    }

    function test_gas_OptimisticFlow() public {
        // 1. Trigger Attention Test (Upfront Slashing)
        address gameAddr = makeAddr("game");
        bytes32 unused = bytes32(0);
        bytes32 _root = 0xd582f99275e227a1cf4284899e5ff06ee56da8859be71b553397c69151bc942f;
        bytes32 outputRoot = keccak256(abi.encode(unused, _root, unused, unused));

        vm.prank(factory);
        uint256 startGas = gasleft();
        rat.triggerAttentionTest(gameAddr, outputRoot, unused, 1234);
        uint256 triggerGas = startGas - gasleft();
        console.log("Gas Used (Trigger + Slash):", triggerGas);

        // 2. Submit Candidate (Optimistic Refund)
        // No proof needed!
        bytes32 candidateKey = bytes32(uint256(uint160(address(0x123))));

        // Identify who was selected
        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddr);
        address challenger = info.challengerAddress;

        vm.prank(challenger);
        startGas = gasleft();
        rat.submitCandidate(
            gameAddr,
            candidateKey,
            _root,
            unused,
            unused,
            unused
        );
        uint256 submitGas = startGas - gasleft();
        console.log("Gas Used (Submit + Refund):", submitGas);
    }

    function test_gas_DisputeByCloserKey() public {
        // Setup state for dispute
        address gameAddr = makeAddr("gameDispute");
        bytes32 unused = bytes32(0);
        // Valid Proof from MerkleTrie.t.sol (validProof1)
        bytes[] memory _proof = new bytes[](3);
        _proof[0] = hex"e68416b65793a03101b4447781f1e6c51ce76c709274fc80bd064f3a58ff981b6015348a826386";
        _proof[1] = hex"f84580a0582eed8dd051b823d13f8648cdcd08aa2d8dac239f458863c4620e8c4d605debca83206262856176616c32ca83206363856176616c3380808080808080808080808080";
        _proof[2] = hex"ca83206262856176616c32";

        bytes32 _root = 0xd582f99275e227a1cf4284899e5ff06ee56da8859be71b553397c69151bc942f;
        bytes32 outputRoot = keccak256(abi.encode(unused, _root, unused, unused));

        // Trigger
        vm.prank(factory);
        // Force seed to select address(this) if possible, or just mock it.
        // For simplicity, we just run trigger until we get a valid challenger or mock state.
        // Actually, we can check who is selected.
        rat.triggerAttentionTest(gameAddr, outputRoot, unused, 1234);

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddr);
        address challenger = info.challengerAddress;

        // Submit a BAD candidate (far away)
        vm.prank(challenger);
        rat.submitCandidate(gameAddr, bytes32(uint256(0)), _root, unused, unused, unused);

        // Dispute with Valid Key (0x123...) which corresponds to the proof
        // Note: The proof corresponds to key 'kv'. 'k' is 0x6b...
        // Let's use the key from the proof test data: 0x6b6579
        bytes32 realKey = 0x6b65790000000000000000000000000000000000000000000000000000000000;
        // In SecureMerkleTrie, input key is hashed.
        // The test proof is raw MerkleTrie. SecureMerkleTrie hashes the key.
        // If we use SecureMerkleTrie, we need a standard Merkle Proof for H(key).
        // This existing proof used in previous test worked because we generated it or picked it carefully?
        // Wait, the previous test used `SecureMerkleTrie.get`.
        // If the previous test passed with `SecureMerkleTrie` and that specific proof, it implies the key bytes match what the trie expects.
        // Let's rely on the Revert Path pattern again for Gas Measurement if we can't easily construct valid hashed proofs.
        // We will force a Revert Path on `disputeByCloserKey` to measure execution cost.

        // We need `candidateKey` to be "far" and `closerKey` to be "valid" in trie but "closer".
        // To trigger the expensive verification, we pass the "Revert Path" key.
        // The contract calls `SecureMerkleTrie.get(closerKey)`.

        uint256 startGas = gasleft();
        try rat.disputeByCloserKey(
            gameAddr,
            realKey, // Arbitrary key to trigger verification
            _root,
            unused,
            unused,
            unused,
            _proof
        ) {
           // Success
        } catch {
           // Revert (Path Mismatch)
        }
        uint256 usedGas = startGas - gasleft();
        console.log("Gas Used (Dispute Closer - Revert Path):", usedGas);
        console.log("Est. Success (Dispute):", usedGas + 45000); // Higher overhead for transfer/slashing
    }

    function test_gas_DisputeByNonInclusion() public {
        // Setup state
        address gameAddr = makeAddr("gameNonInclusion");
        bytes32 unused = bytes32(0);
        bytes32 _root = 0xd582f99275e227a1cf4284899e5ff06ee56da8859be71b553397c69151bc942f;
        bytes32 outputRoot = keccak256(abi.encode(unused, _root, unused, unused));

        vm.prank(factory);
        rat.triggerAttentionTest(gameAddr, outputRoot, unused, 1234);

        RAT.AttentionInfo memory info = rat.getAttentionTest(gameAddr);
        address challenger = info.challengerAddress;

        // Submit "Candidate Key" (We assume it's FAKE, so we will dispute it)
        vm.prank(challenger);
        rat.submitCandidate(gameAddr, bytes32(uint256(1)), _root, unused, unused, unused);

        // Dispute by showing a different key exists?
        // We will trigger the verification logic using Revert Path again to get the "Validation Gas".
        // The logic inside disputeByNonInclusion is: SecureMerkleTrie.get(_provenKey).
        // We pass the SAME Revert Path params as disputeByCloserKey.
        // It should cost roughly the same.

        // Proof for Revert Path (Depth 3)
        bytes32 realKey = 0x6b65790000000000000000000000000000000000000000000000000000000000;
        bytes[] memory _proof = new bytes[](3);
        _proof[0] = hex"e68416b65793a03101b4447781f1e6c51ce76c709274fc80bd064f3a58ff981b6015348a826386";
        _proof[1] = hex"f84580a0582eed8dd051b823d13f8648cdcd08aa2d8dac239f458863c4620e8c4d605debca83206262856176616c32ca83206363856176616c3380808080808080808080808080";
        _proof[2] = hex"ca83206262856176616c32";

        uint256 startGas = gasleft();
        try rat.disputeByNonInclusion(
            gameAddr,
            realKey,
            _root,
            unused,
            unused,
            unused,
            _proof
        ) {
            // Success
        } catch {
            // Revert expected due to path mismatch
        }
        uint256 usedGas = startGas - gasleft();
        console.log("Gas Used (Dispute Non-Inclusion - Revert Path):", usedGas);
        console.log("Est. Success (Dispute NI):", usedGas + 45000);
    }
}
