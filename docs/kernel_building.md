# Linux Kernel Building Guide

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

A comprehensive guide to building the Linux kernel for embedded systems.

## Related Guides

- **[Kernel Image Types](kernel_image_types.md)** - Understanding zImage, uImage, FIT images, and when to use each format

---

## Why Kernel Building Matters

Building your own kernel is essential in embedded Linux because:

- **Hardware Support**: Enable drivers for your specific hardware
- **Size Optimization**: Remove unused features to reduce image size
- **Performance Tuning**: Configure for your use case (real-time, low-latency)
- **Security**: Disable unnecessary features, enable security options
- **Feature Control**: Add or remove specific functionality
- **Learning**: Understand what the kernel does and how it works

## Kernel Source Acquisition

### Getting the Source

```bash
# Option 1: Official kernel.org (recommended for learning)
git clone https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
cd linux
git checkout linux-6.6.y  # Use LTS branch

# Option 2: Vendor kernel (often required for full hardware support)
# Raspberry Pi:
git clone --depth=1 https://github.com/raspberrypi/linux.git

# BeagleBone:
git clone https://github.com/beagleboard/linux.git

# Option 3: Download tarball
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.10.tar.xz
tar xf linux-6.6.10.tar.xz
cd linux-6.6.10
```

### Kernel Version Considerations

| Version Type | Use Case | Support |
|--------------|----------|---------|
| Mainline | Latest features | Short-term |
| Stable | Bug fixes | ~2 months |
| LTS (Long Term) | Production | 2-6 years |
| Vendor | Full HW support | Varies |

Current LTS versions (check kernel.org):
- 6.6.x (2023-2028)
- 6.1.x (2022-2026)
- 5.15.x (2021-2027)
- 5.10.x (2020-2026)

## Kernel Source Structure

```
linux/
├── arch/                    # Architecture-specific code
│   ├── arm/
│   │   ├── boot/           # Boot code, compressed kernel
│   │   │   ├── dts/        # Device tree sources
│   │   │   └── compressed/ # Decompression code
│   │   ├── configs/        # Default configurations
│   │   ├── kernel/         # Core kernel (entry, syscalls)
│   │   ├── mm/             # Memory management
│   │   └── mach-*/         # Machine/SoC specific
│   └── arm64/
│       └── ...
│
├── block/                   # Block device layer
├── crypto/                  # Cryptographic API
├── Documentation/           # Kernel documentation
├── drivers/                 # Device drivers
│   ├── char/               # Character devices
│   ├── gpio/               # GPIO subsystem
│   ├── i2c/                # I2C bus drivers
│   ├── mmc/                # MMC/SD drivers
│   ├── net/                # Network drivers
│   ├── spi/                # SPI bus drivers
│   ├── tty/                # TTY/serial drivers
│   ├── usb/                # USB drivers
│   └── ...
│
├── fs/                      # Filesystem implementations
│   ├── ext4/
│   ├── nfs/
│   └── ...
│
├── include/                 # Header files
│   ├── linux/              # Public kernel headers
│   └── uapi/               # Userspace API headers
│
├── init/                    # Kernel initialization
│   └── main.c              # start_kernel()
│
├── kernel/                  # Core kernel code
│   ├── sched/              # Scheduler
│   ├── irq/                # Interrupt handling
│   └── ...
│
├── lib/                     # Kernel libraries
├── mm/                      # Memory management
├── net/                     # Networking stack
├── scripts/                 # Build scripts
├── security/                # Security modules (SELinux, etc.)
├── sound/                   # Sound subsystem
│
├── Kconfig                  # Top-level Kconfig
├── Makefile                 # Top-level Makefile
└── .config                  # Current configuration (after config)
```

## Building the Kernel: Step by Step

### 1. Environment Setup

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install -y \
    git bc bison flex libssl-dev make libc6-dev libncurses5-dev \
    crossbuild-essential-armhf crossbuild-essential-arm64

# Set cross-compiler environment
# For ARM 32-bit:
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

# For ARM 64-bit:
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Verify compiler
${CROSS_COMPILE}gcc --version
```

### 2. Configuration

```bash
# Clean previous builds
make distclean

# Option A: Use board defconfig
# List available defconfigs:
ls arch/arm/configs/ | head -20
# Common ones: bcm2835_defconfig, multi_v7_defconfig, omap2plus_defconfig

