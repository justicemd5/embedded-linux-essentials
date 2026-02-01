#!/bin/bash
#
# deploy_modules.sh - Deploy kernel modules to BeagleBone Black
#
# Usage:
#   ./deploy_modules.sh [TARGET_IP] [MODULE_NAME]
#
# Examples:
#   ./deploy_modules.sh                    # Deploy all to 192.168.7.2
#   ./deploy_modules.sh 10.0.0.50          # Deploy all to 10.0.0.50
#   ./deploy_modules.sh 192.168.7.2 hwinfo # Deploy only hwinfo module

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/../modules"

# Default target IP
TARGET_IP="${1:-192.168.7.2}"
TARGET_USER="debian"
TARGET_PATH="/tmp"

# Specific module (optional)
SPECIFIC_MODULE="${2:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "BeagleBone Black Module Deployment"
echo "=========================================="
echo ""
echo "Target: ${TARGET_USER}@${TARGET_IP}:${TARGET_PATH}"
echo ""

# Check SSH connectivity
echo "Checking SSH connectivity..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes ${TARGET_USER}@${TARGET_IP} echo "Connected" 2>/dev/null; then
    echo -e "${RED}ERROR: Cannot connect to ${TARGET_IP}${NC}"
    echo "Make sure:"
    echo "  1. BBB is connected and booted"
    echo "  2. SSH is enabled on BBB"
    echo "  3. SSH keys are configured (or use ssh-copy-id)"
    exit 1
fi

# Find modules to deploy
if [ -n "${SPECIFIC_MODULE}" ]; then
    MODULES=$(find "${MODULES_DIR}" -name "${SPECIFIC_MODULE}.ko" 2>/dev/null)
    if [ -z "${MODULES}" ]; then
        echo -e "${RED}ERROR: Module not found: ${SPECIFIC_MODULE}.ko${NC}"
        echo "Available modules:"
        find "${MODULES_DIR}" -name "*.ko" -exec basename {} \;
        exit 1
    fi
else
    MODULES=$(find "${MODULES_DIR}" -name "*.ko")
fi

if [ -z "${MODULES}" ]; then
    echo -e "${YELLOW}No modules found to deploy${NC}"
    echo "Run build_all_modules.sh first"
    exit 1
fi

# Deploy modules
DEPLOYED=0
for module in ${MODULES}; do
    module_name=$(basename ${module})
    echo -n "Deploying ${module_name}... "
    
    if scp -q "${module}" "${TARGET_USER}@${TARGET_IP}:${TARGET_PATH}/"; then
        echo -e "${GREEN}✓${NC}"
        DEPLOYED=$((DEPLOYED + 1))
    else
        echo -e "${RED}✗${NC}"
    fi
done

echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo "Deployed ${DEPLOYED} module(s) to ${TARGET_IP}:${TARGET_PATH}"
echo ""
echo "To load modules on BBB, SSH in and run:"
echo "  ssh ${TARGET_USER}@${TARGET_IP}"
echo "  sudo insmod ${TARGET_PATH}/<module>.ko"
echo "  dmesg | tail"
echo ""
echo "Quick commands:"
for module in ${MODULES}; do
    module_name=$(basename ${module} .ko)
    echo "  sudo insmod ${TARGET_PATH}/${module_name}.ko"
done
