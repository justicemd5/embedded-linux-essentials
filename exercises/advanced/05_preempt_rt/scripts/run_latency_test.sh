#!/bin/bash
#
# run_latency_test.sh - Comprehensive latency testing for PREEMPT_RT kernel
#
# Runs cyclictest with various configurations and generates reports
#
# Usage:
#   ./run_latency_test.sh [test_type]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

TARGET_HOST="${TARGET_HOST:-debian@192.168.7.2}"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"
TEST_TYPE="${1:-quick}"
OUTPUT_DIR="${OUTPUT_DIR:-./latency_results}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [test_type]

Run latency tests on BeagleBone Black with PREEMPT_RT kernel.

Test Types:
    quick       Quick test (30 seconds, no stress)
    standard    Standard test (5 minutes, with stress)
    extended    Extended test (30 minutes, heavy stress)
    custom      Interactive custom configuration

Environment Variables:
    TARGET_HOST  SSH target (default: debian@192.168.7.2)
    OUTPUT_DIR   Results directory (default: ./latency_results)

Prerequisites on BBB:
    - rt-tests package: sudo apt install rt-tests
    - stress-ng package: sudo apt install stress-ng
    - PREEMPT_RT kernel running

Examples:
    $0 quick              # 30-second quick test
    $0 standard           # 5-minute standard test
    TARGET_HOST=root@bbb $0 extended  # Custom host, extended test
EOF
}

check_connection() {
    log_info "Checking connection to $TARGET_HOST..."
    
    if ! ssh $SSH_OPTS "$TARGET_HOST" "echo ok" &>/dev/null; then
        log_error "Cannot connect to $TARGET_HOST"
        exit 1
    fi
    
    log_info "Connection OK"
}

