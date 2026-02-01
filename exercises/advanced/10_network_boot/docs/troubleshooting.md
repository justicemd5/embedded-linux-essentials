# Network Boot Troubleshooting Guide
#
# Common problems and solutions for network boot
#
# Author: Embedded Linux Labs

## 1. DHCP Issues

### 1.1 No DHCP Response

**Symptom:**
```
U-Boot: DHCP client bound to address 0.0.0.0
U-Boot: TFTP error: 'Network unreachable'
```

**Causes and Solutions:**

| Cause | Diagnosis | Solution |
|-------|-----------|----------|
| DHCP server not running | `systemctl status dnsmasq` | `systemctl start dnsmasq` |
| Wrong interface | Check `interface=` in config | Fix interface name |
| Firewall blocking | `iptables -L` | Allow ports 67-68 UDP |
| Cable/link issue | Check LEDs | Replace cable |

**Debug Steps:**
```bash
# Server: Watch for DHCP requests
sudo tcpdump -i eth1 port 67 or port 68

# Check dnsmasq logs
sudo journalctl -u dnsmasq -f

# Check leases
cat /var/lib/misc/dnsmasq.leases
```

### 1.2 Wrong IP Assigned

**Symptom:**
Board gets IP in wrong range or wrong TFTP server address.

**Solutions:**
```bash
# Check dnsmasq configuration
cat /etc/dnsmasq.d/bbb-netboot.conf

# Verify interface binding
grep interface /etc/dnsmasq.d/*.conf

# Clear leases and restart
sudo rm /var/lib/misc/dnsmasq.leases
sudo systemctl restart dnsmasq
```

### 1.3 DHCP Option Not Received

**Symptom:**
IP assigned but TFTP server or boot file not set.

**Check U-Boot:**
```bash
=> printenv serverip
=> printenv bootfile
```

**Fix dnsmasq config:**
```
# Ensure these are set
dhcp-option=66,192.168.10.1    # TFTP server
dhcp-option=67,zImage          # Boot file
```

---

## 2. TFTP Issues

### 2.1 File Not Found

**Symptom:**
```
U-Boot: TFTP error: 'File not found' (1)
```

**Causes and Solutions:**

| Cause | Diagnosis | Solution |
|-------|-----------|----------|
| Wrong filename | Check exact name | Fix filename in U-Boot |
| Wrong path | Check TFTP root | Fix path |
| File missing | `ls /tftpboot/` | Copy file |
| Permission denied | `ls -la /tftpboot/` | `chmod 644` |

**Debug Steps:**
```bash
# Check file exists
ls -la /tftpboot/zImage

# Test TFTP locally
cd /tmp && tftp localhost -c get zImage

# Check TFTP root
grep TFTP_DIRECTORY /etc/default/tftpd-hpa

# Watch TFTP requests
sudo tcpdump -i eth1 port 69 -vv
```

### 2.2 TFTP Timeout

**Symptom:**
```
U-Boot: T T T T T T T
```

**Causes:**
- Firewall blocking UDP 69
- TFTP server not running
- Wrong server IP

**Solutions:**
```bash
# Check TFTP server status
systemctl status tftpd-hpa
# or for dnsmasq internal TFTP:
systemctl status dnsmasq

# Check port is listening
ss -uln | grep 69

# Open firewall
sudo ufw allow 69/udp
```

### 2.3 Transfer Incomplete

**Symptom:**
File downloads but kernel panic on boot.

**Causes:**
- File corruption
- Wrong file type (x86 instead of ARM)

**Verify file:**
```bash
# Check file architecture
file /tftpboot/zImage
# Should show: Linux kernel ARM boot executable

# Check file size matches transfer
ls -l /tftpboot/zImage
# U-Boot should show same "Bytes transferred"

# Verify checksum
md5sum /tftpboot/zImage
# Compare with original
```

---

## 3. NFS Issues

### 3.1 Mount Failed

**Symptom:**
```
Kernel: VFS: Unable to mount root fs via NFS
Kernel: Root-NFS: Server returned error -13
```

**Error Codes:**

| Error | Meaning | Solution |
|-------|---------|----------|
| -2 (ENOENT) | Path not found | Check nfsroot path |
| -13 (EACCES) | Permission denied | Check exports |
| -110 (ETIMEDOUT) | Network timeout | Check connectivity |
| -111 (ECONNREFUSED) | NFS not running | Start NFS server |

**Debug Steps:**
```bash
# Verify NFS server running
systemctl status nfs-kernel-server

# Check exports
showmount -e localhost
exportfs -v

# Test mount locally
sudo mount -t nfs localhost:/export/bbb-root /mnt

# Check firewall
sudo ufw status
sudo ufw allow from 192.168.10.0/24 to any port nfs
```

### 3.2 NFS Version Mismatch

**Symptom:**
```
Kernel: NFS: MOUNT reply contains no root file handle
```

**Solution:**
Specify NFS version in bootargs:
```bash
# For NFSv3 (recommended)
nfsroot=192.168.10.1:/export/bbb-root,v3,tcp

# Or NFSv4 (requires server config)
nfsroot=192.168.10.1:/export/bbb-root,v4
```

### 3.3 Stale File Handle

**Symptom:**
```
Stale file handle
```

**Cause:**
Server-side file changed while client had it cached.

**Solution:**
```bash
# On client (BBB)
sync
mount -o remount /

# Or reboot
reboot
```

---

## 4. Kernel Boot Issues

