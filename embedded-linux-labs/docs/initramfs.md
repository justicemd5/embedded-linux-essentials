# Initramfs Guide

A comprehensive guide to understanding and creating Initial RAM Filesystems for Embedded Linux.

## Why Initramfs Matters

Initramfs (Initial RAM Filesystem) is a critical component in many Linux boot scenarios. Understanding it is essential because:

- **Early Boot**: Provides early userspace before real rootfs is available
- **Complex Storage**: Required for encrypted, LVM, RAID, or network root
- **Recovery**: Enables recovery shells and fallback mechanisms
- **Embedded Systems**: Useful for minimal systems running entirely from RAM
- **Development**: Quick iteration without modifying storage

## What is Initramfs?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          INITRAMFS OVERVIEW                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  initramfs = Initial RAM FileSystem                                         │
│                                                                             │
│  • A compressed cpio archive containing a minimal root filesystem           │
│  • Loaded into RAM by the bootloader alongside the kernel                   │
│  • Kernel unpacks it into a tmpfs and mounts it as initial root            │
│  • Runs /init script to prepare for real root filesystem                   │
│                                                                             │
│  Two Types:                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ External initramfs                    │ Built-in initramfs         │   │
│  ├───────────────────────────────────────┼─────────────────────────────┤   │
│  │ Separate file (initramfs.cpio.gz)     │ Embedded in kernel image   │   │
│  │ Loaded by bootloader                  │ No separate load needed    │   │
│  │ Can be changed without rebuild        │ Requires kernel rebuild    │   │
│  │ Larger total size                     │ Single file to manage      │   │
│  └───────────────────────────────────────┴─────────────────────────────┘   │
│                                                                             │
│  initramfs vs initrd:                                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ initrd (deprecated)       │ initramfs (current)                    │   │
│  ├───────────────────────────┼─────────────────────────────────────────┤   │
│  │ Block device image        │ cpio archive                           │   │
│  │ Mounted as filesystem     │ Unpacked to tmpfs                      │   │
│  │ Requires filesystem driver│ No special driver needed               │   │
│  │ Fixed size                │ Grows as needed                        │   │
│  └───────────────────────────┴─────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## When to Use Initramfs

| Use Case | Why Initramfs Needed |
|----------|---------------------|
| Encrypted root | Need userspace to decrypt before mount |
| LVM root | Need lvm tools before kernel can mount |
| RAID root | Need mdadm before kernel can mount |
| NFS root | Need network setup (though kernel can do this) |
| Complex mount | Any mount requiring userspace tools |
| Recovery | Fallback shell if root mount fails |
| Minimal system | Entire system runs from RAM |
| Diskless boot | No persistent storage at all |
| Development | Quick testing without writing to storage |

## Initramfs Boot Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        INITRAMFS BOOT SEQUENCE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  U-Boot:                                                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Load kernel to memory                                            │   │
│  │ 2. Load initramfs to memory                                         │   │
│  │ 3. Load DTB to memory                                                │   │
│  │ 4. bootz <kernel> <initramfs>:<size> <dtb>                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       v                                                                     │
│  Kernel Early Boot:                                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Kernel decompresses (if zImage)                                  │   │
│  │ 2. Parse device tree                                                │   │
│  │ 3. Initialize memory management                                      │   │
│  │ 4. Create rootfs (tmpfs)                                            │   │
│  │ 5. Unpack initramfs cpio to rootfs                                  │   │
│  │ 6. Execute /init (PID 1)                                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       v                                                                     │
│  /init Script (in initramfs):                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Mount /proc, /sys, /dev                                          │   │
│  │ 2. Load kernel modules (if needed)                                  │   │
│  │ 3. Find/prepare real root device                                    │   │
│  │    - Decrypt if encrypted                                           │   │
│  │    - Assemble if RAID                                               │   │
│  │    - Activate if LVM                                                │   │
│  │ 4. Mount real root filesystem                                        │   │
│  │ 5. switch_root to real root                                         │   │
│  │ 6. exec real /sbin/init                                             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       v                                                                     │
│  Real Root Filesystem:                                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Normal system boot continues...                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Creating a Minimal Initramfs

### Directory Structure

