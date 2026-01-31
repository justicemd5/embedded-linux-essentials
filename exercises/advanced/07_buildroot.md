# Exercise 7: Buildroot System

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Build a complete, minimal embedded Linux system from source using Buildroot for the BeagleBone Black.

## Prerequisites

- Linux development host with 50GB+ free space
- 8GB+ RAM recommended
- Internet connection for downloading sources
- Basic understanding of cross-compilation

## Difficulty: ⭐⭐⭐ Advanced

---

## What is Buildroot?

```
┌─────────────────────────────────────────────────────────────┐
│                    BUILDROOT OVERVIEW                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Buildroot is a tool that builds:                           │
│                                                             │
│  ┌───────────────┐                                          │
│  │ Cross-Compiler│ ◄── Toolchain for target architecture   │
│  └───────┬───────┘                                          │
│          │                                                  │
│          ▼                                                  │
│  ┌───────────────┐                                          │
│  │   Bootloader  │ ◄── U-Boot for your board               │
│  └───────┬───────┘                                          │
│          │                                                  │
│          ▼                                                  │
│  ┌───────────────┐                                          │
│  │    Kernel     │ ◄── Linux kernel + DTB                  │
│  └───────┬───────┘                                          │
│          │                                                  │
│          ▼                                                  │
│  ┌───────────────┐                                          │
│  │   Root FS     │ ◄── BusyBox + selected packages         │
│  └───────────────┘                                          │
│                                                             │
│  All from source, all reproducible!                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Guide

### Step 1: Download Buildroot

```bash
cd ~
mkdir bbb-buildroot && cd bbb-buildroot

# Download latest LTS release
wget https://buildroot.org/downloads/buildroot-2024.02.tar.gz
tar xzf buildroot-2024.02.tar.gz
cd buildroot-2024.02
```

### Step 2: Configure for BeagleBone Black

```bash
# List available defconfigs
make list-defconfigs | grep beagle

# Use BeagleBone defconfig as starting point
make beaglebone_defconfig

# Customize configuration
make menuconfig
```

### Step 3: Essential Configuration Options

Navigate through menuconfig:

```
Target options --->
    Target Architecture: ARM (little endian)
    Target Architecture Variant: cortex-A8
    Target ABI: EABIhf
    Floating point strategy: VFPv3-D16

Build options --->
    ($(HOME)/bbb-buildroot/dl) Download directory
    [*] Enable compiler cache
    (/tmp/buildroot-ccache) Compiler cache location

Toolchain --->
    Toolchain type: Buildroot toolchain
    C library: glibc (or musl for smaller size)
    [*] Enable C++ support
    [*] Build cross gdb for host

System configuration --->
    (bbb) System hostname
    (Welcome to BeagleBone Black!) System banner
    Init system: BusyBox (or systemd for full features)
    /dev management: Dynamic using devtmpfs + mdev
    [*] Enable root login with password
    (root) Root password

Kernel --->
    [*] Linux Kernel
    Kernel version: Latest version (6.6.x)
    Defconfig name: omap2plus
    Kernel binary format: zImage
    [*] Build a Device Tree Blob
    (am335x-boneblack) Device Tree Source file names

Target packages --->
    (see below for package selection)

Filesystem images --->
    [*] ext2/3/4 root filesystem
        ext2/3/4 variant: ext4
        (200M) exact size
    [*] tar the root filesystem

Bootloaders --->
    [*] U-Boot
    Build system: Kconfig
    U-Boot Version: 2024.01
    Board defconfig: am335x_evm
    U-Boot binary format: u-boot.img
    [*] Install U-Boot SPL binary image
```

### Step 4: Select Target Packages

```
Target packages --->
    BusyBox --->
        [*] Show packages that are also provided by busybox

    Debugging, profiling and benchmark --->
        [*] strace
        [*] htop
    
    Development tools --->
        [*] git
        [*] make
    
    Hardware handling --->
        [*] i2c-tools
        [*] can-utils (if using CAN)
        [*] devmem2
    
    Interpreter languages --->
        [*] python3
            [*] pip
    
    Libraries --->
        Crypto --->
            [*] openssl
    
    Networking applications --->
        [*] dropbear (SSH server)
        [*] hostapd (if WiFi AP needed)
        [*] iperf3
        [*] openssh (alternative to dropbear)
    
    Shell and utilities --->
        [*] bash
        [*] file
        [*] sudo
    
    System tools --->
        [*] htop
        [*] util-linux
