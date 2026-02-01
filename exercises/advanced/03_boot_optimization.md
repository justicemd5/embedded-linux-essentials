# Exercise 3: Boot Time Optimization

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Reduce boot time from power-on to application start on BeagleBone Black. Master measurement techniques, identify bottlenecks, and apply optimizations at every boot stage.

## Prerequisites

- Working BeagleBone Black with custom kernel
- U-Boot source and ability to rebuild
- Serial console for timing measurements
- grabserial tool (`pip3 install grabserial`)

## Difficulty: ⭐⭐⭐ Advanced

---

## 📁 Directory Structure

```
03_boot_optimization/
├── scripts/
│   ├── measure_baseline.sh    # Boot time measurement with grabserial
│   ├── analyze_boot.sh        # Boot log analysis and bottleneck ID
│   ├── generate_bootchart.sh  # Create visual boot timeline
│   └── apply_optimizations.sh # Apply optimizations to target
└── configs/
    ├── kernel_fast.config     # Kernel fragment for fast boot
    ├── uboot_fast.config      # U-Boot config for fast boot
    ├── boot_fast.txt          # Minimal U-Boot boot script
    ├── boot_falcon.txt        # Falcon Mode setup script
    └── grabserial.conf        # grabserial configurations
```

---

## Part 1: Boot Time Theory

### Understanding Boot Stages

```
┌─────────────────────────────────────────────────────────────────┐
│                    BOOT TIME BREAKDOWN                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ╔═══════════════╗                                             │
│  ║   POWER ON    ║ t=0                                         │
│  ╚═══════╤═══════╝                                             │
│          │                                                      │
│          ▼ (~0.5s)                                             │
│  ┌───────────────────────────────────────────────────┐         │
│  │ ROM BOOTLOADER (AM335x internal ROM)              │         │
│  │ • Initializes SRAM                                │         │
│  │ • Searches for MLO on MMC/SD/UART/USB            │         │
│  │ • FIXED - Cannot optimize                         │         │
│  └────────────────────┬──────────────────────────────┘         │
│                       │                                         │
│                       ▼ (~1-2s)                                │
│  ┌───────────────────────────────────────────────────┐         │
│  │ MLO/SPL (Secondary Program Loader)                │         │
│  │ • Initializes DRAM controller                     │         │
│  │ • Sets up clocks and PLLs                        │         │
│  │ • Loads U-Boot from storage                       │         │
│  │ ★ Optimization: Falcon Mode (skip U-Boot)        │         │
│  └────────────────────┬──────────────────────────────┘         │
│                       │                                         │
│                       ▼ (~2-4s)                                │
│  ┌───────────────────────────────────────────────────┐         │
│  │ U-BOOT (Main bootloader)                          │         │
│  │ • Autoboot delay (default 3s!)                   │         │
│  │ • Device initialization                           │         │
│  │ • Loads kernel + DTB + ramdisk                   │         │
│  │ ★ Optimization: bootdelay=0, silent, scripting   │         │
│  └────────────────────┬──────────────────────────────┘         │
│                       │                                         │
│                       ▼ (~3-8s)                                │
│  ┌───────────────────────────────────────────────────┐         │
│  │ LINUX KERNEL                                      │         │
│  │ • Hardware initialization (initcalls)            │         │
│  │ • Device driver probing                          │         │
│  │ • Filesystem mounting                            │         │
│  │ ★ Optimization: quiet, driver pruning, modules   │         │
│  └────────────────────┬──────────────────────────────┘         │
│                       │                                         │
│                       ▼ (~5-20s)                               │
│  ┌───────────────────────────────────────────────────┐         │
│  │ USERSPACE (init system)                           │         │
│  │ • systemd (slow) vs BusyBox init (fast)          │         │
│  │ • Service startup                                 │         │
│  │ • Application launch                              │         │
│  │ ★ Optimization: init choice, service pruning     │         │
│  └────────────────────┬──────────────────────────────┘         │
│                       │                                         │
│                       ▼                                         │
│  ╔═══════════════════════════════════════════════════╗         │
│  ║            APPLICATION READY                       ║         │
│  ╚═══════════════════════════════════════════════════╝         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Boot Time Budget Example

| Configuration | ROM | SPL | U-Boot | Kernel | Userspace | **Total** |
|--------------|-----|-----|--------|--------|-----------|-----------|
| **Unoptimized** | 0.5s | 1.5s | 4.0s | 5.0s | 15.0s | **26.0s** |
| **Optimized systemd** | 0.5s | 1.5s | 0.5s | 2.5s | 7.0s | **12.0s** |
| **BusyBox init** | 0.5s | 1.5s | 0.5s | 2.5s | 2.0s | **7.0s** |
| **Falcon Mode** | 0.5s | 2.0s | 0.0s | 2.5s | 2.0s | **7.0s** |
| **Extreme** | 0.5s | 1.0s | 0.0s | 1.5s | 0.5s | **3.5s** |

---

## Part 2: Measuring Boot Time

### Tool: grabserial

📁 **Configuration:** [configs/grabserial.conf](03_boot_optimization/configs/grabserial.conf)

```bash
# Install grabserial
pip3 install grabserial

