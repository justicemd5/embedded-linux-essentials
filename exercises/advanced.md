# Advanced Exercises

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

Challenging exercises for experienced embedded Linux developers targeting **BeagleBone Black Rev C**.

## Prerequisites

- Completed [Intermediate Exercises](intermediate.md)
- Strong C programming skills
- Understanding of kernel internals
- Experience with debugging tools
- BeagleBone Black Rev C with all required accessories

---

## Exercise Directory

The advanced exercises have been split into dedicated files for better organization and depth of coverage. Each exercise is now a comprehensive standalone guide.

### Core Exercises (from original labs)

| # | Exercise | Description | Link |
|---|----------|-------------|------|
| 1 | Kernel Module Development | Write loadable kernel modules with /proc interface | [01_kernel_module.md](advanced/01_kernel_module.md) |
| 2 | Debug Kernel Panic | Analyze and fix kernel crashes using ARM debugging | [02_debug_kernel_panic.md](advanced/02_debug_kernel_panic.md) |
| 3 | Boot Time Optimization | Reduce boot time from power-on to application | [03_boot_optimization.md](advanced/03_boot_optimization.md) |
| 4 | A/B Partition Scheme | Implement robust A/B update system with fallback | [04_ab_partition.md](advanced/04_ab_partition.md) |
| 5 | PREEMPT_RT Kernel | Apply real-time patch and measure latency | [05_preempt_rt.md](advanced/05_preempt_rt.md) |
| 6 | Secure Boot | Implement verified boot chain with signatures | [06_secure_boot.md](advanced/06_secure_boot.md) |

### New: Build System Exercises

| # | Exercise | Description | Link |
|---|----------|-------------|------|
| 7 | **Buildroot System** | Build complete embedded Linux from source | [07_buildroot.md](advanced/07_buildroot.md) |
| 8 | **Yocto Project** | Create custom distribution with OpenEmbedded | [08_yocto.md](advanced/08_yocto.md) |

### New: System Internals

| # | Exercise | Description | Link |
|---|----------|-------------|------|
| 9 | **Custom Init System** | Build minimal init without systemd/BusyBox | [09_custom_init.md](advanced/09_custom_init.md) |
| 10 | **Network Boot** | Set up complete TFTP/NFS boot infrastructure | [10_network_boot.md](advanced/10_network_boot.md) |

---

## Suggested Learning Path

```
┌─────────────────────────────────────────────────────────────┐
│                    ADVANCED TRACK                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [1] Kernel Module ──► [2] Debug Panic ──► [5] PREEMPT_RT  │
│         │                                                   │
│         ▼                                                   │
│  [7] Buildroot ──► [8] Yocto ──► [9] Custom Init           │
│         │                                                   │
│         ▼                                                   │
│  [3] Boot Optimization ──► [4] A/B Partition               │
│                                   │                         │
│                                   ▼                         │
│                            [6] Secure Boot                  │
│                                                             │
│  [10] Network Boot (can be done anytime after Buildroot)   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### If you want to build a complete system from scratch:
→ Start with [Exercise 7: Buildroot](advanced/07_buildroot.md)

### If you want to understand kernel development:
→ Start with [Exercise 1: Kernel Module](advanced/01_kernel_module.md)

### If you want to optimize an existing system:
→ Start with [Exercise 3: Boot Optimization](advanced/03_boot_optimization.md)

### If you want production-grade updates:
→ Start with [Exercise 4: A/B Partition](advanced/04_ab_partition.md)

---

## Certification Project

After completing these exercises, attempt the capstone project that combines all skills:

**[Certification Project](advanced/certification_project.md)**

Create a complete production-ready embedded Linux system that:
- Boots in under 10 seconds
- Has A/B update capability
- Uses custom kernel module
- Implements secure boot (optional)
- Recovers from failed updates automatically

---

## Resources

- [Linux Kernel Documentation](https://www.kernel.org/doc/)
- [U-Boot Documentation](https://u-boot.readthedocs.io/)
- [Buildroot Manual](https://buildroot.org/downloads/manual/manual.html)
- [Yocto Project Documentation](https://docs.yoctoproject.org/)
- [BeagleBone Documentation](https://beagleboard.org/getting-started)
- [Embedded Linux Wiki](https://elinux.org/)
- [Real-Time Linux Wiki](https://wiki.linuxfoundation.org/realtime/start)
