# Bootargs Reference

A comprehensive reference for Linux kernel command line parameters (bootargs) in Embedded Linux systems.

## Why Bootargs Matter

Bootargs (kernel command line parameters) control how the Linux kernel behaves during and after boot. Understanding bootargs is essential because:

- **Boot Source Selection**: Control where the root filesystem comes from
- **Debugging**: Enable kernel debugging features without recompiling
- **Console Configuration**: Direct kernel output to correct device
- **Hardware Configuration**: Pass parameters to drivers
- **Same kernel, different behavior**: Change boot behavior without rebuilding

## How Bootargs Work

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BOOTARGS FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  U-Boot                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rw'      │   │
│  │                                         │                           │   │
│  │ bootz ${loadaddr} - ${fdt_addr}        │                           │   │
│  │         │                               │                           │   │
│  │         └── Passes bootargs to kernel ──┘                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                         │                                   │
│                                         v                                   │
│  Kernel                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Receives bootargs from bootloader (or from DTB chosen node)      │   │
│  │ 2. Parses each parameter                                            │   │
│  │ 3. Core kernel handles known parameters                             │   │
│  │ 4. Drivers check for their specific parameters                      │   │
│  │ 5. Unknown parameters passed to init as arguments/environment       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                         │                                   │
│                                         v                                   │
│  /proc/cmdline (viewable at runtime)                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ $ cat /proc/cmdline                                                 │   │
│  │ console=ttyS0,115200 root=/dev/mmcblk0p2 rw                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Essential Bootargs Categories

### 1. Console Configuration

```bash
# Basic serial console
console=ttyS0,115200

# Format: console=<device>,<baud><parity><bits><flow>
# device: ttyS0, ttyAMA0, ttyO0, etc. (depends on platform)
# baud: 9600, 19200, 38400, 57600, 115200
# parity: n (none), o (odd), e (even)
# bits: 7 or 8
# flow: r (RTS/CTS)

# Examples:
console=ttyS0,115200n8          # 115200 baud, no parity, 8 bits
console=ttyAMA0,115200          # Raspberry Pi UART
console=ttyO0,115200            # BeagleBone UART
console=tty0                    # VGA/HDMI console

# Multiple consoles (output to all, input from last)
console=tty0 console=ttyS0,115200
```

### 2. Root Filesystem Configuration

```bash
# Root device specification
root=/dev/mmcblk0p2             # SD card partition 2
root=/dev/sda1                  # USB drive partition 1
root=/dev/nfs                   # NFS root
root=PARTUUID=xxx-xxx           # By partition UUID
root=LABEL=rootfs               # By filesystem label
root=/dev/ram0                  # RAM disk (initramfs)

# Filesystem type
rootfstype=ext4                 # Explicit filesystem type
rootfstype=squashfs             # Read-only compressed

# Mount options
rw                              # Mount read-write
ro                              # Mount read-only (for squashfs, etc.)

# Wait for device
rootwait                        # Wait indefinitely for root device
rootdelay=5                     # Wait 5 seconds before mounting
```

### 3. Init Process

```bash
init=/sbin/init                 # Standard init
init=/bin/sh                    # Boot to shell (debugging)
init=/linuxrc                   # BusyBox style
rdinit=/init                    # Init in initramfs

# Pass arguments to init
-- arg1 arg2                    # Arguments after -- go to init
```

## Boot Scenarios with Bootargs

### Scenario 1: SD Card Boot

```bash
# Typical SD card boot
setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw'

# Breakdown:
# console=ttyS0,115200    - Serial console at 115200 baud
# root=/dev/mmcblk0p2     - Second partition of first MMC device
# rootfstype=ext4         - Expect ext4 filesystem
# rootwait                - Wait for SD card to be ready
# rw                      - Mount read-write
```

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      SD CARD BOOT DIAGRAM                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   SD Card Layout:                                                           │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │ mmcblk0                                                           │    │
│   │ ├── mmcblk0p1 (FAT32, boot)   ← kernel, DTB, bootloader          │    │
│   │ └── mmcblk0p2 (ext4, rootfs)  ← root= points here                │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│   bootargs flow:                                                            │
│   root=/dev/mmcblk0p2 ────► Kernel mounts /dev/mmcblk0p2 as /              │
│   rootfstype=ext4 ────────► Uses ext4 filesystem driver                    │
│   rw ─────────────────────► Mount with read-write permissions              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Scenario 2: Initramfs Boot