```
initramfs/
├── bin/            # Essential binaries
│   ├── busybox     # Swiss-army knife of embedded Linux
│   ├── sh -> busybox
│   ├── mount -> busybox
│   └── ...
├── sbin/           # System binaries
│   ├── init -> busybox
│   └── switch_root -> busybox
├── lib/            # Libraries (for dynamically linked bins)
│   └── (optional, if using dynamic linking)
├── lib64/          # 64-bit libraries
├── dev/            # Device nodes
│   ├── console
│   ├── null
│   └── tty
├── proc/           # Mount point for procfs
├── sys/            # Mount point for sysfs
├── tmp/            # Temporary files
├── mnt/            # Mount point for real rootfs
│   └── root/
└── init            # Init script (REQUIRED)
```

### Building BusyBox (Static)

```bash
#!/bin/bash
# Build statically linked BusyBox for initramfs

# Set cross-compiler
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

# Get BusyBox source
git clone --depth=1 https://git.busybox.net/busybox
cd busybox

# Configure for static build
make defconfig

# Enable static linking (critical for initramfs)
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Or use menuconfig
make menuconfig
# Settings -> Build Options -> Build static binary (no shared libs)

# Build
make -j$(nproc)

# Result: busybox binary (statically linked)
file busybox
# busybox: ELF 32-bit LSB executable, ARM, statically linked
```

### Creating the Init Script

```bash
#!/bin/sh
# /init - Initramfs init script
# This is the first userspace process (PID 1)

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Create additional device nodes if needed
mknod -m 666 /dev/null c 1 3
mknod -m 666 /dev/zero c 1 5
mknod -m 666 /dev/tty c 5 0

# Enable kernel messages on console
echo 0 > /proc/sys/kernel/printk

# Display boot message
echo "==================================="
echo "  Initramfs Init Script Starting"
echo "==================================="

# Parse kernel command line
ROOT_DEV=""
INIT="/sbin/init"

for param in $(cat /proc/cmdline); do
    case "$param" in
        root=*)
            ROOT_DEV="${param#root=}"
            ;;
        init=*)
            INIT="${param#init=}"
            ;;
    esac
done

echo "Root device: $ROOT_DEV"
echo "Init program: $INIT"

# If no root specified, drop to shell
if [ -z "$ROOT_DEV" ]; then
    echo "No root= specified in bootargs"
    echo "Dropping to emergency shell..."
    exec /bin/sh
fi

# Wait for root device (important for slow devices)
echo "Waiting for root device..."
TIMEOUT=10
while [ ! -e "$ROOT_DEV" ] && [ $TIMEOUT -gt 0 ]; do
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
    echo "  Waiting... ($TIMEOUT seconds remaining)"
done

if [ ! -e "$ROOT_DEV" ]; then
    echo "ERROR: Root device $ROOT_DEV not found!"
    echo "Available block devices:"
    ls -la /dev/mmc* /dev/sd* 2>/dev/null || echo "  None found"
    echo "Dropping to emergency shell..."
    exec /bin/sh
fi

# Mount root filesystem
echo "Mounting root filesystem..."
mount -o ro "$ROOT_DEV" /mnt/root

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to mount root filesystem!"
    echo "Dropping to emergency shell..."
    exec /bin/sh
fi

echo "Root mounted successfully"

# Check for init binary
if [ ! -x "/mnt/root${INIT}" ]; then
    echo "ERROR: Init binary not found: /mnt/root${INIT}"
    echo "Contents of /mnt/root/sbin:"
    ls -la /mnt/root/sbin/
    echo "Dropping to emergency shell..."
    exec /bin/sh
fi

# Clean up before switch
umount /proc
umount /sys
umount /dev

# Switch to real root and exec init
echo "Switching to real root filesystem..."
exec switch_root /mnt/root "$INIT"

# If we get here, something went wrong
echo "ERROR: switch_root failed!"
exec /bin/sh
```

### Complete Creation Script

