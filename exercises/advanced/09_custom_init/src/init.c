/*
 * init.c - Minimal Custom Init System for BeagleBone Black
 * 
 * This is a bare-bones init system that demonstrates
 * the minimum requirements for PID 1 (the first process).
 *
 * Responsibilities of PID 1:
 *   - Mount essential filesystems (/proc, /sys, /dev)
 *   - Set up console/terminal
 *   - Run startup scripts
 *   - Start and manage services
 *   - Reap zombie processes (orphaned children)
 *   - Handle shutdown/reboot signals
 *   - NEVER EXIT (would cause kernel panic)
 *
 * Author: Embedded Linux Labs
 * License: MIT
 *
 * Build:
 *   arm-linux-gnueabihf-gcc -static -o init init.c
 *
 * Install:
 *   cp init /sbin/init
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
#include <sys/ioctl.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <termios.h>
#include <linux/reboot.h>

/* Configuration */
#define CONSOLE         "/dev/ttyO0"        /* BeagleBone serial console */
#define CONSOLE_BACKUP  "/dev/console"
#define SHELL           "/bin/sh"
#define HOSTNAME_FILE   "/etc/hostname"
#define RCS_SCRIPT      "/etc/init.d/rcS"
#define INIT_D_DIR      "/etc/init.d"

/* ANSI colors for pretty output */
#define COL_RESET   "\033[0m"
#define COL_GREEN   "\033[1;32m"
#define COL_YELLOW  "\033[1;33m"
#define COL_RED     "\033[1;31m"
#define COL_BLUE    "\033[1;34m"

/*
 * Service structure for simple service management
 */
struct service {
    const char *name;
    const char *cmd;
    const char *args;
    pid_t pid;
    int respawn;        /* Restart if dies */
    int started;
};

/* Services to start (modify as needed) */
static struct service services[] = {
    { "syslogd",  "/sbin/syslogd",       "-n",     0, 1, 0 },
    { "klogd",    "/sbin/klogd",         "-n",     0, 1, 0 },
    { "dropbear", "/usr/sbin/dropbear",  "-F",     0, 1, 0 },
    { NULL, NULL, NULL, 0, 0, 0 }
};

/* Global flags for shutdown */
static volatile sig_atomic_t shutdown_requested = 0;
static volatile sig_atomic_t reboot_requested = 0;
static volatile sig_atomic_t child_died = 0;

/* Shell PID for respawning */
static pid_t shell_pid = 0;

/* Forward declarations */
static void mount_filesystems(void);
static void setup_console(void);
static void setup_hostname(void);
static void setup_environment(void);
static void run_startup_scripts(void);
static void start_services(void);
static void start_shell(void);
static void reap_children(void);
static void handle_shutdown(void);
static pid_t spawn(const char *cmd, char *const argv[], char *const envp[]);

/*
 * Signal handlers
 */
static void sigchld_handler(int sig)
{
    (void)sig;
    child_died = 1;
}

static void sigterm_handler(int sig)
{
    (void)sig;
    shutdown_requested = 1;
    reboot_requested = 0;
}

static void sigusr1_handler(int sig)
{
    (void)sig;
    shutdown_requested = 1;
    reboot_requested = 1;
}

/*
 * Print functions with color
 */
