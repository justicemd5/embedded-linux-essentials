# Lab 06: NFS Boot

A hands-on lab for booting embedded Linux with root filesystem over NFS.

## Lab Objectives

By the end of this lab, you will be able to:

1. Set up NFS server on host machine
2. Configure TFTP for kernel delivery
3. Configure U-Boot for network boot
4. Boot target with NFS root filesystem
5. Use NFS for rapid development workflow

## Prerequisites

- Completed [Lab 02: U-Boot](../02_uboot/README.md)
- Target board with Ethernet connection
- Host machine on same network
- Root filesystem (from Buildroot, Yocto, or distro)

## Lab Structure

```
06_nfs_boot/
├── README.md              ← This file
└── setup_nfs_server.md    ← Detailed NFS server setup guide
```

---

## Part 1: Host Setup

### Install Required Packages

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y nfs-kernel-server tftpd-hpa

# Fedora/RHEL
sudo dnf install -y nfs-utils tftp-server

# Verify services
systemctl status nfs-kernel-server
systemctl status tftpd-hpa
```

### Create NFS Export Directory

```bash
# Create rootfs directory
sudo mkdir -p /export/rootfs

# Extract or copy your root filesystem
# Option 1: From tarball
sudo tar xf rootfs.tar -C /export/rootfs

