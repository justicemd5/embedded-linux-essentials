# Custom Init Troubleshooting Guide
#
# Common problems and solutions when developing custom init
#
# Author: Embedded Linux Labs

## 1. Boot Issues

### 1.1 Kernel Panic: Unable to mount root fs

**Symptom:**
```
VFS: Cannot open root device "mmcblk0p2" or unknown-block(0,0)
Kernel panic - not syncing: VFS: Unable to mount root fs
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Wrong rootfs device | Check `root=` kernel arg matches actual partition |
| Missing filesystem driver | Enable EXT4/EXT3 in kernel config |
| SD card not detected | Wait for mmcblk driver: `rootwait` |
| Wrong partition | Verify with `fdisk -l /dev/mmcblk0` |

### 1.2 Kernel Panic: No init found

**Symptom:**
```
Kernel panic - not syncing: No init found.
Try passing init= option to kernel.
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Missing /sbin/init | Verify init binary is installed |
| Not executable | `chmod +x /sbin/init` |
| Wrong architecture | Cross-compile for ARM |
| Missing libraries | Build with `-static` |

**Debug approach:**
```bash
# In U-Boot, boot with shell
setenv bootargs 'root=/dev/mmcblk0p2 rootwait init=/bin/sh'

# Then check:
ls -la /sbin/init
file /sbin/init
```

### 1.3 Kernel Panic: Attempted to kill init!

**Symptom:**
```
Kernel panic - not syncing: Attempted to kill init!
```

**Causes:**
- Init process crashed
- Init received uncaught signal
- Init called exit()

**Debug approach:**
```c
// Add to init.c main():
while (1) {
    printf("Init alive at %ld\n", time(NULL));
    sleep(5);
}
// If this stops printing, init died
```

## 2. Console Issues

### 2.1 No Output on Serial Console

**Check 1: Kernel console setting**
```bash
# U-Boot bootargs should include:
console=ttyO0,115200
```

**Check 2: Init console path**
```c
// In init.c, verify CONSOLE path:
#define CONSOLE "/dev/ttyO0"  // BeagleBone
// NOT /dev/ttyS0 (that's x86)
```

**Check 3: Console exists**
```bash
# Boot with shell, check:
ls -la /dev/ttyO*
```

### 2.2 Garbled Output

**Causes:**
- Baud rate mismatch
- Kernel console != init console
- Wrong terminal type

**Solution:**
```bash
# Ensure matching baud rates everywhere:
# U-Boot: 115200
# Kernel: console=ttyO0,115200
# Terminal program: 115200

# In init:
setenv("TERM", "linux", 1);
```

## 3. Zombie Process Issues

### 3.1 Zombie Accumulation

**Symptom:**
```bash
# ps shows many zombies
ps aux | grep Z
```

**Cause:** SIGCHLD not properly handled

**Fix:**
```c
// Correct SIGCHLD handler:
static void sigchld_handler(int sig) {
    (void)sig;
    child_died = 1;  // Just set flag
}

// In main loop:
while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
    // Process exited
}
```

### 3.2 Shell Not Respawning

**Symptom:** Shell exits and doesn't restart

**Fix:**
```c
// Track shell PID
shell_pid = spawn("/bin/sh", ...);

// In reap loop:
if (pid == shell_pid && !shutdown_requested) {
    sleep(1);  // Delay to prevent rapid respawn
    start_shell();
}
```

## 4. Service Issues

### 4.1 Service Fails Silently

**Debug approach:**
```c
// Add verbose logging to spawn():
pid_t spawn(const char *cmd, ...) {
    printf("Spawning: %s\n", cmd);
    
    pid_t pid = fork();
    if (pid == 0) {
        execv(cmd, argv);
        // This only runs if exec fails!
        printf("EXEC FAILED: %s (errno %d: %s)\n", 
               cmd, errno, strerror(errno));
        _exit(127);
    }
    
    if (pid < 0) {
        printf("FORK FAILED: errno %d: %s\n",
               errno, strerror(errno));
    }
    
    return pid;
}
```

### 4.2 Environment Not Set

**Symptom:** Services can't find commands

**Fix:**
```c
// Set PATH before spawning:
setenv("PATH", "/sbin:/bin:/usr/sbin:/usr/bin", 1);

// Or pass environment to execve:
char *envp[] = {
    "PATH=/sbin:/bin:/usr/sbin:/usr/bin",
    "HOME=/root",
    NULL
};
execve(cmd, argv, envp);
```

