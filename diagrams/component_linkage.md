# Component Linkage: How Embedded Linux Components Interact

This document explains how all Embedded Linux components are linked together and depend on each other. Understanding these relationships is crucial for debugging, customization, and system design.

## Why Component Linkage Matters

In embedded systems development, you will frequently encounter situations where:
- A kernel fails to boot because it doesn't match the device tree
- U-Boot can't find files because of partition layout changes  
- The root filesystem mount fails due to incorrect bootargs
- Modules don't load because of kernel version mismatches

Understanding how components link together helps you diagnose and fix these issues quickly.

## Component Dependency Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         COMPONENT LINKAGE MAP                               │
└─────────────────────────────────────────────────────────────────────────────┘

                           BUILD TIME                    RUNTIME
                        ┌─────────────┐              ┌─────────────┐
                        │  Toolchain  │              │   Hardware  │
                        │  (GCC, etc) │              │   (SoC)     │
                        └──────┬──────┘              └──────┬──────┘
                               │                            │
         ┌─────────────────────┼─────────────────────┐      │
         │                     │                     │      │
         v                     v                     v      │
  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐ │
  │   U-Boot    │      │   Kernel    │      │  Root FS    │ │
  │   Source    │      │   Source    │      │  (BusyBox)  │ │
  └──────┬──────┘      └──────┬──────┘      └──────┬──────┘ │
         │                    │                    │        │
         │  defconfig         │  defconfig         │        │
         │  + DT source       │  + DT source       │        │
         v                    v                    v        │
  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐ │
  │  U-Boot.bin │      │   zImage    │      │   rootfs    │ │
  │    + SPL    │──┐   │    + DTB    │──┐   │    .tar     │ │
  └─────────────┘  │   │  + modules  │  │   └─────────────┘ │
                   │   └─────────────┘  │          │        │
                   │         │          │          │        │
                   │         │          │          │        │
                   v         v          v          v        v
              ┌────────────────────────────────────────────────┐
              │              BOOT MEDIA (SD Card)              │
              │  ┌──────────────┐     ┌──────────────────────┐ │
              │  │  Boot Part   │     │    Rootfs Part       │ │
              │  │  (FAT32)     │     │    (ext4)            │ │
              │  │              │     │                      │ │
              │  │  - SPL/MLO   │     │  /bin, /sbin, /lib   │ │
              │  │  - u-boot    │     │  /lib/modules/       │ │
              │  │  - zImage    │     │  /etc, /home, /root  │ │
              │  │  - *.dtb     │     │  (kernel modules     │ │
              │  │  - uEnv.txt  │     │   installed here)    │ │
              │  └──────────────┘     └──────────────────────┘ │
              └────────────────────────────────────────────────┘
```

## Detailed Component Relationships

### 1. Toolchain ↔ All Binaries

**Relationship Type**: Build Dependency

```
┌─────────────────────────────────────────────────────────────┐
│                      TOOLCHAIN                              │
│                                                             │
│  arm-linux-gnueabihf-  (32-bit ARM, hard float)            │
│  aarch64-linux-gnu-    (64-bit ARM)                        │
│                                                             │
│  Components:                                                │
│  ├── gcc          → Compiles all C/C++ code                │
│  ├── binutils     → Assembler, linker, objcopy             │
│  ├── libc (glibc) → C library (version matters!)           │
│  └── headers      → Kernel headers for userspace           │
└─────────────────────────────────────────────────────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            v                 v                 v
      ┌───────────┐    ┌───────────┐    ┌───────────┐
      │  U-Boot   │    │  Kernel   │    │  RootFS   │
      │           │    │           │    │ Binaries  │
      └───────────┘    └───────────┘    └───────────┘

