# Network Boot Theory and Architecture
#
# Comprehensive guide to network boot concepts for embedded systems
#
# Author: Embedded Linux Labs

## 1. Network Boot Overview

### 1.1 What is Network Boot?

Network boot (also known as netboot or PXE boot) allows a system to boot
over a network without local storage. The boot files (kernel, device tree,
root filesystem) are retrieved from network servers.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    NETWORK BOOT ARCHITECTURE                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  BeagleBone Black                        Development Server             │
│  ┌────────────────┐                      ┌────────────────────┐        │
│  │                │                      │                    │        │
│  │   U-Boot       │                      │   DHCP Server      │        │
│  │                │      ┌───────────────│   (dnsmasq)        │        │
│  │   ↓ DHCP      ←──────┤   Network      │                    │        │
│  │   ↓ TFTP      ←──────┤   (Ethernet)   │   TFTP Server      │        │
│  │   ↓ Boot       │      └───────────────│   (/tftpboot/)     │        │
│  │                │                      │                    │        │
│  │   Kernel       │                      │   NFS Server       │        │
│  │   ↓ NFS mount ←───────────────────────│   (/export/root/)  │        │
│  │   ↓            │                      │                    │        │
│  │   Userspace    │                      │                    │        │
│  │                │                      │                    │        │
│  └────────────────┘                      └────────────────────┘        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Why Use Network Boot?

| Advantage | Description |
|-----------|-------------|
| **Rapid Development** | Change kernel/rootfs on server, no SD card reflashing |
| **Diskless Operation** | No wear on SD cards, reduces failure points |
| **Centralized Management** | Single source of truth for all boards |
| **Easy A/B Testing** | Switch between different configurations |
| **CI/CD Integration** | Automated testing on real hardware |
| **Factory Programming** | Initial provisioning of devices |

### 1.3 Disadvantages

| Disadvantage | Mitigation |
|--------------|------------|
| Network dependency | Fall back to local boot |
| Latency | NFS caching, fast network |
| Security | Use encrypted NFS, VLANs |
| Bandwidth | Use initramfs for many devices |

## 2. Network Boot Protocols

### 2.1 DHCP (Dynamic Host Configuration Protocol)

DHCP assigns network configuration to the booting device.

```
DHCP Message Exchange:

Client                              Server
  |                                   |
  |  DHCPDISCOVER (broadcast)         |
  |---------------------------------->|
  |                                   |
  |         DHCPOFFER                 |
  |<----------------------------------|
  |  (IP, netmask, gateway, options)  |
  |                                   |
  |  DHCPREQUEST                      |
  |---------------------------------->|
  |                                   |
  |         DHCPACK                   |
  |<----------------------------------|
  |                                   |
```

**Key DHCP Options for Network Boot:**

| Option | Number | Purpose |
|--------|--------|---------|
| Subnet Mask | 1 | Network configuration |
| Router | 3 | Default gateway |
| DNS Servers | 6 | Name resolution |
| Hostname | 12 | Client hostname |
| Domain Name | 15 | DNS domain |
| TFTP Server | 66 | Server for boot files |
| Boot Filename | 67 | File to download first |
| Vendor Options | 43 | Custom vendor data |

### 2.2 TFTP (Trivial File Transfer Protocol)

TFTP is a simple, connectionless file transfer protocol used to download
boot files because it's small enough to implement in bootloaders.

```
TFTP Transfer:

Client                              Server
  |                                   |
  |  RRQ (Read Request)               |
  |  filename="zImage"                |
  |---------------------------------->|
  |                                   |
  |  DATA block 1 (512 bytes)         |
  |<----------------------------------|
  |                                   |
  |  ACK block 1                      |
  |---------------------------------->|
  |                                   |
  |  DATA block 2 (512 bytes)         |
  |<----------------------------------|
  |                                   |
  |  ACK block 2                      |
  |---------------------------------->|
  |                                   |
  |  ... (continues until done)       |
  |                                   |
```

**TFTP Characteristics:**
- UDP port 69
- No authentication
- No encryption
- Block size: 512 bytes (default), configurable
- Simple protocol for bootloader implementation

**TFTP vs Other Protocols:**

| Protocol | Security | Speed | Bootloader Support |
|----------|----------|-------|-------------------|
| TFTP | None | Medium | Excellent |
| HTTP | Optional | Fast | Limited |
| NFS | Optional | Fast | Rare |
| FTP | Password | Medium | Some |

### 2.3 NFS (Network File System)

NFS provides the root filesystem over the network after kernel boot.

```
NFS Mount Process:

Kernel                              NFS Server
  |                                   |
  |  Portmap query (port 111)         |
  |---------------------------------->|
  |  RPC program ports                |
  |<----------------------------------|
  |                                   |
  |  Mount request (mountd)           |
  |---------------------------------->|
  |  File handle                      |
  |<----------------------------------|
  |                                   |
  |  NFS operations (port 2049)       |
  |<--------------------------------->|
  |  (read, write, lookup, etc.)      |
  |                                   |
```

