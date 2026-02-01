#!/bin/bash
#
# setup_rt_environment.sh - Configure BeagleBone Black for optimal RT performance
#
# Applies system-level optimizations for low-latency operation
#
# Usage:
#   ./setup_rt_environment.sh [TARGET_HOST]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

TARGET_HOST="${1:-debian@192.168.7.2}"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

echo ""
echo "========================================"
echo " RT Environment Setup for BBB"
echo "========================================"
echo ""

log_info "Connecting to $TARGET_HOST..."

# Check connection
if ! ssh $SSH_OPTS "$TARGET_HOST" "echo ok" &>/dev/null; then
    log_error "Cannot connect to $TARGET_HOST"
    exit 1
fi

# Apply all optimizations
ssh $SSH_OPTS "$TARGET_HOST" bash << 'REMOTE_SCRIPT'
#!/bin/bash

set -e

echo "[1/8] Setting CPU governor to performance..."
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [ -f "$cpu" ]; then
        echo performance > "$cpu" 2>/dev/null || echo "  Warning: Could not set $cpu"
    fi
done

echo "[2/8] Disabling CPU idle states..."
for state in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
    if [ -f "$state" ]; then
        echo 1 > "$state" 2>/dev/null || true
    fi
done

echo "[3/8] Setting RT throttling to unlimited..."
if [ -f /proc/sys/kernel/sched_rt_runtime_us ]; then
    echo -1 > /proc/sys/kernel/sched_rt_runtime_us
fi

echo "[4/8] Disabling kernel debug features..."
if [ -f /proc/sys/kernel/ftrace_enabled ]; then
    echo 0 > /proc/sys/kernel/ftrace_enabled 2>/dev/null || true
fi

echo "[5/8] Configuring IRQ affinity..."
# Move all IRQs to CPU 0 if possible (assumes we want CPU 1 isolated)
# This is optional and depends on your CPU topology
# for irq in /proc/irq/*/smp_affinity; do
#     echo 1 > "$irq" 2>/dev/null || true
# done

echo "[6/8] Adjusting kernel parameters..."
# Reduce kernel scheduling granularity for better RT
sysctl -q -w kernel.sched_min_granularity_ns=100000 2>/dev/null || true
sysctl -q -w kernel.sched_wakeup_granularity_ns=25000 2>/dev/null || true

echo "[7/8] Disabling kernel watchdog (if safe)..."
# Watchdog can add latency spikes
sysctl -q -w kernel.watchdog=0 2>/dev/null || true
sysctl -q -w kernel.nmi_watchdog=0 2>/dev/null || true

echo "[8/8] Setting memory allocation..."
# Avoid memory pressure during RT operation
sysctl -q -w vm.swappiness=0 2>/dev/null || true

echo ""
echo "Current configuration:"
echo "  CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'N/A')"
echo "  CPU Frequency: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 'N/A') kHz"
echo "  RT Runtime: $(cat /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null || echo 'N/A')"
echo "  Kernel: $(uname -r)"

REMOTE_SCRIPT

echo ""
log_info "RT environment configured!"
echo ""
echo "Recommendations for kernel bootargs:"
echo "  isolcpus=1             # Isolate CPU 1 for RT tasks (if multi-core)"
echo "  nohz_full=1            # Disable timer ticks on CPU 1"
echo "  rcu_nocbs=1            # Move RCU callbacks off CPU 1"
echo "  idle=poll              # Avoid C-state latency (uses more power)"
echo "  cpufreq.default_governor=performance"
echo ""
echo "Add these to /boot/uEnv.txt or U-Boot bootargs"
echo ""
