#!/bin/bash
# =============================================================================
# Embedded Linux Essentials - Docker Entrypoint
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║           EMBEDDED LINUX ESSENTIALS - Development Environment             ║"
echo "╠═══════════════════════════════════════════════════════════════════════════╣"
echo "║  Target: BeagleBone Black Rev C (AM335x Cortex-A8)                        ║"
echo "║  Cross-Compiler: arm-linux-gnueabihf-gcc                                  ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Display environment info
echo -e "${GREEN}Environment Variables:${NC}"
echo "  ARCH=$ARCH"
echo "  CROSS_COMPILE=$CROSS_COMPILE"
echo ""

# Verify toolchain
echo -e "${GREEN}Cross-Compiler Version:${NC}"
arm-linux-gnueabihf-gcc --version | head -1
echo ""

# Check if we need to start services (requires --privileged)
if [ "$START_SERVICES" = "true" ]; then
    echo -e "${YELLOW}Starting network services...${NC}"
    
    # Start TFTP server
    if command -v in.tftpd &> /dev/null; then
        sudo service tftpd-hpa start 2>/dev/null || echo "  TFTP: Could not start (requires --privileged)"
    fi
    
    # Start NFS server
    if command -v rpc.nfsd &> /dev/null; then
        sudo service nfs-kernel-server start 2>/dev/null || echo "  NFS: Could not start (requires --privileged)"
    fi
    
    echo ""
fi

# Check for serial device access
if [ -e /dev/ttyACM0 ]; then
    echo -e "${GREEN}Serial Device Detected:${NC} /dev/ttyACM0 (BeagleBone Black)"
elif [ -e /dev/ttyUSB0 ]; then
    echo -e "${GREEN}Serial Device Detected:${NC} /dev/ttyUSB0"
else
    echo -e "${YELLOW}Note:${NC} No serial device detected. For serial access, run with:"
    echo "  docker run -it --privileged -v /dev:/dev ..."
fi
echo ""

# Display quick help
echo -e "${GREEN}Quick Commands:${NC}"
echo "  arm-gcc --version      # Check cross-compiler"
echo "  picocom -b 115200 /dev/ttyACM0  # Connect to BBB serial"
echo "  cd /workspace          # Go to workspace"
echo ""

echo -e "${GREEN}Lab Directories:${NC}"
if [ -d "/workspace/01_boot_flow" ]; then
    echo "  /workspace/01_boot_flow    - Boot Flow Lab"
    echo "  /workspace/02_uboot        - U-Boot Lab"
    echo "  /workspace/03_kernel       - Kernel Lab"
    echo "  /workspace/exercises       - Exercises"
else
    echo "  Mount your repository: -v \$(pwd):/workspace"
fi
echo ""

echo -e "${BLUE}Ready for embedded Linux development!${NC}"
echo "────────────────────────────────────────────────────────────────────────────"
echo ""

# Execute the command passed to the container
exec "$@"
