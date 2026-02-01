# Exercise 1: Kernel Module Development

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Develop loadable kernel modules that interact with hardware and provide userspace interfaces. This exercise covers multiple module types from simple procfs to complex character devices and GPIO interrupt handlers.

## Prerequisites

- Completed kernel build from Lab 03
- Cross-compilation toolchain installed (`arm-linux-gnueabihf-gcc`)
- BeagleBone Black with working kernel
- Serial console access via USB (`/dev/ttyACM0`)

## Difficulty: ⭐⭐⭐ Advanced

---

## 📁 Directory Structure

```
01_kernel_module/
├── modules/
│   ├── hwinfo/           # Basic procfs module
│   │   ├── hwinfo.c
│   │   └── Makefile
│   ├── sysfs_demo/       # Sysfs interface module
│   │   ├── sysfs_demo.c
│   │   └── Makefile
│   ├── chardev/          # Character device driver
│   │   ├── chardev.c
│   │   ├── chardev.h
│   │   ├── test_chardev.c
│   │   └── Makefile
│   └── gpio_irq/         # GPIO interrupt handler
│       ├── gpio_irq.c
│       └── Makefile
└── scripts/
    ├── build_all_modules.sh
    ├── deploy_modules.sh
    └── test_modules.sh
```

---

## Part 1: Kernel Module Theory

### What is a Kernel Module?

Kernel modules are pieces of code that can be loaded and unloaded into the kernel dynamically. They extend the kernel's functionality without requiring a reboot.

```
┌─────────────────────────────────────────────────────────────┐
│                 KERNEL MODULE ARCHITECTURE                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   USER SPACE                         │   │
│  │                                                      │   │
│  │  Applications ←──→ /proc ←──→ /sys ←──→ /dev        │   │
│  │       ↓              ↓          ↓          ↓         │   │
│  └──────────────────────────────────────────────────────┘   │
│                         │ System Calls                      │
│  ════════════════════════════════════════════════════════   │
│                         ▼ Kernel Boundary                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  KERNEL SPACE                        │   │
│  │                                                      │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │ procfs  │  │  sysfs  │  │  devfs  │             │   │
│  │  │ handler │  │ handler │  │ handler │             │   │
│  │  └────┬────┘  └────┬────┘  └────┬────┘             │   │
│  │       │            │            │                   │   │
│  │       └────────────┼────────────┘                   │   │
│  │                    ▼                                │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │           YOUR KERNEL MODULE                  │   │   │
│  │  │  ┌────────────────────────────────────────┐  │   │   │
│  │  │  │  init() → register interfaces          │  │   │   │
│  │  │  │  exit() → cleanup & unregister         │  │   │   │
│  │  │  │  file_operations → read/write/ioctl    │  │   │   │
│  │  │  └────────────────────────────────────────┘  │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  │                    ↓                                │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │              HARDWARE                         │   │   │
│  │  │  GPIO │ I2C │ SPI │ UART │ Memory-Mapped I/O │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Module Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│                 MODULE LIFECYCLE                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. COMPILE (on host)                                       │
│     make → produces .ko file                                │
│                                                             │
│  2. TRANSFER                                                │
│     scp module.ko target:/path/                             │
│                                                             │
│  3. LOAD                                                    │
│     insmod module.ko [params]  → calls module_init()        │
│     modprobe module            → handles dependencies       │
│                                                             │
│  4. ACTIVE                                                  │
│     Module is now part of kernel                            │
│     File operations handle user requests                    │
│     IRQ handlers respond to hardware                        │
│                                                             │
│  5. UNLOAD                                                  │
│     rmmod module               → calls module_exit()        │
│     Resources freed, interfaces removed                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Userspace Interfaces

| Interface | Location | Purpose | Best For |
|-----------|----------|---------|----------|
| procfs | `/proc/` | Process/system info | Read-only status, simple data |
| sysfs | `/sys/` | Device attributes | Per-attribute files, kobjects |
| chardev | `/dev/` | Byte stream device | Complex data, ioctl commands |
| netlink | Sockets | Kernel-user messaging | Async events, large data |
| debugfs | `/sys/kernel/debug/` | Debug information | Development, tracing |

---

## Part 2: Module Development

### Module 1: Hardware Info (procfs)

The simplest module demonstrating procfs interface.

📁 **Source:** [modules/hwinfo/hwinfo.c](01_kernel_module/modules/hwinfo/hwinfo.c)
📁 **Makefile:** [modules/hwinfo/Makefile](01_kernel_module/modules/hwinfo/Makefile)

**Key Concepts:**
- `proc_create()` - Create procfs entry
- `seq_file` interface - Handle buffered reads
- `struct proc_ops` - File operations for proc

**Build and Test:**

```bash
cd 01_kernel_module/modules/hwinfo
make KERNEL_DIR=~/bbb/linux

# Deploy
scp hwinfo.ko debian@192.168.7.2:/tmp/

