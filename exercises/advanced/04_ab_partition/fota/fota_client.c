/*
 * FOTA Client for A/B Partition System with Falcon Mode
 * Lightweight C implementation for embedded Linux
 *
 * Features:
 *   - Periodic check for firmware updates from server
 *   - Download and verify update bundles (SHA256)
 *   - Apply updates to standby partition slot
 *   - Support for Falcon mode (SPL direct boot)
 *   - Automatic boot success confirmation
 *   - Manual update trigger via file or signal
 *
 * Dependencies:
 *   - libcurl (HTTP/HTTPS client)
 *   - json-c (JSON parsing)
 *   - openssl (SHA256 verification)
 *   - u-boot-tools (fw_setenv/fw_printenv)
 *
 * Build:
 *   arm-linux-gnueabihf-gcc -o fota_client fota_client.c \
 *       -lcurl -ljson-c -lcrypto -Wall -O2
 *
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <fcntl.h>
#include <errno.h>
#include <syslog.h>
#include <signal.h>
#include <time.h>
#include <curl/curl.h>
#include <json-c/json.h>
#include <openssl/sha.h>

#define VERSION "1.0.0"
#define CONFIG_FILE "/etc/fota/fota.conf"
#define STATE_FILE "/data/fota/state.json"
#define DOWNLOAD_DIR "/tmp/fota"
#define CHECK_INTERVAL 3600  /* Default: check every hour */

/* Partition device mappings for BeagleBone Black */
#define BOOT_A "/dev/mmcblk0p1"
#define ROOT_A "/dev/mmcblk0p2"
#define BOOT_B "/dev/mmcblk0p3"
#define ROOT_B "/dev/mmcblk0p5"

/* Mount points for update operations */
#define MNT_BOOT "/tmp/fota_boot"
#define MNT_ROOT "/tmp/fota_root"

/*
 * Configuration structure
 * Loaded from CONFIG_FILE
 */
typedef struct {
    char server_url[256];      /* Base URL of update server */
    char device_id[64];        /* Unique device identifier */
    char current_version[32];  /* Currently installed version */
    char current_slot;         /* Active slot: 'a' or 'b' */
    int check_interval;        /* Seconds between update checks */
    int falcon_enabled;        /* Use Falcon mode (SPL direct boot) */
} fota_config_t;

/*
 * Update manifest structure
 * Received from update server
 */
typedef struct {
    char version[32];          /* New version string */
    char boot_url[512];        /* URL to boot partition archive */
    char boot_sha256[65];      /* Expected SHA256 of boot archive */
    size_t boot_size;          /* Expected size in bytes */
    char rootfs_url[512];      /* URL to rootfs archive */
    char rootfs_sha256[65];    /* Expected SHA256 of rootfs archive */
    size_t rootfs_size;        /* Expected size in bytes */
} update_manifest_t;

/* Global state */
static volatile int running = 1;
static fota_config_t config;

/*
 * Signal handler for graceful shutdown
 */
void signal_handler(int sig)
{
    syslog(LOG_INFO, "Received signal %d, shutting down", sig);
    running = 0;
}

/*
 * CURL callback: Write data to file
 */
static size_t write_file_callback(void *ptr, size_t size, size_t nmemb, void *stream)
{
    return fwrite(ptr, size, nmemb, (FILE *)stream);
}

/*
 * CURL callback: Accumulate data in memory
 */
struct memory_chunk {
    char *memory;
    size_t size;
};

