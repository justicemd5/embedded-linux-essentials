# Exercise 9: Custom Init System

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Directory Structure

```
09_custom_init/
├── build_init.sh           # Build script for cross-compilation
├── install_init.sh         # Install init to rootfs
├── test_init.sh            # Test init in isolated environment
├── src/
│   ├── init.c              # Minimal init implementation (~450 lines)
│   ├── init_advanced.c     # Advanced init with service management
│   └── Makefile            # Cross-compilation makefile
├── rootfs/
│   ├── etc/
│   │   ├── init.conf       # Init configuration file
│   │   └── init.d/
│   │       ├── rcS         # Main startup script
│   │       ├── S10network  # Network initialization
│   │       ├── S20syslog   # System logger
│   │       └── S50dropbear # SSH server
│   └── sbin/
│       ├── halt            # Halt command
│       └── reboot          # Reboot command
└── docs/
    ├── init_theory.md      # Comprehensive PID 1 theory
    └── troubleshooting.md  # Common problems and solutions
```

## Quick Start

```bash
# Navigate to exercise directory
cd 09_custom_init

# Build minimal init for ARM
./build_init.sh minimal

# Or build advanced version with service management
./build_init.sh advanced

# Build native version for testing on host
./build_init.sh minimal native

# Install to mounted rootfs
sudo mount /dev/sdb2 /mnt
sudo ./install_init.sh /mnt
sudo umount /mnt

# Test in isolated environment (limited)
sudo ./test_init.sh
```

## Objective

Build a minimal init system from scratch without systemd or BusyBox init to understand the Linux boot process.

## Prerequisites

- Working rootfs for BeagleBone Black
- Understanding of PID 1 requirements
- C programming skills
- Cross-compilation setup

## Difficulty: ⭐⭐⭐⭐ Expert

---

## What is Init?

```
┌─────────────────────────────────────────────────────────────┐
│                 INIT SYSTEM OVERVIEW                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Kernel boots ───► executes /sbin/init (PID 1)             │
│                                                             │
│  PID 1 responsibilities:                                    │
│  • Mount essential filesystems (/proc, /sys, /dev)         │
│  • Set up environment                                       │
│  • Start system services                                    │
│  • Reap zombie processes                                    │
│  • Handle shutdown/reboot                                   │
│  • NEVER EXIT (causes kernel panic)                         │
│                                                             │
│  Common init systems:                                       │
│  ┌──────────────┬────────────┬─────────────────────────┐   │
│  │ System       │ Size       │ Use Case                │   │
│  ├──────────────┼────────────┼─────────────────────────┤   │
│  │ systemd      │ ~50MB+     │ Full-featured distros   │   │
│  │ SysVinit     │ ~1MB       │ Traditional systems     │   │
│  │ OpenRC       │ ~2MB       │ Gentoo, Alpine          │   │
│  │ BusyBox init │ ~500KB     │ Embedded systems        │   │
│  │ Custom       │ <100KB     │ Ultra-minimal           │   │
│  └──────────────┴────────────┴─────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Guide

### Step 1: Create Minimal Init

```bash
mkdir -p ~/bbb-init
cd ~/bbb-init
```

**init.c - Complete minimal init:**

```c
/*
 * Minimal Init for BeagleBone Black
 * 
 * This is a bare-bones init system that demonstrates
 * the minimum requirements for PID 1.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#include <linux/reboot.h>

#define CONSOLE "/dev/ttyO0"
#define SHELL   "/bin/sh"

/* Forward declarations */
static void mount_filesystems(void);
static void setup_console(void);
static void setup_hostname(void);
static void reap_zombies(int sig);
static void handle_shutdown(int sig);
static pid_t spawn(const char *cmd, char *const argv[]);
static void run_startup_scripts(void);
static void start_shell(void);

/* Global flag for shutdown */
static volatile int shutdown_requested = 0;
static volatile int reboot_requested = 0;