```bash
#!/bin/bash
# create_initramfs.sh - Create minimal BusyBox-based initramfs

set -e

# Configuration
WORK_DIR="${1:-./initramfs_work}"
OUTPUT="${2:-./initramfs.cpio.gz}"
ARCH="${ARCH:-arm}"
CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabihf-}"

echo "Creating initramfs in $WORK_DIR"
echo "Architecture: $ARCH"
echo "Cross-compiler: $CROSS_COMPILE"

# Create directory structure
mkdir -p "$WORK_DIR"/{bin,sbin,etc,proc,sys,dev,tmp,mnt/root,lib}

# Build or copy BusyBox
if [ ! -f busybox/busybox ]; then
    echo "Building BusyBox..."
    git clone --depth=1 https://git.busybox.net/busybox busybox_src
    cd busybox_src
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE defconfig
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE -j$(nproc)
    cd ..
    cp busybox_src/busybox "$WORK_DIR/bin/"
else
    cp busybox/busybox "$WORK_DIR/bin/"
fi

# Install BusyBox symlinks
cd "$WORK_DIR/bin"
for cmd in sh ash cat cp dd echo ls mkdir mknod mount rm sleep umount; do
    ln -sf busybox $cmd
done
cd "$WORK_DIR/sbin"
ln -sf ../bin/busybox init
ln -sf ../bin/busybox switch_root
cd - > /dev/null

# Create init script
cat > "$WORK_DIR/init" << 'INIT_SCRIPT'
#!/bin/sh
# Minimal init script

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "==================================="
echo "  Initramfs Booted Successfully!"
echo "==================================="
echo ""
echo "This is a minimal BusyBox environment."
echo "Available commands: $(busybox --list | tr '\n' ' ')"
echo ""

# Parse command line for root
for param in $(cat /proc/cmdline); do
    case "$param" in
        root=*)
            ROOT="${param#root=}"
            ;;
    esac
done

if [ -n "$ROOT" ] && [ -e "$ROOT" ]; then
    echo "Root device found: $ROOT"
    echo "Mounting and switching root..."
    mount "$ROOT" /mnt/root
    umount /proc /sys /dev 2>/dev/null
    exec switch_root /mnt/root /sbin/init
fi

echo "No root specified or found. Starting shell..."
exec /bin/sh
INIT_SCRIPT
chmod +x "$WORK_DIR/init"

# Create essential device nodes
sudo mknod -m 666 "$WORK_DIR/dev/null" c 1 3
sudo mknod -m 666 "$WORK_DIR/dev/zero" c 1 5
sudo mknod -m 666 "$WORK_DIR/dev/tty" c 5 0
sudo mknod -m 600 "$WORK_DIR/dev/console" c 5 1

# Create cpio archive
echo "Creating cpio archive..."
cd "$WORK_DIR"
find . -print0 | cpio --null -ov --format=newc | gzip -9 > "../$OUTPUT"
cd - > /dev/null

echo ""
echo "Initramfs created: $OUTPUT"
ls -lh "$OUTPUT"
echo ""
echo "To use with U-Boot:"
echo "  load mmc 0:1 \${loadaddr} zImage"
echo "  load mmc 0:1 \${fdt_addr} board.dtb"
echo "  load mmc 0:1 \${ramdisk_addr} initramfs.cpio.gz"
echo "  bootz \${loadaddr} \${ramdisk_addr}:\${filesize} \${fdt_addr}"
```

## Booting with Initramfs

### U-Boot Commands

```bash
# Load kernel
=> load mmc 0:1 ${loadaddr} zImage

# Load device tree
=> load mmc 0:1 ${fdt_addr} bcm2710-rpi-3-b.dtb

# Load initramfs
=> load mmc 0:1 ${ramdisk_addr} initramfs.cpio.gz

# Boot with initramfs
# Format: bootz <kernel_addr> <initrd_addr>:<initrd_size> <fdt_addr>
=> bootz ${loadaddr} ${ramdisk_addr}:${filesize} ${fdt_addr}

# Note: ${filesize} is automatically set by the previous load command
```

### Setting Up Boot Environment

```bash
# Create boot script with initramfs support
=> setenv ramdisk_addr 0x83000000

=> setenv initrd_boot 'load mmc 0:1 ${loadaddr} zImage; \
    load mmc 0:1 ${fdt_addr} bcm2710-rpi-3-b.dtb; \
    load mmc 0:1 ${ramdisk_addr} initramfs.cpio.gz; \
    setenv bootargs console=ttyS0,115200 rdinit=/init; \
    bootz ${loadaddr} ${ramdisk_addr}:${filesize} ${fdt_addr}'

=> saveenv

# Test boot
=> run initrd_boot
```

