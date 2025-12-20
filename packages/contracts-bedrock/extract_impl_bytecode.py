#!/usr/bin/env python3
import json

with open('forge-artifacts/RAT.sol/RAT.json') as f:
    data = json.load(f)
    print(data['bytecode']['object'])