static void print_banner(void)
{
    printf("\n");
    printf(COL_BLUE);
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║                                                               ║\n");
    printf("║   ╔╗ ┌─┐┌─┐┌─┐┬  ┌─┐╔╗ ┌─┐┌┐┌┌─┐  ╔╗ ┬  ┌─┐┌─┐┬┌─            ║\n");
    printf("║   ╠╩╗├┤ ├─┤│ ┬│  ├┤ ╠╩╗│ ││││├┤   ╠╩╗│  ├─┤│  ├┴┐            ║\n");
    printf("║   ╚═╝└─┘┴ ┴└─┘┴─┘└─┘╚═╝└─┘┘└┘└─┘  ╚═╝┴─┘┴ ┴└─┘┴ ┴            ║\n");
    printf("║                                                               ║\n");
    printf("║            Custom Init System v1.0                            ║\n");
    printf("║                                                               ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf(COL_RESET);
    printf("\n");
}

static void log_ok(const char *msg)
{
    printf(COL_GREEN "[  OK  ]" COL_RESET " %s\n", msg);
}

static void log_fail(const char *msg)
{
    printf(COL_RED "[ FAIL ]" COL_RESET " %s\n", msg);
}

static void log_warn(const char *msg)
{
    printf(COL_YELLOW "[ WARN ]" COL_RESET " %s\n", msg);
}

static void log_info(const char *msg)
{
    printf("[ INFO ] %s\n", msg);
}

/*
 * Mount essential filesystems
 */
static void mount_filesystems(void)
{
    int errors = 0;
    
    log_info("Mounting filesystems...");
    
    /* Create mount points */
    mkdir("/proc", 0555);
    mkdir("/sys", 0555);
    mkdir("/dev", 0755);
    mkdir("/dev/pts", 0755);
    mkdir("/dev/shm", 1777);
    mkdir("/tmp", 01777);
    mkdir("/run", 0755);
    mkdir("/var", 0755);
    mkdir("/var/log", 0755);
    mkdir("/var/run", 0755);
    
    /* Mount procfs */
    if (mount("proc", "/proc", "proc", MS_NOEXEC | MS_NOSUID | MS_NODEV, NULL) != 0) {
        if (errno != EBUSY) {
            log_fail("Mount /proc");
            errors++;
        }
    }
    
    /* Mount sysfs */
    if (mount("sysfs", "/sys", "sysfs", MS_NOEXEC | MS_NOSUID | MS_NODEV, NULL) != 0) {
        if (errno != EBUSY) {
            log_fail("Mount /sys");
            errors++;
        }
    }
    
    /* Mount devtmpfs (kernel will populate with devices) */
    if (mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755") != 0) {
        if (errno != EBUSY) {
            /* Fallback to tmpfs */
            if (mount("tmpfs", "/dev", "tmpfs", MS_NOSUID, "mode=0755") != 0) {
                log_fail("Mount /dev");
                errors++;
            }
        }
    }
    
    /* Mount devpts for pseudo-terminals */
    if (mount("devpts", "/dev/pts", "devpts", MS_NOSUID | MS_NOEXEC,
              "gid=5,mode=620,ptmxmode=000") != 0) {
        if (errno != EBUSY) {
            log_warn("Mount /dev/pts (PTY may not work)");
        }
    }
    
    /* Mount shared memory */
    mount("tmpfs", "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
    
    /* Mount tmpfs for temporary files */
    mount("tmpfs", "/tmp", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
    mount("tmpfs", "/run", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755");
    
    /* Create symlink /var/run -> /run */
    symlink("/run", "/var/run");
    
    /* Create essential device nodes if devtmpfs didn't */
    mknod("/dev/console", S_IFCHR | 0600, makedev(5, 1));
    mknod("/dev/null", S_IFCHR | 0666, makedev(1, 3));
    mknod("/dev/zero", S_IFCHR | 0666, makedev(1, 5));
    mknod("/dev/random", S_IFCHR | 0666, makedev(1, 8));
    mknod("/dev/urandom", S_IFCHR | 0666, makedev(1, 9));
    mknod("/dev/tty", S_IFCHR | 0666, makedev(5, 0));
    mknod("/dev/ptmx", S_IFCHR | 0666, makedev(5, 2));
    
    /* Symlinks for compatibility */
    symlink("/proc/self/fd", "/dev/fd");
    symlink("/proc/self/fd/0", "/dev/stdin");
    symlink("/proc/self/fd/1", "/dev/stdout");
    symlink("/proc/self/fd/2", "/dev/stderr");
    
    if (errors == 0) {
        log_ok("Filesystems mounted");
    } else {
        log_warn("Some filesystems failed to mount");
    }
}

/*
 * Set up console for input/output
 */
static void setup_console(void)
{
    int fd;
    struct termios tty;
    
    log_info("Setting up console...");
    
    /* Close inherited file descriptors */
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    
    /* Try primary console first, then backup */
    fd = open(CONSOLE, O_RDWR | O_NOCTTY);
    if (fd < 0) {
        fd = open(CONSOLE_BACKUP, O_RDWR | O_NOCTTY);
    }
    
    if (fd >= 0) {
        /* Set up stdin/stdout/stderr */
        dup2(fd, STDIN_FILENO);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        if (fd > STDERR_FILENO) {
            close(fd);
        }
        
        /* Create new session and set controlling terminal */
        setsid();
        ioctl(STDIN_FILENO, TIOCSCTTY, 1);
        
        /* Configure terminal */
        if (tcgetattr(STDIN_FILENO, &tty) == 0) {
            tty.c_cc[VTIME] = 0;
            tty.c_cc[VMIN] = 1;
            tcsetattr(STDIN_FILENO, TCSANOW, &tty);
        }
        
        log_ok("Console ready");
    } else {
        /* Last resort - can't output anywhere */
    }
}

/*
 * Set hostname from /etc/hostname
 */
static void setup_hostname(void)
{
    FILE *fp;
    char hostname[64] = "beaglebone";
    char msg[128];
    
    fp = fopen(HOSTNAME_FILE, "r");
    if (fp) {
        if (fgets(hostname, sizeof(hostname), fp)) {
            hostname[strcspn(hostname, "\r\n")] = '\0';
        }
        fclose(fp);
    }
    
    if (sethostname(hostname, strlen(hostname)) == 0) {
        snprintf(msg, sizeof(msg), "Hostname: %s", hostname);
        log_ok(msg);
    } else {
        log_fail("Set hostname");
    }
}

/*
 * Set up environment variables
 */
static void setup_environment(void)
{
    setenv("PATH", "/sbin:/bin:/usr/sbin:/usr/bin", 1);
    setenv("HOME", "/root", 1);
    setenv("TERM", "linux", 1);
    setenv("USER", "root", 1);
    setenv("LOGNAME", "root", 1);
    setenv("SHELL", SHELL, 1);
}

/*
 * Spawn a new process
 */
static pid_t spawn(const char *cmd, char *const argv[], char *const envp[])
{
    pid_t pid = fork();
    
    if (pid == 0) {
        /* Child process */
        
        /* Reset signal handlers */
        signal(SIGCHLD, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGUSR1, SIG_DFL);
        
        /* Execute */
        if (envp) {
            execve(cmd, argv, envp);
        } else {
            execv(cmd, argv);
        }
        
        /* If exec fails */
        _exit(127);
    }
    
    return pid;
}

/*
 * Run startup scripts
 */
static void run_startup_scripts(void)
{
    log_info("Running startup scripts...");
    
    /* Run rcS if it exists */
    if (access(RCS_SCRIPT, X_OK) == 0) {
        char *argv[] = { "/bin/sh", RCS_SCRIPT, NULL };
        pid_t pid = spawn("/bin/sh", argv, NULL);
        
        if (pid > 0) {
            int status;
            waitpid(pid, &status, 0);
            
            if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
                log_ok("Startup scripts completed");
            } else {
                log_warn("Startup scripts had errors");
            }
        }
    } else {
        log_warn("No startup scripts found");
    }
}

/*
 * Start system services
 */
static void start_services(void)
{
    char msg[128];
    
    log_info("Starting services...");
    
    for (int i = 0; services[i].name != NULL; i++) {
        if (access(services[i].cmd, X_OK) == 0) {
            char *argv[4];
            argv[0] = (char *)services[i].cmd;
            argv[1] = (char *)services[i].args;
            argv[2] = NULL;
            
            services[i].pid = spawn(services[i].cmd, argv, NULL);
            
            if (services[i].pid > 0) {
                services[i].started = 1;
                snprintf(msg, sizeof(msg), "Started %s (pid %d)", 
                         services[i].name, services[i].pid);
                log_ok(msg);
            } else {
                snprintf(msg, sizeof(msg), "Failed to start %s", 
                         services[i].name);
                log_fail(msg);
            }
        }
    }
}

/*
 * Start login shell
 */
static void start_shell(void)
{
    char *argv[] = { "-sh", NULL };  /* Leading dash = login shell */
    char *envp[] = {
        "HOME=/root",
        "PATH=/sbin:/bin:/usr/sbin:/usr/bin",
        "TERM=linux",
        "USER=root",
        "LOGNAME=root",
        "SHELL=/bin/sh",
        NULL
    };
    
    printf("\n");
    printf(COL_GREEN "════════════════════════════════════════════════════════════════\n");
    printf("  System Ready - Starting Shell\n");
    printf("════════════════════════════════════════════════════════════════\n" COL_RESET);
    printf("\n");
    
    shell_pid = fork();
    
    if (shell_pid == 0) {
        /* Child - become shell */
        
        /* Reset signals */
        signal(SIGCHLD, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGUSR1, SIG_DFL);
        
        /* Execute shell */
        execve(SHELL, argv, envp);
        
        /* If exec fails */
        perror("init: exec shell");
        _exit(127);
    }
    
    if (shell_pid > 0) {
        log_ok("Shell started");
    } else {
        log_fail("Could not start shell");
    }
}

/*
 * Reap zombie processes and respawn services
 */
static void reap_children(void)
{
    int status;
    pid_t pid;
    char msg[128];
    
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        /* Check if it was the shell */
        if (pid == shell_pid && !shutdown_requested) {
            snprintf(msg, sizeof(msg), "Shell (pid %d) died, respawning...", pid);
            log_warn(msg);
            sleep(1);  /* Prevent rapid respawn */
            start_shell();
            continue;
        }
        
        /* Check if it was a service */
        for (int i = 0; services[i].name != NULL; i++) {
            if (services[i].pid == pid) {
                snprintf(msg, sizeof(msg), "Service %s (pid %d) died", 
                         services[i].name, pid);
                log_warn(msg);
                
                if (services[i].respawn && !shutdown_requested) {
                    sleep(1);
                    char *argv[4];
                    argv[0] = (char *)services[i].cmd;
                    argv[1] = (char *)services[i].args;
                    argv[2] = NULL;
                    services[i].pid = spawn(services[i].cmd, argv, NULL);
                    
                    if (services[i].pid > 0) {
                        snprintf(msg, sizeof(msg), "Respawned %s (pid %d)", 
                                 services[i].name, services[i].pid);
                        log_ok(msg);
                    }
                }
                break;
            }
        }
    }
    
    child_died = 0;
}

/*
 * Handle shutdown/reboot
 */
static void handle_shutdown(void)
{
    log_info("Initiating shutdown sequence...");
    
    /* Send SIGTERM to all processes */
    log_info("Sending SIGTERM to all processes...");
    kill(-1, SIGTERM);
    sleep(2);
    
    /* Send SIGKILL to any remaining */
    log_info("Sending SIGKILL to remaining processes...");
    kill(-1, SIGKILL);
    sleep(1);
    
    /* Sync filesystems */
    log_info("Syncing filesystems...");
    sync();
    sleep(1);
    
    /* Unmount filesystems */
    log_info("Unmounting filesystems...");
    umount("/tmp");
    umount("/run");
    umount("/dev/shm");
    umount("/dev/pts");
    umount("/dev");
    umount("/sys");
    umount("/proc");
    
    /* Final sync */
    sync();
    
    if (reboot_requested) {
        printf("\n" COL_YELLOW "Rebooting system..." COL_RESET "\n");
        reboot(LINUX_REBOOT_CMD_RESTART);
    } else {
        printf("\n" COL_YELLOW "System halted." COL_RESET "\n");
        reboot(LINUX_REBOOT_CMD_POWER_OFF);
    }
}

/*
 * Main init function
 */
int main(int argc, char *argv[])
{
    (void)argc;
    (void)argv;
    
    /* Verify we are PID 1 */
    if (getpid() != 1) {
        fprintf(stderr, "init: must be run as PID 1\n");
        return 1;
    }
    
    /* Set up signal handlers */
    signal(SIGCHLD, sigchld_handler);
    signal(SIGTERM, sigterm_handler);
    signal(SIGUSR1, sigusr1_handler);
    signal(SIGINT, SIG_IGN);     /* Ignore Ctrl-C */
    signal(SIGHUP, SIG_IGN);     /* Ignore hangup */
    
    /* Initialize */
    mount_filesystems();
    setup_console();
    print_banner();
    setup_environment();
    setup_hostname();
    run_startup_scripts();
    start_services();
    start_shell();
    
    /* Main loop - wait for signals and reap children */
    log_info("Init entering main loop");
    
    while (!shutdown_requested) {
        /* Wait for signal or timeout */
        usleep(100000);  /* 100ms */
        
        /* Reap any dead children */
        if (child_died) {
            reap_children();
        }
    }
    
    /* Shutdown */
    handle_shutdown();
    
    /* Should never reach here */
    while (1) {
        pause();
    }
    
    return 0;
}