static size_t write_memory_callback(void *contents, size_t size, size_t nmemb, void *userp)
{
    size_t realsize = size * nmemb;
    struct memory_chunk *mem = (struct memory_chunk *)userp;

    char *ptr = realloc(mem->memory, mem->size + realsize + 1);
    if (!ptr) {
        syslog(LOG_ERR, "Out of memory in CURL callback");
        return 0;
    }

    mem->memory = ptr;
    memcpy(&(mem->memory[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->memory[mem->size] = 0;

    return realsize;
}

/*
 * Calculate SHA256 hash of a file
 * Returns 0 on success, -1 on failure
 */
int calculate_sha256(const char *filename, char *hash_out)
{
    FILE *fp = fopen(filename, "rb");
    if (!fp) {
        syslog(LOG_ERR, "Cannot open file for hashing: %s", filename);
        return -1;
    }

    SHA256_CTX ctx;
    SHA256_Init(&ctx);

    unsigned char buffer[8192];
    size_t bytes;

    while ((bytes = fread(buffer, 1, sizeof(buffer), fp)) > 0) {
        SHA256_Update(&ctx, buffer, bytes);
    }
    fclose(fp);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256_Final(hash, &ctx);

    /* Convert to hex string */
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        sprintf(hash_out + (i * 2), "%02x", hash[i]);
    }
    hash_out[64] = '\0';

    return 0;
}

/*
 * Read current slot from U-Boot environment
 */
char get_current_slot(void)
{
    FILE *fp = popen("fw_printenv -n slot 2>/dev/null", "r");
    if (!fp)
        return 'a';

    char slot = 'a';
    if (fscanf(fp, "%c", &slot) != 1) {
        slot = 'a';
    }
    pclose(fp);

    return (slot == 'b') ? 'b' : 'a';
}

/*
 * Get standby slot information
 */
void get_standby_slot(char current, char *standby,
                      const char **boot_dev, const char **root_dev)
{
    if (current == 'a') {
        *standby = 'b';
        *boot_dev = BOOT_B;
        *root_dev = ROOT_B;
    } else {
        *standby = 'a';
        *boot_dev = BOOT_A;
        *root_dev = ROOT_A;
    }
}

/*
 * Download a file from URL to local path
 * Returns 0 on success, -1 on failure
 */
int download_file(const char *url, const char *dest, size_t expected_size)
{
    CURL *curl = curl_easy_init();
    if (!curl) {
        syslog(LOG_ERR, "Failed to initialize CURL");
        return -1;
    }

    FILE *fp = fopen(dest, "wb");
    if (!fp) {
        syslog(LOG_ERR, "Cannot create file: %s", dest);
        curl_easy_cleanup(curl);
        return -1;
    }

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_file_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, fp);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 600L);  /* 10 minute timeout */
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_FAILONERROR, 1L);

    /* Progress callback could be added here */

    CURLcode res = curl_easy_perform(curl);
    fclose(fp);

    if (res != CURLE_OK) {
        syslog(LOG_ERR, "Download failed: %s", curl_easy_strerror(res));
        unlink(dest);
        curl_easy_cleanup(curl);
        return -1;
    }

    /* Verify size if expected_size > 0 */
    if (expected_size > 0) {
        struct stat st;
        if (stat(dest, &st) == 0 && (size_t)st.st_size != expected_size) {
            syslog(LOG_ERR, "Size mismatch: expected %zu, got %ld",
                   expected_size, st.st_size);
            unlink(dest);
            curl_easy_cleanup(curl);
            return -1;
        }
    }

    curl_easy_cleanup(curl);
    return 0;
}

/*
 * Check for updates from server
 * Returns: 1 = update available, 0 = no update, -1 = error
 */
