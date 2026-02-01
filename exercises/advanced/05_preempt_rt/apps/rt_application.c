/*
 * rt_application.c - Complete RT application template for BeagleBone Black
 * 
 * A fully-featured real-time application demonstrating:
 * - SCHED_FIFO real-time scheduling
 * - Memory locking (mlockall)
 * - Stack pre-faulting
 * - CPU affinity
 * - Periodic execution with clock_nanosleep
 * - Latency statistics collection
 * - Signal handling for graceful shutdown
 * 
 * Compile:
 *   arm-linux-gnueabihf-gcc -O2 -o rt_app rt_application.c -lpthread -lrt
 * 
 * Run on BBB:
 *   sudo ./rt_app
 * 
 * Author: Embedded Linux Labs
 * License: MIT
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

/* ==========================================================================
 * CONFIGURATION
 * ========================================================================== */

#define RT_PRIORITY     80          /* 1-99, higher = more priority */
#define PERIOD_NS       1000000     /* 1ms period (1000Hz) */
#define STACK_SIZE      (512*1024)  /* 512KB pre-allocated stack */
#define CPU_AFFINITY    0           /* Pin to CPU 0 (set -1 to disable) */

/* ==========================================================================
 * LATENCY STATISTICS
 * ========================================================================== */

struct latency_stats {
    long min_ns;
    long max_ns;
    long total_ns;
    long count;
    long histogram[100];  /* 0-99 microseconds */
};

static struct latency_stats stats = {
    .min_ns = LONG_MAX,
    .max_ns = 0,
    .total_ns = 0,
    .count = 0,
};

static volatile sig_atomic_t running = 1;

/* ==========================================================================
 * TIME UTILITIES
 * ========================================================================== */

static inline void timespec_add_ns(struct timespec *ts, long ns)
{
    ts->tv_nsec += ns;
    while (ts->tv_nsec >= 1000000000L) {
        ts->tv_nsec -= 1000000000L;
        ts->tv_sec++;
    }
}

static inline long timespec_diff_ns(struct timespec *a, struct timespec *b)
{
    return (a->tv_sec - b->tv_sec) * 1000000000L + (a->tv_nsec - b->tv_nsec);
}

/* ==========================================================================
 * STATISTICS
 * ========================================================================== */

static void update_stats(long latency_ns)
{
    if (latency_ns < stats.min_ns) stats.min_ns = latency_ns;
    if (latency_ns > stats.max_ns) stats.max_ns = latency_ns;
    stats.total_ns += latency_ns;
    stats.count++;
    
    /* Update histogram (in microseconds) */
    long us = latency_ns / 1000;
    if (us < 100) {
        stats.histogram[us]++;
    }
}

static void print_stats(void)
{
    printf("\n========================================\n");
    printf("  LATENCY STATISTICS\n");
    printf("========================================\n");
    printf("Iterations: %ld\n", stats.count);
    printf("Min latency: %ld ns (%.2f µs)\n", stats.min_ns, stats.min_ns / 1000.0);
    printf("Max latency: %ld ns (%.2f µs)\n", stats.max_ns, stats.max_ns / 1000.0);
    printf("Avg latency: %.2f ns (%.2f µs)\n", 
           (double)stats.total_ns / stats.count,
           (double)stats.total_ns / stats.count / 1000.0);
    printf("\nHistogram (microseconds):\n");
    for (int i = 0; i < 100; i++) {
        if (stats.histogram[i] > 0) {
            printf("  %3d µs: %ld\n", i, stats.histogram[i]);
        }
    }
    printf("========================================\n");
}

/* ==========================================================================
 * SIGNAL HANDLER
 * ========================================================================== */

static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

static void setup_signals(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
}

/* ==========================================================================
 * STACK PRE-FAULTING
 * ========================================================================== */

static void prefault_stack(void)
{
    /* Pre-fault the stack by touching each page */
    volatile char buffer[STACK_SIZE];
    memset((void*)buffer, 0, sizeof(buffer));
}

/* ==========================================================================
 * RT SETUP
 * ========================================================================== */

