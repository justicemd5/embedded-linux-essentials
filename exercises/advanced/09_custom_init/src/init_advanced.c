/*
 * init_advanced.c - Advanced Custom Init System with Service Management
 * 
 * Enhanced init system with:
 *   - Configuration file parsing (/etc/init.conf)
 *   - Service management (start/stop/restart/status)
 *   - Dependency handling
 *   - Run levels support
 *   - Health monitoring
 *   - Watchdog support
 *
 * Author: Embedded Linux Labs
 * License: MIT
 *
 * Build:
 *   arm-linux-gnueabihf-gcc -static -o init init_advanced.c
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
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <termios.h>
#include <time.h>
#include <linux/reboot.h>
#include <linux/watchdog.h>

/*
 * ========================================================================
 * CONFIGURATION
 * ========================================================================
 */

/* Configuration file */
#define CONFIG_FILE     "/etc/init.conf"
#define SERVICES_DIR    "/etc/init.d"
#define PID_DIR         "/var/run"

/* Console configuration */
#define CONSOLE         "/dev/ttyO0"
#define CONSOLE_BACKUP  "/dev/console"

/* Limits */
#define MAX_SERVICES    32
#define MAX_LINE        256
#define MAX_NAME        64
#define MAX_PATH        256

/* Run levels */
#define RUNLEVEL_HALT       0
#define RUNLEVEL_SINGLE     1
#define RUNLEVEL_MULTI      2
#define RUNLEVEL_NETWORK    3
#define RUNLEVEL_FULL       5
#define RUNLEVEL_REBOOT     6

/* Service states */
#define SVC_STOPPED     0
#define SVC_STARTING    1
#define SVC_RUNNING     2
#define SVC_STOPPING    3
#define SVC_FAILED      4

/* Service flags */
#define SVC_FLAG_RESPAWN    (1 << 0)    /* Restart if dies */
#define SVC_FLAG_WAIT       (1 << 1)    /* Wait for completion */
#define SVC_FLAG_CRITICAL   (1 << 2)    /* System crashes if fails */
#define SVC_FLAG_ONESHOT    (1 << 3)    /* Run once, don't monitor */

/* Colors */
#define COL_RESET   "\033[0m"
#define COL_GREEN   "\033[1;32m"
#define COL_YELLOW  "\033[1;33m"
#define COL_RED     "\033[1;31m"
#define COL_BLUE    "\033[1;34m"
#define COL_CYAN    "\033[1;36m"

/*
 * ========================================================================
 * DATA STRUCTURES
 * ========================================================================
 */

/* Service definition */
struct service {
    char name[MAX_NAME];
    char cmd[MAX_PATH];
    char pidfile[MAX_PATH];
    int runlevel;           /* Minimum runlevel to start */
    int flags;              /* Service flags */
    int state;              /* Current state */
    pid_t pid;              /* Process ID when running */
    time_t start_time;      /* When started */
    int restart_count;      /* Number of restarts */
    int max_restarts;       /* Maximum restarts before giving up */
    int restart_delay;      /* Seconds between restarts */
    char *depends[8];       /* Service dependencies */
    int depend_count;
};

/* Init configuration */
struct init_config {
    char hostname[MAX_NAME];
    int default_runlevel;
    int enable_watchdog;
    char watchdog_device[MAX_PATH];
    int watchdog_timeout;
    int enable_logging;
    char logfile[MAX_PATH];
    int respawn_delay;
};

/*
 * ========================================================================
 * GLOBAL STATE
 * ========================================================================
 */

static struct service services[MAX_SERVICES];
static int service_count = 0;

static struct init_config config = {
    .hostname = "beaglebone",
    .default_runlevel = RUNLEVEL_FULL,
    .enable_watchdog = 0,
    .watchdog_device = "/dev/watchdog",
    .watchdog_timeout = 30,
    .enable_logging = 1,
    .logfile = "/var/log/init.log",
    .respawn_delay = 3,
};

