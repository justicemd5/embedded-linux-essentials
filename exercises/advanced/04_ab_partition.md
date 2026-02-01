# Exercise 4: A/B Partition Scheme

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Create a robust A/B update system with automatic fallback for reliable OTA updates.

## Prerequisites

- 8GB or larger microSD card
- U-Boot source with ability to modify environment
- Understanding of partition tables
- Two complete rootfs images

## Difficulty: ⭐⭐⭐⭐ Expert

---

## Tasks

1. Design and create partition layout
2. Implement U-Boot boot counter logic
3. Create update mechanism
4. Test failure recovery

---

## A/B System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    A/B UPDATE SYSTEM                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Slot A    │    │   Slot B    │    │ Persistent  │     │
│  │  (Active)   │    │  (Standby)  │    │    Data     │     │
│  │             │    │             │    │             │     │
│  │  ┌───────┐  │    │  ┌───────┐  │    │  /data      │     │
│  │  │ Boot  │  │    │  │ Boot  │  │    │  /config    │     │
│  │  │ (p1)  │  │    │  │ (p3)  │  │    │  /logs      │     │
│  │  └───────┘  │    │  └───────┘  │    │             │     │
│  │  ┌───────┐  │    │  ┌───────┐  │    │             │     │
│  │  │ Root  │  │    │  │ Root  │  │    │             │     │
│  │  │ (p2)  │  │    │  │ (p4)  │  │    │             │     │
│  │  └───────┘  │    │  └───────┘  │    │             │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│                                                             │
│  Normal: Boot from active slot                              │
│  Update: Write to standby slot, mark pending                │
│  Reboot: Try new slot with boot counter                     │
│  Success: Mark new slot active                              │
│  Failure: Automatic rollback after bootlimit               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Guide

### Step 1: Create Partition Layout

**Partition table for 8GB SD card:**

```bash
# On Linux host with SD card at /dev/sdX
sudo fdisk /dev/sdX

# Create partitions:
# p1: 64MB  FAT32 - Boot A (MLO, u-boot.img, zImage, DTB)
# p2: 2GB   ext4  - Root A
# p3: 64MB  FAT32 - Boot B
# p4: 2GB   ext4  - Root B
# p5: 1GB   ext4  - Persistent Data
# p6: 8MB   (raw) - U-Boot env (optional, can use file)

# Commands:
n, p, 1, <enter>, +64M    # Boot A
n, p, 2, <enter>, +2G     # Root A  
n, p, 3, <enter>, +64M    # Boot B
n, e, 4, <enter>, <enter> # Extended partition for rest
n, l, <enter>, +2G        # Root B (now p5)
n, l, <enter>, +1G        # Data (now p6)
t, 1, c                   # Set p1 to FAT32
t, 3, c                   # Set p3 to FAT32
w                         # Write and exit
```

**Format partitions:**

```bash
sudo mkfs.vfat -F 32 -n BOOT_A /dev/sdX1
sudo mkfs.ext4 -L ROOT_A /dev/sdX2
sudo mkfs.vfat -F 32 -n BOOT_B /dev/sdX3
sudo mkfs.ext4 -L ROOT_B /dev/sdX5
sudo mkfs.ext4 -L DATA /dev/sdX6
```

### Step 2: Populate Initial Partitions

```bash
# Mount partitions
sudo mkdir -p /mnt/{boot_a,root_a,boot_b,root_b,data}
sudo mount /dev/sdX1 /mnt/boot_a
sudo mount /dev/sdX2 /mnt/root_a
sudo mount /dev/sdX3 /mnt/boot_b
sudo mount /dev/sdX5 /mnt/root_b

# Copy boot files to both slots
sudo cp MLO u-boot.img zImage am335x-boneblack.dtb /mnt/boot_a/
sudo cp MLO u-boot.img zImage am335x-boneblack.dtb /mnt/boot_b/

# Copy rootfs to both slots
sudo tar xf rootfs.tar -C /mnt/root_a/
sudo tar xf rootfs.tar -C /mnt/root_b/

# Create data partition structure
sudo mkdir -p /mnt/data/{config,logs,user}

# Unmount
sudo umount /mnt/{boot_a,root_a,boot_b,root_b,data}
```

### Step 3: Configure U-Boot A/B Logic

**Set up environment variables on BBB:**

```bash
# Connect via serial console
screen /dev/ttyACM0 115200

# Stop at U-Boot prompt (press key during boot)
# Set up A/B variables
```

**U-Boot environment script:**