CRITICAL: All binaries must be compiled with compatible toolchains!
- Same architecture (ARM 32-bit vs 64-bit)
- Compatible libc versions (glibc 2.31 vs 2.35)
- Matching ABI (hard float vs soft float)
```

### 2. U-Boot ↔ Kernel

**Relationship Type**: Loader → Loadee + Data Passing

```
┌─────────────────────────────────────────────────────────────┐
│                    U-Boot → Kernel Interface                │
└─────────────────────────────────────────────────────────────┘

U-Boot loads and configures:

     U-BOOT                              KERNEL
  ┌───────────────┐                  ┌───────────────┐
  │               │   1. Load to     │               │
  │  load mmc ... │ ──────────────>  │   zImage      │
  │               │   RAM address    │   Image       │
  │               │                  │               │
  │               │   2. Load DTB    │               │
  │  fdt addr ... │ ──────────────>  │   .dtb file   │
  │               │   to RAM         │   parsed      │
  │               │                  │               │
  │               │   3. Pass        │               │
  │  bootargs=... │ ──────────────>  │   /proc/      │
  │               │   command line   │   cmdline     │
  │               │                  │               │
  │               │   4. Jump to     │               │
  │  bootz/booti  │ ──────────────>  │   Entry       │
  │               │   entry point    │   Point       │
  └───────────────┘                  └───────────────┘

ARM Register Convention at Kernel Entry:
┌──────────┬──────────────────────────────────────┐
│ Register │ Content                              │
├──────────┼──────────────────────────────────────┤
│ r0       │ 0                                    │
│ r1       │ Machine ID (or 0xFFFFFFFF for DT)   │
│ r2       │ Physical address of DTB in RAM      │
│ PC       │ Kernel entry point address          │
└──────────┴──────────────────────────────────────┘
```

### 3. Kernel ↔ Device Tree

**Relationship Type**: Consumer ↔ Hardware Description

```
┌─────────────────────────────────────────────────────────────┐
│               KERNEL ↔ DEVICE TREE RELATIONSHIP             │
└─────────────────────────────────────────────────────────────┘

  Device Tree Source (.dts)              Compiled (.dtb)
  ┌─────────────────────┐              ┌─────────────────────┐
  │ /dts-v1/;           │              │                     │
  │                     │   dtc        │   Binary blob       │
  │ / {                 │ ────────>    │   (Flattened DT)    │
  │   compatible = ...  │  compile     │                     │
  │   memory { ... }    │              │                     │
  │   soc { ... }       │              │                     │
  │ };                  │              │                     │
  └─────────────────────┘              └─────────────────────┘
                                                 │
                                                 │ U-Boot loads
                                                 │ to RAM address
                                                 v
  ┌─────────────────────────────────────────────────────────────┐
  │                        KERNEL                               │
  │                                                             │
  │  DTB Parser (drivers/of/)                                   │
  │      │                                                      │
  │      ├── Extract memory regions → Setup memory zones        │
  │      ├── Find compatible devices → Match with drivers       │
  │      ├── Get interrupt mappings → Configure IRQ controller  │
  │      ├── Get clock references → Setup clock tree            │
  │      └── Get GPIO/pinmux → Configure pins                   │
  │                                                             │
  │  Driver Matching (compatible string):                       │
  │  ┌────────────────────────────────────────────────────────┐ │
  │  │ Device Tree Node:          │ Driver:                   │ │
  │  │ compatible = "brcm,bcm2835-gpio"                       │ │
  │  │       │                           │                    │ │
  │  │       └───────── MATCH ───────────┘                    │ │
  │  │                                                        │ │
  │  │ static const struct of_device_id bcm2835_gpio_match[] │ │
  │  │   { .compatible = "brcm,bcm2835-gpio" },              │ │
  │  └────────────────────────────────────────────────────────┘ │
  └─────────────────────────────────────────────────────────────┘

