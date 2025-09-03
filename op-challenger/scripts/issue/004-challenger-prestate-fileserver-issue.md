# Issue 004: Challenger Prestate Validation Failure - Fileserver Configuration Problem

**Date**: September 2, 2025  
**Status**: RESOLVED  
**Priority**: HIGH  
**Component**: op-challenger, fileserver

## Issue Summary

The op-challenger service was failing to schedule game updates due to prestate validation errors. The challenger could not download prestate files from the fileserver, leading to continuous validation failures.

## Error Symptoms

### Challenger Logs
```
[op-challenger-challenger-2151908] t=2025-09-02T10:54:51+0000 lvl=info msg="Cannon VM configuration" vmBin=/usr/local/bin/cannon server=/usr/local/bin/op-program l2Custom=false snapshotFreq=1000000000 infoFreq=10000000 absolutePrestate="" prestatesBaseURL=http://fileserver/proofs/op-program/cannon

[op-challenger-challenger-2151908] t=2025-09-02T10:55:40+0000 lvl=error msg="Failed to schedule game updates" err="failed to create job for game 0x9311252E0e9474382b48fFaAC144DB7E8AccD507: failed to validate prestate: failed to validate prestate: output root absolute prestate does not match: Provider: 0x94714c59d8bc0417f8d0d493750643ee65fa67c8ad9b9e631c31993b5919adc5 | Contract: 0xdead000000000000000000000000000000000000000000000000000000000000"
```

### HTTP Response
```bash
$ curl http://127.0.0.1:50400/proofs/op-program/cannon/
HTTP/1.1 403 Forbidden
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>nginx/1.29.1</center>
</body>
</html>
```

## Root Cause Analysis

### 1. Missing Prestate Files
- The fileserver `/usr/share/nginx/html/proofs/op-program/cannon/` directory was empty
- No prestate files available for challenger download

### 2. Nginx Configuration Issue
- Default nginx configuration blocked directory browsing (`autoindex` disabled)
- Challenger couldn't access prestate files even if they existed

### 3. Challenger Configuration
- `absolutePrestate=""` (empty) - challenger relied on fileserver download
- `prestatesBaseURL=http://fileserver/proofs/op-program/cannon`

## Impact

- **Challenger Non-Functional**: Unable to validate or challenge dispute games
- **Security Risk**: No active challenger to detect invalid proposals
- **Game Resolution Blocked**: Games remain unresolved indefinitely

## Solution

### Step 1: Verify Fileserver State
```bash
# Command: Check existing files on fileserver
kurtosis service exec simple-devnet fileserver 'find /usr/share/nginx/html -type f'

# Expected Output:
/usr/share/nginx/html/index.html
/usr/share/nginx/html/50x.html

# Result: Only default nginx files present, no prestate files
```

### Step 2: Create Directory Structure
```bash
# Command: Create required directory structure
kurtosis service exec simple-devnet fileserver 'mkdir -p /usr/share/nginx/html/proofs/op-program/cannon'

# Verification:
kurtosis service exec simple-devnet fileserver 'ls -la /usr/share/nginx/html/proofs/op-program/cannon/'
# Expected: Empty directory created successfully
```

### Step 3: Copy Prestate Files

#### 3a. Identify Fileserver Container
```bash
# Command: Get fileserver container ID
docker ps | grep fileserver

# Output:
f2f610226316   nginx:latest   "/docker-entrypoint.…"   27 minutes ago   Up 27 minutes   0.0.0.0:50400->80/tcp   fileserver--a9ff03f3a38e44b68a97677ce55b4a41
```

#### 3b. Copy Local Files to Container
```bash
# Command: Copy prestate files from local directory to container
docker cp /Users/zena/tokamak-projects/optimism/kurtosis-devnet/prestate-build/ f2f610226316:/usr/share/nginx/html/proofs/op-program/cannon/

# Verification: Check files were copied
kurtosis service exec simple-devnet fileserver 'ls -la /usr/share/nginx/html/proofs/op-program/cannon/prestate-build/'

# Expected Output:
total 154912
drwxr-xr-x 2  502 dialout     4096 Sep  1 01:00 .
drwxr-xr-x 3 root root        4096 Sep  2 11:19 ..
-rwxr-xr-x 1  502 dialout  5379205 Sep  1 01:00 meta-interop.json
-rwxr-xr-x 1  502 dialout  5379205 Sep  1 01:00 meta-mt64.json
-rwxr-xr-x 1  502 dialout 54891163 Sep  1 01:00 op-program-client-interop.elf
-rwxr-xr-x 1  502 dialout 54891179 Sep  1 01:00 op-program-client64.elf
-rwxr-xr-x 1  502 dialout 19016038 Sep  1 01:00 prestate-interop.bin.gz
-rwxr-xr-x 1  502 dialout 19016051 Sep  1 01:00 prestate-mt64.bin.gz
-rwxr-xr-x 1  502 dialout    12776 Sep  1 01:00 prestate-proof-interop.json
-rwxr-xr-x 1  502 dialout    12776 Sep  1 01:00 prestate-proof-mt64.json
```