```bash
# Active slot (a or b)
setenv slot a

# Boot attempt limit before switching slots
setenv bootlimit 3

# Current boot attempt counter
setenv bootcount 0

# A/B slot selection logic
setenv ab_select '
    if test ${bootcount} -ge ${bootlimit}; then
        echo "=== Slot ${slot} failed ${bootlimit} times, switching ===";
        if test ${slot} = a; then
            setenv slot b;
        else
            setenv slot a;
        fi;
        setenv bootcount 0;
        saveenv;
        echo "=== Now booting from slot ${slot} ===";
    fi;
    setexpr bootcount ${bootcount} + 1;
    saveenv;
'

# Set partition numbers based on slot
setenv set_slot_parts '
    if test ${slot} = a; then
        setenv bootpart 1;
        setenv rootpart 2;
        echo "Booting from Slot A (p1/p2)";
    else
        setenv bootpart 3;
        setenv rootpart 5;
        echo "Booting from Slot B (p3/p5)";
    fi;
'

# Main boot command for selected slot
setenv boot_slot '
    fatload mmc 0:${bootpart} ${loadaddr} zImage;
    fatload mmc 0:${bootpart} ${fdtaddr} am335x-boneblack.dtb;
    setenv bootargs console=ttyO0,115200n8 root=/dev/mmcblk0p${rootpart} rootwait rw;
    bootz ${loadaddr} - ${fdtaddr};
'

# Recovery boot (tries both slots)
setenv boot_recovery '
    echo "=== RECOVERY MODE ===";
    setenv slot a;
    setenv bootcount 0;
    saveenv;
    run set_slot_parts;
    run boot_slot;
'

# Master boot command
setenv bootcmd 'run ab_select; run set_slot_parts; run boot_slot'

# Save everything
saveenv
```

### Step 4: Create Boot Success Marker

**On target rootfs - /etc/init.d/boot-success:**

```bash
#!/bin/sh
### BEGIN INIT INFO
# Provides:          boot-success
# Required-Start:    $local_fs $network
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: Mark boot as successful
### END INIT INFO

UBOOT_ENV="/dev/mmcblk0"
ENV_OFFSET=0x260000  # Adjust based on your layout

reset_bootcount() {
    # Using fw_setenv (U-Boot tools)
    if command -v fw_setenv > /dev/null; then
        fw_setenv bootcount 0
        logger "boot-success: Reset bootcount to 0"
    else
        logger "boot-success: fw_setenv not found, cannot reset bootcount"
    fi
}

case "$1" in
    start)
        # Wait for system to be stable
        sleep 10
        
        # Check if critical services are running
        if systemctl is-active --quiet networking || \
           [ -f /var/run/network-up ]; then
            reset_bootcount
        else
            logger "boot-success: Network not ready, not marking success"
        fi
        ;;
    *)
        echo "Usage: $0 {start}"
        exit 1
        ;;
esac
```

**Install fw_setenv on rootfs:**

```bash
# On host, cross-compile u-boot-tools
cd u-boot
make CROSS_COMPILE=arm-linux-gnueabihf- envtools

# Copy to rootfs
cp tools/env/fw_printenv rootfs/usr/bin/
ln -s fw_printenv rootfs/usr/bin/fw_setenv

# Create config file
cat > rootfs/etc/fw_env.config << 'EOF'
# Device         Offset    Size    Erase Size
/dev/mmcblk0     0x260000  0x20000  0x20000
EOF
```

### Step 5: Create Update Script

**/usr/bin/ota-update.sh:**

```bash
#!/bin/bash
# OTA Update Script for A/B partition system

set -e

UPDATE_URL="$1"
TEMP_DIR="/tmp/update"

# Determine standby slot
CURRENT_SLOT=$(fw_printenv -n slot)
if [ "$CURRENT_SLOT" = "a" ]; then
    STANDBY_SLOT="b"
    STANDBY_BOOT="/dev/mmcblk0p3"
    STANDBY_ROOT="/dev/mmcblk0p5"
else
    STANDBY_SLOT="a"
    STANDBY_BOOT="/dev/mmcblk0p1"
    STANDBY_ROOT="/dev/mmcblk0p2"
fi

echo "Current slot: $CURRENT_SLOT"
echo "Updating standby slot: $STANDBY_SLOT"

# Download update
mkdir -p $TEMP_DIR
cd $TEMP_DIR
wget -O update.tar.gz "$UPDATE_URL"

# Extract update
tar xzf update.tar.gz

# Update boot partition
echo "Updating boot partition..."
mount $STANDBY_BOOT /mnt
cp -v boot/* /mnt/
umount /mnt

# Update root partition
echo "Updating root partition..."
mkfs.ext4 -F -L ROOT_$STANDBY_SLOT $STANDBY_ROOT
mount $STANDBY_ROOT /mnt
tar xf rootfs.tar -C /mnt
umount /mnt

# Switch to new slot
echo "Switching to slot $STANDBY_SLOT..."
fw_setenv slot $STANDBY_SLOT
fw_setenv bootcount 0

# Cleanup
rm -rf $TEMP_DIR

echo "Update complete! Rebooting..."
reboot
```

---

## Test Scenarios

### Test 1: Normal Boot Cycle

```bash
# Verify boot from slot A
fw_printenv slot
# Expected: slot=a

# Verify bootcount resets
fw_printenv bootcount
# Expected: bootcount=0
```

### Test 2: Simulate Failed Boot

```bash
# Corrupt kernel on slot A
mount /dev/mmcblk0p1 /mnt
mv /mnt/zImage /mnt/zImage.bak
umount /mnt
reboot

# After 3 failed attempts, should boot from slot B
fw_printenv slot
# Expected: slot=b
```

### Test 3: Recovery from Both Slots Bad

```bash
# If both slots fail, enter U-Boot console
# Press key during boot
=> run boot_recovery
```

---

## Monitoring and Logging

**Check current state:**

```bash
fw_printenv slot bootcount bootlimit
```

