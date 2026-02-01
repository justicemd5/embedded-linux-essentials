/*
 * gpio_rt_handler.c - Real-time GPIO interrupt handler
 * 
 * Demonstrates low-latency GPIO edge detection for real-time applications
 * such as:
 * - Motor encoder reading
 * - Hardware event capture
 * - External interrupt handling
 * 
 * Uses Linux's /sys/class/gpio and poll() for edge detection.
 * For lowest latency, consider using the gpiod character device API.
 * 
 * Compile:
 *   arm-linux-gnueabihf-gcc -O2 -o gpio_rt gpio_rt_handler.c -lpthread -lrt
 * 
 * Setup on BBB:
 *   # Export GPIO and configure edge
 *   echo 66 > /sys/class/gpio/export
 *   echo in > /sys/class/gpio/gpio66/direction
 *   echo rising > /sys/class/gpio/gpio66/edge
 * 
 * Run:
 *   sudo ./gpio_rt 66
 * 
 * Author: Embedded Linux Labs
 * License: MIT
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>
#include <time.h>
#include <sched.h>
#include <sys/mman.h>
#include <signal.h>

/* Configuration */
#define RT_PRIORITY     95          /* High priority for interrupt handling */
#define POLL_TIMEOUT_MS 1000        /* 1 second poll timeout */

static volatile sig_atomic_t running = 1;

/* Statistics */
static long interrupt_count = 0;
static long min_latency_ns = LONG_MAX;
static long max_latency_ns = 0;
static struct timespec last_interrupt;

/* ==========================================================================
 * TIME UTILITIES
 * ========================================================================== */

static inline long timespec_diff_ns(struct timespec *a, struct timespec *b)
{
    return (a->tv_sec - b->tv_sec) * 1000000000L + (a->tv_nsec - b->tv_nsec);
}

/* ==========================================================================
 * GPIO UTILITIES
 * ========================================================================== */

static int gpio_export(int gpio)
{
    char path[64];
    char buf[16];
    int fd, len;
    
    /* Check if already exported */
    snprintf(path, sizeof(path), "/sys/class/gpio/gpio%d/value", gpio);
    if (access(path, F_OK) == 0) {
        return 0;  /* Already exported */
    }
    
    fd = open("/sys/class/gpio/export", O_WRONLY);
    if (fd < 0) {
        perror("open export");
        return -1;
    }
    
    len = snprintf(buf, sizeof(buf), "%d", gpio);
    if (write(fd, buf, len) != len) {
        perror("write export");
        close(fd);
        return -1;
    }
    
    close(fd);
    usleep(100000);  /* Wait for export to complete */
    return 0;
}

static int gpio_set_direction(int gpio, const char *dir)
{
    char path[64];
    int fd;
    
    snprintf(path, sizeof(path), "/sys/class/gpio/gpio%d/direction", gpio);
    fd = open(path, O_WRONLY);
    if (fd < 0) {
        perror("open direction");
        return -1;
    }
    
    if (write(fd, dir, strlen(dir)) < 0) {
        perror("write direction");
        close(fd);
        return -1;
    }
    
    close(fd);
    return 0;
}

static int gpio_set_edge(int gpio, const char *edge)
{
    char path[64];
    int fd;
    
    snprintf(path, sizeof(path), "/sys/class/gpio/gpio%d/edge", gpio);
    fd = open(path, O_WRONLY);
    if (fd < 0) {
        perror("open edge");
        return -1;
    }
    
    if (write(fd, edge, strlen(edge)) < 0) {
        perror("write edge");
        close(fd);
        return -1;
    }
    
    close(fd);
    return 0;
}

static int gpio_open_value(int gpio)
{
    char path[64];
    snprintf(path, sizeof(path), "/sys/class/gpio/gpio%d/value", gpio);
    return open(path, O_RDONLY | O_NONBLOCK);
}

/* ==========================================================================
 * INTERRUPT HANDLER
 * ========================================================================== */