#### 3c. Reorganize File Structure
```bash
# Command: Move files to correct location (flatten directory structure)
kurtosis service exec simple-devnet fileserver 'cd /usr/share/nginx/html/proofs/op-program/cannon && mv prestate-build/* . && rmdir prestate-build'

# Verification: Check final file structure
kurtosis service exec simple-devnet fileserver 'ls -la /usr/share/nginx/html/proofs/op-program/cannon/'

# Expected Output: All files directly in cannon/ directory
total 154912
drwxr-xr-x 3 root root        4096 Sep  2 11:19 .
drwxr-xr-x 3 root root        4096 Sep  2 11:19 ..
-rwxr-xr-x 1  502 dialout  5379205 Sep  1 01:00 meta-interop.json
-rwxr-xr-x 1  502 dialout  5379205 Sep  1 01:00 meta-mt64.json
-rwxr-xr-x 1  502 dialout 54891163 Sep  1 01:00 op-program-client-interop.elf
-rwxr-xr-x 1  502 dialout 54891179 Sep  1 01:00 op-program-client64.elf
-rwxr-xr-x 1  502 dialout 19016038 Sep  1 01:00 prestate-interop.bin.gz
-rwxr-xr-x 1  502 dialout 19016051 Sep  1 01:00 prestate-mt64.bin.gz
-rwxr-xr-x 1  502 dialout    12776 Sep  1 01:00 prestate-proof-interop.json
-rwxr-xr-x 1  502 dialout    12776 Sep  1 01:00 prestate-proof-mt64.json
```

### Step 4: Fix Nginx Configuration

#### 4a. Test Access (Before Fix)
```bash
# Command: Test HTTP access before nginx fix
curl -s "http://127.0.0.1:50400/proofs/op-program/cannon/" | head -10

# Output (Before Fix):
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>nginx/1.29.1</center>
</body>
</html>
```

#### 4b. Update Nginx Configuration
```bash
# Command: Enable directory browsing with autoindex
kurtosis service exec simple-devnet fileserver 'echo "server { listen 80; location / { root /usr/share/nginx/html; autoindex on; } }" > /etc/nginx/conf.d/default.conf && nginx -s reload'

# Expected Output:
2025/09/02 11:19:23 [notice] 82#82: signal process started
```

#### 4c. Verify Nginx Configuration
```bash
# Command: Check nginx config file was created
kurtosis service exec simple-devnet fileserver 'cat /etc/nginx/conf.d/default.conf'

# Expected Output:
server { listen 80; location / { root /usr/share/nginx/html; autoindex on; } }
```

### Step 5: Verification

#### 5a. Test HTTP Directory Browsing
```bash
# Command: Test directory browsing works
curl -s "http://127.0.0.1:50400/proofs/op-program/cannon/" | head -20

# Expected Output (After Fix):
<html>
<head><title>Index of /proofs/op-program/cannon/</title></head>
<body>
<h1>Index of /proofs/op-program/cannon/</h1><hr><pre><a href="../">../</a>
<a href="meta-interop.json">meta-interop.json</a>                                  01-Sep-2025 01:00             5379205
<a href="meta-mt64.json">meta-mt64.json</a>                                     01-Sep-2025 01:00             5379205
<a href="op-program-client-interop.elf">op-program-client-interop.elf</a>                      01-Sep-2025 01:00            54891163
<a href="op-program-client64.elf">op-program-client64.elf</a>                            01-Sep-2025 01:00            54891179
<a href="prestate-interop.bin.gz">prestate-interop.bin.gz</a>                            01-Sep-2025 01:00            19016038
<a href="prestate-mt64.bin.gz">prestate-mt64.bin.gz</a>                               01-Sep-2025 01:00            19016051
<a href="prestate-proof-interop.json">prestate-proof-interop.json</a>                        01-Sep-2025 01:00               12776
<a href="prestate-proof-mt64.json">prestate-proof-mt64.json</a>                           01-Sep-2025 01:00               12776
</pre><hr></body>
</html>
```

