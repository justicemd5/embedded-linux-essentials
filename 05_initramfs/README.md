# Lab 05: Initramfs

A hands-on lab for creating and using Initial RAM Filesystems.

## Lab Objectives

By the end of this lab, you will be able to:

1. Understand initramfs purpose and structure
2. Build a minimal initramfs with BusyBox
3. Create a custom init script
4. Boot with initramfs from U-Boot
5. Use initramfs for recovery and debugging

## Prerequisites

- Completed [Lab 03: Linux Kernel](../03_kernel/README.md)
- Cross-compilation toolchain
- Target board with serial console

## Lab Structure

```
05_initramfs/
├── README.md             ← This file
├── create_initramfs.sh   ← Automated initramfs creation script
└── init                  ← Example init script
```

---

## Part 1: Understanding Initramfs

### When to Use Initramfs

| Scenario | Why Initramfs |
|----------|--------------|
| Complex root storage | Need to unlock encrypted, assemble RAID, etc. |
| Network root | Set up networking before mounting NFS |
| Minimal system | Entire system runs from RAM |
| Recovery | Fallback when main system fails |
| Development | Quick testing without storage writes |

### Initramfs vs Regular Boot

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BOOT COMPARISON                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Regular Boot:                                                              │
│  U-Boot → Kernel → Mount root device → Run /sbin/init                      │
│                                                                             │
│  Initramfs Boot:                                                            │
│  U-Boot → Kernel → Unpack initramfs to tmpfs → Run /init →                 │
│           → (Optional: Mount real root → switch_root → Run /sbin/init)     │
│                                                                             │
│  Key Difference:                                                            │
│  - Initramfs provides early userspace BEFORE real root is mounted          │
│  - Can do complex operations requiring userspace tools                     │
│  - Can stay in initramfs (minimal system) or switch to real root           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: Creating Minimal Initramfs

### Directory Structure

```bash
# Create initramfs directory structure
mkdir -p initramfs/{bin,sbin,etc,proc,sys,dev,tmp,mnt/root,lib}
```

### Build Static BusyBox

```bash
# Get BusyBox source
git clone --depth=1 https://git.busybox.net/busybox
cd busybox

# Configure for static linking
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

make defconfig

# Enable static build (CRITICAL for initramfs)
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Or use menuconfig
make menuconfig
# Settings → Build Options → Build static binary

# Build
make -j$(nproc)

# Verify static linking
file busybox
# Should show: "statically linked"
```

### Install BusyBox

```bash
# Copy to initramfs
cp busybox ../initramfs/bin/

# Create symlinks for common utilities
cd ../initramfs/bin
for cmd in sh ash cat cp dd echo ls mkdir mknod mount rm sleep umount; do
    ln -sf busybox $cmd
done

cd ../sbin
ln -sf ../bin/busybox init
ln -sf ../bin/busybox switch_root
```

### Create Device Nodes

```bash
cd ../initramfs/dev

# Essential device nodes
sudo mknod -m 666 null c 1 3
sudo mknod -m 666 zero c 1 5
sudo mknod -m 666 tty c 5 0
sudo mknod -m 600 console c 5 1
```

---

## Part 3: Creating the Init Script

See [init](init) for the complete script.

### Minimal Init Script

```bash
#!/bin/sh
# /init - Minimal initramfs init script

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "==================================="
echo "  Initramfs Started Successfully"
echo "==================================="

# Parse kernel command line
for param in $(cat /proc/cmdline); do
    case "$param" in
        root=*) ROOT="${param#root=}" ;;
    esac
done

# If root specified, mount and switch
if [ -n "$ROOT" ] && [ -e "$ROOT" ]; then
    echo "Mounting root: $ROOT"
    mount "$ROOT" /mnt/root
    
    # Clean up before switch
    umount /proc /sys /dev
    
    # Switch to real root
    exec switch_root /mnt/root /sbin/init
fi

# No root or stay in initramfs
echo "Starting shell..."
exec /bin/sh
```

### Make Init Executable

```bash
chmod +x initramfs/init
```

---

## Part 4: Creating the cpio Archive

```bash
# Create initramfs archive
cd initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.cpio.gz

# Check result
ls -lh ../initramfs.cpio.gz
```

---

## Part 5: Booting with Initramfs

### U-Boot Manual Boot

```bash
# At U-Boot prompt:

# Load kernel
=> load mmc 0:1 ${loadaddr} zImage

# Load device tree
=> load mmc 0:1 ${fdt_addr} board.dtb

# Load initramfs
=> load mmc 0:1 ${ramdisk_addr} initramfs.cpio.gz

# Set boot arguments (rdinit specifies init in initramfs)
=> setenv bootargs console=ttyS0,115200 rdinit=/init

# Boot - note the initramfs address:size format
=> bootz ${loadaddr} ${ramdisk_addr}:${filesize} ${fdt_addr}
```