int main(int argc, char *argv[])
{
    pid_t pid;
    int status;

    /* We must be PID 1 */
    if (getpid() != 1) {
        fprintf(stderr, "init: must be run as PID 1\n");
        return 1;
    }

    /* Set up signal handlers */
    signal(SIGCHLD, reap_zombies);
    signal(SIGTERM, handle_shutdown);
    signal(SIGUSR1, handle_shutdown);  /* For reboot */

    printf("\n");
    printf("===========================================\n");
    printf("  BeagleBone Black Custom Init Starting\n");
    printf("===========================================\n");
    printf("\n");

    /* Mount essential filesystems */
    mount_filesystems();

    /* Set up console */
    setup_console();

    /* Set hostname */
    setup_hostname();

    /* Run startup scripts */
    run_startup_scripts();

    /* Start shell (main service) */
    start_shell();

    /* Main loop - reap children and wait for shutdown */
    printf("init: entering main loop\n");
    while (!shutdown_requested) {
        /* Wait for any child process */
        pid = wait(&status);
        
        if (pid > 0) {
            printf("init: child %d exited with status %d\n", pid, status);
        } else if (errno != EINTR) {
            /* No children, sleep briefly */
            usleep(100000);  /* 100ms */
        }
        
        /* Restart shell if it dies */
        if (access("/bin/sh", X_OK) == 0) {
            /* Check if shell is still running */
            /* In production, you'd track the shell PID */
        }
    }

    /* Shutdown sequence */
    printf("init: shutting down...\n");
    
    /* Kill all processes */
    kill(-1, SIGTERM);
    sleep(2);
    kill(-1, SIGKILL);
    sleep(1);

    /* Unmount filesystems */
    sync();
    umount("/proc");
    umount("/sys");
    
    /* Reboot or halt */
    if (reboot_requested) {
        printf("init: rebooting...\n");
        reboot(LINUX_REBOOT_CMD_RESTART);
    } else {
        printf("init: halting...\n");
        reboot(LINUX_REBOOT_CMD_POWER_OFF);
    }

    /* Should never reach here */
    while (1) {
        sleep(1);
    }

    return 0;
}

static void mount_filesystems(void)
{
    printf("init: mounting filesystems...\n");

    /* Create mount points if needed */
    mkdir("/proc", 0755);
    mkdir("/sys", 0755);
    mkdir("/dev", 0755);
    mkdir("/tmp", 0755);
    mkdir("/run", 0755);

    /* Mount procfs */
    if (mount("proc", "/proc", "proc", 0, NULL) < 0) {
        if (errno != EBUSY)
            perror("init: mount /proc");
    }

    /* Mount sysfs */
    if (mount("sysfs", "/sys", "sysfs", 0, NULL) < 0) {
        if (errno != EBUSY)
            perror("init: mount /sys");
    }

    /* Mount devtmpfs */
    if (mount("devtmpfs", "/dev", "devtmpfs", 0, NULL) < 0) {
        if (errno != EBUSY)
            perror("init: mount /dev");
    }

    /* Mount tmpfs for /tmp and /run */
    mount("tmpfs", "/tmp", "tmpfs", 0, "mode=1777");
    mount("tmpfs", "/run", "tmpfs", 0, "mode=0755");

    /* Create essential device nodes if devtmpfs didn't */
    mknod("/dev/console", S_IFCHR | 0600, makedev(5, 1));
    mknod("/dev/null", S_IFCHR | 0666, makedev(1, 3));
    mknod("/dev/zero", S_IFCHR | 0666, makedev(1, 5));

    printf("init: filesystems mounted\n");
}

static void setup_console(void)
{
    int fd;

    printf("init: setting up console...\n");

    /* Close inherited file descriptors */
    close(0);
    close(1);
    close(2);

    /* Open console for stdin/stdout/stderr */
    fd = open(CONSOLE, O_RDWR);
    if (fd < 0) {
        /* Fallback to /dev/console */
        fd = open("/dev/console", O_RDWR);
    }
    
    if (fd >= 0) {
        dup2(fd, 0);  /* stdin */
        dup2(fd, 1);  /* stdout */
        dup2(fd, 2);  /* stderr */
        if (fd > 2) close(fd);
    }

    /* Set controlling terminal */
    setsid();
    ioctl(0, TIOCSCTTY, 1);
}

