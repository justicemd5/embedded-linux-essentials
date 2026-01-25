# U-Boot Overview

A comprehensive guide to the Das U-Boot bootloader - architecture, internals, configuration, and usage.

## Why U-Boot Matters

U-Boot (Universal Boot Loader) is the most widely used bootloader in embedded Linux systems. Understanding U-Boot is essential because:

- **Industry Standard**: Used in most ARM-based embedded products
- **Highly Customizable**: Can be tailored for any hardware
- **Rich Functionality**: Network boot, scripting, recovery mechanisms
- **Well Documented**: Large community, extensive documentation
- **Interview Topic**: Frequently asked in embedded systems interviews

## What is U-Boot?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          U-BOOT OVERVIEW                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Das U-Boot (Universal Boot Loader)                                         │
│                                                                             │
│  • Open source (GPL-2.0)                                                    │
│  • Started in 1999 as PPCBoot, became U-Boot in 2002                       │
│  • Supports: ARM, x86, MIPS, PowerPC, RISC-V, and more                     │
│  • Primary repository: https://source.denx.de/u-boot/u-boot                │
│                                                                             │
│  Key Features:                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Interactive command shell                                         │   │
│  │ • Environment variables (persistent configuration)                  │   │
│  │ • Multi-format boot (zImage, Image, uImage, FIT)                   │   │
│  │ • Network boot (TFTP, NFS, PXE)                                     │   │
│  │ • Storage support (MMC, NAND, NOR, USB, SATA)                       │   │
│  │ • Filesystem support (FAT, ext4, UBIFS, SquashFS)                   │   │
│  │ • Scripting and automation                                          │   │
│  │ • Device tree support                                               │   │
│  │ • Secure boot (FIT signature verification)                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## U-Boot Directory Structure

```
u-boot/
├── arch/                    # Architecture-specific code
│   ├── arm/
│   │   ├── cpu/            # CPU-specific (Cortex-A, Cortex-M)
│   │   ├── dts/            # Device tree source files
│   │   ├── lib/            # ARM-specific libraries
│   │   └── mach-*/         # Machine/SoC-specific
│   └── ...
│
├── board/                   # Board-specific code
│   ├── raspberrypi/        # Raspberry Pi boards
│   ├── ti/                 # Texas Instruments boards
│   │   └── am335x/         # BeagleBone, etc.
│   ├── freescale/          # NXP/Freescale boards
│   └── ...
│
├── cmd/                     # U-Boot commands
│   ├── boot.c              # boot command
│   ├── mmc.c               # mmc command
│   ├── net.c               # network commands
│   └── ...
│
├── common/                  # Common code
│   ├── main.c              # Main loop
│   ├── board_f.c           # Board init (before relocation)
│   ├── board_r.c           # Board init (after relocation)
│   └── ...
│
├── configs/                 # Board defconfigs
│   ├── rpi_3_defconfig     # Raspberry Pi 3
│   ├── am335x_evm_defconfig
│   └── ...
│
├── doc/                     # Documentation
│
├── drivers/                 # Device drivers
│   ├── mmc/                # MMC/SD drivers
│   ├── net/                # Network drivers
│   ├── serial/             # UART drivers
│   ├── gpio/               # GPIO drivers
│   └── ...
│
├── dts/                     # Device tree infrastructure
│
├── env/                     # Environment handling
│
├── fs/                      # Filesystem support
│   ├── fat/
│   ├── ext4/
│   └── ...
│
├── include/                 # Header files
│   ├── configs/            # Board configuration headers
│   ├── asm/                # Architecture headers
│   └── ...
│
├── lib/                     # Common libraries
│
├── net/                     # Network stack
│
├── scripts/                 # Build scripts
│
└── tools/                   # Host tools
    ├── mkimage.c           # Image creation tool
    └── ...
```

## Building U-Boot

### Step-by-Step Build Process

```bash
# 1. Clone U-Boot source
git clone https://source.denx.de/u-boot/u-boot.git
cd u-boot
git checkout v2024.01  # Use stable release

# 2. Set up cross-compiler
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

# 3. Clean previous builds
make distclean

# 4. Configure for your board
# List available configs:
ls configs/ | grep -i rpi
# Output: rpi_3_defconfig, rpi_4_defconfig, etc.

# Apply configuration:
make rpi_3_defconfig

# 5. Optional: Customize configuration
make menuconfig
# Navigate menus to enable/disable features
# Important sections:
#   - Boot options
#   - Command line interface → Commands
#   - Environment → Environment in ...
#   - Device Drivers

# 6. Build U-Boot
make -j$(nproc)

# 7. Output files
ls -la u-boot.bin SPL u-boot.img
# u-boot.bin  - Main U-Boot binary
# SPL         - First-stage loader (if applicable)
# u-boot.img  - U-Boot with header (for some platforms)
```

