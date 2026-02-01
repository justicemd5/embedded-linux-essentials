#!/bin/bash
#
# apply_rt_patch.sh - Apply PREEMPT_RT patch to Linux kernel
#
# Downloads and applies the PREEMPT_RT patch for BeagleBone Black
#
# Usage:
#   ./apply_rt_patch.sh [kernel_version]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

# Configuration
KERNEL_VERSION="${1:-6.6}"
KERNEL_DIR="${KERNEL_DIR:-$HOME/bbb/linux}"
PATCH_URL_BASE="https://cdn.kernel.org/pub/linux/kernel/projects/rt"

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

show_usage() {
    cat << EOF
Usage: $0 [kernel_version]

Apply PREEMPT_RT patch to Linux kernel.

Arguments:
    kernel_version  Kernel version (e.g., 6.6, 5.15) - default: 6.6

Environment variables:
    KERNEL_DIR      Path to kernel source (default: ~/bbb/linux)

Example:
    $0 6.6
    KERNEL_DIR=/path/to/linux $0 5.15
EOF
}

check_kernel_dir() {
    if [ ! -d "$KERNEL_DIR" ]; then
        log_error "Kernel directory not found: $KERNEL_DIR"
        log_info "Set KERNEL_DIR environment variable or clone kernel source first"
        exit 1
    fi
    
    if [ ! -f "$KERNEL_DIR/Makefile" ]; then
        log_error "Not a valid kernel source directory: $KERNEL_DIR"
        exit 1
    fi
    
    log_info "Using kernel source: $KERNEL_DIR"
}

detect_kernel_version() {
    if [ -f "$KERNEL_DIR/Makefile" ]; then
        VERSION=$(grep "^VERSION" "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
        PATCHLEVEL=$(grep "^PATCHLEVEL" "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
        SUBLEVEL=$(grep "^SUBLEVEL" "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
        
        DETECTED="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"
        log_info "Detected kernel version: $DETECTED"
        
        KERNEL_VERSION="${VERSION}.${PATCHLEVEL}"
    fi
}

find_rt_patch() {
    local major_minor="$1"
    
    log_info "Searching for RT patch for kernel $major_minor..."
    
    # Try to find the patch
    PATCH_DIR="${major_minor}"
    PATCH_URL="${PATCH_URL_BASE}/${PATCH_DIR}/"
    
    # Get patch listing
    PATCH_LIST=$(curl -s "$PATCH_URL" | grep -oP 'patch-[^"<]+\.patch\.xz' | sort -V | tail -1)
    
    if [ -z "$PATCH_LIST" ]; then
        log_error "No RT patch found for kernel $major_minor"
        log_info "Available versions at: $PATCH_URL_BASE"
        exit 1
    fi
    
    PATCH_FILE="$PATCH_LIST"
    FULL_PATCH_URL="${PATCH_URL}${PATCH_FILE}"
    
    log_info "Found patch: $PATCH_FILE"
}

download_patch() {
    local download_dir="$KERNEL_DIR/rt-patch"
    mkdir -p "$download_dir"
    
    PATCH_PATH="$download_dir/$PATCH_FILE"
    
    if [ -f "$PATCH_PATH" ]; then
        log_info "Patch already downloaded: $PATCH_PATH"
    else
        log_info "Downloading RT patch..."
        curl -L -o "$PATCH_PATH" "$FULL_PATCH_URL"
        log_info "Downloaded to: $PATCH_PATH"
    fi
}

apply_patch() {
    cd "$KERNEL_DIR"
    
    # Check if already patched
    if grep -q "PREEMPT_RT" Makefile 2>/dev/null || \
       grep -q "CONFIG_PREEMPT_RT" arch/arm/configs/omap2plus_defconfig 2>/dev/null; then
        log_warn "Kernel appears to already have RT patches applied"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    log_info "Applying RT patch..."
    
    # Extract and apply
    if [[ "$PATCH_PATH" == *.xz ]]; then
        xzcat "$PATCH_PATH" | patch -p1 --dry-run > /dev/null 2>&1 || {
            log_error "Patch dry-run failed. Patch may not be compatible."
            exit 1
        }
        xzcat "$PATCH_PATH" | patch -p1
    elif [[ "$PATCH_PATH" == *.gz ]]; then
        zcat "$PATCH_PATH" | patch -p1
    else
        patch -p1 < "$PATCH_PATH"
    fi
    
    log_info "RT patch applied successfully!"
}

configure_rt() {
    cd "$KERNEL_DIR"
    
    log_info "Configuring kernel for RT..."
    
    # Start with OMAP2 defconfig for BBB
    make ARCH=arm omap2plus_defconfig
    
    # Apply RT-specific configuration
    cat >> .config << 'EOF'
# PREEMPT_RT Configuration
CONFIG_PREEMPT_RT=y
CONFIG_HIGH_RES_TIMERS=y
CONFIG_NO_HZ_FULL=y
CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y

# Debug features (optional, disable for production)
# CONFIG_DEBUG_PREEMPT=y
# CONFIG_PREEMPT_TRACER=y
# CONFIG_IRQSOFF_TRACER=y
EOF
    
    # Update config
    make ARCH=arm olddefconfig
    
    log_info "Configuration updated for PREEMPT_RT"
}

print_next_steps() {
    echo ""
    echo "========================================"
    echo "  RT PATCH APPLIED SUCCESSFULLY"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Review configuration:"
    echo "   cd $KERNEL_DIR"
    echo "   make ARCH=arm menuconfig"
    echo "   # General Setup -> Preemption Model -> Fully Preemptible (RT)"
    echo ""
    echo "2. Build the kernel:"
    echo "   make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j\$(nproc)"
    echo "   make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- dtbs"
    echo "   make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- modules"
    echo ""
    echo "3. Copy to SD card:"
    echo "   sudo cp arch/arm/boot/zImage /mnt/boot/"
    echo "   sudo cp arch/arm/boot/dts/am335x-boneblack.dtb /mnt/boot/"
    echo "   sudo make ARCH=arm modules_install INSTALL_MOD_PATH=/mnt/rootfs"
    echo ""
    echo "4. Verify RT kernel after boot:"
    echo "   uname -a  # Should show -rt in version"
    echo ""
}

# ==========================================================================
# MAIN
# ==========================================================================

case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
esac

echo ""
echo "========================================"
echo " PREEMPT_RT Patch Application Script"
echo "========================================"
echo ""

check_kernel_dir
detect_kernel_version
find_rt_patch "$KERNEL_VERSION"
download_patch
apply_patch
configure_rt
print_next_steps