**Log boot events:**

```bash
# Add to /etc/rsyslog.d/boot.conf
:msg, contains, "boot-success" /var/log/boot-success.log
```

---

## Falcon Mode Implementation

Falcon Mode allows SPL to boot the Linux kernel directly, bypassing the full U-Boot. This dramatically reduces boot time (typically 1-2 seconds faster).

### Falcon Mode Architecture with A/B Slots

```
┌─────────────────────────────────────────────────────────────────────┐
│                    FALCON MODE A/B BOOT                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   NORMAL BOOT PATH:          FALCON MODE PATH:                      │
│   ┌─────────────┐            ┌─────────────┐                        │
│   │     ROM     │            │     ROM     │                        │
│   └──────┬──────┘            └──────┬──────┘                        │
│          ▼                          ▼                               │
│   ┌─────────────┐            ┌─────────────┐                        │
│   │     SPL     │            │     SPL     │                        │
│   └──────┬──────┘            └──────┬──────┘                        │
│          ▼                          │                               │
│   ┌─────────────┐                   │  (reads args.slot_X)          │
│   │   U-Boot    │                   │                               │
│   └──────┬──────┘                   ▼                               │
│          ▼                   ┌─────────────┐                        │
│   ┌─────────────┐            │   KERNEL    │  ◄── Direct boot!      │
│   │   Kernel    │            └─────────────┘                        │
│   └─────────────┘                                                   │
│                                                                     │
│   ~3-4 seconds                ~1-2 seconds                          │
│                                                                     │
│   Fallback: Hold GPIO/button during boot → Normal path              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Step 6: Configure U-Boot for Falcon Mode

**Enable Falcon Mode in U-Boot defconfig:**

```bash
# In u-boot/configs/am335x_boneblack_defconfig, add:
CONFIG_SPL_OS_BOOT=y
CONFIG_SPL_FALCON_BOOT_MMCSD=y
CONFIG_SYS_SPL_ARGS_ADDR=0x80F80000
CONFIG_SPL_ENV_SUPPORT=y
CONFIG_SPL_MMC_SUPPORT=y
CONFIG_SPL_GPIO_SUPPORT=y    # For fallback detection
CONFIG_CMD_SPL=y
```

**Rebuild U-Boot with Falcon support:**

```bash
cd u-boot
make CROSS_COMPILE=arm-linux-gnueabihf- distclean
make CROSS_COMPILE=arm-linux-gnueabihf- am335x_boneblack_defconfig
# Apply Falcon configs
cat >> .config << 'EOF'
CONFIG_SPL_OS_BOOT=y
CONFIG_SPL_FALCON_BOOT_MMCSD=y
CONFIG_SYS_SPL_ARGS_ADDR=0x80F80000
CONFIG_SPL_ENV_SUPPORT=y
CONFIG_CMD_SPL=y
EOF
make CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)
```

### Step 7: Create Falcon Boot Arguments for A/B Slots

The SPL needs pre-saved kernel arguments for each slot. These are stored as raw data files.

**On target, prepare Slot A arguments:**

```bash
# Boot normally into U-Boot console first
=> setenv falcon_args_a 'console=ttyO0,115200n8 root=/dev/mmcblk0p2 rootwait rw quiet'
=> setenv falcon_args_b 'console=ttyO0,115200n8 root=/dev/mmcblk0p5 rootwait rw quiet'

# Load kernel and DTB for Slot A
=> fatload mmc 0:1 ${loadaddr} zImage
=> fatload mmc 0:1 ${fdtaddr} am335x-boneblack.dtb

# Set bootargs for Slot A
=> setenv bootargs ${falcon_args_a}

# Export arguments to SPL-readable format for Slot A
=> spl export fdt ${loadaddr} - ${fdtaddr}

# Save the args blob to boot partition A
=> fatwrite mmc 0:1 ${fdtaddr} args.slot_a ${filesize}

# Repeat for Slot B
=> fatload mmc 0:3 ${loadaddr} zImage
=> fatload mmc 0:3 ${fdtaddr} am335x-boneblack.dtb
=> setenv bootargs ${falcon_args_b}
=> spl export fdt ${loadaddr} - ${fdtaddr}
=> fatwrite mmc 0:3 ${fdtaddr} args.slot_b ${filesize}

# Save active slot pointer
=> setenv falcon_slot a
=> saveenv
```

### Step 8: SPL A/B Slot Selection

Create a custom SPL board file to handle A/B selection. This requires modifying U-Boot source.

**board/ti/am335x/board.c additions:**

```c
#ifdef CONFIG_SPL_OS_BOOT
#include <environment.h>

/* GPIO for fallback - use USER button on BBB (GPIO2_8 = 72) */
#define FALCON_RECOVERY_GPIO    72

int spl_start_uboot(void)
{
    int recovery_pressed;
    
    /* Check if recovery button is held */
    gpio_request(FALCON_RECOVERY_GPIO, "falcon_recovery");
    gpio_direction_input(FALCON_RECOVERY_GPIO);
    recovery_pressed = !gpio_get_value(FALCON_RECOVERY_GPIO);
    gpio_free(FALCON_RECOVERY_GPIO);
    
    if (recovery_pressed) {
        printf("SPL: Recovery button pressed, starting U-Boot\n");
        return 1;  /* Start full U-Boot */
    }
    
    return 0;  /* Proceed with Falcon boot */
}

