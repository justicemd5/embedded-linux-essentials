#!/bin/bash
# OTA Update Script for A/B partition system
# Usage: ota-update.sh <update_url>
#
# Downloads update bundle from URL, verifies checksum, 
# and applies to standby slot.

set -e

UPDATE_URL="$1"
TEMP_DIR="/tmp/update"

if [ -z "$UPDATE_URL" ]; then
    echo "Usage: $0 <update_url>"
    echo ""
    echo "Example:"
    echo "  $0 https://updates.example.com/v1.2.0/update.tar.gz"
    exit 1
fi

# Check for required tools
for tool in fw_printenv fw_setenv wget tar; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: Required tool '$tool' not found"
        exit 1
    fi
done

# Determine current and standby slots
CURRENT_SLOT=$(fw_printenv -n slot 2>/dev/null || echo "a")

if [ "$CURRENT_SLOT" = "a" ]; then
    STANDBY_SLOT="b"
    STANDBY_BOOT="/dev/mmcblk0p3"
    STANDBY_ROOT="/dev/mmcblk0p5"
    STANDBY_LABEL="ROOT_B"
else
    STANDBY_SLOT="a"
    STANDBY_BOOT="/dev/mmcblk0p1"
    STANDBY_ROOT="/dev/mmcblk0p2"
    STANDBY_LABEL="ROOT_A"
fi

echo "============================================"
echo "        OTA Update for A/B System"
echo "============================================"
echo "Current slot:  $CURRENT_SLOT"
echo "Standby slot:  $STANDBY_SLOT"
echo "Update URL:    $UPDATE_URL"
echo "============================================"
echo ""

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    umount /mnt 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Create temp directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download update
echo "[1/6] Downloading update..."
wget -O update.tar.gz "$UPDATE_URL"

# Verify download (check for checksum file)
if wget -q -O update.sha256 "${UPDATE_URL}.sha256" 2>/dev/null; then
    echo "[2/6] Verifying checksum..."
    sha256sum -c update.sha256
else
    echo "[2/6] No checksum file found, skipping verification"
fi

# Extract update
echo "[3/6] Extracting update..."
tar xzf update.tar.gz

# Verify expected files
if [ ! -d "boot" ] || [ ! -f "rootfs.tar" ]; then
    echo "Error: Invalid update bundle (missing boot/ or rootfs.tar)"
    exit 1
fi

# Update boot partition
echo "[4/6] Updating boot partition ($STANDBY_BOOT)..."
mount "$STANDBY_BOOT" /mnt
rm -rf /mnt/*
cp -rv boot/* /mnt/
sync
umount /mnt

# Update root partition
echo "[5/6] Updating root partition ($STANDBY_ROOT)..."
mkfs.ext4 -F -L "$STANDBY_LABEL" "$STANDBY_ROOT"
mount "$STANDBY_ROOT" /mnt
tar xf rootfs.tar -C /mnt
sync
umount /mnt

# Switch to new slot
echo "[6/6] Switching to slot $STANDBY_SLOT..."
fw_setenv slot "$STANDBY_SLOT"
fw_setenv bootcount 0

# Also update Falcon slot if enabled
if fw_printenv falcon_enabled 2>/dev/null | grep -q "1"; then
    echo "Updating Falcon slot pointer..."
    fw_setenv falcon_slot "$STANDBY_SLOT"
    fw_setenv falcon_prepare_${STANDBY_SLOT}_pending 1
fi

echo ""
echo "============================================"
echo "Update complete!"
echo "New active slot: $STANDBY_SLOT"
echo "============================================"
echo ""
echo "Rebooting in 5 seconds... (Ctrl+C to cancel)"
sleep 5
reboot
