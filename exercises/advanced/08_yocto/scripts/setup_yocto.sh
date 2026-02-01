#!/bin/bash
#
# setup_yocto.sh - Download and setup Yocto/Poky for BeagleBone Black
#
# Usage:
#   ./setup_yocto.sh [release] [target_dir]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

RELEASE="${1:-scarthgap}"
TARGET_DIR="${2:-$HOME/yocto-bbb}"

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
Usage: $0 [release] [target_dir]

Download and setup Yocto Project for BeagleBone Black.

Arguments:
    release     Yocto release name (default: scarthgap)
    target_dir  Installation directory (default: ~/yocto-bbb)

Available releases:
    scarthgap   (4.0, LTS until Apr 2026)
    nanbield    (4.3)
    kirkstone   (4.0 LTS, until Apr 2026)

Example:
    $0 scarthgap ~/yocto-bbb
EOF
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing=()
    
    # Essential tools
    for cmd in git python3 gcc g++ make chrpath cpio diffstat; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  sudo apt install gawk wget git diffstat unzip texinfo gcc \\"
        echo "      build-essential chrpath socat cpio python3 python3-pip \\"
        echo "      python3-pexpect xz-utils debianutils iputils-ping \\"
        echo "      python3-git python3-jinja2 libegl1-mesa libsdl1.2-dev \\"
        echo "      pylint xterm python3-subunit mesa-common-dev zstd liblz4-tool"
        exit 1
    fi
    
    log_info "Dependencies OK"
}

check_disk_space() {
    log_info "Checking disk space..."
    
    local required_gb=100
    local avail_gb=$(df "$HOME" --output=avail -BG | tail -1 | tr -d 'G ')
    
    if [ "$avail_gb" -lt "$required_gb" ]; then
        log_warn "Low disk space: ${avail_gb}GB available"
        log_warn "Yocto builds require ${required_gb}GB+ for full build"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        log_info "Disk space OK: ${avail_gb}GB available"
    fi
}

check_memory() {
    log_info "Checking memory..."
    
    local total_mem=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}')
    
    if [ "$total_mem" -lt 8 ]; then
        log_warn "Low memory: ${total_mem}GB RAM"
        log_warn "Recommend 16GB+ for Yocto builds"
    else
        log_info "Memory OK: ${total_mem}GB RAM"
    fi
}

clone_poky() {
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"
    
    if [ -d "poky" ]; then
        log_info "Poky already exists, updating..."
        cd poky
        git fetch origin
        git checkout "$RELEASE"
        cd ..
    else
        log_info "Cloning Poky (${RELEASE} branch)..."
        git clone -b "$RELEASE" git://git.yoctoproject.org/poky.git
    fi
    
    log_info "Poky ready at: $TARGET_DIR/poky"
}

clone_layers() {
    cd "$TARGET_DIR/poky"
    
    # meta-ti for BeagleBone support
    if [ -d "meta-ti" ]; then
        log_info "meta-ti exists, updating..."
        cd meta-ti && git fetch origin && git checkout "$RELEASE" 2>/dev/null || true && cd ..
    else
        log_info "Cloning meta-ti..."
        git clone -b "$RELEASE" git://git.yoctoproject.org/meta-ti.git || \
            git clone -b master git://git.yoctoproject.org/meta-ti.git
    fi
    
    # meta-openembedded for additional packages
    if [ -d "meta-openembedded" ]; then
        log_info "meta-openembedded exists, updating..."
        cd meta-openembedded && git fetch origin && git checkout "$RELEASE" && cd ..
    else
        log_info "Cloning meta-openembedded..."
        git clone -b "$RELEASE" git://git.openembedded.org/meta-openembedded
    fi
}

