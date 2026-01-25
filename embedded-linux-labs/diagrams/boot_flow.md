# Embedded Linux Boot Flow Diagram

This document provides visual representations of the complete Embedded Linux boot sequence from power-on to user space.

## Why Understanding Boot Flow Matters

In embedded systems, understanding the boot flow is critical because:

1. **Debugging**: When a system fails to boot, you need to identify which stage failed
2. **Optimization**: Boot time requirements often require optimizing specific stages
3. **Security**: Secure boot chains require understanding each verification step
4. **Customization**: Adding features often requires modifications at specific boot stages
5. **Recovery**: Implementing recovery mechanisms requires knowledge of fallback points

## Complete Boot Flow Overview

```mermaid
flowchart TD
    subgraph HARDWARE["Hardware Initialization"]
        POWER[/"Power Applied"/]
        RESET["CPU Reset Vector"]
        ROM["ROM Code / BROM"]
    end

    subgraph BOOTLOADER["Bootloader Stages"]
        SPL["SPL / MLO / TPL<br/>(Minimal Loader)"]
        UBOOT["U-Boot<br/>(Full Bootloader)"]
        ENV["Environment Variables<br/>bootcmd, bootargs"]
    end

    subgraph KERNEL_SPACE["Kernel Space"]
        KERNEL["Linux Kernel"]
        DTB["Device Tree Blob<br/>(Hardware Description)"]
        INITRAMFS["initramfs<br/>(Optional Early Rootfs)"]
    end

    subgraph USER_SPACE["User Space"]
        INIT["init / systemd<br/>(PID 1)"]
        ROOTFS["Root Filesystem<br/>(SD/eMMC/NFS)"]
        SERVICES["System Services"]
        APP["User Application"]
    end

    POWER --> RESET
    RESET --> ROM
    ROM -->|"Load from boot media"| SPL
    SPL -->|"Initialize DRAM, load"| UBOOT
    UBOOT -->|"Read"| ENV
    ENV -->|"Execute bootcmd"| KERNEL
    UBOOT -->|"Load & pass"| DTB
    DTB --> KERNEL
    UBOOT -.->|"Optional"| INITRAMFS
    INITRAMFS -.-> KERNEL
    KERNEL -->|"Mount rootfs"| ROOTFS
    KERNEL -->|"Start"| INIT
    INIT --> SERVICES
    SERVICES --> APP

    style POWER fill:#ff6b6b
    style ROM fill:#ffd93d
    style SPL fill:#6bcb77
    style UBOOT fill:#4d96ff
    style KERNEL fill:#845ec2
    style INIT fill:#ff9671
    style APP fill:#00c9a7
```

## Detailed Stage Breakdown

```mermaid
sequenceDiagram
    participant P as Power
    participant ROM as ROM Code
    participant SPL as SPL/MLO
    participant UB as U-Boot
    participant K as Kernel
    participant I as Init

    Note over P,I: Phase 1: Hardware Initialization
    P->>ROM: Power-on Reset
    ROM->>ROM: Execute from internal ROM
    ROM->>ROM: Initialize boot pins
    ROM->>ROM: Detect boot media (SD/eMMC/UART)
    
    Note over P,I: Phase 2: First Stage Bootloader
    ROM->>SPL: Load SPL to internal SRAM
    SPL->>SPL: Initialize clocks
    SPL->>SPL: Initialize DRAM controller
    SPL->>SPL: Initialize boot media interface
    
    Note over P,I: Phase 3: Second Stage Bootloader
    SPL->>UB: Load U-Boot to DRAM
    UB->>UB: Initialize console (UART)
    UB->>UB: Initialize network, storage
    UB->>UB: Read environment (bootargs)
    UB->>UB: Execute bootcmd
    
    Note over P,I: Phase 4: Kernel Boot
    UB->>K: Load kernel + DTB to DRAM
    UB->>K: Jump to kernel entry point
    K->>K: Decompress (if zImage)
    K->>K: Parse device tree
    K->>K: Initialize subsystems
    K->>K: Mount root filesystem
    
    Note over P,I: Phase 5: User Space
    K->>I: Execute /sbin/init
    I->>I: Start system services
    I->>I: Run user applications
```