### Important Configuration Options

```bash
# Key Kconfig options (accessible via menuconfig)

# Boot options
CONFIG_BOOTDELAY=3              # Seconds before auto-boot
CONFIG_BOOTCOMMAND="..."        # Default boot command
CONFIG_USE_BOOTARGS=y           # Use default bootargs
CONFIG_BOOTARGS="console=..."   # Default kernel arguments

# Environment storage
CONFIG_ENV_IS_IN_MMC=y          # Store env in MMC
CONFIG_ENV_SIZE=0x20000         # Environment size (128KB)
CONFIG_ENV_OFFSET=0x100000      # Offset in storage

# Command support
CONFIG_CMD_BOOT=y               # boot, bootd commands
CONFIG_CMD_BOOTM=y              # bootm command
CONFIG_CMD_BOOTZ=y              # bootz command (zImage)
CONFIG_CMD_BOOTI=y              # booti command (Image)
CONFIG_CMD_EXT4=y               # ext4 filesystem commands
CONFIG_CMD_FAT=y                # FAT filesystem commands
CONFIG_CMD_MMC=y                # MMC commands
CONFIG_CMD_NET=y                # Network commands
CONFIG_CMD_TFTP=y               # TFTP command
CONFIG_CMD_PING=y               # ping command
CONFIG_CMD_DHCP=y               # DHCP command

# SPL options
CONFIG_SPL=y                    # Build SPL
CONFIG_SPL_MMC=y                # MMC support in SPL
CONFIG_SPL_SERIAL=y             # Serial output in SPL
```

## U-Boot Environment Variables

### Core Variables

```bash
# Display all variables
=> printenv

# Essential variables:
bootcmd=run mmc_boot                        # Command executed at auto-boot
bootargs=console=ttyS0,115200 root=/dev/mmcblk0p2 rw  # Passed to kernel
bootdelay=3                                 # Seconds before auto-boot
loadaddr=0x80800000                         # Default load address
fdt_addr=0x82000000                         # Device tree address
kernel_addr_r=0x80800000                    # Kernel load address
fdt_addr_r=0x82000000                       # FDT load address
ramdisk_addr_r=0x83000000                   # Ramdisk load address

# Network variables:
ipaddr=192.168.1.50                         # Board IP address
serverip=192.168.1.100                      # TFTP server IP
netmask=255.255.255.0                       # Network mask
gatewayip=192.168.1.1                       # Gateway
ethaddr=00:11:22:33:44:55                   # MAC address

# Boot source selection:
boot_targets=mmc0 mmc1 usb0 pxe dhcp        # Boot order
```

### Variable Operations

```bash
# Set a variable
=> setenv myvar "my value"

# Set bootargs (complex value)
=> setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait rw'

# Create compound command
=> setenv mmc_boot 'load mmc 0:1 ${loadaddr} zImage; load mmc 0:1 ${fdt_addr} board.dtb; bootz ${loadaddr} - ${fdt_addr}'

# Run a command variable
=> run mmc_boot

# Delete a variable
=> setenv myvar

# Save environment to persistent storage
=> saveenv
Saving Environment to MMC... OK

# Reset to default environment
=> env default -a
```

### Common Boot Command Examples

```bash
# Boot from SD card (FAT partition)
setenv mmc_boot 'load mmc 0:1 ${loadaddr} zImage; \
                 load mmc 0:1 ${fdt_addr} bcm2710-rpi-3-b.dtb; \
                 bootz ${loadaddr} - ${fdt_addr}'

# Boot from SD card (ext4 partition)
setenv mmc_boot 'ext4load mmc 0:2 ${loadaddr} /boot/zImage; \
                 ext4load mmc 0:2 ${fdt_addr} /boot/board.dtb; \
                 bootz ${loadaddr} - ${fdt_addr}'

# Boot with initramfs
setenv initrd_boot 'load mmc 0:1 ${loadaddr} zImage; \
                    load mmc 0:1 ${fdt_addr} board.dtb; \
                    load mmc 0:1 ${ramdisk_addr} initramfs.cpio.gz; \
                    bootz ${loadaddr} ${ramdisk_addr}:${filesize} ${fdt_addr}'

# Network boot (TFTP)
setenv net_boot 'dhcp; \
                 tftp ${loadaddr} zImage; \
                 tftp ${fdt_addr} board.dtb; \
                 bootz ${loadaddr} - ${fdt_addr}'

# NFS root boot
setenv nfs_boot 'setenv bootargs console=ttyS0,115200 root=/dev/nfs \
                 nfsroot=${serverip}:/export/rootfs,v3,tcp ip=dhcp; \
                 tftp ${loadaddr} zImage; \
                 tftp ${fdt_addr} board.dtb; \
                 bootz ${loadaddr} - ${fdt_addr}'
```