CRITICAL: DTB must match kernel version!
- Kernel expects certain compatible strings
- Binding documentation: Documentation/devicetree/bindings/
```

### 4. Kernel ↔ Root Filesystem

**Relationship Type**: Mounter ↔ Mount Target + Module Provider

```
┌─────────────────────────────────────────────────────────────┐
│             KERNEL ↔ ROOT FILESYSTEM RELATIONSHIP           │
└─────────────────────────────────────────────────────────────┘

  KERNEL                                ROOT FILESYSTEM
  ┌─────────────────────┐              ┌─────────────────────┐
  │                     │   bootargs:  │                     │
  │  Parse bootargs     │<──────────── │ N/A (passive)       │
  │  root=/dev/mmcblk0p2│              │                     │
  │                     │              │                     │
  │  Mount filesystem   │ ──────────>  │  / (root)           │
  │  (ext4 driver)      │              │  ├── bin/           │
  │                     │              │  ├── sbin/          │
  │                     │              │  │   └── init ←──── │ Execute this
  │  Load modules from  │<──────────── │  ├── lib/           │
  │  /lib/modules/      │              │  │   └── modules/   │
  │  $(uname -r)/       │              │  │       └── 6.6.0/ │
  │                     │              │  ├── etc/           │
  │  Execute init       │ ──────────>  │  ├── dev/ (devtmpfs)│
  │                     │              │  └── ...            │
  └─────────────────────┘              └─────────────────────┘

CRITICAL LINKAGES:

1. Kernel Version ↔ Module Directory
   ┌──────────────────────────────────────────────────────────┐
   │  Kernel: 6.6.0-custom                                    │
   │  Modules must be in: /lib/modules/6.6.0-custom/          │
   │                                                          │
   │  If mismatch → "module version mismatch" errors          │
   └──────────────────────────────────────────────────────────┘

2. Kernel Config ↔ Filesystem Support
   ┌──────────────────────────────────────────────────────────┐
   │  If root is ext4 → Kernel needs CONFIG_EXT4_FS=y         │
   │  If root is NFS  → Kernel needs CONFIG_NFS_FS=y          │
   │                     + CONFIG_IP_PNP=y (for IP config)    │
   │                                                          │
   │  Missing support → "unknown filesystem type" panic       │
   └──────────────────────────────────────────────────────────┘

3. Init Binary ↔ Libc Version
   ┌──────────────────────────────────────────────────────────┐
   │  /sbin/init linked against glibc 2.31                    │
   │  /lib/libc.so.6 must be glibc >= 2.31                    │
   │                                                          │
   │  Version mismatch → init fails to start                  │
   └──────────────────────────────────────────────────────────┘
```

### 5. Bootargs Linkage (Central Configuration)

**Relationship Type**: Configuration Hub

```
┌─────────────────────────────────────────────────────────────┐
│                    BOOTARGS LINKAGE                         │
│                                                             │
│  Bootargs connect multiple components together:             │
└─────────────────────────────────────────────────────────────┘

                    U-BOOT
                 setenv bootargs
                       │
    ┌──────────────────┼──────────────────┐
    │                  │                  │
    v                  v                  v

┌──────────┐    ┌───────────────┐    ┌──────────────┐
│ CONSOLE  │    │   ROOT FS     │    │   KERNEL     │
│          │    │               │    │   BEHAVIOR   │
│console=  │    │root=          │    │              │
│ttyS0,    │    │/dev/mmcblk0p2 │    │debug         │
│115200    │    │               │    │loglevel=7    │
│          │    │rootfstype=ext4│    │earlyprintk   │
│          │    │               │    │              │
│          │    │rootwait       │    │quiet         │
│          │    │rw             │    │              │
└──────────┘    └───────────────┘    └──────────────┘
    │                  │                  │
    v                  v                  v
┌──────────┐    ┌───────────────┐    ┌──────────────┐
│ UART     │    │ Block device  │    │ printk       │
│ Driver   │    │ + FS driver   │    │ subsystem    │
└──────────┘    └───────────────┘    └──────────────┘

