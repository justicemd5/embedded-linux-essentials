#!/bin/bash
#
# capture_crash.sh - Capture kernel crash via serial console
#
# Usage:
#   ./capture_crash.sh [/dev/ttyACM0] [output_file]
#
# This script uses screen or picocom to capture serial output
# and saves it to a file for later analysis.

SERIAL_PORT="${1:-/dev/ttyACM0}"
OUTPUT_FILE="${2:-crash_$(date +%Y%m%d_%H%M%S).log}"
BAUD_RATE="115200"

echo "=========================================="
echo "     Kernel Crash Capture"
echo "=========================================="
echo ""
echo "Serial port: ${SERIAL_PORT}"
echo "Output file: ${OUTPUT_FILE}"
echo "Baud rate:   ${BAUD_RATE}"
echo ""

# Check if serial port exists
if [ ! -e "${SERIAL_PORT}" ]; then
    echo "ERROR: Serial port ${SERIAL_PORT} not found"
    echo ""
    echo "Available serial ports:"
    ls -la /dev/tty{USB,ACM}* 2>/dev/null || echo "  None found"
    echo ""
    echo "For BBB USB serial:"
    echo "  - Connect USB cable to BBB debug port"
    echo "  - Port is usually /dev/ttyACM0"
    exit 1
fi

# Check permissions
if [ ! -r "${SERIAL_PORT}" ]; then
    echo "ERROR: Cannot read ${SERIAL_PORT}"
    echo "Try: sudo usermod -aG dialout $USER"
    echo "Then log out and back in"
    exit 1
fi

echo "Choose capture method:"
echo "  1) screen (with logging)"
echo "  2) picocom (with logging)"
echo "  3) cat (simple capture)"
echo ""
read -p "Selection [1]: " METHOD
METHOD="${METHOD:-1}"

case "${METHOD}" in
    1)
        # Screen with logging
        echo ""
        echo "Starting screen with logging to ${OUTPUT_FILE}"
        echo "Exit with: Ctrl-A, then \\"
        echo ""
        echo "Press Enter to start..."
        read
        screen -L -Logfile "${OUTPUT_FILE}" "${SERIAL_PORT}" "${BAUD_RATE}"
        ;;
    2)
        # Picocom with logging
        if ! command -v picocom &>/dev/null; then
            echo "picocom not installed. Install with: sudo apt install picocom"
            exit 1
        fi
        echo ""
        echo "Starting picocom with logging to ${OUTPUT_FILE}"
        echo "Exit with: Ctrl-A, then Ctrl-X"
        echo ""
        echo "Press Enter to start..."
        read
        picocom -b "${BAUD_RATE}" --logfile "${OUTPUT_FILE}" "${SERIAL_PORT}"
        ;;
    3)
        # Simple cat capture
        echo ""
        echo "Starting simple capture to ${OUTPUT_FILE}"
        echo "Exit with: Ctrl-C"
        echo ""
        stty -F "${SERIAL_PORT}" "${BAUD_RATE}" cs8 -cstopb -parenb
        cat "${SERIAL_PORT}" | tee "${OUTPUT_FILE}"
        ;;
    *)
        echo "Invalid selection"
        exit 1
        ;;
esac

echo ""
echo "Capture saved to: ${OUTPUT_FILE}"
echo "Analyze with: ./analyze_oops.sh ${OUTPUT_FILE}"
