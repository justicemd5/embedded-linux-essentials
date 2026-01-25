# TFTP Recovery Guide

Emergency recovery procedures using TFTP for bricked or corrupted boards.

## Overview

This guide covers:
1. Emergency TFTP boot when local storage is corrupted
2. Reflashing board via network
3. Automated recovery scripts
4. Platform-specific TFTP recovery

---

## Part 1: Prerequisites

### Host Machine Setup

```bash
# Install TFTP server
sudo apt-get install -y tftpd-hpa

# Configure TFTP
sudo nano /etc/default/tftpd-hpa
```

```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
```

```bash
# Create and set permissions
sudo mkdir -p /tftpboot
sudo chmod 777 /tftpboot

# Start service
sudo systemctl enable --now tftpd-hpa
```

### Required Files in /tftpboot

```bash
# Minimum for boot:
/tftpboot/
├── zImage          # Kernel
├── board.dtb       # Device tree
└── rootfs.cpio.gz  # initramfs (optional, for full recovery)

# For reflashing:
/tftpboot/
├── u-boot.bin      # New U-Boot binary
├── sdcard.img      # Complete SD card image
└── rootfs.ext4     # Root filesystem image
```

---

## Part 2: Emergency TFTP Boot

### When U-Boot is Working

If U-Boot is accessible via serial:

```bash
# At U-Boot prompt

# Configure network
=> setenv ethaddr 00:11:22:33:44:55  # If MAC not set
=> setenv ipaddr 192.168.1.50
=> setenv serverip 192.168.1.100
=> setenv netmask 255.255.255.0

# Verify network
=> ping ${serverip}
# Should show: host 192.168.1.100 is alive

# Download kernel
=> tftp ${loadaddr} zImage
# Bytes transferred = XXXXX

# Download device tree
=> tftp ${fdt_addr} bcm2710-rpi-3-b.dtb

# Boot with NFS root (if rootfs is corrupt)
=> setenv bootargs console=ttyS0,115200 root=/dev/nfs nfsroot=${serverip}:/export/rootfs,v3,tcp ip=dhcp
=> bootz ${loadaddr} - ${fdt_addr}
```

### Boot with Initramfs

```bash
# Download initramfs
=> tftp ${ramdisk_addr} rootfs.cpio.gz

# Boot with ramdisk
=> setenv bootargs console=ttyS0,115200
=> bootz ${loadaddr} ${ramdisk_addr}:${filesize} ${fdt_addr}
```

---

## Part 3: Reflashing via TFTP

### Method 1: Flash SD Card from U-Boot

**WARNING: This overwrites the entire SD card!**

```bash
# Download complete image
=> tftp ${loadaddr} sdcard.img
# Note the filesize shown

# Calculate sector count (filesize / 512)
# For a 500MB image: 500*1024*1024/512 = 0xFA000
=> setexpr sectors ${filesize} / 0x200

# Write to SD card
=> mmc dev 0
=> mmc write ${loadaddr} 0 ${sectors}

# Reboot
=> reset
```

### Method 2: Flash Individual Partitions

```bash
# Download and flash boot partition
=> tftp ${loadaddr} boot.vfat
=> mmc dev 0
=> mmc write ${loadaddr} 0x2000 <boot_sectors>

# Download and flash rootfs partition
=> tftp ${loadaddr} rootfs.ext4
=> mmc write ${loadaddr} 0x82000 <rootfs_sectors>
```

### Method 3: Use Recovery initramfs

1. Boot into recovery initramfs via TFTP
2. Download and write images from userspace

```bash
# In recovery initramfs:

# Download image
wget http://192.168.1.100/sdcard.img.gz -O /tmp/sdcard.img.gz

# Write to SD card
gunzip -c /tmp/sdcard.img.gz | dd of=/dev/mmcblk0 bs=4M

# Sync and reboot
sync
reboot
```

---

## Part 4: Platform-Specific TFTP Recovery

### Raspberry Pi

```bash
# Pi 3/4 with working U-Boot:
=> setenv serverip 192.168.1.100
=> tftp ${kernel_addr_r} zImage
=> tftp ${fdt_addr} bcm2711-rpi-4-b.dtb
=> setenv bootargs console=serial0,115200 root=/dev/nfs nfsroot=${serverip}:/export/rootfs ip=dhcp
=> bootz ${kernel_addr_r} - ${fdt_addr}
```

### BeagleBone Black

```bash
# BBB with U-Boot:
=> setenv serverip 192.168.1.100
=> tftp ${loadaddr} zImage
=> tftp ${fdtaddr} am335x-boneblack.dtb
=> setenv bootargs console=ttyO0,115200n8 root=/dev/nfs nfsroot=${serverip}:/export/rootfs ip=dhcp
=> bootz ${loadaddr} - ${fdtaddr}

# Alternative: USB/Ethernet gadget mode
# Hold BOOT button during power-on to enter USB boot mode
```

### i.MX6

