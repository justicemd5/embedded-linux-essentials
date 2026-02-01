#!/bin/bash
# Create A/B partition layout for 8GB SD card
# Usage: sudo ./create_partitions.sh /dev/sdX

set -e

DEVICE="${1:-/dev/sdX}"

if [ "$DEVICE" = "/dev/sdX" ]; then
    echo "Usage: $0 /dev/sdX"
    echo "Replace /dev/sdX with your actual SD card device"
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

echo "WARNING: This will destroy all data on $DEVICE"
read -p "Are you sure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted"
    exit 1
fi

# Unmount any mounted partitions
for part in ${DEVICE}*; do
    if mountpoint -q "$part" 2>/dev/null; then
        umount "$part"
    fi
done

echo "Creating partition table..."

# Use sfdisk for scriptable partitioning
sfdisk "$DEVICE" << EOF
# Partition table for A/B system
# p1: 64MB  FAT32 - Boot A (MLO, u-boot.img, zImage, DTB)
# p2: 2GB   ext4  - Root A
# p3: 64MB  FAT32 - Boot B
# p4: Extended partition for the rest
# p5: 2GB   ext4  - Root B
# p6: 1GB   ext4  - Persistent Data

label: dos

# Boot A - 64MB FAT32
,64M,c,*

# Root A - 2GB Linux
,2G,83

# Boot B - 64MB FAT32
,64M,c

# Extended partition - rest of disk
,,E

# Root B - 2GB Linux (logical)
,2G,83

# Data - 1GB Linux (logical)
,1G,83
EOF

# Wait for kernel to re-read partition table
sleep 2
partprobe "$DEVICE"

echo "Partition table created successfully!"
echo ""
echo "Next step: Run format_partitions.sh $DEVICE"
