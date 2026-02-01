#!/bin/bash
#
# setup_buildroot.sh - Download and setup Buildroot for BeagleBone Black
#
# Usage:
#   ./setup_buildroot.sh [version] [target_dir]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

VERSION="${1:-2024.02}"
TARGET_DIR="${2:-$HOME/bbb-buildroot}"

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
Usage: $0 [version] [target_dir]

Download and setup Buildroot for BeagleBone Black.

Arguments:
    version     Buildroot version (default: 2024.02)
    target_dir  Installation directory (default: ~/bbb-buildroot)

Example:
    $0 2024.02 ~/buildroot-bbb
EOF
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing=()
    
    for cmd in wget tar make gcc g++ patch; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  sudo apt install build-essential wget"
        exit 1
    fi
    
    # Check for Buildroot required packages
    log_info "Checking Buildroot dependencies..."
    
    local buildroot_deps="which sed make bash gzip bzip2 perl tar cpio unzip rsync bc"
    for dep in $buildroot_deps; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Some Buildroot dependencies may be missing: ${missing[*]}"
        echo "Install with:"
        echo "  sudo apt install sed make bash bzip2 perl cpio unzip rsync bc"
    fi
    
    log_info "Dependencies OK"
}

check_disk_space() {
    log_info "Checking disk space..."
    
    local required_gb=15
    local target_mount=$(df "$HOME" --output=avail -h | tail -1 | tr -d ' ')
    local avail_gb=$(df "$HOME" --output=avail -BG | tail -1 | tr -d 'G ')
    
    if [ "$avail_gb" -lt "$required_gb" ]; then
        log_warn "Low disk space: ${avail_gb}GB available, ${required_gb}GB recommended"
    else
        log_info "Disk space OK: ${avail_gb}GB available"
    fi
}

download_buildroot() {
    local url="https://buildroot.org/downloads/buildroot-${VERSION}.tar.gz"
    local tarball="buildroot-${VERSION}.tar.gz"
    
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"
    
    if [ -f "$tarball" ]; then
        log_info "Tarball already exists: $tarball"
    else
        log_info "Downloading Buildroot ${VERSION}..."
        wget --progress=bar:force "$url" -O "$tarball" || {
            log_error "Download failed. Check version and internet connection."
            echo "Available versions: https://buildroot.org/downloads/"
            exit 1
        }
    fi
    
    if [ -d "buildroot-${VERSION}" ]; then
        log_info "Already extracted: buildroot-${VERSION}"
    else
        log_info "Extracting..."
        tar xzf "$tarball"
    fi
    
    log_info "Buildroot ready at: $TARGET_DIR/buildroot-${VERSION}"
}

