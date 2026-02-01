/*
 * multi_rt_app.c - Multi-threaded RT application
 * 
 * Demonstrates a typical embedded real-time application architecture:
 * - High-priority thread: Motor control (1kHz / 1ms)
 * - Medium-priority thread: Sensor reading (100Hz / 10ms)
 * - Low-priority thread: Logging (10Hz / 100ms)
 * 
 * Thread Priority Guidelines:
 * - Priority 99: Reserved for kernel migration threads
 * - Priority 90-98: Critical control loops
 * - Priority 70-89: Sensor/acquisition tasks
 * - Priority 50-69: Processing/logging tasks
 * - Priority 1-49: Background RT tasks
 * 
 * Compile:
 *   arm-linux-gnueabihf-gcc -O2 -o multi_rt multi_rt_app.c -lpthread -lrt
 * 
 * Run on BBB:
 *   sudo ./multi_rt
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
#include <signal.h>
#include <stdatomic.h>

/* ==========================================================================
 * CONFIGURATION
 * ========================================================================== */

/* Thread periods in nanoseconds */
#define MOTOR_PERIOD_NS   1000000    /* 1ms = 1kHz */
#define SENSOR_PERIOD_NS  10000000   /* 10ms = 100Hz */
#define LOGGER_PERIOD_NS  100000000  /* 100ms = 10Hz */

/* Thread priorities (1-99, higher = more priority) */
#define MOTOR_PRIORITY    90
#define SENSOR_PRIORITY   80
#define LOGGER_PRIORITY   70

/* Stack size for RT threads */
#define THREAD_STACK_SIZE (256 * 1024)

/* ==========================================================================
 * SHARED DATA STRUCTURES
 * ========================================================================== */

/* Thread-safe data exchange using atomic operations */
struct motor_data {
    _Atomic int encoder_count;
    _Atomic float velocity;
    _Atomic float pwm_duty;
};

struct sensor_data {
    _Atomic float temperature;
    _Atomic float pressure;
    _Atomic float imu_accel[3];
};

static struct motor_data motor = { 0 };
static struct sensor_data sensors = { 0 };
static volatile sig_atomic_t running = 1;

/* Statistics for each thread */
struct thread_stats {
    const char *name;
    long iterations;
    long max_latency_ns;
    long total_latency_ns;
};

static struct thread_stats motor_stats = { "motor", 0, 0, 0 };
static struct thread_stats sensor_stats = { "sensor", 0, 0, 0 };
static struct thread_stats logger_stats = { "logger", 0, 0, 0 };

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
 * WORK FUNCTIONS
 * ========================================================================== */

/*
 * Motor control loop - runs at 1kHz
 * Reads encoder, computes PID, outputs PWM
 */
static void motor_control_work(void)
{
    static int last_encoder = 0;
    static float integral = 0.0f;
    static float last_error = 0.0f;
    
    /* Simulated encoder read */
    int encoder = atomic_load(&motor.encoder_count);
    int delta = encoder - last_encoder;
    last_encoder = encoder;
    
    /* Simulated velocity calculation */
    float velocity = delta * 0.001f;  /* Simplified */
    atomic_store(&motor.velocity, velocity);
    
    /* PID control (example) */
    float setpoint = 100.0f;  /* Target velocity */
    float error = setpoint - velocity;
    integral += error * 0.001f;
    float derivative = (error - last_error) / 0.001f;
    last_error = error;
    
    /* PID gains */
    float Kp = 1.0f, Ki = 0.1f, Kd = 0.01f;
    float output = Kp * error + Ki * integral + Kd * derivative;
    
    /* Clamp and store PWM output */
    if (output > 100.0f) output = 100.0f;
    if (output < -100.0f) output = -100.0f;
    atomic_store(&motor.pwm_duty, output);
    
    /* Simulated workload */
    volatile int i;
    for (i = 0; i < 100; i++) {
        asm volatile("" ::: "memory");
    }
}

/*
 * Sensor reading loop - runs at 100Hz
 * Reads I2C sensors, applies filtering
 */
static void sensor_read_work(void)
{
    static float temp_filter = 25.0f;
    
    /* Simulated I2C read (in reality: use non-blocking I2C) */
    /* WARNING: Real I2C reads may not be RT-safe! */
    
    /* Simulated temperature reading with noise */
    float raw_temp = 25.0f + (rand() % 100) / 1000.0f;
    
    /* Simple IIR low-pass filter */
    float alpha = 0.1f;
    temp_filter = alpha * raw_temp + (1.0f - alpha) * temp_filter;
    atomic_store(&sensors.temperature, temp_filter);
    
    /* Simulated IMU data */
    float accel_x = (rand() % 2000 - 1000) / 1000.0f;
    atomic_store(&sensors.imu_accel[0], accel_x);
    
    /* Simulated workload */
    volatile int i;
    for (i = 0; i < 500; i++) {
        asm volatile("" ::: "memory");
    }
}

/*
 * Logging loop - runs at 10Hz
 * Collects and logs data (non-blocking)
 */
