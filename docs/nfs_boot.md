# NFS Boot Guide

A comprehensive guide to booting Embedded Linux systems with root filesystem over NFS.

## Why NFS Boot Matters

Network File System (NFS) boot is a powerful development technique in embedded Linux. Understanding it is essential because:

- **Rapid Development**: No need to reflash storage for each code change
- **Large Root FS**: Not limited by embedded storage size
- **Shared Development**: Multiple boards can share one rootfs
- **Easy Debugging**: Direct access to all files from host machine
- **Diskless Systems**: Production use for diskless/thin clients

## How NFS Boot Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         NFS BOOT OVERVIEW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                                                                             │
│   TARGET BOARD                              HOST MACHINE                    │
│  ┌────────────────────┐                   ┌────────────────────────────┐   │
│  │                    │                   │                            │   │
│  │  1. Boot ROM       │                   │  TFTP Server (:69)         │   │
│  │       │            │                   │  /tftpboot/                │   │
│  │  2. SPL            │                   │  ├── zImage                │   │
│  │       │            │                   │  └── board.dtb             │   │
│  │  3. U-Boot         │◄──── TFTP ───────►│                            │   │
│  │       │            │    (kernel+DTB)   │                            │   │
│  │  4. Linux Kernel   │                   │  NFS Server (:2049)        │   │
│  │       │            │                   │  /export/rootfs/           │   │
│  │  5. NFS Root ─────────── NFS ─────────►│  ├── bin/                  │   │
│  │       │            │    (rootfs)       │  ├── sbin/                 │   │
│  │  6. Application    │                   │  ├── lib/                  │   │
│  │                    │                   │  ├── etc/                  │   │
│  └────────────────────┘                   │  └── ...                   │   │
│          │                                │                            │   │
│          │                                └────────────────────────────┘   │
│          │                                         │                        │
│          └────────────────────────────────────────┘                        │
│                        ETHERNET                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## NFS Boot Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         NFS BOOT SEQUENCE                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Phase 1: U-Boot Network Setup                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Initialize network interface                                     │   │
│  │ 2. Get IP address (DHCP or static)                                  │   │
│  │ 3. Download kernel via TFTP                                         │   │
│  │ 4. Download DTB via TFTP                                            │   │
│  │ 5. Set bootargs with NFS root parameters                            │   │
│  │ 6. Boot kernel                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Phase 2: Kernel Network Initialization                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Parse bootargs for ip= and nfsroot=                              │   │
│  │ 2. Configure network interface (IP-Config)                          │   │
│  │    - Static IP from bootargs, or                                    │   │
│  │    - DHCP if ip=dhcp                                                │   │
│  │ 3. Mount NFS root filesystem                                        │   │
│  │ 4. Execute /sbin/init                                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Phase 3: Normal Boot                                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Init starts services                                             │   │
│  │ 2. All file access goes over NFS                                    │   │
│  │ 3. System operates normally                                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Host Setup: NFS Server

### Installing NFS Server (Ubuntu/Debian)

```bash
# Install NFS server packages
sudo apt-get update
sudo apt-get install -y nfs-kernel-server nfs-common

# Verify installation
systemctl status nfs-kernel-server
```

### Creating NFS Export Directory

```bash
# Create export directory
sudo mkdir -p /export/rootfs

# Extract or create root filesystem
# Option 1: Use existing rootfs tarball
sudo tar xf rootfs.tar -C /export/rootfs

# Option 2: Use debootstrap (for Debian/Ubuntu rootfs)
sudo debootstrap --arch=armhf --foreign bullseye /export/rootfs

# Option 3: Copy from SD card
sudo cp -a /media/user/rootfs/* /export/rootfs/

# Set permissions (important!)
sudo chown -R root:root /export/rootfs
sudo chmod 755 /export/rootfs
```

### Configuring NFS Exports

```bash
# Edit exports file
sudo nano /etc/exports
```

Add the following line:
```
# /etc/exports
# Format: <directory> <client>(options)

# Development: Allow any client on local network
/export/rootfs 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)

# Or for specific IP
/export/rootfs 192.168.1.50(rw,sync,no_subtree_check,no_root_squash)

# Or for any client (less secure)
/export/rootfs *(rw,sync,no_subtree_check,no_root_squash)
```

**Export Options Explained:**
| Option | Meaning |
|--------|---------|
| `rw` | Read-write access |
| `ro` | Read-only access |
| `sync` | Write changes to disk before replying |
| `no_subtree_check` | Disable subtree checking (improves reliability) |
| `no_root_squash` | Allow root on client to be root on server |
| `root_squash` | Map client root to nobody (more secure) |

```bash
# Apply changes
sudo exportfs -ra

# Verify exports
sudo exportfs -v
# Output: /export/rootfs  192.168.1.0/24(rw,sync,no_root_squash,...)

# Restart NFS server
sudo systemctl restart nfs-kernel-server

# Check NFS server is listening
sudo ss -tulpn | grep -E '2049|111'
```

### Setting Up TFTP Server

```bash
# Install TFTP server
sudo apt-get install -y tftpd-hpa

# Configure TFTP
sudo nano /etc/default/tftpd-hpa
```

