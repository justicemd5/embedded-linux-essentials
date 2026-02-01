/*
 * cyclictest_custom.c - Custom cyclictest-like latency measurement
 * 
 * A simplified version of cyclictest for educational purposes.
 * Shows how latency measurement works under the hood.
 * 
 * Features:
 * - SCHED_FIFO real-time scheduling
 * - Histogram generation
 * - Max latency tracking
 * - Optional CPU affinity
 * 
 * Compile:
 *   arm-linux-gnueabihf-gcc -O2 -o cyclictest_custom cyclictest_custom.c -lpthread -lrt
 * 
 * Run:
 *   sudo ./cyclictest_custom -p 80 -i 1000 -l 10000
 * 
 * Options:
 *   -p N    Priority (1-99, default: 80)
 *   -i N    Interval in microseconds (default: 1000)
 *   -l N    Number of loops (default: 0 = infinite)
 *   -c N    CPU affinity (default: -1 = no affinity)
 *   -h      Show histogram
 * 
 * Author: Embedded Linux Labs
 * License: MIT
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <errno.h>
#include <time.h>
#include <sched.h>
#include <sys/mman.h>
#include <signal.h>
#include <limits.h>

/* Configuration */
#define DEFAULT_PRIORITY   80
#define DEFAULT_INTERVAL   1000    /* microseconds */
#define DEFAULT_LOOPS      0       /* 0 = infinite */
#define HISTOGRAM_SIZE     1000    /* microseconds */

/* Global state */
struct config {
    int priority;
    long interval_us;
    long loops;
    int cpu;
    int show_histogram;
};

struct stats {
    long min_ns;
    long max_ns;
    long total_ns;
    long count;
    long overruns;
    long histogram[HISTOGRAM_SIZE];
};

static struct config cfg = {
    .priority = DEFAULT_PRIORITY,
    .interval_us = DEFAULT_INTERVAL,
    .loops = DEFAULT_LOOPS,
    .cpu = -1,
    .show_histogram = 0,
};

static struct stats stats = {
    .min_ns = LONG_MAX,
    .max_ns = 0,
    .total_ns = 0,
    .count = 0,
    .overruns = 0,
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
 * SIGNAL HANDLING
 * ========================================================================== */

static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

/* ==========================================================================
 * PARSE ARGUMENTS
 * ========================================================================== */

static void usage(const char *prog)
{
    printf("Usage: %s [options]\n", prog);
    printf("\nOptions:\n");
    printf("  -p N    RT priority (1-99, default: %d)\n", DEFAULT_PRIORITY);
    printf("  -i N    Interval in microseconds (default: %d)\n", DEFAULT_INTERVAL);
    printf("  -l N    Number of loops (0=infinite, default: %d)\n", DEFAULT_LOOPS);
    printf("  -c N    CPU affinity (-1=none, default: -1)\n");
    printf("  -h      Show histogram\n");
    printf("  --help  Show this help\n");
    printf("\nExamples:\n");
    printf("  %s -p 80 -i 1000 -l 10000      # 10000 loops, 1ms interval\n", prog);
    printf("  %s -p 99 -c 0 -i 500 -h        # Pin to CPU0, 500us, histogram\n", prog);
}

static void parse_args(int argc, char *argv[])
{
    int opt;
    
    while ((opt = getopt(argc, argv, "p:i:l:c:h")) != -1) {
        switch (opt) {
        case 'p':
            cfg.priority = atoi(optarg);
            if (cfg.priority < 1 || cfg.priority > 99) {
                fprintf(stderr, "Priority must be 1-99\n");
                exit(1);
            }
            break;
        case 'i':
            cfg.interval_us = atol(optarg);
            if (cfg.interval_us < 10) {
                fprintf(stderr, "Interval must be >= 10us\n");
                exit(1);
            }
            break;
        case 'l':
            cfg.loops = atol(optarg);
            break;
        case 'c':
            cfg.cpu = atoi(optarg);
            break;
        case 'h':
            cfg.show_histogram = 1;
            break;
        default:
            usage(argv[0]);
            exit(1);
        }
    }
}

/* ==========================================================================
 * RT SETUP
 * ========================================================================== */

static int setup_rt(void)
{
    struct sched_param param;
    cpu_set_t cpuset;
    
    /* Lock memory */
    if (mlockall(MCL_CURRENT | MCL_FUTURE) == -1) {
        perror("mlockall");
        return -1;
    }
    
    /* CPU affinity */
    if (cfg.cpu >= 0) {
        CPU_ZERO(&cpuset);
        CPU_SET(cfg.cpu, &cpuset);
        if (sched_setaffinity(0, sizeof(cpuset), &cpuset) == -1) {
            perror("sched_setaffinity");
        }
    }
    
    /* RT scheduling */
    param.sched_priority = cfg.priority;
    if (sched_setscheduler(0, SCHED_FIFO, &param) == -1) {
        perror("sched_setscheduler");
        return -1;
    }
    
    return 0;
}

/* ==========================================================================
 * MAIN LOOP
 * ========================================================================== */

static void cyclic_loop(void)
{
    struct timespec next, now;
    long latency_ns;
    long interval_ns = cfg.interval_us * 1000;
    
    clock_gettime(CLOCK_MONOTONIC, &next);
    
    while (running && (cfg.loops == 0 || stats.count < cfg.loops)) {
        /* Calculate next wakeup */
        timespec_add_ns(&next, interval_ns);
        
        /* Sleep until next */
        if (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL) != 0) {
            if (errno == EINTR) break;
        }
        
        /* Measure latency */
        clock_gettime(CLOCK_MONOTONIC, &now);
        latency_ns = timespec_diff_ns(&now, &next);
        
        /* Check for overrun */
        if (latency_ns > interval_ns) {
            stats.overruns++;
        }
        
        /* Update statistics */
        if (latency_ns > 0) {
            stats.count++;
            stats.total_ns += latency_ns;
            
            if (latency_ns < stats.min_ns) stats.min_ns = latency_ns;
            if (latency_ns > stats.max_ns) stats.max_ns = latency_ns;
            
            /* Histogram */
            long latency_us = latency_ns / 1000;
            if (latency_us < HISTOGRAM_SIZE) {
                stats.histogram[latency_us]++;
            } else {
                stats.histogram[HISTOGRAM_SIZE - 1]++;
            }
        }
        
        /* Progress indicator every second */
        if (stats.count % (1000000 / cfg.interval_us) == 0) {
            printf("\rIterations: %8ld  Max: %8ld ns", stats.count, stats.max_ns);
            fflush(stdout);
        }
    }
    
