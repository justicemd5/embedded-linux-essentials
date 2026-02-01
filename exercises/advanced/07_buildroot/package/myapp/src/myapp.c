/*
 * myapp.c - Example BeagleBone Black Application
 *
 * Demonstrates custom Buildroot package with hardware access
 *
 * Author: Embedded Linux Labs
 * License: MIT
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include <sys/stat.h>

#define VERSION "1.0.0"

/* GPIO sysfs paths */
#define GPIO_EXPORT     "/sys/class/gpio/export"
#define GPIO_UNEXPORT   "/sys/class/gpio/unexport"
#define GPIO_BASE       "/sys/class/gpio/gpio"

/* BeagleBone Black USR LEDs */
#define USR0_LED    "/sys/class/leds/beaglebone:green:usr0"
#define USR1_LED    "/sys/class/leds/beaglebone:green:usr1"
#define USR2_LED    "/sys/class/leds/beaglebone:green:usr2"
#define USR3_LED    "/sys/class/leds/beaglebone:green:usr3"

void print_help(const char *progname) {
    printf("Usage: %s [options]\n", progname);
    printf("\n");
    printf("Options:\n");
    printf("  -i          Show system information\n");
    printf("  -l          Blink USR LEDs\n");
    printf("  -g <gpio>   Read GPIO pin\n");
    printf("  -t          Run hardware tests\n");
    printf("  -h          Show this help\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s -i           # Show system info\n", progname);
    printf("  %s -l           # Blink LEDs\n", progname);
    printf("  %s -g 66        # Read GPIO 66 (P8_7)\n", progname);
    printf("\n");
}

void print_system_info(void) {
    FILE *fp;
    char buffer[256];
    
    printf("\n");
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║              BeagleBone Black System Information             ║\n");
    printf("╚══════════════════════════════════════════════════════════════╝\n");
    printf("\n");
    
    /* Hostname */
    if (gethostname(buffer, sizeof(buffer)) == 0) {
        printf("Hostname:     %s\n", buffer);
    }
    
    /* Kernel */
    fp = fopen("/proc/version", "r");
    if (fp) {
        if (fgets(buffer, sizeof(buffer), fp)) {
            char *newline = strchr(buffer, '\n');
            if (newline) *newline = '\0';
            /* Truncate for display */
            if (strlen(buffer) > 60) {
                buffer[57] = '.';
                buffer[58] = '.';
                buffer[59] = '.';
                buffer[60] = '\0';
            }
            printf("Kernel:       %s\n", buffer);
        }
        fclose(fp);
    }
    
    /* CPU */
    fp = fopen("/proc/cpuinfo", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strncmp(buffer, "Hardware", 8) == 0) {
                char *value = strchr(buffer, ':');
                if (value) {
                    value += 2;  /* Skip ": " */
                    char *newline = strchr(value, '\n');
                    if (newline) *newline = '\0';
                    printf("Hardware:     %s\n", value);
                }
            }
            if (strncmp(buffer, "Serial", 6) == 0) {
                char *value = strchr(buffer, ':');
                if (value) {
                    value += 2;
                    char *newline = strchr(value, '\n');
                    if (newline) *newline = '\0';
                    printf("Serial:       %s\n", value);
                }
            }
        }
        fclose(fp);
    }
    
    /* Memory */
    fp = fopen("/proc/meminfo", "r");
    if (fp) {
        long total_kb = 0, free_kb = 0, avail_kb = 0;
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strncmp(buffer, "MemTotal:", 9) == 0) {
                sscanf(buffer, "MemTotal: %ld kB", &total_kb);
            } else if (strncmp(buffer, "MemFree:", 8) == 0) {
                sscanf(buffer, "MemFree: %ld kB", &free_kb);
            } else if (strncmp(buffer, "MemAvailable:", 13) == 0) {
                sscanf(buffer, "MemAvailable: %ld kB", &avail_kb);
            }
        }
        printf("Memory:       %ld MB total, %ld MB available\n", 
               total_kb / 1024, avail_kb / 1024);
        fclose(fp);
    }
    
    /* Uptime */
    fp = fopen("/proc/uptime", "r");
    if (fp) {
        double uptime;
        if (fscanf(fp, "%lf", &uptime) == 1) {
            int days = (int)uptime / 86400;
            int hours = ((int)uptime % 86400) / 3600;
            int mins = ((int)uptime % 3600) / 60;
            int secs = (int)uptime % 60;
            if (days > 0) {
                printf("Uptime:       %dd %dh %dm %ds\n", days, hours, mins, secs);
            } else {
                printf("Uptime:       %dh %dm %ds\n", hours, mins, secs);
            }
        }
        fclose(fp);
    }
    
    /* Temperature (if available) */
    fp = fopen("/sys/class/thermal/thermal_zone0/temp", "r");
    if (fp) {
        int temp;
        if (fscanf(fp, "%d", &temp) == 1) {
            printf("Temperature:  %.1f°C\n", temp / 1000.0);
        }
        fclose(fp);
    }
    
    /* Load average */
    fp = fopen("/proc/loadavg", "r");
    if (fp) {
        float load1, load5, load15;
        if (fscanf(fp, "%f %f %f", &load1, &load5, &load15) == 3) {
            printf("Load:         %.2f %.2f %.2f\n", load1, load5, load15);
        }
        fclose(fp);
    }
    
    printf("\n");
}

