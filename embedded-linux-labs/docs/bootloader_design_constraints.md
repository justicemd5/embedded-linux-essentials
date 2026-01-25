# Bootloader Design Constraints

Understanding the constraints that shape bootloader design in embedded systems: memory, storage, time, and reliability considerations.

## Why Understanding Constraints Matters

Bootloader design is fundamentally shaped by hardware and system constraints. Understanding these constraints helps you:

- **Make informed design decisions** about bootloader features
- **Debug boot failures** related to resource limitations
- **Optimize boot time** by understanding bottlenecks
- **Design reliable systems** with appropriate fallback mechanisms
- **Choose appropriate hardware** for your requirements

## The Four Primary Constraints

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BOOTLOADER DESIGN CONSTRAINTS                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                        ┌───────────────┐                                    │
│                        │    MEMORY     │                                    │
│                        │  Constraints  │                                    │
│                        └───────┬───────┘                                    │
│                                │                                            │
│            ┌───────────────────┼───────────────────┐                        │
│            │                   │                   │                        │
│  ┌─────────┴───────┐          │         ┌─────────┴───────┐                │
│  │    STORAGE      │          │         │   RELIABILITY   │                │
│  │   Constraints   │◄─────────┼────────►│   Constraints   │                │
│  └─────────────────┘          │         └─────────────────┘                │
│                               │                                            │
│                        ┌──────┴──────┐                                     │
│                        │    TIME     │                                     │
│                        │ Constraints │                                     │
│                        └─────────────┘                                     │
│                                                                             │
│  All four constraints interact and trade off against each other            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Memory Constraints

### The Fundamental Memory Problem

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      MEMORY CONSTRAINT OVERVIEW                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  At power-on, only INTERNAL memory is available:                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         CPU/SoC Die                                 │   │
│  │  ┌──────────────────┐     ┌──────────────────────────────────────┐  │   │
│  │  │    Boot ROM      │     │         Internal SRAM                │  │   │
│  │  │   32-128 KB      │     │          64-256 KB                   │  │   │
│  │  │   (read-only)    │     │         (read/write)                 │  │   │
│  │  └──────────────────┘     └──────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    ▲                                        │
│                                    │ SPL must fit here!                     │
│                                                                             │
│  External DRAM is NOT available until initialized by SPL                    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        External DRAM                                │   │
│  │                       512 MB - 8 GB                                 │   │
│  │                                                                     │   │
│  │         Only accessible AFTER DDR controller initialization         │   │
│  │         Requires precise timing configuration                       │   │
│  │         Training sequences for DDR3/DDR4                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### SRAM Size Comparison Across Platforms

| Platform | Internal SRAM | Typical SPL Size | Remaining for Stack/Heap |
|----------|--------------|------------------|-------------------------|
| AM335x (BBB) | 128 KB | 64-100 KB | 28-64 KB |
| i.MX6 | 256 KB | 80-120 KB | 136-176 KB |
| BCM2837 (RPi) | 512 KB* | N/A (GPU boots) | N/A |
| STM32MP1 | 256 KB | 100-150 KB | 106-156 KB |

*RPi uses GPU memory for initial boot; CPU boot is different

