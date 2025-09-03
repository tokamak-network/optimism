#!/bin/bash

# Fix intent.yaml to match simple.yaml game_type configuration
# Usage: ./fix-intent-yaml.sh

set -e

SIMPLE_YAML="/Users/zena/tokamak-projects/optimism/kurtosis-devnet/simple.yaml"
INTENT_YAML="/tmp/current-devnet-config/intent.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if files exist
check_files() {
    if [ ! -f "$SIMPLE_YAML" ]; then
        log_error "simple.yaml not found at: $SIMPLE_YAML"
        exit 1
    fi
    
    if [ ! -f "$INTENT_YAML" ]; then
        log_error "intent.yaml not found at: $INTENT_YAML"
        log_info "Please run build-devnet.sh first to generate intent.yaml"
        exit 1
    fi
}

# Extract game_type from simple.yaml
get_game_type_from_simple() {
    local game_type=$(grep "game_type:" "$SIMPLE_YAML" | awk '{print $2}' | tr -d ' ')
    
    if [ -z "$game_type" ]; then
        log_error "Could not find game_type in simple.yaml"
        exit 1
    fi
    
    echo "$game_type"
}

# Map game type to VM type
get_vm_type() {
    local game_type=$1
    
    case $game_type in
        0)
            echo "CANNON"
            ;;
        1)
            echo "PERMISSIONED"  # Actually should be PERMISSIONED, not CANNON
            ;;
        *)
            log_warn "Unknown game type: $game_type, defaulting to CANNON"
            echo "CANNON"
            ;;
    esac
}

# Get trace type name for logging
get_trace_type_name() {
    local game_type=$1
    
    case $game_type in
        0)
            echo "cannon"
            ;;
        1) 
            echo "permissioned"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Fix intent.yaml to match simple.yaml configuration
fix_intent_yaml() {
    local game_type=$1
    local vm_type=$2
    local trace_type_name=$3
    
    log_info "Fixing intent.yaml configuration..."
    log_info "  Game Type: $game_type ($trace_type_name)"
    log_info "  VM Type: $vm_type"
    
    # Create backup
    cp "$INTENT_YAML" "$INTENT_YAML.backup"
    log_info "Created backup: $INTENT_YAML.backup"
    
    # Fix respectedGameType
    sed -i.tmp "s/respectedGameType: 0/respectedGameType: $game_type/g" "$INTENT_YAML"
    
    # Fix makeRespected  
    sed -i.tmp "s/makeRespected: false/makeRespected: true/g" "$INTENT_YAML"
    
    # Fix vmType
    sed -i.tmp "s/vmType: CANNON/vmType: $vm_type/g" "$INTENT_YAML"
    
    # Remove sed temp file
    rm -f "$INTENT_YAML.tmp"
    
    log_info "✅ intent.yaml has been updated successfully"
}

# Verify the changes
verify_changes() {
    local expected_game_type=$1
    local expected_vm_type=$2
    
    local actual_game_type=$(grep "respectedGameType:" "$INTENT_YAML" | awk '{print $2}')
    local actual_make_respected=$(grep "makeRespected:" "$INTENT_YAML" | awk '{print $2}')
    local actual_vm_type=$(grep "vmType:" "$INTENT_YAML" | awk '{print $2}')
    
    echo
    log_info "Verification Results:"
    echo "  Expected respectedGameType: $expected_game_type"
    echo "  Actual respectedGameType: $actual_game_type"
    echo "  Expected makeRespected: true"  
    echo "  Actual makeRespected: $actual_make_respected"
    echo "  Expected vmType: $expected_vm_type"
    echo "  Actual vmType: $actual_vm_type"
    
    if [ "$actual_game_type" = "$expected_game_type" ] && \
       [ "$actual_make_respected" = "true" ] && \
       [ "$actual_vm_type" = "$expected_vm_type" ]; then
        log_info "✅ All configurations match expected values"
        return 0
    else
        log_error "❌ Configuration mismatch detected"
        return 1
    fi
}

# Show before/after diff
show_diff() {
    if [ -f "$INTENT_YAML.backup" ]; then
        log_info "Configuration changes:"
        echo
        diff "$INTENT_YAML.backup" "$INTENT_YAML" || true
        echo
    fi
}

# Main execution
main() {
    echo "🔧 Intent.yaml Configuration Fix Script"
    echo "======================================"
    echo
    
    # Check prerequisites
    check_files
    
    # Extract game type from simple.yaml
    local game_type=$(get_game_type_from_simple)
    local vm_type=$(get_vm_type "$game_type")
    local trace_type_name=$(get_trace_type_name "$game_type")
    
    log_info "Found configuration in simple.yaml:"
    log_info "  game_type: $game_type ($trace_type_name)"
    
    # Check current intent.yaml state
    local current_game_type=$(grep "respectedGameType:" "$INTENT_YAML" | awk '{print $2}')
    
    if [ "$current_game_type" = "$game_type" ]; then
        log_info "✅ intent.yaml already matches simple.yaml configuration"
        log_info "  Current respectedGameType: $current_game_type"
        exit 0
    fi
    
    log_warn "Configuration mismatch detected:"
    log_warn "  simple.yaml game_type: $game_type"
    log_warn "  intent.yaml respectedGameType: $current_game_type"
    echo
    
    # Apply fixes
    fix_intent_yaml "$game_type" "$vm_type" "$trace_type_name"
    
    # Verify changes
    if verify_changes "$game_type" "$vm_type"; then
        show_diff
        echo
        log_info "🎉 Configuration fix completed successfully!"
        echo
        log_info "Next steps:"
        echo "  1. Rebuild devnet: ./build-devnet.sh"
        echo "  2. Run challenger: ./run-challenger-devnet.sh"
        echo "  3. Verify no 'unsupported game type' errors"
    else
        log_error "Configuration fix failed"
        log_info "Restoring backup..."
        mv "$INTENT_YAML.backup" "$INTENT_YAML"
        exit 1
    fi
}

# Execute main function
main "$@"