void spl_board_prepare_for_linux(void)
{
    /* Read current slot from environment */
    char *slot = env_get("falcon_slot");
    char args_file[32];
    
    if (!slot || (slot[0] != 'a' && slot[0] != 'b')) {
        slot = "a";  /* Default to slot A */
    }
    
    printf("SPL: Falcon booting from slot %s\n", slot);
    
    /* The args file is loaded by SPL based on slot */
    snprintf(args_file, sizeof(args_file), "args.slot_%s", slot);
    env_set("falcon_args_file", args_file);
}
#endif /* CONFIG_SPL_OS_BOOT */
```

**Modified SPL MMC boot logic (common/spl/spl_mmc.c concept):**

```c
/* In your SPL, configure which partition to read args from */
static int get_falcon_boot_partition(void)
{
    char *slot = env_get("falcon_slot");
    
    if (slot && slot[0] == 'b') {
        return 3;  /* Boot partition B (p3) */
    }
    return 1;  /* Boot partition A (p1) */
}
```

### Step 9: Falcon Mode Environment Variables

**Complete U-Boot environment for Falcon A/B:**

```bash
# Falcon mode settings
setenv falcon_enabled 1
setenv falcon_slot a

# Prepare Falcon boot (run once after kernel/DTB update)
setenv falcon_prepare_a '
    echo "Preparing Falcon args for Slot A...";
    fatload mmc 0:1 ${loadaddr} zImage;
    fatload mmc 0:1 ${fdtaddr} am335x-boneblack.dtb;
    setenv bootargs console=ttyO0,115200n8 root=/dev/mmcblk0p2 rootwait rw quiet;
    spl export fdt ${loadaddr} - ${fdtaddr};
    fatwrite mmc 0:1 ${fdtaddr} args 0x${filesize};
    echo "Slot A Falcon args saved";
'

setenv falcon_prepare_b '
    echo "Preparing Falcon args for Slot B...";
    fatload mmc 0:3 ${loadaddr} zImage;
    fatload mmc 0:3 ${fdtaddr} am335x-boneblack.dtb;
    setenv bootargs console=ttyO0,115200n8 root=/dev/mmcblk0p5 rootwait rw quiet;
    spl export fdt ${loadaddr} - ${fdtaddr};
    fatwrite mmc 0:3 ${fdtaddr} args 0x${filesize};
    echo "Slot B Falcon args saved";
'

# Switch Falcon slot (used after OTA update)
setenv falcon_switch_slot '
    if test ${falcon_slot} = a; then
        setenv falcon_slot b;
    else
        setenv falcon_slot a;
    fi;
    saveenv;
    echo "Falcon will boot from slot ${falcon_slot} on next reboot";
'

saveenv
```

---

## FOTA Update Application

A lightweight Firmware Over-The-Air update daemon that monitors for updates and applies them to the standby slot.

### FOTA Client Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      FOTA UPDATE SYSTEM                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐         HTTPS          ┌──────────────────┐      │
│  │  FOTA Client │ ◄─────────────────────► │   Update Server  │      │
│  │  (on target) │                         │   (manifest.json)│      │
│  └──────┬───────┘                         └──────────────────┘      │
│         │                                                           │
│         ▼                                                           │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                    Update Flow                            │      │
│  │  1. Check manifest for new version                        │      │
│  │  2. Download update bundle (boot.tar.gz + rootfs.tar.gz)  │      │
│  │  3. Verify SHA256 checksums                               │      │
│  │  4. Write to standby slot                                 │      │
│  │  5. Regenerate Falcon args for standby slot               │      │
│  │  6. Update slot pointer + reset bootcount                 │      │
│  │  7. Reboot into new slot                                  │      │
│  └──────────────────────────────────────────────────────────┘      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### FOTA Daemon Source Code

**Create /opt/fota/fota_client.c:**

```c
/*
 * FOTA Client for A/B Partition System with Falcon Mode
 * Lightweight C implementation for embedded Linux
 * 
 * Build: arm-linux-gnueabihf-gcc -o fota_client fota_client.c -lcurl -ljson-c -lcrypto
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
#include <curl/curl.h>
#include <json-c/json.h>
#include <openssl/sha.h>

#define VERSION "1.0.0"
#define CONFIG_FILE "/etc/fota/fota.conf"
#define STATE_FILE "/data/fota/state.json"
#define DOWNLOAD_DIR "/tmp/fota"
#define CHECK_INTERVAL 3600  /* seconds */

/* Partition mappings */
#define BOOT_A "/dev/mmcblk0p1"
#define ROOT_A "/dev/mmcblk0p2"
#define BOOT_B "/dev/mmcblk0p3"
#define ROOT_B "/dev/mmcblk0p5"

typedef struct {
    char server_url[256];
    char device_id[64];
    char current_version[32];
    char current_slot;  /* 'a' or 'b' */
    int check_interval;
    int falcon_enabled;
} fota_config_t;

typedef struct {
    char version[32];
    char boot_url[512];
    char boot_sha256[65];
    size_t boot_size;
    char rootfs_url[512];
    char rootfs_sha256[65];
    size_t rootfs_size;
} update_manifest_t;

