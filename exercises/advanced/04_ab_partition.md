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

## Verification Checklist

- [ ] Partition table created correctly
- [ ] Both slots contain identical bootable images
- [ ] U-Boot A/B logic works correctly
- [ ] Boot counter increments on each boot
- [ ] Boot counter resets on successful boot
- [ ] Automatic switch after bootlimit failures
- [ ] OTA update script works
- [ ] Recovery mode accessible

---

[← Previous: Boot Optimization](03_boot_optimization.md) | [Back to Index](README.md) | [Next: PREEMPT_RT →](05_preempt_rt.md)
