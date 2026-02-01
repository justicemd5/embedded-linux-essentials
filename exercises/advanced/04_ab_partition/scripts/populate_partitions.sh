#!/bin/bash
# Populate A/B partitions with boot files and rootfs
# Usage: sudo ./populate_partitions.sh /dev/sdX [boot_files_dir] [rootfs_tar]

set -e

DEVICE="${1:-/dev/sdX}"
BOOT_DIR="${2:-./boot}"
ROOTFS_TAR="${3:-./rootfs.tar}"

if [ "$DEVICE" = "/dev/sdX" ]; then
    echo "Usage: $0 /dev/sdX [boot_files_dir] [rootfs_tar]"
    echo ""
    echo "Arguments:"
    echo "  /dev/sdX        - SD card device"
    echo "  boot_files_dir  - Directory containing MLO, u-boot.img, zImage, DTB"
    echo "  rootfs_tar      - Root filesystem tarball"
    exit 1
fi

# Verify boot files exist
BOOT_FILES="MLO u-boot.img zImage am335x-boneblack.dtb"
for file in $BOOT_FILES; do
    if [ ! -f "$BOOT_DIR/$file" ]; then
        echo "Error: Missing boot file: $BOOT_DIR/$file"
        exit 1
    fi
done

# Verify rootfs exists
if [ ! -f "$ROOTFS_TAR" ]; then
    echo "Error: Rootfs tarball not found: $ROOTFS_TAR"
    exit 1
fi

# Create mount points
MNT_BASE="/tmp/ab_partition_mnt"
mkdir -p "$MNT_BASE"/{boot_a,root_a,boot_b,root_b,data}

cleanup() {
    echo "Cleaning up..."
    for mnt in boot_a root_a boot_b root_b data; do
        umount "$MNT_BASE/$mnt" 2>/dev/null || true
    done
    rm -rf "$MNT_BASE"
}
trap cleanup EXIT

echo "Mounting partitions..."
mount "${DEVICE}1" "$MNT_BASE/boot_a"
mount "${DEVICE}2" "$MNT_BASE/root_a"
mount "${DEVICE}3" "$MNT_BASE/boot_b"
mount "${DEVICE}5" "$MNT_BASE/root_b"
mount "${DEVICE}6" "$MNT_BASE/data"

echo "Copying boot files to Slot A..."
cp -v "$BOOT_DIR"/MLO "$MNT_BASE/boot_a/"
cp -v "$BOOT_DIR"/u-boot.img "$MNT_BASE/boot_a/"
cp -v "$BOOT_DIR"/zImage "$MNT_BASE/boot_a/"
cp -v "$BOOT_DIR"/am335x-boneblack.dtb "$MNT_BASE/boot_a/"

echo "Copying boot files to Slot B..."
cp -v "$BOOT_DIR"/MLO "$MNT_BASE/boot_b/"
cp -v "$BOOT_DIR"/u-boot.img "$MNT_BASE/boot_b/"
cp -v "$BOOT_DIR"/zImage "$MNT_BASE/boot_b/"
cp -v "$BOOT_DIR"/am335x-boneblack.dtb "$MNT_BASE/boot_b/"

echo "Extracting rootfs to Slot A..."
tar xf "$ROOTFS_TAR" -C "$MNT_BASE/root_a/"

echo "Extracting rootfs to Slot B..."
tar xf "$ROOTFS_TAR" -C "$MNT_BASE/root_b/"

echo "Creating data partition structure..."
mkdir -p "$MNT_BASE/data"/{config,logs,user,fota}

echo "Syncing..."
sync

echo ""
echo "Partitions populated successfully!"
echo ""
echo "Boot A contents:"
ls -la "$MNT_BASE/boot_a/"
echo ""
echo "Data partition structure:"
ls -la "$MNT_BASE/data/"
