# Setting Up NFS Server for Embedded Linux Development

Complete guide to setting up an NFS server for network-booted embedded Linux systems.

## Overview

This guide walks you through setting up:
1. NFS server for root filesystem export
2. TFTP server for kernel/DTB delivery
3. Proper permissions and security
4. Troubleshooting common issues

---

## Part 1: NFS Server Installation

### Ubuntu/Debian

```bash
# Install NFS server packages
sudo apt-get update
sudo apt-get install -y nfs-kernel-server nfs-common

# Verify installation
dpkg -l | grep nfs
```

### Fedora/RHEL/CentOS

```bash
# Install NFS utilities
sudo dnf install -y nfs-utils

# Enable and start services
sudo systemctl enable --now nfs-server
sudo systemctl enable --now rpcbind
```

### Arch Linux

```bash
sudo pacman -S nfs-utils
sudo systemctl enable --now nfs-server
```

---

## Part 2: Create Root Filesystem Directory

### Create Export Directory

```bash
# Create the export directory
sudo mkdir -p /export/rootfs

# Set ownership
sudo chown root:root /export/rootfs
sudo chmod 755 /export/rootfs
```

### Populate with Root Filesystem

**Option A: Extract from tarball**
```bash
# If you have a rootfs tarball
sudo tar xf rootfs.tar -C /export/rootfs
```

**Option B: Copy from SD card**
```bash
# Mount SD card rootfs partition
sudo mount /dev/sdX2 /mnt

# Copy contents
sudo cp -a /mnt/* /export/rootfs/

# Unmount
sudo umount /mnt
```

**Option C: Use debootstrap (Debian/Ubuntu rootfs)**
```bash
# Install debootstrap
sudo apt-get install debootstrap qemu-user-static

# Create ARM rootfs
sudo debootstrap --arch=armhf --foreign bullseye /export/rootfs

# Complete second stage on target or with QEMU
```

**Option D: Use Buildroot output**
```bash
# From Buildroot output directory
sudo tar xf output/images/rootfs.tar -C /export/rootfs
```

---

## Part 3: Configure NFS Exports

### Edit /etc/exports

```bash
sudo nano /etc/exports
```

### Export Configuration Examples

**Basic development setup (single subnet):**
```
/export/rootfs  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
```

**Specific IP only:**
```
/export/rootfs  192.168.1.50(rw,sync,no_subtree_check,no_root_squash)
```

**Multiple boards:**
```
/export/rootfs_rpi    192.168.1.50(rw,sync,no_subtree_check,no_root_squash)
/export/rootfs_bbb    192.168.1.51(rw,sync,no_subtree_check,no_root_squash)
```

**Read-only export (more secure):**
```
/export/rootfs  192.168.1.0/24(ro,sync,no_subtree_check,root_squash)
```

### Export Options Explained

| Option | Description |
|--------|-------------|
| `rw` | Read-write access |
| `ro` | Read-only access |
| `sync` | Write changes to disk before replying |
| `async` | Reply before writing (faster, riskier) |
| `no_subtree_check` | Disable subtree checking (more reliable) |
| `no_root_squash` | Allow root on client to be root on server |
| `root_squash` | Map root to nobody (more secure) |
| `all_squash` | Map all users to nobody |
| `anonuid=1000` | UID to map anonymous users to |
| `anongid=1000` | GID to map anonymous groups to |

### Apply Configuration

```bash
# Export all configured shares
sudo exportfs -ra

# Verify exports
sudo exportfs -v

# Expected output:
# /export/rootfs  192.168.1.0/24(rw,sync,wdelay,no_root_squash,no_subtree_check,...)
```

---

## Part 4: Service Management

### Start/Restart Services

```bash
# Ubuntu/Debian
sudo systemctl restart nfs-kernel-server

# Fedora/RHEL
sudo systemctl restart nfs-server

# Check status
sudo systemctl status nfs-kernel-server
```

### Verify NFS is Listening

```bash
# Check RPC services
rpcinfo -p localhost

# Expected output should include:
#    100003    3   tcp   2049  nfs
#    100003    4   tcp   2049  nfs
#    100005    3   tcp  20048  mountd

# Check NFS port specifically
sudo ss -tulpn | grep 2049
```

---

## Part 5: Firewall Configuration

### UFW (Ubuntu)

```bash
# Allow NFS from local network
sudo ufw allow from 192.168.1.0/24 to any port nfs
sudo ufw allow from 192.168.1.0/24 to any port 111  # rpcbind

# Or allow all NFS-related
sudo ufw allow nfs

# Check status
sudo ufw status
```