```bash
# i.MX6 with U-Boot:
=> setenv serverip 192.168.1.100
=> tftp ${loadaddr} zImage
=> tftp ${fdt_addr} imx6q-board.dtb
=> setenv bootargs console=ttymxc0,115200 root=/dev/nfs nfsroot=${serverip}:/export/rootfs ip=dhcp
=> bootz ${loadaddr} - ${fdt_addr}

# Recovery via USB Serial Download:
# Hold down recovery button, use imx_usb_loader tool
./imx_usb u-boot-dtb.imx
```

### STM32MP1

```bash
# STM32MP1 with U-Boot:
=> setenv serverip 192.168.1.100
=> tftp ${kernel_addr_r} zImage
=> tftp ${fdt_addr_r} stm32mp157c-board.dtb
=> setenv bootargs console=ttySTM0,115200 root=/dev/nfs nfsroot=${serverip}:/export/rootfs ip=dhcp
=> bootz ${kernel_addr_r} - ${fdt_addr_r}

# Recovery via DFU mode:
# Use boot switches to enter DFU mode
dfu-util -a 0 -D tf-a-stm32mp157c.stm32
dfu-util -a 4 -D u-boot.stm32
```

---

## Part 5: Automated TFTP Recovery Script

### U-Boot Recovery Script

Save as `recovery.scr`:

```
# TFTP Recovery Script

echo "=== Emergency TFTP Recovery ==="
echo "Configuring network..."

setenv serverip 192.168.1.100
setenv ipaddr 192.168.1.50
setenv netmask 255.255.255.0

echo "Downloading recovery kernel..."
if tftp ${loadaddr} recovery-zImage; then
    echo "Kernel downloaded"
else
    echo "TFTP failed! Check network."
    exit
fi

echo "Downloading recovery DTB..."
tftp ${fdt_addr} recovery.dtb

echo "Downloading recovery initramfs..."
tftp ${ramdisk_addr} recovery-initramfs.cpio.gz

echo "Booting recovery system..."
setenv bootargs console=ttyS0,115200 recovery
bootz ${loadaddr} ${ramdisk_addr}:${filesize} ${fdt_addr}
```

Compile the script:
```bash
mkimage -C none -A arm -T script -d recovery.scr recovery.scr.uimg
sudo cp recovery.scr.uimg /tftpboot/
```

Load from U-Boot:
```bash
=> tftp ${scriptaddr} recovery.scr.uimg
=> source ${scriptaddr}
```

---

## Part 6: Network Boot as Primary (Development)

### Permanent TFTP Boot Configuration

```bash
# Set up for persistent network boot
=> setenv serverip 192.168.1.100
=> setenv tftp_boot 'dhcp; tftp ${loadaddr} zImage; tftp ${fdt_addr} ${fdtfile}; setenv bootargs console=${console} root=/dev/nfs nfsroot=${serverip}:/export/rootfs,v3 ip=dhcp; bootz ${loadaddr} - ${fdt_addr}'
=> setenv bootcmd 'run tftp_boot'
=> saveenv
```

### Fallback to SD if TFTP Fails

```bash
=> setenv tftp_try 'dhcp; tftp ${loadaddr} zImage'
=> setenv sd_fallback 'fatload mmc 0:1 ${loadaddr} zImage; fatload mmc 0:1 ${fdt_addr} ${fdtfile}'
=> setenv bootcmd 'if run tftp_try; then run tftp_boot; else echo "TFTP failed, booting from SD"; run sd_fallback; run sd_boot; fi'
=> saveenv
```

---

## Part 7: Troubleshooting

### "TFTP error: 'Access violation'"

```bash
# Check TFTP directory permissions
ls -la /tftpboot/
# Should be world-readable

sudo chmod 644 /tftpboot/*
```

### "TFTP error: 'File not found'"

```bash
# Check exact filename (case-sensitive)
ls /tftpboot/

# Check TFTP configuration
grep TFTP_DIRECTORY /etc/default/tftpd-hpa
```

### "T T T T T..." (Timeout)

```bash
# Check firewall
sudo ufw allow 69/udp

# Check TFTP is running
sudo systemctl status tftpd-hpa

# Test from another machine
tftp 192.168.1.100 -c get zImage
```

### "Using device X, ... No link"

```bash
# Network cable issue
# Try different cable or port
# Some boards need specific Ethernet port
```

### "TFTP from server ... ; our IP address is ..."

```bash
# Check DHCP server is running
# Or set static IP:
=> setenv ipaddr 192.168.1.50
=> setenv serverip 192.168.1.100
```

---

## Quick Reference

### Minimal TFTP Boot Commands

```bash
# Configure
=> setenv serverip 192.168.1.100
=> setenv ipaddr 192.168.1.50

# Download
=> tftp ${loadaddr} zImage
=> tftp ${fdt_addr} board.dtb

# Boot
=> setenv bootargs console=ttyS0,115200 root=/dev/nfs nfsroot=${serverip}:/export/rootfs ip=dhcp
=> bootz ${loadaddr} - ${fdt_addr}
```

### Host Checklist

```bash
# Verify TFTP running
sudo systemctl status tftpd-hpa

# Verify files exist
ls -la /tftpboot/

# Test locally
tftp localhost -c get zImage

# Check firewall
sudo ufw status
```
