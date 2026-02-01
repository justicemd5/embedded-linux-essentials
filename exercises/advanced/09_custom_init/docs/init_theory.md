# Custom Init System Theory and Design Guide
#
# A comprehensive guide to understanding PID 1 and init system design
#
# Author: Embedded Linux Labs

## 1. Understanding PID 1

### 1.1 What is PID 1?

PID 1 (Process ID 1) is the first userspace process started by the Linux kernel
during boot. It has special responsibilities and unique properties that make it
critical to system operation.

```
Kernel Boot Sequence:

Hardware → Bootloader → Kernel → decompress_kernel()
                                         ↓
                              start_kernel()
                                         ↓
                              rest_init()
                                         ↓
                              kernel_init() (PID 1 kernel thread)
                                         ↓
                              run_init_process("/sbin/init")
                                         ↓
                              execve("/sbin/init") ← Your init becomes PID 1
```

### 1.2 Special Properties of PID 1

1. **Cannot Be Killed**: The kernel ignores SIGKILL and SIGSTOP sent to PID 1
   - Only signals with registered handlers are delivered
   - This is a safety mechanism

2. **Orphan Reaper**: All orphaned processes become children of PID 1
   - When a parent dies, its children are "reparented" to init
   - Init must call wait()/waitpid() to reap zombies

3. **System Crash on Exit**: If PID 1 exits, the kernel panics
   - There's no recovery mechanism
   - Init must never exit

4. **Default Signal Handling**: Different from normal processes
   - SIGCHLD: Ignored by default (but we want to handle it)
   - Most signals: Ignored unless handler is installed

### 1.3 Zombie Processes Explained

```
Process Lifecycle:

  fork()          exec()         exit()         wait()
    |               |              |              |
    v               v              v              v
[Created] ---> [Running] ---> [Zombie] ---> [Reaped]
                                  ↑              ↑
                            Process died    Parent called
                            but entry in    wait() - entry
                            process table   removed
                            still exists
```

A zombie process:
- Has completed execution (exit() called)
- Still has an entry in process table
- Consumes a PID (limited resource!)
- Waiting for parent to read exit status

If init doesn't reap zombies:
- Process table fills up
- No new processes can be created
- System becomes unusable

## 2. Init System Responsibilities

### 2.1 Boot-Time Responsibilities

```
┌─────────────────────────────────────────────────────────────────┐
│                     INIT BOOT SEQUENCE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Mount Essential Filesystems                                 │
│     └─► /proc, /sys, /dev, /tmp, /run                          │
│                                                                 │
│  2. Set Up Console                                             │
│     └─► Open /dev/console or /dev/ttyO0                        │
│     └─► Redirect stdin/stdout/stderr                            │
│                                                                 │
│  3. Set Hostname                                                │
│     └─► Read /etc/hostname                                     │
│     └─► Call sethostname()                                     │
│                                                                 │
│  4. Set Up Environment                                          │
│     └─► PATH, HOME, TERM, USER                                 │
│                                                                 │
│  5. Run Startup Scripts                                         │
│     └─► /etc/init.d/rcS                                        │
│     └─► /etc/init.d/S* (in order)                              │
│                                                                 │
│  6. Start Services                                              │
│     └─► syslogd, network, SSH, etc.                            │
│                                                                 │
│  7. Start Login Shell/Getty                                     │
│     └─► /bin/sh or /sbin/getty                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Runtime Responsibilities

```
┌─────────────────────────────────────────────────────────────────┐
│                    INIT RUNTIME LOOP                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  while (1) {                                                    │
│                                                                 │
│      wait_for_signal();      ← Pause, waiting for events       │
│                                                                 │
│      if (SIGCHLD received)   ← Child process died              │
│          reap_zombies();     ← Clean up process table          │
│          maybe_respawn();    ← Restart services if needed      │
│                                                                 │
│      if (SIGTERM received)   ← Shutdown requested              │
│          do_shutdown();      ← Halt system                     │
│                                                                 │
│      if (SIGUSR1 received)   ← Reboot requested                │
│          do_reboot();        ← Reboot system                   │
│                                                                 │
│      check_services();       ← Health monitoring               │
│      kick_watchdog();        ← Hardware watchdog               │
│  }                                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Shutdown Responsibilities