static volatile int running = 1;
static fota_config_t config;

/* Signal handler for graceful shutdown */
void signal_handler(int sig) {
    syslog(LOG_INFO, "Received signal %d, shutting down", sig);
    running = 0;
}

/* CURL write callback */
static size_t write_callback(void *ptr, size_t size, size_t nmemb, void *stream) {
    return fwrite(ptr, size, nmemb, (FILE *)stream);
}

/* CURL memory callback for JSON responses */
struct memory_struct {
    char *memory;
    size_t size;
};

static size_t memory_callback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    struct memory_struct *mem = (struct memory_struct *)userp;
    
    char *ptr = realloc(mem->memory, mem->size + realsize + 1);
    if (!ptr) return 0;
    
    mem->memory = ptr;
    memcpy(&(mem->memory[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->memory[mem->size] = 0;
    
    return realsize;
}

/* Calculate SHA256 of a file */
int calculate_sha256(const char *filename, char *hash_out) {
    FILE *fp = fopen(filename, "rb");
    if (!fp) return -1;
    
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
    
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        sprintf(hash_out + (i * 2), "%02x", hash[i]);
    }
    hash_out[64] = 0;
    
    return 0;
}

/* Read current slot from U-Boot environment */
char get_current_slot(void) {
    FILE *fp = popen("fw_printenv -n slot 2>/dev/null", "r");
    if (!fp) return 'a';
    
    char slot = 'a';
    fscanf(fp, "%c", &slot);
    pclose(fp);
    
    return (slot == 'b') ? 'b' : 'a';
}

/* Get standby slot info */
void get_standby_slot(char current, char *standby, 
                      const char **boot_dev, const char **root_dev) {
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

/* Download file with progress */
int download_file(const char *url, const char *dest, size_t expected_size) {
    CURL *curl = curl_easy_init();
    if (!curl) return -1;
    
    FILE *fp = fopen(dest, "wb");
    if (!fp) {
        curl_easy_cleanup(curl);
        return -1;
    }
    
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, fp);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 600L);  /* 10 min timeout */
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    
    CURLcode res = curl_easy_perform(curl);
    fclose(fp);
    curl_easy_cleanup(curl);
    
    if (res != CURLE_OK) {
        syslog(LOG_ERR, "Download failed: %s", curl_easy_strerror(res));
        unlink(dest);
        return -1;
    }
    
    return 0;
}