## U-Boot Commands Reference

### Memory Commands

```bash
# Memory display
=> md 0x80000000 100        # Display 256 words at address
=> md.b 0x80000000 100      # Display bytes
=> md.w 0x80000000 100      # Display half-words (16-bit)
=> md.l 0x80000000 100      # Display words (32-bit)

# Memory write
=> mw 0x80000000 0xdeadbeef 100  # Fill memory with pattern

# Memory copy
=> cp 0x80000000 0x81000000 1000  # Copy 0x1000 words

# Memory compare
=> cmp 0x80000000 0x81000000 1000
```

### Storage Commands

```bash
# MMC commands
=> mmc list                 # List MMC devices
=> mmc dev 0                # Select MMC device 0
=> mmc info                 # Show device info
=> mmc part                 # Show partitions
=> mmc read 0x80000000 0x800 0x4000  # Read raw sectors

# Filesystem commands
=> fatls mmc 0:1            # List files on FAT partition
=> fatload mmc 0:1 0x80000000 zImage  # Load file
=> fatinfo mmc 0:1          # Show filesystem info

=> ext4ls mmc 0:2           # List files on ext4 partition
=> ext4load mmc 0:2 0x80000000 /boot/zImage

# Generic load command (auto-detects FS)
=> load mmc 0:1 0x80000000 zImage
```

### Network Commands

```bash
# Basic network setup
=> dhcp                     # Get IP via DHCP
=> setenv ipaddr 192.168.1.50
=> setenv serverip 192.168.1.100

# Connectivity test
=> ping 192.168.1.100

# TFTP download
=> tftp 0x80000000 zImage   # Download to address
=> tftp                     # Download to ${loadaddr}

# NFS mount (for debugging)
=> nfs 0x80000000 192.168.1.100:/export/rootfs/boot/zImage
```

### Boot Commands

```bash
# Boot zImage (ARM32)
=> bootz ${loadaddr} - ${fdt_addr}
# Format: bootz <kernel_addr> <initrd_addr> <fdt_addr>
# Use '-' for no initrd

# Boot Image (ARM64)
=> booti ${loadaddr} - ${fdt_addr}

# Boot uImage (legacy)
=> bootm ${loadaddr}

# Boot FIT image
=> bootm ${loadaddr}#config-1

# Execute bootcmd
=> boot
# or
=> bootd
```

### Information Commands

```bash
=> version                  # U-Boot version
=> bdinfo                   # Board info (memory, etc.)
=> coninfo                  # Console info
=> help                     # List all commands
=> help mmc                 # Help for specific command
```

## U-Boot Scripting

### Script Variables

```bash
# Create a boot script
=> setenv try_mmc 'if load mmc 0:1 ${loadaddr} zImage; then echo Found kernel on MMC; else echo No kernel on MMC; fi'
=> run try_mmc

# Conditional boot with fallback
=> setenv bootcmd 'run mmc_boot || run net_boot || echo All boot methods failed'
```

### Script Files (boot.scr)

```bash
# Create boot script on host:
cat > boot.cmd << 'EOF'
echo "=== Custom Boot Script ==="
setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rw

# Try to load kernel
if load mmc 0:1 ${loadaddr} zImage; then
    echo "Kernel loaded from MMC"
else
    echo "Trying network boot..."
    dhcp
    tftp ${loadaddr} zImage
fi

# Load device tree
load mmc 0:1 ${fdt_addr} board.dtb

# Boot
bootz ${loadaddr} - ${fdt_addr}
EOF

# Compile to boot.scr
mkimage -C none -A arm -T script -d boot.cmd boot.scr

# Copy boot.scr to SD card boot partition
# U-Boot will auto-execute if configured
```

