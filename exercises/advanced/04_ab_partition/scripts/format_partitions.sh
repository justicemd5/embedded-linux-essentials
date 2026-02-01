#!/bin/bash
# Format A/B partitions
# Usage: sudo ./format_partitions.sh /dev/sdX

set -e

DEVICE="${1:-/dev/sdX}"

if [ "$DEVICE" = "/dev/sdX" ]; then
    echo "Usage: $0 /dev/sdX"
    echo "Replace /dev/sdX with your actual SD card device"
    exit 1
fi

echo "Formatting partitions on $DEVICE..."

# Format Boot A (FAT32)
echo "Formatting Boot A (${DEVICE}1)..."
mkfs.vfat -F 32 -n BOOT_A "${DEVICE}1"

# Format Root A (ext4)
echo "Formatting Root A (${DEVICE}2)..."
mkfs.ext4 -L ROOT_A "${DEVICE}2"

# Format Boot B (FAT32)
echo "Formatting Boot B (${DEVICE}3)..."
mkfs.vfat -F 32 -n BOOT_B "${DEVICE}3"

# Format Root B (ext4) - Note: logical partition starts at 5
echo "Formatting Root B (${DEVICE}5)..."
mkfs.ext4 -L ROOT_B "${DEVICE}5"

# Format Data (ext4)
echo "Formatting Data (${DEVICE}6)..."
mkfs.ext4 -L DATA "${DEVICE}6"

echo ""
echo "All partitions formatted successfully!"
echo ""
echo "Partition layout:"
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEVICE"
echo ""
echo "Next step: Run populate_partitions.sh $DEVICE"
