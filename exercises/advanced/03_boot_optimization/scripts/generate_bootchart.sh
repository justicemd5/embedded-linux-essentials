#!/bin/bash
#
# generate_bootchart.sh - Generate visual bootchart from kernel log
#
# Creates SVG visualization of boot process using kernel bootgraph.pl
# or generates text-based chart if SVG tools unavailable
#
# Author: Embedded Linux Labs
# License: MIT

set -e

LOG_FILE="${1:-}"
OUTPUT_BASE="${2:-bootchart}"
KERNEL_SRC="${KERNEL_SRC:-$HOME/bbb/linux}"

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_usage() {
    cat << EOF
Usage: $0 <dmesg_log> [output_base]

Generate boot visualization from kernel log.

Arguments:
    dmesg_log      dmesg output with initcall_debug enabled
    output_base    Output filename base (default: bootchart)

Requirements:
    - Kernel log with initcall_debug enabled
    - (Optional) Kernel source with scripts/bootgraph.pl for SVG output

Enable initcall_debug:
    Add 'initcall_debug' to kernel bootargs before capturing

Examples:
    # On target: dmesg > /tmp/dmesg.log
    # Copy to host: scp debian@192.168.7.2:/tmp/dmesg.log .
    $0 dmesg.log
    $0 dmesg.log my_bootchart
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

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  BOOTCHART GENERATOR"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check for initcall data
if ! grep -q "initcall" "$LOG_FILE"; then
    echo -e "${RED}Error:${NC} No initcall data found in log"
    echo ""
    echo "Enable initcall debugging:"
    echo "  1. Add 'initcall_debug' to kernel bootargs"
    echo "  2. Reboot and capture: dmesg > /tmp/dmesg.log"
    echo "  3. Run this script again"
    exit 1
fi

INITCALL_COUNT=$(grep -c "initcall" "$LOG_FILE" || echo "0")
echo "Found $INITCALL_COUNT initcall entries"
echo ""

# =============================================================================
# TRY KERNEL'S BOOTGRAPH.PL
# =============================================================================

generate_svg() {
    local BOOTGRAPH="$KERNEL_SRC/scripts/bootgraph.pl"
    
    if [ -f "$BOOTGRAPH" ]; then
        echo -e "${GREEN}Using kernel's bootgraph.pl...${NC}"
        
        # bootgraph.pl needs specific format
        perl "$BOOTGRAPH" "$LOG_FILE" > "${OUTPUT_BASE}.svg"
        
        if [ -s "${OUTPUT_BASE}.svg" ]; then
            echo "Generated: ${OUTPUT_BASE}.svg"
            return 0
        fi
    fi
    
    return 1
}

# =============================================================================
# TEXT-BASED BOOTCHART
# =============================================================================

generate_text_chart() {
    local TEXT_FILE="${OUTPUT_BASE}_chart.txt"
    
    echo "Generating text-based bootchart..."
    echo ""
    
    {
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "  BOOT PROCESS TIMELINE"
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo ""
        echo "Time (s)  Duration   Function"
        echo "────────  ─────────  ──────────────────────────────────────────────────────────"
        
        # Parse initcall entries
        grep "initcall.*returned" "$LOG_FILE" | while read -r line; do
            # Extract timestamp
            TIME=$(echo "$line" | grep -oP '\[\s*\K[\d.]+')
            
            # Extract function name
            FUNC=$(echo "$line" | grep -oP 'initcall \K[^\s]+')
            
            # Extract duration
            USECS=$(echo "$line" | grep -oP 'after \K\d+')
            
            if [ -n "$USECS" ]; then
                # Calculate duration in ms
                MS=$(echo "scale=1; $USECS / 1000" | bc)
                
                # Create visual bar (1 char per 10ms, max 40)
                BAR_LEN=$(echo "$USECS / 10000" | bc)
                [ "$BAR_LEN" -gt 40 ] && BAR_LEN=40
                BAR=$(printf '█%.0s' $(seq 1 $BAR_LEN 2>/dev/null) 2>/dev/null || echo "█")
                
                printf "%8s  %6s ms  %-40s %s\n" "$TIME" "$MS" "${FUNC:0:40}" "$BAR"
            fi
        done | sort -k1 -t' ' -n
        
        echo ""
        echo "════════════════════════════════════════════════════════════════════════════════"
        
    } > "$TEXT_FILE"
    
    echo "Generated: $TEXT_FILE"
}

# =============================================================================
# INITCALL SUMMARY
# =============================================================================

generate_summary() {
    local SUMMARY_FILE="${OUTPUT_BASE}_summary.txt"
    
    echo "Generating initcall summary..."
    
    {
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "  INITCALL TIMING SUMMARY"
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo ""
        echo "Generated: $(date)"
        echo "Source:    $LOG_FILE"
        echo ""
        
        # Total time
        TOTAL_USECS=$(grep "initcall.*returned" "$LOG_FILE" | \
            grep -oP 'after \K\d+' | \
            awk '{sum+=$1} END {print sum}')
        TOTAL_S=$(echo "scale=3; $TOTAL_USECS / 1000000" | bc)
        
        echo "Total initcall time: ${TOTAL_USECS} µs (${TOTAL_S}s)"
        echo ""
        
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "  TOP 30 SLOWEST INITCALLS"
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo ""
        printf "%-12s  %-10s  %s\n" "Duration" "Time (s)" "Function"
        printf "%-12s  %-10s  %s\n" "────────────" "──────────" "────────────────────────────────────────"
        
        grep "initcall.*returned" "$LOG_FILE" | while read -r line; do
            TIME=$(echo "$line" | grep -oP '\[\s*\K[\d.]+')
            FUNC=$(echo "$line" | grep -oP 'initcall \K[^\s]+')
            USECS=$(echo "$line" | grep -oP 'after \K\d+')
            if [ -n "$USECS" ]; then
                echo "$USECS $TIME $FUNC"
            fi
        done | sort -rn | head -30 | while read -r usecs time func; do
            MS=$(echo "scale=2; $usecs / 1000" | bc)
            printf "%8.2f ms  %10s  %s\n" "$MS" "$time" "$func"
        done
        
        echo ""
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "  INITCALL TIME DISTRIBUTION"
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo ""
        
        # Distribution buckets
        echo "Time Range          Count"
        echo "──────────────────  ─────"
        
        UNDER_1MS=$(grep "initcall.*returned" "$LOG_FILE" | grep -oP 'after \K\d+' | awk '$1 < 1000 {c++} END {print c+0}')
        MS_1_10=$(grep "initcall.*returned" "$LOG_FILE" | grep -oP 'after \K\d+' | awk '$1 >= 1000 && $1 < 10000 {c++} END {print c+0}')
        MS_10_100=$(grep "initcall.*returned" "$LOG_FILE" | grep -oP 'after \K\d+' | awk '$1 >= 10000 && $1 < 100000 {c++} END {print c+0}')
        MS_100_1000=$(grep "initcall.*returned" "$LOG_FILE" | grep -oP 'after \K\d+' | awk '$1 >= 100000 && $1 < 1000000 {c++} END {print c+0}')
        OVER_1S=$(grep "initcall.*returned" "$LOG_FILE" | grep -oP 'after \K\d+' | awk '$1 >= 1000000 {c++} END {print c+0}')
        
        printf "< 1 ms              %4d\n" "$UNDER_1MS"
        printf "1 - 10 ms           %4d\n" "$MS_1_10"
        printf "10 - 100 ms         %4d\n" "$MS_10_100"
        printf "100 ms - 1 s        %4d\n" "$MS_100_1000"
        printf "> 1 s               %4d\n" "$OVER_1S"
        
        echo ""
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "  OPTIMIZATION TARGETS"
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo ""
        echo "Initcalls > 100ms should be reviewed:"
        echo ""
        
        grep "initcall.*returned" "$LOG_FILE" | while read -r line; do
            FUNC=$(echo "$line" | grep -oP 'initcall \K[^\s]+')
            USECS=$(echo "$line" | grep -oP 'after \K\d+')
            if [ -n "$USECS" ] && [ "$USECS" -gt 100000 ]; then
                MS=$(echo "scale=1; $USECS / 1000" | bc)
                echo "  - $FUNC: ${MS}ms"
                
                # Provide optimization hints
                case "$FUNC" in
                    *usb*)
                        echo "    Hint: Consider USB_AUTOSUSPEND or disable USB if unused"
                        ;;
                    *mmc*)
                        echo "    Hint: MMC probe can be slow; consider deferred probe"
                        ;;
                    *net*|*eth*)
                        echo "    Hint: Network init can be deferred to user space"
                        ;;
                    *i2c*)
                        echo "    Hint: I2C device probing; check device tree entries"
                        ;;
                esac
            fi
        done
        
        echo ""
        
    } > "$SUMMARY_FILE"
    
    echo "Generated: $SUMMARY_FILE"
}

# =============================================================================
# MAIN
# =============================================================================

# Try SVG first
if generate_svg 2>/dev/null; then
    echo ""
else
    echo "Note: bootgraph.pl not found at $KERNEL_SRC/scripts/"
    echo "      Set KERNEL_SRC to kernel source path for SVG output"
    echo ""
fi

# Always generate text versions
generate_text_chart
generate_summary

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  OUTPUT FILES"
echo "════════════════════════════════════════════════════════════"
echo ""
ls -la ${OUTPUT_BASE}* 2>/dev/null || echo "No output files generated"
echo ""
