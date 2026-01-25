# Bootloader Stages Explained

A detailed exploration of the multi-stage boot process in Embedded Linux systems, from power-on to kernel execution.

## Why Understanding Bootloader Stages Matters

In embedded systems, the boot process is not a single step but a carefully orchestrated sequence of stages. Understanding these stages is critical for:

- **Debugging boot failures**: Knowing which stage failed helps focus investigation
- **Optimizing boot time**: Each stage can be optimized independently
- **Implementing secure boot**: Security verification happens at each stage
- **Customizing boot behavior**: Different stages offer different customization options
- **Recovery implementation**: Fallback mechanisms operate at specific stages

## Overview: The Multi-Stage Boot Process

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    WHY MULTIPLE BOOT STAGES?                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Problem: When power is applied, the CPU can only access:                   │
│           - Internal ROM (small, read-only)                                 │
│           - Internal SRAM (small, ~64-256KB)                                │
│                                                                             │
│           External DRAM is NOT available until it's initialized!            │
│                                                                             │
│  Solution: Multi-stage boot                                                 │
│                                                                             │
│  Stage 0 (ROM)   → Minimal code, loads Stage 1                              │
│  Stage 1 (SPL)   → Initializes DRAM, loads Stage 2                          │
│  Stage 2 (U-Boot)→ Full bootloader, loads kernel                            │
│  Stage 3 (Kernel)→ Operating system, runs user applications                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Stage 0: ROM Code (Boot ROM / BROM)

### What It Is

The ROM code is vendor-programmed, read-only firmware burned into the SoC during manufacturing. It's the very first code that executes when power is applied.

### Key Characteristics

| Property | Details |
|----------|---------|
| Location | Internal SoC ROM (on-die) |
| Size | 32-128 KB typical |
| Modifiable | No - burned at factory |
| Execution | Directly from reset vector |

### Primary Responsibilities

```
┌─────────────────────────────────────────────────────────────┐
│                    ROM CODE TASKS                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Initialize minimum clocks                               │
│     └── Enable oscillator, basic PLL                        │
│                                                             │
│  2. Read boot pins / fuses                                  │
│     └── Determine boot source order                         │
│                                                             │
│  3. Initialize boot interface                               │
│     └── MMC, SPI, NAND, UART, or USB                        │
│                                                             │
│  4. Load first-stage bootloader                             │
│     └── Read SPL from boot media to internal SRAM           │
│                                                             │
│  5. Verify image (optional, secure boot)                    │
│     └── Check signature if secure boot is enabled           │
│                                                             │
│  6. Jump to first-stage bootloader                          │
│     └── Transfer execution to SPL in SRAM                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Boot Source Detection

Different SoCs use different mechanisms to determine boot order:

**Texas Instruments AM335x (BeagleBone):**
```
SYSBOOT[4:0] pins determine boot order:

  Pins       Primary    Secondary   Tertiary
  ────────   ─────────  ─────────   ─────────
  11100      MMC1       MMC0        UART0
  11000      SPI0       MMC0        USB0
  10000      NAND       MMC0        UART0
```

**NXP i.MX6:**
```
Boot mode selected by:
1. BOOT_MODE[1:0] pins
2. eFuses (one-time programmable)
3. GPIO overrides

Boot sources: SD, eMMC, NAND, SPI-NOR, Serial Download
```

**Raspberry Pi (BCM2837):**
```
Fixed boot order:
1. SD card
2. USB (on Pi 3 with updated firmware)
3. Network (PXE, on Pi 3)