# On BBB
sudo insmod /tmp/hwinfo.ko
cat /proc/hwinfo
sudo rmmod hwinfo
```

**Expected Output:**

```
╔═══════════════════════════════════════════════════════╗
║     BeagleBone Black Hardware Information Module      ║
╠═══════════════════════════════════════════════════════╣
║ Platform: TI AM335x (Cortex-A8 @ 1GHz)                ║
╠═══════════════════════════════════════════════════════╣
║ KERNEL INFORMATION                                    ║
║   Version: 6.6.0                                      ║
...
```

---

### Module 2: Sysfs Demo

Demonstrates sysfs attribute creation with read/write support.

📁 **Source:** [modules/sysfs_demo/sysfs_demo.c](01_kernel_module/modules/sysfs_demo/sysfs_demo.c)
📁 **Makefile:** [modules/sysfs_demo/Makefile](01_kernel_module/modules/sysfs_demo/Makefile)

**Key Concepts:**
- `kobject_create_and_add()` - Create sysfs directory
- `struct kobj_attribute` - Define attributes
- `__ATTR()` / `__ATTR_RO()` - Attribute macros

**Sysfs Attributes Created:**

| Attribute | Mode | Description |
|-----------|------|-------------|
| `ram_mb` | RO | Total RAM in MB |
| `brightness` | RW | Simulated LED brightness (0-100) |
| `device_name` | RW | Configurable device name |
| `stats` | RO | Read/write statistics |
| `logging` | RW | Enable/disable logging |

**Build and Test:**

```bash
cd 01_kernel_module/modules/sysfs_demo
make KERNEL_DIR=~/bbb/linux

# On BBB
sudo insmod /tmp/sysfs_demo.ko

# Read attributes
cat /sys/kernel/bbb_demo/ram_mb
cat /sys/kernel/bbb_demo/brightness

# Write attribute
echo 75 | sudo tee /sys/kernel/bbb_demo/brightness
cat /sys/kernel/bbb_demo/stats

sudo rmmod sysfs_demo
```

---

### Module 3: Character Device

Full-featured character device with read/write/ioctl.

📁 **Source:** [modules/chardev/chardev.c](01_kernel_module/modules/chardev/chardev.c)
📁 **Header:** [modules/chardev/chardev.h](01_kernel_module/modules/chardev/chardev.h)
📁 **Test Program:** [modules/chardev/test_chardev.c](01_kernel_module/modules/chardev/test_chardev.c)
📁 **Makefile:** [modules/chardev/Makefile](01_kernel_module/modules/chardev/Makefile)

**Key Concepts:**
- `alloc_chrdev_region()` - Dynamic major number
- `cdev_add()` - Register character device
- `class_create()` / `device_create()` - Auto-create /dev node
- `copy_to_user()` / `copy_from_user()` - Safe data transfer
- `unlocked_ioctl` - Custom commands

**IOCTL Commands:**

| Command | Type | Description |
|---------|------|-------------|
| `CHARDEV_IOCRESET` | `_IO` | Reset buffer to zeros |
| `CHARDEV_IOCGETSIZE` | `_IOR` | Get buffer size |
| `CHARDEV_IOCGETCOUNT` | `_IOR` | Get data length |

**Build and Test:**

```bash
# Build module
cd 01_kernel_module/modules/chardev
make KERNEL_DIR=~/bbb/linux

# Build test program
arm-linux-gnueabihf-gcc -o test_chardev test_chardev.c

# Deploy
scp chardev.ko test_chardev debian@192.168.7.2:/tmp/

# On BBB
sudo insmod /tmp/chardev.ko
sudo /tmp/test_chardev

# Manual test
echo "Hello World" > /dev/bbbchar
cat /dev/bbbchar

sudo rmmod chardev
```

---

### Module 4: GPIO Interrupt Handler

Demonstrates GPIO input with interrupt handling and debouncing.

📁 **Source:** [modules/gpio_irq/gpio_irq.c](01_kernel_module/modules/gpio_irq/gpio_irq.c)
📁 **Makefile:** [modules/gpio_irq/Makefile](01_kernel_module/modules/gpio_irq/Makefile)

**Key Concepts:**
- `gpiod_direction_input()` - Configure GPIO
- `gpiod_to_irq()` - Get IRQ for GPIO
- `request_irq()` - Register interrupt handler
- Workqueue for bottom-half processing
- Timer-based debouncing

**Hardware Setup:**

```
BeagleBone Black P9 Header:
┌─────┬─────┐
│ GND │ VDD │ P9_1, P9_2
├─────┼─────┤
│     │     │
├─────┼─────┤
│     │     │
├─────┼─────┤
│     │     │
├─────┼─────┤
│ P12 │     │ ← GPIO1_28 (default for this module)
├─────┼─────┤
│     │     │
...

Wire a button:
  P9_1 (GND) ──┤ Button ├── P9_12 (GPIO)
  