create_external_tree() {
    local ext_dir="$TARGET_DIR/bbb-external"
    
    log_info "Creating external tree at: $ext_dir"
    
    mkdir -p "$ext_dir"/{board/bbb,configs,package/myapp}
    
    # External descriptor
    cat > "$ext_dir/external.desc" << 'EOF'
name: BBB_EXTERNAL
desc: Custom BeagleBone Black External Tree
EOF
    
    # Config.in
    cat > "$ext_dir/Config.in" << 'EOF'
# Custom packages for BeagleBone Black
# Add package Config.in files here

menu "Custom BBB Packages"
    source "$BR2_EXTERNAL_BBB_EXTERNAL_PATH/package/myapp/Config.in"
endmenu
EOF
    
    # External makefile
    cat > "$ext_dir/external.mk" << 'EOF'
# Include all package makefiles
include $(sort $(wildcard $(BR2_EXTERNAL_BBB_EXTERNAL_PATH)/package/*/*.mk))
EOF
    
    # Sample package Config.in
    cat > "$ext_dir/package/myapp/Config.in" << 'EOF'
config BR2_PACKAGE_MYAPP
    bool "myapp"
    depends on BR2_USE_WCHAR
    help
      My custom application for BeagleBone Black.
      
      This is an example package demonstrating how to
      add custom applications to Buildroot.

      https://example.com/myapp
EOF
    
    # Sample package makefile
    cat > "$ext_dir/package/myapp/myapp.mk" << 'EOF'
################################################################################
#
# myapp - Example custom package for BeagleBone Black
#
################################################################################

MYAPP_VERSION = 1.0.0
MYAPP_SITE = $(BR2_EXTERNAL_BBB_EXTERNAL_PATH)/package/myapp/src
MYAPP_SITE_METHOD = local
MYAPP_LICENSE = MIT
MYAPP_LICENSE_FILES = LICENSE

# Dependencies (adjust as needed)
# MYAPP_DEPENDENCIES = libgpiod

define MYAPP_BUILD_CMDS
    $(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)
endef

define MYAPP_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0755 $(@D)/myapp $(TARGET_DIR)/usr/bin/myapp
endef

$(eval $(generic-package))
EOF
    
    # Sample package source
    mkdir -p "$ext_dir/package/myapp/src"
    
    cat > "$ext_dir/package/myapp/src/myapp.c" << 'EOF'
/*
 * myapp.c - Example application for BeagleBone Black
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>

#define VERSION "1.0.0"

void print_system_info(void) {
    FILE *fp;
    char buffer[256];
    
    printf("\n=== BeagleBone Black System Info ===\n\n");
    
    /* Hostname */
    if (gethostname(buffer, sizeof(buffer)) == 0) {
        printf("Hostname: %s\n", buffer);
    }
    
    /* Kernel version */
    fp = fopen("/proc/version", "r");
    if (fp) {
        if (fgets(buffer, sizeof(buffer), fp)) {
            printf("Kernel: %.60s...\n", buffer);
        }
        fclose(fp);
    }
    
    /* CPU info */
    fp = fopen("/proc/cpuinfo", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strncmp(buffer, "model name", 10) == 0 ||
                strncmp(buffer, "Hardware", 8) == 0) {
                printf("%s", buffer);
            }
        }
        fclose(fp);
    }
    
    /* Memory */
    fp = fopen("/proc/meminfo", "r");
    if (fp) {
        if (fgets(buffer, sizeof(buffer), fp)) {
            printf("%s", buffer);
        }
        fclose(fp);
    }
    
    /* Uptime */
    fp = fopen("/proc/uptime", "r");
    if (fp) {
        double uptime;
        if (fscanf(fp, "%lf", &uptime) == 1) {
            int hours = (int)uptime / 3600;
            int mins = ((int)uptime % 3600) / 60;
            int secs = (int)uptime % 60;
            printf("Uptime: %dh %dm %ds\n", hours, mins, secs);
        }
        fclose(fp);
    }
    
    printf("\n");
}

int main(int argc, char *argv[]) {
    printf("myapp version %s\n", VERSION);
    printf("Custom BeagleBone Black Application\n");
    
    if (argc > 1 && strcmp(argv[1], "-i") == 0) {
        print_system_info();
    } else {
        printf("Use -i flag for system info\n");
    }
    
    return 0;
}
EOF
    
    cat > "$ext_dir/package/myapp/src/Makefile" << 'EOF'
CC ?= gcc
CFLAGS ?= -Wall -O2
LDFLAGS ?=

TARGET = myapp
SRCS = myapp.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(TARGET) $(OBJS)

.PHONY: all clean
EOF
    
    cat > "$ext_dir/package/myapp/src/LICENSE" << 'EOF'
MIT License

Copyright (c) 2024 Embedded Linux Labs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
    
    log_info "External tree created at: $ext_dir"
}