# Option 2: From SD card
sudo cp -a /media/sdcard/rootfs/* /export/rootfs/

# Set permissions
sudo chown -R root:root /export/rootfs
sudo chmod 755 /export/rootfs
```

### Configure NFS Exports

```bash
# Edit exports file
sudo nano /etc/exports
```

Add this line:
```
/export/rootfs  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
```

```bash
# Apply changes
sudo exportfs -ra

# Verify
sudo exportfs -v
```

### Configure TFTP Server

```bash
# Edit TFTP configuration
sudo nano /etc/default/tftpd-hpa
```

```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
```

```bash
# Create TFTP directory
sudo mkdir -p /tftpboot
sudo chmod 777 /tftpboot

# Copy boot files
sudo cp zImage /tftpboot/
sudo cp *.dtb /tftpboot/

# Restart TFTP
sudo systemctl restart tftpd-hpa
```

---

## Part 2: Network Configuration

### Host Network

```bash
# Check host IP
ip addr show
# Note your IP, e.g., 192.168.1.100

# Verify NFS is listening
sudo ss -tulpn | grep 2049

# Verify TFTP is listening
sudo ss -tulpn | grep 69
```

### Test from Another Linux Machine

```bash
# Test TFTP
tftp 192.168.1.100 -c get zImage

# Test NFS
sudo mount -t nfs 192.168.1.100:/export/rootfs /mnt
ls /mnt
sudo umount /mnt
```

---

## Part 3: Target U-Boot Configuration

### Manual Boot Commands

```bash
# At U-Boot prompt:

# Set IP addresses
=> setenv ipaddr 192.168.1.50
=> setenv serverip 192.168.1.100
=> setenv netmask 255.255.255.0
=> setenv gatewayip 192.168.1.1

# Test network
=> ping ${serverip}

# Download kernel via TFTP
=> tftp ${loadaddr} zImage
# You should see: Bytes transferred = ...

# Download DTB
=> tftp ${fdt_addr} bcm2710-rpi-3-b.dtb

# Set NFS boot arguments
=> setenv bootargs console=ttyS0,115200 root=/dev/nfs nfsroot=${serverip}:/export/rootfs,v3,tcp ip=dhcp

# Boot
=> bootz ${loadaddr} - ${fdt_addr}
```

### Persistent Network Boot Configuration

```bash
# Create reusable environment
=> setenv serverip 192.168.1.100
=> setenv nfs_root /export/rootfs

# Network arguments
=> setenv nfs_args 'setenv bootargs console=${console} root=/dev/nfs nfsroot=${serverip}:${nfs_root},v3,tcp ip=dhcp'

# TFTP load commands
=> setenv tftp_kernel 'tftp ${loadaddr} zImage'
=> setenv tftp_fdt 'tftp ${fdt_addr} ${fdtfile}'

# Complete NFS boot command
=> setenv nfs_boot 'dhcp; run nfs_args; run tftp_kernel; run tftp_fdt; bootz ${loadaddr} - ${fdt_addr}'

# Set as default boot
=> setenv bootcmd 'run nfs_boot'

# Save
=> saveenv
```

---

## Part 4: Kernel Configuration

Ensure your kernel has these options enabled:

```bash
# Required options (must be =y, not =m for root NFS)
CONFIG_NET=y
CONFIG_INET=y
CONFIG_IP_PNP=y
CONFIG_IP_PNP_DHCP=y
CONFIG_NFS_FS=y
CONFIG_NFS_V3=y
CONFIG_ROOT_NFS=y

# Your Ethernet driver (must be built-in!)
CONFIG_NET_ETHERNET=y
# Plus your specific driver, e.g.:
CONFIG_USB_NET_SMSC95XX=y     # Raspberry Pi 3
CONFIG_BCMGENET=y             # Raspberry Pi 4
CONFIG_TI_CPSW=y              # BeagleBone
```

---

## Part 5: Development Workflow

### The Power of NFS Development

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    NFS DEVELOPMENT CYCLE                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   On Host (192.168.1.100):                                                  │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ 1. Edit source code                                                 │   │
│   │ 2. Cross-compile                                                    │   │
│   │ 3. Copy to NFS rootfs:                                              │   │
│   │    cp myapp /export/rootfs/usr/bin/                                 │   │
│   │                                                                     │   │
│   │    NO REBOOT NEEDED!                                                │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                      │                                       │
│                                      v                                       │
│   On Target (192.168.1.50):                                                 │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ 4. Run updated binary immediately:                                  │   │
│   │    /usr/bin/myapp                                                   │   │
│   │                                                                     │   │
│   │    Changes visible instantly!                                       │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Kernel Module Development

```bash
# On host: Build module
cd my_driver
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
     KERNEL_DIR=/path/to/linux modules

# Copy to NFS rootfs
sudo cp my_driver.ko /export/rootfs/lib/modules/$(kernel_version)/

# On target: Load immediately
insmod /lib/modules/$(uname -r)/my_driver.ko
dmesg | tail

# Unload, fix, rebuild, copy, reload - no reboot!
rmmod my_driver
```

---

## Lab Exercises

### Exercise 1: Basic NFS Boot

1. Set up NFS server on host
2. Configure TFTP with kernel and DTB
3. Boot target via NFS
4. Verify by checking mounts: `mount | grep nfs`

### Exercise 2: Development Cycle

1. Create a simple "Hello World" application on host
2. Cross-compile and copy to NFS rootfs
3. Run on target
4. Modify, recompile, copy
5. Run updated version without reboot

### Exercise 3: Kernel Module Development

1. Create simple kernel module
2. Build against your kernel tree
3. Copy to NFS rootfs
4. Load and test on target
5. Iterate without rebooting

### Exercise 4: Mixed Boot

1. Boot kernel from SD card
2. Use NFS for root filesystem
3. Combine advantages of both methods

---

## Troubleshooting

### TFTP Issues

```bash
# "TFTP error: 'File not found'"
# - Check file exists in /tftpboot
# - Check filename matches exactly (case sensitive)
ls -la /tftpboot/

# "TFTP timeout"
# - Check firewall
sudo ufw allow 69/udp
# - Check TFTP service running
sudo systemctl status tftpd-hpa
```

### NFS Mount Fails

```bash
# "VFS: Unable to mount root fs via NFS"

# On host, check:
# - NFS server running
sudo systemctl status nfs-kernel-server
# - Export configured
sudo exportfs -v
# - Firewall
sudo ufw allow from 192.168.1.0/24

# On target, check:
# - Network working (can ping?)
# - Kernel has NFS support built-in
# - Kernel has network driver built-in
```

### Permission Errors

```bash
# "Permission denied" on NFS

# Check exports has no_root_squash
cat /etc/exports
# Should have: no_root_squash

# Re-export
sudo exportfs -ra
```

---

## What You Learned

After completing this lab:

1. ✅ NFS server setup and configuration
2. ✅ TFTP server for kernel delivery
3. ✅ U-Boot network boot configuration
4. ✅ NFS-based development workflow
5. ✅ Rapid application and module iteration

---

## Next Lab

Continue to [Lab 07: Recovery](../07_recovery/README.md) for board recovery techniques.