Note: RPi boot is unique - GPU boots first, not CPU!
```

### ROM Code Limitations

```
LIMITATIONS:
┌─────────────────────────────────────────────────────────────┐
│ ✗ Cannot be updated or patched                             │
│ ✗ Very limited error handling                               │
│ ✗ No user interface                                         │
│ ✗ Limited boot media support (only what's built-in)        │
│ ✗ Cannot access external DRAM                               │
│ ✗ Platform-specific (not portable)                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Stage 1: SPL (Secondary Program Loader)

### What It Is

The SPL is a minimal bootloader whose primary purpose is to initialize DRAM and load the full bootloader. It runs from internal SRAM, which is limited in size.

### Terminology

| Term | Platform | Notes |
|------|----------|-------|
| SPL | U-Boot generic | Secondary Program Loader |
| MLO | TI (BeagleBone) | MMC Loader |
| TPL | U-Boot | Tertiary Program Loader (even more minimal) |
| FSBL | Xilinx | First Stage Boot Loader |
| BL2 | ARM TF-A | Boot Loader Stage 2 |

### Size Constraints

```
┌─────────────────────────────────────────────────────────────┐
│                SPL SIZE CONSTRAINTS                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Internal SRAM layout (example: AM335x with 128KB SRAM)     │
│                                                             │
│  0x402F0000 ┌───────────────────────┐                       │
│             │   Stack (grows down)  │ ~4KB                  │
│  0x402F4000 ├───────────────────────┤                       │
│             │                       │                       │
│             │   SPL Code + Data     │ ~109KB max            │
│             │                       │                       │
│  0x40309000 ├───────────────────────┤                       │
│             │   Heap                │ ~4KB                  │
│  0x4030A000 ├───────────────────────┤                       │
│             │   ROM vectors/data    │ ~8KB (reserved)       │
│  0x4030C000 └───────────────────────┘                       │
│                                                             │
│  Practical SPL size: 64-100KB depending on features        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### SPL Tasks in Detail

```c
// Simplified SPL boot flow (conceptual C pseudocode)

void spl_main(void)
{
    // 1. Early hardware init
    cpu_init_early();           // Disable watchdog, setup exceptions
    
    // 2. Initialize clocks
    clock_init();               // PLL, system clocks
    
    // 3. Initialize console (optional but helpful)
    uart_init();
    puts("SPL: Starting...\n");
    
    // 4. Initialize DRAM (THE CRITICAL STEP)
    dram_init();               // DDR timing, calibration
    puts("SPL: DRAM initialized\n");
    
    // 5. Initialize boot device
    mmc_init();                // Or SPI, NAND, etc.
    
    // 6. Load U-Boot to DRAM
    load_image("u-boot.img", UBOOT_LOAD_ADDR);
    
    // 7. Jump to U-Boot
    jump_to_image(UBOOT_LOAD_ADDR);
}
```

### DRAM Initialization Deep Dive

The most critical and complex SPL task is DRAM initialization:

```
┌─────────────────────────────────────────────────────────────┐
│                 DRAM INITIALIZATION                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Configure memory controller registers                   │
│     - Set timing parameters (tRCD, tRP, tRAS, tRC, etc.)   │
│     - Configure address mapping (rows, columns, banks)      │
│     - Set data width (16/32-bit)                            │
│                                                             │
│  2. Initialize PHY (Physical Interface)                     │
│     - Set IO drive strength                                 │
│     - Configure DLL (Delay-Locked Loop)                     │
│                                                             │
│  3. Execute DRAM training (DDR3/DDR4)                       │
│     - Write leveling                                        │
│     - Read DQS training                                     │
│     - Write DQS training                                    │
│                                                             │
│  4. Verify DRAM functionality                               │
│     - Write test patterns                                   │
│     - Read back and verify                                  │
│                                                             │
│  If any step fails → system will not boot!                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### SPL Configuration in U-Boot

```bash
# Key SPL configuration options (Kconfig)

CONFIG_SPL=y                      # Enable SPL build
CONFIG_SPL_TEXT_BASE=0x402F4000   # Load address in SRAM
CONFIG_SPL_MAX_SIZE=0x1B400       # Max size (109KB)
CONFIG_SPL_BSS_MAX_SIZE=0x1000    # BSS size limit

# SPL drivers (keep minimal!)
CONFIG_SPL_MMC=y                  # MMC support in SPL
CONFIG_SPL_SERIAL=y               # Serial output in SPL
# CONFIG_SPL_NET=y                # Usually too big for SPL
# CONFIG_SPL_USB=y                # Usually too big for SPL

# DRAM configuration
CONFIG_SPL_RAM_DEVICE=y           # RAM initialization
CONFIG_SYS_SDRAM_BASE=0x80000000  # DRAM base address
```

---

## Stage 2: U-Boot (Full Bootloader)

### What It Is

U-Boot is a full-featured, open-source bootloader that runs from DRAM. It provides all the functionality needed to load and boot the operating system.

### Key Capabilities

```
┌─────────────────────────────────────────────────────────────┐
│                  U-BOOT CAPABILITIES                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │ Hardware Init   │  │ User Interface  │                   │
│  ├─────────────────┤  ├─────────────────┤                   │
│  │ • Full clock    │  │ • Command shell │                   │
│  │ • All peripherals│  │ • Environment   │                   │
│  │ • Network       │  │ • Scripting     │                   │
│  │ • USB           │  │ • Menus         │                   │
│  │ • Display       │  │ • Variables     │                   │
│  └─────────────────┘  └─────────────────┘                   │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │ Storage Access  │  │ Network Boot    │                   │
│  ├─────────────────┤  ├─────────────────┤                   │
│  │ • MMC/SD/eMMC   │  │ • TFTP          │                   │
│  │ • NAND flash    │  │ • DHCP          │                   │
│  │ • SPI flash     │  │ • NFS           │                   │
│  │ • USB storage   │  │ • HTTP (new)    │                   │
│  │ • SATA          │  │ • PXE boot      │                   │
│  └─────────────────┘  └─────────────────┘                   │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │ Filesystem      │  │ Image Handling  │                   │
│  ├─────────────────┤  ├─────────────────┤                   │
│  │ • FAT           │  │ • Load kernel   │                   │
│  │ • ext2/3/4      │  │ • Load DTB      │                   │
│  │ • UBIFS         │  │ • Load initramfs│                   │
│  │ • SquashFS      │  │ • Verify images │                   │
│  └─────────────────┘  └─────────────────┘                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### U-Boot Boot Sequence

```
┌─────────────────────────────────────────────────────────────┐
│                 U-BOOT EXECUTION FLOW                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  board_init_f()                                             │
│  ├── 1. cpu_init_f()          // CPU early init             │
│  ├── 2. board_early_init_f()  // Board early init           │
│  ├── 3. env_init()            // Environment init           │
│  ├── 4. init_baud_rate()      // Serial baud rate           │
│  ├── 5. serial_init()         // Initialize UART            │
│  ├── 6. console_init_f()      // Console init               │
│  └── 7. dram_init()           // DRAM size detection        │
│                                                             │
│  relocate_code()              // Copy U-Boot to high memory │
│                                                             │
│  board_init_r()                                             │
│  ├── 1. board_init()          // Board-specific init        │
│  ├── 2. mmc_initialize()      // MMC/SD init                │
│  ├── 3. env_relocate()        // Load environment           │
│  ├── 4. stdio_init()          // Standard I/O init          │
│  ├── 5. eth_initialize()      // Network init               │
│  └── 6. main_loop()           // Command loop / autoboot    │
│                                                             │
│  main_loop()                                                │
│  ├── bootdelay countdown      // Wait for interrupt         │
│  ├── if not interrupted:                                    │
│  │   └── run_command(bootcmd) // Execute boot command       │
│  └── else:                                                  │
│      └── command_loop()       // Interactive shell          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Key U-Boot Commands

```bash
# Environment commands
printenv                    # Show all environment variables
setenv bootargs "..."       # Set boot arguments
saveenv                     # Save environment to storage
editenv bootargs            # Interactive edit

# Memory commands
md 0x80000000 100           # Memory display
mw 0x80000000 0xDEADBEEF    # Memory write
cp 0x80000000 0x81000000 0x1000  # Memory copy

# Storage commands
mmc list                    # List MMC devices
mmc dev 0                   # Select MMC device 0
mmc part                    # Show partitions
mmc read 0x80800000 0 0x4000  # Read raw sectors

# Filesystem commands
fatls mmc 0:1               # List files on FAT partition
ext4ls mmc 0:2              # List files on ext4 partition
load mmc 0:1 0x80800000 zImage  # Load file to memory

# Network commands
dhcp                        # Get IP via DHCP
tftp 0x80800000 zImage      # Download file via TFTP
ping 192.168.1.1            # Test connectivity

# Boot commands
bootz 0x80800000 - 0x82000000  # Boot zImage with DTB
booti 0x80800000 - 0x82000000  # Boot Image (ARM64)
bootm 0x80800000               # Boot uImage (legacy)
boot                        # Execute bootcmd
```

---

## Stage 3: Linux Kernel

### Kernel Entry Point

When U-Boot transfers control to the kernel, specific conditions must be met:

```
┌─────────────────────────────────────────────────────────────┐
│              ARM KERNEL ENTRY REQUIREMENTS                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CPU State:                                                 │
│  • CPU in SVC (supervisor) mode                             │
│  • Interrupts disabled (IRQ and FIQ)                        │
│  • MMU disabled                                             │
│  • Data cache disabled                                      │
│                                                             │
│  Register State (ARM32):                                    │
│  ┌─────────┬────────────────────────────────────┐           │
│  │ R0      │ 0                                  │           │
│  │ R1      │ Machine type number (or 0xFFFFFFFF)│           │
│  │ R2      │ Physical address of DTB            │           │
│  │ PC      │ Kernel entry point                 │           │
│  └─────────┴────────────────────────────────────┘           │
│                                                             │
│  Register State (ARM64):                                    │
│  ┌─────────┬────────────────────────────────────┐           │
│  │ X0      │ Physical address of DTB            │           │
│  │ X1-X3   │ Reserved (0)                       │           │
│  │ PC      │ Kernel entry point                 │           │
│  └─────────┴────────────────────────────────────┘           │
│                                                             │
│  Memory Requirements:                                       │
│  • Kernel loaded at correct address (TEXT_OFFSET)           │
│  • DTB loaded at 2MB-aligned address                        │
│  • 128MB gap between kernel and DTB (recommended)           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Kernel Boot Process

```
┌─────────────────────────────────────────────────────────────┐
│                KERNEL BOOT SEQUENCE                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. HEAD (arch/arm/kernel/head.S)                           │
│     ├── Verify CPU mode and state                           │
│     ├── Enable MMU                                          │
│     ├── Setup initial page tables                           │
│     └── Jump to start_kernel()                              │
│                                                             │
│  2. start_kernel() (init/main.c)                            │
│     ├── setup_arch()          // Architecture setup         │
│     ├── mm_init()             // Memory management          │
│     ├── sched_init()          // Scheduler                  │
│     ├── early_irq_init()      // Interrupt system           │
│     ├── init_timers()         // Timer subsystem            │
│     ├── console_init()        // Console initialization     │
│     ├── ...                                                 │
│     └── rest_init()                                         │
│                                                             │
│  3. rest_init()                                             │
│     ├── kernel_thread(kernel_init)  // Create init thread   │
│     ├── kernel_thread(kthreadd)     // Kernel thread daemon │
│     └── cpu_idle()                  // Become idle thread   │
│                                                             │
│  4. kernel_init()                                           │
│     ├── kernel_init_freeable()                              │
│     │   ├── do_basic_setup()  // Driver initialization      │
│     │   ├── prepare_namespace()  // Mount root filesystem   │
│     │   └── ...                                             │
│     └── run_init_process()    // Execute /sbin/init         │
│                                                             │
│  5. /sbin/init (PID 1)                                      │
│     └── Start user space (systemd, services, etc.)          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Stage Comparison Summary

```
┌───────────┬──────────────┬──────────────┬──────────────┬──────────────┐
│ Property  │   ROM Code   │     SPL      │   U-Boot     │    Kernel    │
├───────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Location  │ On-chip ROM  │ Internal     │ External     │ External     │
│           │              │ SRAM         │ DRAM         │ DRAM         │
├───────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Typical   │ 32-128 KB    │ 64-128 KB    │ 512KB-1MB    │ 5-20 MB      │
│ Size      │              │              │              │              │
├───────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ DRAM      │ No           │ Initializes  │ Full access  │ Full access  │
│ Access    │              │ DRAM         │              │              │
├───────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ User      │ None         │ Minimal      │ Full shell   │ Full OS      │
│ Interface │              │ (UART only)  │ + network    │              │
├───────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Modifiable│ No           │ Yes (build)  │ Yes (build)  │ Yes (build)  │
├───────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Boot Time │ 10-50 ms     │ 50-200 ms    │ 1-3 sec      │ 1-10 sec     │
└───────────┴──────────────┴──────────────┴──────────────┴──────────────┘
```

---

## Common Mistakes and Debugging

### SPL Debugging

```bash
# If SPL fails to load, common causes:
# 1. Wrong file name (must be "MLO" on TI platforms)
# 2. Wrong location on boot media
# 3. DRAM timing parameters incorrect
# 4. SPL too large for SRAM

# Enable SPL debug output:
# In U-Boot config:
CONFIG_SPL_SERIAL=y
CONFIG_SPL_LIBCOMMON_SUPPORT=y
CONFIG_SPL_SYS_MALLOC_SIMPLE=y
```

### U-Boot Debugging

```bash
# If U-Boot hangs, check:
# 1. SPL loaded U-Boot to correct address
# 2. DRAM is fully functional
# 3. Environment is valid

# Debug commands:
version                     # Verify U-Boot version
bdinfo                      # Board info (DRAM, etc.)
coninfo                     # Console info
```

### Kernel Debugging

```bash
# If kernel panics, useful bootargs:
setenv bootargs console=ttyS0,115200 earlyprintk loglevel=8 debug
# earlyprintk: Show messages before console is fully up
# loglevel=8: Maximum verbosity
# debug: Enable debug messages
```

---

## What You Learned

After reading this document, you understand:

1. ✅ Why embedded systems need multiple boot stages
2. ✅ What ROM code does and its limitations
3. ✅ Why SPL is necessary and what it initializes
4. ✅ The critical role of DRAM initialization
5. ✅ U-Boot capabilities and boot sequence
6. ✅ How control passes from U-Boot to kernel
7. ✅ Kernel entry requirements and boot sequence
8. ✅ How to debug boot stage failures

---

## Next Steps

1. Read [Bootloader Design Constraints](bootloader_design_constraints.md)
2. Read [U-Boot Overview](uboot_overview.md)
3. Complete [Lab 01: Boot Flow](../01_boot_flow/README.md)
4. Complete [Lab 02: U-Boot](../02_uboot/README.md)
