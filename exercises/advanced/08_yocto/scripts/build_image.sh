#!/bin/bash
#
# build_image.sh - Build Yocto image for BeagleBone Black
#
# Usage:
#   ./build_image.sh [image] [action]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

IMAGE="${1:-core-image-minimal}"
ACTION="${2:-build}"
YOCTO_DIR="${YOCTO_DIR:-$HOME/yocto-bbb/poky}"
BUILD_DIR="$YOCTO_DIR/build-bbb"

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
Usage: $0 [image] [action]

Build Yocto image for BeagleBone Black.

Images:
    core-image-minimal        Minimal boot image (default)
    core-image-base           Console-only image
    core-image-full-cmdline   Full command-line development image
    bbb-custom-image          Custom BBB image (if created)

Actions:
    build       Build the image (default)
    sdk         Generate SDK
    clean       Clean image
    cleanall    Deep clean (removes sstate)

Environment:
    YOCTO_DIR   Yocto/Poky directory

Example:
    $0 core-image-minimal
    $0 core-image-base sdk
EOF
}

check_environment() {
    if [ ! -d "$YOCTO_DIR" ]; then
        log_error "Yocto directory not found: $YOCTO_DIR"
        echo "Run setup_yocto.sh first or set YOCTO_DIR"
        exit 1
    fi
    
    if [ ! -f "$YOCTO_DIR/oe-init-build-env" ]; then
        log_error "Invalid Yocto directory"
        exit 1
    fi
}

init_environment() {
    log_info "Initializing build environment..."
    
    cd "$YOCTO_DIR"
    
    # Source the environment
    set +e  # Disable exit on error temporarily
    source oe-init-build-env build-bbb > /dev/null 2>&1
    set -e
    
    # Verify we're in the build directory
    if [ ! -f "conf/local.conf" ]; then
        log_error "Build environment not initialized properly"
        exit 1
    fi
}

build_image() {
    log_info "Building image: $IMAGE"
    log_info "This may take several hours on first build..."
    echo ""
    
    local start_time=$(date +%s)
    
    bitbake "$IMAGE"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local mins=$(((duration % 3600) / 60))
    
    echo ""
    log_info "Build complete in ${hours}h ${mins}m"
    show_output
}

build_sdk() {
    log_info "Generating SDK for: $IMAGE"
    log_info "This will take a while..."
    
    bitbake -c populate_sdk "$IMAGE"
    
    log_info "SDK generated"
    ls -la tmp/deploy/sdk/*.sh 2>/dev/null || true
}

clean_image() {
    log_info "Cleaning image: $IMAGE"
    bitbake -c clean "$IMAGE"
    log_info "Clean complete"
}

deep_clean() {
    log_warn "This will remove sstate cache and may significantly increase rebuild time!"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bitbake -c cleanall "$IMAGE"
        log_info "Deep clean complete"
    fi
}

show_output() {
    local images_dir="tmp/deploy/images/beaglebone-yocto"
    
    if [ -d "$images_dir" ]; then
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo "  BUILD OUTPUT"
        echo "════════════════════════════════════════════════════════════"
        echo ""
        echo "Images at: $BUILD_DIR/$images_dir"
        echo ""
        ls -lh "$images_dir"/*.wic.xz 2>/dev/null || true
        ls -lh "$images_dir"/*.ext4 2>/dev/null || true
        ls -lh "$images_dir"/*.dtb 2>/dev/null || true
        ls -lh "$images_dir"/zImage 2>/dev/null || true
        ls -lh "$images_dir"/MLO 2>/dev/null || true
        echo ""
        echo "To flash SD card:"
        local wic_file=$(ls "$images_dir"/*-beaglebone-yocto.wic.xz 2>/dev/null | head -1)
        if [ -n "$wic_file" ]; then
            echo "  xz -dk $wic_file"
            echo "  sudo dd if=${wic_file%.xz} of=/dev/sdX bs=4M status=progress"
        fi
    fi
}

list_images() {
    log_info "Available images:"
    echo ""
    
    bitbake-layers show-recipes 2>/dev/null | grep "^core-image\|^.*-image" | head -20 || \
        echo "  core-image-minimal, core-image-base, core-image-full-cmdline"
}

# ==========================================================================
# MAIN
# ==========================================================================

case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    -l|--list)
        check_environment
        init_environment
        list_images
        exit 0
        ;;
esac

echo ""
echo "========================================"
echo " Yocto Image Builder"
echo "========================================"
echo ""

check_environment
init_environment

case "${ACTION}" in
    build)
        build_image
        ;;
    sdk)
        build_sdk
        ;;
    clean)
        clean_image
        ;;
    cleanall)
        deep_clean
        ;;
    *)
        log_error "Unknown action: $ACTION"
        show_usage
        exit 1
        ;;
esac
