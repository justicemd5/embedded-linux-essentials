# Exercise 2: Debug Kernel Panic

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Learn to analyze and fix kernel crashes using debugging techniques specific to ARM architecture. This exercise covers intentionally buggy modules, crash analysis, and proper debugging workflows.

## Prerequisites

- Completed Exercise 1 (Kernel Module)
- Serial console access for crash capture
- Cross-compilation toolchain with debug tools
- Kernel built with debug symbols (optional but helpful)

## Difficulty: ⭐⭐⭐ Advanced

---

## 📁 Directory Structure

```
02_debug_kernel_panic/
├── modules/
│   ├── buggy/            # Intentionally buggy module
│   │   ├── buggy.c
│   │   └── Makefile
│   └── buggy_fixed/      # Fixed version
│       ├── buggy_fixed.c
│       └── Makefile
├── scripts/
│   ├── analyze_oops.sh   # Oops message analyzer
│   ├── capture_crash.sh  # Serial capture utility
│   └── decode_stack.sh   # Stack trace decoder
└── examples/
    └── oops_examples.txt # Reference oops messages
```

---

## Part 1: Kernel Crash Theory

### Types of Kernel Failures

```
┌─────────────────────────────────────────────────────────────┐
│                 KERNEL FAILURE TYPES                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  OOPS (Recoverable)                                         │
│  ══════════════════                                         │
│  • Triggered by: NULL deref, invalid memory access          │
│  • Effect: Process killed, system may continue              │
│  • Recovery: Usually possible, check dmesg                  │
│                                                             │
│  PANIC (Non-recoverable)                                    │
│  ═══════════════════════                                    │
│  • Triggered by: Critical subsystem failure, double fault   │
│  • Effect: System halts completely                          │
│  • Recovery: Requires reboot                                │
│                                                             │
│  BUG/WARN                                                   │
│  ═════════                                                  │
│  • Triggered by: BUG(), BUG_ON(), WARN(), WARN_ON()        │
│  • Effect: Assertion failure, stack dump                    │
│  • Recovery: WARN continues, BUG causes oops                │
│                                                             │
│  LOCKUP                                                     │
│  ══════                                                     │
│  • Soft lockup: CPU busy-looping without scheduling         │
│  • Hard lockup: CPU not responding to interrupts            │
│  • Detected by: watchdog mechanisms                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### ARM Oops Anatomy

```
┌─────────────────────────────────────────────────────────────┐
│                 ANATOMY OF ARM OOPS                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [  123.456789] Unable to handle kernel NULL pointer deref  │
│                 ├── Error type description                  │
│                                                             │
│  [  123.456800] Internal error: Oops: 805 [#1] SMP ARM      │
│                                 │     │   └── Instance #    │
│                                 │     └── Error code        │
│                                 └── ARM oops marker         │
│                                                             │
│  CPU: 0 PID: 123 Comm: kworker/0:1 Tainted: G O 6.6.0      │
│       │   │           │                    │               │
│       │   │           │                    └── Taint flags │
│       │   │           └── Process name                     │
│       │   └── Process ID                                   │
│       └── CPU number                                        │
│                                                             │
│  PC is at function_name+0x2c/0x40 [module]                  │
│          │             │    │      │                        │
│          │             │    │      └── Module name          │
│          │             │    └── Function size               │
│          │             └── Offset in function               │
│          └── Function where crash occurred                  │
│                                                             │
│  REGISTERS:                                                 │
│  pc : [<bf000028>]    ← Program Counter (crash address)    │
│  lr : [<bf000060>]    ← Link Register (return address)     │
│  sp : [cf8a5f00]      ← Stack Pointer                       │
│  r0-r12               ← General purpose registers           │
│                                                             │
│  ERROR CODES:                                               │
│  0x005 = Read from invalid address                          │
│  0x805 = Write to invalid address (bit 11 = write)         │
│  0x017 = Alignment fault                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Common Kernel Bugs

| Bug Type | Cause | Detection |
|----------|-------|-----------|
| NULL pointer dereference | Uninitialized or freed pointer | r0-r3 = 0x00000000 |
| Use after free | Accessing freed memory | KASAN, random crashes |
| Stack overflow | Deep recursion, large locals | Stack limit exceeded |
| Division by zero | Unchecked divisor | Undefined instruction |
| Buffer overflow | Out-of-bounds access | KASAN, memory corruption |
| Deadlock | Circular lock dependency | Lockdep warnings |
| Race condition | Missing synchronization | Random failures |

---

## Part 2: The Buggy Module

The buggy module provides four different crash types for practice.

📁 **Source:** [modules/buggy/buggy.c](02_debug_kernel_panic/modules/buggy/buggy.c)
📁 **Makefile:** [modules/buggy/Makefile](02_debug_kernel_panic/modules/buggy/Makefile)

### Bug Types

| Type | Description | Module Parameter |
|------|-------------|------------------|
| 1 | NULL pointer dereference | `bug_type=1` (default) |
| 2 | Use after free | `bug_type=2` |
| 3 | Stack overflow (recursion) | `bug_type=3` |
| 4 | Division by zero | `bug_type=4` |

### Build the Module

```bash
cd 02_debug_kernel_panic/modules/buggy
make KERNEL_DIR=~/bbb/linux

# Generate disassembly for analysis
make disasm

# View files
ls -la buggy.ko buggy.dis buggy.symbols
```

### Deploy and Trigger Crash

```bash
# Copy to BBB
scp buggy.ko debian@192.168.7.2:/tmp/

# IMPORTANT: Start serial capture first!
# In another terminal:
./scripts/capture_crash.sh /dev/ttyACM0

# On BBB (via SSH or serial)
sudo insmod /tmp/buggy.ko bug_type=1 delay_seconds=5
# Wait 5 seconds for crash...
```

---

## Part 3: Crash Analysis Workflow

### Step 1: Capture the Crash

📁 **Script:** [scripts/capture_crash.sh](02_debug_kernel_panic/scripts/capture_crash.sh)

```bash
# Start capture before loading module
chmod +x scripts/*.sh
./scripts/capture_crash.sh /dev/ttyACM0 crash.log
```

### Step 2: Analyze the Oops

📁 **Script:** [scripts/analyze_oops.sh](02_debug_kernel_panic/scripts/analyze_oops.sh)

```bash
# Analyze captured crash log
./scripts/analyze_oops.sh crash.log buggy.ko
```

Output:
```
=== Crash Location ===
PC is at trigger_null_deref+0x2c/0x40 [buggy]
  Function: trigger_null_deref
  Offset:   0x2c

=== NULL Pointer Analysis ===
Potential NULL pointers found in registers:
r0 : 00000000

=== Analysis Summary ===
Likely cause: NULL pointer dereference
  - Check if pointers are validated before use
  - Look for uninitialized pointers
```

### Step 3: Disassemble and Decode

```bash
# Generate disassembly
arm-linux-gnueabihf-objdump -d buggy.ko > buggy.dis

# Find crash location (offset 0x2c in trigger_null_deref)
arm-linux-gnueabihf-objdump -d buggy.ko | grep -A30 "<trigger_null_deref>:"
```

Example disassembly:
```asm
00000000 <trigger_null_deref>:
   0:   e92d4800    push    {fp, lr}
   4:   e28db004    add     fp, sp, #4
   8:   e59f0028    ldr     r0, [pc, #40]   ; format string
   c:   eb000000    bl      pr_info
  10:   e59f0024    ldr     r0, [pc, #36]   ; format string  
  14:   eb000000    bl      pr_info
  18:   e3a03000    mov     r3, #0          ; ← ptr = NULL
  1c:   e3a0202a    mov     r2, #42         ; ← value = 42
  20:   e5832000    str     r2, [r3]        ; ← CRASH! *ptr = 42
```

### Step 4: Use addr2line

```bash
# Get source line from offset
arm-linux-gnueabihf-addr2line -e buggy.ko -f 0x20
# Output:
# trigger_null_deref
# /path/to/buggy.c:35
```

---

## Part 4: The Fixed Module

📁 **Source:** [modules/buggy_fixed/buggy_fixed.c](02_debug_kernel_panic/modules/buggy_fixed/buggy_fixed.c)
📁 **Makefile:** [modules/buggy_fixed/Makefile](02_debug_kernel_panic/modules/buggy_fixed/Makefile)

This module demonstrates proper fixes for all bug types:

### Fix 1: NULL Pointer Check

```c
/* BAD */
int *ptr = NULL;
*ptr = 42;  /* CRASH */

/* GOOD */
int *ptr = kmalloc(sizeof(*ptr), GFP_KERNEL);
if (!ptr) {
    pr_err("Allocation failed\n");
    return -ENOMEM;
}
*ptr = 42;
kfree(ptr);
ptr = NULL;  /* Prevent use-after-free */
```

### Fix 2: Use After Free Prevention

```c
/* BAD */
kfree(data);
pr_info("Value: %d\n", data->value);  /* CRASH */

/* GOOD */
int saved = data->value;
kfree(data);
data = NULL;
pr_info("Value: %d\n", saved);
```

### Fix 3: Avoid Unbounded Recursion

```c
/* BAD */
int recursive(int n) {
    char buf[1024];
    return recursive(n + 1);  /* Stack overflow */
}

/* GOOD */
int iterative(int max) {
    int result = 0;
    for (int i = 0; i < max; i++) {
        result += i;
        cond_resched();  /* Allow scheduler */
    }
    return result;
}
```

### Fix 4: Validate Divisor

```c
/* BAD */
result = value / divisor;  /* May crash if divisor == 0 */

/* GOOD */
if (divisor == 0) {
    pr_warn("Division by zero\n");
    result = 0;
} else {
    result = value / divisor;
}
```

---

## Part 5: Advanced Debugging

### Enable KGDB

```bash
# Kernel config
CONFIG_KGDB=y
CONFIG_KGDB_SERIAL_CONSOLE=y
CONFIG_DEBUG_INFO=y

# Bootargs
setenv bootargs "... kgdboc=ttyO0,115200 kgdbwait"

# On host
arm-linux-gnueabihf-gdb vmlinux
(gdb) target remote /dev/ttyUSB0
(gdb) break trigger_null_deref
(gdb) continue
```

### Enable KASAN (Kernel Address Sanitizer)

```bash
# Kernel config (requires extra RAM)
CONFIG_KASAN=y
CONFIG_KASAN_INLINE=y

# Catches:
# - Use after free
# - Out-of-bounds access
# - Use after scope
```

### Use Dynamic Debug

```bash
# Enable module debug messages
echo 'module buggy +p' > /sys/kernel/debug/dynamic_debug/control

# Enable file debug
echo 'file buggy.c +pflmt' > /sys/kernel/debug/dynamic_debug/control
```

### ftrace for Execution Flow

```bash
# On BBB
mount -t tracefs nodev /sys/kernel/tracing
cd /sys/kernel/tracing

# Trace function calls
echo function > current_tracer
echo buggy_handler > set_ftrace_filter
echo 1 > tracing_on

# Load module
insmod /tmp/buggy.ko delay_seconds=3

# Wait for crash, then check trace
cat trace
```

---

## Part 6: Reference Material

📁 **Examples:** [examples/oops_examples.txt](02_debug_kernel_panic/examples/oops_examples.txt)

This file contains annotated oops examples for reference.

### Quick Reference: ARM Registers

| Register | Purpose | In Oops |
|----------|---------|---------|
| r0-r3 | Function arguments / scratch | Check for NULL |
| r4-r11 | Callee-saved | May contain useful data |
| r12 (ip) | Intra-procedure scratch | - |
| sp | Stack pointer | Stack address |
| lr | Link register | Return address |
| pc | Program counter | Crash location |

### Quick Reference: Analysis Commands

```bash
# Disassemble module
arm-linux-gnueabihf-objdump -d module.ko > module.dis

# With source annotation
arm-linux-gnueabihf-objdump -S module.ko > module_annotated.dis

# Symbol table
arm-linux-gnueabihf-nm module.ko

# addr2line
arm-linux-gnueabihf-addr2line -e module.ko -f 0xOFFSET

# Module info
modinfo module.ko

# Check dependencies
arm-linux-gnueabihf-nm module.ko | grep " U "
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No oops message visible | Enable `console=ttyO0,115200` in bootargs |
| addr2line shows ?? | Build module with `-g` flag |
| Offset doesn't match | Ensure analyzing correct .ko file |
| System hangs without message | May be hard lockup, try NMI watchdog |
| Cannot reproduce crash | Timing-dependent, try different scenarios |

---

## Verification Checklist

- [ ] Buggy module builds successfully
- [ ] Crash captured via serial console
- [ ] Oops message analyzed with scripts
- [ ] Crash location identified in source
- [ ] Fixed module runs without crash
- [ ] addr2line returns correct line numbers
- [ ] Disassembly matches crash offset

---

## Challenge Extensions

1. **Enable KGDB** - Set breakpoint before crash, examine registers
2. **Try KASAN** - Detect use-after-free more reliably
3. **Analyze real driver** - Find bugs in an actual kernel driver
4. **Create race condition** - Practice debugging concurrency bugs
5. **Set up kdump** - Capture crash dumps for offline analysis

---

[← Previous: Kernel Module](01_kernel_module.md) | [Back to Index](README.md) | [Next: Boot Optimization →](03_boot_optimization.md)