```bash
# Initramfs-only boot (no root= needed)
setenv bootargs 'console=ttyS0,115200 rdinit=/init'

# Initramfs with switch to real root
setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rw'
# (Init script in initramfs handles the switch)

# Initramfs for debugging
setenv bootargs 'console=ttyS0,115200 rdinit=/bin/sh'
# Boots directly to shell in initramfs
```

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     INITRAMFS BOOT DIAGRAM                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Memory Layout:                                                            │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │ RAM                                                               │    │
│   │ ├── Kernel (loaded by U-Boot)                                     │    │
│   │ ├── DTB (loaded by U-Boot)                                        │    │
│   │ └── initramfs.cpio.gz (loaded by U-Boot, unpacked by kernel)     │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│   Boot flow:                                                                │
│   1. Kernel unpacks initramfs to tmpfs                                      │
│   2. Kernel runs rdinit=/init (or /init by default)                        │
│   3. Init script prepares real root (optional)                             │
│   4. switch_root to real filesystem (optional)                             │
│                                                                             │
│   U-Boot command:                                                           │
│   bootz ${loadaddr} ${initrd_addr}:${initrd_size} ${fdt_addr}              │
│                      ▲                                                      │
│                      └── initramfs address and size                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Scenario 3: NFS Root Boot

```bash
# NFS root with DHCP
setenv bootargs 'console=ttyS0,115200 root=/dev/nfs \
    nfsroot=192.168.1.100:/export/rootfs,v3,tcp ip=dhcp'

# NFS root with static IP
setenv bootargs 'console=ttyS0,115200 root=/dev/nfs \
    nfsroot=192.168.1.100:/export/rootfs,v3,tcp \
    ip=192.168.1.50:192.168.1.100:192.168.1.1:255.255.255.0::eth0:off'
```

**IP parameter format:**
```
ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>

client-ip  : Board's IP address
server-ip  : NFS/TFTP server IP
gw-ip      : Gateway IP
netmask    : Network mask
hostname   : Board's hostname (optional)
device     : Network interface (eth0, usb0, etc.)
autoconf   : off, dhcp, bootp, rarp, any
```

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      NFS BOOT DIAGRAM                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Network Setup:                                                            │
│   ┌──────────────────┐         ┌──────────────────────────────────────┐    │
│   │ Target Board     │         │ Host Server                          │    │
│   │ IP: DHCP or      │◄───────►│ IP: 192.168.1.100                   │    │
│   │     192.168.1.50 │ Network │ NFS export: /export/rootfs           │    │
│   └──────────────────┘         └──────────────────────────────────────┘    │
│                                                                             │
│   bootargs flow:                                                            │
│   root=/dev/nfs ───────────► Kernel knows to use NFS for root             │
│   nfsroot=... ─────────────► Server IP, path, and options                  │
│   ip=dhcp ─────────────────► Get IP via DHCP before mounting NFS          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Scenario 4: Debugging Boot

```bash
# Maximum debug output
setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rw \
    earlyprintk earlycon loglevel=8 debug ignore_loglevel'

# Quiet boot (minimal output)
setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rw quiet'

# Boot to emergency shell
setenv bootargs 'console=ttyS0,115200 init=/bin/sh'
```

## Complete Bootargs Reference

### Kernel Core Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `console=` | Console device | `console=ttyS0,115200` |
| `root=` | Root device | `root=/dev/mmcblk0p2` |
| `rootfstype=` | Filesystem type | `rootfstype=ext4` |
| `rootwait` | Wait for root device | (no value) |
| `rootdelay=` | Delay before mount | `rootdelay=5` |
| `rw` | Mount root read-write | (no value) |
| `ro` | Mount root read-only | (no value) |
| `init=` | Init program | `init=/sbin/init` |
| `rdinit=` | Init in initramfs | `rdinit=/init` |

### Debugging Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `debug` | Enable debug output | (no value) |
| `earlyprintk` | Early boot messages | (no value) |
| `earlycon` | Early console | `earlycon=uart8250,mmio,0x...` |
| `loglevel=` | Kernel log level (0-7) | `loglevel=7` |
| `ignore_loglevel` | Show all messages | (no value) |
| `quiet` | Suppress most messages | (no value) |
| `initcall_debug` | Debug init calls | (no value) |
| `printk.time=1` | Add timestamps | (no value) |

### Memory Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `mem=` | Limit usable memory | `mem=512M` |
| `memtest` | Run memory test | (no value) |
| `memblock=debug` | Memory debug | (no value) |