# Apply defconfig:
make bcm2711_defconfig  # For Raspberry Pi 4

# Option B: Start from scratch (not recommended)
make allnoconfig   # Minimal configuration
make defconfig     # Default for architecture

# Option C: Copy existing config
cp /path/to/working/.config .
make olddefconfig  # Update for new kernel version
```

### 3. Customization with menuconfig

```bash
# Launch graphical configuration
make menuconfig
```

```
┌──────────────────────── Linux Kernel Configuration ────────────────────────┐
│                                                                            │
│  Important sections to understand:                                         │
│                                                                            │
│  General setup --->                                                        │
│      Local version (append to kernel release)                              │
│      Default hostname                                                      │
│      [*] Support for paging of anonymous memory                            │
│                                                                            │
│  Processor type and features --->                                          │
│      Processor family (depends on arch)                                    │
│      [*] Symmetric multi-processing support                                │
│                                                                            │
│  Device Drivers --->                                                       │
│      [*] GPIO Support --->                                                 │
│      [*] I2C support --->                                                  │
│      [*] SPI support --->                                                  │
│      [*] Network device support --->                                       │
│      [*] MMC/SD/SDIO card support --->                                     │
│                                                                            │
│  File systems --->                                                         │
│      <*> The Extended 4 (ext4) filesystem                                  │
│      [*] Network File Systems --->                                         │
│          <*> NFS client support                                            │
│          [*] Root file system on NFS                                       │
│                                                                            │
│  Kernel hacking --->                                                       │
│      [*] Kernel debugging                                                  │
│      [*] Early printk                                                      │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

**Configuration Symbol Meanings**:
- `[*]` - Built into kernel (=y)
- `[M]` - Built as module (=m)
- `[ ]` - Not included (not set)
- `<*>` - Built-in, modules available
- `<M>` - As module, built-in available
- `< >` - Not selected

### 4. Building

```bash
# Build kernel image
# For ARM64:
make Image -j$(nproc)

# For ARM32:
make zImage -j$(nproc)

# Build device tree blobs
make dtbs -j$(nproc)

# Build modules
make modules -j$(nproc)

# Output locations:
# Kernel: arch/arm64/boot/Image (or arch/arm/boot/zImage)
# DTBs:   arch/arm64/boot/dts/*.dtb
# Modules: throughout the tree
```

### 5. Installing Modules

```bash
# Install to staging directory (for rootfs)
make INSTALL_MOD_PATH=/path/to/rootfs modules_install

# This creates:
# /path/to/rootfs/lib/modules/<kernel-version>/
#     ├── kernel/          # Module files (.ko)
#     ├── modules.alias    # Module aliases
#     ├── modules.dep      # Dependencies
#     └── ...
```

### 6. Complete Build Script

```bash
#!/bin/bash
# build_kernel.sh - Complete kernel build script

set -e

# Configuration
KERNEL_SRC="${1:-/path/to/linux}"
OUTPUT_DIR="${2:-./output}"
DEFCONFIG="${3:-bcm2711_defconfig}"

# Cross-compiler setup
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Enter kernel source
cd "${KERNEL_SRC}"

# Clean
make distclean

# Configure
make "${DEFCONFIG}"

# Build
make Image dtbs modules -j$(nproc)

# Copy outputs
cp arch/arm64/boot/Image "${OUTPUT_DIR}/"
cp arch/arm64/boot/dts/broadcom/*.dtb "${OUTPUT_DIR}/"

# Install modules
make INSTALL_MOD_PATH="${OUTPUT_DIR}/rootfs" modules_install

echo "Build complete. Outputs in ${OUTPUT_DIR}"
```