static int current_runlevel = RUNLEVEL_SINGLE;
static int target_runlevel = RUNLEVEL_FULL;

static volatile sig_atomic_t shutdown_requested = 0;
static volatile sig_atomic_t reboot_requested = 0;
static volatile sig_atomic_t child_died = 0;
static volatile sig_atomic_t runlevel_change = 0;

static int watchdog_fd = -1;
static FILE *logfile = NULL;

/*
 * ========================================================================
 * UTILITY FUNCTIONS
 * ========================================================================
 */

/* Get current timestamp as string */
static char *timestamp(void)
{
    static char buf[32];
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", t);
    return buf;
}

/* Log message */
static void log_msg(int level, const char *fmt, ...)
{
    va_list ap;
    const char *prefix;
    const char *color;
    
    switch (level) {
        case 0: prefix = "ERROR"; color = COL_RED; break;
        case 1: prefix = "WARN "; color = COL_YELLOW; break;
        case 2: prefix = "INFO "; color = COL_GREEN; break;
        case 3: prefix = "DEBUG"; color = COL_CYAN; break;
        default: prefix = "     "; color = ""; break;
    }
    
    /* Console output */
    printf("%s[%s]%s ", color, prefix, COL_RESET);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    printf("\n");
    
    /* File output */
    if (logfile) {
        fprintf(logfile, "[%s] [%s] ", timestamp(), prefix);
        va_start(ap, fmt);
        vfprintf(logfile, fmt, ap);
        va_end(ap);
        fprintf(logfile, "\n");
        fflush(logfile);
    }
}

#define log_error(...)  log_msg(0, __VA_ARGS__)
#define log_warn(...)   log_msg(1, __VA_ARGS__)
#define log_info(...)   log_msg(2, __VA_ARGS__)
#define log_debug(...)  log_msg(3, __VA_ARGS__)

