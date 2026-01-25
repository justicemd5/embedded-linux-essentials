# Embedded Linux Components

A comprehensive guide to understanding all the components that make up an Embedded Linux system.

## Why This Matters

Before you can build, customize, or debug an Embedded Linux system, you must understand what components exist and what role each plays. This foundational knowledge is essential for:

- **System Design**: Choosing the right components for your application
- **Debugging**: Knowing where to look when something fails
- **Optimization**: Identifying which components affect boot time, size, or power
- **Security**: Understanding the chain of trust in secure boot
- **Interviews**: Demonstrating deep embedded systems knowledge

## Component Overview Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EMBEDDED LINUX STACK                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      USER SPACE                                     │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │   │
│  │  │   App1   │ │   App2   │ │ Services │ │  Daemon  │ │  Shell   │  │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘  │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │                    C Library (glibc/musl)                   │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │ System Calls                          │
│  ┌─────────────────────────────────┴───────────────────────────────────┐   │
│  │                         KERNEL SPACE                                │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │                     Linux Kernel                             │   │   │
│  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────┐  │   │   │
│  │  │  │Scheduler│ │ Memory  │ │  VFS    │ │ Network │ │Drivers│  │   │   │
│  │  │  │         │ │ Manager │ │         │ │  Stack  │ │       │  │   │   │
│  │  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └───────┘  │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │               Device Tree (Hardware Description)             │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│  ┌─────────────────────────────────┴───────────────────────────────────┐   │
│  │                        BOOTLOADER                                   │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │                      U-Boot (Main)                           │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │                   SPL (First Stage)                          │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│  ┌─────────────────────────────────┴───────────────────────────────────┐   │
│  │                         HARDWARE                                    │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │   │
│  │  │   SoC    │ │   RAM    │ │  Flash   │ │   I/O    │ │Peripherals│  │   │
│  │  │ (CPU+ROM)│ │  (DDR)   │ │(SD/eMMC) │ │(GPIO/SPI)│ │(USB/ETH) │  │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Detailed Component Descriptions

### 1. Boot ROM (Vendor-Provided)

**What it is**: Read-only code burned into the SoC during manufacturing.

**Location**: Internal ROM within the SoC die.

**Purpose**:
- Execute first when power is applied
- Initialize minimal hardware (clocks, boot pins)
- Detect boot media (SD, eMMC, UART, USB, SPI, NAND)
- Load first-stage bootloader to internal SRAM
- Validate images (in secure boot scenarios)

**Characteristics**:
- Cannot be modified (burned at factory)
- Size: typically 32-128 KB
- Platform-specific behavior

**Example Platforms**:
| Platform | ROM Name | Boot Media Detection |
|----------|----------|---------------------|
| AM335x (BBB) | ROM Code | SYSBOOT pins |
| i.MX6 | Boot ROM | Fuses + GPIO |
| BCM2837 (RPi) | GPU Bootrom | Fixed: SD → USB |
| STM32MP1 | Boot ROM | Boot pins |

---

### 2. SPL / MLO / TPL (First-Stage Bootloader)

**What it is**: A minimal bootloader that fits in internal SRAM.

**Names by platform**:
- **SPL**: Secondary Program Loader (U-Boot terminology)
- **MLO**: MMC Loader (TI platforms)
- **TPL**: Tertiary Program Loader (for very constrained systems)

**Location**: Loaded to internal SRAM (before DRAM is available).

**Purpose**:
- Initialize system clocks
- Configure power management
- **Initialize DRAM controller** (most critical task)
- Load full bootloader (U-Boot) to DRAM
- Hand off to full bootloader

**Constraints**:
- Must fit in internal SRAM (typically 64-256 KB)
- Cannot use DRAM (not initialized yet)
- Limited functionality - just enough to load U-Boot

**Source Code Location** (in U-Boot):
```
u-boot/
├── arch/arm/cpu/         # CPU-specific SPL code
├── board/<vendor>/       # Board-specific SPL code
├── common/spl/           # Common SPL framework
└── drivers/              # Minimal drivers for SPL
```

---

### 3. U-Boot (Second-Stage Bootloader)

**What it is**: A full-featured, open-source bootloader.

**Location**: Loaded to DRAM by SPL.

**Purpose**:
- Provide interactive boot environment
- Initialize all hardware (network, storage, display)
- Load Linux kernel, device tree, and initramfs
- Pass boot parameters (bootargs) to kernel
- Support multiple boot sources and fallback
- Enable recovery mechanisms

**Key Features**:
- Command-line interface
- Environment variables (persistent configuration)
- Scripting support
- Network boot (TFTP, NFS)
- Filesystem support (FAT, ext4, etc.)
- USB, MMC, NAND, SPI flash support

