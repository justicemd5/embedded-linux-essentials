# Lab 03: Linux Kernel Building

A hands-on lab for building and configuring the Linux kernel for embedded systems.

## Lab Objectives

By the end of this lab, you will be able to:

1. Obtain Linux kernel source code
2. Configure the kernel for embedded targets
3. Cross-compile the kernel and modules
4. Build and understand Device Tree Blobs
5. Deploy and boot your custom kernel

## Prerequisites

- Completed [Lab 02: U-Boot](../02_uboot/README.md)
- Cross-compilation toolchain installed
- Target board with serial console
- At least 10GB free disk space

## Lab Structure

```
03_kernel/
├── README.md                ← This file
├── build_kernel.sh          ← Kernel build automation script
└── kernel_config_notes.md   ← Important configuration options
```

---

## Part 1: Obtaining Kernel Source

### Option A: Official Kernel from kernel.org

```bash
# Clone mainline kernel (large download!)
git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
cd linux

# Or clone stable branch (recommended for embedded)
git clone https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
cd linux
git checkout linux-6.6.y
```

### Option B: Vendor/BSP Kernel

Many boards have vendor-specific kernels with additional drivers:

```bash
# Raspberry Pi kernel
git clone --depth=1 https://github.com/raspberrypi/linux
cd linux

# BeagleBone kernel
git clone https://github.com/beagleboard/linux
cd linux
git checkout 6.1
```

### Option C: Download Tarball

```bash
# Download specific version
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.20.tar.xz
tar xf linux-6.6.20.tar.xz
cd linux-6.6.20
```

---

## Part 2: Understanding Kernel Structure

```
linux/
├── arch/               ← Architecture-specific code
│   ├── arm/           
│   │   ├── boot/      ← Boot code and compressed kernel
│   │   │   ├── dts/   ← Device Tree Source files
│   │   │   └── zImage ← Output: compressed kernel
│   │   ├── configs/   ← Default configurations
│   │   └── mach-*/    ← Machine/SoC specific code
│   └── arm64/         ← 64-bit ARM
├── drivers/           ← Device drivers
├── fs/                ← Filesystems
├── include/           ← Header files
├── init/              ← Kernel initialization
├── kernel/            ← Core kernel code
├── mm/                ← Memory management
├── net/               ← Networking
├── scripts/           ← Build scripts
├── Documentation/     ← Kernel documentation
├── Kconfig            ← Configuration system
└── Makefile           ← Main build file
```

---

## Part 3: Configuring the Kernel

### Step 1: Set Up Environment

```bash
# For 32-bit ARM (BeagleBone, older Pi)
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

# For 64-bit ARM (Raspberry Pi 3/4)
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Verify toolchain
${CROSS_COMPILE}gcc --version
```

### Step 2: Apply Default Configuration

```bash
# List available configs for your architecture
ls arch/${ARCH}/configs/

# Apply a default configuration
# Raspberry Pi 3/4 (64-bit):
make bcm2711_defconfig

# BeagleBone Black:
make omap2plus_defconfig

# Or use multi-platform:
make multi_v7_defconfig
```

### Step 3: Customize Configuration

```bash
# Text-based menu configuration
make menuconfig

# Or graphical (requires Qt)
make xconfig

# Or GTK-based
make gconfig
```

### Important Configuration Options

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ESSENTIAL KERNEL OPTIONS                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  General Setup:                                                             │
│  [*] Local version - append to kernel release                              │
│      (-mykernel) Custom version string                                      │
│  [*] Support for paging of anonymous memory (swap)                          │
│  [*] Control Group support                                                  │
│                                                                             │
│  Processor Features:                                                        │
│  [*] Symmetric Multi-Processing (if multi-core)                            │
│  [*] Support ARM LPAE (for >4GB RAM)                                        │
│                                                                             │
│  Device Drivers:                                                            │
│  [*] MMC/SD/SDIO card support                                               │
│      [*] MMC block device driver                                            │
│      [*] Your specific MMC controller                                       │
│  [*] Network device support                                                 │
│      [*] Ethernet driver support                                            │
│      [*] Your specific Ethernet driver                                      │
│  [*] Serial drivers                                                         │
│      [*] Your UART driver                                                   │
│                                                                             │
│  File Systems:                                                              │
│  [*] Ext4 filesystem                                                        │
│  [*] VFAT filesystem (for boot partition)                                   │
│  [*] NFS client support (for NFS boot)                                      │
│                                                                             │
│  Boot Options (for NFS root):                                               │
│  [*] IP: kernel level autoconfiguration                                     │
│  [*] IP: DHCP support                                                       │
│  [*] Root file system on NFS                                                │
│                                                                             │
│  Device Tree:                                                               │
│  [*] Open Firmware / Flattened Device Tree support                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 4: Save Configuration

```bash
# Configuration is saved to .config

# Save a copy
cp .config ../my_kernel_config

# View differences from default
make savedefconfig
diff defconfig arch/${ARCH}/configs/original_defconfig
```

---

## Part 4: Building the Kernel

### Basic Build

```bash
# Build kernel image, modules, and device trees
make -j$(nproc)

# This produces:
# - arch/arm/boot/zImage (or Image for arm64)
# - arch/arm/boot/dts/*.dtb
# - Various .ko module files

# Build just the kernel
make -j$(nproc) zImage   # or Image for arm64

# Build just device trees
make -j$(nproc) dtbs

# Build just modules
make -j$(nproc) modules
```