static void handle_interrupt(int fd)
{
    struct timespec now;
    char buf[8];
    long diff;
    
    /* Timestamp immediately */
    clock_gettime(CLOCK_MONOTONIC, &now);
    
    /* Read value (clears interrupt) */
    lseek(fd, 0, SEEK_SET);
    read(fd, buf, sizeof(buf));
    
    interrupt_count++;
    
    /* Calculate interval since last interrupt */
    if (last_interrupt.tv_sec != 0) {
        diff = timespec_diff_ns(&now, &last_interrupt);
        if (diff > 0) {
            if (diff < min_latency_ns) min_latency_ns = diff;
            if (diff > max_latency_ns) max_latency_ns = diff;
        }
    }
    
    last_interrupt = now;
    
    /*
     * PUT YOUR RT WORK HERE
     * This function runs on every GPIO edge
     * Keep it short and deterministic!
     */
    
    /* Example: Update encoder count */
    /* encoder_count++; */
    
    /* Print every 1000 interrupts */
    if (interrupt_count % 1000 == 0) {
        printf("Interrupts: %ld, Interval min: %ld ns, max: %ld ns\n",
               interrupt_count, min_latency_ns, max_latency_ns);
    }
}

/* ==========================================================================
 * RT SETUP
 * ========================================================================== */

static int setup_rt(void)
{
    struct sched_param param;
    
    /* Lock memory */
    if (mlockall(MCL_CURRENT | MCL_FUTURE) == -1) {
        perror("mlockall");
    }
    
    /* Set RT scheduling */
    param.sched_priority = RT_PRIORITY;
    if (sched_setscheduler(0, SCHED_FIFO, &param) == -1) {
        perror("sched_setscheduler");
        return -1;
    }
    
    printf("RT scheduling enabled: SCHED_FIFO, priority %d\n", RT_PRIORITY);
    return 0;
}

/* ==========================================================================
 * SIGNAL HANDLER
 * ========================================================================== */

static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

/* ==========================================================================
 * MAIN LOOP
 * ========================================================================== */

static void gpio_poll_loop(int gpio)
{
    struct pollfd pfd;
    int ret;
    
    /* Export and configure GPIO */
    if (gpio_export(gpio) < 0) return;
    if (gpio_set_direction(gpio, "in") < 0) return;
    if (gpio_set_edge(gpio, "both") < 0) return;
    
    /* Open value file */
    pfd.fd = gpio_open_value(gpio);
    if (pfd.fd < 0) {
        perror("gpio_open_value");
        return;
    }
    pfd.events = POLLPRI | POLLERR;
    
    /* Initial read to clear pending */
    char buf[8];
    read(pfd.fd, buf, sizeof(buf));
    
    printf("Waiting for GPIO %d edges...\n", gpio);
    printf("Press Ctrl+C to stop\n\n");
    
    while (running) {
        ret = poll(&pfd, 1, POLL_TIMEOUT_MS);
        
        if (ret < 0) {
            if (errno == EINTR) continue;
            perror("poll");
            break;
        }
        
        if (ret == 0) {
            /* Timeout - no edge */
            continue;
        }
        
        if (pfd.revents & POLLPRI) {
            handle_interrupt(pfd.fd);
        }
    }
    
    close(pfd.fd);
}

/* ==========================================================================
 * MAIN
 * ========================================================================== */

int main(int argc, char *argv[])
{
    int gpio;
    
    printf("\n========================================\n");
    printf("  GPIO RT INTERRUPT HANDLER\n");
    printf("========================================\n\n");
    
    if (argc < 2) {
        printf("Usage: %s <gpio_number>\n", argv[0]);
        printf("Example: %s 66\n", argv[0]);
        printf("\nBBB GPIO examples:\n");
        printf("  P8.7  = GPIO66\n");
        printf("  P8.8  = GPIO67\n");
        printf("  P8.9  = GPIO69\n");
        printf("  P8.10 = GPIO68\n");
        return 1;
    }
    
    gpio = atoi(argv[1]);
    
    if (geteuid() != 0) {
        fprintf(stderr, "Warning: Not running as root\n");
    }
    
    /* Setup signals */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    /* Setup RT */
    setup_rt();
    
    /* Initialize last interrupt time */
    memset(&last_interrupt, 0, sizeof(last_interrupt));
    
    /* Run main loop */
    gpio_poll_loop(gpio);
    
    /* Print final statistics */
    printf("\n========================================\n");
    printf("  FINAL STATISTICS\n");
    printf("========================================\n");
    printf("Total interrupts: %ld\n", interrupt_count);
    if (interrupt_count > 1) {
        printf("Min interval: %ld ns (%.2f µs)\n", 
               min_latency_ns, min_latency_ns / 1000.0);
        printf("Max interval: %ld ns (%.2f µs)\n", 
               max_latency_ns, max_latency_ns / 1000.0);
    }
    printf("========================================\n");
    
    return 0;
}
