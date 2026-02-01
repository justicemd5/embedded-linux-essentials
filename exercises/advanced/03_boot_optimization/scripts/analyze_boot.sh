#!/bin/bash
#
# analyze_boot.sh - Analyze boot log and identify bottlenecks
#
# Parses grabserial or kernel boot log to extract timing information
#
# Author: Embedded Linux Labs
# License: MIT

set -e

LOG_FILE="${1:-}"
REPORT_FILE="${2:-boot_analysis_report.txt}"

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_usage() {
    cat << EOF
Usage: $0 <boot_log_file> [report_file]

Analyze a boot log and identify bottlenecks.

Arguments:
    boot_log_file  Boot log captured with grabserial or dmesg
    report_file    Output report file (default: boot_analysis_report.txt)

The log should contain:
    - printk timestamps (printk.time=1 or grabserial -t)
    - Optional: initcall_debug output for detailed analysis

Examples:
    $0 boot.log                    # Analyze boot.log
    $0 boot.log analysis.txt       # Save report to file
EOF
}

if [ -z "$LOG_FILE" ]; then
    show_usage
    exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
    echo "Error: File not found: $LOG_FILE"
    exit 1
fi

# Redirect all output to both terminal and file
exec > >(tee "$REPORT_FILE")
exec 2>&1

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  BOOT TIME ANALYSIS REPORT"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Log file: $LOG_FILE"
echo "Date:     $(date)"
echo ""

# =============================================================================
# BOOT STAGE DETECTION
# =============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  BOOT STAGES TIMELINE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Function to extract grabserial timestamp (format: [0.123456])
get_grabserial_time() {
    grep -m1 "$1" "$LOG_FILE" 2>/dev/null | grep -oP '^\[\s*\K[\d.]+' || echo ""
}

# Function to extract kernel timestamp [  0.123456]
get_kernel_time() {
    grep -m1 "$1" "$LOG_FILE" 2>/dev/null | grep -oP '\[\s*\K[\d.]+' || echo ""
}

# Detect timestamp format
if grep -qP '^\[\s*\d+\.\d+\]' "$LOG_FILE"; then
    echo "Timestamp format: grabserial (absolute)"
    TIME_FORMAT="grabserial"
else
    echo "Timestamp format: kernel (relative)"
    TIME_FORMAT="kernel"
fi
echo ""

declare -A STAGES

# ROM Bootloader (AM335x identification)
STAGES[rom]=$(get_grabserial_time "AM335X\|CH1\|CH2")

# U-Boot SPL
STAGES[spl]=$(get_grabserial_time "U-Boot SPL")

# U-Boot proper
STAGES[uboot]=$(get_grabserial_time "U-Boot 20")

# U-Boot autoboot
STAGES[autoboot]=$(get_grabserial_time "Hit any key to stop autoboot")

# Kernel load
STAGES[kernel_load]=$(get_grabserial_time "Starting kernel")

# First kernel message
STAGES[kernel_start]=$(get_kernel_time "Booting Linux on physical CPU")

# Memory init
STAGES[memory]=$(get_kernel_time "Memory:")

# Device tree
STAGES[dtb]=$(get_kernel_time "Machine model:")

# Mount root
STAGES[rootfs]=$(get_kernel_time "VFS: Mounted root")

# Init start
STAGES[init]=$(get_kernel_time "Run /.*init\|systemd\[1\]: Detected architecture")

# Login prompt (may need grabserial time)
STAGES[login]=$(get_grabserial_time "login:")

echo "Stage Timeline:"
echo ""
printf "  %-20s %s\n" "Stage" "Time"
printf "  %-20s %s\n" "────────────────────" "────────────"

for stage in rom spl uboot autoboot kernel_load kernel_start memory dtb rootfs init login; do
    if [ -n "${STAGES[$stage]:-}" ]; then
        printf "  %-20s %ss\n" "$stage" "${STAGES[$stage]}"
    fi
done

echo ""

# =============================================================================
# BOOT TIME SUMMARY
# =============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STAGE DURATIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Calculate stage durations (if we have times)
calculate_duration() {
    local start=$1
    local end=$2
    if [ -n "$start" ] && [ -n "$end" ]; then
        echo "scale=3; $end - $start" | bc 2>/dev/null || echo ""
    fi
}

SPL_DUR=$(calculate_duration "${STAGES[rom]:-0}" "${STAGES[spl]:-}")
UBOOT_DUR=$(calculate_duration "${STAGES[spl]:-0}" "${STAGES[kernel_load]:-}")
KERNEL_DUR=$(calculate_duration "0" "${STAGES[init]:-}")

echo "Stage Durations (approximate):"
echo ""
if [ -n "$SPL_DUR" ]; then
    printf "  ROM → SPL:       %6ss\n" "$SPL_DUR"
fi
if [ -n "$UBOOT_DUR" ]; then
    printf "  SPL → Kernel:    %6ss\n" "$UBOOT_DUR"
fi
if [ -n "$KERNEL_DUR" ]; then
    printf "  Kernel init:     %6ss\n" "$KERNEL_DUR"
fi
echo ""

