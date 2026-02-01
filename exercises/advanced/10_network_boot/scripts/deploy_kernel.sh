#!/bin/bash
#
# deploy_kernel.sh - Deploy kernel and modules to network boot server
#
# Quick deployment of kernel, DTB, and modules to TFTP and NFS
#
# Usage:
#   ./deploy_kernel.sh [kernel_source_dir]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

# ==========================================================================
# CONFIGURATION
# ==========================================================================

KERNEL_DIR="${1:-$(pwd)}"
TFTP_ROOT="${TFTP_ROOT:-/tftpboot}"
NFS_ROOT="${NFS_ROOT:-/export/bbb-root}"

CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabihf-}"
ARCH="arm"

# Target board
DTB_NAME="${DTB_NAME:-am335x-boneblack.dtb}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==========================================================================
# FUNCTIONS
# ==========================================================================

check_kernel_dir() {
    if [ ! -f "$KERNEL_DIR/Makefile" ]; then
        log_error "Not a kernel source directory: $KERNEL_DIR"
        exit 1
    fi
    
    if ! grep -q "^VERSION" "$KERNEL_DIR/Makefile"; then
        log_error "Invalid kernel Makefile"
        exit 1
    fi
    
    # Get kernel version
    KERNEL_VERSION=$(make -s -C "$KERNEL_DIR" kernelversion 2>/dev/null || echo "unknown")
    log_info "Kernel version: $KERNEL_VERSION"
}

check_build() {
    local zimage="$KERNEL_DIR/arch/arm/boot/zImage"
    local dtb="$KERNEL_DIR/arch/arm/boot/dts/$DTB_NAME"
    
    if [ ! -f "$zimage" ]; then
        log_error "zImage not found. Build kernel first:"
        log_info "  make ARCH=arm CROSS_COMPILE=$CROSS_COMPILE zImage"
        exit 1
    fi
    
    if [ ! -f "$dtb" ]; then
        log_error "DTB not found: $dtb"
        log_info "Build device tree:"
        log_info "  make ARCH=arm CROSS_COMPILE=$CROSS_COMPILE dtbs"
        exit 1
    fi
    
    log_info "Found zImage: $(ls -lh "$zimage" | awk '{print $5}')"
    log_info "Found DTB: $DTB_NAME"
}

check_directories() {
    if [ ! -d "$TFTP_ROOT" ]; then
        log_error "TFTP directory not found: $TFTP_ROOT"
        log_info "Run setup_server.sh first"
        exit 1
    fi
    
    if [ ! -d "$NFS_ROOT" ]; then
        log_error "NFS root not found: $NFS_ROOT"
        log_info "Run setup_server.sh first"
        exit 1
    fi
}

