#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# Challenger Monitoring Script
#
# Monitors op-challenger activity, game participation, and performance
#
# Usage: ./monitor-challenger.sh [mode]
# Modes: summary | config | sync | logs | games | errors
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_title() {
    echo -e "${CYAN}━━━ $1 ━━━${NC}"
}

##############################################################################
# Helper functions
##############################################################################

get_challenger_container() {
    docker ps --format '{{.Names}}' | grep "op-challenger" | head -1 || echo ""
}

check_challenger_running() {
    local container=$(get_challenger_container)
    if [ -z "$container" ]; then
        log_error "op-challenger container is not running"
        exit 1
    fi
    echo "$container"
}

get_game_type_name() {
    local game_type="$1"
    case "$game_type" in
        0) echo "CANNON" ;;
        1) echo "PERMISSIONED_CANNON" ;;
        2) echo "ASTERISC" ;;
        254) echo "FAST" ;;
        255) echo "ALPHABET" ;;
        *) echo "UNKNOWN($game_type)" ;;
    esac
}

get_game_type_color() {
    local game_type="$1"
    case "$game_type" in
        0|1) echo "${BLUE}" ;;      # CANNON - Blue
        2) echo "${CYAN}" ;;         # ASTERISC - Cyan
        254) echo "${YELLOW}" ;;     # FAST - Yellow
        255) echo "${GREEN}" ;;      # ALPHABET - Green
        *) echo "${NC}" ;;
    esac
}

# Query GameType from game contract
get_game_type() {
    local game_address="$1"
    local l1_rpc="${L1_RPC_URL:-http://localhost:8545}"

    # Call gameType() function
    local result=$(cast call "$game_address" "gameType()(uint32)" --rpc-url "$l1_rpc" 2>/dev/null || echo "")

    if [ -n "$result" ]; then
        echo "$result"
    else
        echo ""
    fi
}