/* Check for updates from server */
int check_for_update(update_manifest_t *manifest) {
    char url[512];
    snprintf(url, sizeof(url), "%s/api/v1/devices/%s/update", 
             config.server_url, config.device_id);
    
    CURL *curl = curl_easy_init();
    if (!curl) return -1;
    
    struct memory_struct chunk = {0};
    chunk.memory = malloc(1);
    chunk.size = 0;
    
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, memory_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
    
    /* Add current version header */
    struct curl_slist *headers = NULL;
    char version_header[64];
    snprintf(version_header, sizeof(version_header), 
             "X-Current-Version: %s", config.current_version);
    headers = curl_slist_append(headers, version_header);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    
    CURLcode res = curl_easy_perform(curl);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    
    if (res != CURLE_OK) {
        free(chunk.memory);
        return -1;
    }
    
    /* Parse JSON response */
    struct json_object *root = json_tokener_parse(chunk.memory);
    free(chunk.memory);
    
    if (!root) return -1;
    
    struct json_object *update_available;
    if (!json_object_object_get_ex(root, "update_available", &update_available) ||
        !json_object_get_boolean(update_available)) {
        json_object_put(root);
        return 0;  /* No update */
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

/* Apply update to standby slot */
int apply_update(update_manifest_t *manifest) {
    char standby_slot;
    const char *boot_dev, *root_dev;
    char cmd[512];
    char hash[65];
    
    get_standby_slot(config.current_slot, &standby_slot, &boot_dev, &root_dev);
    
    syslog(LOG_INFO, "Applying update to slot %c", standby_slot);
    
    /* Create download directory */
    mkdir(DOWNLOAD_DIR, 0755);
    
    /* Download boot archive */
    syslog(LOG_INFO, "Downloading boot files...");
    char boot_file[256];
    snprintf(boot_file, sizeof(boot_file), "%s/boot.tar.gz", DOWNLOAD_DIR);
    
    if (download_file(manifest->boot_url, boot_file, manifest->boot_size) < 0) {
        syslog(LOG_ERR, "Failed to download boot files");
        return -1;
    }
    
    /* Verify boot checksum */
    if (calculate_sha256(boot_file, hash) < 0 ||
        strcmp(hash, manifest->boot_sha256) != 0) {
        syslog(LOG_ERR, "Boot checksum mismatch");
        return -1;
    }
    
    /* Download rootfs archive */
    syslog(LOG_INFO, "Downloading rootfs...");
    char rootfs_file[256];
    snprintf(rootfs_file, sizeof(rootfs_file), "%s/rootfs.tar.gz", DOWNLOAD_DIR);
    
    if (download_file(manifest->rootfs_url, rootfs_file, manifest->rootfs_size) < 0) {
        syslog(LOG_ERR, "Failed to download rootfs");
        return -1;
    }
    
    /* Verify rootfs checksum */
    if (calculate_sha256(rootfs_file, hash) < 0 ||
        strcmp(hash, manifest->rootfs_sha256) != 0) {
        syslog(LOG_ERR, "Rootfs checksum mismatch");
        return -1;
    }
    
    syslog(LOG_INFO, "Checksums verified, flashing standby slot...");
    
    /* Flash boot partition */
    mkdir("/tmp/fota_boot", 0755);
    snprintf(cmd, sizeof(cmd), "mount %s /tmp/fota_boot", boot_dev);
    if (system(cmd) != 0) {
        syslog(LOG_ERR, "Failed to mount boot partition");
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd), "rm -rf /tmp/fota_boot/* && tar xzf %s -C /tmp/fota_boot/", boot_file);
    system(cmd);
    
    /* Regenerate Falcon args if enabled */
    if (config.falcon_enabled) {
        syslog(LOG_INFO, "Regenerating Falcon boot args...");
        /* This is typically done via fw_setenv or U-Boot script */
        snprintf(cmd, sizeof(cmd), 
                 "fw_setenv falcon_prepare_%c_pending 1", standby_slot);
        system(cmd);
    }
    
    sync();
    umount("/tmp/fota_boot");
    
    /* Flash rootfs partition */
    syslog(LOG_INFO, "Formatting and writing rootfs...");
    snprintf(cmd, sizeof(cmd), 
             "mkfs.ext4 -F -L ROOT_%c %s", 
             standby_slot - 32, root_dev);  /* Uppercase label */
    if (system(cmd) != 0) {
        syslog(LOG_ERR, "Failed to format rootfs partition");
        return -1;
    }
    
    mkdir("/tmp/fota_root", 0755);
    snprintf(cmd, sizeof(cmd), "mount %s /tmp/fota_root", root_dev);
    if (system(cmd) != 0) {
        syslog(LOG_ERR, "Failed to mount rootfs partition");
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd), "tar xzf %s -C /tmp/fota_root/", rootfs_file);
    system(cmd);
    
    sync();
    umount("/tmp/fota_root");
    
    /* Cleanup downloads */
    unlink(boot_file);
    unlink(rootfs_file);
    rmdir(DOWNLOAD_DIR);
    
    /* Switch to new slot */
    syslog(LOG_INFO, "Switching to slot %c", standby_slot);
    
    snprintf(cmd, sizeof(cmd), "fw_setenv slot %c", standby_slot);
    system(cmd);
    
    system("fw_setenv bootcount 0");
    
    if (config.falcon_enabled) {
        snprintf(cmd, sizeof(cmd), "fw_setenv falcon_slot %c", standby_slot);
        system(cmd);
    }
    
    /* Save update state */
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

/* Load configuration */
int load_config(void) {
    FILE *fp = fopen(CONFIG_FILE, "r");
    if (!fp) {
        syslog(LOG_ERR, "Cannot open config file: %s", CONFIG_FILE);
        return -1;
    }
    
    char line[512];
    while (fgets(line, sizeof(line), fp)) {
        char key[64], value[256];
        if (sscanf(line, "%63[^=]=%255[^\n]", key, value) == 2) {
            if (strcmp(key, "server_url") == 0)
                strncpy(config.server_url, value, sizeof(config.server_url)-1);
            else if (strcmp(key, "device_id") == 0)
                strncpy(config.device_id, value, sizeof(config.device_id)-1);
            else if (strcmp(key, "current_version") == 0)
                strncpy(config.current_version, value, sizeof(config.current_version)-1);
            else if (strcmp(key, "check_interval") == 0)
                config.check_interval = atoi(value);
            else if (strcmp(key, "falcon_enabled") == 0)
                config.falcon_enabled = atoi(value);
        }
    }
    fclose(fp);
    
    config.current_slot = get_current_slot();
    
    if (config.check_interval <= 0)
        config.check_interval = CHECK_INTERVAL;
    
    return 0;
}

/* Mark boot as successful (called after system is stable) */
void mark_boot_success(void) {
    /* Reset boot counter */
    system("fw_setenv bootcount 0");
    
    /* Clear pending state */
    FILE *fp = fopen(STATE_FILE, "r");
    if (fp) {
        char buffer[512];
        size_t len = fread(buffer, 1, sizeof(buffer)-1, fp);
        fclose(fp);
        buffer[len] = 0;
        
        struct json_object *root = json_tokener_parse(buffer);
        if (root) {
            struct json_object *version;
            if (json_object_object_get_ex(root, "pending_version", &version)) {
                /* Update current version in config */
                FILE *cfg = fopen(CONFIG_FILE, "r");
                if (cfg) {
                    char config_content[2048];
                    size_t clen = fread(config_content, 1, sizeof(config_content)-1, cfg);
                    fclose(cfg);
                    config_content[clen] = 0;
                    
                    /* Update version line */
                    char new_version_line[128];
                    snprintf(new_version_line, sizeof(new_version_line),
                             "current_version=%s", json_object_get_string(version));
                    
                    /* Simple sed-like replacement */
                    char cmd[512];
                    snprintf(cmd, sizeof(cmd),
                             "sed -i 's/current_version=.*/current_version=%s/' %s",
                             json_object_get_string(version), CONFIG_FILE);
                    system(cmd);
                    
                    syslog(LOG_INFO, "Boot confirmed, version updated to %s",
                           json_object_get_string(version));
                }
            }
            json_object_put(root);
        }
        unlink(STATE_FILE);
    }
}

/* Manual update trigger via signal or file */
void check_manual_trigger(void) {
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

int main(int argc, char *argv[]) {
    int daemon_mode = 1;
    int force_check = 0;
    
    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-f") == 0 || strcmp(argv[i], "--foreground") == 0)
            daemon_mode = 0;
        else if (strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "--check") == 0)
            force_check = 1;
        else if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "--success") == 0) {
            openlog("fota", LOG_PID, LOG_DAEMON);
            load_config();
            mark_boot_success();
            closelog();
            return 0;
        }
        else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--version") == 0) {
            printf("FOTA Client v%s\n", VERSION);
            return 0;
        }
        else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printf("Usage: %s [options]\n", argv[0]);
            printf("  -f, --foreground  Run in foreground\n");
            printf("  -c, --check       Check for update and exit\n");
            printf("  -s, --success     Mark current boot as successful\n");
            printf("  -v, --version     Show version\n");
            printf("  -h, --help        Show this help\n");
            return 0;
        }
    }
    
    /* Initialize */
    openlog("fota", LOG_PID, LOG_DAEMON);
    curl_global_init(CURL_GLOBAL_ALL);
    
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
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
            printf("Update available: %s\n", manifest.version);
            apply_update(&manifest);
        } else if (result == 0) {
            printf("No update available\n");
        } else {
            printf("Check failed\n");
            return 1;
        }
        return 0;
    }
    
    /* Daemon mode */
    if (daemon_mode) {
        if (daemon(0, 0) < 0) {
            syslog(LOG_ERR, "Failed to daemonize");
            return 1;
        }
    }
    
    /* Mark previous boot as successful if we're running */
    mark_boot_success();
    
    /* Main loop */
    time_t last_check = 0;
    
    while (running) {
        time_t now = time(NULL);
        
        /* Check for manual trigger */
        check_manual_trigger();
        
        /* Periodic check */
        if (now - last_check >= config.check_interval) {
            update_manifest_t manifest = {0};
            if (check_for_update(&manifest) > 0) {
                apply_update(&manifest);
            }
            last_check = now;
        }
        
        sleep(60);  /* Check triggers every minute */
    }
    
    curl_global_cleanup();
    closelog();
    
    return 0;
}
```

### FOTA Configuration File

**Create /etc/fota/fota.conf:**

```ini
# FOTA Client Configuration
server_url=https://updates.example.com
device_id=bbb-001
current_version=1.0.0
check_interval=3600
falcon_enabled=1
```

### FOTA Trigger Script

**Create /usr/bin/fota-trigger:**

```bash
#!/bin/bash
# Trigger immediate FOTA update check