create_board_files() {
    local board_dir="$TARGET_DIR/bbb-external/board/bbb"
    
    log_info "Creating board files..."
    
    # Rootfs overlay
    mkdir -p "$board_dir/rootfs_overlay/etc"
    
    cat > "$board_dir/rootfs_overlay/etc/motd" << 'EOF'

  ____                   _      ____                  
 | __ )  ___  __ _  __ _| | ___| __ )  ___  _ __   ___
 |  _ \ / _ \/ _` |/ _` | |/ _ \  _ \ / _ \| '_ \ / _ \
 | |_) |  __/ (_| | (_| | |  __/ |_) | (_) | | | |  __/
 |____/ \___|\__,_|\__, |_|\___|____/ \___/|_| |_|\___|
                   |___/                               
              ____  _            _    
             | __ )| | __ _  ___| | __
             |  _ \| |/ _` |/ __| |/ /
             | |_) | | (_| | (__|   < 
             |____/|_|\__,_|\___|_|\_\

    Custom Buildroot System for BeagleBone Black
    
EOF
    
    # Post-build script
    cat > "$board_dir/post_build.sh" << 'EOF'
#!/bin/bash
#
# post_build.sh - Buildroot post-build hook
#
# Arguments:
#   $1 = Target directory (where rootfs is being built)

TARGET_DIR=$1

echo "=== Running post-build script ==="

# Create custom init script
cat > "$TARGET_DIR/etc/init.d/S99custom" << 'INIT'
#!/bin/sh
#
# S99custom - Custom startup script
#

case "$1" in
    start)
        echo "Starting custom services..."
        
        # Set LED heartbeat
        if [ -d /sys/class/leds/beaglebone:green:heartbeat ]; then
            echo heartbeat > /sys/class/leds/beaglebone:green:heartbeat/trigger
        fi
        
        # Log boot completion
        echo "$(date): System boot complete" >> /var/log/boot.log
        ;;
        
    stop)
        echo "Stopping custom services..."
        ;;
        
    restart)
        $0 stop
        $0 start
        ;;
        
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
INIT

chmod +x "$TARGET_DIR/etc/init.d/S99custom"

# Create useful aliases
cat >> "$TARGET_DIR/etc/profile" << 'PROFILE'

# Custom aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# BBB specific
alias gpioinfo='cat /sys/kernel/debug/gpio'
alias i2cdetect0='i2cdetect -y -r 0'
alias i2cdetect1='i2cdetect -y -r 1'
alias i2cdetect2='i2cdetect -y -r 2'

PROFILE

echo "=== Post-build complete ==="
EOF
    
    chmod +x "$board_dir/post_build.sh"
    
    # Post-image script
    cat > "$board_dir/post_image.sh" << 'EOF'
#!/bin/bash
#
# post_image.sh - Buildroot post-image hook
#
# Arguments:
#   $1 = Images directory

IMAGES_DIR=$1
BOARD_DIR=$(dirname $0)

echo "=== Running post-image script ==="

# Create SD card image
if command -v genimage &> /dev/null; then
    echo "Creating SD card image..."
    # genimage --config "$BOARD_DIR/genimage.cfg" \
    #     --rootpath "$TARGET_DIR" \
    #     --inputpath "$IMAGES_DIR" \
    #     --outputpath "$IMAGES_DIR"
fi

# Generate checksums
echo "Generating checksums..."
cd "$IMAGES_DIR"
sha256sum MLO u-boot.img zImage am335x-boneblack.dtb rootfs.ext4 > SHA256SUMS 2>/dev/null || true

echo "=== Post-image complete ==="
EOF
    
    chmod +x "$board_dir/post_image.sh"
    
    log_info "Board files created"
}

create_defconfig() {
    local configs_dir="$TARGET_DIR/bbb-external/configs"
    
    log_info "Creating custom defconfig..."
    
    cat > "$configs_dir/bbb_custom_defconfig" << 'EOF'
# BeagleBone Black Custom Configuration
# Created by setup_buildroot.sh

# Target Architecture
BR2_arm=y
BR2_cortex_a8=y
BR2_ARM_EABIHF=y
BR2_ARM_FPU_VFPV3=y

# Toolchain
BR2_TOOLCHAIN_BUILDROOT_GLIBC=y
BR2_TOOLCHAIN_BUILDROOT_CXX=y

# Build options
BR2_CCACHE=y
BR2_CCACHE_DIR="/tmp/buildroot-ccache"

# System Configuration
BR2_TARGET_GENERIC_HOSTNAME="bbb"
BR2_TARGET_GENERIC_ISSUE="Welcome to BeagleBone Black"
BR2_SYSTEM_BIN_SH_BASH=y
BR2_ENABLE_LOCALE_PURGE=y
BR2_TARGET_GENERIC_ROOT_PASSWD="root"
BR2_TARGET_TZ_INFO=y

# Kernel
BR2_LINUX_KERNEL=y
BR2_LINUX_KERNEL_CUSTOM_VERSION=y
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.6.28"
BR2_LINUX_KERNEL_USE_DEFCONFIG=y
BR2_LINUX_KERNEL_DEFCONFIG="omap2plus"
BR2_LINUX_KERNEL_ZIMAGE=y
BR2_LINUX_KERNEL_DTS_SUPPORT=y
BR2_LINUX_KERNEL_INTREE_DTS_NAME="am335x-boneblack"

# Bootloader
BR2_TARGET_UBOOT=y
BR2_TARGET_UBOOT_BUILD_SYSTEM_KCONFIG=y
BR2_TARGET_UBOOT_CUSTOM_VERSION=y
BR2_TARGET_UBOOT_CUSTOM_VERSION_VALUE="2024.01"
BR2_TARGET_UBOOT_BOARD_DEFCONFIG="am335x_evm"
BR2_TARGET_UBOOT_FORMAT_IMG=y
BR2_TARGET_UBOOT_SPL=y
BR2_TARGET_UBOOT_SPL_NAME="MLO"

# Filesystem
BR2_TARGET_ROOTFS_EXT2=y
BR2_TARGET_ROOTFS_EXT2_4=y
BR2_TARGET_ROOTFS_EXT2_SIZE="256M"
BR2_TARGET_ROOTFS_TAR=y

# Essential packages
BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y
BR2_PACKAGE_BASH=y
BR2_PACKAGE_HTOP=y
BR2_PACKAGE_STRACE=y
BR2_PACKAGE_I2C_TOOLS=y
BR2_PACKAGE_DEVMEM2=y
BR2_PACKAGE_DROPBEAR=y
BR2_PACKAGE_OPENSSH=y
BR2_PACKAGE_IPERF3=y

# Python (optional - increases build time)
# BR2_PACKAGE_PYTHON3=y
# BR2_PACKAGE_PYTHON_PIP=y

# External tree settings
# BR2_ROOTFS_OVERLAY="$(BR2_EXTERNAL_BBB_EXTERNAL_PATH)/board/bbb/rootfs_overlay"
# BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_BBB_EXTERNAL_PATH)/board/bbb/post_build.sh"
# BR2_ROOTFS_POST_IMAGE_SCRIPT="$(BR2_EXTERNAL_BBB_EXTERNAL_PATH)/board/bbb/post_image.sh"
EOF
    
    log_info "Defconfig created at: $configs_dir/bbb_custom_defconfig"
}

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  BUILDROOT SETUP COMPLETE"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Buildroot:     $TARGET_DIR/buildroot-${VERSION}"
    echo "External tree: $TARGET_DIR/bbb-external"
    echo ""
    echo "Quick start:"
    echo ""
    echo "  cd $TARGET_DIR/buildroot-${VERSION}"
    echo ""
    echo "  # Option 1: Use BeagleBone defconfig"
    echo "  make beaglebone_defconfig"
    echo ""
    echo "  # Option 2: Use custom defconfig with external tree"
    echo "  make BR2_EXTERNAL=$TARGET_DIR/bbb-external bbb_custom_defconfig"
    echo ""
    echo "  # Configure"
    echo "  make menuconfig"
    echo ""
    echo "  # Build (takes 30-90 minutes)"
    echo "  make -j\$(nproc)"
    echo ""
    echo "Output will be in: output/images/"
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
echo " Buildroot Setup for BeagleBone Black"
echo "========================================"
echo ""
echo "Version: ${VERSION}"
echo "Target:  ${TARGET_DIR}"
echo ""

check_dependencies
check_disk_space
download_buildroot
create_external_tree
create_board_files
create_defconfig
print_summary