### Firewalld (Fedora/RHEL)

```bash
# Allow NFS service
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-all
```

### iptables (Direct)

```bash
# Allow NFS (TCP and UDP)
sudo iptables -A INPUT -p tcp --dport 2049 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 2049 -j ACCEPT

# Allow rpcbind
sudo iptables -A INPUT -p tcp --dport 111 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 111 -j ACCEPT

# Allow mountd (may use dynamic port, fixed in /etc/nfs.conf)
sudo iptables -A INPUT -p tcp --dport 20048 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 20048 -j ACCEPT
```

---

## Part 6: TFTP Server Setup

### Install TFTP Server

```bash
# Ubuntu/Debian
sudo apt-get install -y tftpd-hpa

# Fedora/RHEL
sudo dnf install -y tftp-server
```

### Configure TFTP

Edit `/etc/default/tftpd-hpa`:
```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
```

### Create TFTP Directory

```bash
sudo mkdir -p /tftpboot
sudo chmod 777 /tftpboot  # or set proper ownership
```

### Copy Boot Files

```bash
# Copy kernel
sudo cp /path/to/zImage /tftpboot/

# Copy device tree
sudo cp /path/to/*.dtb /tftpboot/

# List contents
ls -la /tftpboot/
```

### Start TFTP Service

```bash
sudo systemctl enable --now tftpd-hpa
sudo systemctl status tftpd-hpa
```

### Firewall for TFTP

```bash
# UFW
sudo ufw allow 69/udp

# Firewalld
sudo firewall-cmd --permanent --add-service=tftp
sudo firewall-cmd --reload
```

---

## Part 7: Testing

### Test NFS from Another Linux Machine

```bash
# Show available exports
showmount -e 192.168.1.100

# Mount and verify
sudo mount -t nfs 192.168.1.100:/export/rootfs /mnt
ls /mnt
df -h /mnt
sudo umount /mnt
```

### Test TFTP

```bash
# Install TFTP client
sudo apt-get install tftp-hpa

# Test download
cd /tmp
tftp 192.168.1.100 -c get zImage
ls -la zImage
```

---

## Part 8: Common Issues

### "Permission denied"

```bash
# Check exports
sudo exportfs -v | grep no_root_squash

# If missing, add to /etc/exports and re-export
sudo exportfs -ra
```

### "mount.nfs: access denied"

```bash
# Check firewall
sudo ufw status

# Check export allows your IP
cat /etc/exports

# Check NFS version (v3 is more compatible)
sudo mount -t nfs -o vers=3 server:/path /mnt
```

### "RPC: Program not registered"

```bash
# Start rpcbind
sudo systemctl start rpcbind

# Then restart NFS
sudo systemctl restart nfs-kernel-server
```

### "Connection refused"

```bash
# Verify services are running
sudo systemctl status nfs-kernel-server
sudo systemctl status rpcbind

# Check correct port
sudo ss -tulpn | grep 2049
```

---

## Part 9: Advanced Configuration

### Fixed NFS Ports (for Firewall)

Edit `/etc/nfs.conf`:
```ini
[mountd]
port=20048

[statd]
port=32765

[lockd]
port=32766
```

Restart services:
```bash
sudo systemctl restart nfs-kernel-server
```

### NFSv4 Only (More Secure)

```bash
# In /etc/exports, use fsid option
/export/rootfs  192.168.1.0/24(rw,sync,fsid=0,no_subtree_check,no_root_squash)

# Client mounts as:
mount -t nfs4 192.168.1.100:/ /mnt
```

### Monitoring NFS

```bash
# Show current NFS statistics
nfsstat

# Show connected clients
sudo ss -tn | grep 2049

# Real-time monitoring
watch -n 1 'nfsstat -c'
```

---

## Quick Reference

### Commands Summary

```bash
# Export/refresh shares
sudo exportfs -ra

# List exports
sudo exportfs -v

# Restart NFS
sudo systemctl restart nfs-kernel-server

# Check status
sudo systemctl status nfs-kernel-server

# Test from client
showmount -e <server-ip>
sudo mount -t nfs <server>:/export/rootfs /mnt
```

### Typical /etc/exports for Development

```
# Development board - full access
/export/rootfs  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)

# TFTP directory (if serving via NFS too)
/tftpboot       192.168.1.0/24(ro,sync,no_subtree_check)
```
