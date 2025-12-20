
import json
import sys

try:
    with open('forge-artifacts/Proxy.sol/Proxy.json', 'r') as f:
        data = json.load(f)
        print(data['bytecode']['object'])
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