check_rt_kernel() {
    log_info "Checking for RT kernel..."
    
    UNAME=$(ssh $SSH_OPTS "$TARGET_HOST" "uname -r")
    
    if echo "$UNAME" | grep -q "rt\|PREEMPT_RT"; then
        log_info "RT kernel detected: $UNAME"
    else
        log_warn "No RT kernel detected: $UNAME"
        log_warn "Results may not reflect RT performance"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_tools() {
    log_info "Checking for required tools on target..."
    
    if ! ssh $SSH_OPTS "$TARGET_HOST" "which cyclictest" &>/dev/null; then
        log_warn "cyclictest not found, installing rt-tests..."
        ssh $SSH_OPTS "$TARGET_HOST" "sudo apt-get update && sudo apt-get install -y rt-tests"
    fi
    
    if ! ssh $SSH_OPTS "$TARGET_HOST" "which stress-ng" &>/dev/null; then
        log_warn "stress-ng not found, installing..."
        ssh $SSH_OPTS "$TARGET_HOST" "sudo apt-get install -y stress-ng" || {
            log_warn "Could not install stress-ng, stress tests may be limited"
        }
    fi
}

setup_rt_environment() {
    log_info "Configuring RT environment on target..."
    
    ssh $SSH_OPTS "$TARGET_HOST" bash << 'REMOTE_SCRIPT'
# Set performance governor
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance > "$cpu" 2>/dev/null || true
done

# Disable kernel debugging that adds latency
echo 0 > /proc/sys/kernel/ftrace_enabled 2>/dev/null || true

# Set RT throttling to unlimited (for testing only!)
echo -1 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null || true

echo "RT environment configured"
REMOTE_SCRIPT
}

run_quick_test() {
    log_info "Running quick latency test (30 seconds)..."
    
    local output_file="${OUTPUT_DIR}/quick_${TIMESTAMP}.txt"
    
    ssh $SSH_OPTS "$TARGET_HOST" "sudo cyclictest -l 30000 -m -Sp99 -i1000 -h500 -q" \
        | tee "$output_file"
}

run_standard_test() {
    log_info "Running standard latency test (5 minutes with stress)..."
    
    local output_file="${OUTPUT_DIR}/standard_${TIMESTAMP}.txt"
    local histogram_file="${OUTPUT_DIR}/standard_hist_${TIMESTAMP}.txt"
    
    # Start stress in background on target
    log_info "Starting stress load..."
    ssh $SSH_OPTS "$TARGET_HOST" "sudo stress-ng --cpu 1 --io 1 --vm 1 --vm-bytes 64M --timeout 310s &" || {
        log_warn "stress-ng failed, running without stress"
    }
    
    sleep 5  # Let stress stabilize
    
    log_info "Running cyclictest..."
    ssh $SSH_OPTS "$TARGET_HOST" "sudo cyclictest -l 300000 -m -Sp99 -i1000 -h500 -q" \
        | tee "$output_file"
    
    # Save histogram
    ssh $SSH_OPTS "$TARGET_HOST" "sudo killall stress-ng 2>/dev/null" || true
}

run_extended_test() {
    log_info "Running extended latency test (30 minutes with heavy stress)..."
    
    local output_file="${OUTPUT_DIR}/extended_${TIMESTAMP}.txt"
    
    # Heavy stress
    log_info "Starting heavy stress load..."
    ssh $SSH_OPTS "$TARGET_HOST" bash << 'STRESS_SCRIPT'
sudo stress-ng --cpu 1 --io 2 --vm 1 --vm-bytes 128M \
    --hdd 1 --fork 2 --timeout 1810s &
STRESS_SCRIPT
    
    sleep 10  # Let stress stabilize
    
    log_info "Running cyclictest (this will take 30 minutes)..."
    ssh $SSH_OPTS "$TARGET_HOST" "sudo cyclictest -l 1800000 -m -Sp99 -i1000 -h1000 -q" \
        | tee "$output_file"
    
    ssh $SSH_OPTS "$TARGET_HOST" "sudo killall stress-ng 2>/dev/null" || true
}

run_custom_test() {
    echo ""
    echo "Custom Test Configuration"
    echo "========================="
    
    read -p "Duration (seconds) [60]: " duration
    duration=${duration:-60}
    
    read -p "Interval (microseconds) [1000]: " interval
    interval=${interval:-1000}
    
    read -p "Priority (1-99) [99]: " priority
    priority=${priority:-99}
    
    read -p "Enable stress? [Y/n]: " stress
    stress=${stress:-Y}
    
    local loops=$((duration * 1000000 / interval))
    local output_file="${OUTPUT_DIR}/custom_${TIMESTAMP}.txt"
    
    log_info "Running custom test: ${duration}s, ${interval}µs interval, priority ${priority}"
    
    if [[ $stress =~ ^[Yy]$ ]]; then
        ssh $SSH_OPTS "$TARGET_HOST" "sudo stress-ng --cpu 1 --timeout $((duration + 10))s &" || true
        sleep 3
    fi
    
    ssh $SSH_OPTS "$TARGET_HOST" "sudo cyclictest -l $loops -m -Sp${priority} -i${interval} -h500 -q" \
        | tee "$output_file"
    
    if [[ $stress =~ ^[Yy]$ ]]; then
        ssh $SSH_OPTS "$TARGET_HOST" "sudo killall stress-ng 2>/dev/null" || true
    fi
}

analyze_results() {
    local result_file="$1"
    
    if [ ! -f "$result_file" ]; then
        return
    fi
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  LATENCY ANALYSIS"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    # Extract key metrics
    MAX_LATENCY=$(grep "Max Latencies" "$result_file" 2>/dev/null | awk '{print $NF}')
    AVG_LATENCY=$(grep "Avg Latencies" "$result_file" 2>/dev/null | awk '{print $NF}')
    
    if [ -n "$MAX_LATENCY" ]; then
        echo "Maximum Latency: ${MAX_LATENCY} µs"
        
        # Evaluate result
        if [ "$MAX_LATENCY" -lt 50 ]; then
            echo -e "${GREEN}✓ Excellent: < 50µs${NC}"
        elif [ "$MAX_LATENCY" -lt 100 ]; then
            echo -e "${GREEN}✓ Good: < 100µs${NC}"
        elif [ "$MAX_LATENCY" -lt 200 ]; then
            echo -e "${YELLOW}⚠ Acceptable: < 200µs${NC}"
        else
            echo -e "${RED}✗ Poor: > 200µs - Needs investigation${NC}"
        fi
    fi
    
    echo ""
    echo "Full results saved to: $result_file"
    echo "════════════════════════════════════════════════════════════"
}

# ==========================================================================
# MAIN
# ==========================================================================

case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
esac

echo ""
echo "========================================"
echo " PREEMPT_RT Latency Test Suite"
echo "========================================"
echo ""

mkdir -p "$OUTPUT_DIR"

check_connection
check_rt_kernel
check_tools
setup_rt_environment

echo ""

case "$TEST_TYPE" in
    quick)
        run_quick_test
        analyze_results "${OUTPUT_DIR}/quick_${TIMESTAMP}.txt"
        ;;
    standard)
        run_standard_test
        analyze_results "${OUTPUT_DIR}/standard_${TIMESTAMP}.txt"
        ;;
    extended)
        run_extended_test
        analyze_results "${OUTPUT_DIR}/extended_${TIMESTAMP}.txt"
        ;;
    custom)
        run_custom_test
        analyze_results "${OUTPUT_DIR}/custom_${TIMESTAMP}.txt"
        ;;
    *)
        log_error "Unknown test type: $TEST_TYPE"
        show_usage
        exit 1
        ;;
esac

echo ""
log_info "Test complete!"