**Key Environment Variables**:
```bash
bootcmd=run mmc_boot      # Command executed at boot
bootargs=console=...      # Passed to Linux kernel
bootdelay=3               # Seconds before auto-boot
loadaddr=0x80800000       # Default load address
fdt_addr=0x82000000       # Device tree load address
```

---

### 4. Linux Kernel

**What it is**: The core operating system that manages hardware and provides services to applications.

**Location**: Loaded to DRAM by U-Boot.

**Key Responsibilities**:
- Process and thread management
- Memory management (virtual memory, paging)
- Device drivers (hardware abstraction)
- Filesystem support
- Network stack
- Security and permissions
- Inter-process communication

**Image Types**:
| Image | Description | Typical Use |
|-------|-------------|-------------|
| `Image` | Uncompressed kernel | ARM64, fast boot |
| `zImage` | Compressed, self-extracting | ARM32 |
| `uImage` | U-Boot wrapper around zImage | Legacy U-Boot |
| `vmlinuz` | Compressed for x86 | Desktop Linux |

**Kernel Configuration**:
```bash
# Configure for your board
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcm2711_defconfig

# Customize configuration
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig

# Build kernel
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)
```

---

### 5. Device Tree / Device Tree Blob (DTB)

**What it is**: A data structure describing hardware to the kernel.

**Purpose**:
- Describe non-discoverable hardware
- Specify memory map, peripherals, interrupts
- Configure GPIO pins, clocks, regulators
- Enable board-specific customization without recompiling kernel

**File Types**:
- `.dts` - Device Tree Source (human-readable)
- `.dtsi` - Device Tree Source Include (shared definitions)
- `.dtb` - Device Tree Blob (compiled binary)
- `.dtbo` - Device Tree Overlay (runtime modifications)

**Example Structure**:
```dts
/dts-v1/;

/ {
    compatible = "raspberrypi,3-model-b", "brcm,bcm2837";
    model = "Raspberry Pi 3 Model B";
    
    memory@0 {
        device_type = "memory";
        reg = <0x0 0x40000000>;  // 1GB at address 0
    };
    
    leds {
        compatible = "gpio-leds";
        led0 {
            label = "led0";
            gpios = <&gpio 47 0>;
        };
    };
};
```

---

### 6. initramfs (Initial RAM Filesystem)

**What it is**: A temporary root filesystem loaded into RAM during early boot.

**Purpose**:
- Provide early userspace before real rootfs is mounted
- Load kernel modules needed to access real rootfs
- Run early initialization scripts
- Provide recovery shell if boot fails
- Handle encrypted root filesystems

**When it's used**:
- Complex storage (LVM, RAID, encrypted)
- Network boot (NFS root)
- Debugging boot issues
- Embedded systems with custom early init

**Creation**:
```bash
# Create directory structure
mkdir -p initramfs/{bin,sbin,etc,proc,sys,dev,lib}

# Add busybox (statically linked)
cp busybox initramfs/bin/
cd initramfs/bin
./busybox --install -s .

# Create init script
cat > initramfs/init << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
exec /bin/sh
EOF
chmod +x initramfs/init

# Create cpio archive
cd initramfs
find . | cpio -H newc -o | gzip > ../initramfs.cpio.gz
```

---

### 7. Root Filesystem

**What it is**: The main filesystem containing all userspace programs and data.

**Contents**:
```
/
├── bin/        # Essential user binaries (ls, cp, sh)
├── sbin/       # Essential system binaries (init, mount)
├── lib/        # Essential shared libraries
├── etc/        # System configuration files
├── dev/        # Device nodes
├── proc/       # Process information (virtual)
├── sys/        # Sysfs (virtual, kernel info)
├── tmp/        # Temporary files
├── var/        # Variable data (logs, spool)
├── home/       # User home directories
├── root/       # Root user home
├── usr/        # Secondary hierarchy (more programs)
└── opt/        # Optional software packages
```

**Common Root Filesystem Types**:
| Type | Description | Use Case |
|------|-------------|----------|
| BusyBox | Minimal, single binary | Embedded, initramfs |
| Buildroot | Build system for custom rootfs | Embedded products |
| Yocto/OE | Full embedded Linux distro builder | Complex products |
| Debian/Ubuntu | Full distribution | Development, Pi |
| Alpine | Minimal, musl-based | Containers, embedded |

---

### 8. Init System

**What it is**: The first userspace process (PID 1) that starts all other services.

**Common Init Systems**:

| Init System | Description | Use Case |
|-------------|-------------|----------|
| BusyBox init | Minimal, simple | Embedded, initramfs |
| SysVinit | Traditional, script-based | Legacy systems |
| systemd | Modern, parallel, feature-rich | Desktop, servers |
| OpenRC | Dependency-based, lightweight | Gentoo, Alpine |
| runit | Simple, supervision | Containers |