## How the Kernel Uses the Device Tree

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    KERNEL + DEVICE TREE INTERACTION                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  U-Boot passes DTB address in register r2 (ARM) or x0 (ARM64)              │
│                                                                             │
│  1. Early Boot (before page tables):                                        │
│     ┌──────────────────────────────────────────────────────────────────┐   │
│     │ • __fdt_pointer = DTB physical address                           │   │
│     │ • Minimal parsing for memory size                                │   │
│     │ • Extract bootargs (if embedded in DTB)                          │   │
│     └──────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  2. setup_machine_fdt() / setup_arch():                                     │
│     ┌──────────────────────────────────────────────────────────────────┐   │
│     │ • Verify DTB magic number (0xd00dfeed)                           │   │
│     │ • Map DTB to virtual memory                                      │   │
│     │ • Parse /memory nodes → setup memory                             │   │
│     │ • Parse /chosen node → get bootargs                              │   │
│     └──────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  3. Platform Driver Matching:                                               │
│     ┌──────────────────────────────────────────────────────────────────┐   │
│     │                                                                  │   │
│     │  Device Tree Node:              Driver:                          │   │
│     │  ┌──────────────────┐          ┌──────────────────────────────┐ │   │
│     │  │ uart@7e201000 {  │          │ static struct of_device_id   │ │   │
│     │  │   compatible =   │ ──MATCH──│   bcm2835_uart_match[] = {   │ │   │
│     │  │   "brcm,bcm2835- │          │   { .compatible =            │ │   │
│     │  │    aux-uart";    │          │     "brcm,bcm2835-aux-uart" }│ │   │
│     │  │ };               │          │ };                           │ │   │
│     │  └──────────────────┘          └──────────────────────────────┘ │   │
│     │                                                                  │   │
│     │  When match found → driver probe() called                       │   │
│     │                                                                  │   │
│     └──────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  4. Driver Resource Extraction:                                             │
│     ┌──────────────────────────────────────────────────────────────────┐   │
│     │ static int my_driver_probe(struct platform_device *pdev)         │   │
│     │ {                                                                │   │
│     │     // Get memory-mapped I/O region                              │   │
│     │     res = platform_get_resource(pdev, IORESOURCE_MEM, 0);        │   │
│     │     base = devm_ioremap_resource(&pdev->dev, res);               │   │
│     │                                                                  │   │
│     │     // Get interrupt number                                      │   │
│     │     irq = platform_get_irq(pdev, 0);                             │   │
│     │                                                                  │   │
│     │     // Get custom properties from DT                             │   │
│     │     of_property_read_u32(pdev->dev.of_node, "clock-frequency",   │   │
│     │                          &freq);                                 │   │
│     │ }                                                                │   │
│     └──────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Kernel Configuration Deep Dive

### Essential Options for Embedded Systems

```bash
# Must-have for most embedded systems:

# Networking
CONFIG_NET=y
CONFIG_INET=y                    # TCP/IP
CONFIG_NETDEVICES=y              # Network device support

# Block devices
CONFIG_BLOCK=y
CONFIG_MMC=y                     # MMC/SD support
CONFIG_MMC_SDHCI=y               # SDHCI controller

# Filesystems
CONFIG_EXT4_FS=y                 # ext4 (typical rootfs)
CONFIG_VFAT_FS=y                 # FAT (boot partition)
CONFIG_TMPFS=y                   # tmpfs for /tmp, /run
CONFIG_PROC_FS=y                 # /proc filesystem
CONFIG_SYSFS=y                   # /sys filesystem
CONFIG_DEVTMPFS=y                # Automatic device nodes
CONFIG_DEVTMPFS_MOUNT=y          # Auto-mount devtmpfs

# Device tree
CONFIG_OF=y                      # Open Firmware / Device Tree

# For NFS root:
CONFIG_NFS_FS=y
CONFIG_ROOT_NFS=y
CONFIG_IP_PNP=y
CONFIG_IP_PNP_DHCP=y
```

### Size Optimization

```bash
# Options to reduce kernel size:

# General
CONFIG_CC_OPTIMIZE_FOR_SIZE=y    # -Os instead of -O2
CONFIG_EMBEDDED=y                # Reveal more options
CONFIG_EXPERT=y                  # Expert options

# Disable unused features
# CONFIG_MODULES is not set       # No loadable modules
# CONFIG_PRINTK is not set        # No kernel messages
# CONFIG_BUG is not set           # No BUG() checks
# CONFIG_KALLSYMS is not set      # No symbol table
# CONFIG_DEBUG_INFO is not set    # No debug info

# Strip unnecessary architectures
# CONFIG_COMPAT is not set        # No 32-bit compat (on 64-bit)

# Typical sizes:
# Full kernel:     15-25 MB
# Optimized:        4-8 MB
# Minimal:          1-3 MB
```

