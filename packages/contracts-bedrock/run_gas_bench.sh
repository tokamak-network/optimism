#!/bin/bash
export PATH="$PATH":/home/jazz/.foundry/bin
forge test --match-contract RAT_Gas_Benchmark --ffi -vv || echo "Forge test failed"
