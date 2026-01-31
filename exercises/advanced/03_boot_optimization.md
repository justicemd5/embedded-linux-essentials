# Exercise 3: Boot Time Optimization

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Reduce boot time from power-on to application start on BeagleBone Black.

## Prerequisites

- Working BeagleBone Black with custom kernel
- U-Boot source and ability to rebuild
- Serial console for timing measurements
- Stopwatch or timestamp analysis tools

## Difficulty: ⭐⭐⭐ Advanced

---

## Tasks

1. Measure baseline boot time
2. Identify bottlenecks at each stage
3. Apply optimizations to U-Boot, kernel, and userspace
4. Measure and document improvement

---

## BeagleBone Black Boot Stages

```
┌─────────────────────────────────────────────────────────────┐
│                 BBB BOOT TIME BREAKDOWN                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Power On                                                   │
│     │                                                       │
│     ▼ (~0.5s)                                              │
│  ROM Bootloader (fixed, cannot optimize)                    │
│     │                                                       │
│     ▼ (~1-2s)                                              │
│  MLO/SPL ──────────► Opportunity: Minimal SPL              │
│     │                                                       │
│     ▼ (~2-4s)                                              │
│  U-Boot ───────────► Opportunity: bootdelay, silent mode   │
│     │                                                       │
│     ▼ (~3-8s)                                              │
│  Kernel ───────────► Opportunity: config, initcall order   │
│     │                                                       │
│     ▼ (~5-20s)                                             │
│  Userspace ────────► Opportunity: init system, services    │
│     │                                                       │
│     ▼                                                       │
│  Application Ready                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Guide

### Step 1: Measure Baseline Boot Time

**Enable kernel timestamps:**

```bash
# Add to U-Boot bootargs
setenv bootargs 'console=ttyO0,115200n8 root=/dev/mmcblk0p2 rootwait printk.time=1'
saveenv
```

**Capture boot log:**

```bash
# On host - capture with timestamps
script -t 2>timing.txt boot.log
screen /dev/ttyACM0 115200
# Power cycle BBB, wait for login prompt
# Exit screen (Ctrl-A, \)
exit

# Analyze timing
scriptreplay timing.txt boot.log
```

**Measure with grabserial (recommended):**

```bash
# Install grabserial
pip3 install grabserial

# Capture with hardware timestamps
grabserial -d /dev/ttyACM0 -b 115200 -t -m "U-Boot SPL" -q "login:"
```

### Step 2: Analyze Baseline

**Typical BBB unoptimized boot:**

| Stage | Time | Cumulative |
|-------|------|------------|
| ROM → MLO | ~0.5s | 0.5s |
| MLO → U-Boot | ~1.5s | 2.0s |
| U-Boot delay | 3.0s | 5.0s |
| U-Boot → Kernel | ~1.0s | 6.0s |
| Kernel init | ~5.0s | 11.0s |
| Userspace (systemd) | ~15.0s | 26.0s |
| **Total** | | **~26s** |

---

## Optimization Techniques

### U-Boot Optimizations

**1. Eliminate boot delay:**

```bash
# In U-Boot console
setenv bootdelay 0
saveenv
```

**2. Silent boot (optional):**

```bash
# Disable console output
setenv silent 1
saveenv
```

**3. Optimize U-Boot config:**

```bash
# In am335x_evm_defconfig or menuconfig
CONFIG_BOOTDELAY=0
# CONFIG_CMD_NET is not set        # If not using network boot
# CONFIG_CMD_USB is not set        # If not using USB boot
# CONFIG_CMD_FPGA is not set       # Not needed on BBB
CONFIG_SILENT_CONSOLE=y            # Optional silent mode
```

**4. Use Falcon Mode (skip U-Boot):**

```bash
# SPL boots kernel directly - advanced!
# Saves ~2 seconds but loses U-Boot flexibility
CONFIG_SPL_OS_BOOT=y
```

### Kernel Optimizations

**1. Kernel command line:**

```bash
# Add to bootargs
quiet loglevel=0
```

**2. Kernel config optimizations:**

```bash
make menuconfig