int check_for_update(update_manifest_t *manifest)
{
    char url[512];
    snprintf(url, sizeof(url), "%s/api/v1/devices/%s/update",
             config.server_url, config.device_id);

    CURL *curl = curl_easy_init();
    if (!curl)
        return -1;

    struct memory_chunk chunk = {0};
    chunk.memory = malloc(1);
    chunk.size = 0;

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_memory_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);

    /* Add headers with device info */
    struct curl_slist *headers = NULL;
    char version_header[64];
    snprintf(version_header, sizeof(version_header),
             "X-Current-Version: %s", config.current_version);
    headers = curl_slist_append(headers, version_header);

    char slot_header[32];
    snprintf(slot_header, sizeof(slot_header),
             "X-Current-Slot: %c", config.current_slot);
    headers = curl_slist_append(headers, slot_header);

    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    CURLcode res = curl_easy_perform(curl);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) {
        syslog(LOG_WARNING, "Update check failed: %s", curl_easy_strerror(res));
        free(chunk.memory);
        return -1;
    }

    /* Parse JSON response */
    struct json_object *root = json_tokener_parse(chunk.memory);
    free(chunk.memory);

    if (!root) {
        syslog(LOG_ERR, "Failed to parse update response");
        return -1;
    }

    struct json_object *update_available;
    if (!json_object_object_get_ex(root, "update_available", &update_available) ||
        !json_object_get_boolean(update_available)) {
        json_object_put(root);
        return 0;  /* No update available */
    }

    /* Extract manifest data */
    struct json_object *obj;

    if (json_object_object_get_ex(root, "version", &obj))
        strncpy(manifest->version, json_object_get_string(obj), 31);

    if (json_object_object_get_ex(root, "boot_url", &obj))
        strncpy(manifest->boot_url, json_object_get_string(obj), 511);

    if (json_object_object_get_ex(root, "boot_sha256", &obj))
        strncpy(manifest->boot_sha256, json_object_get_string(obj), 64);

    if (json_object_object_get_ex(root, "boot_size", &obj))
        manifest->boot_size = json_object_get_int64(obj);

    if (json_object_object_get_ex(root, "rootfs_url", &obj))
        strncpy(manifest->rootfs_url, json_object_get_string(obj), 511);

    if (json_object_object_get_ex(root, "rootfs_sha256", &obj))
        strncpy(manifest->rootfs_sha256, json_object_get_string(obj), 64);

    if (json_object_object_get_ex(root, "rootfs_size", &obj))
        manifest->rootfs_size = json_object_get_int64(obj);

    json_object_put(root);

    syslog(LOG_INFO, "Update available: %s -> %s",
           config.current_version, manifest->version);

    return 1;  /* Update available */
}

/*
 * Apply update to standby slot
 * Returns 0 on success, -1 on failure
 */
int apply_update(update_manifest_t *manifest)
{
    char standby_slot;
    const char *boot_dev, *root_dev;
    char cmd[512];
    char hash[65];

    get_standby_slot(config.current_slot, &standby_slot, &boot_dev, &root_dev);

    syslog(LOG_INFO, "Applying update v%s to slot %c",
           manifest->version, standby_slot);

    /* Create download directory */
    mkdir(DOWNLOAD_DIR, 0755);

    /* Download and verify boot archive */
    char boot_file[256];
    snprintf(boot_file, sizeof(boot_file), "%s/boot.tar.gz", DOWNLOAD_DIR);

    syslog(LOG_INFO, "Downloading boot files...");
    if (download_file(manifest->boot_url, boot_file, manifest->boot_size) < 0) {
        syslog(LOG_ERR, "Failed to download boot files");
        return -1;
    }

    if (calculate_sha256(boot_file, hash) < 0 ||
        strcmp(hash, manifest->boot_sha256) != 0) {
        syslog(LOG_ERR, "Boot archive checksum mismatch");
        syslog(LOG_ERR, "  Expected: %s", manifest->boot_sha256);
        syslog(LOG_ERR, "  Got:      %s", hash);
        return -1;
    }
    syslog(LOG_INFO, "Boot archive verified");

    /* Download and verify rootfs archive */
    char rootfs_file[256];
    snprintf(rootfs_file, sizeof(rootfs_file), "%s/rootfs.tar.gz", DOWNLOAD_DIR);

    syslog(LOG_INFO, "Downloading rootfs...");
    if (download_file(manifest->rootfs_url, rootfs_file, manifest->rootfs_size) < 0) {
        syslog(LOG_ERR, "Failed to download rootfs");
        return -1;
    }

    if (calculate_sha256(rootfs_file, hash) < 0 ||
        strcmp(hash, manifest->rootfs_sha256) != 0) {
        syslog(LOG_ERR, "Rootfs archive checksum mismatch");
        return -1;
    }
    syslog(LOG_INFO, "Rootfs archive verified");

    /* Flash boot partition */
    syslog(LOG_INFO, "Flashing boot partition %s...", boot_dev);
    mkdir(MNT_BOOT, 0755);

    snprintf(cmd, sizeof(cmd), "mount %s %s", boot_dev, MNT_BOOT);
    if (system(cmd) != 0) {
        syslog(LOG_ERR, "Failed to mount boot partition");
        return -1;
    }

    snprintf(cmd, sizeof(cmd), "rm -rf %s/* && tar xzf %s -C %s/",
             MNT_BOOT, boot_file, MNT_BOOT);
    system(cmd);

    sync();
    umount(MNT_BOOT);

    /* Flash rootfs partition */
    syslog(LOG_INFO, "Formatting and flashing rootfs %s...", root_dev);

    snprintf(cmd, sizeof(cmd), "mkfs.ext4 -F -L ROOT_%c %s",
             standby_slot - 32, root_dev);  /* Uppercase label */
    if (system(cmd) != 0) {
        syslog(LOG_ERR, "Failed to format rootfs partition");
        return -1;
    }

    mkdir(MNT_ROOT, 0755);
    snprintf(cmd, sizeof(cmd), "mount %s %s", root_dev, MNT_ROOT);
    if (system(cmd) != 0) {
        syslog(LOG_ERR, "Failed to mount rootfs partition");
        return -1;
    }

    snprintf(cmd, sizeof(cmd), "tar xzf %s -C %s/", rootfs_file, MNT_ROOT);
    system(cmd);

    sync();
    umount(MNT_ROOT);

    /* Cleanup downloads */
    unlink(boot_file);
    unlink(rootfs_file);
    rmdir(DOWNLOAD_DIR);

    /* Update U-Boot environment to switch slots */
    syslog(LOG_INFO, "Switching to slot %c...", standby_slot);

    snprintf(cmd, sizeof(cmd), "fw_setenv slot %c", standby_slot);
    system(cmd);

    system("fw_setenv bootcount 0");

    /* Update Falcon slot if enabled */
    if (config.falcon_enabled) {
        snprintf(cmd, sizeof(cmd), "fw_setenv falcon_slot %c", standby_slot);
        system(cmd);

        /* Mark that Falcon args need regeneration */
        snprintf(cmd, sizeof(cmd),
                 "fw_setenv falcon_prepare_%c_pending 1", standby_slot);
        system(cmd);
    }

    /* Save pending update state */
    mkdir("/data/fota", 0755);
    snprintf(cmd, sizeof(cmd),
             "echo '{\"pending_version\":\"%s\",\"pending_slot\":\"%c\"}' > %s",
             manifest->version, standby_slot, STATE_FILE);
    system(cmd);

    syslog(LOG_INFO, "Update applied successfully, rebooting...");

    sync();
    sleep(2);
    system("reboot");

    return 0;
}