**NFS Versions:**

| Version | Features |
|---------|----------|
| NFSv3 | Stateless, simple, widely compatible |
| NFSv4 | Stateful, better security, single port |

**NFS Mount Options for Boot:**

| Option | Purpose |
|--------|---------|
| ro/rw | Read-only or read-write |
| tcp/udp | Transport protocol |
| nolock | Skip NFS locking (faster) |
| nfsvers=3/4 | NFS version |
| proto=tcp | Force TCP |

## 3. Boot Sequence

### 3.1 Complete Boot Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    NETWORK BOOT SEQUENCE                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Power On                                                            │
│     │                                                                   │
│     ▼                                                                   │
│  2. ROM Bootloader                                                      │
│     └─► Loads SPL/MLO from MMC/UART/USB                                │
│         │                                                               │
│         ▼                                                               │
│  3. SPL (Secondary Program Loader)                                      │
│     └─► Initializes RAM, loads U-Boot                                  │
│         │                                                               │
│         ▼                                                               │
│  4. U-Boot                                                              │
│     ├─► Initialize network interface                                   │
│     ├─► Send DHCP DISCOVER                                             │
│     ├─► Receive DHCP OFFER/ACK                                         │
│     │   └─► Get: IP, netmask, gateway, TFTP server                    │
│     ├─► TFTP download: kernel (zImage)                                 │
│     ├─► TFTP download: device tree (*.dtb)                             │
│     ├─► (Optional) TFTP download: initramfs                            │
│     ├─► Set bootargs with NFS root                                     │
│     └─► Boot kernel (bootz)                                            │
│         │                                                               │
│         ▼                                                               │
│  5. Linux Kernel                                                        │
│     ├─► Initialize hardware                                            │
│     ├─► Process device tree                                            │
│     ├─► Configure network via ip= parameter                           │
│     ├─► NFS mount root filesystem                                      │
│     └─► Execute /sbin/init                                             │
│         │                                                               │
│         ▼                                                               │
│  6. Init/Userspace                                                      │
│     ├─► Mount /proc, /sys, etc.                                        │
│     ├─► Start services                                                 │
│     └─► Login prompt                                                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 U-Boot Network Commands

```bash
# Get IP via DHCP
=> dhcp

# Set static IP
=> setenv ipaddr 192.168.10.50
=> setenv serverip 192.168.10.1
=> setenv gatewayip 192.168.10.1
=> setenv netmask 255.255.255.0

# Download file via TFTP
=> tftp ${loadaddr} zImage
# Shows: Bytes transferred = 5234688 (4fde00 hex)

# Download device tree
=> tftp ${fdtaddr} am335x-boneblack.dtb

# Boot with NFS root
=> setenv bootargs console=ttyO0,115200n8 \
    root=/dev/nfs rw \
    nfsroot=192.168.10.1:/export/bbb-root,v3,tcp \
    ip=dhcp
=> bootz ${loadaddr} - ${fdtaddr}
```

### 3.3 Kernel IP Configuration

The `ip=` kernel parameter configures networking before NFS mount:

```
ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>

Examples:
  ip=dhcp                          # Use DHCP
  ip=::::::dhcp                    # Same as above
  ip=192.168.10.50::192.168.10.1:255.255.255.0:bbb:eth0:off
                                   # Static configuration
```

| Field | Description |
|-------|-------------|
| client-ip | IP address of client |
| server-ip | IP address of NFS server |
| gw-ip | Gateway IP |
| netmask | Network mask |
| hostname | Client hostname |
| device | Network device (eth0) |
| autoconf | off, dhcp, bootp, rarp |

## 4. Server Configuration

### 4.1 Directory Structure

```
Server Filesystem:

/tftpboot/                    ← TFTP root
├── zImage                    ← Linux kernel
├── am335x-boneblack.dtb      ← Device tree
├── initramfs.cpio.gz         ← Optional initramfs
├── overlays/                 ← Device tree overlays
│   └── *.dtbo
└── boards/                   ← Per-board files
    ├── bbb-01/
    │   ├── zImage
    │   └── *.dtb
    └── bbb-02/
        └── ...

/export/                      ← NFS exports root
├── bbb-root/                 ← Main development rootfs
│   ├── bin/
│   ├── sbin/
│   ├── etc/
│   ├── lib/
│   ├── usr/
│   └── ...
├── bbb-prod/                 ← Production rootfs
└── bbb-test/                 ← Testing rootfs
```

### 4.2 dnsmasq vs ISC DHCP + tftpd-hpa

| Feature | dnsmasq | ISC DHCP + tftpd-hpa |
|---------|---------|---------------------|
| Configuration | Single file | Two files |
| Complexity | Simple | More flexible |
| DNS | Included | Separate |
| TFTP | Included | Separate |
| Resources | Low | Medium |
| Best for | Development | Production |

### 4.3 NFS Export Options

```
/export/bbb-root 192.168.10.0/24(rw,sync,no_subtree_check,no_root_squash)
```