### NFS Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `nfsroot=` | NFS root path | `nfsroot=192.168.1.100:/rootfs` |
| `nfsrootdebug` | NFS mount debug | (no value) |
| `ip=` | IP configuration | `ip=dhcp` |

### Module Parameters

```bash
# Format: module_name.parameter=value
# Example for 8250 serial driver:
8250.nr_uarts=4

# Example for USB storage:
usb-storage.quirks=0x1234:0x5678:u

# Generic parameters
module_blacklist=bad_module      # Don't load module
```

## Quick Reference Cards

### SD Card Boot Template

```bash
setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw'
setenv bootcmd 'load mmc 0:1 ${loadaddr} zImage; load mmc 0:1 ${fdt_addr} board.dtb; bootz ${loadaddr} - ${fdt_addr}'
```

### Initramfs Boot Template

```bash
setenv bootargs 'console=ttyS0,115200 rdinit=/init'
setenv bootcmd 'load mmc 0:1 ${loadaddr} zImage; load mmc 0:1 ${fdt_addr} board.dtb; load mmc 0:1 ${initrd_addr} initramfs.cpio.gz; bootz ${loadaddr} ${initrd_addr}:${filesize} ${fdt_addr}'
```

### NFS Boot Template

```bash
setenv bootargs 'console=ttyS0,115200 root=/dev/nfs nfsroot=${serverip}:/export/rootfs,v3,tcp ip=dhcp'
setenv bootcmd 'dhcp; tftp ${loadaddr} zImage; tftp ${fdt_addr} board.dtb; bootz ${loadaddr} - ${fdt_addr}'
```

### Debug Boot Template

```bash
setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rw earlyprintk loglevel=8 debug'
```

## Changing Boot Behavior: Examples

### Example: Same Kernel, Different Root Sources

```bash
# Scenario: You have one kernel, want to boot from different sources

# Option 1: SD Card Root
setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait rw'

# Option 2: USB Root
setenv bootargs 'console=ttyS0,115200 root=/dev/sda1 rootwait rw'

# Option 3: NFS Root
setenv bootargs 'console=ttyS0,115200 root=/dev/nfs nfsroot=192.168.1.100:/rootfs ip=dhcp'

# Option 4: Initramfs Only
setenv bootargs 'console=ttyS0,115200 rdinit=/init'

# All use same kernel and DTB - only bootargs changes!
```

## Common Mistakes and Debugging

### Mistake 1: Wrong Console Device

```bash
# Symptom: No kernel output after "Starting kernel..."

# Check your platform's UART name:
# Raspberry Pi: ttyAMA0 or ttyS0
# BeagleBone: ttyO0 or ttyS0
# i.MX: ttymxc0
# STM32MP1: ttySTM0

# Debug: Try different console devices
console=ttyS0,115200
console=ttyAMA0,115200
console=ttyO0,115200
```

### Mistake 2: Missing rootwait

```bash
# Symptom: VFS: Cannot open root device "mmcblk0p2"

# Problem: Kernel tries to mount before SD card is ready
# Solution: Add rootwait
root=/dev/mmcblk0p2 rootwait rw
```

### Mistake 3: Wrong Device Name

```bash
# Symptom: VFS: Cannot open root device "mmcblk0p2"

# Debug: Boot with init=/bin/sh, then check devices
ls /dev/mmc*
ls /dev/sd*
cat /proc/partitions

# Device names vary:
# SD in internal slot: mmcblk0
# SD in USB reader: sda
# eMMC: mmcblk1 (sometimes)
```

### Viewing Bootargs at Runtime

```bash
# On running system:
cat /proc/cmdline

# In dmesg:
dmesg | grep "Command line"
dmesg | grep "Kernel command line"
```

## What You Learned

After reading this document, you understand:

1. ✅ How bootargs flow from U-Boot to kernel
2. ✅ Essential console configuration parameters
3. ✅ Root filesystem configuration options
4. ✅ How to configure bootargs for SD card boot
5. ✅ How to configure bootargs for initramfs boot
6. ✅ How to configure bootargs for NFS boot
7. ✅ Debugging parameters for kernel issues
8. ✅ How changing bootargs changes boot behavior
9. ✅ Common bootargs mistakes and fixes

---

## Next Steps

1. Practice changing bootargs in [Lab 02: U-Boot](../02_uboot/README.md)
2. Try different boot scenarios in exercises
3. Use bootargs for debugging in [Lab 07: Recovery](../07_recovery/README.md)