# Basic measurement
grabserial -d /dev/ttyACM0 -b 115200 -t -m "U-Boot SPL" -q "login:"
```

### Measurement Script

📁 **Script:** [scripts/measure_baseline.sh](03_boot_optimization/scripts/measure_baseline.sh)

```bash
# Make executable
chmod +x 03_boot_optimization/scripts/*.sh

# Measure baseline boot time
./03_boot_optimization/scripts/measure_baseline.sh /dev/ttyACM0

# Output goes to ./measurements/boot_baseline_YYYYMMDD_HHMMSS.log
```

### Analysis Script

📁 **Script:** [scripts/analyze_boot.sh](03_boot_optimization/scripts/analyze_boot.sh)

```bash
# Analyze captured boot log
./03_boot_optimization/scripts/analyze_boot.sh measurements/boot_baseline_*.log

# Generates report with:
# - Stage timeline
# - Bottleneck identification
# - Top slowest initcalls
# - Optimization recommendations
```

### Enable Kernel Timestamps

```bash
# In U-Boot
setenv bootargs 'console=ttyO0,115200n8 root=/dev/mmcblk0p2 rootwait printk.time=1'
saveenv
```

### Enable Initcall Debug

```bash
# For detailed kernel analysis
setenv bootargs 'console=ttyO0,115200n8 root=/dev/mmcblk0p2 rootwait printk.time=1 initcall_debug'
saveenv
```

---

## Part 3: U-Boot Optimizations

📁 **Config:** [configs/uboot_fast.config](03_boot_optimization/configs/uboot_fast.config)
📁 **Boot Script:** [configs/boot_fast.txt](03_boot_optimization/configs/boot_fast.txt)

### Quick Wins

**1. Eliminate boot delay (saves 3s):**

```bash
# In U-Boot console
setenv bootdelay 0
saveenv
```

**2. Silent boot:**

```bash
setenv silent 1
saveenv
```

**3. Minimal boot script:**

```bash
# Compile optimized boot script
cd 03_boot_optimization/configs
mkimage -C none -A arm -T script -d boot_fast.txt boot.scr
scp boot.scr debian@192.168.7.2:/boot/
```

### Falcon Mode (Advanced)

📁 **Setup Script:** [configs/boot_falcon.txt](03_boot_optimization/configs/boot_falcon.txt)

Falcon Mode allows SPL to boot Linux directly, completely bypassing U-Boot proper. This saves 2-3 seconds but removes the U-Boot console.

```bash
# In U-Boot console (one-time setup):

# 1. Set minimal bootargs
setenv bootargs 'console=ttyO0,115200n8 root=/dev/mmcblk0p2 rootwait quiet'

# 2. Load kernel and DTB
mmc dev 0
load mmc 0:1 0x82000000 zImage
load mmc 0:1 0x88000000 am335x-boneblack.dtb

# 3. Export to SPL
spl export fdt 0x82000000 - 0x88000000

# 4. Save
saveenv
```

Recovery: Hold boot button during power-on to force U-Boot.

---

## Part 4: Kernel Optimizations

📁 **Config Fragment:** [configs/kernel_fast.config](03_boot_optimization/configs/kernel_fast.config)

### Bootargs Optimization

```bash
# Add to bootargs
quiet loglevel=0
```

### Apply Config Fragment

```bash
cd ~/bbb/linux

# Start with default
make am335x_evm_defconfig

# Merge fast boot options
scripts/kconfig/merge_config.sh .config \
    /path/to/03_boot_optimization/configs/kernel_fast.config

# Build
make -j$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
```

### Key Kernel Options

| Option | Effect | Savings |
|--------|--------|---------|
| `CONFIG_CC_OPTIMIZE_FOR_SIZE=y` | Smaller kernel | ~0.5s load |
| `CONFIG_KERNEL_LZO=y` | Fast decompression | ~0.3s |
| `CONFIG_PREEMPT_NONE=y` | Less scheduling overhead | ~0.2s |
| `CONFIG_HZ_100=y` | Reduced timer overhead | ~0.1s |
| Disable unused drivers | Less initcalls | 1-3s |

### Initcall Analysis

📁 **Script:** [scripts/generate_bootchart.sh](03_boot_optimization/scripts/generate_bootchart.sh)

```bash
# On target (with initcall_debug enabled)
dmesg > /tmp/dmesg.log
scp debian@192.168.7.2:/tmp/dmesg.log .

# Generate bootchart
./03_boot_optimization/scripts/generate_bootchart.sh dmesg.log

# View results
cat bootchart_summary.txt
```

---

## Part 5: Userspace Optimizations

📁 **Script:** [scripts/apply_optimizations.sh](03_boot_optimization/scripts/apply_optimizations.sh)

### Analyze Current State

```bash
# Connect and analyze
./03_boot_optimization/scripts/apply_optimizations.sh debian@192.168.7.2 --analyze
```

### Apply Optimizations

```bash
# Apply all optimizations
./03_boot_optimization/scripts/apply_optimizations.sh debian@192.168.7.2
```

### Manual systemd Optimization

```bash
# On BBB
systemd-analyze
systemd-analyze blame | head -20
systemd-analyze critical-chain

# Disable slow services
sudo systemctl disable bluetooth ModemManager avahi-daemon
sudo systemctl mask systemd-networkd-wait-online
```

### BusyBox Init Alternative

For fastest userspace boot, replace systemd with BusyBox init:

```bash
# In kernel bootargs
init=/linuxrc

# Or custom init script
init=/sbin/myinit
```

See [Exercise 09: Custom Init](09_custom_init.md) for details.

---

## Part 6: Advanced Techniques

### Read-Only Root Filesystem

```bash
# Create squashfs (compressed, fast mount)
mksquashfs rootfs/ rootfs.sqsh -comp lzo

# Use overlay for writable areas
mount -t overlay overlay -o lowerdir=/,upperdir=/tmp/upper,workdir=/tmp/work /merged
```

### Pre-linked Applications

```bash
# Pre-resolve dynamic library symbols
prelink -a -m -R -f /path/to/rootfs
```

### Application Hibernation (Fastest)

```bash
# Save application state to disk
# Boot directly into running application
# Requires custom kernel support
CONFIG_HIBERNATION=y
---

## Results Tracking Table

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