backup_old_files() {
    local backup_dir="$TFTP_ROOT/backup"
    mkdir -p "$backup_dir"
    
    if [ -f "$TFTP_ROOT/zImage" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        cp "$TFTP_ROOT/zImage" "$backup_dir/zImage.$timestamp"
        cp "$TFTP_ROOT/$DTB_NAME" "$backup_dir/$DTB_NAME.$timestamp" 2>/dev/null || true
        log_info "Previous kernel backed up to $backup_dir"
        
        # Keep only last 5 backups
        ls -t "$backup_dir"/zImage.* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    fi
}

deploy_kernel() {
    log_info "Deploying kernel to TFTP..."
    
    cp "$KERNEL_DIR/arch/arm/boot/zImage" "$TFTP_ROOT/"
    chmod 644 "$TFTP_ROOT/zImage"
    
    log_info "Deployed: $TFTP_ROOT/zImage"
}

deploy_dtb() {
    log_info "Deploying device tree..."
    
    # Copy main DTB
    cp "$KERNEL_DIR/arch/arm/boot/dts/$DTB_NAME" "$TFTP_ROOT/"
    chmod 644 "$TFTP_ROOT/$DTB_NAME"
    
    # Also copy overlays if present
    local overlay_dir="$KERNEL_DIR/arch/arm/boot/dts/overlays"
    if [ -d "$overlay_dir" ]; then
        mkdir -p "$TFTP_ROOT/overlays"
        cp "$overlay_dir"/*.dtbo "$TFTP_ROOT/overlays/" 2>/dev/null || true
        log_info "Deployed overlays to $TFTP_ROOT/overlays/"
    fi
    
    log_info "Deployed: $TFTP_ROOT/$DTB_NAME"
}

deploy_modules() {
    log_info "Deploying kernel modules to NFS..."
    
    # Install modules
    make -C "$KERNEL_DIR" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" \
        INSTALL_MOD_PATH="$NFS_ROOT" modules_install
    
    # Run depmod
    local mod_dir="$NFS_ROOT/lib/modules/$KERNEL_VERSION"
    if [ -d "$mod_dir" ]; then
        log_info "Running depmod..."
        depmod -a -b "$NFS_ROOT" "$KERNEL_VERSION" 2>/dev/null || true
    fi
    
    log_info "Modules installed to $NFS_ROOT/lib/modules/"
}

deploy_system_map() {
    log_info "Deploying System.map..."
    
    if [ -f "$KERNEL_DIR/System.map" ]; then
        cp "$KERNEL_DIR/System.map" "$NFS_ROOT/boot/"
        log_info "Deployed: $NFS_ROOT/boot/System.map"
    fi
}

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  DEPLOYMENT COMPLETE"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Kernel Version: $KERNEL_VERSION"
    echo ""
    echo "Files deployed:"
    echo "  TFTP:"
    ls -lh "$TFTP_ROOT/zImage" "$TFTP_ROOT/$DTB_NAME" 2>/dev/null
    echo ""
    echo "  Modules:"
    ls -d "$NFS_ROOT/lib/modules/$KERNEL_VERSION" 2>/dev/null || echo "  (no modules)"
    echo ""
    echo "Reset BeagleBone to boot with new kernel."
    echo ""
}

# ==========================================================================
# MAIN
# ==========================================================================

show_usage() {
    cat << EOF
Deploy Kernel to Network Boot Server

Usage: $0 [OPTIONS] [KERNEL_DIR]

Options:
    -h, --help          Show this help
    -k, --kernel-only   Deploy kernel and DTB only (no modules)
    -m, --modules-only  Deploy modules only
    -b, --no-backup     Skip backup of old files

Environment Variables:
    TFTP_ROOT       TFTP directory (default: /tftpboot)
    NFS_ROOT        NFS root directory (default: /export/bbb-root)
    CROSS_COMPILE   Cross compiler prefix (default: arm-linux-gnueabihf-)
    DTB_NAME        Device tree blob name (default: am335x-boneblack.dtb)

Examples:
    $0                          # Deploy from current directory
    $0 ~/linux                  # Deploy from ~/linux
    $0 --kernel-only ~/linux    # Only deploy kernel, skip modules
EOF
}

KERNEL_ONLY=0
MODULES_ONLY=0
NO_BACKUP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -k|--kernel-only)
            KERNEL_ONLY=1
            shift
            ;;
        -m|--modules-only)
            MODULES_ONLY=1
            shift
            ;;
        -b|--no-backup)
            NO_BACKUP=1
            shift
            ;;
        *)
            KERNEL_DIR="$1"
            shift
            ;;
    esac
done

echo ""
log_info "Deploying kernel to network boot server..."
echo ""

check_kernel_dir
check_build
check_directories

if [ "$MODULES_ONLY" -eq 0 ]; then
    [ "$NO_BACKUP" -eq 0 ] && backup_old_files
    deploy_kernel
    deploy_dtb
fi

if [ "$KERNEL_ONLY" -eq 0 ]; then
    deploy_modules
fi

deploy_system_map
print_summary