# Get port information
get_port_info() {
    if command -v kurtosis >/dev/null 2>&1; then
        local enclave_inspect=$(kurtosis enclave inspect simple-devnet 2>/dev/null || echo "")

        if [ -n "$enclave_inspect" ]; then
            L1_RPC_PORT=$(echo "$enclave_inspect" | grep "rpc: 8545/tcp" | head -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ' || echo "8545")
            L2_RPC_PORT=$(echo "$enclave_inspect" | grep "rpc: 8545/tcp" | tail -1 | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ' || echo "9545")
            ROLLUP_RPC_PORT=$(echo "$enclave_inspect" | grep "rpc: 8547/tcp" | sed 's/.*-> //' | sed 's/.*://' | tr -d ' ' || echo "7545")
        fi
    fi

    L1_RPC_PORT=${L1_RPC_PORT:-8545}
    L2_RPC_PORT=${L2_RPC_PORT:-9545}
    ROLLUP_RPC_PORT=${ROLLUP_RPC_PORT:-7545}

    L1_RPC_URL="http://localhost:$L1_RPC_PORT"
    L2_RPC_URL="http://localhost:$L2_RPC_PORT"
    ROLLUP_RPC_URL="http://localhost:$ROLLUP_RPC_PORT"
}

##############################################################################
# Main monitoring functions
##############################################################################

# 1. Challenger Container Status
show_container_status() {
    log_title "Challenger Container Status"

    local container=$(get_challenger_container)

    if [ -n "$container" ]; then
        local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        local uptime=$(docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null || echo "unknown")

        if [ "$status" = "running" ]; then
            log_success "Container: $container"
            echo "  Status:  $status"
            echo "  Started: $uptime"
        else
            log_error "Container: $container"
            echo "  Status: $status"
        fi
    else
        log_error "op-challenger container not found"
    fi
    echo ""
}

# 2. Recent Challenger Logs
show_recent_logs() {
    log_title "Recent Challenger Activity (Last 20 lines)"

    local container=$(get_challenger_container)

    if [ -n "$container" ]; then
        docker logs --tail=20 "$container" 2>&1 | while IFS= read -r line; do
            # Color-code different log levels
            if echo "$line" | grep -q "lvl=error\|lvl=crit"; then
                echo -e "${RED}$line${NC}"
            elif echo "$line" | grep -q "lvl=warn"; then
                echo -e "${YELLOW}$line${NC}"
            elif echo "$line" | grep -q "Game info\|Performing action\|Resolving"; then
                echo -e "${GREEN}$line${NC}"
            else
                echo "$line"
            fi
        done
    fi
    echo ""
}

# 3. Game Participation Summary
show_game_summary() {
    log_title "Game Participation Summary"

    local container=$(get_challenger_container)

    if [ -n "$container" ]; then
        echo "Analyzing logs for game activity..."

        # Get all logs once for efficiency
        local all_logs=$(docker logs "$container" 2>&1)

        # Count resolved games (unique)
        local games_resolved=$(echo "$all_logs" | grep "Game resolved" | sed -n 's/.*game=\(0x[a-fA-F0-9]*\).*/\1/p' | sort -u | wc -l | tr -d ' ')
        local defender_won=$(echo "$all_logs" | grep "Game resolved" | grep 'status="Defender Won"' | sed -n 's/.*game=\(0x[a-fA-F0-9]*\).*/\1/p' | sort -u | wc -l | tr -d ' ')
        local challenger_won=$(echo "$all_logs" | grep "Game resolved" | grep 'status="Challenger Won"' | sed -n 's/.*game=\(0x[a-fA-F0-9]*\).*/\1/p' | sort -u | wc -l | tr -d ' ')

        # Get list of resolved game addresses
        local resolved_games=$(echo "$all_logs" | grep "Game resolved" | sed -n 's/.*game=\(0x[a-fA-F0-9]*\).*/\1/p' | sort -u)

        # Count all unique games
        local all_games=$(echo "$all_logs" | grep -E "Game info|Game resolved" | sed -n 's/.*game=\(0x[a-fA-F0-9]*\).*/\1/p' | sort -u)
        local games_detected=$(echo "$all_games" | wc -l | tr -d ' ')

        # Count in-progress games
        local games_in_progress=0
        if [ -n "$all_games" ]; then
            if [ -n "$resolved_games" ]; then
                games_in_progress=$(echo "$all_games" | grep -v -F -f <(echo "$resolved_games") | wc -l | tr -d ' ')
            else
                games_in_progress=$games_detected
            fi
        fi

        # Count moves made
        local moves_made=$(echo "$all_logs" | grep "Performing action" | wc -l | tr -d ' ')

        # Count errors (last 100 lines)
        local recent_logs=$(echo "$all_logs" | tail -100)
        local errors=$(echo "$recent_logs" | grep "lvl=error" | wc -l | tr -d ' ')

        echo ""
        echo "  📊 Total Games:           $games_detected"
        echo "     ├─ 🟢 Active (In Progress):  $games_in_progress"
        echo "     └─ ✅ Resolved:              $games_resolved"
        if [ "$games_resolved" -gt 0 ]; then
            local total_resolved=$((defender_won + challenger_won))
            if [ "$total_resolved" -gt 0 ]; then
                local defender_pct=$((defender_won * 100 / total_resolved))
                local challenger_pct=$((challenger_won * 100 / total_resolved))
                echo "        ├─ 🛡️  Defender Won:     $defender_won ($defender_pct%)"
                echo "        └─ ⚔️  Challenger Won:   $challenger_won ($challenger_pct%)"
            fi
        fi
        echo ""
        echo "  🎯 Moves Made:            $moves_made"
        echo "  ⚠️  Recent Errors:         $errors"

        # Show recent error samples if any
        if [ "$errors" -gt 0 ]; then
            echo ""
            echo "  Recent Error Samples (last 3):"
            echo "$recent_logs" | grep "lvl=error" | tail -3 | while IFS= read -r error_line; do
                local timestamp=$(echo "$error_line" | sed -n 's/^t=\([^ ]*\).*/\1/p' | sed 's/\+.*//' | sed 's/T/ /')
                local msg=$(echo "$error_line" | sed -n 's/.*msg="\([^"]*\)".*/\1/p')

                if [ -n "$msg" ]; then
                    echo "    [$timestamp] $msg"
                fi
            done
            echo ""
            log_info "💡 View full error logs:"
            echo "     docker logs $container 2>&1 | grep 'lvl=error' | tail -20"
        fi
    fi
    echo ""
}

# 4. Active Games List
show_active_games() {
    log_title "Active Games (Last 10)"

    local container=$(get_challenger_container)

    if [ -n "$container" ]; then
        docker logs --tail=200 "$container" 2>&1 | grep "Game info" | tail -10 | while IFS= read -r line; do
            local game=$(echo "$line" | sed -n 's/.*game=\(0x[a-fA-F0-9]*\).*/\1/p' || echo "")
            local claims=$(echo "$line" | sed -n 's/.*claims=\([0-9]*\).*/\1/p' || echo "")
            local status=$(echo "$line" | sed -n 's/.*status="\([^"]*\)".*/\1/p' || echo "")

            if [ -n "$game" ]; then
                local game_type=$(get_game_type "$game")
                local game_type_name=$(get_game_type_name "$game_type")
                local game_type_color=$(get_game_type_color "$game_type")

                local type_badge=""
                if [ -n "$game_type" ]; then
                    type_badge="[${game_type_color}${game_type_name}${NC}] "
                fi

                if [ "$status" = "In Progress" ]; then
                    echo -e "  ${type_badge}${CYAN}$game${NC} - Claims: $claims - ${YELLOW}$status${NC}"
                elif [ "$status" = "Challenger Wins" ]; then
                    echo -e "  ${type_badge}${CYAN}$game${NC} - Claims: $claims - ${GREEN}$status${NC}"
                elif [ "$status" = "Defender Wins" ]; then
                    echo -e "  ${type_badge}${CYAN}$game${NC} - Claims: $claims - ${RED}$status${NC}"
                else
                    echo -e "  ${type_badge}${CYAN}$game${NC} - Claims: $claims - $status"
                fi
            fi
        done
    fi
    echo ""
}

# 5. Recently Resolved Games
show_resolved_games() {
    log_title "Recently Resolved Games (Last 10)"

    local container=$(get_challenger_container)

    if [ -n "$container" ]; then
        docker logs --tail=500 "$container" 2>&1 | grep "Game resolved" | tail -10 | while IFS= read -r line; do
            local timestamp=$(echo "$line" | sed -n 's/^t=\([^ ]*\).*/\1/p' || echo "")
            local game=$(echo "$line" | sed -n 's/.*game=\(0x[a-fA-F0-9]*\).*/\1/p' || echo "")
            local status=$(echo "$line" | sed -n 's/.*status="\([^"]*\)".*/\1/p' || echo "")

            local time_short=$(echo "$timestamp" | sed 's/\+.*//' | sed 's/T/ /')

            if [ -n "$game" ]; then
                local game_type=$(get_game_type "$game")
                local game_type_name=$(get_game_type_name "$game_type")
                local game_type_color=$(get_game_type_color "$game_type")

                local type_badge=""
                if [ -n "$game_type" ]; then
                    type_badge="[${game_type_color}${game_type_name}${NC}] "
                fi

                if [ "$status" = "Challenger Won" ]; then
                    echo -e "  ${type_badge}${CYAN}$game${NC} - ${GREEN}✓ $status${NC} - $time_short"
                elif [ "$status" = "Defender Won" ]; then
                    echo -e "  ${type_badge}${CYAN}$game${NC} - ${BLUE}✓ $status${NC} - $time_short"
                else
                    echo -e "  ${type_badge}${CYAN}$game${NC} - ✓ $status - $time_short"
                fi
            fi
        done
    fi
    echo ""
}

# 6. Challenger Actions Log
show_actions() {
    log_title "Recent Challenger Actions (Last 10)"

    local container=$(get_challenger_container)

    if [ -n "$container" ]; then
        docker logs --tail=200 "$container" 2>&1 | grep "Performing action" | tail -10 | while IFS= read -r line; do
            local game=$(echo "$line" | sed -n 's/.*game=\(0x[a-fA-F0-9]*\).*/\1/p' || echo "")
            local action=$(echo "$line" | sed -n 's/.*action=\([a-z]*\).*/\1/p' || echo "")
            local attack=$(echo "$line" | sed -n 's/.*is_attack=\(true\|false\).*/\1/p' || echo "")

            if [ -n "$game" ]; then
                local game_type=$(get_game_type "$game")
                local game_type_name=$(get_game_type_name "$game_type")
                local game_type_color=$(get_game_type_color "$game_type")

                local type_badge=""
                if [ -n "$game_type" ]; then
                    type_badge="[${game_type_color}${game_type_name}${NC}] "
                fi

                if [ "$attack" = "true" ]; then
                    echo -e "  ${type_badge}${CYAN}$game${NC} - ${RED}Attack${NC} ($action)"
                else
                    echo -e "  ${type_badge}${CYAN}$game${NC} - ${GREEN}Defend${NC} ($action)"
                fi
            fi
        done
    fi
    echo ""
}

# 7. Error Analysis
show_errors() {
    log_title "Recent Errors (Last 10)"

    local container=$(get_challenger_container)

    if [ -n "$container" ]; then
        local error_lines=$(docker logs --tail=100 "$container" 2>&1 | grep -E "lvl=error|lvl=crit" | tail -10)

        if [ -n "$error_lines" ]; then
            echo "$error_lines" | while IFS= read -r line; do
                echo -e "${RED}$line${NC}"
            done
        else
            log_success "No recent errors found!"
        fi
    fi
    echo ""
}

# 8. System Configuration
show_system_config() {
    log_title "System Configuration"

    # Load addresses from deploy config
    local addresses_file="${SCRIPT_DIR}/../../kurtosis-devnet/.l1-artifacts/.deploy-config"
    if [ ! -f "$addresses_file" ]; then
        log_warn "Deploy config not found"
        echo ""
        return
    fi

    local dgf_address=$(grep -o "DisputeGameFactoryProxy.*0x[a-fA-F0-9]*" "$addresses_file" 2>/dev/null | awk '{print $NF}' | head -1 || echo "")

    if [ -z "$dgf_address" ]; then
        log_warn "DisputeGameFactory address not found"
        echo ""
        return
    fi

    echo "  DisputeGameFactory: $dgf_address"
    echo ""

    # Get game implementation for type 0 (CANNON)
    local game_impl_0=$(cast call "$dgf_address" "gameImpls(uint32)(address)" 0 --rpc-url "$L1_RPC_URL" 2>/dev/null || echo "")

    if [ -n "$game_impl_0" ] && [ "$game_impl_0" != "0x0000000000000000000000000000000000000000" ]; then
        echo "  ┌─ GameType 0 (CANNON - MIPS VM)"
        echo "  │  Address: $game_impl_0"

        local max_clock=$(cast call "$game_impl_0" "maxClockDuration()(uint64)" --rpc-url "$L1_RPC_URL" 2>/dev/null || echo "0")
        local max_clock_min=$((max_clock / 60))

        local absolute_prestate=$(cast call "$game_impl_0" "absolutePrestate()(bytes32)" --rpc-url "$L1_RPC_URL" 2>/dev/null || echo "")

        echo "  │  Max Clock Duration: ${max_clock}s (${max_clock_min} min)"
        echo "  │  Absolute Prestate: ${absolute_prestate:0:18}...${absolute_prestate: -6}"
    fi

    echo ""
}

# 9. Synchronization Status
show_sync_status() {
    log_title "Blockchain Synchronization Status"

    # L1 Block Height
    local l1_block=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$L1_RPC_URL" 2>/dev/null | jq -r '.result' || echo "0x0")
    local l1_num=$((16#${l1_block#0x} || 0))

    # L2 Block Height
    local l2_block=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$L2_RPC_URL" 2>/dev/null | jq -r '.result' || echo "0x0")
    local l2_num=$((16#${l2_block#0x} || 0))

    echo ""
    echo "  ┌─ L1 Ethereum"
    if [ "$l1_num" -gt 0 ]; then
        echo -e "  │  └─ Block: ${GREEN}$l1_num${NC}"
    else
        echo -e "  │  └─ Block: ${RED}Not available${NC}"
    fi

    echo "  │"
    echo "  └─ L2 OP Stack"
    if [ "$l2_num" -gt 0 ]; then
        echo -e "     └─ Block: ${GREEN}$l2_num${NC}"
    else
        echo -e "     └─ Block: ${RED}Not synced${NC}"
    fi

    echo ""
}

# 10. Live Log Tail
tail_logs() {
    log_title "Challenger Live Logs (Ctrl+C to exit)"
    echo ""

    local container=$(get_challenger_container)

    if [ -n "$container" ]; then
        docker logs -f --tail=50 "$container" 2>&1 | while IFS= read -r line; do
            # Color-code logs
            if echo "$line" | grep -q "lvl=error\|lvl=crit"; then
                echo -e "${RED}$line${NC}"
            elif echo "$line" | grep -q "lvl=warn"; then
                echo -e "${YELLOW}$line${NC}"
            elif echo "$line" | grep -q "Game info"; then
                echo -e "${CYAN}$line${NC}"
            elif echo "$line" | grep -q "Performing action"; then
                echo -e "${GREEN}$line${NC}"
            elif echo "$line" | grep -q "Resolving"; then
                echo -e "${GREEN}✅ $line${NC}"
            else
                echo "$line"
            fi
        done
    fi
}

##############################################################################
# Main script
##############################################################################

# Initialize port information
get_port_info

# Parse arguments
MODE="${1:-summary}"

case "$MODE" in
    summary)
        echo ""
        log_info "=========================================="
        log_info "Challenger Monitoring Dashboard"
        log_info "=========================================="
        echo ""

        show_container_status
        show_system_config
        show_sync_status
        show_game_summary
        show_active_games
        show_resolved_games
        show_actions
        show_errors

        echo ""
        log_info "=========================================="
        log_info "Monitoring Options"
        log_info "=========================================="
        echo ""
        echo "  Live logs:      $0 logs"
        echo "  Games only:     $0 games"
        echo "  Errors only:    $0 errors"
        echo "  Sync status:    $0 sync"
        echo "  Config:         $0 config"
        echo "  Full summary:   $0 summary (default)"
        echo ""
        ;;

    config)
        echo ""
        show_system_config
        ;;

    sync)
        echo ""
        show_sync_status
        ;;

    logs)
        tail_logs
        ;;

    games)
        echo ""
        show_game_summary
        show_active_games
        show_resolved_games
        show_actions
        ;;

    errors)
        echo ""
        show_errors
        ;;

    *)
        log_error "Unknown mode: $MODE"
        echo ""
        echo "Usage: $0 [summary|config|sync|logs|games|errors]"
        echo ""
        echo "Modes:"
        echo "  summary  - Full dashboard with all information (default)"
        echo "  config   - System configuration"
        echo "  sync     - Blockchain sync status"
        echo "  logs     - Live log tail (Ctrl+C to exit)"
        echo "  games    - Game participation details"
        echo "  errors   - Error analysis"
        echo ""
        exit 1
        ;;
esac

exit 0
