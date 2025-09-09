# RAT Test Results Summary (Run 3)

## 📊 Test Execution Overview

This document provides a comprehensive summary of the actual test execution results for the RAT (Randomized Attention Test) contract. All tests were successfully executed using the Foundry testing framework.

### How to run (exact commands)

```bash
cd /optimism/packages/contracts-bedrock
forge test --match-contract RAT_Simple_Test --gas-report -vv

# Individual cases
forge test --match-test test_stake_gas_measurement -vv
RAT stake() gas used: 67177

forge test --match-test test_stake_valid_challenger_gas_measurement -vv
RAT stake() valid challenger gas used: 114711

forge test --match-test test_submitCorrectEvidence_gas_measurement -vv
RAT triggerAttentionTest() gas used: 96476
RAT submitCorrectEvidence() gas used: 7526

forge test --match-test test_triggerAttentionTest_gas_measurement -vv
RAT triggerAttentionTest() gas used (100% probability): 98375


forge test --match-test test_triggerAttentionTest_low_probability_gas_measurement -vv
RAT triggerAttentionTest() gas used (1% probability): 3904

forge test --match-test test_triggerAttentionTest_zero_probability_gas_measurement -vv
RAT triggerAttentionTest() gas used (0% probability): 3728

forge test --match-test test_resolveClaim_gas_measurement -vv
RAT resolveClaim() gas used: 4857

```
