#!/bin/bash
#
# build_all_modules.sh - Build all kernel modules for BeagleBone Black
#
# Prerequisites:
#   - ARM cross-compiler (arm-linux-gnueabihf-gcc)
#   - Linux kernel source tree (configured for BBB)
#
# Usage:
#   ./build_all_modules.sh [KERNEL_DIR]
#
# Environment variables:
#   KERNEL_DIR     - Path to kernel source (default: ~/bbb/linux)
#   CROSS_COMPILE  - Cross-compiler prefix (default: arm-linux-gnueabihf-)
#   ARCH           - Target architecture (default: arm)

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"
KERNEL_DIR="${1:-${KERNEL_DIR:-$HOME/bbb/linux}}"
CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabihf-}"
ARCH="${ARCH:-arm}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "BeagleBone Black Kernel Module Builder"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  KERNEL_DIR:     ${KERNEL_DIR}"
echo "  CROSS_COMPILE:  ${CROSS_COMPILE}"
echo "  ARCH:           ${ARCH}"
echo "  MODULES_DIR:    ${MODULES_DIR}"
echo ""

# Verify kernel directory
if [ ! -d "${KERNEL_DIR}" ]; then
    echo -e "${RED}ERROR: Kernel directory not found: ${KERNEL_DIR}${NC}"
    echo "Please set KERNEL_DIR or pass it as an argument"
    exit 1
fi

if [ ! -f "${KERNEL_DIR}/.config" ]; then
    echo -e "${RED}ERROR: Kernel not configured (.config not found)${NC}"
    echo "Please configure the kernel first:"
    echo "  cd ${KERNEL_DIR}"
    echo "  make ARCH=arm omap2plus_defconfig"
    exit 1
fi

# Verify cross-compiler
if ! command -v ${CROSS_COMPILE}gcc &> /dev/null; then
    echo -e "${RED}ERROR: Cross-compiler not found: ${CROSS_COMPILE}gcc${NC}"
    echo "Please install ARM cross-compiler:"
    echo "  sudo apt install gcc-arm-linux-gnueabihf"
    exit 1
fi

# Find all module directories
MODULE_DIRS=$(find "${MODULES_DIR}" -name "Makefile" -exec dirname {} \;)

if [ -z "${MODULE_DIRS}" ]; then
    echo -e "${YELLOW}WARNING: No module directories found${NC}"
    exit 0
fi

# Build each module
FAILED=0
BUILT=0

for dir in ${MODULE_DIRS}; do
    module_name=$(basename "${dir}")
    echo ""
    echo -e "${YELLOW}Building: ${module_name}${NC}"
    echo "  Directory: ${dir}"
    
    if make -C "${dir}" \
        KERNEL_DIR="${KERNEL_DIR}" \
        CROSS_COMPILE="${CROSS_COMPILE}" \
        ARCH="${ARCH}" \
        2>&1 | sed 's/^/    /'; then
        
        # Find the .ko file
        ko_file=$(find "${dir}" -name "*.ko" | head -1)
        if [ -n "${ko_file}" ]; then
            echo -e "  ${GREEN}✓ Built: $(basename ${ko_file})${NC}"
            BUILT=$((BUILT + 1))
        else
            echo -e "  ${RED}✗ No .ko file produced${NC}"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "  ${RED}✗ Build failed${NC}"
        FAILED=$((FAILED + 1))
    fi
done

# Summary
echo ""
echo "=========================================="
echo "Build Summary"
echo "=========================================="
echo -e "  ${GREEN}Built:  ${BUILT}${NC}"
echo -e "  ${RED}Failed: ${FAILED}${NC}"

# List all .ko files
echo ""
echo "Generated modules:"
find "${MODULES_DIR}" -name "*.ko" -exec echo "  {}" \;

# Optional: copy all modules to a staging directory
STAGING_DIR="${SCRIPT_DIR}/staging"
if [ "$2" == "--stage" ]; then
    mkdir -p "${STAGING_DIR}"
    find "${MODULES_DIR}" -name "*.ko" -exec cp {} "${STAGING_DIR}/" \;
    echo ""
    echo "Modules staged to: ${STAGING_DIR}"
fi

exit ${FAILED}
