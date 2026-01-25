# Board Recovery Guide

A comprehensive guide to recovering "bricked" embedded Linux boards and implementing robust recovery strategies.

## Why Recovery Skills Matter

In embedded systems development and production, boards can become unbootable due to:

- Failed firmware updates
- Corrupted bootloader or kernel
- Misconfigured boot parameters
- Damaged filesystems
- Hardware issues

Understanding recovery techniques is essential for:

- **Development**: Quick recovery from failed experiments
- **Production**: Field recovery procedures
- **Debugging**: Accessing systems that won't boot normally
- **Reliability**: Designing robust boot mechanisms

## What Does "Bricked" Mean?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BRICKED BOARD STATES                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  "Brick" Severity Levels:                                                   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ SOFT BRICK (Recoverable without hardware intervention)              │   │
│  │                                                                     │   │
│  │ • U-Boot works, kernel fails to boot                               │   │
│  │   → Recovery: Fix bootargs, load different kernel                  │   │
│  │                                                                     │   │
│  │ • Kernel boots, rootfs mount fails                                 │   │
│  │   → Recovery: Fix root=, boot initramfs, repair rootfs             │   │
│  │                                                                     │   │
│  │ • System boots but application crashes                             │   │
│  │   → Recovery: Serial console access, fix application               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ MEDIUM BRICK (Requires bootloader-level recovery)                   │   │
│  │                                                                     │   │
│  │ • U-Boot environment corrupted                                     │   │
│  │   → Recovery: Reset environment, TFTP boot                         │   │
│  │                                                                     │   │
│  │ • Kernel image corrupted                                           │   │
│  │   → Recovery: TFTP load good kernel, reflash                       │   │
│  │                                                                     │   │
│  │ • U-Boot corrupted but SPL works                                   │   │
│  │   → Recovery: SPL USB/UART recovery, reload U-Boot                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ HARD BRICK (Requires hardware intervention)                         │   │
│  │                                                                     │   │
│  │ • SPL corrupted                                                    │   │
│  │   → Recovery: Rewrite SD card, use UART boot mode                  │   │
│  │                                                                     │   │
│  │ • Boot ROM can't find valid image                                  │   │
│  │   → Recovery: External programmer, JTAG, boot mode pins            │   │
│  │                                                                     │   │
│  │ • eFuses blown incorrectly                                         │   │
│  │   → Recovery: Often not possible (permanent)                       │   │
│  │                                                                     │   │
│  │ • Hardware failure                                                 │   │
│  │   → Recovery: Replace hardware                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Recovery Methods Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      RECOVERY METHODS HIERARCHY                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Try these in order (easiest to hardest):                                   │
│                                                                             │
│  1. Serial Console Recovery                                                 │
│     └── Access U-Boot prompt, fix environment, boot from network           │
│                                                                             │
│  2. TFTP Recovery                                                           │
│     └── Download good images via network                                    │
│                                                                             │
│  3. USB Recovery                                                            │
│     └── Boot from USB device with recovery images                          │
│                                                                             │
│  4. SD Card Reflash                                                         │
│     └── Remove SD, rewrite on host computer                                │   │
│                                                                             │
│  5. UART/USB Boot Mode                                                      │
│     └── Use ROM code's serial download feature                             │
│                                                                             │
│  6. JTAG/SWD                                                                │
│     └── Direct memory access for debugging/recovery                        │
│                                                                             │
│  7. Hardware Programmer                                                     │
│     └── Direct flash programming (SPI, NAND)                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Serial Console Recovery

### Setup

```bash
# Connect USB-to-UART adapter
# Identify device
dmesg | grep tty
# Usually /dev/ttyUSB0 or /dev/ttyACM0

# Open serial console (115200 baud, 8N1)
minicom -D /dev/ttyUSB0 -b 115200
# or
picocom -b 115200 /dev/ttyUSB0
# or
screen /dev/ttyUSB0 115200
```

### Interrupt Autoboot

```
U-Boot 2024.01 (Jan 01 2024)

DRAM:  512 MiB
MMC:   mmc@7e202000: 0
Hit any key to stop autoboot:  3    ← PRESS ANY KEY HERE!
=>
```

### Fix Environment Issues

```bash
# View current environment
=> printenv

# Reset to defaults if corrupted
=> env default -a
=> saveenv

# Fix specific variables
=> setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rw'
=> setenv bootcmd 'run mmc_boot'
=> saveenv
```

### Boot from Alternate Source

```bash
# Try different partitions
=> load mmc 0:1 ${loadaddr} zImage.backup
=> bootz ${loadaddr} - ${fdt_addr}

# Try USB
=> usb start
=> load usb 0:1 ${loadaddr} zImage
=> bootz ${loadaddr} - ${fdt_addr}

# Network boot (if U-Boot has network)
=> dhcp
=> tftp ${loadaddr} zImage
=> tftp ${fdt_addr} board.dtb
=> bootz ${loadaddr} - ${fdt_addr}
```

