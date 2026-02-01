#!/bin/bash
#
# measure_baseline.sh - Measure BeagleBone Black baseline boot time
#
# Uses grabserial for accurate hardware timestamps
#
# Author: Embedded Linux Labs
# License: MIT

set -e

SERIAL_PORT="${1:-/dev/ttyACM0}"
BAUD_RATE="${2:-115200}"
OUTPUT_DIR="${3:-./measurements}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/boot_baseline_${TIMESTAMP}.log"

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
Usage: $0 [SERIAL_PORT] [BAUD_RATE] [OUTPUT_DIR]

Measure BeagleBone Black boot time using grabserial.

Arguments:
    SERIAL_PORT  Serial port device (default: /dev/ttyACM0)
    BAUD_RATE    Baud rate (default: 115200)
    OUTPUT_DIR   Directory for output files (default: ./measurements)

Prerequisites:
    - grabserial: pip3 install grabserial
    - Serial console access to BBB
    - printk.time=1 in kernel bootargs

Examples:
    $0                           # Use defaults
    $0 /dev/ttyUSB0             # Use USB serial adapter
    $0 /dev/ttyACM0 115200 /tmp # Custom output directory
EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check grabserial
    if ! command -v grabserial &> /dev/null; then
        log_error "grabserial not found. Install with: pip3 install grabserial"
        exit 1
    fi
    
    # Check serial port
    if [ ! -e "$SERIAL_PORT" ]; then
        log_error "Serial port $SERIAL_PORT not found"
        log_info "Available ports:"
        ls -la /dev/tty{USB,ACM}* 2>/dev/null || echo "  None found"
        exit 1
    fi
    
    # Check permissions
    if [ ! -r "$SERIAL_PORT" ] || [ ! -w "$SERIAL_PORT" ]; then
        log_error "Cannot access $SERIAL_PORT. Add user to dialout group:"
        echo "    sudo usermod -aG dialout \$USER"
        exit 1
    fi
    
    log_info "Prerequisites OK"
}

create_output_dir() {
    mkdir -p "$OUTPUT_DIR"
    log_info "Output directory: $OUTPUT_DIR"
}

measure_with_grabserial() {
    log_info "Starting boot measurement..."
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  BOOT TIME MEASUREMENT                                     ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Serial Port: $SERIAL_PORT @ $BAUD_RATE baud"
    echo "Output:      $OUTPUT_FILE"
    echo ""
    echo -e "${YELLOW}>>> Power cycle the BeagleBone Black NOW <<<${NC}"
    echo ""
    echo "Markers detected:"
    echo "  - Start:  'U-Boot SPL' or 'AM335X' (ROM output)"
    echo "  - End:    'login:' prompt"
    echo ""
    echo "Press Ctrl-C to abort if boot doesn't start in 30 seconds"
    echo ""
    
    # Run grabserial with timestamps
    # -t: show timestamps
    # -m: match string to start timing
    # -q: quit after matching this string
    # -e: elapsed time from match
    grabserial -d "$SERIAL_PORT" -b "$BAUD_RATE" \
        -t \
        -m "U-Boot SPL\|AM335X\|U-Boot 20" \
        -q "login:" \
        --endtime=120 \
        | tee "$OUTPUT_FILE"
    
    echo ""
    log_info "Measurement saved to: $OUTPUT_FILE"
}

measure_with_screen() {
    # Fallback if grabserial not available
    log_info "Starting boot measurement with screen..."
    
    local TIMING_FILE="${OUTPUT_DIR}/timing_${TIMESTAMP}.txt"
    
    echo "Output: $OUTPUT_FILE"
    echo "Timing: $TIMING_FILE"
    echo ""
    echo -e "${YELLOW}>>> Power cycle the BeagleBone Black NOW <<<${NC}"
    echo ""
    echo "Press Ctrl-A, \\ to exit screen when boot completes"
    echo ""
    
    # Use script for timing
    script -t 2>"$TIMING_FILE" "$OUTPUT_FILE" -c "screen $SERIAL_PORT $BAUD_RATE"
    
    log_info "To replay with timing: scriptreplay $TIMING_FILE $OUTPUT_FILE"
}

analyze_log() {
    if [ ! -f "$OUTPUT_FILE" ]; then
        log_warn "Output file not found, skipping analysis"
        return
    fi
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  BOOT TIME ANALYSIS                                        ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Extract key timestamps
    echo "Key boot milestones:"
    echo ""
    
    # U-Boot SPL
    SPL_TIME=$(grep -m1 "U-Boot SPL" "$OUTPUT_FILE" | awk '{print $1}' || echo "N/A")
    echo "  U-Boot SPL:    $SPL_TIME"
    
    # U-Boot proper
    UBOOT_TIME=$(grep -m1 "U-Boot 20" "$OUTPUT_FILE" | awk '{print $1}' || echo "N/A")
    echo "  U-Boot:        $UBOOT_TIME"
    
    # Kernel start
    KERNEL_TIME=$(grep -m1 "Starting kernel" "$OUTPUT_FILE" | awk '{print $1}' || echo "N/A")
    echo "  Kernel start:  $KERNEL_TIME"
    
    # Kernel version line
    VERSION_TIME=$(grep -m1 "Linux version" "$OUTPUT_FILE" | awk '{print $1}' || echo "N/A")
    echo "  Linux version: $VERSION_TIME"
    
    # Init start (kernel timestamps)
    INIT_TIME=$(grep -m1 "Run /.*init" "$OUTPUT_FILE" | grep -oP '\[\s*\K[\d.]+' || echo "N/A")
    echo "  Init start:    ${INIT_TIME}s (kernel time)"
    
    # Login prompt
    LOGIN_TIME=$(grep -m1 "login:" "$OUTPUT_FILE" | awk '{print $1}' || echo "N/A")
    echo "  Login prompt:  $LOGIN_TIME"
    
    echo ""
    
    # Extract kernel initcall info if available
    if grep -q "initcall" "$OUTPUT_FILE"; then
        echo "Top 10 slowest initcalls:"
        grep "initcall.*returned" "$OUTPUT_FILE" | \
            sed 's/.*initcall \([^ ]*\).*after \([0-9]*\) usecs/\2 \1/' | \
            sort -rn | head -10 | \
            awk '{printf "  %8d µs  %s\n", $1, $2}'
        echo ""
    fi
    
    # Count messages by stage
    echo "Messages per stage:"
    echo "  U-Boot:    $(grep -c "^U-Boot\|Hit any key" "$OUTPUT_FILE" 2>/dev/null || echo 0)"
    echo "  Kernel:    $(grep -c '^\[' "$OUTPUT_FILE" 2>/dev/null || echo 0)"
    echo ""
    
    log_info "For detailed analysis, run: ./analyze_boot.sh $OUTPUT_FILE"
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
esac

# Main
echo ""
echo "========================================"
echo " Boot Time Measurement Tool"
echo "========================================"
echo ""

check_prerequisites
create_output_dir
measure_with_grabserial
analyze_log

echo ""
log_info "Measurement complete!"