COMPLETE BOOTARGS EXAMPLE:
┌─────────────────────────────────────────────────────────────┐
│ bootargs=console=ttyS0,115200 root=/dev/mmcblk0p2          │
│          rootfstype=ext4 rootwait rw loglevel=7            │
│                                                             │
│ Meaning:                                                    │
│ - console=ttyS0,115200  : Use first serial port at 115200  │
│ - root=/dev/mmcblk0p2   : Mount 2nd partition of 1st MMC   │
│ - rootfstype=ext4       : Expect ext4 filesystem           │
│ - rootwait              : Wait for device to appear        │
│ - rw                    : Mount read-write                 │
│ - loglevel=7            : Show all kernel messages         │
└─────────────────────────────────────────────────────────────┘
```

### 6. initramfs Linkage

**Relationship Type**: Early Root → Final Root Transition

```
┌─────────────────────────────────────────────────────────────┐
│                   INITRAMFS LINKAGE                         │
└─────────────────────────────────────────────────────────────┘

  U-BOOT                  KERNEL                   INIT
  ┌─────────────┐        ┌─────────────┐         ┌─────────────┐
  │             │        │             │         │             │
  │ Load        │──────> │ Unpack to   │──────>  │ Run /init   │
  │ initramfs   │        │ rootfs      │         │ script      │
  │ to RAM      │        │ (tmpfs)     │         │             │
  │             │        │             │         │ - Load      │
  │ (Optional)  │        │ Mount as    │         │   modules   │
  │             │        │ initial /   │         │ - Find real │
  │             │        │             │         │   rootfs    │
  └─────────────┘        └─────────────┘         │ - switch_   │
                                                 │   root      │
                                                 └──────┬──────┘
                                                        │
                                                        v
                                                 ┌─────────────┐
                                                 │ Real rootfs │
                                                 │ /dev/...    │
                                                 │             │
                                                 │ Run real    │
                                                 │ /sbin/init  │
                                                 └─────────────┘

INITRAMFS INTERNAL STRUCTURE:
┌─────────────────────────────────────────────────────────────┐
│  initramfs.cpio.gz (or built into kernel)                   │
│  ├── /init          ← Entry point script                    │
│  ├── /bin/busybox   ← Minimal tools                        │
│  ├── /sbin/         ← Links to busybox                     │
│  ├── /lib/          ← Minimal libraries                    │
│  ├── /lib/modules/  ← Essential kernel modules             │
│  ├── /dev/          ← Basic device nodes                   │
│  ├── /proc/         ← Empty (mount point)                  │
│  └── /sys/          ← Empty (mount point)                  │
└─────────────────────────────────────────────────────────────┘
```

### 7. NFS Boot Linkage

**Relationship Type**: Network-Based Root Filesystem

```
┌─────────────────────────────────────────────────────────────┐
│                     NFS BOOT LINKAGE                        │
└─────────────────────────────────────────────────────────────┘

  TARGET BOARD                         HOST MACHINE
  ┌─────────────────────┐              ┌─────────────────────┐
  │                     │              │                     │
  │  U-Boot             │              │  TFTP Server        │
  │  ┌───────────────┐  │   TFTP       │  /tftpboot/         │
  │  │ tftp kernel   │<─┼──────────────┤  ├── zImage         │
  │  │ tftp dtb      │  │              │  └── board.dtb      │
  │  └───────────────┘  │              │                     │
  │                     │              └─────────────────────┘
  │  Kernel             │              ┌─────────────────────┐
  │  ┌───────────────┐  │   NFS        │  NFS Server         │
  │  │ Mount NFS     │<─┼──────────────┤  /export/rootfs/    │
  │  │ rootfs        │  │              │  ├── bin/           │
  │  └───────────────┘  │              │  ├── sbin/          │
  │                     │              │  ├── lib/           │
  │  Applications       │   NFS        │  ├── etc/           │
  │  ┌───────────────┐  │  (R/W)       │  └── home/          │
  │  │ Read/Write    │<─┼──────────────┤                     │
  │  │ files         │  │              │                     │
  │  └───────────────┘  │              │                     │
  └─────────────────────┘              └─────────────────────┘