| Option | Description |
|--------|-------------|
| rw | Read-write access |
| ro | Read-only access |
| sync | Synchronous writes (safer) |
| async | Asynchronous writes (faster) |
| no_subtree_check | Skip subtree checking |
| no_root_squash | Allow root access |
| root_squash | Map root to nobody |
| all_squash | Map all users to nobody |

## 5. Debugging

### 5.1 Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| No DHCP | "DHCP client bound to address 0.0.0.0" | Check DHCP server, interface |
| TFTP timeout | "TFTP error: 'File not found'" | Check TFTP path, permissions |
| NFS mount fail | "VFS: Unable to mount root fs" | Check NFS exports, firewall |
| Wrong kernel | Boots but crashes | Check architecture (ARM) |
| No network | No IP after boot | Check ip= bootarg |

### 5.2 Debugging Commands

**On Server:**
```bash
# Check DHCP
sudo journalctl -u dnsmasq -f
cat /var/lib/misc/dnsmasq.leases

# Check TFTP
sudo tcpdump -i eth1 port 69

# Check NFS
showmount -e localhost
sudo tcpdump -i eth1 port 2049

# Test TFTP
tftp 192.168.10.1 -c get zImage

# Test NFS
sudo mount -t nfs 192.168.10.1:/export/bbb-root /mnt
```

**On BeagleBone (U-Boot):**
```bash
# Check network
=> ping 192.168.10.1

# Verbose TFTP
=> setenv ethact cpsw
=> tftpboot ${loadaddr} zImage

# Print network info
=> printenv ipaddr serverip
```

**On BeagleBone (Linux):**
```bash
# Check NFS mounts
mount | grep nfs
cat /proc/mounts

# Check network
ip addr
ping 192.168.10.1
```

### 5.3 tcpdump Filters

```bash
# All network boot traffic
tcpdump -i eth1 'port 67 or port 68 or port 69 or port 2049 or port 111'

# DHCP only
tcpdump -i eth1 'port 67 or port 68'

# TFTP only  
tcpdump -i eth1 'port 69'

# NFS only
tcpdump -i eth1 'port 2049'

# Specific host
tcpdump -i eth1 host 192.168.10.50
```

## 6. Advanced Configurations

### 6.1 Multiple Boards

```
Board-specific TFTP directories:

/tftpboot/
├── common/
│   └── zImage              ← Shared kernel
├── bbb-01/
│   └── am335x-boneblack.dtb  ← Board-specific DTB
└── bbb-02/
    └── am335x-boneblack.dtb
```

U-Boot per-board configuration:
```bash
# Set board ID
=> setenv boardid bbb-01

# Use board-specific files
=> tftp ${loadaddr} common/zImage
=> tftp ${fdtaddr} ${boardid}/am335x-boneblack.dtb
```

### 6.2 Read-Only Root with Overlay

For production, use a read-only NFS root with a tmpfs overlay:

```bash
# Kernel bootargs
root=/dev/nfs nfsroot=...,ro

# In init script:
mount -t tmpfs tmpfs /tmp
mount -t overlay overlay -o lowerdir=/,upperdir=/tmp/upper,workdir=/tmp/work /merged
pivot_root /merged /merged/mnt
```

### 6.3 Initramfs + NFS

Use initramfs to set up complex boot scenarios:

```bash
# U-Boot
=> tftp ${loadaddr} zImage
=> tftp ${fdtaddr} am335x-boneblack.dtb
=> tftp ${rdaddr} initramfs.cpio.gz
=> setenv bootargs console=ttyO0,115200n8
=> bootz ${loadaddr} ${rdaddr}:${filesize} ${fdtaddr}
```

In initramfs `/init`:
```bash
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys

# Configure network
ip addr add 192.168.10.50/24 dev eth0
ip link set eth0 up

# Mount NFS
mkdir /newroot
mount -t nfs 192.168.10.1:/export/bbb-root /newroot

# Switch to NFS root
exec switch_root /newroot /sbin/init
```

## 7. Security Considerations

### 7.1 Risks

| Risk | Description |
|------|-------------|
| Unauthenticated TFTP | Anyone can serve malicious images |
| NFS root squash | Root access to all files |
| Network sniffing | All traffic is unencrypted |
| DHCP spoofing | Man-in-the-middle attacks |

### 7.2 Mitigations

| Mitigation | Implementation |
|------------|----------------|
| Isolated network | Dedicated VLAN for development |
| Signed images | U-Boot FIT image verification |
| NFSv4 + Kerberos | Encrypted, authenticated NFS |
| 802.1X | Port-based network access control |
| VPN | Encrypt all traffic |

### 7.3 Production Recommendations

1. **Don't use network boot in production** unless necessary
2. Use signed boot images (see Secure Boot exercise)
3. Isolate development network from production
4. Implement network segmentation
5. Use encrypted protocols where possible

## 8. Resources

- U-Boot Network Documentation
- Linux NFS Documentation
- RFC 2131 (DHCP)
- RFC 1350 (TFTP)
- "Embedded Linux Primer" by Christopher Hallinan
