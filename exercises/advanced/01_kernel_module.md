# Exercise 1: Kernel Module Development

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Develop a loadable kernel module that interacts with hardware and provides userspace interfaces.

## Prerequisites

- Completed kernel build from Lab 03
- Cross-compilation toolchain installed
- BeagleBone Black with working kernel
- Serial console access via USB (/dev/ttyACM0)

## Difficulty: ⭐⭐⭐ Advanced

---

## Tasks

1. Create basic kernel module skeleton
2. Add initialization and cleanup functions
3. Implement /proc interface for userspace interaction
4. Cross-compile and test on BeagleBone Black

---

## Step-by-Step Guide

### Step 1: Create Module Directory

```bash
mkdir -p ~/bbb-modules/hwinfo
cd ~/bbb-modules/hwinfo
```

### Step 2: Create the Module Source (hwinfo.c)

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>

#define PROC_NAME "hwinfo"

static int hwinfo_show(struct seq_file *m, void *v)
{
    seq_printf(m, "BeagleBone Black Hardware Info Module\n");
    seq_printf(m, "======================================\n");
    seq_printf(m, "Platform: TI AM335x (Cortex-A8)\n");
    seq_printf(m, "Kernel Version: %s\n", UTS_RELEASE);
    seq_printf(m, "System RAM: %lu MB\n", 
               (unsigned long)(totalram_pages() * PAGE_SIZE / 1024 / 1024));
    seq_printf(m, "Page Size: %lu bytes\n", PAGE_SIZE);
    seq_printf(m, "HZ (Tick Rate): %d\n", HZ);
    
#ifdef CONFIG_ARM
    seq_printf(m, "Architecture: ARM 32-bit\n");
#endif
    
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
MODULE_DESCRIPTION("BeagleBone Black Hardware Information Module");
MODULE_VERSION("1.0");
```

### Step 3: Create Makefile

```makefile
# Makefile for BeagleBone Black kernel module
obj-m := hwinfo.o

# Path to your cross-compiled kernel source
KERNEL_DIR ?= $(HOME)/bbb/linux

# BeagleBone Black settings
ARCH ?= arm
CROSS_COMPILE ?= arm-linux-gnueabihf-

# Build targets
all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean

# Install to target (adjust IP/path as needed)
install:
	scp hwinfo.ko debian@beaglebone:/tmp/

.PHONY: all clean install
```

### Step 4: Build the Module

```bash
# Set environment
export KERNEL_DIR=~/bbb/linux
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

# Build
make

# Verify output
file hwinfo.ko
# Should show: ELF 32-bit LSB relocatable, ARM, ...
```

### Step 5: Deploy and Test on BeagleBone Black

```bash
# Copy to target
scp hwinfo.ko debian@192.168.7.2:/tmp/

# Connect via serial console
screen /dev/ttyACM0 115200

# On BeagleBone Black:
sudo insmod /tmp/hwinfo.ko
dmesg | tail -5
cat /proc/hwinfo
sudo rmmod hwinfo
```

---

## Expected Output

```
BeagleBone Black Hardware Info Module
======================================
Platform: TI AM335x (Cortex-A8)
Kernel Version: 6.6.0
System RAM: 512 MB
Page Size: 4096 bytes
HZ (Tick Rate): 100
Architecture: ARM 32-bit
```

---

## Challenge Extensions

### Challenge 1: Add Sysfs Interface

Create a sysfs interface instead of /proc:

```c
#include <linux/kobject.h>
#include <linux/sysfs.h>

static struct kobject *hwinfo_kobj;

static ssize_t ram_show(struct kobject *kobj, 
                        struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%lu\n", 
                   (unsigned long)(totalram_pages() * PAGE_SIZE / 1024 / 1024));
}

static struct kobj_attribute ram_attribute = 
    __ATTR(ram_mb, 0444, ram_show, NULL);

static int __init hwinfo_init(void)
{
    hwinfo_kobj = kobject_create_and_add("hwinfo", kernel_kobj);
    if (!hwinfo_kobj)
        return -ENOMEM;
    
    return sysfs_create_file(hwinfo_kobj, &ram_attribute.attr);
}
```

### Challenge 2: Read AM335x Hardware Registers

```c
#include <linux/io.h>

#define AM335X_CONTROL_MODULE_BASE  0x44E10000
#define DEVICE_ID_OFFSET            0x0600

static void read_device_id(struct seq_file *m)
{
    void __iomem *ctrl_base;
    u32 device_id;
    
    ctrl_base = ioremap(AM335X_CONTROL_MODULE_BASE, 0x1000);
    if (!ctrl_base) {
        seq_printf(m, "Failed to map control module\n");
        return;
    }
    
    device_id = readl(ctrl_base + DEVICE_ID_OFFSET);
    seq_printf(m, "Device ID: 0x%08x\n", device_id);
    
    iounmap(ctrl_base);
}
```

### Challenge 3: Add Write Capability

```c
static ssize_t hwinfo_write(struct file *file, const char __user *buf,
                            size_t count, loff_t *ppos)
{
    char kbuf[64];
    
    if (count >= sizeof(kbuf))
        return -EINVAL;
    
    if (copy_from_user(kbuf, buf, count))
        return -EFAULT;
    
    kbuf[count] = '\0';
    pr_info("hwinfo: received command: %s", kbuf);
    
    /* Process command here */
    
    return count;
}

static const struct proc_ops hwinfo_fops = {
    .proc_open    = hwinfo_open,
    .proc_read    = seq_read,
    .proc_write   = hwinfo_write,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Invalid module format" | Kernel version mismatch | Rebuild with correct kernel headers |
| "Unknown symbol" | Missing kernel config | Enable required features in kernel config |
| Module crashes on load | NULL pointer dereference | Add defensive checks, use pr_debug |
| Permission denied | Not root | Use sudo for insmod/rmmod |

### Debugging Tips

```bash
# Check kernel log for errors
dmesg | grep hwinfo

# Verify module info
modinfo hwinfo.ko

# Check symbol dependencies
nm hwinfo.ko | grep " U "

# Enable dynamic debug
echo 'module hwinfo +p' > /sys/kernel/debug/dynamic_debug/control
```

---

## Verification Checklist

- [ ] Module compiles without warnings
- [ ] Module loads successfully on BBB
- [ ] /proc/hwinfo shows correct information
- [ ] Module unloads cleanly
- [ ] No memory leaks (check with kmemleak if enabled)
- [ ] dmesg shows init/exit messages

---

[← Back to Advanced Exercises](README.md) | [Next: Debug Kernel Panic →](02_debug_kernel_panic.md)