# =============================================================================
# INITCALL ANALYSIS
# =============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  INITCALL ANALYSIS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if grep -q "initcall.*returned" "$LOG_FILE"; then
    echo "Top 20 slowest initcalls:"
    echo ""
    printf "  %-12s %s\n" "Time (µs)" "Function"
    printf "  %-12s %s\n" "────────────" "────────────────────────────────────"
    
    grep "initcall.*returned" "$LOG_FILE" | \
        sed 's/.*initcall \([^ ]*\).*after \([0-9]*\) usecs/\2 \1/' | \
        sort -rn | head -20 | \
        awk '{printf "  %10d   %s\n", $1, $2}'
    
    echo ""
    
    # Total initcall time
    TOTAL_INITCALL=$(grep "initcall.*returned" "$LOG_FILE" | \
        sed 's/.*after \([0-9]*\) usecs.*/\1/' | \
        awk '{sum+=$1} END {print sum}')
    
    if [ -n "$TOTAL_INITCALL" ]; then
        TOTAL_SECONDS=$(echo "scale=3; $TOTAL_INITCALL / 1000000" | bc)
        echo "Total initcall time: ${TOTAL_INITCALL} µs (${TOTAL_SECONDS}s)"
    fi
else
    echo "No initcall_debug data found."
    echo "Add 'initcall_debug' to kernel bootargs for detailed analysis."
fi

echo ""

# =============================================================================
# KERNEL MODULE LOADING
# =============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  KERNEL MODULE LOADING"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

MODULE_COUNT=$(grep -c "module.*loaded" "$LOG_FILE" 2>/dev/null || echo "0")
echo "Modules loaded during boot: $MODULE_COUNT"
echo ""

if [ "$MODULE_COUNT" -gt 0 ]; then
    echo "Modules loaded:"
    grep "module.*loaded\|: loading\|: loaded" "$LOG_FILE" | head -20
fi

echo ""

# =============================================================================
# SYSTEMD ANALYSIS (if applicable)
# =============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  USERSPACE / INIT SYSTEM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if grep -q "systemd" "$LOG_FILE"; then
    echo "Init system: systemd"
    echo ""
    
    # Look for systemd startup time
    grep "Startup finished in" "$LOG_FILE" | tail -1 || echo "Startup time not found in log"
    echo ""
    
    echo "For detailed systemd analysis, run on target:"
    echo "  systemd-analyze"
    echo "  systemd-analyze blame"
    echo "  systemd-analyze critical-chain"
else
    echo "Init system: Not systemd (possibly BusyBox or SysV init)"
fi

echo ""

# =============================================================================
# BOTTLENECK IDENTIFICATION
# =============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  BOTTLENECK IDENTIFICATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Potential bottlenecks detected:"
echo ""

# Check for boot delay
if grep -q "Hit any key to stop autoboot" "$LOG_FILE"; then
    DELAY=$(grep "Hit any key" "$LOG_FILE" | grep -oP '\d+(?= second)' | head -1)
    if [ -n "$DELAY" ] && [ "$DELAY" -gt 0 ]; then
        echo "  ⚠️  U-Boot bootdelay: ${DELAY}s"
        echo "      Fix: setenv bootdelay 0; saveenv"
        echo ""
    fi
fi

# Check for verbose output
if ! grep -q "quiet" "$LOG_FILE" 2>/dev/null; then
    if [ "$(grep -c '^\[' "$LOG_FILE")" -gt 100 ]; then
        echo "  ⚠️  Verbose kernel output detected"
        echo "      Fix: Add 'quiet loglevel=0' to bootargs"
        echo ""
    fi
fi

# Check for slow initcalls
if grep -q "initcall.*returned" "$LOG_FILE"; then
    SLOW_INITCALLS=$(grep "initcall.*returned" "$LOG_FILE" | \
        sed 's/.*after \([0-9]*\) usecs.*/\1/' | \
        awk '$1 > 500000 {count++} END {print count+0}')
    
    if [ "$SLOW_INITCALLS" -gt 0 ]; then
        echo "  ⚠️  $SLOW_INITCALLS initcalls taking >500ms"
        echo "      Review top initcalls above, consider deferred init"
        echo ""
    fi
fi

# Check for filesystem errors
if grep -q "EXT4-fs error\|VFS: Cannot open root device" "$LOG_FILE"; then
    echo "  ❌  Filesystem errors detected"
    echo "      Check root= parameter and filesystem integrity"
    echo ""
fi

# =============================================================================
# OPTIMIZATION RECOMMENDATIONS
# =============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OPTIMIZATION RECOMMENDATIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cat << 'RECOMMENDATIONS'
U-Boot:
  □ Set bootdelay to 0
  □ Enable silent mode if console output not needed
  □ Consider Falcon Mode for fastest boot

Kernel:
  □ Add 'quiet loglevel=0' to bootargs
  □ Disable CONFIG_DEBUG_INFO
  □ Use LZO or uncompressed kernel
  □ Disable unused drivers
  □ Build slow drivers as modules

Userspace:
  □ Disable unnecessary systemd services
  □ Consider BusyBox init for faster boot
  □ Optimize /etc/rc.local and startup scripts
  □ Use read-only rootfs with tmpfs overlays
RECOMMENDATIONS

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Report saved to: $REPORT_FILE"
echo "════════════════════════════════════════════════════════════════"
