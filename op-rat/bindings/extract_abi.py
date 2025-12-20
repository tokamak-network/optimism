#!/usr/bin/env python3
import json
import sys

# Read the forge artifact JSON
with open(sys.argv[1], 'r') as f:
    data = json.load(f)

# Extract and output just the ABI
with open(sys.argv[2], 'w') as f:
    json.dump(data['abi'], f, indent=2)

print(f"ABI extracted to {sys.argv[2]}")