static void setup_hostname(void)
{
    FILE *fp;
    char hostname[64] = "beaglebone";

    fp = fopen("/etc/hostname", "r");
    if (fp) {
        if (fgets(hostname, sizeof(hostname), fp)) {
            hostname[strcspn(hostname, "\n")] = 0;
        }
        fclose(fp);
    }

    if (sethostname(hostname, strlen(hostname)) < 0) {
        perror("init: sethostname");
    }

    printf("init: hostname set to '%s'\n", hostname);
}

static void reap_zombies(int sig)
{
    (void)sig;
    while (waitpid(-1, NULL, WNOHANG) > 0) {
        /* Reap all zombie children */
    }
}

static void handle_shutdown(int sig)
{
    shutdown_requested = 1;
    if (sig == SIGUSR1) {
        reboot_requested = 1;
    }
}

static pid_t spawn(const char *cmd, char *const argv[])
{
    pid_t pid = fork();
    
    if (pid == 0) {
        /* Child */
        execv(cmd, argv);
        perror("init: exec failed");
        _exit(127);
    }
    
    return pid;
}

static void run_startup_scripts(void)
{
    char *argv[] = { "/bin/sh", "-c", NULL, NULL };
    
    printf("init: running startup scripts...\n");

    /* Run /etc/init.d/rcS if it exists */
    if (access("/etc/init.d/rcS", X_OK) == 0) {
        argv[2] = "/etc/init.d/rcS";
        pid_t pid = spawn("/bin/sh", argv);
        if (pid > 0) {
            int status;
            waitpid(pid, &status, 0);
        }
    }

    /* Run all scripts in /etc/init.d starting with S */
    /* In production, you'd iterate through the directory */
}

static void start_shell(void)
{
    pid_t pid;
    char *argv[] = { "-sh", NULL };  /* Leading dash for login shell */
    char *envp[] = { 
        "HOME=/root",
        "PATH=/sbin:/bin:/usr/sbin:/usr/bin",
        "TERM=linux",
        "USER=root",
        NULL 
    };

    printf("init: starting shell on %s\n", CONSOLE);
    printf("\n");
    printf("===========================================\n");
    printf("  BeagleBone Black Ready - Type 'help'\n");
    printf("===========================================\n");
    printf("\n");

    pid = fork();
    if (pid == 0) {
        /* Child - become the shell */
        execve(SHELL, argv, envp);
        perror("init: exec shell");
        _exit(127);
    }
}
```

### Step 2: Create Makefile

```makefile
# Makefile for custom init

CC = arm-linux-gnueabihf-gcc
CFLAGS = -Wall -Wextra -O2 -static
LDFLAGS = -static

TARGET = init

.PHONY: all clean install

all: $(TARGET)

$(TARGET): init.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<
	arm-linux-gnueabihf-strip $@

clean:
	rm -f $(TARGET)

install: $(TARGET)
	install -m 0755 $(TARGET) $(DESTDIR)/sbin/init
```

### Step 3: Build Init

```bash
make
file init
# Should show: ELF 32-bit LSB executable, ARM, statically linked

ls -la init
# Should be small, ~100-200KB
```

### Step 4: Create Startup Script

```bash
mkdir -p rootfs/etc/init.d

cat > rootfs/etc/init.d/rcS << 'EOF'
#!/bin/sh
# BeagleBone Black Startup Script

echo "Running startup scripts..."

# Remount root read-write
mount -o remount,rw /

# Set up networking
if [ -x /sbin/ifconfig ]; then
    ifconfig lo 127.0.0.1 up
    ifconfig eth0 up
    # Enable DHCP if udhcpc is available
    if [ -x /sbin/udhcpc ]; then
        udhcpc -i eth0 -b
    fi
fi

# Set date (useful if no RTC)
if [ -f /etc/timestamp ]; then
    date -s "$(cat /etc/timestamp)"
fi