create_custom_layer() {
    local layer_dir="$TARGET_DIR/poky/meta-bbb-custom"
    
    log_info "Creating custom layer..."
    
    mkdir -p "$layer_dir"/{conf,recipes-core/images,recipes-app/myapp/files,recipes-kernel/linux/files}
    
    # layer.conf
    cat > "$layer_dir/conf/layer.conf" << EOF
# Custom BeagleBone Black Layer
# Layer created by setup_yocto.sh

BBPATH .= ":\${LAYERDIR}"

BBFILES += "\${LAYERDIR}/recipes-*/*/*.bb \\
            \${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "meta-bbb-custom"
BBFILE_PATTERN_meta-bbb-custom = "^\${LAYERDIR}/"
BBFILE_PRIORITY_meta-bbb-custom = "10"

LAYERDEPENDS_meta-bbb-custom = "core"
LAYERSERIES_COMPAT_meta-bbb-custom = "${RELEASE}"
EOF
    
    log_info "Custom layer created at: $layer_dir"
}

create_build_directory() {
    local build_dir="$TARGET_DIR/poky/build-bbb"
    
    log_info "Creating build directory..."
    
    cd "$TARGET_DIR/poky"
    
    # Source environment without actually initializing
    mkdir -p "$build_dir/conf"
    
    # local.conf
    cat > "$build_dir/conf/local.conf" << 'EOF'
#
# BeagleBone Black Yocto Configuration
# Generated by setup_yocto.sh
#

# Machine Selection
MACHINE = "beaglebone-yocto"

# Parallelization - adjust for your system
# Use number of CPU cores for both
BB_NUMBER_THREADS ?= "${@oe.utils.cpu_count()}"
PARALLEL_MAKE ?= "-j ${@oe.utils.cpu_count()}"

# Download and cache directories (shared between builds)
DL_DIR = "${TOPDIR}/../downloads"
SSTATE_DIR = "${TOPDIR}/../sstate-cache"

# Disk space monitoring
BB_DISKMON_DIRS ??= "\
    STOPTASKS,${TMPDIR},1G,100K \
    STOPTASKS,${DL_DIR},1G,100K \
    STOPTASKS,${SSTATE_DIR},1G,100K \
    ABORT,${TMPDIR},100M,1K \
    ABORT,${DL_DIR},100M,1K \
    ABORT,${SSTATE_DIR},100M,1K"

# Package management format
PACKAGE_CLASSES ?= "package_ipk"

# Extra image features
EXTRA_IMAGE_FEATURES ?= "debug-tweaks ssh-server-dropbear tools-debug"

# Filesystem types to generate
IMAGE_FSTYPES = "tar.xz ext4 wic.xz"

# Additional packages for all images
IMAGE_INSTALL:append = " i2c-tools devmem2 htop strace"

# License handling
LICENSE_FLAGS_ACCEPTED = "commercial"

# Hash equivalence (speeds up builds)
BB_SIGNATURE_HANDLER = "OEEquivHash"

# Useful for debugging
#INHERIT += "rm_work"  # Remove work directories to save space
#BB_NUMBER_PARSE_THREADS = "4"  # Reduce if low memory
EOF
    
    # bblayers.conf
    cat > "$build_dir/conf/bblayers.conf" << EOF
# POKY_BBLAYERS_CONF_VERSION is increased each time build/conf/bblayers.conf
# changes incompatibly
POKY_BBLAYERS_CONF_VERSION = "2"

BBPATH = "\${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \\
  \${TOPDIR}/../meta \\
  \${TOPDIR}/../meta-poky \\
  \${TOPDIR}/../meta-yocto-bsp \\
  \${TOPDIR}/../meta-openembedded/meta-oe \\
  \${TOPDIR}/../meta-openembedded/meta-python \\
  \${TOPDIR}/../meta-openembedded/meta-networking \\
  \${TOPDIR}/../meta-bbb-custom \\
  "

# Note: meta-ti layers can be added if needed:
#  \${TOPDIR}/../meta-ti/meta-ti-bsp \\
EOF
    
    log_info "Build directory ready at: $build_dir"
}

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  YOCTO SETUP COMPLETE"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Directory: $TARGET_DIR"
    echo "Release:   $RELEASE"
    echo ""
    echo "Getting started:"
    echo ""
    echo "  cd $TARGET_DIR/poky"
    echo "  source oe-init-build-env build-bbb"
    echo ""
    echo "  # Build minimal image (1-2 hours first time)"
    echo "  bitbake core-image-minimal"
    echo ""
    echo "  # Or build development image"
    echo "  bitbake core-image-full-cmdline"
    echo ""
    echo "Output will be in:"
    echo "  build-bbb/tmp/deploy/images/beaglebone-yocto/"
    echo ""
    echo "Useful commands:"
    echo "  bitbake-layers show-layers          # Show active layers"
    echo "  bitbake-layers show-recipes | less  # List all recipes"
    echo "  bitbake -c menuconfig virtual/kernel  # Configure kernel"
    echo "  bitbake -c populate_sdk <image>     # Generate SDK"
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
echo " Yocto Project Setup for BeagleBone Black"
echo "========================================"
echo ""
echo "Release: ${RELEASE}"
echo "Target:  ${TARGET_DIR}"
echo ""

check_dependencies
check_disk_space
check_memory
clone_poky
clone_layers
create_custom_layer
create_build_directory
print_summary
