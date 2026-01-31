# Exercise 2: Debug Kernel Panic

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Analyze and fix a kernel crash using debugging techniques specific to ARM architecture.

## Prerequisites

- Completed Exercise 1 (Kernel Module)
- Serial console access for crash capture
- Cross-compilation toolchain with debug tools
- Kernel built with debug symbols (optional but helpful)

## Difficulty: ⭐⭐⭐ Advanced

---

## Tasks

1. Intentionally cause a kernel panic
2. Capture crash dump / oops message via serial
3. Analyze with addr2line and objdump
4. Identify root cause and fix

---

## Step-by-Step Guide

### Step 1: Create a Buggy Module

```bash
mkdir -p ~/bbb-modules/buggy
cd ~/bbb-modules/buggy
```

**buggy.c:**

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/workqueue.h>
#include <linux/slab.h>

static struct delayed_work buggy_work;

static void buggy_handler(struct work_struct *work)
{
    int *ptr = NULL;
    
    pr_info("buggy: About to crash on BeagleBone Black...\n");
    pr_info("buggy: Dereferencing NULL pointer in 3..2..1..\n");
    
    /* This will cause a NULL pointer dereference */
    *ptr = 42;
    
    /* Never reached */
    pr_info("buggy: This message will never appear\n");
}

static int __init buggy_init(void)
{
    pr_info("buggy: Module loaded on AM335x\n");
    pr_info("buggy: Scheduling crash in 5 seconds...\n");
    
    INIT_DELAYED_WORK(&buggy_work, buggy_handler);
    schedule_delayed_work(&buggy_work, HZ * 5); /* 5 seconds */
    
    return 0;
}

static void __exit buggy_exit(void)
{
    cancel_delayed_work_sync(&buggy_work);
    pr_info("buggy: Module unloaded\n");
}