```
# /etc/default/tftpd-hpa
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
```

```bash
# Create TFTP directory
sudo mkdir -p /tftpboot
sudo chmod 777 /tftpboot

# Copy kernel and DTB
sudo cp zImage /tftpboot/
sudo cp bcm2710-rpi-3-b.dtb /tftpboot/

# Restart TFTP server
sudo systemctl restart tftpd-hpa

# Verify TFTP is running
sudo systemctl status tftpd-hpa
```

## Target Setup: Kernel Configuration

### Required Kernel Options

```bash
# Enable NFS support
CONFIG_NETWORK_FILESYSTEMS=y
CONFIG_NFS_FS=y                  # NFS client support
CONFIG_NFS_V3=y                  # NFSv3 support
CONFIG_NFS_V4=y                  # NFSv4 support (optional)
CONFIG_ROOT_NFS=y                # Root filesystem on NFS

# IP configuration
CONFIG_IP_PNP=y                  # IP: kernel level autoconfiguration
CONFIG_IP_PNP_DHCP=y             # DHCP support
CONFIG_IP_PNP_BOOTP=y            # BOOTP support (optional)
CONFIG_IP_PNP_RARP=y             # RARP support (optional)

# Network driver (must be built-in, not module!)
CONFIG_NET_ETHERNET=y
# Your specific Ethernet driver, e.g.:
CONFIG_SMSC911X=y                # BeagleBone
CONFIG_GENET=y                   # Raspberry Pi 4
CONFIG_USB_NET_SMSC95XX=y        # Raspberry Pi 3 (USB Ethernet)
```

**Important**: For NFS root boot, the Ethernet driver **must** be built into the kernel (`=y`), not as a module (`=m`). The driver is needed before the root filesystem is mounted.

## Target Setup: U-Boot Configuration

### Manual NFS Boot Commands

```bash
# Set up network
=> setenv ipaddr 192.168.1.50        # Board IP
=> setenv serverip 192.168.1.100     # Server IP (TFTP + NFS)
=> setenv netmask 255.255.255.0
=> setenv gatewayip 192.168.1.1

# Verify network
=> ping ${serverip}

# Download kernel and DTB
=> tftp ${loadaddr} zImage
=> tftp ${fdt_addr} bcm2710-rpi-3-b.dtb

# Set NFS boot arguments
=> setenv bootargs console=ttyS0,115200 root=/dev/nfs \
    nfsroot=${serverip}:/export/rootfs,v3,tcp \
    ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}::eth0:off

# Boot
=> bootz ${loadaddr} - ${fdt_addr}
```

### NFS Bootargs Explained

```bash
# Full bootargs format
bootargs=console=ttyS0,115200 root=/dev/nfs \
    nfsroot=<server>:<path>,<options> \
    ip=<client>:<server>:<gateway>:<netmask>:<hostname>:<device>:<autoconf>
```

**nfsroot parameter:**
```
nfsroot=192.168.1.100:/export/rootfs,v3,tcp

192.168.1.100       # NFS server IP
:/export/rootfs     # Export path on server
,v3                 # Use NFSv3 (more compatible)
,tcp                # Use TCP (more reliable than UDP)
```

**ip parameter (manual configuration):**
```
ip=192.168.1.50:192.168.1.100:192.168.1.1:255.255.255.0:myboard:eth0:off

192.168.1.50        # Client IP
192.168.1.100       # Server IP
192.168.1.1         # Gateway
255.255.255.0       # Netmask
myboard             # Hostname
eth0                # Network interface
off                 # Don't use autoconf after setting IP
```

**ip parameter (DHCP):**
```
ip=dhcp              # Get everything from DHCP

# Or more specific
ip=:::::eth0:dhcp    # Use eth0, get IP from DHCP
```

### Persistent NFS Boot Configuration

```bash
# Create comprehensive NFS boot environment
=> setenv serverip 192.168.1.100
=> setenv nfs_root /export/rootfs

=> setenv nfs_args 'setenv bootargs console=${console} root=/dev/nfs \
    nfsroot=${serverip}:${nfs_root},v3,tcp ip=dhcp'

=> setenv nfs_boot 'run nfs_args; \
    tftp ${loadaddr} zImage; \
    tftp ${fdt_addr} ${fdtfile}; \
    bootz ${loadaddr} - ${fdt_addr}'

=> setenv bootcmd 'run nfs_boot'

=> saveenv
```

## Diskless Boot: Complete Network Boot

For fully diskless systems (no local storage at all):

### U-Boot in TFTP

```bash
# Some platforms support loading U-Boot via TFTP (PXE boot)
# Check your platform's ROM code capabilities

# Alternative: Use network boot with SD card for bootloader only
# SD card contents:
#   - SPL/MLO
#   - u-boot.img
#   - boot.scr (with NFS boot commands)
```

### Example boot.scr for NFS