int set_led_trigger(const char *led_path, const char *trigger) {
    char path[256];
    int fd;
    
    snprintf(path, sizeof(path), "%s/trigger", led_path);
    fd = open(path, O_WRONLY);
    if (fd < 0) {
        return -1;
    }
    
    write(fd, trigger, strlen(trigger));
    close(fd);
    return 0;
}

int set_led_brightness(const char *led_path, int brightness) {
    char path[256];
    char value[16];
    int fd;
    
    snprintf(path, sizeof(path), "%s/brightness", led_path);
    fd = open(path, O_WRONLY);
    if (fd < 0) {
        return -1;
    }
    
    snprintf(value, sizeof(value), "%d", brightness);
    write(fd, value, strlen(value));
    close(fd);
    return 0;
}

void blink_leds(void) {
    const char *leds[] = { USR0_LED, USR1_LED, USR2_LED, USR3_LED };
    int num_leds = sizeof(leds) / sizeof(leds[0]);
    int i, cycle;
    
    printf("Blinking USR LEDs (Ctrl-C to stop)...\n");
    
    /* Set all to none trigger for manual control */
    for (i = 0; i < num_leds; i++) {
        set_led_trigger(leds[i], "none");
    }
    
    /* Knight Rider pattern */
    for (cycle = 0; cycle < 10; cycle++) {
        /* Forward */
        for (i = 0; i < num_leds; i++) {
            set_led_brightness(leds[i], 1);
            usleep(100000);
            set_led_brightness(leds[i], 0);
        }
        /* Backward */
        for (i = num_leds - 2; i > 0; i--) {
            set_led_brightness(leds[i], 1);
            usleep(100000);
            set_led_brightness(leds[i], 0);
        }
    }
    
    /* Restore heartbeat on USR0 */
    set_led_trigger(USR0_LED, "heartbeat");
    
    printf("Done!\n");
}

int read_gpio(int gpio) {
    char path[256];
    char value_str[4];
    int fd;
    int value;
    
    /* Try to export GPIO */
    fd = open(GPIO_EXPORT, O_WRONLY);
    if (fd >= 0) {
        char gpio_str[8];
        snprintf(gpio_str, sizeof(gpio_str), "%d", gpio);
        write(fd, gpio_str, strlen(gpio_str));
        close(fd);
        usleep(100000);  /* Wait for export */
    }
    
    /* Read value */
    snprintf(path, sizeof(path), "%s%d/value", GPIO_BASE, gpio);
    fd = open(path, O_RDONLY);
    if (fd < 0) {
        printf("Error: Cannot open GPIO %d\n", gpio);
        printf("Make sure GPIO is not in use and try:\n");
        printf("  echo %d > /sys/class/gpio/export\n", gpio);
        return -1;
    }
    
    memset(value_str, 0, sizeof(value_str));
    read(fd, value_str, sizeof(value_str) - 1);
    close(fd);
    
    value = atoi(value_str);
    printf("GPIO %d = %d\n", gpio, value);
    
    return value;
}

void run_tests(void) {
    printf("\n");
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║                    Hardware Test Suite                       ║\n");
    printf("╚══════════════════════════════════════════════════════════════╝\n");
    printf("\n");
    
    /* Test 1: LEDs */
    printf("[TEST] USR LEDs... ");
    if (set_led_trigger(USR0_LED, "heartbeat") == 0) {
        printf("PASS\n");
    } else {
        printf("FAIL (check permissions)\n");
    }
    
    /* Test 2: Memory */
    printf("[TEST] Memory allocation... ");
    void *mem = malloc(1024 * 1024);  /* 1MB */
    if (mem) {
        memset(mem, 0xAA, 1024 * 1024);
        free(mem);
        printf("PASS\n");
    } else {
        printf("FAIL\n");
    }
    
    /* Test 3: I2C */
    printf("[TEST] I2C bus... ");
    if (access("/dev/i2c-0", F_OK) == 0 || 
        access("/dev/i2c-1", F_OK) == 0 ||
        access("/dev/i2c-2", F_OK) == 0) {
        printf("PASS (bus available)\n");
    } else {
        printf("SKIP (no I2C bus found)\n");
    }
    
    /* Test 4: SPI */
    printf("[TEST] SPI bus... ");
    if (access("/dev/spidev0.0", F_OK) == 0 ||
        access("/dev/spidev1.0", F_OK) == 0) {
        printf("PASS (bus available)\n");
    } else {
        printf("SKIP (no SPI bus found)\n");
    }
    
    /* Test 5: Network */
    printf("[TEST] Network interface... ");
    if (access("/sys/class/net/eth0", F_OK) == 0) {
        printf("PASS (eth0 present)\n");
    } else {
        printf("SKIP (no eth0)\n");
    }
    
    printf("\n");
}

int main(int argc, char *argv[]) {
    int opt;
    int gpio = -1;
    
    if (argc < 2) {
        printf("myapp version %s - BeagleBone Black Utility\n", VERSION);
        printf("Use -h for help\n");
        return 0;
    }
    
    while ((opt = getopt(argc, argv, "hilg:t")) != -1) {
        switch (opt) {
            case 'i':
                print_system_info();
                break;
            case 'l':
                blink_leds();
                break;
            case 'g':
                gpio = atoi(optarg);
                read_gpio(gpio);
                break;
            case 't':
                run_tests();
                break;
            case 'h':
            default:
                print_help(argv[0]);
                break;
        }
    }
    
    return 0;
}