    printf("\n");
}

/* ==========================================================================
 * PRINT RESULTS
 * ========================================================================== */

static void print_results(void)
{
    printf("\n");
    printf("========================================\n");
    printf("  CYCLIC TEST RESULTS\n");
    printf("========================================\n");
    printf("Iterations:    %ld\n", stats.count);
    printf("Interval:      %ld µs\n", cfg.interval_us);
    printf("Priority:      %d (SCHED_FIFO)\n", cfg.priority);
    if (cfg.cpu >= 0) {
        printf("CPU affinity:  %d\n", cfg.cpu);
    }
    printf("Overruns:      %ld\n", stats.overruns);
    printf("\n");
    printf("Latency (ns):\n");
    printf("  Min:  %10ld (%7.2f µs)\n", stats.min_ns, stats.min_ns / 1000.0);
    printf("  Max:  %10ld (%7.2f µs)\n", stats.max_ns, stats.max_ns / 1000.0);
    printf("  Avg:  %10.0f (%7.2f µs)\n", 
           (double)stats.total_ns / stats.count,
           (double)stats.total_ns / stats.count / 1000.0);
    printf("========================================\n");
    
    /* Histogram */
    if (cfg.show_histogram) {
        printf("\nHistogram (µs : count)\n");
        printf("----------------------------------------\n");
        
        long max_count = 0;
        for (int i = 0; i < HISTOGRAM_SIZE; i++) {
            if (stats.histogram[i] > max_count) {
                max_count = stats.histogram[i];
            }
        }
        
        for (int i = 0; i < HISTOGRAM_SIZE; i++) {
            if (stats.histogram[i] > 0) {
                int bar_len = (int)(stats.histogram[i] * 40 / max_count);
                printf("%4d: %8ld ", i, stats.histogram[i]);
                for (int j = 0; j < bar_len; j++) printf("█");
                printf("\n");
            }
        }
        printf("----------------------------------------\n");
    }
}

/* ==========================================================================
 * MAIN
 * ========================================================================== */

int main(int argc, char *argv[])
{
    printf("\n========================================\n");
    printf("  CUSTOM CYCLIC TEST\n");
    printf("========================================\n\n");
    
    parse_args(argc, argv);
    
    if (geteuid() != 0) {
        fprintf(stderr, "Error: Must run as root\n");
        return 1;
    }
    
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    printf("Configuration:\n");
    printf("  Priority:   %d\n", cfg.priority);
    printf("  Interval:   %ld µs\n", cfg.interval_us);
    printf("  Loops:      %ld%s\n", cfg.loops, cfg.loops == 0 ? " (infinite)" : "");
    printf("  CPU:        %d%s\n", cfg.cpu, cfg.cpu < 0 ? " (no affinity)" : "");
    printf("  Histogram:  %s\n", cfg.show_histogram ? "yes" : "no");
    printf("\n");
    
    if (setup_rt() != 0) {
        fprintf(stderr, "Failed to setup RT scheduling\n");
        return 1;
    }
    
    printf("Starting cyclic test... (Ctrl+C to stop)\n\n");
    
    cyclic_loop();
    
    print_results();
    
    return 0;
}