```bash
# boot.cmd - source for boot.scr
echo "=== NFS Network Boot ==="

setenv serverip 192.168.1.100
setenv nfs_root /export/rootfs

# Get IP via DHCP
dhcp

# Download kernel and DTB
tftp ${loadaddr} zImage
tftp ${fdt_addr} ${fdtfile}

# Set NFS boot arguments
setenv bootargs console=ttyS0,115200 root=/dev/nfs \
    nfsroot=${serverip}:${nfs_root},v3,tcp ip=dhcp

# Boot
bootz ${loadaddr} - ${fdt_addr}
```

```bash
# Compile boot script
mkimage -C none -A arm -T script -d boot.cmd boot.scr
```

## Development Workflow with NFS

### Typical Development Cycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    NFS DEVELOPMENT WORKFLOW                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  On Host Machine:                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Edit source code                                                 │   │
│  │         │                                                           │   │
│  │ 2. Cross-compile                                                    │   │
│  │         │                                                           │   │
│  │ 3. Copy binary to NFS rootfs                                        │   │
│  │    cp myapp /export/rootfs/usr/bin/                                 │   │
│  │         │                                                           │   │
│  │    (No reboot needed!)                                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                           │                                                 │
│                           v                                                 │
│  On Target Board:                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 4. Run updated binary immediately                                   │   │
│  │    # /usr/bin/myapp                                                 │   │
│  │                                                                     │   │
│  │ 5. Debug, test, iterate                                             │   │
│  │                                                                     │   │
│  │    (All file changes visible instantly)                             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Advantages:                                                                │
│  • No SD card flashing required                                             │
│  • Changes visible immediately                                              │
│  • Can use host debugging tools on files                                    │
│  • Easy to test multiple binaries                                           │
│  • Can edit files on target, changes saved to host                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Kernel Module Development with NFS

```bash
# On host: Build module
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
    KERNEL_SRC=/path/to/linux modules

# Copy to NFS rootfs
cp mydriver.ko /export/rootfs/lib/modules/$(kernel_version)/

# On target: Load module (no reboot!)
insmod /lib/modules/$(uname -r)/mydriver.ko
dmesg | tail

# Test and iterate
rmmod mydriver
# Fix issues on host, copy again, reload
```

## Troubleshooting NFS Boot

### Common Issues and Solutions

**Issue 1: TFTP timeout**
```bash
# Check TFTP server is running
sudo systemctl status tftpd-hpa

# Check firewall
sudo ufw status
sudo ufw allow 69/udp

# Test from another Linux machine
tftp 192.168.1.100 -c get zImage
```

**Issue 2: NFS mount fails**
```bash
# Check NFS server is running
sudo systemctl status nfs-kernel-server

# Verify exports
sudo exportfs -v

# Check firewall (NFS uses multiple ports)
sudo ufw allow 2049/tcp
sudo ufw allow 2049/udp
sudo ufw allow 111/tcp
sudo ufw allow 111/udp

# Test mount from another Linux machine
sudo mount -t nfs 192.168.1.100:/export/rootfs /mnt
```

**Issue 3: "VFS: Unable to mount root fs via NFS"**
```bash
# Check kernel has NFS support built-in (not as module)
grep NFS /boot/config-$(uname -r)
# CONFIG_NFS_FS=y  <-- Must be y, not m

# Check kernel has network driver built-in
# Check IP autoconfiguration is enabled
# CONFIG_IP_PNP=y
# CONFIG_IP_PNP_DHCP=y
```

**Issue 4: Permission denied on NFS**
```bash
# Check no_root_squash is set in exports
cat /etc/exports
# Should have: no_root_squash

# Re-export
sudo exportfs -ra

# Check permissions
ls -la /export/rootfs
# Should be owned by root
```

### Debug Boot Arguments

```bash
# Add debug output to bootargs
bootargs=console=ttyS0,115200 root=/dev/nfs \
    nfsroot=192.168.1.100:/export/rootfs,v3,tcp \
    ip=dhcp \
    nfsrootdebug \
    debug \
    loglevel=8
```

## Performance Considerations

### NFS Performance Tips

```bash
# Use TCP instead of UDP (more reliable)
nfsroot=...,tcp

# Adjust rsize and wsize (default usually fine)
nfsroot=...,rsize=8192,wsize=8192

# Use NFSv3 for compatibility, NFSv4 for security
nfsroot=...,v3  # or v4
```

### Network Bottlenecks

| Factor | Impact | Mitigation |
|--------|--------|------------|
| 100Mbps Ethernet | Slow for large files | Use Gigabit if available |
| WiFi | Unreliable for NFS | Use wired Ethernet |
| Switch/hub | Network congestion | Use good quality switch |
| Cable quality | Packet loss | Use Cat5e or better |

## What You Learned

After reading this document, you understand:

1. ✅ What NFS boot is and when to use it
2. ✅ The complete NFS boot flow
3. ✅ How to set up an NFS server on the host
4. ✅ How to configure TFTP for kernel delivery
5. ✅ Required kernel configuration for NFS root
6. ✅ U-Boot configuration for NFS boot
7. ✅ How to use NFS for rapid development
8. ✅ Troubleshooting NFS boot issues

---

## Next Steps

1. Complete [Lab 06: NFS Boot](../06_nfs_boot/README.md)
2. Set up NFS development environment for your board
3. Practice the development workflow