static void logging_work(void)
{
    /* Read latest data atomically */
    float velocity = atomic_load(&motor.velocity);
    float pwm = atomic_load(&motor.pwm_duty);
    float temp = atomic_load(&sensors.temperature);
    
    /* In real app: write to ring buffer, not directly to file */
    /* Files are NOT RT-safe due to potential blocking */
    
    /* For demonstration, just print occasionally */
    static int print_count = 0;
    if (print_count++ >= 10) {  /* Every second */
        printf("vel=%.2f pwm=%.1f temp=%.2f\n", velocity, pwm, temp);
        print_count = 0;
    }
}

/* ==========================================================================
 * THREAD CONFIGURATION
 * ========================================================================== */

struct thread_config {
    const char *name;
    int priority;
    long period_ns;
    void (*work_func)(void);
    struct thread_stats *stats;
    int cpu;  /* -1 for no affinity */
};

static struct thread_config thread_configs[] = {
    { "motor",  MOTOR_PRIORITY,  MOTOR_PERIOD_NS,  motor_control_work, &motor_stats, 0 },
    { "sensor", SENSOR_PRIORITY, SENSOR_PERIOD_NS, sensor_read_work, &sensor_stats, 0 },
    { "logger", LOGGER_PRIORITY, LOGGER_PERIOD_NS, logging_work, &logger_stats, -1 },
    { NULL, 0, 0, NULL, NULL, -1 }  /* Sentinel */
};

/* ==========================================================================
 * GENERIC RT THREAD
 * ========================================================================== */

static void *rt_thread(void *arg)
{
    struct thread_config *cfg = (struct thread_config *)arg;
    struct timespec next, now;
    long latency;
    
    printf("[%s] Thread started: priority=%d, period=%ldms\n",
           cfg->name, cfg->priority, cfg->period_ns / 1000000);
    
    /* Set CPU affinity if specified */
    if (cfg->cpu >= 0) {
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        CPU_SET(cfg->cpu, &cpuset);
        if (pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset) != 0) {
            perror("pthread_setaffinity_np");
        }
    }
    
    /* Get initial time */
    clock_gettime(CLOCK_MONOTONIC, &next);
    
    while (running) {
        /* Calculate next wakeup */
        timespec_add_ns(&next, cfg->period_ns);
        
        /* Sleep until next period */
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL);
        
        /* Measure latency */
        clock_gettime(CLOCK_MONOTONIC, &now);
        latency = timespec_diff_ns(&now, &next);
        
        /* Update statistics */
        if (latency > 0) {
            cfg->stats->iterations++;
            cfg->stats->total_latency_ns += latency;
            if (latency > cfg->stats->max_latency_ns) {
                cfg->stats->max_latency_ns = latency;
            }
        }
        
        /* Execute work function */
        cfg->work_func();
    }
    
    printf("[%s] Thread stopping\n", cfg->name);
    return NULL;
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
 * MAIN
 * ========================================================================== */

int main(void)
{
    pthread_t threads[10];
    pthread_attr_t attr;
    struct sched_param param;
    int thread_count = 0;
    
    printf("\n========================================\n");
    printf("  MULTI-THREADED RT APPLICATION\n");
    printf("========================================\n\n");
    
    /* Check privileges */
    if (geteuid() != 0) {
        fprintf(stderr, "Error: Must run as root for RT scheduling\n");
        return 1;
    }
    
    /* Setup signal handlers */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    /* Lock all memory */
    if (mlockall(MCL_CURRENT | MCL_FUTURE) == -1) {
        perror("mlockall failed");
    }
    
    /* Initialize pthread attributes */
    pthread_attr_init(&attr);
    pthread_attr_setinheritsched(&attr, PTHREAD_EXPLICIT_SCHED);
    pthread_attr_setschedpolicy(&attr, SCHED_FIFO);
    pthread_attr_setstacksize(&attr, THREAD_STACK_SIZE);
    
    /* Create RT threads */
    for (int i = 0; thread_configs[i].name != NULL; i++) {
        param.sched_priority = thread_configs[i].priority;
        pthread_attr_setschedparam(&attr, &param);
        
        if (pthread_create(&threads[i], &attr, rt_thread, &thread_configs[i]) != 0) {
            perror("pthread_create failed");
            fprintf(stderr, "Failed to create thread: %s\n", thread_configs[i].name);
            continue;
        }
        thread_count++;
    }
    
    pthread_attr_destroy(&attr);
    
    printf("\nStarted %d RT threads. Press Ctrl+C to stop.\n\n", thread_count);
    
    /* Wait for all threads */
    for (int i = 0; i < thread_count; i++) {
        pthread_join(threads[i], NULL);
    }
    
    /* Print statistics */
    printf("\n========================================\n");
    printf("  THREAD STATISTICS\n");
    printf("========================================\n");
    for (int i = 0; thread_configs[i].name != NULL; i++) {
        struct thread_stats *s = thread_configs[i].stats;
        if (s->iterations > 0) {
            printf("[%s] Iterations: %ld, Max latency: %ld µs, Avg: %.2f µs\n",
                   s->name, s->iterations,
                   s->max_latency_ns / 1000,
                   (double)s->total_latency_ns / s->iterations / 1000.0);
        }
    }
    printf("========================================\n");
    
    return 0;
}