/* Trim whitespace from string */
static char *trim(char *str)
{
    char *end;
    while (*str == ' ' || *str == '\t') str++;
    end = str + strlen(str) - 1;
    while (end > str && (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r'))
        *end-- = '\0';
    return str;
}

/* Read PID from file */
static pid_t read_pidfile(const char *path)
{
    FILE *fp = fopen(path, "r");
    pid_t pid = 0;
    
    if (fp) {
        fscanf(fp, "%d", &pid);
        fclose(fp);
    }
    return pid;
}

/* Check if process is running */
static int is_running(pid_t pid)
{
    if (pid <= 0) return 0;
    return kill(pid, 0) == 0;
}

/*
 * ========================================================================
 * CONFIGURATION PARSING
 * ========================================================================
 */

/* Parse configuration file */
static void parse_config(void)
{
    FILE *fp;
    char line[MAX_LINE];
    char key[MAX_NAME], value[MAX_PATH];
    
    fp = fopen(CONFIG_FILE, "r");
    if (!fp) {
        log_warn("Config file not found, using defaults");
        return;
    }
    
    log_info("Parsing configuration...");
    
    while (fgets(line, sizeof(line), fp)) {
        char *l = trim(line);
        
        /* Skip comments and empty lines */
        if (*l == '#' || *l == '\0') continue;
        
        if (sscanf(l, "%63[^=]=%255s", key, value) == 2) {
            trim(key);
            trim(value);
            
            if (strcmp(key, "hostname") == 0) {
                strncpy(config.hostname, value, MAX_NAME - 1);
            } else if (strcmp(key, "runlevel") == 0) {
                config.default_runlevel = atoi(value);
            } else if (strcmp(key, "watchdog") == 0) {
                config.enable_watchdog = (strcmp(value, "1") == 0 || 
                                         strcmp(value, "true") == 0);
            } else if (strcmp(key, "watchdog_device") == 0) {
                strncpy(config.watchdog_device, value, MAX_PATH - 1);
            } else if (strcmp(key, "watchdog_timeout") == 0) {
                config.watchdog_timeout = atoi(value);
            } else if (strcmp(key, "logging") == 0) {
                config.enable_logging = (strcmp(value, "1") == 0 || 
                                        strcmp(value, "true") == 0);
            } else if (strcmp(key, "respawn_delay") == 0) {
                config.respawn_delay = atoi(value);
            }
        }
    }
    
    fclose(fp);
    
    target_runlevel = config.default_runlevel;
}

/* Parse service file */
static int parse_service_file(const char *path)
{
    FILE *fp;
    char line[MAX_LINE];
    struct service *svc;
    
    if (service_count >= MAX_SERVICES) {
        log_error("Maximum services reached");
        return -1;
    }
    
    fp = fopen(path, "r");
    if (!fp) return -1;
    
    svc = &services[service_count];
    memset(svc, 0, sizeof(*svc));
    
    /* Extract service name from filename */
    const char *name = strrchr(path, '/');
    name = name ? name + 1 : path;
    strncpy(svc->name, name, MAX_NAME - 1);
    
    /* Defaults */
    svc->runlevel = RUNLEVEL_FULL;
    svc->max_restarts = 5;
    svc->restart_delay = config.respawn_delay;
    
    while (fgets(line, sizeof(line), fp)) {
        char *l = trim(line);
        
        if (*l == '#' || *l == '\0') continue;
        
        char key[MAX_NAME], value[MAX_PATH];
        if (sscanf(l, "%63[^=]=%255[^\n]", key, value) == 2) {
            trim(key);
            trim(value);
            
            if (strcmp(key, "command") == 0 || strcmp(key, "cmd") == 0) {
                strncpy(svc->cmd, value, MAX_PATH - 1);
            } else if (strcmp(key, "pidfile") == 0) {
                strncpy(svc->pidfile, value, MAX_PATH - 1);
            } else if (strcmp(key, "runlevel") == 0) {
                svc->runlevel = atoi(value);
            } else if (strcmp(key, "respawn") == 0) {
                if (strcmp(value, "true") == 0 || strcmp(value, "1") == 0)
                    svc->flags |= SVC_FLAG_RESPAWN;
            } else if (strcmp(key, "wait") == 0) {
                if (strcmp(value, "true") == 0 || strcmp(value, "1") == 0)
                    svc->flags |= SVC_FLAG_WAIT;
            } else if (strcmp(key, "critical") == 0) {
                if (strcmp(value, "true") == 0 || strcmp(value, "1") == 0)
                    svc->flags |= SVC_FLAG_CRITICAL;
            } else if (strcmp(key, "oneshot") == 0) {
                if (strcmp(value, "true") == 0 || strcmp(value, "1") == 0)
                    svc->flags |= SVC_FLAG_ONESHOT;
            }
        }
    }
    
    fclose(fp);
    
    if (svc->cmd[0] == '\0') {
        /* No command specified, try script path */
        snprintf(svc->cmd, MAX_PATH, "%s start", path);
    }
    
    service_count++;
    log_debug("Loaded service: %s", svc->name);
    
    return 0;
}

/* Load all services from /etc/init.d */
static void load_services(void)
{
    DIR *dir;
    struct dirent *entry;
    char path[MAX_PATH];
    
    log_info("Loading services from %s...", SERVICES_DIR);
    
    dir = opendir(SERVICES_DIR);
    if (!dir) {
        log_warn("Cannot open services directory");
        return;
    }
    
    while ((entry = readdir(dir)) != NULL) {
        /* Look for S* files (startup scripts) */
        if (entry->d_name[0] == 'S' && entry->d_name[1] >= '0' && entry->d_name[1] <= '9') {
            snprintf(path, sizeof(path), "%s/%s", SERVICES_DIR, entry->d_name);
            
            struct stat st;
            if (stat(path, &st) == 0 && (st.st_mode & S_IXUSR)) {
                /* Create a simple service for the script */
                struct service *svc = &services[service_count];
                memset(svc, 0, sizeof(*svc));
                
                strncpy(svc->name, entry->d_name, MAX_NAME - 1);
                snprintf(svc->cmd, MAX_PATH, "%s start", path);
                svc->runlevel = RUNLEVEL_FULL;
                svc->flags = SVC_FLAG_ONESHOT;
                svc->state = SVC_STOPPED;
                
                service_count++;
                log_debug("Added startup script: %s", svc->name);
            }
        }
    }
    
    closedir(dir);
    log_info("Loaded %d services", service_count);
}

/*
 * ========================================================================
 * SERVICE MANAGEMENT
 * ========================================================================
 */

/* Find service by name */
static struct service *find_service(const char *name)
{
    for (int i = 0; i < service_count; i++) {
        if (strcmp(services[i].name, name) == 0) {
            return &services[i];
        }
    }
    return NULL;
}

/* Start a service */
static int start_service(struct service *svc)
{
    pid_t pid;
    char *argv[4];
    
    if (svc->state == SVC_RUNNING) {
        log_debug("Service %s already running", svc->name);
        return 0;
    }
    
    /* Check if command exists */
    if (access(svc->cmd, X_OK) != 0) {
        /* Try to find executable in path */
        char *space = strchr(svc->cmd, ' ');
        if (space) {
            *space = '\0';
            if (access(svc->cmd, X_OK) != 0) {
                *space = ' ';
                log_warn("Command not found: %s", svc->cmd);
                svc->state = SVC_FAILED;
                return -1;
            }
            *space = ' ';
        }
    }
    
    log_info("Starting %s...", svc->name);
    svc->state = SVC_STARTING;
    
    pid = fork();
    
    if (pid == 0) {
        /* Child process */
        
        /* Reset signals */
        signal(SIGCHLD, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGUSR1, SIG_DFL);
        
        /* Execute via shell */
        argv[0] = "/bin/sh";
        argv[1] = "-c";
        argv[2] = svc->cmd;
        argv[3] = NULL;
        
        execv("/bin/sh", argv);
        _exit(127);
    }
    
    if (pid < 0) {
        log_error("Failed to fork for %s", svc->name);
        svc->state = SVC_FAILED;
        return -1;
    }
    
    svc->pid = pid;
    svc->start_time = time(NULL);
    
    /* Wait for oneshot services */
    if (svc->flags & SVC_FLAG_WAIT) {
        int status;
        waitpid(pid, &status, 0);
        
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            svc->state = SVC_STOPPED;  /* Oneshot completed */
            log_info("Completed %s", svc->name);
        } else {
            svc->state = SVC_FAILED;
            log_error("Failed %s (exit %d)", svc->name, 
                     WIFEXITED(status) ? WEXITSTATUS(status) : -1);
            return -1;
        }
    } else {
        svc->state = SVC_RUNNING;
        log_info("Started %s (pid %d)", svc->name, pid);
    }
    
    return 0;
}

/* Stop a service */
static int stop_service(struct service *svc)
{
    int status;
    
    if (svc->state != SVC_RUNNING) {
        return 0;
    }
    
    log_info("Stopping %s...", svc->name);
    svc->state = SVC_STOPPING;
    
    /* Try graceful shutdown */
    kill(svc->pid, SIGTERM);
    
    /* Wait up to 5 seconds */
    for (int i = 0; i < 50; i++) {
        usleep(100000);
        if (waitpid(svc->pid, &status, WNOHANG) > 0) {
            svc->state = SVC_STOPPED;
            svc->pid = 0;
            log_info("Stopped %s", svc->name);
            return 0;
        }
    }
    
    /* Force kill */
    log_warn("Force killing %s", svc->name);
    kill(svc->pid, SIGKILL);
    waitpid(svc->pid, &status, 0);
    
    svc->state = SVC_STOPPED;
    svc->pid = 0;
    
    return 0;
}

/* Restart a service */
static int restart_service(struct service *svc)
{
    stop_service(svc);
    sleep(1);
    return start_service(svc);
}

/* Start all services for current runlevel */
static void start_all_services(void)
{
    log_info("Starting services for runlevel %d...", current_runlevel);
    
    for (int i = 0; i < service_count; i++) {
        if (services[i].runlevel <= current_runlevel) {
            start_service(&services[i]);
        }
    }
}

/* Stop all services */
static void stop_all_services(void)
{
    log_info("Stopping all services...");
    
    /* Stop in reverse order */
    for (int i = service_count - 1; i >= 0; i--) {
        stop_service(&services[i]);
    }
}

/* Check service health and respawn if needed */
static void check_services(void)
{
    for (int i = 0; i < service_count; i++) {
        struct service *svc = &services[i];
        
        if (svc->state == SVC_RUNNING) {
            /* Check if still running */
            if (!is_running(svc->pid)) {
                log_warn("Service %s (pid %d) died", svc->name, svc->pid);
                svc->state = SVC_STOPPED;
                
                /* Respawn if configured */
                if ((svc->flags & SVC_FLAG_RESPAWN) && !shutdown_requested) {
                    if (svc->restart_count < svc->max_restarts) {
                        log_info("Respawning %s (attempt %d/%d)", 
                                svc->name, svc->restart_count + 1, svc->max_restarts);
                        sleep(svc->restart_delay);
                        start_service(svc);
                        svc->restart_count++;
                    } else {
                        log_error("Service %s exceeded max restarts", svc->name);
                        svc->state = SVC_FAILED;
                        
                        if (svc->flags & SVC_FLAG_CRITICAL) {
                            log_error("Critical service failed, rebooting!");
                            reboot_requested = 1;
                            shutdown_requested = 1;
                        }
                    }
                }
            }
        }
    }
}

/*
 * ========================================================================
 * WATCHDOG
 * ========================================================================
 */

static void setup_watchdog(void)
{
    if (!config.enable_watchdog) return;
    
    log_info("Setting up watchdog...");
    
    watchdog_fd = open(config.watchdog_device, O_WRONLY);
    if (watchdog_fd < 0) {
        log_warn("Cannot open watchdog device");
        return;
    }
    
    /* Set timeout */
    ioctl(watchdog_fd, WDIOC_SETTIMEOUT, &config.watchdog_timeout);
    
    log_info("Watchdog enabled (timeout %ds)", config.watchdog_timeout);
}

static void kick_watchdog(void)
{
    if (watchdog_fd >= 0) {
        write(watchdog_fd, "k", 1);
    }
}

static void stop_watchdog(void)
{
    if (watchdog_fd >= 0) {
        /* Write 'V' to disable watchdog */
        write(watchdog_fd, "V", 1);
        close(watchdog_fd);
        watchdog_fd = -1;
    }
}

/*
 * ========================================================================
 * SYSTEM SETUP
 * ========================================================================
 */

static void mount_filesystems(void)
{
    log_info("Mounting filesystems...");
    
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
    
    mount("proc", "/proc", "proc", MS_NOEXEC | MS_NOSUID | MS_NODEV, NULL);
    mount("sysfs", "/sys", "sysfs", MS_NOEXEC | MS_NOSUID | MS_NODEV, NULL);
    mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755");
    mount("devpts", "/dev/pts", "devpts", MS_NOSUID | MS_NOEXEC, "gid=5,mode=620");
    mount("tmpfs", "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
    mount("tmpfs", "/tmp", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
    mount("tmpfs", "/run", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755");
    
    symlink("/run", "/var/run");
    symlink("/proc/self/fd", "/dev/fd");
    symlink("/proc/self/fd/0", "/dev/stdin");
    symlink("/proc/self/fd/1", "/dev/stdout");
    symlink("/proc/self/fd/2", "/dev/stderr");
    
    log_info("Filesystems mounted");
}

static void setup_console(void)
{
    int fd;
    
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    
    fd = open(CONSOLE, O_RDWR | O_NOCTTY);
    if (fd < 0) {
        fd = open(CONSOLE_BACKUP, O_RDWR | O_NOCTTY);
    }
    
    if (fd >= 0) {
        dup2(fd, STDIN_FILENO);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        if (fd > STDERR_FILENO) close(fd);
        
        setsid();
        ioctl(STDIN_FILENO, TIOCSCTTY, 1);
    }
}

static void setup_logging(void)
{
    if (!config.enable_logging) return;
    
    logfile = fopen(config.logfile, "a");
    if (logfile) {
        fprintf(logfile, "\n=== Init started at %s ===\n", timestamp());
        fflush(logfile);
    }
}

static void setup_hostname(void)
{
    sethostname(config.hostname, strlen(config.hostname));
    log_info("Hostname: %s", config.hostname);
}

static void setup_environment(void)
{
    setenv("PATH", "/sbin:/bin:/usr/sbin:/usr/bin", 1);
    setenv("HOME", "/root", 1);
    setenv("TERM", "linux", 1);
}

/*
 * ========================================================================
 * SIGNAL HANDLERS
 * ========================================================================
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

static void reap_children(void)
{
    int status;
    pid_t pid;
    
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        for (int i = 0; i < service_count; i++) {
            if (services[i].pid == pid) {
                log_debug("Service %s exited", services[i].name);
                services[i].pid = 0;
                if (services[i].state == SVC_RUNNING) {
                    services[i].state = SVC_STOPPED;
                }
                break;
            }
        }
    }
    child_died = 0;
}

/*
 * ========================================================================
 * SHUTDOWN
 * ========================================================================
 */

static void do_shutdown(void)
{
    log_info("Initiating shutdown...");
    
    stop_watchdog();
    stop_all_services();
    
    log_info("Sending SIGTERM to all processes...");
    kill(-1, SIGTERM);
    sleep(2);
    
    log_info("Sending SIGKILL to remaining processes...");
    kill(-1, SIGKILL);
    sleep(1);
    
    sync();
    
    log_info("Unmounting filesystems...");
    umount("/tmp");
    umount("/run");
    umount("/dev/shm");
    umount("/dev/pts");
    umount("/dev");
    umount("/sys");
    umount("/proc");
    
    sync();
    
    if (logfile) {
        fprintf(logfile, "=== Init stopped at %s ===\n", timestamp());
        fclose(logfile);
    }
    
    if (reboot_requested) {
        printf("\n" COL_YELLOW "Rebooting..." COL_RESET "\n");
        reboot(LINUX_REBOOT_CMD_RESTART);
    } else {
        printf("\n" COL_YELLOW "System halted." COL_RESET "\n");
        reboot(LINUX_REBOOT_CMD_POWER_OFF);
    }
}

/*
 * ========================================================================
 * MAIN
 * ========================================================================
 */

static void print_banner(void)
{
    printf("\n");
    printf(COL_BLUE "╔══════════════════════════════════════════════════════╗\n");
    printf("║         Advanced Init System v2.0                    ║\n");
    printf("║         BeagleBone Black                             ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n" COL_RESET);
    printf("\n");
}

int main(int argc, char *argv[])
{
    (void)argc;
    (void)argv;
    
    /* Verify PID 1 */
    if (getpid() != 1) {
        fprintf(stderr, "init: must be run as PID 1\n");
        return 1;
    }
    
    /* Set up signals */
    signal(SIGCHLD, sigchld_handler);
    signal(SIGTERM, sigterm_handler);
    signal(SIGUSR1, sigusr1_handler);
    signal(SIGINT, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    
    /* Initialize */
    mount_filesystems();
    setup_console();
    print_banner();
    parse_config();
    setup_logging();
    setup_environment();
    setup_hostname();
    setup_watchdog();
    
    /* Load and start services */
    load_services();
    current_runlevel = target_runlevel;
    start_all_services();
    
    log_info("System ready (runlevel %d)", current_runlevel);
    
    /* Main loop */
    while (!shutdown_requested) {
        usleep(100000);  /* 100ms */
        
        if (child_died) {
            reap_children();
        }
        
        check_services();
        kick_watchdog();
    }
    
    /* Shutdown */
    do_shutdown();
    
    /* Never reach here */
    while (1) pause();
    
    return 0;
}
