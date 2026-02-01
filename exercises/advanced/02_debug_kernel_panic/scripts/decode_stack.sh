#!/bin/bash
#
# decode_stack.sh - Decode kernel stack trace with symbols
#
# Usage:
#   ./decode_stack.sh <vmlinux> <stack_trace_file>
#
# Prerequisites:
#   - vmlinux with debug symbols
#   - addr2line from cross-compiler

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <vmlinux> <stack_trace_file>"
    echo ""
    echo "Example:"
    echo "  ./decode_stack.sh ~/bbb/linux/vmlinux stack.txt"
    exit 1
fi

VMLINUX="$1"
STACK_FILE="$2"
ADDR2LINE="arm-linux-gnueabihf-addr2line"

if [ ! -f "${VMLINUX}" ]; then
    echo "ERROR: vmlinux not found: ${VMLINUX}"
    exit 1
fi

if [ ! -f "${STACK_FILE}" ]; then
    echo "ERROR: Stack file not found: ${STACK_FILE}"
    exit 1
fi

if ! command -v "${ADDR2LINE}" &>/dev/null; then
    echo "ERROR: ${ADDR2LINE} not found"
    echo "Install with: sudo apt install binutils-arm-linux-gnueabihf"
    exit 1
fi

echo "=========================================="
echo "     Stack Trace Decoder"
echo "=========================================="
echo ""
echo "vmlinux: ${VMLINUX}"
echo "Stack file: ${STACK_FILE}"
echo ""

# Extract addresses from stack trace
# Format: [<c0123456>] or just c0123456
ADDRESSES=$(grep -oE '\[?<?(c0[0-9a-f]{6})>?\]?' "${STACK_FILE}" | \
            sed 's/[<>\[\]]//g' | sort -u)

if [ -z "${ADDRESSES}" ]; then
    echo "No kernel addresses found in stack trace"
    echo "Expected format: [<c0123456>] or c0123456"
    exit 1
fi

echo "Decoded stack trace:"
echo "===================="
echo ""

for addr in ${ADDRESSES}; do
    # Add 0x prefix for addr2line
    RESULT=$("${ADDR2LINE}" -f -e "${VMLINUX}" "0x${addr}" 2>/dev/null)
    if [ -n "${RESULT}" ]; then
        FUNC=$(echo "${RESULT}" | head -1)
        FILE=$(echo "${RESULT}" | tail -1)
        printf "0x%s: %s\n" "${addr}" "${FUNC}"
        printf "         %s\n" "${FILE}"
        echo ""
    fi
done

echo "===================="
echo "Decoding complete."
