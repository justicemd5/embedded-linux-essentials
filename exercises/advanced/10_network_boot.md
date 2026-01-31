# Exercise 10: Network Boot Infrastructure

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

## Objective

Set up a complete network boot environment with TFTP and NFS for diskless BeagleBone Black operation.

## Prerequisites

- Linux server with network connectivity to BBB
- U-Boot with network support
- Ethernet connection (USB Ethernet or on-board)
- Static IP or DHCP server control

## Difficulty: ⭐⭐⭐ Advanced

---

## Network Boot Overview

```
┌─────────────────────────────────────────────────────────────┐
│                 NETWORK BOOT ARCHITECTURE                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌───────────────┐            ┌───────────────┐            │
│  │  BeagleBone   │            │  Linux Server │            │
│  │    Black      │◄──────────►│               │            │
│  └───────┬───────┘  Ethernet  └───────┬───────┘            │
│          │                            │                     │
│          ▼                            ▼                     │
│  1. U-Boot starts          ┌─────────────────────┐         │
│          │                 │  DHCP Server        │         │
│  2. DHCP request ─────────►│  - IP assignment    │         │
│          │                 │  - TFTP server IP   │         │
│  3. DHCP response ◄────────│  - Boot filename    │         │
│          │                 └─────────────────────┘         │
│          ▼                                                  │
│  4. TFTP request  ─────────►┌─────────────────────┐        │
│     (zImage, DTB)           │  TFTP Server        │        │
│          │                  │  /tftpboot/         │        │
│  5. Files downloaded ◄──────│  ├── zImage         │        │
│          │                  │  └── *.dtb          │        │
│          ▼                  └─────────────────────┘        │
│  6. Kernel boots with                                       │
│     root=/dev/nfs  ────────►┌─────────────────────┐        │
│          │                  │  NFS Server         │        │
│  7. NFS mount      ◄────────│  /export/bbb-root/  │        │
│          │                  │  (complete rootfs)  │        │
│          ▼                  └─────────────────────┘        │
│  8. System running                                          │
│     (diskless)                                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Guide

### Step 1: Server Setup (Ubuntu/Debian)

```bash
# Install required packages
sudo apt update
sudo apt install -y tftpd-hpa nfs-kernel-server dnsmasq

# Or for separate DHCP server
sudo apt install -y isc-dhcp-server
```

### Step 2: Configure Network Interface

```bash
# Set static IP on server interface connected to BBB
# Edit /etc/netplan/01-netcfg.yaml (Ubuntu 18.04+)
sudo cat > /etc/netplan/01-bbb-network.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eth1:  # Interface connected to BBB
      addresses:
        - 192.168.10.1/24
      dhcp4: no
EOF

sudo netplan apply
```

### Step 3: Configure DHCP Server

**Option A: Using dnsmasq (simpler):**

```bash
sudo cat > /etc/dnsmasq.d/bbb.conf << 'EOF'
# Interface to listen on
interface=eth1
bind-interfaces

# DHCP range
dhcp-range=192.168.10.100,192.168.10.200,12h

# Static IP for specific BBB (optional)
dhcp-host=d0:39:72:xx:xx:xx,beaglebone,192.168.10.50

# TFTP server
enable-tftp
tftp-root=/tftpboot

# PXE boot options
dhcp-boot=zImage
dhcp-option=66,192.168.10.1  # TFTP server
dhcp-option=67,zImage        # Boot filename
EOF

sudo systemctl restart dnsmasq
```

**Option B: Using isc-dhcp-server:**

```bash
sudo cat > /etc/dhcp/dhcpd.conf << 'EOF'
authoritative;

subnet 192.168.10.0 netmask 255.255.255.0 {
    range 192.168.10.100 192.168.10.200;
    option routers 192.168.10.1;
    option domain-name-servers 8.8.8.8;
    
    # TFTP options
    next-server 192.168.10.1;
    filename "zImage";
    
    # Static assignment for BBB
    host beaglebone {
        hardware ethernet d0:39:72:xx:xx:xx;
        fixed-address 192.168.10.50;
    }
}
EOF