**Boot Process with systemd**:
```
Kernel → /sbin/init (→ systemd) → default.target
                                      │
                    ┌─────────────────┼─────────────────┐
                    v                 v                 v
             basic.target      network.target    multi-user.target
                    │                 │                 │
                    v                 v                 v
              udev, tmpfiles   NetworkManager     sshd, cron
```

---

### 9. C Library

**What it is**: The standard C library that provides the interface between userspace and kernel.

**Functions**:
- System call wrappers (open, read, write, fork)
- Standard C functions (printf, malloc, string functions)
- POSIX API implementation
- Dynamic linking support

**Common C Libraries**:
| Library | Size | Features | Use Case |
|---------|------|----------|----------|
| glibc | Large (~10MB) | Full POSIX, extensive | Desktop, servers |
| musl | Small (~1MB) | Clean, static-friendly | Embedded, Alpine |
| uClibc-ng | Small (~1MB) | Embedded-focused | Buildroot, legacy |
| Newlib | Very small | Minimal, bare-metal | RTOS, MCUs |

---

### 10. Cross-Compilation Toolchain

**What it is**: A set of tools that run on your host machine but produce binaries for the target.

**Components**:
- **GCC**: Cross-compiler (arm-linux-gnueabihf-gcc)
- **Binutils**: Assembler, linker, objcopy
- **C Library**: Headers and runtime for target
- **GDB**: Cross-debugger

**Naming Convention**:
```
<arch>-<vendor>-<os>-<abi>
  │       │      │     │
  │       │      │     └── ABI (gnu, gnueabi, gnueabihf, musl)
  │       │      └──────── OS (linux, none for bare-metal)
  │       └─────────────── Vendor (optional, e.g., unknown)
  └─────────────────────── Architecture (arm, aarch64, riscv64)

Examples:
- arm-linux-gnueabihf-     # ARM 32-bit, hard float
- aarch64-linux-gnu-       # ARM 64-bit
- arm-none-eabi-           # ARM bare-metal
```

---

## Component Size Comparison

```
┌──────────────────────────────────────────────────────────────┐
│              TYPICAL COMPONENT SIZES                         │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ROM Code       ████ 32-128 KB (fixed)                       │
│                                                              │
│  SPL/MLO        ████████ 64-128 KB                           │
│                                                              │
│  U-Boot         ████████████████ 512 KB - 1 MB               │
│                                                              │
│  Kernel         ████████████████████████████████ 5-20 MB     │
│                                                              │
│  DTB            ██ 32-64 KB                                  │
│                                                              │
│  initramfs      ████████████ 1-10 MB                         │
│                                                              │
│  Root FS        ████████████████████████████████████████     │
│  (minimal)      10-50 MB                                     │
│                                                              │
│  Root FS        ████████████████████████████████████████████ │
│  (full distro)  500 MB - 4 GB                                │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Common Mistakes and Debugging Tips

### Mistake 1: Architecture Mismatch
```
# WRONG: Using x86 compiler for ARM target
$ gcc -o myapp myapp.c
$ file myapp
myapp: ELF 64-bit LSB executable, x86-64  # Won't run on ARM!

# CORRECT: Using cross-compiler
$ arm-linux-gnueabihf-gcc -o myapp myapp.c
$ file myapp
myapp: ELF 32-bit LSB executable, ARM
```

### Mistake 2: Missing Kernel Module Directory
```
# Kernel expects modules in specific directory
$ ls /lib/modules/
5.10.0    # This must match $(uname -r) exactly!

# If kernel is 5.10.1 and modules are for 5.10.0:
# → modprobe will fail with version mismatch
```

### Mistake 3: Wrong Device Tree
```
# Kernel boot log:
[    0.000000] OF: fdt: Machine model: Unknown  # Wrong or missing DTB!
[    0.100000] Kernel panic - not syncing: No init found
```

---

## What You Learned

After reading this document, you should understand:

1. ✅ All major components of an Embedded Linux system
2. ✅ The purpose and responsibilities of each component
3. ✅ How components relate to each other
4. ✅ Typical sizes and resource requirements
5. ✅ Common configuration files and their locations
6. ✅ How to identify which component is causing a problem
7. ✅ The difference between various C libraries and init systems
8. ✅ Cross-compilation toolchain naming conventions

---

## Next Steps

1. Read [Bootloader Stages](bootloader_stages.md) to understand boot flow in detail
2. Read [Component Linkage](../diagrams/component_linkage.md) to see how parts connect
3. Start [Lab 01: Boot Flow](../01_boot_flow/README.md) for hands-on experience