### 4.1 Kernel Panic - No init

**Symptom:**
```
Kernel panic - not syncing: No working init found.
```

**Causes:**
- init missing in rootfs
- Wrong architecture
- Missing libraries

**Debug:**
```bash
# On server - check rootfs
ls -la /export/bbb-root/sbin/init
file /export/bbb-root/sbin/init
# Should show: ARM, 32-bit

# Check for missing libraries
ls /export/bbb-root/lib/
```

### 4.2 Kernel Panic - Unable to mount root

**Symptom:**
```
VFS: Cannot open root device "nfs"
```

**Causes:**
- NFS not enabled in kernel
- Network driver not enabled

**Check kernel config:**
```bash
# Needed for NFS root
CONFIG_ROOT_NFS=y
CONFIG_NFS_FS=y
CONFIG_IP_PNP=y
CONFIG_IP_PNP_DHCP=y
```

### 4.3 No Network After Boot

**Symptom:**
Kernel boots but no network connectivity.

**Causes:**
- ip= parameter missing or wrong
- Network driver issue
- DHCP timeout

**Solutions:**
```bash
# Verify bootargs include ip=dhcp
=> printenv bootargs

# Or use static IP
ip=192.168.10.50::192.168.10.1:255.255.255.0:bbb:eth0:off

# Check kernel messages
dmesg | grep -i eth
dmesg | grep -i cpsw
```

---

## 5. Performance Issues

### 5.1 Slow NFS Performance

**Symptoms:**
- Slow file operations
- Long boot time
- Applications lag

**Optimizations:**

```bash
# Server: Increase NFS threads
# /etc/default/nfs-kernel-server
RPCNFSDCOUNT=8

# Server: Enable async (caution: less safe)
/export/bbb-root *(rw,async,no_subtree_check,no_root_squash)

# Client: Use optimal mount options (in kernel bootargs)
nfsroot=...,tcp,noatime,nodiratime,rsize=32768,wsize=32768
```

### 5.2 Slow TFTP Transfer

**Symptoms:**
- Kernel download takes minutes
- Progress dots appear slowly

**Optimizations:**
```bash
# Increase TFTP block size
# In dnsmasq.conf:
tftp-max-block-size=1024

# Or use tftpd-hpa with:
TFTP_OPTIONS="--secure --blocksize 1024"
```

---

## 6. Quick Reference

### 6.1 Essential Services

```bash
# Check all services
systemctl status dnsmasq
systemctl status nfs-kernel-server
systemctl status rpcbind

# Restart all
sudo systemctl restart dnsmasq
sudo systemctl restart nfs-kernel-server
```

### 6.2 Essential Commands

```bash
# Server checks
showmount -e localhost          # NFS exports
cat /var/lib/misc/dnsmasq.leases  # DHCP leases
ss -ulnp | grep -E ':(67|69) '   # DHCP/TFTP ports
ss -tlnp | grep :2049            # NFS port

# Network debug
tcpdump -i eth1 port 67 or port 68  # DHCP
tcpdump -i eth1 port 69             # TFTP
tcpdump -i eth1 port 2049           # NFS

# Firewall
sudo ufw status
sudo ufw allow from 192.168.10.0/24
```

### 6.3 U-Boot Debug

```bash
# Network test
=> ping 192.168.10.1

# Check variables
=> printenv ipaddr serverip

# Verbose TFTP
=> tftp ${loadaddr} zImage

# Reset to defaults
=> env default -a
=> saveenv
```

### 6.4 Kernel Bootargs Template

```
console=ttyO0,115200n8 root=/dev/nfs rw \
    nfsroot=192.168.10.1:/export/bbb-root,v3,tcp,nolock \
    ip=dhcp \
    rootwait
```

---

## 7. Diagnostic Flowchart

```
                        START
                          │
                          ▼
              ┌───────────────────┐
              │ DHCP working?     │
              │ (check leases)    │
              └─────────┬─────────┘
                       │
            ┌──────────┴──────────┐
            │                     │
           NO                    YES
            │                     │
            ▼                     ▼
    ┌───────────────┐   ┌───────────────────┐
    │ Check:        │   │ TFTP working?     │
    │ - dnsmasq     │   │ (tcpdump port 69) │
    │ - interface   │   └─────────┬─────────┘
    │ - firewall    │             │
    └───────────────┘   ┌─────────┴─────────┐
                        │                   │
                       NO                  YES
                        │                   │
                        ▼                   ▼
              ┌───────────────┐   ┌───────────────────┐
              │ Check:        │   │ Kernel boots?     │
              │ - tftpd       │   │ (serial console)  │
              │ - file path   │   └─────────┬─────────┘
              │ - permissions │             │
              └───────────────┘   ┌─────────┴─────────┐
                                  │                   │
                                 NO                  YES
                                  │                   │
                                  ▼                   ▼
                        ┌───────────────┐   ┌───────────────────┐
                        │ Check:        │   │ NFS mounts?       │
                        │ - file arch   │   │ (check root)      │
                        │ - DTB match   │   └─────────┬─────────┘
                        │ - bootargs    │             │
                        └───────────────┘   ┌─────────┴─────────┐
                                            │                   │
                                           NO                  YES
                                            │                   │
                                            ▼                   ▼
                                  ┌───────────────┐           DONE!
                                  │ Check:        │
                                  │ - NFS exports │
                                  │ - nfsroot=    │
                                  │ - ip=dhcp     │
                                  └───────────────┘
```