module_init(buggy_init);
module_exit(buggy_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Embedded Linux Labs");
MODULE_DESCRIPTION("Intentionally buggy module for debugging practice");
```

**Makefile:**

```makefile
obj-m := buggy.o

KERNEL_DIR ?= $(HOME)/bbb/linux
ARCH ?= arm
CROSS_COMPILE ?= arm-linux-gnueabihf-

# Build with debug info for better analysis
EXTRA_CFLAGS += -g

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
```

### Step 2: Build and Deploy

```bash
make
scp buggy.ko debian@192.168.7.2:/tmp/
```

### Step 3: Capture the Crash

Open serial console and load the module:

```bash
# On host - start serial capture
screen -L -Logfile crash.log /dev/ttyACM0 115200

# On BeagleBone Black:
sudo insmod /tmp/buggy.ko
# Wait 5 seconds for crash...
```

### Step 4: Analyze the Oops

Example ARM oops output:

```
[  123.456789] buggy: About to crash on BeagleBone Black...
[  123.456790] buggy: Dereferencing NULL pointer in 3..2..1..
[  123.456800] Unable to handle kernel NULL pointer dereference at virtual address 00000000
[  123.456810] pgd = (ptrval)
[  123.456820] [00000000] *pgd=00000000
[  123.456830] Internal error: Oops: 805 [#1] SMP ARM
[  123.456840] Modules linked in: buggy(O+)
[  123.456850] CPU: 0 PID: 123 Comm: kworker/0:1 Tainted: G           O      6.6.0 #1
[  123.456860] Hardware name: TI AM335x BeagleBone Black
[  123.456870] Workqueue: events buggy_handler [buggy]
[  123.456880] PC is at buggy_handler+0x2c/0x40 [buggy]
[  123.456890] LR is at process_one_work+0x1a8/0x2c0
[  123.456900] pc : [<bf000028>]    lr : [<c0047abc>]    psr: 60000013
[  123.456910] sp : cf8a5f00  ip : cf8a5f38  fp : cf8a5f34
[  123.456920] r10: 00000000  r9 : c0803a00  r8 : cf8a4000
[  123.456930] r7 : c1820100  r6 : bf000000  r5 : cf8f7e00  r4 : c1820118
[  123.456940] r3 : 0000002a  r2 : 00000000  r1 : cf8a5e94  r0 : 00000000
[  123.456950] Flags: nZCv  IRQs on  FIQs on  Mode SVC_32  ISA ARM
```

### Step 5: Decode the Crash

**Key information from oops:**

| Field | Value | Meaning |
|-------|-------|---------|
| PC is at | buggy_handler+0x2c/0x40 | Crash location |
| r0 | 00000000 | NULL pointer! |
| r3 | 0000002a | Value 42 (0x2a) we tried to write |

**Disassemble the module:**

```bash
# Disassemble
arm-linux-gnueabihf-objdump -d buggy.ko > buggy.dis

# Find the crash offset (0x2c)
arm-linux-gnueabihf-objdump -d buggy.ko | grep -A20 "<buggy_handler>:"
```

**Expected disassembly:**

```asm
00000000 <buggy_handler>:
   0:   e92d4800    push    {fp, lr}
   4:   e28db004    add     fp, sp, #4
   8:   e59f0024    ldr     r0, [pc, #36]   ; load format string
   c:   eb000000    bl      pr_info
  10:   e59f0020    ldr     r0, [pc, #32]   ; load format string
  14:   eb000000    bl      pr_info
  18:   e3a03000    mov     r3, #0          ; ptr = NULL
  1c:   e3a0202a    mov     r2, #42         ; value = 42
  20:   e5832000    str     r2, [r3]        ; CRASH! *ptr = 42
  ...
```

**Use addr2line (if debug symbols):**

```bash
arm-linux-gnueabihf-addr2line -e buggy.o -f 0x2c
# Output: buggy_handler
#         /path/to/buggy.c:15
```

---

## Oops Analysis Checklist

```
┌─────────────────────────────────────────────────────────────┐
│                 KERNEL OOPS ANALYSIS                        │
├─────────────────────────────────────────────────────────────┤
│ 1. Find "PC is at" → Identifies crashing function          │
│                                                             │
│ 2. Check registers → Look for NULL (0x00000000)            │
│    r0-r3: Function arguments                                │
│    r4-r11: Callee-saved registers                          │
│    sp: Stack pointer                                        │
│    lr: Link register (return address)                       │
│    pc: Program counter (crash location)                     │
│                                                             │
│ 3. Examine call stack → Trace execution path               │
│                                                             │
│ 4. Match offset to disassembly → Find exact instruction    │
│                                                             │
│ 5. Correlate with source → Use addr2line for line number   │
└─────────────────────────────────────────────────────────────┘
```

---

## Fix the Bug

**Fixed buggy.c:**

```c
static void buggy_handler(struct work_struct *work)
{
    int value = 42;
    int *ptr = &value;  /* Point to valid memory */
    
    pr_info("buggy: Writing value safely...\n");
    
    /* Safe: ptr points to stack variable */
    *ptr = 42;
    
    pr_info("buggy: Value written successfully: %d\n", *ptr);
}
```

**Or with proper heap allocation:**

```c
static void buggy_handler(struct work_struct *work)
{
    int *ptr;
    
    ptr = kmalloc(sizeof(int), GFP_KERNEL);
    if (!ptr) {
        pr_err("buggy: Memory allocation failed\n");
        return;
    }
    
    *ptr = 42;
    pr_info("buggy: Value written successfully: %d\n", *ptr);
    
    kfree(ptr);
}
```

---

## Advanced Debugging Techniques

### Enable More Debug Info

Add to kernel bootargs:

```
console=ttyO0,115200n8 earlyprintk debug ignore_loglevel
```

### Use KGDB (Kernel Debugger)

```bash
# Kernel config
CONFIG_KGDB=y
CONFIG_KGDB_SERIAL_CONSOLE=y

# Bootargs
kgdboc=ttyO0,115200 kgdbwait

# On host (using second serial or ethernet)
arm-linux-gnueabihf-gdb vmlinux
(gdb) target remote /dev/ttyUSB0
```

### Kernel Address Sanitizer (KASAN)

```bash
# Enable in kernel config (requires more RAM)
CONFIG_KASAN=y
CONFIG_KASAN_INLINE=y

# Catches use-after-free, out-of-bounds, etc.
```

---

## Common ARM Oops Types

| Error Code | Description |
|------------|-------------|
| Oops: 5 | Read from invalid address |
| Oops: 805 | Write to invalid address |
| Oops: 17 | Alignment fault |
| Oops: 207 | Execute from invalid address |

---

## Verification Checklist

- [ ] Successfully triggered kernel oops
- [ ] Captured complete oops message via serial
- [ ] Identified crash function and offset
- [ ] Matched offset to source line
- [ ] Created and tested fix
- [ ] Module now works without crash

---

[← Previous: Kernel Module](01_kernel_module.md) | [Back to Index](README.md) | [Next: Boot Optimization →](03_boot_optimization.md)
