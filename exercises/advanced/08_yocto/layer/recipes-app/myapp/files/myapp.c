/*
 * myapp.c - Example BeagleBone Black Application for Yocto
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

#define VERSION "1.0.0"

void print_help(const char *progname) {
    printf("Usage: %s [options]\n", progname);
    printf("\n");
    printf("Options:\n");
    printf("  -i    Show system information\n");
    printf("  -l    Blink LEDs\n");
    printf("  -h    Show this help\n");
    printf("  -v    Show version\n");
    printf("\n");
}

void print_system_info(void) {
    FILE *fp;
    char buffer[256];
    
    printf("\n");
    printf("═══════════════════════════════════════════════════════════\n");
    printf("               BeagleBone Black System Info                \n");
    printf("═══════════════════════════════════════════════════════════\n");
    printf("\n");
    
    /* Hostname */
    if (gethostname(buffer, sizeof(buffer)) == 0) {
        printf("Hostname:    %s\n", buffer);
    }
    
    /* Kernel version */
    fp = fopen("/proc/version", "r");
    if (fp) {
        if (fgets(buffer, sizeof(buffer), fp)) {
            buffer[strcspn(buffer, "\n")] = 0;
            if (strlen(buffer) > 60) buffer[60] = 0;
            printf("Kernel:      %s...\n", buffer);
        }
        fclose(fp);
    }
    
    /* Memory */
    fp = fopen("/proc/meminfo", "r");
    if (fp) {
        long total = 0, avail = 0;
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strncmp(buffer, "MemTotal:", 9) == 0) {
                sscanf(buffer, "MemTotal: %ld", &total);
            } else if (strncmp(buffer, "MemAvailable:", 13) == 0) {
                sscanf(buffer, "MemAvailable: %ld", &avail);
            }
        }
        printf("Memory:      %ld MB total, %ld MB available\n", 
               total/1024, avail/1024);
        fclose(fp);
    }
    
    /* Uptime */
    fp = fopen("/proc/uptime", "r");
    if (fp) {
        double uptime;
        if (fscanf(fp, "%lf", &uptime) == 1) {
            int hrs = (int)uptime / 3600;
            int mins = ((int)uptime % 3600) / 60;
            int secs = (int)uptime % 60;
            printf("Uptime:      %02d:%02d:%02d\n", hrs, mins, secs);
        }
        fclose(fp);
    }
    
    printf("\n");
}

int set_led_brightness(const char *led, int brightness) {
    char path[128];
    char value[8];
    int fd;
    
    snprintf(path, sizeof(path), "/sys/class/leds/%s/brightness", led);
    fd = open(path, O_WRONLY);
    if (fd < 0) return -1;
    
    snprintf(value, sizeof(value), "%d", brightness);
    write(fd, value, strlen(value));
    close(fd);
    return 0;
}

void blink_leds(void) {
    const char *leds[] = {
        "beaglebone:green:usr0",
        "beaglebone:green:usr1",
        "beaglebone:green:usr2",
        "beaglebone:green:usr3"
    };
    int num_leds = 4;
    int i, cycle;
    
    printf("Blinking LEDs (Ctrl-C to stop)...\n");
    
    /* Set all to manual control */
    for (i = 0; i < num_leds; i++) {
        char path[128];
        int fd;
        snprintf(path, sizeof(path), "/sys/class/leds/%s/trigger", leds[i]);
        fd = open(path, O_WRONLY);
        if (fd >= 0) {
            write(fd, "none", 4);
            close(fd);
        }
    }
    
    /* Blink pattern */
    for (cycle = 0; cycle < 10; cycle++) {
        for (i = 0; i < num_leds; i++) {
            set_led_brightness(leds[i], 1);
            usleep(100000);
            set_led_brightness(leds[i], 0);
        }
    }
    
    printf("Done!\n");
}

int main(int argc, char *argv[]) {
    int opt;
    
    while ((opt = getopt(argc, argv, "hvilHIL")) != -1) {
        switch (opt) {
            case 'v':
                printf("myapp version %s\n", VERSION);
                printf("Built with Yocto Project\n");
                return 0;
            case 'i':
            case 'I':
                print_system_info();
                return 0;
            case 'l':
            case 'L':
                blink_leds();
                return 0;
            case 'h':
            case 'H':
            default:
                print_help(argv[0]);
                return 0;
        }
    }
    
    printf("myapp version %s - Yocto example application\n", VERSION);
    printf("Use -h for help\n");
    return 0;
}
