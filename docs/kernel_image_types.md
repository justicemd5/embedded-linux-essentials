# Linux Kernel Image Types Guide

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

A comprehensive guide to understanding the various Linux kernel image formats used in embedded systems, with focus on BeagleBone Black and ARM platforms.

---

## Table of Contents

1. [Overview](#overview)
2. [Raw Kernel Images](#raw-kernel-images)
3. [U-Boot Legacy Images (uImage)](#u-boot-legacy-images-uimage)
4. [FIT Images (Flattened Image Tree)](#fit-images-flattened-image-tree)
5. [Boot Commands Summary](#boot-commands-summary)
6. [Creating Each Image Type](#creating-each-image-type)
7. [Choosing the Right Format](#choosing-the-right-format)
8. [BeagleBone Black Specifics](#beaglebone-black-specifics)

---

## Overview

When you build the Linux kernel, the output is a binary image that must be loaded and executed by the bootloader. Different image formats exist because:

1. **Historical reasons** - Different architectures evolved different formats
2. **Bootloader requirements** - U-Boot, GRUB, etc. have different needs
3. **Feature requirements** - Signing, compression, multi-image support
4. **Boot speed vs. size tradeoffs** - Compressed vs. uncompressed

### Quick Reference Table

| Image Format | Extension | Description | Boot Command | Best For |
|--------------|-----------|-------------|--------------|----------|
| vmlinux | - | Raw ELF binary | - | Debugging |
| Image | - | Uncompressed binary | booti | ARM64, fast boot |
| zImage | - | Compressed, self-extracting | bootz | ARM32 (BBB) |
| uImage | .uimg | U-Boot legacy wrapper | bootm | Legacy systems |
| FIT Image | .itb, .fit | Multi-component signed | bootm | Modern, secure boot |

### Image Creation Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      KERNEL IMAGE BUILD FLOW                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Source Code                                                               │
│       │                                                                     │
│       ▼                                                                     │
│   ┌──────────┐                                                              │
│   │ Compile  │ make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-            │
│   └────┬─────┘                                                              │
│        │                                                                    │
│        ▼                                                                    │
│   ┌──────────┐    ELF format with symbols                                   │
│   │ vmlinux  │◄── For debugging, ~50-100MB unstripped                      │
│   └────┬─────┘                                                              │
│        │                                                                    │
│        ▼ objcopy (strip, convert)                                           │
│   ┌──────────┐    Raw binary, no ELF headers                               │
│   │ Image    │◄── Uncompressed, ~10-30MB                                   │
│   └────┬─────┘    (arch/arm64/boot/Image)                                  │
│        │                                                                    │
│        ├──────────────────────────────────────────┐                        │
│        │                                          │                        │
│        ▼ gzip + self-extracting stub              │                        │
│   ┌──────────┐    Compressed, ~3-8MB              │                        │
│   │  zImage  │◄── (arch/arm/boot/zImage)          │                        │
│   └────┬─────┘                                    │                        │
│        │                                          │                        │
│        ├────────────────────┐                     │                        │
│        │                    │                     │                        │
│        ▼ mkimage -T kernel  ▼ mkimage -f .its     │                        │
│   ┌──────────┐         ┌──────────┐               │                        │
│   │  uImage  │         │ FIT Image│               │                        │
│   │ (legacy) │         │ (modern) │               │                        │
│   └──────────┘         └──────────┘               │                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Raw Kernel Images

### vmlinux

The **vmlinux** is the raw, uncompressed Linux kernel in ELF (Executable and Linkable Format).

```
┌─────────────────────────────────────────────────────────────────┐
│                         vmlinux                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ELF Header                                                     │
│  ├── Magic: 7f 45 4c 46 (ELF)                                  │
│  ├── Class: 32-bit or 64-bit                                   │
│  ├── Entry point: start_kernel()                               │
│  └── Section headers                                            │
│                                                                 │
│  Sections:                                                      │
│  ├── .text      - Executable code                              │
│  ├── .rodata    - Read-only data                               │
│  ├── .data      - Initialized data                             │
│  ├── .bss       - Uninitialized data                           │
│  ├── .init      - Initialization code (freed after boot)      │
│  └── .symtab    - Symbol table (debugging)                     │
│                                                                 │
│  Size: 50-100+ MB (with debug symbols)                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Use cases:**
- Debugging with GDB
- Symbol resolution for crash analysis
- Kernel profiling tools

**Location:** `linux/vmlinux`

```bash
# Examine vmlinux
file vmlinux
# vmlinux: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, ...

# Get symbol addresses
nm vmlinux | grep start_kernel
# c0a00000 T start_kernel

# Use with GDB
arm-linux-gnueabihf-gdb vmlinux
```

---

### Image (Uncompressed)

The **Image** is a raw binary extracted from vmlinux, stripped of ELF metadata. Used primarily on ARM64.

```
┌─────────────────────────────────────────────────────────────────┐
│                          Image                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Structure:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  64-byte header (ARM64 only)                            │   │
│  │  ├── Magic: ARM\x64                                     │   │
│  │  ├── Text offset                                        │   │
│  │  └── Image size                                         │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │                                                         │   │
│  │  Raw kernel binary code                                 │   │
│  │  (stripped ELF, just code and data)                     │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Size: 10-30 MB                                                 │
│  Boot: booti command (ARM64)                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Location:** `arch/arm64/boot/Image`

**Use cases:**
- ARM64 systems (Raspberry Pi 3/4 in 64-bit mode)
- When boot speed is critical (no decompression needed)
- Systems with fast storage but limited CPU

```bash
# Build Image for ARM64
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image

# Check image
file arch/arm64/boot/Image
# arch/arm64/boot/Image: Linux kernel ARM64 boot executable Image, ...

# Boot in U-Boot
=> booti ${loadaddr} - ${fdtaddr}
```

---

### zImage (Compressed, Self-Extracting)

The **zImage** is a compressed kernel with a decompression stub. Standard for ARM32.

```
┌─────────────────────────────────────────────────────────────────┐
│                          zImage                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Decompression Stub (~16KB)                             │   │
│  │  ├── Entry point (start:)                               │   │
│  │  ├── Self-relocation code                               │   │
│  │  ├── Decompressor (gzip, lz4, lzma, etc.)              │   │
│  │  └── Jump to kernel                                     │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │                                                         │   │
│  │  Compressed Kernel                                      │   │
│  │  (gzip compressed by default)                           │   │
│  │                                                         │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  Appended DTB (optional)                                │   │
│  │  (for older bootloaders)                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Size: 3-8 MB (typically)                                       │
│  Boot: bootz command (ARM32)                                   │
│                                                                 │
│  Boot Process:                                                  │
│  1. U-Boot loads zImage to memory                               │
│  2. Jumps to decompression stub                                 │
│  3. Stub decompresses kernel to final location                 │
│  4. Stub jumps to decompressed kernel                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Location:** `arch/arm/boot/zImage`

**This is the standard format for BeagleBone Black.**

```bash
# Build zImage for ARM32 (BeagleBone Black)
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage

# Check image
file arch/arm/boot/zImage
# arch/arm/boot/zImage: Linux kernel ARM boot executable zImage (little-endian)

# Verify size savings
ls -lh vmlinux arch/arm/boot/zImage
# vmlinux:  70M
# zImage:    5M

# Boot in U-Boot
=> fatload mmc 0:1 ${loadaddr} zImage
=> fatload mmc 0:1 ${fdtaddr} am335x-boneblack.dtb
=> bootz ${loadaddr} - ${fdtaddr}
```

### zImage Compression Options

The kernel can be configured to use different compression algorithms:

| Algorithm | Config Option | Size | Decompress Speed | CPU Usage |
|-----------|---------------|------|------------------|-----------|
| gzip | CONFIG_KERNEL_GZIP | Medium | Medium | Medium |
| lz4 | CONFIG_KERNEL_LZ4 | Larger | Fastest | Lowest |
| lzma | CONFIG_KERNEL_LZMA | Smallest | Slowest | Highest |
| xz | CONFIG_KERNEL_XZ | Smallest | Slow | High |
| lzo | CONFIG_KERNEL_LZO | Medium | Fast | Low |

```bash
# Check compression in menuconfig
make ARCH=arm menuconfig
# General setup --->
#   Kernel compression mode (Gzip)  --->
```

---

## U-Boot Legacy Images (uImage)

### What is uImage?

The **uImage** is a legacy U-Boot wrapper format that adds a 64-byte header to a kernel image.

```
┌─────────────────────────────────────────────────────────────────┐
│                          uImage                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  U-Boot Header (64 bytes)                               │   │
│  │  ├── Magic: 27 05 19 56                                 │   │
│  │  ├── Header CRC32                                       │   │
│  │  ├── Timestamp                                          │   │
│  │  ├── Data size                                          │   │
│  │  ├── Data CRC32                                         │   │
│  │  ├── Load address                                       │   │
│  │  ├── Entry point                                        │   │
│  │  ├── OS type (Linux)                                    │   │
│  │  ├── Architecture (ARM)                                 │   │
│  │  ├── Image type (Kernel)                                │   │
│  │  ├── Compression type                                   │   │
│  │  └── Image name (32 bytes)                              │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │                                                         │   │
│  │  Payload (zImage or raw binary)                         │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Boot: bootm command                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Creating uImage

```bash
# Build kernel first
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage

# Create uImage with mkimage
mkimage -A arm -O linux -T kernel -C none -a 0x82000000 -e 0x82000000 \
    -n "Linux Kernel" -d arch/arm/boot/zImage uImage

# Or use the kernel's built-in target
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
    LOADADDR=0x82000000 uImage
```

### mkimage Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| -A | Architecture | arm, arm64, x86 |
| -O | Operating system | linux, u-boot |
| -T | Image type | kernel, ramdisk, firmware |
| -C | Compression | none, gzip, bzip2, lzma |
| -a | Load address | 0x82000000 |
| -e | Entry point | 0x82000000 |
| -n | Image name | "Linux Kernel" |
| -d | Data file | zImage |

### Booting uImage

```bash
# In U-Boot
=> fatload mmc 0:1 ${loadaddr} uImage
=> fatload mmc 0:1 ${fdtaddr} am335x-boneblack.dtb
=> bootm ${loadaddr} - ${fdtaddr}

# With initramfs
=> fatload mmc 0:1 ${loadaddr} uImage
=> fatload mmc 0:1 ${ramdiskaddr} initramfs.uImage
=> fatload mmc 0:1 ${fdtaddr} am335x-boneblack.dtb
=> bootm ${loadaddr} ${ramdiskaddr} ${fdtaddr}
```

### Why uImage is Legacy

Modern systems prefer zImage/bootz or FIT because:

1. **Fixed addresses** - uImage has hardcoded load/entry addresses
2. **No multi-image** - Only one component per image
3. **No signing** - No built-in security
4. **Complexity** - Extra wrapping step required

---

## FIT Images (Flattened Image Tree)

### What is FIT?

**FIT (Flattened Image Tree)** is the modern U-Boot image format that can contain multiple components with cryptographic signing.

```
┌─────────────────────────────────────────────────────────────────┐
│                       FIT IMAGE                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  FDT Header (Device Tree format)                        │   │
│  │  ├── Magic: d0 0d fe ed                                 │   │
│  │  ├── Total size                                         │   │
│  │  ├── Structure offset                                   │   │
│  │  └── Strings offset                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  /images                                                │   │
│  │  ├── kernel-1                                           │   │
│  │  │   ├── data = <binary>                                │   │
│  │  │   ├── type = "kernel"                                │   │
│  │  │   ├── arch = "arm"                                   │   │
│  │  │   ├── compression = "none"                           │   │
│  │  │   ├── load = <0x82000000>                            │   │
│  │  │   ├── entry = <0x82000000>                           │   │
│  │  │   ├── hash-1 { algo = "sha256"; value = <...> }     │   │
│  │  │   └── signature-1 { algo = "sha256,rsa2048"; ... }  │   │
│  │  │                                                      │   │
│  │  ├── fdt-bbb                                            │   │
│  │  │   ├── data = <binary>                                │   │
│  │  │   ├── type = "flat_dt"                               │   │
│  │  │   ├── hash-1 { algo = "sha256"; value = <...> }     │   │
│  │  │   └── signature-1 { ... }                            │   │
│  │  │                                                      │   │
│  │  └── ramdisk-1 (optional)                               │   │
│  │      ├── data = <binary>                                │   │
│  │      ├── type = "ramdisk"                               │   │
│  │      └── hash-1 { ... }                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  /configurations                                        │   │
│  │  ├── default = "conf-1"                                 │   │
│  │  └── conf-1                                             │   │
│  │      ├── kernel = "kernel-1"                            │   │
│  │      ├── fdt = "fdt-bbb"                                │   │
│  │      ├── ramdisk = "ramdisk-1"                          │   │
│  │      └── signature-1 { sign-images = "kernel", "fdt" } │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Boot: bootm command                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### FIT Image Advantages

| Feature | uImage | FIT |
|---------|--------|-----|
| Multiple components | ❌ | ✅ Kernel, DTB, initramfs |
| Multiple configurations | ❌ | ✅ Debug, prod, recovery |
| Hash verification | CRC32 only | ✅ SHA256, SHA512 |
| Cryptographic signing | ❌ | ✅ RSA signatures |
| Device tree format | No | ✅ Easy parsing |
| Compression per-component | ❌ | ✅ |
| Self-describing | Minimal | ✅ Rich metadata |

### Creating FIT Images

#### Step 1: Create Image Source File (.its)

```dts
/* image.its - FIT Image Source for BeagleBone Black */
/dts-v1/;

/ {
    description = "BeagleBone Black Boot Image";
    #address-cells = <1>;

    images {
        kernel-1 {
            description = "Linux kernel for AM335x";
            data = /incbin/("zImage");
            type = "kernel";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <0x82000000>;
            entry = <0x82000000>;
            
            hash-1 {
                algo = "sha256";
            };
        };

        fdt-1 {
            description = "BeagleBone Black DTB";
            data = /incbin/("am335x-boneblack.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            
            hash-1 {
                algo = "sha256";
            };
        };

        ramdisk-1 {
            description = "Initial ramdisk";
            data = /incbin/("initramfs.cpio.gz");
            type = "ramdisk";
            arch = "arm";
            os = "linux";
            compression = "gzip";
            
            hash-1 {
                algo = "sha256";
            };
        };
    };

    configurations {
        default = "conf-1";

        conf-1 {
            description = "Standard boot";
            kernel = "kernel-1";
            fdt = "fdt-1";
        };

        conf-2 {
            description = "Boot with initramfs";
            kernel = "kernel-1";
            fdt = "fdt-1";
            ramdisk = "ramdisk-1";
        };
    };
};
```

#### Step 2: Build FIT Image

```bash
# Ensure required files exist
ls zImage am335x-boneblack.dtb initramfs.cpio.gz

# Create unsigned FIT image
mkimage -f image.its image.fit

# Verify image contents
mkimage -l image.fit
```

#### Step 3: Boot FIT Image

```bash
# In U-Boot
=> fatload mmc 0:1 ${loadaddr} image.fit
=> bootm ${loadaddr}

# Boot specific configuration
=> bootm ${loadaddr}#conf-2

# Check image info in U-Boot
=> iminfo ${loadaddr}
```

### Signed FIT Images

For secure boot, FIT images can be signed:

```bash
# Generate keys
openssl genrsa -out dev_key.pem 2048
openssl rsa -in dev_key.pem -pubout -out dev_key.pub

# Sign FIT image (also embeds public key in U-Boot DTB)
mkimage -f image.its \
    -k /path/to/keys \
    -K /path/to/u-boot/arch/arm/dts/am335x-boneblack.dtb \
    -r \
    image.fit.signed
```

See [Exercise 06: Secure Boot](../exercises/advanced/06_secure_boot.md) for complete secure boot implementation.

---

## Boot Commands Summary

| Image Type | Boot Command | Format |
|------------|--------------|--------|
| zImage | bootz | bootz ${kernel_addr} ${ramdisk_addr} ${fdt_addr} |
| Image (ARM64) | booti | booti ${kernel_addr} ${ramdisk_addr} ${fdt_addr} |
| uImage | bootm | bootm ${kernel_addr} ${ramdisk_addr} ${fdt_addr} |
| FIT | bootm | bootm ${fit_addr} or bootm ${fit_addr}#config |

### Address Format Notes

```bash
# If no ramdisk, use '-' as placeholder
=> bootz ${loadaddr} - ${fdtaddr}

# With ramdisk
=> bootz ${loadaddr} ${ramdiskaddr}:${ramdisksize} ${fdtaddr}

# FIT image (auto-selects default configuration)
=> bootm ${loadaddr}

# FIT image with specific configuration
=> bootm ${loadaddr}#conf-debug
```

---

## Creating Each Image Type

### Complete Build Example

```bash
# Set up environment
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

# Configure for BeagleBone Black
cd ~/linux
make omap2plus_defconfig

# Build everything
make -j$(nproc) zImage dtbs modules

# Outputs:
# - vmlinux           (raw ELF, for debugging)
# - arch/arm/boot/zImage (compressed kernel, USE THIS)
# - arch/arm/boot/dts/am335x-boneblack.dtb (device tree)
```

### Create uImage from zImage

```bash
# Method 1: Using mkimage directly
mkimage -A arm -O linux -T kernel -C none \
    -a 0x82000000 -e 0x82000000 \
    -n "Linux 6.6" \
    -d arch/arm/boot/zImage uImage

# Method 2: Using kernel build system
make LOADADDR=0x82000000 uImage
# Output: arch/arm/boot/uImage
```

### Create FIT Image

```bash
# Prepare files
mkdir fit && cd fit
cp ../arch/arm/boot/zImage .
cp ../arch/arm/boot/dts/am335x-boneblack.dtb .

# Create .its file (see above)
cat > image.its << 'EOF'
# ... (image source content)
EOF

# Build FIT
mkimage -f image.its image.fit
```

---

## Choosing the Right Format

### Decision Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              KERNEL IMAGE FORMAT SELECTION                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Start                                                          │
│    │                                                            │
│    ▼                                                            │
│  ┌─────────────────────┐                                        │
│  │ Need secure boot?   │                                        │
│  └──────────┬──────────┘                                        │
│         Yes │           No                                      │
│             ▼           │                                       │
│      ┌─────────────┐    │                                       │
│      │ FIT Image   │    │                                       │
│      │ (signed)    │    │                                       │
│      └─────────────┘    │                                       │
│                         ▼                                       │
│               ┌─────────────────────┐                           │
│               │ Multiple configs?   │                           │
│               └──────────┬──────────┘                           │
│                      Yes │           No                         │
│                          ▼           │                          │
│                   ┌─────────────┐    │                          │
│                   │ FIT Image   │    │                          │
│                   │ (unsigned)  │    │                          │
│                   └─────────────┘    │                          │
│                                      ▼                          │
│                            ┌─────────────────────┐              │
│                            │ Architecture?       │              │
│                            └──────────┬──────────┘              │
│                                       │                         │
│                    ┌──────────────────┼───────────────┐         │
│                    ▼                  ▼               ▼         │
│              ┌──────────┐      ┌──────────┐    ┌──────────┐     │
│              │ ARM32    │      │ ARM64    │    │ Legacy   │     │
│              │          │      │          │    │ System   │     │
│              └────┬─────┘      └────┬─────┘    └────┬─────┘     │
│                   ▼                 ▼               ▼           │
│              ┌──────────┐      ┌──────────┐    ┌──────────┐     │
│              │ zImage   │      │ Image    │    │ uImage   │     │
│              │ (bootz)  │      │ (booti)  │    │ (bootm)  │     │
│              └──────────┘      └──────────┘    └──────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Recommendations by Use Case

| Use Case | Recommended Format | Rationale |
|----------|-------------------|-----------|
| BeagleBone Black (standard) | zImage | Native ARM32, simple |
| BeagleBone Black (secure) | FIT (signed) | Verified boot chain |
| Raspberry Pi 4 (64-bit) | Image | ARM64, fast boot |
| Production device | FIT (signed) | Security, multi-config |
| Development/testing | zImage or Image | Simple, fast iteration |
| Legacy systems | uImage | Compatibility |
| A/B updates | FIT | Atomic updates, versioning |

---

## BeagleBone Black Specifics

### Standard Boot Setup

For BeagleBone Black Rev C with AM335x:

```bash
# Kernel build
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- omap2plus_defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage dtbs

# Deploy to SD card
sudo mount /dev/sdX1 /mnt
sudo cp arch/arm/boot/zImage /mnt/
sudo cp arch/arm/boot/dts/am335x-boneblack.dtb /mnt/
sudo umount /mnt
```

### U-Boot Environment for BBB

```bash
# Standard zImage boot
setenv loadaddr 0x82000000
setenv fdtaddr 0x88000000
setenv bootcmd 'fatload mmc 0:1 ${loadaddr} zImage; fatload mmc 0:1 ${fdtaddr} am335x-boneblack.dtb; bootz ${loadaddr} - ${fdtaddr}'
setenv bootargs 'console=ttyO0,115200n8 root=/dev/mmcblk0p2 rw rootwait'
saveenv
```

### Memory Map for BBB

```
┌─────────────────────────────────────────────────────────────────┐
│                 BBB MEMORY MAP (512MB DDR3)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  0x80000000 ─┬─ DRAM Start                                      │
│              │                                                  │
│  0x80200000 ─┼─ U-Boot (typical location)                       │
│              │                                                  │
│  0x82000000 ─┼─ Kernel load address (zImage)                    │
│              │  ↓ Kernel decompresses and runs here             │
│              │                                                  │
│  0x88000000 ─┼─ Device Tree address                             │
│              │                                                  │
│  0x88080000 ─┼─ Initramfs (if used)                             │
│              │                                                  │
│  0x9FFFFFFF ─┴─ DRAM End (512MB)                                │
│                                                                 │
│  Common U-Boot variables:                                       │
│    loadaddr=0x82000000                                          │
│    fdtaddr=0x88000000                                           │
│    ramdiskaddr=0x88080000                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Summary

| Format | Command | Size | Security | Best For |
|--------|---------|------|----------|----------|
| vmlinux | N/A | ~50MB | None | Debugging |
| Image | booti | ~15MB | None | ARM64 systems |
| zImage | bootz | ~5MB | None | ARM32 (BBB) |
| uImage | bootm | ~5MB | CRC32 | Legacy |
| FIT | bootm | Varies | SHA256+RSA | Modern/Secure |

**For BeagleBone Black:**
- Use **zImage** for development and simple setups
- Use **FIT images** for production with secure boot requirements

---

## Related Documentation

- [Kernel Building Guide](kernel_building.md)
- [U-Boot Overview](uboot_overview.md)
- [Boot Flow](../01_boot_flow/README.md)
- [Secure Boot Exercise](../exercises/advanced/06_secure_boot.md)

---

## References

- U-Boot FIT Documentation: `doc/uImage.FIT/` in U-Boot source
- Kernel Image Types: `Documentation/arm/booting.rst` in kernel source
- mkimage man page: `man mkimage`