## Memory Layout During Boot

```mermaid
graph LR
    subgraph MEMORY["System Memory Map"]
        subgraph SRAM["Internal SRAM (~128KB)"]
            ROM_DATA["ROM Data"]
            SPL_CODE["SPL Code + Stack"]
        end
        
        subgraph DRAM["External DRAM (512MB-4GB)"]
            UBOOT_AREA["U-Boot (~1MB)"]
            KERNEL_AREA["Kernel Image (~10MB)"]
            DTB_AREA["Device Tree (~64KB)"]
            INITRAMFS_AREA["initramfs (~5MB)"]
            FREE["Free Memory"]
        end
    end
    
    style SRAM fill:#ffcc80
    style DRAM fill:#81d4fa
```

## Boot Media Detection (Platform Specific)

```mermaid
flowchart LR
    subgraph RPi["Raspberry Pi"]
        GPU["GPU Bootrom"]
        GPU --> BC["bootcode.bin"]
        BC --> START["start.elf"]
        START --> UB_RPI["U-Boot or kernel"]
    end
    
    subgraph AM335x["BeagleBone (AM335x)"]
        ROM_BB["ROM Code"]
        ROM_BB -->|"SYSBOOT pins"| DETECT["Detect Boot Source"]
        DETECT --> MMC["MMC0/1"]
        DETECT --> UART["UART"]
        DETECT --> USB["USB"]
        MMC --> MLO["MLO (SPL)"]
    end
    
    subgraph iMX["i.MX"]
        ROM_IMX["Boot ROM"]
        ROM_IMX -->|"Fuses + GPIO"| DETECT_IMX["Detect Boot Source"]
        DETECT_IMX --> SD["SD Card"]
        DETECT_IMX --> EMMC["eMMC"]
        DETECT_IMX --> NAND["NAND"]
        SD --> SPL_IMX["SPL"]
    end
```

## Boot Arguments Flow

```mermaid
flowchart LR
    subgraph UBOOT_ENV["U-Boot Environment"]
        BOOTARGS["bootargs variable"]
        BOOTCMD["bootcmd variable"]
    end
    
    subgraph KERNEL_CMDLINE["Kernel Command Line"]
        ROOT["root=/dev/mmcblk0p2"]
        ROOTFSTYPE["rootfstype=ext4"]
        CONSOLE["console=ttyS0,115200"]
        INIT["init=/sbin/init"]
        EXTRA["rw quiet"]
    end
    
    subgraph KERNEL_USE["Kernel Usage"]
        MOUNT["Mount rootfs"]
        SERIAL["Serial console"]
        STARTUP["Init process"]
    end
    
    BOOTARGS --> ROOT
    BOOTARGS --> ROOTFSTYPE
    BOOTARGS --> CONSOLE
    BOOTARGS --> INIT
    BOOTARGS --> EXTRA
    
    ROOT --> MOUNT
    CONSOLE --> SERIAL
    INIT --> STARTUP
```

## Typical Boot Times

| Stage | Typical Duration | Can Be Optimized |
|-------|-----------------|------------------|
| ROM Code | 10-50 ms | No (fixed) |
| SPL | 50-200 ms | Limited |
| U-Boot | 1-3 seconds | Yes |
| Kernel | 1-5 seconds | Yes |
| Init/Systemd | 2-10 seconds | Yes |
| **Total** | **4-20 seconds** | **Yes** |

## What You Learned

After studying this diagram:
- You understand the complete boot sequence from power-on to user application
- You can identify which component is responsible for each boot stage
- You understand the memory transitions (ROM → SRAM → DRAM)
- You can trace how bootargs flow from U-Boot to kernel
- You understand platform-specific boot variations