# Set interface
sudo sed -i 's/INTERFACESv4=""/INTERFACESv4="eth1"/' /etc/default/isc-dhcp-server

sudo systemctl restart isc-dhcp-server
```

### Step 4: Configure TFTP Server

```bash
# Create TFTP root directory
sudo mkdir -p /tftpboot
sudo chmod 755 /tftpboot

# Configure tftpd-hpa
sudo cat > /etc/default/tftpd-hpa << 'EOF'
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
EOF

sudo systemctl restart tftpd-hpa

# Copy boot files
sudo cp zImage /tftpboot/
sudo cp am335x-boneblack.dtb /tftpboot/
sudo chmod 644 /tftpboot/*
```

### Step 5: Configure NFS Server

```bash
# Create NFS export directory
sudo mkdir -p /export/bbb-root

# Extract rootfs (or copy from existing)
sudo tar xf rootfs.tar -C /export/bbb-root

# Configure NFS exports
sudo cat >> /etc/exports << 'EOF'
/export/bbb-root 192.168.10.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF

# Apply exports
sudo exportfs -ra

# Start/restart NFS
sudo systemctl restart nfs-kernel-server

# Verify exports
showmount -e localhost
```

### Step 6: Prepare Rootfs for NFS Boot

```bash
# Modify fstab for NFS root
sudo cat > /export/bbb-root/etc/fstab << 'EOF'
# NFS root filesystem - no entry needed, kernel mounts it

# Mount essential filesystems
proc            /proc        proc    defaults          0 0
sysfs           /sys         sysfs   defaults          0 0
devtmpfs        /dev         devtmpfs defaults         0 0
tmpfs           /tmp         tmpfs   defaults          0 0
tmpfs           /run         tmpfs   defaults          0 0
tmpfs           /var/log     tmpfs   defaults          0 0
EOF

# Ensure network is configured for DHCP
sudo cat > /export/bbb-root/etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
```

### Step 7: Configure U-Boot for Network Boot

```bash
# Connect to BBB serial console
screen /dev/ttyACM0 115200

# At U-Boot prompt, configure network boot
=> setenv ipaddr 192.168.10.50
=> setenv serverip 192.168.10.1
=> setenv gatewayip 192.168.10.1
=> setenv netmask 255.255.255.0

# Set NFS root path
=> setenv nfsroot /export/bbb-root

# Create boot command
=> setenv netboot '
    echo "Network Boot Starting...";
    dhcp;
    setenv bootargs console=ttyO0,115200n8 root=/dev/nfs rw nfsroot=${serverip}:${nfsroot},v3,tcp ip=dhcp;
    tftp ${loadaddr} zImage;
    tftp ${fdtaddr} am335x-boneblack.dtb;
    bootz ${loadaddr} - ${fdtaddr};
'

# Set as default boot command
=> setenv bootcmd 'run netboot'

# Save configuration
=> saveenv

# Test boot
=> run netboot
```

---

## Alternative: Manual TFTP Commands

```bash
# U-Boot manual commands for debugging

# Get IP via DHCP
=> dhcp

# Set server IP
=> setenv serverip 192.168.10.1

# Download kernel
=> tftp ${loadaddr} zImage
# Should show: Bytes transferred = xxxxx

# Download device tree
=> tftp ${fdtaddr} am335x-boneblack.dtb

# Set boot arguments for NFS
=> setenv bootargs console=ttyO0,115200n8 root=/dev/nfs rw \
    nfsroot=192.168.10.1:/export/bbb-root,v3,tcp ip=dhcp

# Boot
=> bootz ${loadaddr} - ${fdtaddr}
```

---

## Advanced: Development Workflow

### Auto-Rebuild and Test Script

```bash
#!/bin/bash
# deploy-and-boot.sh - Build, deploy, and boot BBB via network

set -e

SERVER_IP="192.168.10.1"
TFTP_DIR="/tftpboot"
NFS_DIR="/export/bbb-root"

echo "Building kernel..."
make -j$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage dtbs

echo "Deploying to TFTP..."
sudo cp arch/arm/boot/zImage $TFTP_DIR/
sudo cp arch/arm/boot/dts/am335x-boneblack.dtb $TFTP_DIR/

echo "Installing modules to NFS root..."
sudo make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
    INSTALL_MOD_PATH=$NFS_DIR modules_install

echo "Done! Reset BBB to boot new kernel."

# Optional: trigger reboot via SSH if BBB is running
# ssh root@192.168.10.50 "reboot" || true
```

### Multiple Board Support

```bash
# Directory structure for multiple boards
/tftpboot/
├── beaglebone-1/
│   ├── zImage
│   └── am335x-boneblack.dtb
├── beaglebone-2/
│   ├── zImage
│   └── am335x-boneblack.dtb
└── default/
    ├── zImage
    └── am335x-boneblack.dtb

/export/
├── bbb-root-dev/      # Development rootfs
├── bbb-root-test/     # Testing rootfs
└── bbb-root-prod/     # Production rootfs
```

**U-Boot config for specific board:**

```bash
=> setenv boardid beaglebone-1
=> setenv netboot '
    dhcp;
    tftp ${loadaddr} ${boardid}/zImage;
    tftp ${fdtaddr} ${boardid}/am335x-boneblack.dtb;
    setenv bootargs console=ttyO0,115200n8 root=/dev/nfs rw \
        nfsroot=${serverip}:/export/bbb-root-dev,v3,tcp ip=dhcp;
    bootz ${loadaddr} - ${fdtaddr};
'
```

---

## Troubleshooting

### DHCP Issues

```bash
# Check DHCP server status
sudo systemctl status dnsmasq
# or
sudo systemctl status isc-dhcp-server

# View DHCP leases
cat /var/lib/misc/dnsmasq.leases

# Debug DHCP
sudo tcpdump -i eth1 port 67 or port 68

# U-Boot DHCP debug
=> setenv ethact cpsw
=> dhcp
```

### TFTP Issues

```bash
# Test TFTP from server
tftp localhost -c get zImage

# Check permissions
ls -la /tftpboot/

# View TFTP logs
sudo journalctl -u tftpd-hpa

# Firewall rules
sudo ufw allow 69/udp
sudo ufw allow from 192.168.10.0/24
```

### NFS Issues

```bash
# Check NFS exports
showmount -e localhost

# Test NFS mount locally
sudo mount -t nfs localhost:/export/bbb-root /mnt

# Check NFS service
sudo systemctl status nfs-kernel-server

# View NFS logs
sudo journalctl -u nfs-kernel-server

# Firewall
sudo ufw allow from 192.168.10.0/24 to any port nfs
```

### Kernel Boot Issues

```bash
# Common bootargs problems:
# - Missing 'ip=dhcp' → no network config
# - Wrong nfsroot path → mount fails  
# - NFSv4 vs v3 mismatch → use 'nfsvers=3' or 'v3'

# Debug bootargs
=> printenv bootargs

# Test with minimal bootargs first
=> setenv bootargs console=ttyO0,115200n8 ip=dhcp root=/dev/nfs \
    nfsroot=192.168.10.1:/export/bbb-root,nfsvers=3,tcp
```

---

## Security Considerations

```
⚠️ Network boot has security implications:

1. TFTP is unencrypted and unauthenticated
   - Anyone on network can serve malicious images
   - Use isolated network for development

2. NFS root is accessible from network
   - Use no_root_squash carefully
   - Restrict to specific IP range

3. Consider for production:
   - HTTPS boot (U-Boot FIT with signatures)
   - Encrypted NFS or iSCSI
   - VPN/isolated VLAN
```

---

## Verification Checklist

- [ ] DHCP server assigns IP to BBB
- [ ] TFTP server serves zImage and DTB
- [ ] NFS export is accessible
- [ ] U-Boot can download kernel via TFTP
- [ ] Kernel boots with NFS root
- [ ] System reaches login prompt
- [ ] Network is functional after boot
- [ ] Files modified on server reflect on BBB
- [ ] Reboot works reliably

---

[← Previous: Custom Init](09_custom_init.md) | [Back to Index](README.md) | [Certification Project →](certification_project.md)
