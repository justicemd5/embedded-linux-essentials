#!/bin/bash
#
# test_init.sh - Test custom init in isolated environment
#
# This script uses unshare/chroot to test init without needing
# actual hardware. Note: Not a perfect simulation of PID 1!
#
# Author: Embedded Linux Labs
# License: MIT

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    cat << EOF
Test Custom Init System

Usage: $0 <rootfs_path>

This creates a minimal test environment to exercise init.

Note: This is NOT a true PID 1 test - the real init won't
work correctly without being actual PID 1. This is for
basic functionality testing only.

For real testing:
  1. Build a complete rootfs
  2. Boot on BeagleBone or QEMU

EOF
}

create_test_rootfs() {
    local rootfs="$1"
    
    log_info "Creating test rootfs in $rootfs..."
    
    sudo mkdir -p "$rootfs"/{bin,sbin,etc,proc,sys,dev,tmp,run,var/log,lib}
    
    # Copy essential binaries from host
    if command -v busybox &>/dev/null; then
        sudo cp "$(which busybox)" "$rootfs/bin/"
        # Create symlinks
        for cmd in sh ls cat echo mount umount mkdir chmod; do
            sudo ln -sf busybox "$rootfs/bin/$cmd"
        done
    fi
    
    # Copy init
    if [ -f "$SCRIPT_DIR/build/init" ]; then
        sudo cp "$SCRIPT_DIR/build/init" "$rootfs/sbin/"
    elif [ -f "$SCRIPT_DIR/src/init.native" ]; then
        sudo cp "$SCRIPT_DIR/src/init.native" "$rootfs/sbin/init"
    else
        log_error "No init binary found. Run ./build_init.sh native first"
        exit 1
    fi
    
    # Create hostname
    echo "test-system" | sudo tee "$rootfs/etc/hostname" > /dev/null
    
    # Create rcS script
    sudo mkdir -p "$rootfs/etc/init.d"
    cat << 'SCRIPT' | sudo tee "$rootfs/etc/init.d/rcS" > /dev/null
#!/bin/sh
echo "Test startup script running..."
echo "Hostname: $(hostname)"
echo "Date: $(date)"
SCRIPT
    sudo chmod +x "$rootfs/etc/init.d/rcS"
    
    log_info "Test rootfs created"
}

run_test() {
    local rootfs="$1"
    
    log_warn "This test simulates init but cannot truly test PID 1 behavior"
    log_info "Starting test..."
    
    # Use unshare to create new namespaces
    sudo unshare --mount --uts --ipc --pid --fork \
        chroot "$rootfs" /sbin/init
}

# ==========================================================================
# MAIN
# ==========================================================================

if [ $# -lt 1 ]; then
    # Create temporary test rootfs
    TEMP_ROOTFS=$(mktemp -d)
    trap "sudo rm -rf $TEMP_ROOTFS" EXIT
    
    log_warn "No rootfs specified, creating temporary one at $TEMP_ROOTFS"
    create_test_rootfs "$TEMP_ROOTFS"
    run_test "$TEMP_ROOTFS"
else
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            if [ ! -d "$1/sbin" ]; then
                log_warn "Creating test rootfs at $1"
                create_test_rootfs "$1"
            fi
            run_test "$1"
            ;;
    esac
fi