static int setup_rt(void)
{
    struct sched_param param;
    cpu_set_t cpuset;
    
    /* Step 1: Lock all memory */
    if (mlockall(MCL_CURRENT | MCL_FUTURE) == -1) {
        perror("mlockall failed");
        /* Continue anyway - may work without it */
    }
    
    /* Step 2: Pre-fault the stack */
    prefault_stack();
    
    /* Step 3: Set CPU affinity (if configured) */
    if (CPU_AFFINITY >= 0) {
        CPU_ZERO(&cpuset);
        CPU_SET(CPU_AFFINITY, &cpuset);
        if (sched_setaffinity(0, sizeof(cpuset), &cpuset) == -1) {
            perror("sched_setaffinity failed");
        } else {
            printf("Pinned to CPU %d\n", CPU_AFFINITY);
        }
    }
    
    /* Step 4: Set SCHED_FIFO scheduling */
    param.sched_priority = RT_PRIORITY;
    if (sched_setscheduler(0, SCHED_FIFO, &param) == -1) {
        perror("sched_setscheduler failed");
        fprintf(stderr, "Run as root or set CAP_SYS_NICE\n");
        return -1;
    }
    
    printf("RT scheduling enabled: SCHED_FIFO, priority %d\n", RT_PRIORITY);
    return 0;
}

/* ==========================================================================
 * WORK FUNCTION
 * ========================================================================== */

/*
 * This is where you put your actual real-time work.
 * Keep it short and deterministic!
 */
static void do_rt_work(void)
{
    /* Example: Toggle GPIO, read sensor, compute PID, etc. */
    /* 
     * IMPORTANT RULES:
     * 1. No dynamic memory allocation (malloc/free)
     * 2. No blocking I/O
     * 3. No system calls that may block
     * 4. Minimize memory access (use registers/cache)
     * 5. Bound all loops
     */
    
    /* Simulated work: busy-wait for ~10µs */
    volatile int i;
    for (i = 0; i < 1000; i++) {
        /* Compiler barrier to prevent optimization */
        asm volatile("" ::: "memory");
    }
}

/* ==========================================================================
 * MAIN RT LOOP
 * ========================================================================== */

static void rt_loop(void)
{
    struct timespec next, now, expected;
    long latency;
    
    printf("Starting RT loop with period %d µs (%.1f Hz)\n", 
           PERIOD_NS / 1000, 1e9 / PERIOD_NS);
    printf("Press Ctrl+C to stop and show statistics\n\n");
    
    /* Get initial time */
    clock_gettime(CLOCK_MONOTONIC, &next);
    
    while (running) {
        /* Calculate next wakeup time */
        timespec_add_ns(&next, PERIOD_NS);
        expected = next;
        
        /* Sleep until next period */
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL);
        
        /* Measure wakeup latency */
        clock_gettime(CLOCK_MONOTONIC, &now);
        latency = timespec_diff_ns(&now, &expected);
        
        /* Update statistics (only positive latency) */
        if (latency > 0) {
            update_stats(latency);
        }
        
        /* Do the actual work */
        do_rt_work();
        
        /* Print periodic progress */
        if (stats.count % 10000 == 0) {
            printf("Iterations: %8ld  Current latency: %6ld ns  Max: %6ld ns\r",
                   stats.count, latency, stats.max_ns);
            fflush(stdout);
        }
    }
}

/* ==========================================================================
 * MAIN
 * ========================================================================== */

int main(int argc, char *argv[])
{
    printf("\n");
    printf("========================================\n");
    printf("  RT APPLICATION - BeagleBone Black\n");
    printf("========================================\n\n");
    
    (void)argc;
    (void)argv;
    
    /* Check if running as root */
    if (geteuid() != 0) {
        fprintf(stderr, "Warning: Not running as root\n");
        fprintf(stderr, "RT scheduling may fail without elevated privileges\n\n");
    }
    
    /* Setup signal handlers */
    setup_signals();
    
    /* Configure RT scheduling */
    if (setup_rt() != 0) {
        fprintf(stderr, "Failed to setup RT, running in normal mode\n");
    }
    
    /* Run the RT loop */
    rt_loop();
    
    /* Print final statistics */
    print_stats();
    
    return 0;
}