```

### Step 5: Build Everything

```bash
# Start build (takes 30-90 minutes first time)
make -j$(nproc)

# Or build with logging
make -j$(nproc) 2>&1 | tee build.log
```

### Step 6: Examine Build Output

```bash
ls -la output/images/
# Expected:
# am335x-boneblack.dtb    - Device tree blob
# MLO                     - First stage bootloader (SPL)
# rootfs.ext4             - Root filesystem image
# rootfs.tar              - Root filesystem tarball
# u-boot.img              - U-Boot proper
# zImage                  - Linux kernel
```

### Step 7: Create SD Card

```bash
# Automated script
cat > create_sd.sh << 'SCRIPT'
#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 /dev/sdX"
    exit 1
fi

DEVICE=$1
IMAGES=output/images

# Safety check
if mount | grep -q "$DEVICE"; then
    echo "Device is mounted! Unmount first."
    exit 1
fi

# Create partitions
sudo parted -s $DEVICE mklabel msdos
sudo parted -s $DEVICE mkpart primary fat32 1MiB 64MiB
sudo parted -s $DEVICE mkpart primary ext4 64MiB 100%
sudo parted -s $DEVICE set 1 boot on

# Wait for kernel to recognize partitions
sleep 2

# Format
sudo mkfs.vfat -F 32 -n BOOT ${DEVICE}1
sudo mkfs.ext4 -L rootfs ${DEVICE}2

# Mount
sudo mkdir -p /mnt/{boot,rootfs}
sudo mount ${DEVICE}1 /mnt/boot
sudo mount ${DEVICE}2 /mnt/rootfs

# Copy boot files
sudo cp $IMAGES/MLO /mnt/boot/
sudo cp $IMAGES/u-boot.img /mnt/boot/
sudo cp $IMAGES/zImage /mnt/boot/
sudo cp $IMAGES/am335x-boneblack.dtb /mnt/boot/

# Extract rootfs
sudo tar xf $IMAGES/rootfs.tar -C /mnt/rootfs

# Create uEnv.txt
sudo bash -c 'cat > /mnt/boot/uEnv.txt << EOF
bootpart=0:1
bootdir=
bootfile=zImage
fdtfile=am335x-boneblack.dtb
console=ttyO0,115200n8
rootpart=0:2
rootfstype=ext4
uenvcmd=fatload mmc \${bootpart} \${loadaddr} \${bootfile}; fatload mmc \${bootpart} \${fdtaddr} \${fdtfile}; setenv bootargs console=\${console} root=/dev/mmcblk0p2 rootwait rw; bootz \${loadaddr} - \${fdtaddr}
EOF'

# Sync and unmount
sync
sudo umount /mnt/boot /mnt/rootfs

echo "SD card ready!"
SCRIPT

chmod +x create_sd.sh
sudo ./create_sd.sh /dev/sdX
```

### Step 8: Boot BeagleBone Black

```bash
# Insert SD card, hold S2 button, power on
# Connect via serial
screen /dev/ttyACM0 115200

# Login
# Username: root
# Password: root (or what you configured)
```

---

## Creating Custom Configuration

### Save Your Configuration

```bash
# Save defconfig
make savedefconfig
cp defconfig configs/bbb_custom_defconfig

# Save full config
cp .config configs/bbb_custom_fullconfig
```

### Create External Tree

For custom packages and configurations:

```bash
mkdir -p ~/bbb-external/{board,configs,package}

# Create external tree skeleton
cat > ~/bbb-external/external.desc << 'EOF'
name: BBB_EXTERNAL
desc: Custom BeagleBone Black configuration
EOF

cat > ~/bbb-external/Config.in << 'EOF'
# Custom packages go here
source "$BR2_EXTERNAL_BBB_EXTERNAL_PATH/package/myapp/Config.in"
EOF

