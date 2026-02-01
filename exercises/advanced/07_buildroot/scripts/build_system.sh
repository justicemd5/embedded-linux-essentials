#!/bin/bash
#
# build_system.sh - Build complete Buildroot system
#
# Usage:
#   ./build_system.sh [target]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

TARGET="${1:-all}"
BUILDROOT_DIR="${BUILDROOT_DIR:-$HOME/bbb-buildroot/buildroot-2024.02}"
EXTERNAL_DIR="${EXTERNAL_DIR:-$HOME/bbb-buildroot/bbb-external}"
LOG_FILE="build_$(date +%Y%m%d_%H%M%S).log"

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
Usage: $0 [target]

Build Buildroot system for BeagleBone Black.

Targets:
    all             Full build (default)
    menuconfig      Configure build
    linux-menuconfig  Configure kernel
    linux-rebuild   Rebuild kernel only
    uboot-rebuild   Rebuild U-Boot only
    rootfs          Regenerate root filesystem
    clean           Clean build
    distclean       Full clean (including downloads)

Environment:
    BUILDROOT_DIR   Buildroot source directory
    EXTERNAL_DIR    External tree directory

Example:
    $0 all              # Full build
    $0 linux-rebuild    # Just rebuild kernel
EOF
}

check_buildroot() {
    if [ ! -d "$BUILDROOT_DIR" ]; then
        log_error "Buildroot not found at: $BUILDROOT_DIR"
        echo "Run setup_buildroot.sh first or set BUILDROOT_DIR"
        exit 1
    fi
    
    if [ ! -f "$BUILDROOT_DIR/Makefile" ]; then
        log_error "Invalid Buildroot directory"
        exit 1
    fi
    
    log_info "Using Buildroot: $BUILDROOT_DIR"
}

check_config() {
    if [ ! -f "$BUILDROOT_DIR/.config" ]; then
        log_warn "No configuration found"
        echo ""
        echo "Configure first with one of:"
        echo "  make beaglebone_defconfig"
        echo "  make BR2_EXTERNAL=$EXTERNAL_DIR bbb_custom_defconfig"
        echo ""
        exit 1
    fi
}

build_all() {
    log_info "Starting full build..."
    log_info "Log file: $LOG_FILE"
    
    cd "$BUILDROOT_DIR"
    
    # Check for external tree
    local make_cmd="make"
    if [ -d "$EXTERNAL_DIR" ] && [ -f "$EXTERNAL_DIR/external.desc" ]; then
        make_cmd="make BR2_EXTERNAL=$EXTERNAL_DIR"
        log_info "Using external tree: $EXTERNAL_DIR"
    fi
    
    local start_time=$(date +%s)
    
    echo "Build started at $(date)"
    $make_cmd -j$(nproc) 2>&1 | tee "$LOG_FILE"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local mins=$(((duration % 3600) / 60))
    local secs=$((duration % 60))
    
    echo ""
    log_info "Build complete in ${hours}h ${mins}m ${secs}s"
    log_info "Output in: $BUILDROOT_DIR/output/images/"
}

rebuild_linux() {
    log_info "Rebuilding Linux kernel..."
    
    cd "$BUILDROOT_DIR"
    make linux-rebuild
    make
    
    log_info "Kernel rebuild complete"
    ls -la output/images/zImage output/images/am335x-boneblack.dtb
}

rebuild_uboot() {
    log_info "Rebuilding U-Boot..."
    
    cd "$BUILDROOT_DIR"
    make uboot-rebuild
    make
    
    log_info "U-Boot rebuild complete"
    ls -la output/images/MLO output/images/u-boot.img
}

regenerate_rootfs() {
    log_info "Regenerating root filesystem..."
    
    cd "$BUILDROOT_DIR"
    rm -rf output/images/rootfs.*
    make
    
    log_info "Rootfs regenerated"
    ls -la output/images/rootfs.*
}

do_clean() {
    log_info "Cleaning build..."
    
    cd "$BUILDROOT_DIR"
    make clean
    
    log_info "Clean complete"
}

do_distclean() {
    log_warn "This will remove all build output and configuration!"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$BUILDROOT_DIR"
        make distclean
        log_info "Distclean complete"
    else
        log_info "Cancelled"
    fi
}

show_config() {
    log_info "Current configuration:"
    echo ""
    
    cd "$BUILDROOT_DIR"
    
    if [ -f .config ]; then
        echo "Target architecture:"
        grep "^BR2_ARCH=" .config || true
        
        echo ""
        echo "Kernel:"
        grep "^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE" .config || true
        
        echo ""
        echo "U-Boot:"
        grep "^BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE" .config || true
        
        echo ""
        echo "Root filesystem size:"
        grep "^BR2_TARGET_ROOTFS_EXT2_SIZE" .config || true
    else
        log_warn "No configuration found"
    fi
}

# ==========================================================================
# MAIN
# ==========================================================================

case "${TARGET}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    all)
        check_buildroot
        check_config
        build_all
        ;;
    menuconfig)
        check_buildroot
        cd "$BUILDROOT_DIR"
        if [ -d "$EXTERNAL_DIR" ]; then
            make BR2_EXTERNAL="$EXTERNAL_DIR" menuconfig
        else
            make menuconfig
        fi
        ;;
    linux-menuconfig)
        check_buildroot
        check_config
        cd "$BUILDROOT_DIR"
        make linux-menuconfig
        ;;
    linux-rebuild)
        check_buildroot
        check_config
        rebuild_linux
        ;;
    uboot-rebuild)
        check_buildroot
        check_config
        rebuild_uboot
        ;;
    rootfs)
        check_buildroot
        check_config
        regenerate_rootfs
        ;;
    clean)
        check_buildroot
        do_clean
        ;;
    distclean)
        check_buildroot
        do_distclean
        ;;
    config|status)
        check_buildroot
        show_config
        ;;
    *)
        log_error "Unknown target: $TARGET"
        show_usage
        exit 1
        ;;
esac