## TFTP Recovery

### Host Setup

```bash
# Install and configure TFTP server
sudo apt-get install tftpd-hpa

# Create TFTP directory
sudo mkdir -p /tftpboot
sudo chmod 777 /tftpboot

# Copy recovery images
sudo cp zImage /tftpboot/
sudo cp board.dtb /tftpboot/
sudo cp rootfs.tar.gz /tftpboot/

# Restart TFTP server
sudo systemctl restart tftpd-hpa
```

### Target Recovery via TFTP

```bash
# Set network parameters
=> setenv ipaddr 192.168.1.50
=> setenv serverip 192.168.1.100
=> setenv netmask 255.255.255.0

# Test connectivity
=> ping ${serverip}
# Output: host 192.168.1.100 is alive

# Download kernel
=> tftp ${loadaddr} zImage
# Bytes transferred = 5242880

# Download DTB
=> tftp ${fdt_addr} board.dtb

# Boot with minimal bootargs
=> setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rw
=> bootz ${loadaddr} - ${fdt_addr}

# If successful, reflash permanent storage
# ... (from booted recovery system)
```

### TFTP Recovery of Entire System

```bash
# Boot into recovery initramfs via TFTP
=> tftp ${loadaddr} zImage
=> tftp ${fdt_addr} board.dtb
=> tftp ${ramdisk_addr} recovery-initramfs.cpio.gz
=> setenv bootargs console=ttyS0,115200 rdinit=/init
=> bootz ${loadaddr} ${ramdisk_addr}:${filesize} ${fdt_addr}

# Once booted into recovery initramfs:
# Download and flash new rootfs
wget http://192.168.1.100/rootfs.tar.gz
mount /dev/mmcblk0p2 /mnt
tar xzf rootfs.tar.gz -C /mnt
umount /mnt
reboot
```

## USB Recovery Boot

### Creating USB Recovery Drive

```bash
# On host: Prepare USB drive
sudo fdisk /dev/sdb
# Create partition, type 0x0C (FAT32 LBA)

# Format as FAT32
sudo mkfs.vfat -F 32 /dev/sdb1

# Mount and copy files
sudo mount /dev/sdb1 /mnt
sudo cp zImage /mnt/
sudo cp board.dtb /mnt/
sudo cp recovery-initramfs.cpio.gz /mnt/
sudo umount /mnt
```

### Booting from USB

```bash
# Initialize USB
=> usb start
=> usb storage

# List files
=> fatls usb 0:1

# Load and boot
=> load usb 0:1 ${loadaddr} zImage
=> load usb 0:1 ${fdt_addr} board.dtb
=> setenv bootargs console=ttyS0,115200 root=/dev/sda2 rootwait rw
=> bootz ${loadaddr} - ${fdt_addr}
```

## SD Card Reflash

When all else fails, remove the SD card and reflash on host:

### Identify SD Card

```bash
# Insert SD card and identify device
lsblk
# Look for new device, usually /dev/sdb or /dev/mmcblk0

# CAUTION: Double-check device name!
```

### Backup (if possible)

```bash
# Create full image backup
sudo dd if=/dev/sdb of=sd_backup.img bs=4M status=progress
```

### Reflash Complete Image

```bash
# Write pre-built image
sudo dd if=recovery-image.img of=/dev/sdb bs=4M status=progress
sync
```

### Reflash Individual Partitions

```bash
# Partition SD card
sudo fdisk /dev/sdb
# Create:
# Partition 1: 100MB, type 0x0C (FAT32 LBA), bootable
# Partition 2: Remaining, type 0x83 (Linux)

# Format partitions
sudo mkfs.vfat -F 32 -n BOOT /dev/sdb1
sudo mkfs.ext4 -L rootfs /dev/sdb2

# Mount and copy boot files
sudo mount /dev/sdb1 /mnt
sudo cp MLO u-boot.img zImage *.dtb /mnt/
sudo umount /mnt

# Mount and extract rootfs
sudo mount /dev/sdb2 /mnt
sudo tar xf rootfs.tar -C /mnt
sudo umount /mnt
```

## UART Boot Mode (ROM Recovery)

Many SoCs support loading code via UART when no valid boot image is found:

### AM335x (BeagleBone) UART Boot

```bash
# Set boot mode pins to UART boot (check schematic)
# Or rely on boot fallback (tries UART after other sources fail)

# Use xmodem to send SPL
sx MLO < /dev/ttyUSB0 > /dev/ttyUSB0

# Or use imx_uart_loader for i.MX
# Or use STM32CubeProgrammer for STM32MP1
```

### Raspberry Pi Recovery

