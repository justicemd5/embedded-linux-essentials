#!/bin/bash
#
# install_init.sh - Install custom init to rootfs
#
# Usage:
#   ./install_init.sh /path/to/rootfs
#
# Author: Embedded Linux Labs
# License: MIT

set -e

ROOTFS="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
ROOTFS_DIR="$SCRIPT_DIR/rootfs"

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
Usage: $0 /path/to/rootfs

Install custom init system to mounted rootfs.

Arguments:
    /path/to/rootfs   Path to mounted root filesystem

Example:
    sudo mount /dev/sdb2 /mnt
    $0 /mnt
    sudo umount /mnt
EOF
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_rootfs() {
    if [ -z "$ROOTFS" ]; then
        show_usage
        exit 1
    fi
    
    if [ ! -d "$ROOTFS" ]; then
        log_error "Rootfs not found: $ROOTFS"
        exit 1
    fi
    
    # Check if it looks like a rootfs
    if [ ! -d "$ROOTFS/sbin" ] && [ ! -d "$ROOTFS/bin" ]; then
        log_warn "Path doesn't look like a rootfs: $ROOTFS"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

build_init() {
    log_info "Building custom init..."
    
    cd "$SRC_DIR"
    make clean
    make
    
    if [ ! -f "init" ]; then
        log_error "Build failed"
        exit 1
    fi
    
    log_info "Build successful"
}

backup_original() {
    if [ -f "$ROOTFS/sbin/init" ]; then
        log_info "Backing up original init..."
        cp "$ROOTFS/sbin/init" "$ROOTFS/sbin/init.backup"
    fi
}

install_init() {
    log_info "Installing custom init..."
    
    # Create directories
    mkdir -p "$ROOTFS/sbin"
    mkdir -p "$ROOTFS/etc/init.d"
    
    # Install init binary
    cp "$SRC_DIR/init" "$ROOTFS/sbin/init"
    chmod 755 "$ROOTFS/sbin/init"
    
    log_info "Installed: /sbin/init"
}

install_scripts() {
    log_info "Installing startup scripts..."
    
    # Install rcS
    cp "$ROOTFS_DIR/etc/init.d/rcS" "$ROOTFS/etc/init.d/"
    chmod 755 "$ROOTFS/etc/init.d/rcS"
    log_info "  Installed: /etc/init.d/rcS"
    
    # Install other scripts
    for script in "$ROOTFS_DIR/etc/init.d/S"*; do
        if [ -f "$script" ]; then
            name=$(basename "$script")
            cp "$script" "$ROOTFS/etc/init.d/"
            chmod 755 "$ROOTFS/etc/init.d/$name"
            log_info "  Installed: /etc/init.d/$name"
        fi
    done
}

install_commands() {
    log_info "Installing shutdown commands..."
    
    mkdir -p "$ROOTFS/sbin"
    
    # Install halt and reboot
    cp "$ROOTFS_DIR/sbin/halt" "$ROOTFS/sbin/"
    cp "$ROOTFS_DIR/sbin/reboot" "$ROOTFS/sbin/"
    chmod 755 "$ROOTFS/sbin/halt"
    chmod 755 "$ROOTFS/sbin/reboot"
    
    # Create symlinks
    ln -sf halt "$ROOTFS/sbin/poweroff" 2>/dev/null || true
    ln -sf reboot "$ROOTFS/sbin/shutdown" 2>/dev/null || true
    
    log_info "  Installed: halt, reboot, poweroff, shutdown"
}

create_hostname() {
    if [ ! -f "$ROOTFS/etc/hostname" ]; then
        echo "beaglebone" > "$ROOTFS/etc/hostname"
        log_info "Created /etc/hostname"
    fi
}

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  CUSTOM INIT INSTALLED"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Installed to: $ROOTFS"
    echo ""
    echo "Files installed:"
    ls -la "$ROOTFS/sbin/init" "$ROOTFS/sbin/halt" "$ROOTFS/sbin/reboot"
    echo ""
    echo "Startup scripts:"
    ls "$ROOTFS/etc/init.d/"
    echo ""
    echo "To restore original init:"
    echo "  mv $ROOTFS/sbin/init.backup $ROOTFS/sbin/init"
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
echo " Custom Init System Installer"
echo "========================================"
echo ""

check_root
check_rootfs
build_init
backup_original
install_init
install_scripts
install_commands
create_hostname
print_summary