### Debugging Options

```bash
# Enable for development:
CONFIG_DEBUG_KERNEL=y
CONFIG_DEBUG_INFO=y              # Debug symbols
CONFIG_EARLY_PRINTK=y            # Early console output
CONFIG_PRINTK_TIME=y             # Timestamps in dmesg
CONFIG_DYNAMIC_DEBUG=y           # Runtime debug control
CONFIG_MAGIC_SYSRQ=y             # SysRq key support
CONFIG_DEBUG_FS=y                # debugfs filesystem
CONFIG_KGDB=y                    # Kernel debugger
```

## Common Kernel Boot Parameters

```bash
# Console configuration
console=ttyS0,115200             # Use serial port at 115200 baud
console=tty0                     # Use VGA console
earlycon=uart8250,mmio,0x...    # Early console (before driver init)

# Root filesystem
root=/dev/mmcblk0p2              # Root on SD card partition 2
root=/dev/nfs                    # Root via NFS
root=PARTUUID=xxx               # Root by partition UUID
root=LABEL=rootfs               # Root by label
rootfstype=ext4                  # Filesystem type
rootwait                         # Wait for device
rw                               # Mount read-write
ro                               # Mount read-only

# Init
init=/sbin/init                  # Init binary
rdinit=/init                     # Init in initramfs

# Memory
mem=512M                         # Limit memory
memblock=debug                   # Memory debug

# Debug
debug                            # Enable debug messages
loglevel=7                       # Maximum verbosity (0-7)
earlyprintk                      # Early printk
ignore_loglevel                  # Ignore loglevel, print all
```

## Module Building

### Building Out-of-Tree Modules

```bash
# Create module source
cat > hello_module.c << 'EOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

static int __init hello_init(void)
{
    printk(KERN_INFO "Hello, Embedded World!\n");
    return 0;
}

static void __exit hello_exit(void)
{
    printk(KERN_INFO "Goodbye, Embedded World!\n");
}

module_init(hello_init);
module_exit(hello_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Embedded Developer");
MODULE_DESCRIPTION("Hello World Module");
EOF

# Create Makefile
cat > Makefile << 'EOF'
obj-m := hello_module.o

KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build

all:
	make -C $(KERNEL_SRC) M=$(PWD) modules

clean:
	make -C $(KERNEL_SRC) M=$(PWD) clean
EOF

# Cross-compile module
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
     KERNEL_SRC=/path/to/linux modules

# Output: hello_module.ko
```

### Loading Modules on Target

```bash
# Copy module to target
scp hello_module.ko root@target:/lib/modules/

# On target:
insmod /lib/modules/hello_module.ko
lsmod
dmesg | tail
rmmod hello_module
```

## Common Mistakes and Debugging

### Mistake 1: Wrong ARCH/CROSS_COMPILE

```bash
# Wrong (compiles for host):
make defconfig
make

# Correct (cross-compile for ARM):
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
make defconfig
make
```

### Mistake 2: Missing Root FS Support

```bash
# Symptom: VFS: Cannot open root device "mmcblk0p2"

# Solution: Enable MMC and ext4 support
make menuconfig
# Device Drivers -> MMC/SD/SDIO -> [*] MMC support
# File systems -> [*] ext4 filesystem
```

### Mistake 3: Module Version Mismatch

```bash
# Symptom: module: disagrees about version of symbol module_layout

# Solution: Rebuild modules with exact kernel version
# Use LOCALVERSION to track versions:
make LOCALVERSION="-custom-v1" Image modules

# Modules will be installed to:
# /lib/modules/6.6.0-custom-v1/
```

---

## What You Learned

After reading this document, you understand:

1. ✅ Where to get kernel source (mainline vs vendor)
2. ✅ Kernel source directory structure
3. ✅ How to configure the kernel (defconfig, menuconfig)
4. ✅ How to build kernel, DTBs, and modules
5. ✅ How to install modules to a rootfs
6. ✅ How the kernel uses the device tree
7. ✅ Essential configuration options for embedded systems
8. ✅ How to optimize kernel for size
9. ✅ How to build out-of-tree modules

---

## Next Steps

1. Complete [Lab 03: Kernel](../03_kernel/README.md)
2. Read [Device Tree](device_tree.md)
3. Practice kernel configuration with exercises