With internal pull-up, GPIO reads HIGH when button not pressed.
```

**Build and Test:**

```bash
cd 01_kernel_module/modules/gpio_irq
make KERNEL_DIR=~/bbb/linux

# On BBB - load with default GPIO
sudo insmod /tmp/gpio_irq.ko

# Or specify different GPIO
sudo insmod /tmp/gpio_irq.ko gpio_num=48  # P9_15

# Monitor interrupts
watch -n1 cat /sys/class/gpio_irq/gpio_irq/irq_count

# View kernel messages
dmesg -w

sudo rmmod gpio_irq
```

---

## Part 3: Build and Deploy Scripts

### Build All Modules

📁 **Script:** [scripts/build_all_modules.sh](01_kernel_module/scripts/build_all_modules.sh)

```bash
# Make executable
chmod +x 01_kernel_module/scripts/*.sh

# Build all modules
./01_kernel_module/scripts/build_all_modules.sh ~/bbb/linux
```

### Deploy to BBB

📁 **Script:** [scripts/deploy_modules.sh](01_kernel_module/scripts/deploy_modules.sh)

```bash
# Deploy all modules
./01_kernel_module/scripts/deploy_modules.sh 192.168.7.2

# Deploy specific module
./01_kernel_module/scripts/deploy_modules.sh 192.168.7.2 hwinfo
```

### Run Tests

📁 **Script:** [scripts/test_modules.sh](01_kernel_module/scripts/test_modules.sh)

```bash
# Run all module tests
./01_kernel_module/scripts/test_modules.sh 192.168.7.2
```

---

## Part 4: Advanced Topics

### Memory Management in Kernel

```c
/* Kernel memory allocation functions */

/* For small allocations (< PAGE_SIZE) */
ptr = kmalloc(size, GFP_KERNEL);      /* May fail */
ptr = kzalloc(size, GFP_KERNEL);      /* Zero-initialized */
kfree(ptr);

/* For arrays */
ptr = kcalloc(n, size, GFP_KERNEL);

/* For larger allocations */
ptr = vmalloc(size);                   /* Virtual contiguous */
vfree(ptr);

/* GFP flags */
GFP_KERNEL   /* May sleep, normal allocation */
GFP_ATOMIC   /* Cannot sleep, interrupt context */
GFP_DMA      /* DMA-capable memory */
```

### Concurrency and Locking

```c
/* Mutex - can sleep */
DEFINE_MUTEX(my_mutex);
mutex_lock(&my_mutex);
/* critical section */
mutex_unlock(&my_mutex);

/* Spinlock - cannot sleep, IRQ-safe */
DEFINE_SPINLOCK(my_lock);
spin_lock_irqsave(&my_lock, flags);
/* critical section */
spin_unlock_irqrestore(&my_lock, flags);

/* RCU - read-optimized */
rcu_read_lock();
/* read data */
rcu_read_unlock();
```

### Debug Techniques

```bash
# Dynamic debug - enable at runtime
echo 'module hwinfo +p' > /sys/kernel/debug/dynamic_debug/control

# ftrace - function tracing
echo function > /sys/kernel/debug/tracing/current_tracer
echo hwinfo_show > /sys/kernel/debug/tracing/set_ftrace_filter
cat /sys/kernel/debug/tracing/trace

# Kernel address sanitizer (if enabled)
# Detects memory errors in modules
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Invalid module format" | Kernel version mismatch | Rebuild with correct kernel source |
| "Unknown symbol" | Missing dependency | Check `nm module.ko \| grep " U "` |
| "Permission denied" | Not root | Use `sudo` for insmod/rmmod |
| Module crashes on load | NULL dereference | Add defensive checks, use `pr_debug` |
| "Device or resource busy" | Already loaded | `rmmod` first, or check references |

### Debugging Workflow

```bash
# Check kernel log for errors
dmesg | tail -50

# Verify module info
modinfo module.ko

# Check symbol dependencies
nm module.ko | grep " U "

# List loaded modules
lsmod | grep module_name

# Check reference count
cat /sys/module/module_name/refcnt
```

---

## Verification Checklist

- [ ] All modules compile without warnings
- [ ] hwinfo module creates /proc/hwinfo
- [ ] sysfs_demo creates /sys/kernel/bbb_demo/
- [ ] chardev creates /dev/bbbchar automatically
- [ ] gpio_irq responds to button presses
- [ ] All modules unload cleanly
- [ ] No kernel oops or warnings in dmesg

---

## Challenge Extensions

1. **Add netlink interface** - Implement async notifications to userspace
2. **Create platform driver** - Use device tree binding
3. **Add debugfs entries** - Expose internal state for debugging
4. **Implement mmap** - Allow userspace to map kernel memory
5. **Add power management** - Implement suspend/resume callbacks

---

[← Back to Advanced Exercises](README.md) | [Next: Debug Kernel Panic →](02_debug_kernel_panic.md)