### Kernel Configuration for Initramfs

```bash
# Required kernel options
CONFIG_BLK_DEV_INITRD=y          # Enable initrd/initramfs support
CONFIG_RD_GZIP=y                 # Support gzip compressed initramfs
CONFIG_RD_XZ=y                   # Support xz compressed (optional, smaller)

# For built-in initramfs
CONFIG_INITRAMFS_SOURCE="/path/to/initramfs"  # Path to cpio or directory
CONFIG_INITRAMFS_COMPRESSION_GZIP=y

# Useful for initramfs
CONFIG_DEVTMPFS=y                # Auto-populate /dev
CONFIG_DEVTMPFS_MOUNT=y          # Auto-mount devtmpfs at /dev
```

## Advanced Initramfs Topics

### Adding Kernel Modules

```bash
# Create modules directory
mkdir -p initramfs/lib/modules/$(uname -r)

# Copy needed modules
cp /lib/modules/$(uname -r)/kernel/drivers/mmc/host/sdhci.ko \
   initramfs/lib/modules/$(uname -r)/

# Generate modules.dep
depmod -b initramfs $(uname -r)

# In init script, load modules:
modprobe -d /lib/modules/$(uname -r) sdhci
```

### Emergency Shell for Debugging

```bash
# Add to init script for debugging
rescue_shell() {
    echo "Dropping to rescue shell..."
    echo "Type 'exit' to continue boot (if possible)"
    /bin/sh
}

# Use it when something fails
mount "$ROOT" /mnt/root || rescue_shell
```

### switch_root vs pivot_root

```bash
# switch_root (preferred for initramfs)
# - Deletes everything in initramfs
# - Changes root to new filesystem
# - Executes init on new root
exec switch_root /mnt/root /sbin/init

# pivot_root (older method)
# - Keeps old root accessible
# - Swaps root mounts
cd /mnt/root
pivot_root . mnt
exec chroot . /sbin/init
```

## Common Mistakes and Debugging

### Mistake 1: Forgetting to Make init Executable

```bash
# Symptom: Kernel panic - not syncing: No init found

# Solution: Ensure init is executable
chmod +x initramfs/init
```

### Mistake 2: Dynamic Linking Without Libraries

```bash
# Symptom: /init: not found (even though file exists)

# Check if binary is statically linked
file initramfs/bin/busybox
# Should show: statically linked

# If dynamically linked, include libraries:
cp /lib/ld-linux-armhf.so.3 initramfs/lib/
cp /lib/arm-linux-gnueabihf/libc.so.6 initramfs/lib/
```

### Mistake 3: Wrong Initramfs Address

```bash
# Symptom: Kernel doesn't see initramfs or corrupted data

# Check memory regions don't overlap:
# - Kernel at 0x80800000
# - DTB at 0x82000000
# - Initramfs at 0x83000000 (must not overlap!)

# Verify size
=> load mmc 0:1 ${ramdisk_addr} initramfs.cpio.gz
# Check ${filesize} matches actual file
```

### Debugging Tips

```bash
# Add debug output to init
set -x  # Enable shell tracing

# Check kernel messages
cat /proc/kmsg

# Verify initramfs contents at runtime
ls -la /
cat /init

# Check cmdline parsing
cat /proc/cmdline

# List available devices
ls -la /dev/
cat /proc/partitions
```

---

## What You Learned

After reading this document, you understand:

1. ✅ What initramfs is and when to use it
2. ✅ The difference between initramfs and initrd
3. ✅ Initramfs boot flow from U-Boot to real root
4. ✅ How to build a statically linked BusyBox
5. ✅ How to create a minimal initramfs structure
6. ✅ How to write an init script
7. ✅ How to boot with initramfs from U-Boot
8. ✅ Kernel configuration for initramfs
9. ✅ Debugging initramfs boot issues

---

## Next Steps

1. Complete [Lab 05: Initramfs](../05_initramfs/README.md)
2. Use the provided [create_initramfs.sh](../05_initramfs/create_initramfs.sh)
3. Try booting your board with custom initramfs