### Design Implications

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MEMORY CONSTRAINT IMPLICATIONS                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  SPL DESIGN:                                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Must fit in SRAM with stack + heap                                │   │
│  │ • Link-time size checking (CONFIG_SPL_MAX_SIZE)                     │   │
│  │ • Minimal driver set (only what's needed to load U-Boot)            │   │
│  │ • No complex features (no filesystem, minimal parsing)              │   │
│  │ • Static allocation preferred (predictable memory use)              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  U-BOOT DESIGN:                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Relocates itself to end of DRAM                                   │   │
│  │ • Uses memory map to avoid kernel/DTB load areas                    │   │
│  │ • Environment size limited (typically 8-128 KB)                     │   │
│  │ • Heap size must be configured appropriately                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  KERNEL/DTB PLACEMENT:                                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Kernel loaded at TEXT_OFFSET (e.g., 0x8000 from DRAM base)        │   │
│  │ • DTB loaded below kernel or with 128MB gap                         │   │
│  │ • initramfs loaded after kernel                                     │   │
│  │ • Addresses must be aligned (2MB for DTB)                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Example: U-Boot Memory Configuration

```c
// include/configs/am335x_evm.h (example)

/* DRAM Memory Map */
#define CONFIG_SYS_SDRAM_BASE       0x80000000  // DRAM starts here
#define CONFIG_SYS_SDRAM_SIZE       (512 << 20) // 512 MB

/* U-Boot placement (after relocation) */
#define CONFIG_SYS_TEXT_BASE        0x80800000  // Initial load address
#define CONFIG_SYS_INIT_SP_ADDR     (CONFIG_SYS_SDRAM_BASE + 0x1000 - \
                                     GENERATED_GBL_DATA_SIZE)

/* Kernel and DTB load addresses */
#define CONFIG_SYS_LOAD_ADDR        0x82000000  // Default load address
#define CONFIG_SYS_FDT_ADDR         0x88000000  // DTB load address

/* Environment */
#define CONFIG_ENV_SIZE             (128 << 10) // 128 KB
#define CONFIG_ENV_OFFSET           0x100000    // Offset in storage

/* Heap and stack */
#define CONFIG_SYS_MALLOC_LEN       (16 << 20)  // 16 MB heap
```

---

## 2. Storage Constraints

### Boot Media Characteristics

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     STORAGE CONSTRAINT OVERVIEW                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Different storage media have different characteristics:                     │
│                                                                             │
│  ┌─────────────────┬─────────────┬─────────────┬─────────────┬───────────┐ │
│  │     Media       │   Speed     │   Wear      │ Reliability │   Boot    │ │
│  │                 │             │             │             │  Support  │ │
│  ├─────────────────┼─────────────┼─────────────┼─────────────┼───────────┤ │
│  │ NOR Flash       │ Fast read   │ High wear   │ Very high   │ XIP       │ │
│  │                 │ Slow write  │ (100K)      │             │ possible  │ │
│  ├─────────────────┼─────────────┼─────────────┼─────────────┼───────────┤ │
│  │ NAND Flash      │ Fast        │ Medium      │ Medium      │ ECC       │ │
│  │                 │ read/write  │ (10K-100K)  │ (bit flips) │ required  │ │
│  ├─────────────────┼─────────────┼─────────────┼─────────────┼───────────┤ │
│  │ eMMC            │ Fast        │ Managed     │ High        │ Common    │ │
│  │                 │             │ internally  │             │           │ │
│  ├─────────────────┼─────────────┼─────────────┼─────────────┼───────────┤ │
│  │ SD Card         │ Variable    │ Managed     │ Medium      │ Common    │ │
│  │                 │             │ internally  │             │           │ │
│  ├─────────────────┼─────────────┼─────────────┼─────────────┼───────────┤ │
│  │ SPI Flash       │ Slow        │ High wear   │ High        │ Small     │ │
│  │                 │             │ (100K)      │             │ images    │ │
│  └─────────────────┴─────────────┴─────────────┴─────────────┴───────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Partition and Layout Constraints

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   STORAGE LAYOUT CONSTRAINTS                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  SD/eMMC Layout (MBR Partition Table):                                      │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Offset    │ Content          │ Notes                               │   │
│  ├───────────┼──────────────────┼─────────────────────────────────────┤   │
│  │ 0x0       │ MBR              │ Partition table (512 bytes)         │   │
│  │ 0x200     │ SPL (raw)        │ Some platforms read from here       │   │
│  │ 0x8000    │ U-Boot (raw)     │ Or at fixed offset for platform     │   │
│  │ Part 1    │ Boot (FAT32)     │ MLO, u-boot.img, zImage, DTB        │   │
│  │ Part 2    │ RootFS (ext4)    │ Linux root filesystem               │   │
│  │ Part 3    │ Data (optional)  │ Application data, persistent logs   │   │
│  └───────────┴──────────────────┴─────────────────────────────────────┘   │
│                                                                             │
│  NAND Layout (No partition table - raw offsets):                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Offset    │ Content          │ Notes                               │   │
│  ├───────────┼──────────────────┼─────────────────────────────────────┤   │
│  │ 0x0       │ SPL              │ Multiple copies for redundancy      │   │
│  │ 0x80000   │ SPL backup 1     │ ECC protected                       │   │
│  │ 0x100000  │ SPL backup 2     │ ECC protected                       │   │
│  │ 0x180000  │ U-Boot           │ Multiple copies possible            │   │
│  │ 0x300000  │ U-Boot env       │ Two copies for wear leveling        │   │
│  │ 0x380000  │ Kernel           │ UBI volume or raw                   │   │
│  │ 0x800000  │ RootFS (UBI)     │ UBIFS for wear leveling             │   │
│  └───────────┴──────────────────┴─────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Environment Storage Options

```bash
# U-Boot environment storage options (Kconfig)

# Store in MMC/SD
CONFIG_ENV_IS_IN_MMC=y
CONFIG_SYS_MMC_ENV_DEV=0        # MMC device number
CONFIG_SYS_MMC_ENV_PART=0       # Partition (0 = raw, 1/2 = boot/data)
CONFIG_ENV_OFFSET=0x100000      # Offset within device/partition
CONFIG_ENV_SIZE=0x20000         # 128 KB

# Store in SPI Flash
CONFIG_ENV_IS_IN_SPI_FLASH=y
CONFIG_ENV_OFFSET=0x80000       # Offset in SPI flash
CONFIG_ENV_SIZE=0x10000         # 64 KB
CONFIG_ENV_SECT_SIZE=0x10000    # Sector size for erase

# Store in NAND
CONFIG_ENV_IS_IN_NAND=y
CONFIG_ENV_OFFSET=0x300000
CONFIG_ENV_SIZE=0x20000
CONFIG_ENV_RANGE=0x40000        # Larger range for bad block handling

# Redundant environment (for reliability)
CONFIG_SYS_REDUNDAND_ENVIRONMENT=y
CONFIG_ENV_OFFSET_REDUND=0x120000  # Second copy offset
```

---

## 3. Time Constraints

### Boot Time Breakdown

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      TIME CONSTRAINT OVERVIEW                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Typical Boot Time Breakdown (Consumer Device):                              │
│                                                                             │
│  0s        1s        2s        3s        4s        5s        6s             │
│  ├─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤             │
│  │ ROM     │                                                                │
│  │◄──►50ms │                                                                │
│  │         │                                                                │
│  │    SPL  │                                                                │
│  │   ◄────►│ 200ms                                                          │
│  │         │                                                                │
│  │         U-Boot                                                           │
│  │         ◄─────────────────►│ 2s (with bootdelay)                         │
│  │                            │                                             │
│  │                            Kernel                                        │
│  │                            ◄───────────────────►│ 3s                     │
│  │                                                 │                        │
│  │                                                 Systemd/Init             │
│  │                                                 ◄────────►│ 2s          │
│  │                                                           │              │
│  │                                                           Application    │
│  ├─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤             │
│  0s        1s        2s        3s        4s        5s        6s             │
│                                                                             │
│  Total: ~6 seconds to first application                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Boot Time Optimization Strategies

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BOOT TIME OPTIMIZATION                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  SPL Optimization:                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Pre-compute DDR timing (no runtime calibration if possible)       │   │
│  │ • Remove unused drivers (SPL is already minimal)                    │   │
│  │ • Use fastest available boot media interface                        │   │
│  │ • Potential: 50-100ms savings                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  U-Boot Optimization:                                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Set bootdelay=0 (no autoboot delay)                               │   │
│  │ • Remove unused commands (reduce size, init time)                   │   │
│  │ • Skip network init if not needed                                   │   │
│  │ • Use Falcon Mode (SPL loads kernel directly)                       │   │
│  │ • Potential: 1-2 seconds savings                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Kernel Optimization:                                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Compile only needed drivers (no modules at boot)                  │   │
│  │ • Use uncompressed Image instead of zImage                          │   │
│  │ • Defer non-critical driver probing                                 │   │
│  │ • Reduce kernel log verbosity (quiet)                               │   │
│  │ • Use initramfs for fast early userspace                            │   │
│  │ • Potential: 1-3 seconds savings                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Init Optimization:                                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Start application early (before all services)                     │   │
│  │ • Parallel service startup (systemd)                                │   │
│  │ • Lazy load non-critical services                                   │   │
│  │ • Use simple init (BusyBox) instead of systemd                      │   │
│  │ • Potential: 1-5 seconds savings                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Falcon Mode (SPL Direct Kernel Boot)

```
Standard Boot:
  ROM → SPL → U-Boot → Kernel
              ▲
              └── 1-2 second overhead

Falcon Mode:
  ROM → SPL → Kernel (directly)
              ▲
              └── Skip U-Boot entirely!

Configuration:
  # Prepare Falcon Mode arguments (run once from U-Boot)
  => spl export fdt <kernel_addr> - <dtb_addr>
  
  # This saves kernel parameters to storage for SPL to use
  # SPL can then boot kernel directly without U-Boot
  
  # Enable in Kconfig:
  CONFIG_SPL_OS_BOOT=y
  CONFIG_SPL_FALCON_BOOT_MMCSD=y
```

---

## 4. Reliability Constraints

### Failure Modes and Mitigation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   RELIABILITY CONSTRAINT OVERVIEW                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  An embedded device must boot reliably because:                              │
│  • Often no physical access for recovery                                    │
│  • Power may be interrupted at any time                                     │
│  • Flash/storage wears out over time                                        │
│  • Field updates may fail partway through                                   │
│                                                                             │
│  Failure Modes and Mitigations:                                              │
│                                                                             │
│  ┌─────────────────┬─────────────────────────────────────────────────────┐ │
│  │ Failure Mode    │ Mitigation Strategy                                 │ │
│  ├─────────────────┼─────────────────────────────────────────────────────┤ │
│  │ Corrupted SPL   │ Multiple SPL copies in storage                      │ │
│  │                 │ ROM checks each copy in sequence                    │ │
│  ├─────────────────┼─────────────────────────────────────────────────────┤ │
│  │ Corrupted       │ Redundant environment (two copies)                  │ │
│  │ U-Boot env      │ CRC validation, fallback to default                 │ │
│  ├─────────────────┼─────────────────────────────────────────────────────┤ │
│  │ Corrupted       │ A/B partition scheme                                │ │
│  │ U-Boot          │ Try primary, fallback to backup                     │ │
│  ├─────────────────┼─────────────────────────────────────────────────────┤ │
│  │ Corrupted       │ A/B partition scheme                                │ │
│  │ kernel          │ Boot counter + rollback                             │ │
│  ├─────────────────┼─────────────────────────────────────────────────────┤ │
│  │ Corrupted       │ A/B partition scheme                                │ │
│  │ rootfs          │ Read-only rootfs + overlay                          │ │
│  │                 │ SquashFS + overlayfs                                │ │
│  ├─────────────────┼─────────────────────────────────────────────────────┤ │
│  │ Power loss      │ Atomic updates                                      │ │
│  │ during update   │ Copy-on-write filesystems                           │ │
│  │                 │ Journaling                                          │ │
│  ├─────────────────┼─────────────────────────────────────────────────────┤ │
│  │ Bad blocks      │ ECC (for NAND)                                      │ │
│  │ (NAND)          │ UBIFS/JFFS2 bad block handling                      │ │
│  │                 │ Multiple copies of critical data                    │ │
│  └─────────────────┴─────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### A/B Partition Scheme

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     A/B PARTITION SCHEME                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Storage Layout:                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │         Slot A                    │         Slot B                  │   │
│  │  ┌─────────────────────────┐     │  ┌─────────────────────────┐   │   │
│  │  │ Kernel A                │     │  │ Kernel B                │   │   │
│  │  │ (active)                │     │  │ (backup)                │   │   │
│  │  ├─────────────────────────┤     │  ├─────────────────────────┤   │   │
│  │  │ RootFS A                │     │  │ RootFS B                │   │   │
│  │  │ (mounted)               │     │  │ (idle)                  │   │   │
│  │  └─────────────────────────┘     │  └─────────────────────────┘   │   │
│  │                                   │                                │   │
│  │         ┌─────────────────────────────────────────┐               │   │
│  │         │          Shared Data Partition          │               │   │
│  │         │       (user data, configuration)        │               │   │
│  │         └─────────────────────────────────────────┘               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Update Process:                                                            │
│  1. Write new image to inactive slot (B)                                    │
│  2. Verify new image                                                        │
│  3. Set "next boot = B" flag                                                │
│  4. Reboot                                                                  │
│  5. If boot succeeds, mark B as good                                        │
│  6. If boot fails, bootloader automatically tries A                         │
│                                                                             │
│  U-Boot Implementation:                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ # In bootcmd:                                                       │   │
│  │ if test ${boot_slot} = A; then                                      │   │
│  │     setenv kernel_part 2                                            │   │
│  │     setenv rootfs_part 3                                            │   │
│  │ else                                                                │   │
│  │     setenv kernel_part 4                                            │   │
│  │     setenv rootfs_part 5                                            │   │
│  │ fi                                                                  │   │
│  │                                                                     │   │
│  │ # Boot counter for rollback                                         │   │
│  │ if test ${boot_count} -gt 3; then                                   │   │
│  │     echo "Too many boot failures, switching slot"                   │   │
│  │     setenv boot_slot A  # Fallback to A                             │   │
│  │     setenv boot_count 0                                             │   │
│  │     saveenv                                                         │   │
│  │ fi                                                                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Watchdog Timer Integration

```c
// Simplified watchdog integration concept

// In U-Boot:
// Start watchdog with timeout before booting kernel
wdt start 30000  // 30 second timeout

// In Linux kernel:
// Kernel takes over watchdog, must kick it regularly
// If kernel hangs, watchdog resets system

// In application:
int main() {
    int fd = open("/dev/watchdog", O_WRONLY);
    
    while (running) {
        // Application logic
        do_work();
        
        // Kick watchdog to prevent reset
        ioctl(fd, WDIOC_KEEPALIVE, NULL);
        
        sleep(10);  // Kick every 10 seconds
    }
    
    // Disable watchdog on clean shutdown
    write(fd, "V", 1);  // Magic close
    close(fd);
}
```

---

## Constraint Trade-offs

### The Design Triangle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DESIGN TRADE-OFFS                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                           Fast Boot                                         │
│                              ▲                                              │
│                             /│\                                             │
│                            / │ \                                            │
│                           /  │  \                                           │
│                          /   │   \                                          │
│                         /    │    \                                         │
│            Feature-rich ◄────┼────► Reliable                                │
│                          \   │   /                                          │
│                           \  │  /                                           │
│                            \ │ /                                            │
│                             \│/                                             │
│                              ▼                                              │
│                        Small Size                                           │
│                                                                             │
│  You can optimize for 2 of these, but not all 4:                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Goal              │ Trade-off                                       │   │
│  ├───────────────────┼─────────────────────────────────────────────────┤   │
│  │ Fast + Small      │ Fewer features, less redundancy                 │   │
│  │ Fast + Reliable   │ Larger size (redundant images)                  │   │
│  │ Feature + Reliable│ Slower boot (more checks)                       │   │
│  │ Small + Reliable  │ Fewer features, possibly slower                 │   │
│  └───────────────────┴─────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Real-World Examples

| Product Type | Priority | Approach |
|--------------|----------|----------|
| Automotive ECU | Reliability > Time | A/B, watchdog, verified boot |
| Set-top box | Time > Features | Falcon mode, minimal boot |
| Industrial HMI | Reliability > Size | Full redundancy, robust FS |
| IoT Sensor | Size > Features | Minimal bootloader, no U-Boot |
| Development Board | Features > Time | Full U-Boot, network boot |

---

## Common Mistakes and Debugging Tips

### Mistake 1: SPL Too Large

```bash
# Error during build:
Error: SPL image is too large (120KB > 109KB available)

# Solution: Disable unnecessary SPL features
# In menuconfig, under SPL configuration:
# - Disable USB support in SPL
# - Disable network support in SPL
# - Use minimal malloc implementation
CONFIG_SPL_USB=n
CONFIG_SPL_NET=n
CONFIG_SPL_SYS_MALLOC_SIMPLE=y
```

### Mistake 2: Environment Corruption

```bash
# Symptom: U-Boot uses default environment after power loss

# Cause: Environment stored in wear-prone location

# Solution: Enable redundant environment
CONFIG_SYS_REDUNDAND_ENVIRONMENT=y
CONFIG_ENV_OFFSET=0x100000
CONFIG_ENV_OFFSET_REDUND=0x140000

# U-Boot will alternate between two copies
```

### Mistake 3: No Fallback Boot

```bash
# Symptom: Board won't boot after failed update

# Solution: Implement boot counting and fallback
setenv bootcmd 'setexpr boot_count ${boot_count} + 1; saveenv; \
    if test ${boot_count} -gt 3; then run fallback_boot; fi; \
    run primary_boot'

setenv fallback_boot 'setenv boot_count 0; saveenv; \
    load mmc 0:2 ${loadaddr} /backup/zImage; bootz ...'
```

---

## What You Learned

After reading this document, you understand:

1. ✅ Why memory constraints require multi-stage boot
2. ✅ How SRAM limitations affect SPL design
3. ✅ Storage layout options and their trade-offs
4. ✅ How to store U-Boot environment reliably
5. ✅ Boot time breakdown and optimization strategies
6. ✅ Reliability mechanisms (redundancy, A/B, watchdog)
7. ✅ Trade-offs between speed, size, features, and reliability
8. ✅ How to design robust boot sequences

---

## Next Steps

1. Read [U-Boot Overview](uboot_overview.md) for detailed U-Boot internals
2. Complete [Lab 02: U-Boot](../02_uboot/README.md) including environment persistence
3. Study [Recovery Guide](recovery_guide.md) for failure handling