```
┌─────────────────────────────────────────────────────────────────┐
│                   SHUTDOWN SEQUENCE                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Stop accepting new processes                                │
│                                                                 │
│  2. Send SIGTERM to all processes                               │
│     └─► Graceful shutdown request                              │
│     └─► Wait 2-5 seconds                                       │
│                                                                 │
│  3. Send SIGKILL to remaining processes                         │
│     └─► Force terminate                                        │
│     └─► Wait for reaping                                       │
│                                                                 │
│  4. Sync filesystems                                            │
│     └─► sync() - flush buffers to disk                         │
│                                                                 │
│  5. Unmount filesystems                                         │
│     └─► In reverse order of mounting                           │
│     └─► umount() each one                                      │
│                                                                 │
│  6. Final sync                                                  │
│     └─► One more sync() for safety                             │
│                                                                 │
│  7. Halt/Reboot                                                 │
│     └─► reboot(LINUX_REBOOT_CMD_POWER_OFF)                     │
│     └─► reboot(LINUX_REBOOT_CMD_RESTART)                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 3. Essential Filesystems

### 3.1 /proc (procfs)

Virtual filesystem providing process and kernel information.

```
/proc/
├── 1/                  ← Process 1 (init) info
│   ├── cmdline         ← Command line arguments
│   ├── status          ← Process status
│   ├── fd/             ← File descriptors
│   └── maps            ← Memory mappings
├── cpuinfo             ← CPU information
├── meminfo             ← Memory statistics
├── modules             ← Loaded kernel modules
├── mounts              ← Mounted filesystems
├── cmdline             ← Kernel command line
├── sys/                ← Sysctl parameters
│   ├── kernel/
│   └── net/
└── version             ← Kernel version
```

Mount command:
```c
mount("proc", "/proc", "proc", MS_NOEXEC | MS_NOSUID | MS_NODEV, NULL);
```

### 3.2 /sys (sysfs)

Virtual filesystem exposing kernel objects and device information.

```
/sys/
├── class/              ← Device classes
│   ├── gpio/           ← GPIO pins
│   ├── leds/           ← LED devices
│   ├── net/            ← Network interfaces
│   └── pwm/            ← PWM channels
├── devices/            ← Device hierarchy
├── bus/                ← Bus types
│   ├── i2c/
│   ├── spi/
│   └── usb/
├── firmware/           ← Firmware interfaces
│   └── devicetree/     ← Device tree
└── kernel/             ← Kernel parameters
```

Mount command:
```c
mount("sysfs", "/sys", "sysfs", MS_NOEXEC | MS_NOSUID | MS_NODEV, NULL);
```

### 3.3 /dev (devtmpfs)

Device files for hardware access.

```
/dev/
├── console             ← System console
├── null                ← Data sink (/dev/null)
├── zero                ← Zero bytes source
├── random              ← Random number generator (blocking)
├── urandom             ← Random number generator (non-blocking)
├── tty                 ← Current terminal
├── ttyO0               ← BeagleBone serial port
├── mmcblk0             ← MMC/SD card
│   ├── mmcblk0p1       ← Partition 1 (boot)
│   └── mmcblk0p2       ← Partition 2 (rootfs)
├── pts/                ← Pseudo-terminals
└── shm/                ← Shared memory
```

Mount command:
```c
mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755");
```

### 3.4 Mount Flags

| Flag | Description |
|------|-------------|
| MS_NOEXEC | Disallow program execution |
| MS_NOSUID | Ignore setuid/setgid bits |
| MS_NODEV | Disallow device file access |
| MS_RDONLY | Mount read-only |
| MS_REMOUNT | Remount with new options |

## 4. Signal Handling

### 4.1 Signals Used by Init

| Signal | Number | Purpose |
|--------|--------|---------|
| SIGCHLD | 17 | Child process terminated |
| SIGTERM | 15 | Graceful shutdown |
| SIGKILL | 9 | Forced termination (ignored for PID 1) |
| SIGUSR1 | 10 | Custom: Reboot request |
| SIGUSR2 | 12 | Custom: Various uses |
| SIGHUP | 1 | Hangup/reload config |
| SIGINT | 2 | Interrupt (Ctrl-C) |

### 4.2 Signal Handler Setup

```c
#include <signal.h>

/* Signal handler for SIGCHLD */
static void sigchld_handler(int sig) {
    (void)sig;  /* Unused */
    
    /* Set flag to reap in main loop */
    child_died = 1;
}

/* Setup */
struct sigaction sa;
memset(&sa, 0, sizeof(sa));
sa.sa_handler = sigchld_handler;
sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;
sigaction(SIGCHLD, &sa, NULL);
```

### 4.3 Safe Signal Handling

Signal handlers should be minimal:
- Don't call non-async-safe functions (malloc, printf, etc.)
- Only set flags or use sig_atomic_t variables
- Do actual work in main loop

```c
/* Wrong - printf is not async-signal-safe! */
static void bad_handler(int sig) {
    printf("Signal received!\n");  /* Dangerous! */
}

/* Correct - set flag only */
static volatile sig_atomic_t got_signal = 0;

static void good_handler(int sig) {
    (void)sig;
    got_signal = 1;
}

/* Main loop checks and processes */
while (1) {
    if (got_signal) {
        got_signal = 0;
        printf("Signal received!\n");  /* Safe here */
    }
}
```

## 5. Process Management

### 5.1 fork() and exec()

```c
pid_t spawn(const char *cmd, char *const argv[]) {
    pid_t pid = fork();
    
    if (pid == 0) {
        /* Child process */
        
        /* Reset signal handlers to default */
        signal(SIGCHLD, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        
        /* Execute command */
        execv(cmd, argv);
        
        /* If exec fails */
        _exit(127);
    }
    
    /* Parent returns child PID (or -1 on error) */
    return pid;
}
```

### 5.2 Reaping Zombies

```c
void reap_zombies(void) {
    int status;
    pid_t pid;
    
    /* Non-blocking wait for all dead children */
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        if (WIFEXITED(status)) {
            printf("Process %d exited with status %d\n",
                   pid, WEXITSTATUS(status));
        } else if (WIFSIGNALED(status)) {
            printf("Process %d killed by signal %d\n",
                   pid, WTERMSIG(status));
        }
        
        /* Check if it was a service and respawn if needed */
        check_service_respawn(pid);
    }
}
```

### 5.3 Process Table

```
/proc/[pid]/stat contents:

pid   comm   state   ppid   pgrp   session   tty_nr   tpgid ...
1     (init) S       0      1      1         0        -1

State codes:
  R - Running
  S - Sleeping (interruptible)
  D - Sleeping (uninterruptible) 
  Z - Zombie
  T - Stopped
  X - Dead
```

## 6. Console Setup

### 6.1 Opening the Console

```c
void setup_console(void) {
    int fd;
    
    /* Close inherited file descriptors */
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    
    /* Open console device */
    fd = open("/dev/ttyO0", O_RDWR | O_NOCTTY);
    if (fd < 0) {
        fd = open("/dev/console", O_RDWR | O_NOCTTY);
    }
    
    if (fd < 0) {
        /* Last resort - /dev/null */
        fd = open("/dev/null", O_RDWR);
    }
    
    /* Set as stdin (fd 0) */
    dup2(fd, STDIN_FILENO);
    
    /* Set as stdout (fd 1) */
    dup2(fd, STDOUT_FILENO);
    
    /* Set as stderr (fd 2) */
    dup2(fd, STDERR_FILENO);
    
    /* Close original if > 2 */
    if (fd > STDERR_FILENO) {
        close(fd);
    }
    
    /* Create new session */
    setsid();
    
    /* Set controlling terminal */
    ioctl(STDIN_FILENO, TIOCSCTTY, 1);
}
```

### 6.2 File Descriptors

```
Standard file descriptors:

  FD 0 (stdin)  ──────────────────┐
                                  │
  FD 1 (stdout) ──────────────────┼────► /dev/ttyO0
                                  │
  FD 2 (stderr) ──────────────────┘

After dup2(fd, 0), dup2(fd, 1), dup2(fd, 2):
  - All three point to same terminal
  - Allows printf() to display on serial console
  - Allows read() from keyboard/serial
```

## 7. System Calls Reference

### 7.1 Process-Related

| Call | Purpose |
|------|---------|
| fork() | Create child process |
| execve() | Replace process with new program |
| waitpid() | Wait for child state change |
| kill() | Send signal to process |
| exit() | Terminate process |
| setsid() | Create new session |
| setpgid() | Set process group |

### 7.2 Filesystem-Related

| Call | Purpose |
|------|---------|
| mount() | Mount filesystem |
| umount() | Unmount filesystem |
| sync() | Flush filesystem buffers |
| mkdir() | Create directory |
| open() | Open file/device |
| close() | Close file descriptor |
| read() | Read from file |
| write() | Write to file |
| dup2() | Duplicate file descriptor |

### 7.3 System-Related

| Call | Purpose |
|------|---------|
| reboot() | Halt/reboot system |
| sethostname() | Set system hostname |
| ioctl() | Device control |
| mknod() | Create device node |

## 8. Comparison with Other Init Systems

### 8.1 Feature Comparison

| Feature | Custom Init | SysVinit | BusyBox init | systemd |
|---------|-------------|----------|--------------|---------|
| Binary Size | ~20KB | ~100KB | ~50KB | ~1MB+ |
| Startup Time | Fast | Medium | Fast | Medium |
| Dependencies | None | libc | BusyBox | Many |
| Service Mgmt | Basic | Scripts | Scripts | Full |
| Parallelism | No | No | No | Yes |
| Sockets | No | No | No | Yes |
| Cgroups | No | No | No | Yes |
| Complexity | Low | Medium | Low | High |

### 8.2 When to Use Custom Init

✅ Use custom init when:
- Minimal system footprint required
- Boot time is critical
- No dynamic service management needed
- Learning/educational purposes
- Resource-constrained embedded systems

❌ Use systemd/OpenRC when:
- Complex service dependencies
- Dynamic device management
- Container support needed
- Desktop/server systems

## 9. Debugging Init

### 9.1 Kernel Command Line

```
init=/sbin/init_debug    # Use debug init
init=/bin/sh             # Emergency shell
debug                    # Enable debug output
console=ttyO0,115200     # Serial console
```

### 9.2 Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| No console | No output | Check console= and init= |
| Zombies | High PID count | Fix SIGCHLD handling |
| No reboot | System hangs | Check shutdown sequence |
| Services fail | Error messages | Check PATH, permissions |

### 9.3 Debugging Techniques

```bash
# Boot with emergency shell
bootargs=init=/bin/sh console=ttyO0,115200

# Then manually test init:
$ mount -t proc proc /proc
$ mount -t sysfs sysfs /sys
$ /sbin/init &
$ ps aux  # See if init is running
```

## 10. Resources

- "Understanding the Linux Kernel" by Bovet & Cesati
- "Linux System Programming" by Robert Love
- kernel.org Documentation: init and process management
- BusyBox init source code
- systemd design documents
