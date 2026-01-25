# Advanced Exercises

Challenging exercises for experienced embedded Linux developers.

## Prerequisites

- Completed [Intermediate Exercises](intermediate.md)
- Strong C programming skills
- Understanding of kernel internals
- Experience with debugging tools

---

## Exercise 1: Write a Kernel Module

### Objective
Develop a loadable kernel module that interacts with hardware.

### Tasks

1. Create basic kernel module skeleton
2. Add initialization and cleanup functions
3. Implement /proc interface for userspace interaction
4. Cross-compile and test on target

### Step-by-Step Guide

**Create the module (hwinfo.c):**

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>

#define PROC_NAME "hwinfo"

static int hwinfo_show(struct seq_file *m, void *v)
{
    seq_printf(m, "Embedded Linux Hardware Info Module\n");
    seq_printf(m, "====================================\n");
    seq_printf(m, "Kernel Version: %s\n", UTS_RELEASE);
    seq_printf(m, "System RAM: %lu MB\n", 
               (unsigned long)(totalram_pages() * PAGE_SIZE / 1024 / 1024));
    seq_printf(m, "Page Size: %lu bytes\n", PAGE_SIZE);
    seq_printf(m, "HZ (Tick Rate): %d\n", HZ);
    return 0;
}

static int hwinfo_open(struct inode *inode, struct file *file)
{
    return single_open(file, hwinfo_show, NULL);
}

static const struct proc_ops hwinfo_fops = {
    .proc_open    = hwinfo_open,
    .proc_read    = seq_read,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};

static int __init hwinfo_init(void)
{
    struct proc_dir_entry *entry;
    
    entry = proc_create(PROC_NAME, 0444, NULL, &hwinfo_fops);
    if (!entry) {
        pr_err("hwinfo: failed to create /proc/%s\n", PROC_NAME);
        return -ENOMEM;
    }
    
    pr_info("hwinfo: module loaded, /proc/%s created\n", PROC_NAME);
    return 0;
}

static void __exit hwinfo_exit(void)
{
    remove_proc_entry(PROC_NAME, NULL);
    pr_info("hwinfo: module unloaded\n");
}