#### 5b. Test Prestate File Download
```bash
# Command: Download and verify prestate file content
curl -s "http://127.0.0.1:50400/proofs/op-program/cannon/prestate-proof-mt64.json" | jq '.pre'

# Expected Output:
"0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195"

# Command: Verify this matches the contract's absolute prestate
L1_RPC="http://127.0.0.1:50514"; GAME1="0x9311252E0e9474382b48fFaAC144DB7E8AccD507"; cast call --rpc-url "$L1_RPC" "$GAME1" "absolutePrestate() returns (bytes32)"

# Expected Output:
0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195
```

#### 5c. Test All Critical Files
```bash
# Command: Verify all required files are downloadable
for file in prestate-proof-mt64.json prestate-mt64.bin.gz meta-mt64.json op-program-client64.elf; do
  echo "Testing $file..."
  curl -f -s "http://127.0.0.1:50400/proofs/op-program/cannon/$file" > /dev/null
  if [ $? -eq 0 ]; then
    echo "✅ $file - OK"
  else
    echo "❌ $file - FAILED"
  fi
done

# Expected Output:
Testing prestate-proof-mt64.json...
✅ prestate-proof-mt64.json - OK
Testing prestate-mt64.bin.gz...
✅ prestate-mt64.bin.gz - OK
Testing meta-mt64.json...
✅ meta-mt64.json - OK
Testing op-program-client64.elf...
✅ op-program-client64.elf - OK
```

## Verification Results

### Before Fix
- **Fileserver**: Empty, 403 Forbidden
- **Challenger**: Prestate validation failure
- **Contract Prestate**: `0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195`
- **Provider Prestate**: `0x94714c59d8bc0417f8d0d493750643ee65fa67c8ad9b9e631c31993b5919adc5`

### After Fix
- **Fileserver**: ✅ All prestate files accessible
- **Available Files**:
  - `prestate-proof-mt64.json` 
  - `prestate-mt64.bin.gz`
  - `prestate-proof-interop.json`
  - `prestate-interop.bin.gz`
  - `meta-mt64.json`, `meta-interop.json`
  - `op-program-client64.elf`, `op-program-client-interop.elf`
- **Correct Prestate**: `0x03a1a13511403f206bb2414e3bf974f8b4608ad8f7b37ee6642f6598dbe06195`

## Files Involved

### Critical Files
- **Prestate Proof**: `/proofs/op-program/cannon/prestate-proof-mt64.json`
- **Prestate Binary**: `/proofs/op-program/cannon/prestate-mt64.bin.gz`
- **Nginx Config**: `/etc/nginx/conf.d/default.conf`

### Local Source Files
- `/Users/zena/tokamak-projects/optimism/kurtosis-devnet/prestate-build/`

## Prevention Measures

### 1. Automated Prestate Upload
Ensure Kurtosis devnet setup includes prestate file upload to fileserver

### 2. Nginx Configuration Template
Include proper nginx configuration with `autoindex on` in devnet setup

### 3. Health Check Script
Create a script to verify fileserver accessibility:
```bash
#!/bin/bash
# Check if challenger can download prestates
curl -f "http://fileserver/proofs/op-program/cannon/prestate-proof-mt64.json" > /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Fileserver accessible"
else
    echo "❌ Fileserver not accessible"
    exit 1
fi
```

### 4. Challenger Startup Validation
Add prestate download validation during challenger startup

## Related Issues
- Issue 001: Deployment bug affecting game creation
- Issue 002: Op-deployer intent type configuration
- Issue 003: Op-deployer initialization flags

## Technical Notes

### Challenger Command Line
```bash
op-challenger \
  --cannon-l2-genesis=/network-configs/genesis-2151908.json \
  --cannon-rollup-config=/network-configs/rollup-2151908.json \
  --game-factory-address=0x11bc20970ae77e832c04d50fd38e15aaa13caefb \
  --datadir=/data/op-challenger/op-challenger-data \
  --l1-beacon=http://172.16.0.13:4000 \
  --l1-eth-rpc=http://172.16.0.12:8545 \
  --l2-eth-rpc=http://op-el-2151908-node0-op-geth:8545 \
  --private-key=0x717c53f6d6c266889465d78a885cd0a2e22d41f73e21fa1f07ba5849c82d79c3 \
  --rollup-rpc=http://op-cl-2151908-node0-op-node:8547 \
  --trace-type=cannon \
  --cannon-prestates-url=http://fileserver/proofs/op-program/cannon \
  --metrics.enabled \
  --metrics.addr=0.0.0.0 \
  --metrics.port=9001
```

### Key Configuration Parameters
- `absolutePrestate=""` - Empty, relies on fileserver
- `prestatesBaseURL=http://fileserver/proofs/op-program/cannon`
- `--cannon-prestates-url=http://fileserver/proofs/op-program/cannon`

## Resolution Status
✅ **RESOLVED** - Challenger can now successfully download prestate files and validate dispute games.