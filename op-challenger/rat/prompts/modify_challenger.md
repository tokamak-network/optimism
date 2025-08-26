# Randomized Attention Test (RAT) Challenger

RAT is designed to test challenger attention to verify whether challengers are monitoring diligently.

**For contract-related matters, refer to build_contracts.md.**

## Implementation Direction

1. Meet minimum staking requirements
- When the challenger runs, check the staking amount, and if it's less than the minimum staking amount, stake to meet or exceed the minimum staking amount.

2. game_solver.go
- File: op-challenger/game/fault/solver/game_solver.go

    2.1. Add attention correct evidence submission function
        - This function is executed when the root claim is determined to be correct.
        - Query attention information for the game ID from the RAT contract.
        - If the challenger address in the attention information matches the worker challenger's address:
            - Execute the correct evidence submission function.
            ```solidity
            function submitCorrectEvidence(
                address _gameAddress,
                bytes32 _proofLV,
                bytes32 _proofRV
            ) external
            ```
        - If the challenger address in the attention information doesn't match the worker challenger's address, exit without any action.

    2.2. Modify CalculateNextActions function
        - Execute attention based on attention conditions when challenger verifies true/false of root claim
        - If both the root claim and L2 block number are correct, call the 'attention correct evidence submission function'.
        - If the root claim is wrong -> It's already automatically executed for the challenger. However, if executed in RAT, it becomes duplicate execution... how should we handle this?
        - If the root claim is correct but the L2 block number is wrong ??? => How should we handle this?