```bash
# Raspberry Pi doesn't have UART boot in the traditional sense
# Recovery: Remove SD card, mount on host, fix boot files

# Or use USB boot mode (Pi 3 and later):
# 1. Set OTP bit to enable USB boot (one-time)
# 2. Boot from USB drive with working image
```

## Debug Bootargs for Recovery

### Maximum Verbosity

```bash
setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rw \
    earlyprintk \
    loglevel=8 \
    debug \
    ignore_loglevel \
    initcall_debug \
    printk.time=1
```

### Boot to Shell

```bash
# Boot to shell instead of init (bypasses broken init)
setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rw init=/bin/sh

# Once in shell, fix issues:
mount -o remount,rw /
# Edit files, fix problems
exec /sbin/init
```

### Single User Mode

```bash
# Some systems support single user mode
setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rw single
# Or
setenv bootargs ... 1
# Or  
setenv bootargs ... S
```

## Designing Robust Recovery Systems

### A/B Partition Scheme

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       A/B RECOVERY DESIGN                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Storage Layout:                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Part 1: Boot (FAT32)                                                │   │
│  │ ├── zImage.A, board.dtb.A   (Slot A boot files)                    │   │
│  │ └── zImage.B, board.dtb.B   (Slot B boot files)                    │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ Part 2: RootFS A (ext4)      ← Active slot                         │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ Part 3: RootFS B (ext4)      ← Backup slot                         │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ Part 4: Data (ext4)          ← Persistent user data                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  U-Boot Logic:                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ if boot_slot == A:                                                  │   │
│  │     try boot from slot A                                            │   │
│  │     if fails 3 times:                                               │   │
│  │         switch to slot B                                            │   │
│  │ else:                                                               │   │
│  │     try boot from slot B                                            │   │
│  │     if fails 3 times:                                               │   │
│  │         switch to slot A                                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Boot Counter Implementation

```bash
# In U-Boot environment:

# Increment boot counter
setenv bootcmd 'setexpr boot_count ${boot_count} + 1; saveenv; run try_boot'

# Check counter and fallback
setenv try_boot '\
    if test ${boot_count} -gt 3; then \
        echo "Too many boot failures, switching slot"; \
        if test ${boot_slot} = A; then \
            setenv boot_slot B; \
        else \
            setenv boot_slot A; \
        fi; \
        setenv boot_count 0; \
        saveenv; \
    fi; \
    run boot_${boot_slot}'

# Reset counter on successful boot (from Linux init script)
# fw_setenv boot_count 0
```

### Watchdog Integration

```bash
# Start watchdog in U-Boot before booting kernel
# Kernel/application must kick watchdog regularly
# If system hangs, watchdog resets → U-Boot sees failed boot

# In U-Boot:
wdt start 60000  # 60 second timeout

# In Linux:
# Kernel takes over watchdog
# Application must open /dev/watchdog and write periodically
```

## Recovery Checklist

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     RECOVERY TROUBLESHOOTING CHECKLIST                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  □ Check power supply (5V, sufficient current)                              │
│  □ Check serial console connection (TX→RX, RX→TX, GND→GND)                 │
│  □ Verify baud rate (usually 115200)                                        │
│  □ Try different USB-to-UART adapter                                        │
│                                                                             │
│  If no output at all:                                                       │
│  □ Check if board powers on (LEDs, power consumption)                       │
│  □ Verify boot mode pins/jumpers                                            │
│  □ Try different SD card                                                    │
│  □ Reflash SD card on host                                                  │
│                                                                             │
│  If U-Boot starts but kernel fails:                                         │
│  □ Check bootargs (console, root device)                                    │
│  □ Enable earlyprintk and debug                                             │
│  □ Try known-good kernel                                                    │
│  □ Boot from network (TFTP)                                                 │
│                                                                             │
│  If kernel starts but init fails:                                           │
│  □ Boot with init=/bin/sh                                                   │
│  □ Check rootfs integrity                                                   │
│  □ Verify init binary exists and is executable                              │
│  □ Check for missing libraries                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## What You Learned

After reading this document, you understand:

1. ✅ Different levels of "bricked" boards
2. ✅ Recovery methods hierarchy (easiest to hardest)
3. ✅ How to use serial console for recovery
4. ✅ TFTP recovery procedures
5. ✅ USB and SD card recovery methods
6. ✅ UART boot mode for ROM-level recovery
7. ✅ Debug bootargs for troubleshooting
8. ✅ A/B partition schemes for robust recovery
9. ✅ Boot counter and watchdog integration
10. ✅ Recovery troubleshooting checklist

---

## Next Steps

1. Complete [Lab 07: Recovery](../07_recovery/README.md)
2. Practice [TFTP Recovery](../07_recovery/tftp_recovery.md)
3. Learn [UART Debugging](../07_recovery/uart_debugging.md)
4. Implement recovery mechanism in exercises