BOOTARGS FOR NFS:
┌─────────────────────────────────────────────────────────────┐
│ bootargs=console=ttyS0,115200                               │
│          root=/dev/nfs                                      │
│          nfsroot=192.168.1.100:/export/rootfs,v3,tcp        │
│          ip=192.168.1.50::192.168.1.1:255.255.255.0::eth0:off│
└─────────────────────────────────────────────────────────────┘

KERNEL CONFIG REQUIREMENTS:
┌─────────────────────────────────────────────────────────────┐
│ CONFIG_NFS_FS=y           # NFS filesystem support          │
│ CONFIG_ROOT_NFS=y         # Root over NFS                   │
│ CONFIG_IP_PNP=y           # IP autoconfiguration            │
│ CONFIG_IP_PNP_DHCP=y      # DHCP support (optional)         │
└─────────────────────────────────────────────────────────────┘
```

## Component Version Compatibility Matrix

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    VERSION COMPATIBILITY MATRIX                            │
├──────────────┬───────────────────────────────────────────────────────────┤
│ Component    │ Must Match / Compatible With                              │
├──────────────┼───────────────────────────────────────────────────────────┤
│ Toolchain    │ ✓ Architecture (ARM32 vs ARM64)                          │
│              │ ✓ ABI (hard float vs soft float)                         │
│              │ ✓ libc version (for userspace binaries)                  │
├──────────────┼───────────────────────────────────────────────────────────┤
│ U-Boot       │ ✓ SoC / Board configuration                              │
│              │ ✓ Memory map (kernel/DTB load addresses)                 │
│              │ ✓ Storage driver (MMC, NAND, SPI, etc.)                  │
├──────────────┼───────────────────────────────────────────────────────────┤
│ Kernel       │ ✓ Device Tree (compatible strings, bindings)             │
│              │ ✓ Kernel modules (exact version match)                   │
│              │ ✓ Root filesystem type (ext4, NFS, etc.)                 │
│              │ ✓ Architecture (same as toolchain)                       │
├──────────────┼───────────────────────────────────────────────────────────┤
│ Device Tree  │ ✓ Kernel version (binding compatibility)                 │
│              │ ✓ Hardware (actual board revision)                       │
│              │ ✓ Peripheral configuration                               │
├──────────────┼───────────────────────────────────────────────────────────┤
│ Root FS      │ ✓ Kernel module version (/lib/modules/X.Y.Z/)            │
│              │ ✓ libc version (match toolchain)                         │
│              │ ✓ Architecture (same as toolchain)                       │
├──────────────┼───────────────────────────────────────────────────────────┤
│ Initramfs    │ ✓ Kernel version (if contains modules)                   │
│              │ ✓ libc or static linking                                 │
│              │ ✓ Architecture (same as toolchain)                       │
└──────────────┴───────────────────────────────────────────────────────────┘
```

## Debugging Linkage Issues

### Common Symptoms and Causes

| Symptom | Likely Cause | Component Link Broken |
|---------|--------------|----------------------|
| No boot output | Wrong UART config in DT | U-Boot ↔ DT |
| Kernel panic: no init | Wrong root= bootarg | Kernel ↔ RootFS |
| module version mismatch | Kernel/modules rebuilt separately | Kernel ↔ Modules |
| Unknown filesystem | Missing FS driver in kernel | Kernel ↔ RootFS |
| Failed to mount NFS | Missing network driver | Kernel ↔ DT |
| Segfault on any command | libc version mismatch | Toolchain ↔ RootFS |

## What You Learned

After studying this document:
- You understand how each Embedded Linux component depends on others
- You can trace the data flow from U-Boot environment to kernel behavior
- You know which version mismatches cause which failures
- You can debug boot issues by identifying broken linkages
- You understand why rebuilding one component may require rebuilding others
