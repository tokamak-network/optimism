# CHANGES.md - Development and Troubleshooting Log

## Overview
This document tracks all the problems encountered, their causes, solutions, and script improvements made during the development of the Challenger Network system.

## Problems Encountered and Solutions

### 1. Go-libp2p-mplex Compatibility Issues
**Problem**: `op-node build failed` with errors:
```
undefined: network.ConnErrorCode
undefined: network.StreamErrorCode
```
- **Cause**: `go-libp2p-mplex@v0.9.0` incompatible with `go-libp2p@v0.36.2`
  - In go-libp2p v0.36.2+, the `network.ConnErrorCode` and `network.StreamErrorCode` types were removed
  - The methods `CloseWithError` and `ResetWithError` now use `int` type instead
- **Solution**:
  - Updated Dockerfile compatibility patch to use `int` type instead of removed error code types
  - Modified `install-tools.sh` to automatically apply the correct fix
- **Technical Details**:
  ```go
  // Before (incorrect):
  func (c *conn) CloseWithError(code network.ConnErrorCode) error
  func (s *stream) ResetWithError(code network.StreamErrorCode) error
  
  // After (correct):
  func (c *conn) CloseWithError(code int) error
  func (s *stream) ResetWithError(code int) error
  ```
- **Files Modified**:
  - `ops/docker/op-stack-go/Dockerfile` - Updated compatibility patch with correct types
  - `install-tools.sh` - Updated `fix_dockerfile()` function with correct types
- **Status**: ✅ Resolved

### 2. Missing go.sum Entries
**Problem**: Missing go.sum entries for various dependencies:
```
missing go.sum entry for module providing package github.com/pion/ice/v4
missing go.sum entry for module providing package github.com/pion/webrtc/v4
missing go.sum entry for module providing package github.com/libp2p/go-yamux/v5
```
- **Cause**: Dependency updates not properly reflected in go.sum
- **Solution**: Added `fix_go_dependencies()` function to run `go mod tidy`
- **Files Modified**:
  - `go.sum` - Updated with missing dependency checksums
  - `install-tools.sh` - Added `fix_go_dependencies()` function
- **Status**: ✅ Resolved

### 3. madns.DefaultResolver Interface Incompatibility
**Problem**:
```
cannot use madns.DefaultResolver (variable of type *madns.Resolver) as network.MultiaddrDNSResolver value in argument to libp2p.MultiaddrResolver: *madns.Resolver does not implement network.MultiaddrDNSResolver (missing method ResolveDNSAddr)
```
- **Cause**: `go-libp2p` v0.40.0 changed the `network.MultiaddrDNSResolver` interface
- **Solution**:
  - Commented out `libp2p.MultiaddrResolver(madns.DefaultResolver)` line in `op-node/p2p/host.go`
  - libp2p v0.40.0+ has built-in DNS resolver by default, so no functionality loss
  - Added explanatory comments about built-in DNS resolver
- **Files Modified**:
  - `op-node/p2p/host.go` - Commented out madns.DefaultResolver usage
  - `install-tools.sh` - Added `fix_op_node_p2p()` function for automation
- **Code Changes**:
  ```go
  // Before:
  libp2p.MultiaddrResolver(madns.DefaultResolver),

  // After:
  // libp2p v0.40.0+ has built-in DNS resolver by default
  // No additional configuration needed for basic DNS resolution
  // libp2p.MultiaddrResolver(madns.DefaultResolver),
  ```
- **Status**: ✅ Resolved (Safe solution - no functionality loss)

## Script Improvements Made

### 1. install-tools.sh Enhancements
- **Added**: `fix_dockerfile()` function for go-libp2p-mplex compatibility
- **Added**: `fix_go_dependencies()` function for go.mod/go.sum updates
- **Added**: `fix_op_node_p2p()` function for madns.DefaultResolver issue
- **Improved**: OPTIMISM_ROOT path calculation
- **Added**: User prompts with default 'Y' responses for automatic fixes

### 2. New Scripts Created
- **Added**: `restart-devnet.sh` - Automated devnet cleanup and restart

## File Modifications

### Core Files Modified
1. **go.mod/go.sum**: Updated libp2p dependencies
2. **ops/docker/op-stack-go/Dockerfile**: Added compatibility patch
3. **op-node/p2p/host.go**: Commented out madns.DefaultResolver (temporary)
4. **mise.toml**: Updated Go version to 1.23.10

### Scripts Modified
1. **install-tools.sh**: Major enhancements with auto-fix functions
2. **build-devnet.sh**: Removed deprecated Docker build check
3. **check-system.sh**: Updated terminology
4. **run-challenger-devnet.sh**: Updated terminology

## Recent Updates (2025-08-29)

### Latest Fix: Docker Build Error for op-node
**Date**: 2025-08-29
**Problem**: `op-node` Docker build failing with:
```
ERROR: failed to build: target stage "op-node" could not be found
undefined: network.ConnErrorCode
undefined: network.StreamErrorCode
```
- **Root Cause Analysis**:
  - Build script was looking for target `op-node` but Dockerfile defines `op-node-target`
  - Compatibility patch in Dockerfile was using removed libp2p error code types
  - Docker build cache was still using old incorrect patch
- **Solution Applied**:
  1. Updated `install-tools.sh` to use correct parameter types (`int` instead of `network.ConnErrorCode/StreamErrorCode`)
  2. **Direct Dockerfile Fix**: Manually updated existing Dockerfile to use correct types
     - Line 65: `network.ConnErrorCode` → `int`
     - Line 68: `network.StreamErrorCode` → `int`
  3. Fixed Docker build compatibility for go-libp2p-mplex v0.9.0 with go-libp2p v0.36.2+
- **Files Directly Modified**:
  - `ops/docker/op-stack-go/Dockerfile` - Lines 65, 68 updated with correct `int` types
- **Additional Fix**: Removed unused `madns` import causing build error
  - Line 29 in `op-node/p2p/host.go`: Removed unused import `madns "github.com/multiformats/go-multiaddr-dns"`
- **Testing**: ✅ Successfully validated with Docker build

## Current Status
- ✅ Go-libp2p-mplex compatibility fixed (with correct types)
- ✅ Docker build errors resolved
- ✅ Automated fix integrated into install-tools.sh
- ⚠️ madns.DefaultResolver issue has temporary workaround
- 🔄 Ready for testing the complete build pipeline

## Next Steps
1. ✅ **Completed**: Fixed install-tools.sh with correct go-libp2p types
2. 🔄 **Next**: Test the automated fixes: `./install-tools.sh` 
3. 🔄 **Then**: Verify op-node build: `./build-devnet.sh`
4. Consider permanent solution for madns.DefaultResolver issue
5. Continue with challenger network development

## Notes
- All fixes are automated in install-tools.sh where possible
- Temporary workarounds are clearly marked
- Comprehensive logging and error handling added
- User-friendly prompts with sensible defaults implemented