usage() {
    echo "Usage: $0 [options]"
    echo "  -c, --check     Check for updates without applying"
    echo "  -u, --update    Check and apply update if available"
    echo "  -s, --status    Show current FOTA status"
    echo "  -r, --rollback  Rollback to previous slot"
    echo "  -h, --help      Show this help"
}

get_status() {
    echo "=== FOTA Status ==="
    echo "Current slot: $(fw_printenv -n slot 2>/dev/null || echo 'unknown')"
    echo "Boot count: $(fw_printenv -n bootcount 2>/dev/null || echo 'unknown')"
    echo "Boot limit: $(fw_printenv -n bootlimit 2>/dev/null || echo 'unknown')"
    echo "Falcon slot: $(fw_printenv -n falcon_slot 2>/dev/null || echo 'disabled')"
    echo ""
    
    if [ -f /etc/fota/fota.conf ]; then
        echo "Current version: $(grep current_version /etc/fota/fota.conf | cut -d= -f2)"
        echo "Update server: $(grep server_url /etc/fota/fota.conf | cut -d= -f2)"
    fi
    
    if [ -f /data/fota/state.json ]; then
        echo ""
        echo "Pending update: $(cat /data/fota/state.json)"
    fi
}

rollback() {
    CURRENT=$(fw_printenv -n slot 2>/dev/null)
    if [ "$CURRENT" = "a" ]; then
        NEW="b"
    else
        NEW="a"
    fi
    
    echo "Rolling back from slot $CURRENT to slot $NEW..."
    fw_setenv slot $NEW
    fw_setenv bootcount 0
    fw_setenv falcon_slot $NEW 2>/dev/null
    
    echo "Rollback configured. Reboot to apply."
    read -p "Reboot now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    fi
}

case "$1" in
    -c|--check)
        /opt/fota/fota_client --check --foreground
        ;;
    -u|--update)
        echo "Triggering update check..."
        touch /tmp/fota_trigger
        # Or direct call
        /opt/fota/fota_client --check
        ;;
    -s|--status)
        get_status
        ;;
    -r|--rollback)
        rollback
        ;;
    -h|--help|*)
        usage
        ;;
esac
```

### Systemd Service for FOTA

**Create /etc/systemd/system/fota.service:**

```ini
[Unit]
Description=FOTA Update Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/fota/fota_client --foreground
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=30