### 4.3 Script Permission Denied

**Symptom:**
```
/etc/init.d/rcS: Permission denied
```

**Fix:**
```bash
chmod +x /etc/init.d/rcS
chmod +x /etc/init.d/S*
```

## 5. Shutdown Issues

### 5.1 System Hangs on Shutdown

**Symptom:** "System halted" but doesn't power off

**Check:**
```c
// Verify reboot() call:
#include <sys/reboot.h>
#include <linux/reboot.h>

reboot(LINUX_REBOOT_CMD_POWER_OFF);  // For halt
reboot(LINUX_REBOOT_CMD_RESTART);    // For reboot
```

**Note:** Some boards don't support software power-off

### 5.2 Filesystem Corruption After Reboot

**Cause:** Not syncing before reboot

**Fix:**
```c
void do_shutdown(void) {
    // 1. Kill processes
    kill(-1, SIGTERM);
    sleep(2);
    kill(-1, SIGKILL);
    sleep(1);
    
    // 2. Sync MUST be called!
    sync();
    
    // 3. Unmount filesystems
    umount("/tmp");
    umount("/run");
    // ... etc
    
    // 4. Final sync
    sync();
    sleep(1);  // Wait for sync to complete
    
    // 5. Now reboot
    reboot(LINUX_REBOOT_CMD_RESTART);
}
```

## 6. Build Issues

### 6.1 Dynamic Linking Errors

**Symptom:**
```
/sbin/init: error while loading shared libraries
```

**Fix:** Use static linking
```makefile
LDFLAGS = -static
```

### 6.2 Missing System Calls

**Symptom:**
```
undefined reference to 'sethostname'
undefined reference to 'reboot'
```

**Fix:** Include correct headers
```c
#define _GNU_SOURCE  // Must be first!
#include <unistd.h>
#include <sys/reboot.h>
#include <linux/reboot.h>  // For reboot constants
```

### 6.3 Wrong Architecture

**Symptom:**
```
-bash: /sbin/init: cannot execute binary file
```

**Debug:**
```bash
file /sbin/init
# Should show: ELF 32-bit LSB executable, ARM, ...
# Not: ELF 64-bit LSB executable, x86-64, ...
```

**Fix:** Use cross-compiler
```bash
arm-linux-gnueabihf-gcc -static -o init init.c
```

## 7. Debugging Techniques

### 7.1 Boot With Emergency Shell

```bash
# U-Boot:
setenv bootargs 'root=/dev/mmcblk0p2 rootwait init=/bin/sh console=ttyO0,115200'
boot

# Now you have a shell to debug
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Test init manually
/sbin/init &

# Check if running
ps aux | grep init
```

### 7.2 Add Debug Output

```c
// At start of main():
printf("Init started, PID=%d\n", getpid());

// After each step:
printf("Mounted filesystems\n");
printf("Console setup\n");
printf("Starting services\n");

// Flush output
fflush(stdout);
```

### 7.3 Use strace (on host)

```bash
# Build native version
gcc -o init.native init.c

# Trace system calls
sudo strace -f ./init.native

# Note: Won't be PID 1, some things won't work
```

### 7.4 Kernel Debug Messages

```bash
# Add to kernel command line:
debug loglevel=7

# Enable early printk
earlyprintk=serial,ttyO0,115200
```

## 8. Quick Reference

### 8.1 Essential Files Checklist

```
/sbin/init              - Init binary (static, executable)
/bin/sh                 - Shell
/etc/hostname           - Hostname
/etc/init.d/rcS         - Startup script (executable)
/dev/console            - Console device
/dev/null               - Null device
```

### 8.2 Minimal Working init.c

```c
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <linux/reboot.h>

int main(void) {
    if (getpid() != 1) return 1;
    
    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    
    printf("Init running!\n");
    
    while (1) {
        sleep(3600);
    }
    
    return 0;
}
```

### 8.3 Test Commands

```bash
# Check process table
ps aux

# Check mounts
cat /proc/mounts

# Check zombie count
ps aux | grep -c Z

# Send shutdown signal
kill -TERM 1

# Send reboot signal  
kill -USR1 1
```