## U-Boot Boot Flow Internals

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      U-BOOT INITIALIZATION SEQUENCE                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  _start (arch/arm/cpu/armvX/start.S)                                        │
│  │                                                                          │
│  ├── Save boot parameters                                                   │
│  ├── Set up initial stack pointer                                           │
│  ├── Clear BSS                                                              │
│  └── Call board_init_f()                                                    │
│                                                                             │
│  board_init_f() [common/board_f.c]                                          │
│  │                                                                          │
│  │  Runs with limited stack (in SRAM)                                       │
│  │  Global data in temporary location                                       │
│  │                                                                          │
│  ├── init_sequence_f[] executes:                                            │
│  │   ├── setup_mon_len        # U-Boot size                                │
│  │   ├── fdtdec_setup         # FDT setup                                  │
│  │   ├── initf_malloc         # Early malloc                               │
│  │   ├── arch_cpu_init        # CPU init                                   │
│  │   ├── env_init             # Environment init                           │
│  │   ├── init_baud_rate       # Console baud rate                          │
│  │   ├── serial_init          # UART init                                  │
│  │   ├── console_init_f       # Console init (pre-reloc)                   │
│  │   ├── dram_init            # DRAM init/size detection                   │
│  │   └── ...                                                               │
│  │                                                                          │
│  └── Prepare for relocation (calculate new addresses)                       │
│                                                                             │
│  relocate_code() [arch/arm/lib/relocate.S]                                  │
│  │                                                                          │
│  ├── Copy U-Boot to top of DRAM                                             │
│  ├── Fix up relocations                                                     │
│  ├── Clear BSS                                                              │
│  └── Jump to relocated board_init_r()                                       │
│                                                                             │
│  board_init_r() [common/board_r.c]                                          │
│  │                                                                          │
│  │  Runs from DRAM with full resources                                      │
│  │                                                                          │
│  ├── init_sequence_r[] executes:                                            │
│  │   ├── initr_trace          # Tracing init                               │
│  │   ├── initr_reloc_global_data                                           │
│  │   ├── initr_malloc         # Full malloc                                │
│  │   ├── board_init           # Board-specific init                        │
│  │   ├── initr_mmc            # MMC init                                   │
│  │   ├── initr_env            # Load environment                           │
│  │   ├── initr_stdio          # Standard I/O init                          │
│  │   ├── initr_eth            # Network init                               │
│  │   └── run_main_loop        # Main command loop                          │
│  │                                                                          │
│  └── main_loop() [common/main.c]                                            │
│                                                                             │
│  main_loop()                                                                │
│  │                                                                          │
│  ├── Show boot banner                                                       │
│  ├── bootdelay countdown                                                    │
│  │   └── If interrupted → command loop                                      │
│  ├── Execute bootcmd                                                        │
│  │   └── Normally boots kernel                                             │
│  └── Command loop (if boot fails or interrupted)                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Adding Custom Functionality

### Adding a Custom Command

See [02_uboot/custom_cmd/README.md](../02_uboot/custom_cmd/README.md) for complete implementation.

```c
// cmd/hello.c - Example custom command
#include <command.h>
#include <common.h>

static int do_hello(struct cmd_tbl *cmdtp, int flag, int argc, char *const argv[])
{
    if (argc < 2) {
        printf("Hello, World!\n");
    } else {
        printf("Hello, %s!\n", argv[1]);
    }
    return 0;
}

U_BOOT_CMD(
    hello,      // Command name
    2,          // Max arguments
    1,          // Repeatable
    do_hello,   // Function
    "say hello",          // Short help
    "[name]\n"            // Long help
    "    - Print hello message"
);
```

### Adding a Custom Board

```
1. Create board directory:
   board/mycompany/myboard/
   
2. Add files:
   - Kconfig          # Board Kconfig options
   - Makefile         # Board Makefile
   - myboard.c        # Board init code
   - MAINTAINERS      # Maintainer info
   
3. Create defconfig:
   configs/myboard_defconfig
   
4. Add device tree:
   arch/arm/dts/myboard.dts
   
5. Add to Kconfig:
   arch/arm/mach-*/Kconfig
```

## Common Mistakes and Debugging

### Debugging U-Boot

```bash
# Enable verbose output
=> setenv bootargs console=ttyS0,115200 debug earlyprintk

# Check memory layout
=> bdinfo
arch_number = 0x00000000
boot_params = 0x80000100
DRAM bank   = 0x00000000
-> start    = 0x80000000
-> size     = 0x20000000  # 512 MB
...

# Debug environment
=> printenv bootcmd bootargs

# Check if file exists
=> load mmc 0:1 ${loadaddr} zImage
Loading: Failed to load 'zImage'  # File not found

# List files to verify
=> fatls mmc 0:1
  8388608   zimage    # Note: lowercase!
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No output | Wrong UART | Check dts console setting |
| `bad CRC` | Corrupted env | `env default -a; saveenv` |
| `Wrong Image Format` | Wrong boot command | Use bootz/booti for raw kernel |
| `Starting kernel...` then hang | Bad bootargs | Check console, root settings |
| `TFTP error` | Network config | Check cables, IP settings |

---

## What You Learned

After reading this document, you understand:

1. ✅ U-Boot's role and capabilities
2. ✅ U-Boot directory structure and code organization
3. ✅ How to build U-Boot for different platforms
4. ✅ Important configuration options
5. ✅ Environment variables and their purposes
6. ✅ Common commands for memory, storage, network, and boot
7. ✅ U-Boot initialization sequence
8. ✅ How to add custom commands
9. ✅ Debugging techniques

---

## Next Steps

1. Complete [Lab 02: U-Boot](../02_uboot/README.md)
2. Practice [Environment Persistence](../02_uboot/env_sdcard/README.md)
3. Add a [Custom Command](../02_uboot/custom_cmd/README.md)
4. Read [Bootargs Reference](bootargs_reference.md)