/*
 * Load configuration from file
 */
int load_config(void)
{
    FILE *fp = fopen(CONFIG_FILE, "r");
    if (!fp) {
        syslog(LOG_ERR, "Cannot open config file: %s", CONFIG_FILE);
        return -1;
    }

    /* Set defaults */
    memset(&config, 0, sizeof(config));
    config.check_interval = CHECK_INTERVAL;

    char line[512];
    while (fgets(line, sizeof(line), fp)) {
        /* Skip comments and empty lines */
        if (line[0] == '#' || line[0] == '\n')
            continue;

        char key[64], value[256];
        if (sscanf(line, "%63[^=]=%255[^\n]", key, value) == 2) {
            if (strcmp(key, "server_url") == 0)
                strncpy(config.server_url, value, sizeof(config.server_url) - 1);
            else if (strcmp(key, "device_id") == 0)
                strncpy(config.device_id, value, sizeof(config.device_id) - 1);
            else if (strcmp(key, "current_version") == 0)
                strncpy(config.current_version, value, sizeof(config.current_version) - 1);
            else if (strcmp(key, "check_interval") == 0)
                config.check_interval = atoi(value);
            else if (strcmp(key, "falcon_enabled") == 0)
                config.falcon_enabled = atoi(value);
        }
    }
    fclose(fp);

    /* Get current slot from U-Boot */
    config.current_slot = get_current_slot();

    /* Validate required fields */
    if (config.server_url[0] == '\0' || config.device_id[0] == '\0') {
        syslog(LOG_ERR, "Missing required config: server_url or device_id");
        return -1;
    }

    return 0;
}

/*
 * Mark current boot as successful
 * Called after system is stable
 */