### Build Output Locations

```bash
# Kernel image
ls -lh arch/${ARCH}/boot/zImage      # ARM32
ls -lh arch/${ARCH}/boot/Image       # ARM64

# Device Tree Blobs
ls arch/${ARCH}/boot/dts/*.dtb
ls arch/${ARCH}/boot/dts/broadcom/*.dtb   # For Raspberry Pi

# Modules
find . -name "*.ko" | head -10
```

### Install Modules to Custom Location

```bash
# Install to temporary directory
make INSTALL_MOD_PATH=../modules_install modules_install

# This creates:
# ../modules_install/lib/modules/<version>/
#   ├── kernel/          ← Module files
#   ├── modules.dep      ← Dependency info
#   └── modules.alias    ← Alias mappings
```

---

## Part 5: Deployment

### Prepare SD Card

```bash
# Identify SD card device
lsblk

# Mount partitions
sudo mount /dev/sdb1 /mnt/boot      # Boot partition (FAT32)
sudo mount /dev/sdb2 /mnt/rootfs    # Root filesystem (ext4)
```

### Copy Kernel and DTB

```bash
# For Raspberry Pi (64-bit)
sudo cp arch/arm64/boot/Image /mnt/boot/kernel8.img
sudo cp arch/arm64/boot/dts/broadcom/bcm2711-rpi-4-b.dtb /mnt/boot/

# For BeagleBone
sudo cp arch/arm/boot/zImage /mnt/boot/
sudo cp arch/arm/boot/dts/am335x-boneblack.dtb /mnt/boot/

# If using U-Boot, update boot commands accordingly
```

### Copy Modules

```bash
# Install modules to rootfs
sudo make INSTALL_MOD_PATH=/mnt/rootfs modules_install

# Or from temporary location
sudo cp -r ../modules_install/lib/modules/* /mnt/rootfs/lib/modules/
```

### Unmount and Boot

```bash
sudo umount /mnt/boot
sudo umount /mnt/rootfs
sync
```

---

## Part 6: Verify Kernel

### Check Running Kernel

```bash
# On target after boot
uname -a
# Linux myboard 6.6.20-mykernel #1 SMP PREEMPT ...

# View kernel build info
cat /proc/version

# View kernel config (if enabled)
zcat /proc/config.gz | grep CONFIG_LOCALVERSION
```

### Check Modules

```bash
# List loaded modules
lsmod

# Load a module
modprobe my_driver

# Module info
modinfo /lib/modules/$(uname -r)/kernel/drivers/my_driver.ko
```

---

## Lab Exercises

### Exercise 1: Build Default Kernel

1. Clone kernel source for your board
2. Apply default configuration
3. Build kernel, DTBs, and modules
4. Deploy and boot
5. Verify with `uname -a`

### Exercise 2: Enable Debug Options

1. Run `make menuconfig`
2. Enable these options:
   - Kernel hacking → Magic SysRq key
   - Kernel hacking → Debug kernel
   - Kernel hacking → Kernel debugging
3. Rebuild and test Magic SysRq

### Exercise 3: Build Minimal Kernel

1. Start from `make tinyconfig`
2. Add only essential options for boot
3. Compare size with default kernel
4. Boot and verify functionality

### Exercise 4: Add Local Version

1. Set `CONFIG_LOCALVERSION="-lab03"`
2. Rebuild
3. Verify with `uname -r`

### Exercise 5: Build as External Module

1. Create a simple "Hello World" kernel module
2. Build against your kernel tree
3. Load and test on target

---

## Troubleshooting

### Build Errors

```bash
# Missing toolchain
make: arm-linux-gnueabihf-gcc: Command not found
# Solution: Install or set CROSS_COMPILE correctly

# Missing dependencies
fatal error: openssl/bio.h: No such file or directory
# Solution: sudo apt-get install libssl-dev

# Out of disk space
No space left on device
# Solution: Use 'make clean' or build on larger disk
```

### Boot Issues

```bash
# Kernel panic - not syncing: VFS: Unable to mount root fs
# Causes:
# - Wrong root= in bootargs
# - Missing filesystem driver in kernel
# - rootwait missing for SD card

# Kernel doesn't print anything
# Causes:
# - Wrong console= in bootargs
# - Serial driver not enabled
# - Wrong DTB for board
```

### Module Issues

```bash
# modprobe: FATAL: Module not found
# Cause: Modules not installed or wrong kernel version
# Solution: Ensure modules match running kernel version

# depmod: WARNING: could not open modules.dep
# Cause: modules.dep not generated
# Solution: Run 'depmod -a' on target
```

---

## What You Learned

After completing this lab:

1. ✅ How to obtain kernel source (mainline vs vendor)
2. ✅ Kernel directory structure
3. ✅ Configuration with defconfig and menuconfig
4. ✅ Essential kernel options for embedded
5. ✅ Cross-compilation of kernel, DTBs, and modules
6. ✅ Deployment to SD card
7. ✅ Verification of running kernel

---

## Next Lab

Continue to [Lab 04: Device Tree](../04_device_tree/README.md) to learn about device tree customization.