cat > ~/bbb-external/external.mk << 'EOF'
include $(sort $(wildcard $(BR2_EXTERNAL_BBB_EXTERNAL_PATH)/package/*/*.mk))
EOF

# Use external tree
make BR2_EXTERNAL=~/bbb-external menuconfig
```

### Add Custom Package

```bash
mkdir -p ~/bbb-external/package/myapp

# Config.in
cat > ~/bbb-external/package/myapp/Config.in << 'EOF'
config BR2_PACKAGE_MYAPP
    bool "myapp"
    help
      My custom application for BeagleBone Black.
EOF

# myapp.mk
cat > ~/bbb-external/package/myapp/myapp.mk << 'EOF'
################################################################################
#
# myapp
#
################################################################################

MYAPP_VERSION = 1.0
MYAPP_SITE = /path/to/myapp/source
MYAPP_SITE_METHOD = local

define MYAPP_BUILD_CMDS
    $(MAKE) CC="$(TARGET_CC)" -C $(@D)
endef

define MYAPP_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0755 $(@D)/myapp $(TARGET_DIR)/usr/bin/myapp
endef

$(eval $(generic-package))
EOF
```

---

## Customization Options

### Add Overlay Files

```bash
# Create overlay directory
mkdir -p ~/bbb-external/board/bbb/rootfs_overlay/etc

# Add custom files
cat > ~/bbb-external/board/bbb/rootfs_overlay/etc/motd << 'EOF'
Welcome to BeagleBone Black Custom Build!
EOF

# In menuconfig:
# System configuration --->
#     Root filesystem overlay: /path/to/rootfs_overlay
```

### Post-Build Script

```bash
cat > ~/bbb-external/board/bbb/post_build.sh << 'EOF'
#!/bin/bash
# $1 = target directory

# Add custom init script
cat > $1/etc/init.d/S99custom << 'INIT'
#!/bin/sh
case "$1" in
    start)
        echo "Starting custom services..."
        # Your startup commands
        ;;
    stop)
        echo "Stopping custom services..."
        ;;
esac
INIT
chmod +x $1/etc/init.d/S99custom

# Enable hardware interfaces
echo "cape_enable=bone_capemgr.enable_partno=BB-I2C1,BB-SPI0" >> $1/boot/uEnv.txt
EOF

chmod +x ~/bbb-external/board/bbb/post_build.sh

# In menuconfig:
# System configuration --->
#     Post-build script: /path/to/post_build.sh
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Build fails with "missing dependency" | Install host packages: `sudo apt install build-essential libncurses-dev` |
| Download fails | Check internet, or pre-download to `dl/` directory |
| "No space left on device" | Use larger disk, or set `BR2_DL_DIR` to external storage |
| Wrong kernel version | Update `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE` |
| U-Boot doesn't boot | Check `BR2_TARGET_UBOOT_BOARD_DEFCONFIG` |

### Rebuild Specific Component

```bash
# Rebuild just kernel
make linux-rebuild

# Rebuild just U-Boot
make uboot-rebuild

# Reconfigure kernel
make linux-menuconfig
make linux-rebuild

# Full clean rebuild
make clean
make -j$(nproc)
```

---

## Build Time Optimization

```bash
# Use ccache (enabled in Build options)
# Use parallel jobs
make -j$(nproc)

# Use external toolchain (pre-built)
# Toolchain --->
#     Toolchain type: External toolchain
#     Toolchain: Linaro ARM ...

# Use fragments for faster iteration
make linux-rebuild all  # Just rebuild kernel and regenerate images
```

---

## Verification Checklist

- [ ] Buildroot downloaded and extracted
- [ ] BeagleBone defconfig applied
- [ ] All required packages selected
- [ ] Build completes without errors
- [ ] SD card created with all images
- [ ] BeagleBone boots to login prompt
- [ ] Network connectivity works
- [ ] SSH access works
- [ ] Custom packages/overlays applied

---

[← Previous: Secure Boot](06_secure_boot.md) | [Back to Index](README.md) | [Next: Yocto Project →](08_yocto.md)