# Security hardening
NoNewPrivileges=false
ProtectSystem=false
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

### FOTA Build Instructions

**Create /opt/fota/Makefile:**

```makefile
# FOTA Client Makefile
CC = arm-linux-gnueabihf-gcc
CFLAGS = -Wall -O2
LDFLAGS = -lcurl -ljson-c -lcrypto

TARGET = fota_client
SRC = fota_client.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	install -m 755 $(TARGET) /opt/fota/
	install -m 755 fota-trigger /usr/bin/
	install -m 644 fota.service /etc/systemd/system/
	mkdir -p /etc/fota /data/fota
	test -f /etc/fota/fota.conf || install -m 644 fota.conf /etc/fota/
	systemctl daemon-reload
	systemctl enable fota

.PHONY: all clean install
```

---

## Update Server Manifest Example

**Server endpoint: GET /api/v1/devices/{device_id}/update**

```json
{
    "update_available": true,
    "version": "1.1.0",
    "release_notes": "Bug fixes and performance improvements",
    "boot_url": "https://updates.example.com/releases/1.1.0/boot.tar.gz",
    "boot_sha256": "a1b2c3d4e5f6...",
    "boot_size": 5242880,
    "rootfs_url": "https://updates.example.com/releases/1.1.0/rootfs.tar.gz",
    "rootfs_sha256": "f6e5d4c3b2a1...",
    "rootfs_size": 104857600,
    "min_version": "1.0.0",
    "mandatory": false
}
```

---

## Complete Boot Flow with Falcon + A/B + FOTA

```
┌─────────────────────────────────────────────────────────────────────┐
│           COMPLETE SYSTEM FLOW: FALCON + A/B + FOTA                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  POWER ON                                                           │
│      │                                                              │
│      ▼                                                              │
│  ┌───────┐     Button held?     ┌──────────┐                       │
│  │  SPL  │ ─────── YES ───────► │  U-Boot  │ → Normal boot path    │
│  └───┬───┘                      └──────────┘                       │
│      │ NO (Falcon mode)                                             │
│      ▼                                                              │
│  Read falcon_slot env                                               │
│      │                                                              │
│      ├─── slot=a ──► Load zImage + args from p1 ──► Boot to p2     │
│      │                                                              │
│      └─── slot=b ──► Load zImage + args from p3 ──► Boot to p5     │
│                                                                     │
│  LINUX RUNNING                                                      │
│      │                                                              │
│      ▼                                                              │
│  ┌────────────────┐                                                 │
│  │  boot-success  │ → Reset bootcount after system stable           │
│  └────────────────┘                                                 │
│      │                                                              │
│      ▼                                                              │
│  ┌────────────────┐         ┌─────────────────┐                    │
│  │  FOTA daemon   │ ◄─────► │  Update Server  │                    │
│  └───────┬────────┘         └─────────────────┘                    │
│          │                                                          │
│          │ Update available?                                        │
│          │                                                          │
│          ▼                                                          │
│  ┌──────────────────────────────────────────────┐                  │
│  │ 1. Download to /tmp                          │                  │
│  │ 2. Verify SHA256                             │                  │
│  │ 3. Flash standby slot (opposite of current)  │                  │
│  │ 4. Set falcon_slot + slot to standby         │                  │
│  │ 5. Reset bootcount                           │                  │
│  │ 6. Reboot                                    │                  │
│  └──────────────────────────────────────────────┘                  │
│                                                                     │
│  REBOOT → SPL boots new slot via Falcon                            │
│      │                                                              │
│      ├── SUCCESS → boot-success resets counter, confirms update    │
│      │                                                              │
│      └── FAILURE → After bootlimit, auto-rollback to old slot      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Verification Checklist

- [ ] Partition table created correctly
- [ ] Both slots contain identical bootable images
- [ ] U-Boot A/B logic works correctly
- [ ] Boot counter increments on each boot
- [ ] Boot counter resets on successful boot
- [ ] Automatic switch after bootlimit failures
- [ ] OTA update script works
- [ ] Recovery mode accessible
- [ ] Falcon Mode boots in under 2 seconds
- [ ] Falcon fallback (button) enters U-Boot
- [ ] Falcon args generated for both slots
- [ ] FOTA client compiles and runs
- [ ] FOTA checks server periodically
- [ ] FOTA applies update to standby slot
- [ ] FOTA triggers Falcon args regeneration
- [ ] FOTA rollback works correctly

---

## Troubleshooting

### Falcon Mode Issues

```bash
# Check if Falcon is configured
fw_printenv falcon_slot falcon_enabled

# Verify args file exists
mount /dev/mmcblk0p1 /mnt && ls -la /mnt/args* && umount /mnt

# Force U-Boot (hold USER button during boot)
# Then check SPL messages for errors
```

### FOTA Issues

```bash
# Check FOTA logs
journalctl -u fota -f

# Manual update check
/opt/fota/fota_client --check --foreground

# Verify network connectivity
curl -I https://updates.example.com/api/v1/health

# Check slot state
fota-trigger --status
```

---

[← Previous: Boot Optimization](03_boot_optimization.md) | [Back to Index](README.md) | [Next: PREEMPT_RT →](05_preempt_rt.md)