### U-Boot Environment for Initramfs Boot

```bash
# Create persistent environment
=> setenv ramdisk_addr 0x83000000
=> setenv initrd_file initramfs.cpio.gz

=> setenv load_initrd 'load mmc 0:1 ${ramdisk_addr} ${initrd_file}'

=> setenv initrd_boot 'run load_kernel; run load_fdt; run load_initrd; \
    setenv bootargs console=ttyS0,115200 rdinit=/init; \
    bootz ${loadaddr} ${ramdisk_addr}:${filesize} ${fdt_addr}'

=> saveenv
=> run initrd_boot
```

---

## Part 6: Advanced Init Script

### Init with Root Mounting

```bash
#!/bin/sh
# /init - Initramfs init script with root mounting

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "==================================="
echo "  Initramfs Init Starting"
echo "==================================="

# Parse kernel command line
ROOT=""
INIT="/sbin/init"

for param in $(cat /proc/cmdline); do
    case "$param" in
        root=*) ROOT="${param#root=}" ;;
        init=*) INIT="${param#init=}" ;;
    esac
done

echo "Root device: $ROOT"
echo "Init program: $INIT"

# Drop to shell if no root
if [ -z "$ROOT" ]; then
    echo "No root= in bootargs, starting shell..."
    exec /bin/sh
fi

# Wait for root device
echo "Waiting for root device..."
TIMEOUT=30
while [ ! -e "$ROOT" ] && [ $TIMEOUT -gt 0 ]; do
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done

if [ ! -e "$ROOT" ]; then
    echo "ERROR: Root device not found!"
    echo "Available devices:"
    ls -la /dev/mmc* /dev/sd* 2>/dev/null
    echo "Dropping to shell..."
    exec /bin/sh
fi

# Mount root filesystem
echo "Mounting root..."
mount -o ro "$ROOT" /mnt/root

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to mount root!"
    exec /bin/sh
fi

# Verify init exists
if [ ! -x "/mnt/root${INIT}" ]; then
    echo "ERROR: Init not found: ${INIT}"
    echo "Contents of /mnt/root/sbin:"
    ls -la /mnt/root/sbin/
    exec /bin/sh
fi

# Switch to real root
echo "Switching to real root..."
umount /proc /sys /dev 2>/dev/null
exec switch_root /mnt/root "$INIT"
```

---

## Part 7: Using create_initramfs.sh Script

The provided [create_initramfs.sh](create_initramfs.sh) automates the entire process.

```bash
# Basic usage
./create_initramfs.sh

# With custom output
./create_initramfs.sh ./my_initramfs ./output/initramfs.cpio.gz

# Set architecture
ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- ./create_initramfs.sh
```

---

## Lab Exercises

### Exercise 1: Build Minimal Initramfs

1. Create directory structure
2. Build static BusyBox
3. Write minimal init script
4. Create cpio archive
5. Boot and verify

### Exercise 2: Add Networking to Initramfs

1. Add networking commands to BusyBox config
2. Include network setup in init script
3. Boot and configure network manually

### Exercise 3: Create Recovery Initramfs

1. Add fdisk, mkfs utilities
2. Add file recovery tools
3. Create menu-driven recovery interface

### Exercise 4: Debug Boot Issues

1. Create initramfs with debug output
2. Use it to diagnose boot problems
3. Mount and inspect real root filesystem

---

## Troubleshooting

### No output after "Starting kernel"

```bash
# Check console in bootargs
console=ttyS0,115200

# Verify kernel has correct UART driver
```

### "No init found"

```bash
# Verify init is executable
chmod +x initramfs/init

# Check BusyBox is statically linked
file initramfs/bin/busybox

# Verify init script has correct shebang
head -1 initramfs/init
# Should be: #!/bin/sh
```

### "not syncing: VFS: Unable to mount root fs"

```bash
# For initramfs-only boot, don't specify root=
# Just use: rdinit=/init

# Verify initramfs was loaded at correct address
# Check U-Boot load command output
```

---

## What You Learned

After completing this lab:

1. ✅ Initramfs purpose and use cases
2. ✅ Building static BusyBox
3. ✅ Creating initramfs directory structure
4. ✅ Writing init scripts
5. ✅ Creating cpio archives
6. ✅ Booting with initramfs from U-Boot

---

## Next Lab

Continue to [Lab 06: NFS Boot](../06_nfs_boot/README.md) for network-based root filesystem.