# Load kernel modules
if [ -d /lib/modules ]; then
    for mod in /lib/modules/$(uname -r)/*.ko; do
        [ -f "$mod" ] && insmod "$mod" 2>/dev/null
    done
fi

# Run any custom scripts
for script in /etc/init.d/S*; do
    [ -x "$script" ] && "$script" start
done

echo "Startup complete!"
EOF

chmod +x rootfs/etc/init.d/rcS
```

### Step 5: Create Shutdown Commands

```bash
mkdir -p rootfs/sbin

# Halt command
cat > rootfs/sbin/halt << 'EOF'
#!/bin/sh
echo "System is halting..."
sync
kill -TERM 1
EOF
chmod +x rootfs/sbin/halt

# Reboot command
cat > rootfs/sbin/reboot << 'EOF'
#!/bin/sh
echo "System is rebooting..."
sync
kill -USR1 1
EOF
chmod +x rootfs/sbin/reboot

# Poweroff alias
ln -s halt rootfs/sbin/poweroff
```

### Step 6: Deploy to BeagleBone Black

```bash
# Mount rootfs partition
sudo mount /dev/sdX2 /mnt

# Backup original init
sudo mv /mnt/sbin/init /mnt/sbin/init.backup

# Install custom init
sudo cp init /mnt/sbin/init
sudo cp -a rootfs/etc/init.d/* /mnt/etc/init.d/
sudo cp -a rootfs/sbin/* /mnt/sbin/

sudo umount /mnt
```

### Step 7: Boot and Test

```bash
# Connect via serial
screen /dev/ttyACM0 115200

# Power on BBB, observe boot messages
# Should see custom init messages
# Type commands at the shell prompt

# Test shutdown
halt

# Test reboot
reboot
```

---

## Advanced Features

### Add Service Management

```c
/* Simple service management */
struct service {
    const char *name;
    const char *cmd;
    pid_t pid;
    int restart;
};

static struct service services[] = {
    { "syslogd", "/sbin/syslogd", 0, 1 },
    { "dropbear", "/usr/sbin/dropbear -F", 0, 1 },
    { NULL, NULL, 0, 0 }
};

static void start_services(void)
{
    for (int i = 0; services[i].name; i++) {
        if (access(services[i].cmd, X_OK) == 0) {
            services[i].pid = spawn(services[i].cmd, ...);
            printf("init: started %s (pid %d)\n", 
                   services[i].name, services[i].pid);
        }
    }
}

static void restart_service_if_dead(pid_t died_pid)
{
    for (int i = 0; services[i].name; i++) {
        if (services[i].pid == died_pid && services[i].restart) {
            printf("init: restarting %s\n", services[i].name);
            services[i].pid = spawn(services[i].cmd, ...);
        }
    }
}
```

### Add Configuration File

```c
/* Parse /etc/inittab-like config */
static void parse_config(void)
{
    FILE *fp = fopen("/etc/init.conf", "r");
    char line[256];
    
    if (!fp) return;
    
    while (fgets(line, sizeof(line), fp)) {
        /* Parse: name:command:respawn */
        char *name = strtok(line, ":");
        char *cmd = strtok(NULL, ":");
        char *action = strtok(NULL, ":");
        /* ... */
    }
    
    fclose(fp);
}
```

---

## Comparison: Init Systems

| Feature | Custom | BusyBox | systemd |
|---------|--------|---------|---------|
| Binary size | ~100KB | ~500KB | ~50MB |
| Boot time | Fastest | Fast | Slower |
| Dependencies | None | BusyBox | Many |
| Service mgmt | Basic | Basic | Full |
| Parallelization | No | No | Yes |
| Logging | Manual | syslog | journald |
| Complexity | Simple | Simple | Complex |

---

## Verification Checklist

- [ ] Init compiles as static ARM binary
- [ ] Init runs as PID 1
- [ ] /proc, /sys, /dev mounted
- [ ] Console accessible
- [ ] Shell starts
- [ ] Startup scripts run
- [ ] Zombie reaping works
- [ ] Shutdown command works
- [ ] Reboot command works

---

[← Previous: Yocto](08_yocto.md) | [Back to Index](README.md) | [Next: Network Boot →](10_network_boot.md)