module_init(hwinfo_init);
module_exit(hwinfo_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Embedded Linux Labs");
MODULE_DESCRIPTION("Hardware Information Module");
MODULE_VERSION("1.0");
```

**Create Makefile:**

```makefile
obj-m := hwinfo.o

KERNEL_DIR ?= /path/to/linux
ARCH ?= arm
CROSS_COMPILE ?= arm-linux-gnueabihf-

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
```

**Build and test:**

```bash
# Build
make KERNEL_DIR=/path/to/linux

# Copy to target
scp hwinfo.ko target:/tmp/

# On target:
insmod /tmp/hwinfo.ko
cat /proc/hwinfo
rmmod hwinfo
```

### Expected Outcome

Module loads and creates `/proc/hwinfo` with system information.

### Challenge Extensions

1. Add sysfs interface instead of/in addition to proc
2. Read actual hardware registers
3. Add write capability to control hardware
4. Implement interrupt handler

### Troubleshooting Hints
- "Invalid module format"? Kernel version mismatch
- "Unknown symbol"? Check kernel config for required features
- Crash on load? Check for NULL pointer dereferences

---

## Exercise 2: Debug Kernel Panic

### Objective
Analyze and fix a kernel crash using debugging techniques.

### Tasks

1. Intentionally cause a kernel panic
2. Capture crash dump / oops message
3. Analyze with addr2line and objdump
4. Identify root cause

### Step-by-Step Guide

**Create buggy module (buggy.c):**

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/workqueue.h>

static struct delayed_work buggy_work;

static void buggy_handler(struct work_struct *work)
{
    int *ptr = NULL;
    
    pr_info("buggy: About to crash...\n");
    
    /* This will cause a NULL pointer dereference */
    *ptr = 42;
}

static int __init buggy_init(void)
{
    INIT_DELAYED_WORK(&buggy_work, buggy_handler);
    schedule_delayed_work(&buggy_work, HZ * 5); /* 5 seconds */
    pr_info("buggy: Crash in 5 seconds!\n");
    return 0;
}

static void __exit buggy_exit(void)
{
    cancel_delayed_work_sync(&buggy_work);
}

module_init(buggy_init);
module_exit(buggy_exit);
MODULE_LICENSE("GPL");
```

**Analyze the crash:**

```bash
# After crash, capture oops from serial log
# Look for lines like:
# PC is at buggy_handler+0x10/0x20 [buggy]

# Disassemble the module
arm-linux-gnueabihf-objdump -d buggy.ko

# Find the offset mentioned in oops
# addr2line for exact source line (if debug symbols)
arm-linux-gnueabihf-addr2line -e buggy.ko 0x10
```

### Oops Analysis Checklist

```
1. Find "PC is at" - identifies crashing function
2. Check register values - look for NULL (0x00000000)
3. Examine call stack - trace how we got there
4. Match offset to disassembly
```

### Expected Outcome

You can identify:
- Which function crashed
- Which line caused the crash
- What the NULL pointer access looked like

### Challenge: Fix and Verify

1. Add NULL check before dereference
2. Rebuild module
3. Verify crash is prevented

---

## Exercise 3: Boot Time Optimization

### Objective
Reduce boot time from power-on to application start.

### Tasks

1. Measure baseline boot time
2. Identify bottlenecks
3. Apply optimizations
4. Measure improvement

### Step-by-Step Guide

**Measure baseline:**

```bash
# Enable timestamps in dmesg
# In bootargs: printk.time=1

# After boot, check timestamps
dmesg | head -20
dmesg | tail -20

# Use systemd-analyze (if systemd)
systemd-analyze
systemd-analyze blame
```

**Optimization techniques:**

```bash
# 1. Kernel command line
# Add: quiet loglevel=0

# 2. Kernel config
# Disable: CONFIG_DEBUG_INFO
# Disable: Unused drivers
# Enable: CONFIG_CC_OPTIMIZE_FOR_SIZE

# 3. Init system
# Remove: Unused services
# Parallelize: Service startup

# 4. U-Boot
# Set: bootdelay=0
# Disable: Console banner if not needed
```

**Advanced: Boot graph:**

```bash
# Enable kernel boot graph
# In bootargs: initcall_debug

# After boot, generate chart
dmesg > boot.log
# Use scripts/bootgraph.pl from kernel source
```

### Expected Outcome

Documented boot time reduction with specific improvements.

### Target Metrics

| Stage | Typical | Optimized Target |
|-------|---------|------------------|
| U-Boot | 3-5s | <1s |
| Kernel | 5-15s | <3s |
| Userspace | 10-30s | <5s |
| **Total** | 20-50s | <10s |

---

## Exercise 4: Implement A/B Partition Scheme

### Objective
Create a robust A/B update system with automatic fallback.

### Tasks

1. Design partition layout
2. Implement U-Boot boot counter
3. Create update mechanism
4. Test failure recovery

### Step-by-Step Guide

**Partition Layout:**

```
mmcblk0p1 - Boot A (kernel, dtb)
mmcblk0p2 - Root A
mmcblk0p3 - Boot B (kernel, dtb)
mmcblk0p4 - Root B
mmcblk0p5 - Data (persistent)
mmcblk0p6 - U-Boot env
```

**U-Boot environment:**

```bash
# Set up A/B variables
=> setenv slot a
=> setenv bootlimit 3
=> setenv bootcount 0

# Boot logic
=> setenv ab_select '
    if test ${bootcount} -ge ${bootlimit}; then
        echo "Slot ${slot} failed, switching...";
        if test ${slot} = a; then
            setenv slot b;
        else
            setenv slot a;
        fi;
        setenv bootcount 0;
        saveenv;
    fi;
    setexpr bootcount ${bootcount} + 1;
    saveenv;
'

=> setenv boot_slot '
    if test ${slot} = a; then
        setenv bootpart 1;
        setenv rootpart 2;
    else
        setenv bootpart 3;
        setenv rootpart 4;
    fi;
    fatload mmc 0:${bootpart} ${loadaddr} zImage;
    fatload mmc 0:${bootpart} ${fdt_addr} board.dtb;
    setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p${rootpart} rootwait;
    bootz ${loadaddr} - ${fdt_addr};
'

=> setenv bootcmd 'run ab_select; run boot_slot'
=> saveenv
```

**Userspace success marker:**

```bash
#!/bin/bash
# /etc/init.d/boot-success.sh
# Called after successful boot

# Reset boot counter
fw_setenv bootcount 0
```

### Expected Outcome

System that:
- Boots from slot A normally
- After 3 failed boots, switches to slot B
- Resets counter on successful boot

### Test Scenarios

1. Normal boot - verify counter resets
2. Corrupt kernel A - verify switch to B
3. Both slots bad - verify enters recovery

---

## Exercise 5: Real-time Kernel Patch (PREEMPT_RT)

### Objective
Apply PREEMPT_RT patch and measure latency improvements.

### Tasks

1. Apply RT patch to kernel
2. Configure RT-specific options
3. Build and deploy
4. Benchmark latency

### Step-by-Step Guide

**Apply patch:**

```bash
# Download matching RT patch
wget https://cdn.kernel.org/pub/linux/kernel/projects/rt/6.6/patch-6.6-rt15.patch.xz
xz -d patch-6.6-rt15.patch.xz

# Apply to kernel
cd linux-6.6
patch -p1 < ../patch-6.6-rt15.patch
```

**Configure RT kernel:**

```bash
make menuconfig
# General Setup → Preemption Model → Fully Preemptible Kernel (RT)
# Enable: CONFIG_PREEMPT_RT
# Enable: CONFIG_HIGH_RES_TIMERS
# Disable: CONFIG_CPU_FREQ (or careful tuning)
```

**Benchmark with cyclictest:**

```bash
# Install rt-tests
git clone git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
cd rt-tests
make CROSS_COMPILE=arm-linux-gnueabihf-

# Run on target
./cyclictest -l10000 -m -Sp99 -i200 -h400 -q > output

# Analyze
grep -v -e "^#" -e "^$" output | awk '/Max/ {print}'
```

### Expected Outcome

| Metric | Non-RT | PREEMPT_RT |
|--------|--------|------------|
| Avg latency | 10-50µs | 5-20µs |
| Max latency | 500-5000µs | 50-100µs |

### Troubleshooting Hints
- High latency spikes? Check for CPU frequency scaling
- Kernel doesn't boot? Try less aggressive RT config first
- Cyclictest errors? Ensure permissions, run as root

---

## Exercise 6: Secure Boot Implementation

### Objective
Implement verified boot chain with signed images.

### Tasks

1. Generate signing keys
2. Sign kernel and U-Boot
3. Configure U-Boot for verification
4. Test secure boot flow

### Step-by-Step Guide

**Generate keys:**

```bash
# Generate RSA key pair
openssl genrsa -out signing_key.pem 2048
openssl rsa -in signing_key.pem -pubout -out signing_key.pub

# Convert for U-Boot
# (Platform specific - consult U-Boot docs)
```

**Enable FIT image signing:**

```bash
# Create ITS file (image tree source)
cat > kernel.its << 'EOF'
/dts-v1/;

/ {
    description = "Signed Kernel";
    #address-cells = <1>;
    
    images {
        kernel {
            description = "Linux kernel";
            data = /incbin/("zImage");
            type = "kernel";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <0x80008000>;
            entry = <0x80008000>;
            signature {
                algo = "sha256,rsa2048";
                key-name-hint = "signing_key";
            };
        };
        fdt {
            description = "Device Tree";
            data = /incbin/("board.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
        };
    };
    
    configurations {
        default = "conf";
        conf {
            description = "Signed boot configuration";
            kernel = "kernel";
            fdt = "fdt";
            signature {
                algo = "sha256,rsa2048";
                key-name-hint = "signing_key";
                sign-images = "kernel", "fdt";
            };
        };
    };
};
EOF

# Create signed FIT image
mkimage -f kernel.its -k keys/ -K u-boot.dtb -r image.fit
```

**Configure U-Boot:**

```bash
# Enable in menuconfig
CONFIG_FIT=y
CONFIG_FIT_SIGNATURE=y
CONFIG_RSA=y

# Add public key to U-Boot DTB during mkimage
```

### Expected Outcome

Boot chain that:
- Verifies kernel signature before loading
- Refuses to boot unsigned/modified images
- Provides tamper evidence

### Security Considerations

1. Protect private signing key
2. Store public key in secure location (OTP if available)
3. Consider rollback protection
4. Test failure modes

---

## Summary

After completing these exercises, you have advanced skills in:

- ✅ Kernel module development
- ✅ Kernel crash debugging and analysis
- ✅ Boot time optimization
- ✅ A/B partition update systems
- ✅ Real-time kernel configuration
- ✅ Secure boot implementation

---

## Certification Project

Combine skills from all exercises to create:

**A complete embedded Linux system that:**
1. Boots in under 10 seconds
2. Has A/B update capability
3. Uses custom kernel module for hardware interaction
4. Implements secure boot (optional)
5. Recovers from failed updates automatically

**Deliverables:**
- Source code for all components
- Build scripts
- Documentation
- Test plan and results

---

## Resources

- [Linux Kernel Documentation](https://www.kernel.org/doc/)
- [U-Boot Documentation](https://u-boot.readthedocs.io/)
- [Embedded Linux Wiki](https://elinux.org/)
- [Real-Time Linux Wiki](https://wiki.linuxfoundation.org/realtime/start)
