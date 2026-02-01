#!/bin/bash
#
# analyze_oops.sh - Parse and analyze kernel oops messages
#
# Usage:
#   ./analyze_oops.sh crash.log [module.ko]
#
# This script extracts key information from kernel oops output
# and helps identify the crash location.

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <crash_log> [module.ko]"
    echo ""
    echo "Example:"
    echo "  ./analyze_oops.sh crash.log buggy.ko"
    exit 1
fi

CRASH_LOG="$1"
MODULE_KO="${2:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "     Kernel Oops Analyzer"
echo "=========================================="
echo ""
echo "Analyzing: ${CRASH_LOG}"
echo ""

# Check if file exists
if [ ! -f "${CRASH_LOG}" ]; then
    echo -e "${RED}ERROR: File not found: ${CRASH_LOG}${NC}"
    exit 1
fi

# Extract error type
echo -e "${BLUE}=== Error Type ===${NC}"
grep -E "(Unable to handle|Internal error|Oops|BUG:|kernel panic)" "${CRASH_LOG}" | head -5 || echo "No specific error type found"
echo ""

# Extract PC (Program Counter)
echo -e "${BLUE}=== Crash Location ===${NC}"
PC_LINE=$(grep -E "PC is at|pc :" "${CRASH_LOG}" | head -1)
if [ -n "${PC_LINE}" ]; then
    echo "${PC_LINE}"
    
    # Extract function and offset
    if [[ "${PC_LINE}" =~ "PC is at" ]]; then
        FUNCTION=$(echo "${PC_LINE}" | sed 's/.*PC is at \([^+]*\)+.*/\1/')
        OFFSET=$(echo "${PC_LINE}" | sed 's/.*+\(0x[0-9a-f]*\).*/\1/')
        echo "  Function: ${FUNCTION}"
        echo "  Offset:   ${OFFSET}"
    fi
else
    echo "PC not found in log"
fi
echo ""

# Extract registers
echo -e "${BLUE}=== CPU Registers ===${NC}"
grep -E "^r[0-9]+|^sp|^lr|^pc" "${CRASH_LOG}" | head -10 || echo "Registers not found"
echo ""

# Look for NULL pointers in registers
echo -e "${BLUE}=== NULL Pointer Analysis ===${NC}"
if grep -q "00000000" "${CRASH_LOG}"; then
    echo "Potential NULL pointers found in registers:"
    grep -E "^r[0-9]+" "${CRASH_LOG}" | grep "00000000" | head -5 || true
else
    echo "No obvious NULL pointers in registers"
fi
echo ""

# Extract call stack
echo -e "${BLUE}=== Call Stack ===${NC}"
grep -A20 "Call trace:" "${CRASH_LOG}" 2>/dev/null || \
grep -A20 "Backtrace:" "${CRASH_LOG}" 2>/dev/null || \
grep -E "^\[<[0-9a-f]+>\]" "${CRASH_LOG}" | head -10 || \
echo "Call stack not found"
echo ""

# Extract module list
echo -e "${BLUE}=== Loaded Modules ===${NC}"
grep "Modules linked in:" "${CRASH_LOG}" | head -1 || echo "Module list not found"
echo ""

# If module.ko provided, do addr2line
if [ -n "${MODULE_KO}" ] && [ -f "${MODULE_KO}" ]; then
    echo -e "${BLUE}=== Module Analysis ===${NC}"
    echo "Module: ${MODULE_KO}"
    
    # Extract offset from PC line if available
    if [ -n "${OFFSET}" ]; then
        echo ""
        echo "Attempting addr2line at offset ${OFFSET}..."
        
        # Try addr2line with cross-compiler
        if command -v arm-linux-gnueabihf-addr2line &>/dev/null; then
            arm-linux-gnueabihf-addr2line -e "${MODULE_KO}" -f "${OFFSET}" 2>/dev/null || \
                echo "addr2line failed (module may lack debug symbols)"
        else
            echo "arm-linux-gnueabihf-addr2line not found"
        fi
        
        echo ""
        echo "Disassembly around crash point:"
        if command -v arm-linux-gnueabihf-objdump &>/dev/null; then
            arm-linux-gnueabihf-objdump -d "${MODULE_KO}" | grep -A5 -B5 "${OFFSET#0x}" 2>/dev/null || \
                echo "Could not find offset in disassembly"
        fi
    fi
fi

# Summary
echo ""
echo -e "${BLUE}=== Analysis Summary ===${NC}"

# Determine likely cause
if grep -q "NULL pointer dereference" "${CRASH_LOG}"; then
    echo -e "${YELLOW}Likely cause: NULL pointer dereference${NC}"
    echo "  - Check if pointers are validated before use"
    echo "  - Look for uninitialized pointers"
    echo "  - Check memory allocation return values"
elif grep -q "use-after-free" "${CRASH_LOG}"; then
    echo -e "${YELLOW}Likely cause: Use after free${NC}"
    echo "  - Memory accessed after kfree()"
    echo "  - Set pointers to NULL after freeing"
elif grep -q "stack overflow" "${CRASH_LOG}"; then
    echo -e "${YELLOW}Likely cause: Stack overflow${NC}"
    echo "  - Check for unbounded recursion"
    echo "  - Reduce large local variables"
elif grep -q "divide error" "${CRASH_LOG}"; then
    echo -e "${YELLOW}Likely cause: Division by zero${NC}"
    echo "  - Validate divisors before division"
else
    echo "Could not determine specific cause"
    echo "Review the crash location and registers manually"
fi

echo ""
echo -e "${GREEN}Analysis complete.${NC}"
