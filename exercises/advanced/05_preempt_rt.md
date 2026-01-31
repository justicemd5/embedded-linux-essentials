# Exercise 5: PREEMPT_RT Real-Time Kernel

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Apply PREEMPT_RT patch to the Linux kernel and measure latency improvements for real-time applications on the BeagleBone Black.

## Prerequisites

- Working kernel build setup for BBB
- Understanding of real-time concepts
- Cross-compilation toolchain (arm-linux-gnueabihf-)
- Application requiring deterministic timing

## Difficulty: ⭐⭐⭐⭐ Expert

---

## Table of Contents

1. [Real-Time Systems Theory](#real-time-systems-theory)
2. [Linux Scheduling Fundamentals](#linux-scheduling-fundamentals)
3. [Why Standard Linux is Not Real-Time](#why-standard-linux-is-not-real-time)
4. [PREEMPT_RT Deep Dive](#preempt_rt-deep-dive)
5. [Step-by-Step Implementation](#step-by-step-guide)
6. [Application Development](#rt-application-development)
7. [Advanced Tuning](#advanced-system-tuning)
8. [Debugging and Profiling](#debugging-and-profiling)
9. [Real-World Use Cases](#real-world-use-cases)
10. [Alternatives to PREEMPT_RT](#alternatives-to-preempt_rt)

---

# Part 1: Theory and Background

## Real-Time Systems Theory

### What is Real-Time?

**Real-time does NOT mean "fast"** — it means **predictable** and **deterministic**.

A real-time system must respond to events within a **guaranteed time bound** called the **deadline**. Missing a deadline can have consequences ranging from degraded performance to catastrophic failure.

```
┌─────────────────────────────────────────────────────────────┐
│              REAL-TIME SYSTEM CLASSIFICATION                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  HARD REAL-TIME                                             │
│  ═══════════════                                            │
│  • Missing deadline = System failure                        │
│  • Examples: Airbag deployment, pacemaker, ABS brakes       │
│  • Deadline: microseconds to milliseconds                   │
│  • Consequence: Death, injury, or catastrophic damage       │
│                                                             │
│  FIRM REAL-TIME                                             │
│  ═══════════════                                            │
│  • Missing deadline = Result becomes worthless              │
│  • Examples: Financial trading, video frame rendering       │
│  • Deadline: milliseconds to seconds                        │
│  • Consequence: Missed opportunity, degraded quality        │
│                                                             │
│  SOFT REAL-TIME                                             │
│  ══════════════                                             │
│  • Missing deadline = Degraded experience                   │
│  • Examples: Video streaming, audio playback, VoIP          │
│  • Deadline: milliseconds to seconds                        │
│  • Consequence: Glitches, stuttering, user annoyance        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Key Real-Time Metrics

| Metric | Definition | Typical Values |
|--------|------------|----------------|
| **Latency** | Time from event to response start | 1µs - 10ms |
| **Jitter** | Variation in latency | Should be < 10% of latency |
| **Deadline** | Maximum allowed response time | Application-specific |
| **WCET** | Worst-Case Execution Time | Must be < Deadline |
| **Period** | Time between recurring events | 100µs - 1s |

### The Real-Time Equation

For a system to be real-time:

```
WCET (Worst-Case Execution Time) + WCRT (Worst-Case Response Time) ≤ Deadline
```

Where:
- **WCET**: Maximum time your code takes to execute
- **WCRT**: Maximum time from event occurrence to code execution start
- **Deadline**: Your application's timing requirement

**Example - Motor Control Loop:**
```
Event: Encoder pulse every 100µs
Deadline: Must respond within 50µs
WCET of handler: 10µs
Required WCRT: ≤ 40µs

Standard Linux WCRT: 500-5000µs ❌ FAILS
PREEMPT_RT WCRT: 20-80µs ✓ PASSES
```

---

## Linux Scheduling Fundamentals

### The Linux Scheduler

Linux uses the **Completely Fair Scheduler (CFS)** for normal processes, but also supports real-time scheduling policies.

```
┌─────────────────────────────────────────────────────────────┐
│                 LINUX SCHEDULING CLASSES                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Priority 0-99: REAL-TIME (higher number = higher priority)│
│  ┌─────────────────────────────────────────────────────┐   │
│  │  SCHED_FIFO    │ First-In-First-Out, no time slicing│   │
│  │  SCHED_RR      │ Round-Robin with time quantum      │   │
│  │  SCHED_DEADLINE│ Earliest Deadline First (EDF)      │   │
│  └─────────────────────────────────────────────────────┘   │
│                          ▲                                  │
│                          │ Always preempts                  │
│                          ▼                                  │
│  Priority 100-139: NORMAL (nice -20 to +19)                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  SCHED_OTHER   │ Default, CFS time-sharing          │   │
│  │  SCHED_BATCH   │ CPU-intensive batch jobs           │   │
│  │  SCHED_IDLE    │ Very low priority background       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### SCHED_FIFO vs SCHED_RR

```c
/* SCHED_FIFO Example */
// Process runs until:
// 1. It voluntarily yields (sched_yield())
// 2. It blocks (I/O, sleep, mutex)
// 3. Higher priority RT task becomes runnable

/* SCHED_RR Example */
// Same as FIFO, but also:
// 4. Time quantum expires → moves to end of priority queue
// Default quantum: 100ms (check /proc/sys/kernel/sched_rr_timeslice_ms)
```

### SCHED_DEADLINE (Earliest Deadline First)

The most sophisticated RT scheduler, based on GEDF (Global Earliest Deadline First):

```c
#include <sched.h>
#include <linux/sched.h>

struct sched_attr {
    __u32 size;
    __u32 sched_policy;     /* SCHED_DEADLINE */
    __u64 sched_flags;
    
    /* SCHED_DEADLINE parameters */
    __u64 sched_runtime;    /* Execution time per period (ns) */
    __u64 sched_deadline;   /* Relative deadline (ns) */
    __u64 sched_period;     /* Period (ns) */
};

/* Example: Task needs 10ms every 100ms, deadline at 50ms */
struct sched_attr attr = {
    .size = sizeof(attr),
    .sched_policy = SCHED_DEADLINE,
    .sched_runtime =  10 * 1000000,  /* 10ms */
    .sched_deadline = 50 * 1000000,  /* 50ms */
    .sched_period = 100 * 1000000,   /* 100ms */
};

sched_setattr(0, &attr, 0);
```

---

## Why Standard Linux is Not Real-Time

### Sources of Unbounded Latency

Standard Linux has several mechanisms that can delay high-priority tasks for unpredictable amounts of time:

```
┌─────────────────────────────────────────────────────────────┐
│          LATENCY SOURCES IN STANDARD LINUX                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. INTERRUPT HANDLING                                      │
│     ┌─────────────────────────────────────────────────┐    │
│     │ Hardware IRQ → Top Half (ISR) → Bottom Half     │    │
│     │                     ↓                            │    │
│     │            Interrupts disabled!                  │    │
│     │            Can't preempt ISR                     │    │
│     └─────────────────────────────────────────────────┘    │
│     Impact: 10µs - 1ms+ (varies by driver)                 │
│                                                             │
│  2. SPINLOCKS                                               │
│     ┌─────────────────────────────────────────────────┐    │
│     │ spin_lock_irqsave() disables:                   │    │
│     │ • Local interrupts                               │    │
│     │ • Preemption                                     │    │
│     │ Critical section can be arbitrarily long        │    │
│     └─────────────────────────────────────────────────┘    │
│     Impact: 1µs - 10ms (depends on driver)                 │
│                                                             │
│  3. SOFTIRQS / TASKLETS                                     │
│     ┌─────────────────────────────────────────────────┐    │
│     │ Network RX, timer handling, block I/O           │    │
│     │ Run with preemption disabled                    │    │
│     │ Can process many items in one batch             │    │
│     └─────────────────────────────────────────────────┘    │
│     Impact: 100µs - 50ms (network storm = long delay)      │
│                                                             │
│  4. RCU (Read-Copy-Update) CALLBACKS                        │
│     ┌─────────────────────────────────────────────────┐    │
│     │ Memory reclamation, route table updates         │    │
│     │ Batched processing                              │    │
│     └─────────────────────────────────────────────────┘    │
│     Impact: 10µs - 10ms                                    │
│                                                             │
│  5. MEMORY MANAGEMENT                                       │
│     ┌─────────────────────────────────────────────────┐    │
│     │ • Page faults (demand paging)                   │    │
│     │ • Memory allocation (buddy/slab)                │    │
│     │ • Memory compaction                             │    │
│     │ • Swap operations                               │    │
│     └─────────────────────────────────────────────────┘    │
│     Impact: 1µs - 100ms+ (disk I/O if swapping)            │
│                                                             │
│  6. KERNEL PREEMPTION POINTS                                │
│     ┌─────────────────────────────────────────────────┐    │
│     │ Even with CONFIG_PREEMPT, kernel code between   │    │
│     │ preemption points cannot be interrupted         │    │
│     └─────────────────────────────────────────────────┘    │
│     Impact: Variable                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Latency Example: Network Interrupt Storm

```
Timeline (microseconds):

0     100   200   300   400   500   ...  5000
|-----|-----|-----|-----|-----|-----|...|-----|
                                              
[========= Network IRQ Processing =========]
                    ↑
            Your RT task wants to run here
            but must wait until IRQ processing completes!
            
Result: 5ms latency instead of expected 50µs
```

### The Priority Inversion Problem

```
┌─────────────────────────────────────────────────────────────┐
│                 PRIORITY INVERSION                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Time →                                                     │
│                                                             │
│  High-Pri ──────┬──────[BLOCKED]─────────────┬──────────   │
│  Task           │                             │             │
│                 │  Waiting for lock           │             │
│                 ▼                             ▲             │
│  Med-Pri  ══════════════════════════════════════════════   │
│  Task           Running (no lock needed)                    │
│                 PREEMPTS low-priority task!                 │
│                                                             │
│  Low-Pri  ──────┬────────────────────────────┬──────────   │
│  Task      [LOCK]        Preempted!          [UNLOCK]       │
│                 │        Can't run!           │             │
│                 ▼                             ▲             │
│                                                             │
│  Result: High-priority task waits for MEDIUM priority!     │
│  This is UNBOUNDED - medium task could run forever         │
│                                                             │
└─────────────────────────────────────────────────────────────┘

SOLUTION: Priority Inheritance Protocol
- When high-pri blocks on lock held by low-pri
- Low-pri temporarily inherits high-pri's priority  
- Medium-pri cannot preempt anymore
- Lock released faster, high-pri runs sooner
```

---

## PREEMPT_RT Deep Dive

### What PREEMPT_RT Changes

The PREEMPT_RT patch (now partially mainlined) transforms Linux into a fully preemptible kernel:

```
┌─────────────────────────────────────────────────────────────┐
│                 PREEMPT_RT TRANSFORMATIONS                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  STANDARD LINUX              PREEMPT_RT                     │
│  ══════════════              ══════════                     │
│                                                             │
│  1. INTERRUPT HANDLERS                                      │
│  ┌─────────────────┐        ┌─────────────────┐            │
│  │ Runs in IRQ     │   →    │ Runs as kernel  │            │
│  │ context         │        │ thread          │            │
│  │ Can't preempt   │        │ CAN be preempted│            │
│  └─────────────────┘        └─────────────────┘            │
│                                                             │
│  2. SPINLOCKS                                               │
│  ┌─────────────────┐        ┌─────────────────┐            │
│  │ spin_lock()     │   →    │ rt_mutex (sleeps)│           │
│  │ Disables preempt│        │ Preemption OK   │            │
│  │ Busy-waits      │        │ Priority inherit│            │
│  └─────────────────┘        └─────────────────┘            │
│                                                             │
│  3. SOFTIRQS                                                │
│  ┌─────────────────┐        ┌─────────────────┐            │
│  │ Run in softirq  │   →    │ Run in kernel   │            │
│  │ context         │        │ threads         │            │
│  │ Batch processed │        │ (ksoftirqd)     │            │
│  └─────────────────┘        └─────────────────┘            │
│                                                             │
│  4. RCU                                                     │
│  ┌─────────────────┐        ┌─────────────────┐            │
│  │ Preemption      │   →    │ Preemptible RCU │            │
│  │ disabled        │        │ (PREEMPT_RCU)   │            │
│  └─────────────────┘        └─────────────────┘            │
│                                                             │
│  5. SLEEPING SPINLOCKS                                      │
│  ┌─────────────────┐        ┌─────────────────┐            │
│  │ local_irq_save()│   →    │ local_lock      │            │
│  │ Disables IRQs   │        │ Sleepable       │            │
│  └─────────────────┘        └─────────────────┘            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Threaded Interrupt Handlers

In PREEMPT_RT, interrupt handlers become schedulable threads:

```c
/* Standard Linux IRQ handler */
static irqreturn_t my_isr(int irq, void *dev_id)
{
    /* Runs with interrupts disabled on this CPU */
    /* Cannot be preempted */
    /* Should be VERY short */
    do_something_quick();
    return IRQ_HANDLED;
}

/* PREEMPT_RT: Handler runs as thread */
/* Priority determined by: /proc/irq/<n>/smp_affinity and chrt */

$ ps aux | grep irq
root  [irq/28-mmc0]     /* MMC interrupt thread */
root  [irq/45-eth0]     /* Network interrupt thread */
root  [irq/70-gpio]     /* GPIO interrupt thread */

/* You can set IRQ thread priorities! */
$ chrt -f -p 90 $(pgrep -f "irq/70-gpio")  /* Set GPIO IRQ to priority 90 */
```

### Spinlock Transformation

```c
/* What happens to spinlocks in PREEMPT_RT */

/* STANDARD LINUX */
spinlock_t lock;
spin_lock(&lock);       /* Disables preemption, busy-waits */
/* critical section */
spin_unlock(&lock);

/* PREEMPT_RT - Automatically transformed to: */
struct rt_mutex lock;   /* Now a sleeping lock! */
rt_mutex_lock(&lock);   /* Can sleep, has priority inheritance */
/* critical section - CAN BE PREEMPTED by higher priority! */
rt_mutex_unlock(&lock);

/* Some locks MUST remain spinning (raw_spinlock_t) */
raw_spinlock_t raw_lock;  /* Stays as true spinlock */
raw_spin_lock(&raw_lock); /* For scheduler, interrupt controller, etc. */
```

### What Stays Non-Preemptible

Even in PREEMPT_RT, some code paths cannot be preempted:

```
┌─────────────────────────────────────────────────────────────┐
│         NON-PREEMPTIBLE CODE IN PREEMPT_RT                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. raw_spinlock_t holders                                  │
│     • Scheduler code                                        │
│     • Interrupt controller                                  │
│     • Low-level timer code                                  │
│                                                             │
│  2. NMI (Non-Maskable Interrupt) handlers                   │
│     • Hardware watchdog                                     │
│     • Machine check exceptions                              │
│                                                             │
│  3. Entry/exit code                                         │
│     • System call entry/exit                                │
│     • Interrupt entry/exit                                  │
│                                                             │
│  4. Some architecture-specific code                         │
│     • TLB flush IPIs                                        │
│     • CPU hotplug                                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Preemption Levels Comparison

```
┌─────────────────────────────────────────────────────────────┐
│              LINUX PREEMPTION CONFIGURATIONS                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CONFIG_PREEMPT_NONE (Server)                               │
│  ════════════════════════════                               │
│  • No kernel preemption                                     │
│  • Preempt only at: syscall return, interrupt return        │
│  • Best throughput, worst latency                           │
│  • Latency: unbounded (10ms+ common)                        │
│                                                             │
│  CONFIG_PREEMPT_VOLUNTARY (Desktop default)                 │
│  ═════════════════════════════════════════                  │
│  • Explicit preemption points (might_sleep())               │
│  • Better interactivity                                     │
│  • Latency: 1-10ms typical                                  │
│                                                             │
│  CONFIG_PREEMPT (Low-Latency Desktop)                       │
│  ════════════════════════════════════                       │
│  • Preempt anywhere except:                                 │
│    - Spinlock held                                          │
│    - Interrupts disabled                                    │
│    - preempt_disable() sections                             │
│  • Latency: 100µs - 1ms typical, can spike to 10ms+        │
│                                                             │
│  CONFIG_PREEMPT_RT (Real-Time) ← This exercise!            │
│  ══════════════════════════════════════════════             │
│  • Nearly everything preemptible                            │
│  • Threaded interrupts                                      │
│  • Sleeping spinlocks                                       │
│  • Priority inheritance                                     │
│  • Latency: 20-100µs typical, worst-case < 150µs           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

# Part 2: Implementation

## Step-by-Step Guide

### Step 1: Get Matching RT Patch

```bash
cd ~/bbb
mkdir rt-kernel && cd rt-kernel

# Check your kernel version
KERNEL_VERSION=6.6.32

# Download RT patch (adjust version to match your kernel)
RT_VERSION=6.6.32-rt32
wget https://cdn.kernel.org/pub/linux/kernel/projects/rt/6.6/patch-${RT_VERSION}.patch.xz
xz -d patch-${RT_VERSION}.patch.xz

# Clone matching kernel
git clone --depth 1 --branch v${KERNEL_VERSION} \
    git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux-rt
```

### Step 2: Apply RT Patch

```bash
cd linux-rt

# Apply patch
patch -p1 < ../patch-${RT_VERSION}.patch

# Verify patch applied
grep -r "PREEMPT_RT" Kconfig*
# Should show PREEMPT_RT options
```

### Step 3: Configure RT Kernel

```bash
# Start with BBB config
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- omap2plus_defconfig

# Enter menuconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig
```

**Required RT configuration:**

```
General setup --->
    Preemption Model --->
        (X) Fully Preemptible Kernel (Real-Time)

Kernel hacking --->
    Memory Debugging --->
        [ ] Debug preemptible kernel  (disable for production)

Kernel Features --->
    [*] High Resolution Timer Support
    Timer frequency --->
        (X) 1000 HZ

Power management options --->
    CPU Frequency scaling --->
        [ ] CPU Frequency scaling   (disable for consistent latency)
    
CPU Power Management --->
    CPU Idle --->
        [ ] CPU idle PM support     (or limit idle states)
```

**Save and verify:**

```bash
grep PREEMPT_RT .config
# Should show: CONFIG_PREEMPT_RT=y
```

### Step 4: Build RT Kernel

```bash
# Build kernel and modules
make -j$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage
make -j$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- modules
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- dtbs

# Verify RT in version
strings arch/arm/boot/zImage | grep -i "Linux version" | head -1
# Should show: Linux version 6.6.32-rt32 ...
```

### Step 5: Deploy RT Kernel

```bash
# Mount SD card boot partition
sudo mount /dev/sdX1 /mnt

# Backup original kernel
sudo mv /mnt/zImage /mnt/zImage.backup

# Install RT kernel
sudo cp arch/arm/boot/zImage /mnt/
sudo cp arch/arm/boot/dts/am335x-boneblack.dtb /mnt/

# Install modules to rootfs
sudo mount /dev/sdX2 /mnt/rootfs
sudo make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
    INSTALL_MOD_PATH=/mnt/rootfs modules_install

sudo umount /mnt /mnt/rootfs
```

### Step 6: Build Cyclictest

```bash
# Clone rt-tests
git clone git://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
cd rt-tests

# Cross-compile
make CROSS_COMPILE=arm-linux-gnueabihf-

# Copy to target
scp cyclictest debian@192.168.7.2:/usr/local/bin/
```

### Step 7: Run Latency Tests

**On BeagleBone Black:**

```bash
# Basic test (as root)
sudo cyclictest -l10000 -m -Sp90 -i200 -h400 -q

# Full stress test
# Terminal 1: Generate CPU load
stress-ng --cpu 4 --io 2 --vm 1 --vm-bytes 64M --timeout 300s &

# Terminal 2: Generate network load
ping -f 192.168.7.1 &

# Terminal 3: Run cyclictest
sudo cyclictest -l100000 -m -Sp99 -i200 -h400 -q > results.txt
```

**Analyze results:**

```bash
# View results
cat results.txt

# Extract key metrics
grep "Max Latencies" results.txt
grep "Avg Latencies" results.txt
```

---

## Expected Results

| Metric | Standard Kernel | PREEMPT_RT |
|--------|-----------------|------------|
| Avg latency | 20-100 µs | 5-30 µs |
| Max latency (no load) | 100-500 µs | 30-80 µs |
| Max latency (stress) | 500-5000 µs | 50-150 µs |

---

## RT Application Best Practices

### Set Real-Time Priority

```c
#include <sched.h>
#include <sys/mlock.h>

int main(void)
{
    struct sched_param param;
    
    /* Lock memory to prevent page faults */
    mlockall(MCL_CURRENT | MCL_FUTURE);
    
    /* Set SCHED_FIFO with priority 80 */
    param.sched_priority = 80;
    if (sched_setscheduler(0, SCHED_FIFO, &param) == -1) {
        perror("sched_setscheduler");
        return 1;
    }
    
    /* Your RT code here */
    
    return 0;
}
```

### CPU Isolation

```bash
# Bootargs: isolate CPU 0 for RT tasks
isolcpus=0 nohz_full=0 rcu_nocbs=0

# Pin RT process to isolated CPU
taskset -c 0 ./rt_application
```

### Avoid Priority Inversion

```c
/* Use priority inheritance mutex */
pthread_mutexattr_t attr;
pthread_mutex_t mutex;

pthread_mutexattr_init(&attr);
pthread_mutexattr_setprotocol(&attr, PTHREAD_PRIO_INHERIT);
pthread_mutex_init(&mutex, &attr);
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| High latency spikes | CPU frequency scaling | Disable cpufreq or set performance governor |
| Kernel doesn't boot | Aggressive RT config | Start with less aggressive options |
| cyclictest permission denied | Not root | Run with sudo |
| Inconsistent results | Background processes | Use CPU isolation |

### Debug High Latency

```bash
# Enable function tracer
echo function_graph > /sys/kernel/debug/tracing/current_tracer
echo 1 > /sys/kernel/debug/tracing/tracing_on
# Run workload
cat /sys/kernel/debug/tracing/trace

# Or use trace-cmd
trace-cmd record -e sched_switch cyclictest -l1000 -m -Sp99 -i200
trace-cmd report
```

---

## Performance Governor Setup

```bash
# Check available governors
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors

# Set performance governor
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Or in bootargs:
cpufreq.default_governor=performance
```

---

## Verification Checklist

- [ ] RT patch applied successfully
- [ ] CONFIG_PREEMPT_RT=y in .config
- [ ] RT kernel boots on BBB
- [ ] `uname -a` shows -rt in version
- [ ] cyclictest runs without errors
- [ ] Max latency under stress < 200µs
- [ ] Application runs with RT priority

---

# Part 3: Application Development

## RT Application Development

### Complete Real-Time Application Template

```c
/*
 * rt_application.c - Complete RT application template for BeagleBone Black
 * 
 * Compile: arm-linux-gnueabihf-gcc -o rt_app rt_application.c -lpthread -lrt
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sched.h>
#include <pthread.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <signal.h>

/* Configuration */
#define RT_PRIORITY     80          /* 1-99, higher = more priority */
#define PERIOD_NS       1000000     /* 1ms period */
#define STACK_SIZE      (512*1024)  /* 512KB pre-allocated stack */

/* Statistics */
struct latency_stats {
    long min_ns;
    long max_ns;
    long long sum_ns;
    long count;
    long histogram[1000];  /* 0-999µs buckets */
};

static volatile int running = 1;
static struct latency_stats stats = {
    .min_ns = LONG_MAX,
    .max_ns = 0,
    .sum_ns = 0,
    .count = 0
};

/* Signal handler for graceful shutdown */
void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

/* Add nanoseconds to timespec, handling overflow */
static inline void timespec_add_ns(struct timespec *ts, long ns)
{
    ts->tv_nsec += ns;
    while (ts->tv_nsec >= 1000000000L) {
        ts->tv_nsec -= 1000000000L;
        ts->tv_sec++;
    }
}

/* Calculate difference in nanoseconds */
static inline long timespec_diff_ns(struct timespec *start, struct timespec *end)
{
    return (end->tv_sec - start->tv_sec) * 1000000000L +
           (end->tv_nsec - start->tv_nsec);
}

/* Update latency statistics */
static void update_stats(long latency_ns)
{
    if (latency_ns < stats.min_ns) stats.min_ns = latency_ns;
    if (latency_ns > stats.max_ns) stats.max_ns = latency_ns;
    stats.sum_ns += latency_ns;
    stats.count++;
    
    /* Histogram: 1µs buckets, capped at 999µs */
    int bucket = latency_ns / 1000;
    if (bucket > 999) bucket = 999;
    stats.histogram[bucket]++;
}

/* Print final statistics */
static void print_stats(void)
{
    printf("\n=== Latency Statistics ===\n");
    printf("Samples: %ld\n", stats.count);
    printf("Min: %ld ns (%.2f µs)\n", stats.min_ns, stats.min_ns/1000.0);
    printf("Max: %ld ns (%.2f µs)\n", stats.max_ns, stats.max_ns/1000.0);
    printf("Avg: %.2f ns (%.2f µs)\n", 
           (double)stats.sum_ns/stats.count,
           (double)stats.sum_ns/stats.count/1000.0);
    
    /* Print histogram for latencies > 50µs */
    printf("\nLatency histogram (>50µs):\n");
    for (int i = 50; i < 1000; i++) {
        if (stats.histogram[i] > 0) {
            printf("  %3d-%3dµs: %ld\n", i, i+1, stats.histogram[i]);
        }
    }
}

/* Configure RT scheduling */
static int setup_rt_scheduling(void)
{
    struct sched_param param;
    
    /* Set SCHED_FIFO with specified priority */
    param.sched_priority = RT_PRIORITY;
    if (sched_setscheduler(0, SCHED_FIFO, &param) == -1) {
        perror("sched_setscheduler failed");
        if (errno == EPERM) {
            fprintf(stderr, "Run as root or with CAP_SYS_NICE\n");
        }
        return -1;
    }
    
    printf("RT scheduling enabled: SCHED_FIFO priority %d\n", RT_PRIORITY);
    return 0;
}

/* Lock all memory to prevent page faults */
static int lock_memory(void)
{
    /* Lock all current and future memory */
    if (mlockall(MCL_CURRENT | MCL_FUTURE) == -1) {
        perror("mlockall failed");
        return -1;
    }
    
    /* Pre-fault the stack */
    unsigned char dummy[STACK_SIZE];
    memset(dummy, 0, STACK_SIZE);
    
    printf("Memory locked and pre-faulted\n");
    return 0;
}

/* Set CPU affinity */
static int set_cpu_affinity(int cpu)
{
    cpu_set_t cpuset;
    
    CPU_ZERO(&cpuset);
    CPU_SET(cpu, &cpuset);
    
    if (sched_setaffinity(0, sizeof(cpuset), &cpuset) == -1) {
        perror("sched_setaffinity failed");
        return -1;
    }
    
    printf("Pinned to CPU %d\n", cpu);
    return 0;
}

/* Your RT work function - called every period */
static void do_rt_work(void)
{
    /* 
     * This is where your real-time code goes.
     * Examples:
     * - Read sensor via GPIO/I2C/SPI
     * - Calculate control output (PID)
     * - Write actuator command
     * - Log data
     */
    
    /* Simulate some work (~10µs) */
    volatile int x = 0;
    for (int i = 0; i < 1000; i++) x += i;
    (void)x;
}

/* Main RT loop */
static void rt_loop(void)
{
    struct timespec next_period;
    struct timespec before, after;
    
    /* Get current time as starting point */
    clock_gettime(CLOCK_MONOTONIC, &next_period);
    
    printf("Starting RT loop with %d ns period\n", PERIOD_NS);
    
    while (running) {
        /* Calculate next period */
        timespec_add_ns(&next_period, PERIOD_NS);
        
        /* Wait until next period (high-resolution sleep) */
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next_period, NULL);
        
        /* Measure wake-up latency */
        clock_gettime(CLOCK_MONOTONIC, &before);
        long wakeup_latency = timespec_diff_ns(&next_period, &before);
        update_stats(wakeup_latency);
        
        /* Do the actual work */
        do_rt_work();
        
        /* Optional: measure work completion time */
        clock_gettime(CLOCK_MONOTONIC, &after);
        long work_time = timespec_diff_ns(&before, &after);
        
        /* Check for deadline miss */
        if (wakeup_latency + work_time > PERIOD_NS) {
            printf("WARNING: Deadline miss! Latency=%ld + Work=%ld > Period=%d\n",
                   wakeup_latency, work_time, PERIOD_NS);
        }
    }
}

int main(int argc, char *argv[])
{
    printf("BeagleBone Black RT Application\n");
    printf("================================\n\n");
    
    /* Check for root */
    if (geteuid() != 0) {
        fprintf(stderr, "WARNING: Not running as root, RT features may fail\n");
    }
    
    /* Set up signal handlers */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    /* Initialize RT environment */
    if (lock_memory() != 0) {
        fprintf(stderr, "Failed to lock memory\n");
        return 1;
    }
    
    if (set_cpu_affinity(0) != 0) {
        fprintf(stderr, "Failed to set CPU affinity\n");
        return 1;
    }
    
    if (setup_rt_scheduling() != 0) {
        fprintf(stderr, "Failed to set RT scheduling\n");
        return 1;
    }
    
    /* Run the RT loop */
    rt_loop();
    
    /* Print statistics on exit */
    print_stats();
    
    return 0;
}
```

### Building and Running

```bash
# Cross-compile on host
arm-linux-gnueabihf-gcc -O2 -o rt_app rt_application.c -lpthread -lrt

# Copy to BBB
scp rt_app debian@192.168.7.2:/home/debian/

# On BBB, run as root
sudo ./rt_app

# Let it run for a while, then Ctrl+C to see statistics
```

### Multi-Threaded RT Application

```c
/*
 * multi_rt_app.c - Multi-threaded RT application
 * 
 * Thread priorities:
 *   High-priority: Motor control (1kHz)
 *   Medium-priority: Sensor reading (100Hz)
 *   Low-priority: Logging (10Hz)
 */

#include <pthread.h>
#include <sched.h>
#include <sys/mman.h>

/* Thread configuration */
struct thread_config {
    const char *name;
    int priority;
    long period_ns;
    void (*work_func)(void);
};

/* Work functions */
void motor_control_work(void) {
    /* 1kHz motor control loop */
    /* Read encoder, calculate PID, output PWM */
}

void sensor_read_work(void) {
    /* 100Hz sensor reading */
    /* Read I2C sensors, filter data */
}

void logging_work(void) {
    /* 10Hz data logging */
    /* Write to buffer/file */
}

struct thread_config threads[] = {
    { "motor",  90, 1000000,   motor_control_work },   /* 1ms */
    { "sensor", 80, 10000000,  sensor_read_work },     /* 10ms */
    { "logger", 70, 100000000, logging_work },         /* 100ms */
    { NULL, 0, 0, NULL }
};

void *rt_thread(void *arg)
{
    struct thread_config *cfg = (struct thread_config *)arg;
    struct sched_param param;
    struct timespec next;
    
    /* Set thread priority */
    param.sched_priority = cfg->priority;
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &param);
    
    clock_gettime(CLOCK_MONOTONIC, &next);
    
    while (running) {
        timespec_add_ns(&next, cfg->period_ns);
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL);
        cfg->work_func();
    }
    
    return NULL;
}

int main(void)
{
    pthread_t thread_ids[10];
    pthread_attr_t attr;
    
    mlockall(MCL_CURRENT | MCL_FUTURE);
    
    pthread_attr_init(&attr);
    pthread_attr_setschedpolicy(&attr, SCHED_FIFO);
    pthread_attr_setinheritsched(&attr, PTHREAD_EXPLICIT_SCHED);
    
    for (int i = 0; threads[i].name != NULL; i++) {
        struct sched_param param = { .sched_priority = threads[i].priority };
        pthread_attr_setschedparam(&attr, &param);
        pthread_create(&thread_ids[i], &attr, rt_thread, &threads[i]);
    }
    
    /* Wait for threads */
    for (int i = 0; threads[i].name != NULL; i++) {
        pthread_join(thread_ids[i], NULL);
    }
    
    return 0;
}
```

### Using POSIX Timers for Periodic Tasks

```c
#include <signal.h>
#include <time.h>

static volatile int timer_fired = 0;

void timer_handler(int sig, siginfo_t *si, void *uc)
{
    (void)sig; (void)si; (void)uc;
    timer_fired = 1;
}

int setup_periodic_timer(long period_ns)
{
    struct sigevent sev;
    struct itimerspec its;
    timer_t timerid;
    struct sigaction sa;
    
    /* Set up signal handler */
    sa.sa_flags = SA_SIGINFO;
    sa.sa_sigaction = timer_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGRTMIN, &sa, NULL);
    
    /* Create timer */
    sev.sigev_notify = SIGEV_SIGNAL;
    sev.sigev_signo = SIGRTMIN;
    sev.sigev_value.sival_ptr = &timerid;
    timer_create(CLOCK_MONOTONIC, &sev, &timerid);
    
    /* Start periodic timer */
    its.it_value.tv_sec = 0;
    its.it_value.tv_nsec = period_ns;
    its.it_interval.tv_sec = 0;
    its.it_interval.tv_nsec = period_ns;
    timer_settime(timerid, 0, &its, NULL);
    
    return 0;
}

/* In main loop */
while (running) {
    /* Wait for timer signal */
    while (!timer_fired) {
        pause();  /* Sleep until signal */
    }
    timer_fired = 0;
    
    do_rt_work();
}
```

---

# Part 4: Advanced Topics

## Advanced System Tuning

### IRQ Thread Priority Management

```bash
#!/bin/bash
# set_irq_priorities.sh - Configure IRQ thread priorities for BBB

# View current IRQ thread priorities
ps -eo pid,ni,pri,comm | grep irq/

# Set priorities for critical IRQs
# Higher number = higher priority (1-99)

# Network IRQ - medium priority (don't starve the network)
IRQ_ETH=$(pgrep -f "irq/.*-eth")
[ -n "$IRQ_ETH" ] && chrt -f -p 50 $IRQ_ETH

# GPIO IRQ - high priority (for sensors/encoders)
IRQ_GPIO=$(pgrep -f "irq/.*-gpio")
[ -n "$IRQ_GPIO" ] && chrt -f -p 85 $IRQ_GPIO

# Timer IRQ - highest priority
IRQ_TIMER=$(pgrep -f "irq/.*-timer")
[ -n "$IRQ_TIMER" ] && chrt -f -p 95 $IRQ_TIMER

# MMC IRQ - low priority (SD card can wait)
IRQ_MMC=$(pgrep -f "irq/.*-mmc")
[ -n "$IRQ_MMC" ] && chrt -f -p 40 $IRQ_MMC

echo "IRQ priorities configured"
ps -eo pid,ni,pri,comm | grep irq/ | sort -k3 -n
```

### Kernel Command Line Options

```bash
# Complete RT bootargs for BBB
setenv bootargs 'console=ttyO0,115200n8 root=/dev/mmcblk0p2 rootwait \
    isolcpus=0 \
    nohz_full=0 \
    rcu_nocbs=0 \
    rcu_nocb_poll \
    nosoftlockup \
    nowatchdog \
    cpufreq.default_governor=performance \
    processor.max_cstate=1 \
    idle=poll \
    intel_idle.max_cstate=0 \
    nmi_watchdog=0 \
    skew_tick=1 \
    clocksource=tsc \
    tsc=reliable'
```

**Explanation of each option:**

| Option | Purpose |
|--------|---------|
| `isolcpus=0` | Isolate CPU 0 from scheduler (dedicated for RT) |
| `nohz_full=0` | Disable timer ticks on CPU 0 when busy |
| `rcu_nocbs=0` | Move RCU callbacks off CPU 0 |
| `rcu_nocb_poll` | Poll RCU instead of interrupt |
| `nosoftlockup` | Disable soft lockup detector |
| `nowatchdog` | Disable watchdog (can cause latency spikes) |
| `processor.max_cstate=1` | Limit CPU power states (faster wake-up) |
| `idle=poll` | Don't enter deep sleep (trading power for latency) |
| `skew_tick=1` | Randomize timer ticks to reduce lock contention |

### Sysctl Settings for RT

```bash
# /etc/sysctl.d/99-realtime.conf

# Disable kernel printk to console (can cause latency)
kernel.printk = 0 4 1 7

# RT throttling - allow RT tasks to use 100% CPU
kernel.sched_rt_runtime_us = -1
# Or limit to 95%: kernel.sched_rt_runtime_us = 950000

# Reduce vmstat updates
vm.stat_interval = 10

# Disable transparent hugepages (can cause latency spikes)
# (Do this differently, via kernel cmdline: transparent_hugepage=never)

# Network settings to reduce latency
net.core.busy_poll = 50
net.core.busy_read = 50
```

### CPU Frequency and Power Management

```bash
# Set performance governor
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "performance" > $cpu
done

# Verify frequency is locked at maximum
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq

# Disable CPU idle states for minimum latency
for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
    echo 1 > $cpu
done

# AM335x specific: Disable SmartReflex (voltage scaling)
# This may require kernel config changes
```

---

## Debugging and Profiling

### Ftrace for Latency Analysis

```bash
# Enable function tracing on BBB
mount -t tracefs nodev /sys/kernel/tracing
cd /sys/kernel/tracing

# Trace function execution time
echo function_graph > current_tracer
echo 1 > tracing_on

# Run your RT application for a short time
sleep 5

echo 0 > tracing_on
cat trace > /tmp/ftrace.log
```

### Cyclictest Deep Dive

```bash
# Basic test
cyclictest -l10000 -m -Sp99 -i200 -h400 -q

# Options explained:
# -l10000     : 10000 loops
# -m          : Lock memory (mlockall)
# -S          : Standard mode (SMP mode on multi-core)
# -p99        : Priority 99 (highest RT priority)
# -i200       : 200µs interval between wake-ups
# -h400       : Histogram with 400µs max
# -q          : Quiet (only final stats)

# More detailed test with all options
cyclictest \
    --loops=100000 \
    --mlockall \
    --priority=99 \
    --policy=fifo \
    --interval=200 \
    --distance=0 \
    --histogram=1000 \
    --histofall=1000 \
    --quiet \
    --affinity=0 \
    --breaktrace=100 \
    2>&1 | tee cyclictest_results.txt

# With breaktrace: stop and dump trace if latency > 100µs
```

### Using trace-cmd

```bash
# Record scheduling events during cyclictest
trace-cmd record -e sched_switch -e sched_wakeup \
    cyclictest -l1000 -m -Sp99 -i200 -q

# Generate report
trace-cmd report > trace_report.txt

# Visualize with KernelShark (on desktop Linux)
# scp trace.dat to your desktop
# kernelshark trace.dat
```

### hwlatdetect for Hardware Latency

```bash
# Detect SMI (System Management Interrupt) and other HW latency
hwlatdetect --duration=60 --threshold=10 --hardlimit=100

# This detects latency caused by:
# - SMI (BIOS handlers)
# - CPU frequency transitions
# - Hardware bugs
# - Firmware issues
```

### Custom Latency Measurement

```c
/* Measure latency in your own code */
#include <time.h>
#include <stdio.h>

struct latency_point {
    const char *name;
    struct timespec ts;
};

#define MAX_POINTS 10
static struct latency_point points[MAX_POINTS];
static int point_count = 0;

static inline void mark_latency(const char *name)
{
    if (point_count < MAX_POINTS) {
        points[point_count].name = name;
        clock_gettime(CLOCK_MONOTONIC, &points[point_count].ts);
        point_count++;
    }
}

static void print_latency_report(void)
{
    printf("Latency Report:\n");
    for (int i = 1; i < point_count; i++) {
        long diff = (points[i].ts.tv_sec - points[i-1].ts.tv_sec) * 1000000000L +
                    (points[i].ts.tv_nsec - points[i-1].ts.tv_nsec);
        printf("  %s -> %s: %ld ns\n", 
               points[i-1].name, points[i].name, diff);
    }
    point_count = 0;
}

/* Usage */
void my_rt_function(void)
{
    mark_latency("start");
    
    read_sensor();
    mark_latency("after_sensor");
    
    calculate_pid();
    mark_latency("after_pid");
    
    write_output();
    mark_latency("end");
    
    print_latency_report();
}
```

---

## Real-World Use Cases

### Case 1: Motor Control (BBB + PRU)

```
┌─────────────────────────────────────────────────────────────┐
│              MOTOR CONTROL SYSTEM                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌───────────────────────────────────────────────────┐     │
│  │                  BeagleBone Black                 │     │
│  │  ┌───────────────────────────────────────────┐   │     │
│  │  │         ARM Cortex-A8 (PREEMPT_RT)        │   │     │
│  │  │                                           │   │     │
│  │  │  ┌─────────────────────────────────────┐  │   │     │
│  │  │  │  RT Control Loop (1kHz)              │  │   │     │
│  │  │  │  - Position/Velocity calculation    │  │   │     │
│  │  │  │  - PID control                      │  │   │     │
│  │  │  │  - Trajectory generation            │  │   │     │
│  │  │  └─────────────────────────────────────┘  │   │     │
│  │  │            ↓ Shared Memory                 │   │     │
│  │  └───────────────────────────────────────────┘   │     │
│  │                                                   │     │
│  │  ┌───────────────────────────────────────────┐   │     │
│  │  │          PRU (200MHz, deterministic)      │   │     │
│  │  │  - Encoder reading (1-10µs precision)    │   │     │
│  │  │  - PWM generation (variable frequency)   │   │     │
│  │  │  - Commutation timing                    │   │     │
│  │  └───────────────────────────────────────────┘   │     │
│  │                                                   │     │
│  └───────────────────────────────────────────────────┘     │
│                                                             │
│  Latency Budget:                                            │
│  - Encoder → PRU: 1µs (PRU handles this)                   │
│  - PRU → ARM notification: 10µs                            │
│  - ARM RT loop processing: 100µs                           │
│  - ARM → PRU command: 10µs                                 │
│  - PRU → PWM output: 1µs                                   │
│  Total: < 150µs ✓                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Case 2: Data Acquisition System

```c
/*
 * High-speed data acquisition with PREEMPT_RT
 * Samples ADC at 10kHz, stores to ring buffer
 */

#define SAMPLE_RATE_HZ  10000
#define PERIOD_NS       (1000000000 / SAMPLE_RATE_HZ)  /* 100µs */
#define BUFFER_SIZE     (SAMPLE_RATE_HZ * 60)  /* 1 minute buffer */

struct sample {
    uint64_t timestamp_ns;
    int16_t  channels[8];
};

struct ring_buffer {
    struct sample samples[BUFFER_SIZE];
    volatile int write_idx;
    volatile int read_idx;
};

void *acquisition_thread(void *arg)
{
    struct ring_buffer *rb = (struct ring_buffer *)arg;
    struct timespec next;
    
    setup_rt_priority(95);  /* High priority for acquisition */
    mlockall(MCL_CURRENT | MCL_FUTURE);
    
    clock_gettime(CLOCK_MONOTONIC, &next);
    
    while (running) {
        timespec_add_ns(&next, PERIOD_NS);
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL);
        
        /* Read ADC (via SPI or I2C) */
        struct sample *s = &rb->samples[rb->write_idx];
        clock_gettime(CLOCK_MONOTONIC, (struct timespec *)&s->timestamp_ns);
        read_adc_channels(s->channels);
        
        rb->write_idx = (rb->write_idx + 1) % BUFFER_SIZE;
    }
    
    return NULL;
}

void *storage_thread(void *arg)
{
    struct ring_buffer *rb = (struct ring_buffer *)arg;
    FILE *fp;
    
    setup_rt_priority(50);  /* Lower priority for storage */
    
    fp = fopen("/data/acquisition.bin", "wb");
    
    while (running || rb->read_idx != rb->write_idx) {
        if (rb->read_idx != rb->write_idx) {
            fwrite(&rb->samples[rb->read_idx], sizeof(struct sample), 1, fp);
            rb->read_idx = (rb->read_idx + 1) % BUFFER_SIZE;
        } else {
            usleep(1000);  /* Sleep 1ms if buffer empty */
        }
    }
    
    fclose(fp);
    return NULL;
}
```

### Case 3: CAN Bus Communication

```c
/*
 * Real-time CAN communication on BeagleBone Black
 * Requires: can-utils, SocketCAN
 */

#include <linux/can.h>
#include <linux/can/raw.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>

#define CAN_INTERFACE "can0"

int setup_can_socket(void)
{
    int sock;
    struct ifreq ifr;
    struct sockaddr_can addr;
    
    sock = socket(PF_CAN, SOCK_RAW, CAN_RAW);
    if (sock < 0) return -1;
    
    strcpy(ifr.ifr_name, CAN_INTERFACE);
    ioctl(sock, SIOCGIFINDEX, &ifr);
    
    addr.can_family = AF_CAN;
    addr.can_ifindex = ifr.ifr_ifindex;
    bind(sock, (struct sockaddr *)&addr, sizeof(addr));
    
    /* Set socket to non-blocking for RT use */
    int flags = fcntl(sock, F_GETFL, 0);
    fcntl(sock, F_SETFL, flags | O_NONBLOCK);
    
    return sock;
}

void *can_rx_thread(void *arg)
{
    int sock = *(int *)arg;
    struct can_frame frame;
    struct timespec deadline;
    
    setup_rt_priority(85);
    
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    
    while (running) {
        timespec_add_ns(&deadline, 1000000);  /* 1ms period */
        
        /* Try to receive CAN frame */
        int nbytes = read(sock, &frame, sizeof(frame));
        if (nbytes > 0) {
            process_can_frame(&frame);
        }
        
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &deadline, NULL);
    }
    
    return NULL;
}
```

---

## Alternatives to PREEMPT_RT

### Comparison of Real-Time Approaches

```
┌─────────────────────────────────────────────────────────────┐
│           REAL-TIME LINUX APPROACHES                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  PREEMPT_RT                                                 │
│  ══════════                                                 │
│  ✓ Full Linux API available                                │
│  ✓ Single kernel image                                      │
│  ✓ Well-maintained (part of mainline now)                  │
│  ✗ Soft real-time (100µs typical worst-case)               │
│  ✗ Not suitable for < 50µs requirements                    │
│  Use case: Motor control, data acquisition, CNC             │
│                                                             │
│  XENOMAI / COBALT                                           │
│  ════════════════                                           │
│  ✓ Hard real-time (< 10µs worst-case)                      │
│  ✓ Dual-kernel architecture                                │
│  ✗ Separate RT API (not POSIX)                             │
│  ✗ More complex setup                                       │
│  ✗ Kernel compatibility issues                              │
│  Use case: Industrial automation, robotics                  │
│                                                             │
│  RTEMS / VxWorks / QNX                                      │
│  ══════════════════════                                     │
│  ✓ True RTOS, deterministic                                │
│  ✓ Very low latency (< 5µs)                                │
│  ✗ Not Linux                                                │
│  ✗ Different toolchain, ecosystem                          │
│  ✗ Commercial licensing (mostly)                           │
│  Use case: Aerospace, medical devices, hard RT              │
│                                                             │
│  PRU (BeagleBone Specific)                                  │
│  ═════════════════════════                                  │
│  ✓ Deterministic (5ns resolution)                          │
│  ✓ Runs alongside Linux                                     │
│  ✗ Limited resources (8KB RAM)                             │
│  ✗ Separate programming model                              │
│  ✗ BeagleBone only                                         │
│  Use case: PWM, encoder, timing-critical I/O                │
│                                                             │
│  BARE METAL                                                 │
│  ══════════                                                 │
│  ✓ Complete control                                         │
│  ✓ Lowest possible latency                                 │
│  ✗ No OS features                                          │
│  ✗ Must write everything yourself                          │
│  Use case: Simple, ultra-low-latency applications          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### When to Use What

| Requirement | Solution |
|-------------|----------|
| Latency < 100µs, Linux ecosystem | PREEMPT_RT |
| Latency < 10µs, need Linux | Xenomai |
| Latency < 5µs, BBB platform | PRU |
| Latency < 1µs, any platform | Bare metal / RTOS |
| Commercial / certified | VxWorks / QNX |

---

## Summary and Best Practices

### PREEMPT_RT Checklist

```
┌─────────────────────────────────────────────────────────────┐
│              PREEMPT_RT BEST PRACTICES                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  KERNEL CONFIGURATION                                       │
│  ☐ CONFIG_PREEMPT_RT=y                                     │
│  ☐ CONFIG_HIGH_RES_TIMERS=y                                │
│  ☐ CONFIG_NO_HZ_FULL=y (for isolated CPUs)                 │
│  ☐ Disable debug options for production                    │
│                                                             │
│  SYSTEM CONFIGURATION                                       │
│  ☐ Isolate CPU for RT tasks (isolcpus=)                    │
│  ☐ Disable CPU frequency scaling                           │
│  ☐ Disable CPU idle states                                 │
│  ☐ Set appropriate IRQ thread priorities                   │
│  ☐ Disable unnecessary services                            │
│                                                             │
│  APPLICATION DESIGN                                         │
│  ☐ Use mlockall(MCL_CURRENT | MCL_FUTURE)                  │
│  ☐ Pre-allocate all memory                                 │
│  ☐ Use clock_nanosleep() with CLOCK_MONOTONIC              │
│  ☐ Set SCHED_FIFO or SCHED_RR policy                       │
│  ☐ Use priority inheritance mutexes                        │
│  ☐ Avoid dynamic memory allocation in RT path              │
│  ☐ Avoid file I/O in RT path                               │
│  ☐ Avoid printf/logging in RT path                         │
│                                                             │
│  TESTING                                                    │
│  ☐ Run cyclictest under stress                             │
│  ☐ Test for at least 24 hours                              │
│  ☐ Document worst-case latency                             │
│  ☐ Test all failure modes                                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### What to Avoid in RT Code

```c
/* NEVER DO THESE IN RT PATH */

// ❌ Dynamic memory allocation
void *ptr = malloc(size);  /* Can trigger page fault! */

// ❌ File I/O
FILE *f = fopen("file", "r");  /* Disk I/O is unbounded! */
printf("debug\n");             /* stdout is file I/O! */

// ❌ Network I/O
send(sock, data, len, 0);  /* Network latency is huge */

// ❌ System calls that may block indefinitely
sleep(1);  /* Use clock_nanosleep with absolute time instead */
mutex_lock(&lock);  /* If lock held by lower priority = inversion */

// ❌ Calling non-RT-safe library functions
/* Many libc functions allocate memory internally */


/* DO THESE INSTEAD */

// ✓ Pre-allocate all memory before RT loop
void *buffer = malloc(size);
mlockall(MCL_CURRENT | MCL_FUTURE);
/* ... then enter RT loop ... */

// ✓ Use lock-free data structures
atomic_store(&shared_var, value);

// ✓ Use bounded wait with timeout
pthread_mutex_timedlock(&mutex, &timeout);

// ✓ Log to ring buffer, let non-RT thread write to disk
log_to_ringbuffer(message);
```

---

## Verification Checklist

- [ ] RT patch applied successfully
- [ ] CONFIG_PREEMPT_RT=y in .config
- [ ] RT kernel boots on BBB
- [ ] `uname -a` shows -rt in version
- [ ] cyclictest runs without errors
- [ ] Max latency under stress < 200µs
- [ ] Application runs with RT priority
- [ ] IRQ thread priorities configured
- [ ] CPU isolation working (if used)
- [ ] Memory locked with mlockall()
- [ ] 24-hour stress test passed

---

[← Previous: A/B Partition](04_ab_partition.md) | [Back to Index](README.md) | [Next: Secure Boot →](06_secure_boot.md)