# Disable debug features
# CONFIG_DEBUG_INFO is not set
# CONFIG_DEBUG_KERNEL is not set
# CONFIG_PRINTK_TIME is not set    # After measurement!

# Optimize for size
CONFIG_CC_OPTIMIZE_FOR_SIZE=y

# Disable unused features
# CONFIG_USB_SUPPORT is not set    # If not using USB
# CONFIG_SOUND is not set          # If not using audio
# CONFIG_INPUT_EVDEV is not set    # If not using input

# Enable deferred initcalls (6.x+)
CONFIG_DEFERRED_INITCALLS=y
```

**3. Analyze initcall times:**

```bash
# Add to bootargs
initcall_debug

# After boot
dmesg | grep "initcall" | sort -k2 -t'=' -n | tail -20
```

**4. Use kernel compression wisely:**

```bash
# LZO is faster to decompress than GZIP
CONFIG_KERNEL_LZO=y
# Or no compression if storage is fast
CONFIG_KERNEL_UNCOMPRESSED=y
```

### Userspace Optimizations

**1. Analyze systemd (if used):**

```bash
systemd-analyze
systemd-analyze blame
systemd-analyze critical-chain
```

**2. Disable unnecessary services:**

```bash
systemctl disable bluetooth
systemctl disable ModemManager
systemctl disable cups
systemctl disable avahi-daemon
# Keep only essential services
```

**3. Use simpler init system:**

```bash
# BusyBox init is much faster than systemd
# See Exercise 09: Custom Init System
```

**4. Parallel service startup:**

```bash
# In /etc/systemd/system.conf
DefaultDependencies=no
```

**5. Filesystem optimization:**

```bash
# Use faster filesystem
# ext4 with journal disabled for read-only rootfs
tune2fs -O ^has_journal /dev/mmcblk0p2

# Or use squashfs for read-only rootfs
mksquashfs rootfs/ rootfs.sqsh -comp lzo
```

---

## Advanced: Create Boot Graph

```bash
# Kernel boot graph
# Add to bootargs: initcall_debug

# After boot, on target:
dmesg > /tmp/boot.log

# Copy to host
scp debian@192.168.7.2:/tmp/boot.log .

# Generate graph (from kernel source)
./scripts/bootgraph.pl boot.log > boot.svg
```

---

## BBB-Specific Optimizations

### Optimize Device Tree Loading

```bash
# Load DTB from known location, skip auto-detect
setenv fdtfile am335x-boneblack.dtb
# Don't search for overlays on boot
setenv uboot_overlay_options ""
```

### Skip eMMC if Booting from SD

```bash
# In U-Boot, force SD boot
setenv mmcdev 0
setenv mmcpart 1
```

### Pre-link Critical Applications

```bash
# On build host
prelink -a -m -R -f /path/to/rootfs
```

---

## Results Tracking

| Stage | Baseline | Optimized | Savings |
|-------|----------|-----------|---------|
| ROM → MLO | 0.5s | 0.5s | 0s |
| MLO → U-Boot | 1.5s | 1.5s | 0s |
| U-Boot | 4.0s | 0.5s | **3.5s** |
| Kernel | 5.0s | 2.5s | **2.5s** |
| Userspace | 15.0s | 4.0s | **11.0s** |
| **Total** | **26.0s** | **9.0s** | **17.0s** |

---

## Target Metrics

| Configuration | Boot Time |
|---------------|-----------|
| Unoptimized Debian | 25-40s |
| Optimized systemd | 8-12s |
| BusyBox init | 4-6s |
| Falcon Mode + BusyBox | 2-4s |

---

## Verification Checklist

- [ ] Baseline boot time measured and documented
- [ ] U-Boot bootdelay set to 0
- [ ] Unnecessary kernel drivers disabled
- [ ] Kernel command line includes `quiet loglevel=0`
- [ ] Unnecessary services disabled
- [ ] Final boot time measured and compared
- [ ] All required functionality still works

---

[← Previous: Debug Kernel Panic](02_debug_kernel_panic.md) | [Back to Index](README.md) | [Next: A/B Partition →](04_ab_partition.md)
