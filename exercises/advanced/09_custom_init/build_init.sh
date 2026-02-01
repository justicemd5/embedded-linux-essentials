#!/bin/bash
#
# build_init.sh - Build custom init system
#
# Usage:
#   ./build_init.sh [minimal|advanced|all] [debug]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
BUILD_DIR="$SCRIPT_DIR/build"

# Cross-compiler settings
CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabihf-}"
CC="${CROSS_COMPILE}gcc"
STRIP="${CROSS_COMPILE}strip"

# Build options
CFLAGS="-Wall -Wextra -Werror -Os"
LDFLAGS="-static"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    cat << EOF
Build Custom Init System

Usage: $0 [target] [options]

Targets:
    minimal     Build minimal init (default)
    advanced    Build advanced init with service management
    all         Build all variants

Options:
    debug       Build with debug symbols (no optimization)
    native      Build for host system (testing)

Examples:
    $0                  # Build minimal for ARM
    $0 advanced         # Build advanced for ARM
    $0 all debug        # Build all with debug symbols
    $0 minimal native   # Build minimal for host

Environment:
    CROSS_COMPILE       Cross-compiler prefix (default: arm-linux-gnueabihf-)
EOF
}

check_tools() {
    if ! command -v "$CC" &>/dev/null; then
        log_error "Cross-compiler not found: $CC"
        log_info "Install with: sudo apt install gcc-arm-linux-gnueabihf"
        exit 1
    fi
    
    log_info "Using compiler: $CC"
    $CC --version | head -1
}

setup_build_dir() {
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
}

build_minimal() {
    log_info "Building minimal init..."
    
    $CC $CFLAGS $LDFLAGS -o init "$SRC_DIR/init.c"
    
    if [ "$DEBUG" != "1" ]; then
        $STRIP init
    fi
    
    log_info "Built: $BUILD_DIR/init"
    ls -la init
    file init
}

build_advanced() {
    log_info "Building advanced init..."
    
    # Advanced version needs stdarg.h for variadic macros
    $CC $CFLAGS $LDFLAGS -o init_advanced "$SRC_DIR/init_advanced.c"
    
    if [ "$DEBUG" != "1" ]; then
        $STRIP init_advanced
    fi
    
    log_info "Built: $BUILD_DIR/init_advanced"
    ls -la init_advanced
    file init_advanced
}

build_native() {
    log_info "Building for host system..."
    
    # Use native compiler
    CC="gcc"
    STRIP="strip"
    
    mkdir -p "$BUILD_DIR/native"
    cd "$BUILD_DIR/native"
    
    gcc -Wall -Wextra -O2 -o init "$SRC_DIR/init.c"
    gcc -Wall -Wextra -O2 -o init_advanced "$SRC_DIR/init_advanced.c"
    
    log_info "Built native binaries in $BUILD_DIR/native"
    ls -la
}

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  BUILD COMPLETE"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Build directory: $BUILD_DIR"
    echo ""
    echo "Binaries:"
    ls -lh "$BUILD_DIR"/init* 2>/dev/null || true
    ls -lh "$BUILD_DIR/native"/init* 2>/dev/null || true
    echo ""
    echo "To install to rootfs:"
    echo "  sudo ./install_init.sh /mnt/rootfs"
    echo ""
    echo "Or manually:"
    echo "  sudo cp $BUILD_DIR/init /mnt/rootfs/sbin/init"
    echo ""
}

# ==========================================================================
# MAIN
# ==========================================================================

TARGET="${1:-minimal}"
OPTION="${2:-}"

# Parse options
DEBUG=0
NATIVE=0

for arg in "$@"; do
    case "$arg" in
        debug)
            DEBUG=1
            CFLAGS="-Wall -Wextra -O0 -g"
            log_info "Debug build enabled"
            ;;
        native)
            NATIVE=1
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
    esac
done

case "$TARGET" in
    minimal)
        check_tools
        setup_build_dir
        if [ "$NATIVE" = "1" ]; then
            build_native
        else
            build_minimal
        fi
        ;;
    advanced)
        check_tools
        setup_build_dir
        if [ "$NATIVE" = "1" ]; then
            build_native
        else
            build_advanced
        fi
        ;;
    all)
        check_tools
        setup_build_dir
        if [ "$NATIVE" = "1" ]; then
            build_native
        else
            build_minimal
            build_advanced
        fi
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        log_error "Unknown target: $TARGET"
        show_usage
        exit 1
        ;;
esac

print_summary