void mark_boot_success(void)
{
    /* Reset boot counter */
    system("fw_setenv bootcount 0");

    /* Check for pending update to confirm */
    FILE *fp = fopen(STATE_FILE, "r");
    if (fp) {
        char buffer[512];
        size_t len = fread(buffer, 1, sizeof(buffer) - 1, fp);
        fclose(fp);
        buffer[len] = '\0';

        struct json_object *root = json_tokener_parse(buffer);
        if (root) {
            struct json_object *version;
            if (json_object_object_get_ex(root, "pending_version", &version)) {
                const char *new_version = json_object_get_string(version);

                /* Update version in config file */
                char cmd[512];
                snprintf(cmd, sizeof(cmd),
                         "sed -i 's/current_version=.*/current_version=%s/' %s",
                         new_version, CONFIG_FILE);
                system(cmd);

                syslog(LOG_INFO, "Boot confirmed, version updated to %s", new_version);
            }
            json_object_put(root);
        }
        unlink(STATE_FILE);
    }
}

/*
 * Check for manual update trigger
 */
void check_manual_trigger(void)
{
    const char *trigger_file = "/tmp/fota_trigger";

    if (access(trigger_file, F_OK) == 0) {
        syslog(LOG_INFO, "Manual update trigger detected");
        unlink(trigger_file);

        update_manifest_t manifest = {0};
        if (check_for_update(&manifest) > 0) {
            apply_update(&manifest);
        }
    }
}

/*
 * Print usage information
 */
void print_usage(const char *progname)
{
    printf("FOTA Client v%s\n", VERSION);
    printf("Firmware Over-The-Air update daemon for A/B partition systems\n\n");
    printf("Usage: %s [options]\n\n", progname);
    printf("Options:\n");
    printf("  -f, --foreground  Run in foreground (don't daemonize)\n");
    printf("  -c, --check       Check for update once and exit\n");
    printf("  -s, --success     Mark current boot as successful\n");
    printf("  -v, --version     Show version and exit\n");
    printf("  -h, --help        Show this help message\n");
}

/*
 * Main entry point
 */
int main(int argc, char *argv[])
{
    int daemon_mode = 1;
    int force_check = 0;

    /* Parse command line arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-f") == 0 || strcmp(argv[i], "--foreground") == 0) {
            daemon_mode = 0;
        } else if (strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "--check") == 0) {
            force_check = 1;
            daemon_mode = 0;
        } else if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "--success") == 0) {
            openlog("fota", LOG_PID, LOG_DAEMON);
            load_config();
            mark_boot_success();
            closelog();
            return 0;
        } else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--version") == 0) {
            printf("FOTA Client v%s\n", VERSION);
            return 0;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    /* Initialize logging */
    openlog("fota", LOG_PID, LOG_DAEMON);

    /* Initialize CURL globally */
    curl_global_init(CURL_GLOBAL_ALL);

    /* Set up signal handlers */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    /* Load configuration */
    if (load_config() < 0) {
        syslog(LOG_ERR, "Failed to load configuration");
        return 1;
    }

    syslog(LOG_INFO, "FOTA Client v%s started (slot=%c, version=%s)",
           VERSION, config.current_slot, config.current_version);

    /* Single check mode */
    if (force_check) {
        update_manifest_t manifest = {0};
        int result = check_for_update(&manifest);

        if (result > 0) {
            printf("Update available: %s -> %s\n",
                   config.current_version, manifest.version);
            apply_update(&manifest);
        } else if (result == 0) {
            printf("No update available (current: %s)\n", config.current_version);
        } else {
            printf("Update check failed\n");
            return 1;
        }
        return 0;
    }

    /* Daemonize if requested */
    if (daemon_mode) {
        if (daemon(0, 0) < 0) {
            syslog(LOG_ERR, "Failed to daemonize: %s", strerror(errno));
            return 1;
        }
    }

    /* Mark previous boot as successful */
    mark_boot_success();

    /* Main daemon loop */
    time_t last_check = 0;

    while (running) {
        time_t now = time(NULL);

        /* Check for manual trigger file */
        check_manual_trigger();

        /* Periodic update check */
        if (now - last_check >= config.check_interval) {
            update_manifest_t manifest = {0};

            if (check_for_update(&manifest) > 0) {
                apply_update(&manifest);
                /* If we get here, apply_update didn't reboot - something failed */
            }

            last_check = now;
        }

        sleep(60);  /* Check triggers every minute */
    }

    /* Cleanup */
    curl_global_cleanup();
    closelog();

    return 0;
}
