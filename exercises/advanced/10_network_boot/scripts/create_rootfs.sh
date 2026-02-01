#!/bin/bash
#
# create_rootfs.sh - Create or populate rootfs for NFS boot
#
# Creates a bootable root filesystem for BeagleBone Black NFS boot
#
# Usage:
#   ./create_rootfs.sh [OPTIONS]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

# ==========================================================================
# CONFIGURATION
# ==========================================================================

NFS_ROOT="${NFS_ROOT:-/export/bbb-root}"
HOSTNAME="${HOSTNAME:-beaglebone-nfs}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}==>${NC} $1"; }

# ==========================================================================
# FUNCTIONS
# ==========================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

create_directory_structure() {
    log_step "Creating directory structure..."
    
    mkdir -p "$NFS_ROOT"/{bin,sbin,etc,proc,sys,dev,tmp,run,mnt,opt,srv,home}
    mkdir -p "$NFS_ROOT"/var/{log,spool,cache,lib,tmp}
    mkdir -p "$NFS_ROOT"/usr/{bin,sbin,lib,share,include,local}
    mkdir -p "$NFS_ROOT"/lib/{firmware,modules}
    mkdir -p "$NFS_ROOT"/etc/{init.d,network,default,opt}
    mkdir -p "$NFS_ROOT"/root
    
    # Set permissions
    chmod 1777 "$NFS_ROOT/tmp"
    chmod 1777 "$NFS_ROOT/var/tmp"
    chmod 0700 "$NFS_ROOT/root"
    
    log_info "Directory structure created"
}

create_device_nodes() {
    log_step "Creating essential device nodes..."
    
    # Most will be created by devtmpfs, but these are needed early
    mknod -m 666 "$NFS_ROOT/dev/null" c 1 3 2>/dev/null || true
    mknod -m 666 "$NFS_ROOT/dev/zero" c 1 5 2>/dev/null || true
    mknod -m 666 "$NFS_ROOT/dev/random" c 1 8 2>/dev/null || true
    mknod -m 666 "$NFS_ROOT/dev/urandom" c 1 9 2>/dev/null || true
    mknod -m 600 "$NFS_ROOT/dev/console" c 5 1 2>/dev/null || true
    mknod -m 666 "$NFS_ROOT/dev/tty" c 5 0 2>/dev/null || true
    mknod -m 666 "$NFS_ROOT/dev/ptmx" c 5 2 2>/dev/null || true
    
    mkdir -p "$NFS_ROOT/dev/pts"
    mkdir -p "$NFS_ROOT/dev/shm"
    
    log_info "Device nodes created"
}

create_etc_files() {
    log_step "Creating /etc configuration files..."
    
    # /etc/fstab
    cat > "$NFS_ROOT/etc/fstab" << 'EOF'
# NFS root filesystem - mounted by kernel (no entry needed)
#
# Format: <device> <mount> <type> <options> <dump> <pass>
proc            /proc        proc    defaults          0 0
sysfs           /sys         sysfs   defaults          0 0
devtmpfs        /dev         devtmpfs defaults         0 0
devpts          /dev/pts     devpts  defaults          0 0
tmpfs           /dev/shm     tmpfs   defaults          0 0
tmpfs           /tmp         tmpfs   defaults,size=64M 0 0
tmpfs           /run         tmpfs   defaults,size=32M 0 0
tmpfs           /var/log     tmpfs   defaults,size=16M 0 0
EOF
    
    # /etc/hostname
    echo "$HOSTNAME" > "$NFS_ROOT/etc/hostname"
    
    # /etc/hosts
    cat > "$NFS_ROOT/etc/hosts" << EOF
127.0.0.1       localhost
127.0.1.1       $HOSTNAME
EOF
    
    # /etc/resolv.conf
    cat > "$NFS_ROOT/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    
    # /etc/passwd
    cat > "$NFS_ROOT/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF
    
    # /etc/group
    cat > "$NFS_ROOT/etc/group" << 'EOF'
root:x:0:
daemon:x:1:
tty:x:5:
disk:x:6:
dialout:x:20:
audio:x:29:
video:x:44:
plugdev:x:46:
staff:x:50:
users:x:100:
nogroup:x:65534:
EOF
    
    # /etc/shadow (root password)
    local hashed_pass=$(openssl passwd -6 "$ROOT_PASSWORD")
    cat > "$NFS_ROOT/etc/shadow" << EOF
root:$hashed_pass:19000:0:99999:7:::
daemon:*:19000:0:99999:7:::
nobody:*:19000:0:99999:7:::
EOF
    chmod 640 "$NFS_ROOT/etc/shadow"
    
    # /etc/profile
    cat > "$NFS_ROOT/etc/profile" << 'EOF'
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
export HOME=${HOME:-/root}
export TERM=${TERM:-linux}
export PS1='\u@\h:\w\$ '
export EDITOR=vi
export PAGER=less

# Set umask
umask 022

# Load local profile if exists
[ -f /etc/profile.local ] && . /etc/profile.local
EOF
    
    # /etc/inittab (for BusyBox init)
    cat > "$NFS_ROOT/etc/inittab" << 'EOF'
# Startup script
::sysinit:/etc/init.d/rcS

# Console on serial port
ttyO0::respawn:/sbin/getty -L ttyO0 115200 vt100

# Trap CTRL-ALT-DEL
::ctrlaltdel:/sbin/reboot

# Shutdown
::shutdown:/etc/init.d/rcK
EOF
    
    # /etc/shells
    cat > "$NFS_ROOT/etc/shells" << 'EOF'
/bin/sh
/bin/ash
/bin/bash
EOF
    
    # /etc/network/interfaces
    cat > "$NFS_ROOT/etc/network/interfaces" << 'EOF'
# Loopback
auto lo
iface lo inet loopback

# Ethernet - configured by kernel ip= bootarg
# Manual entry to prevent conflicts
auto eth0
iface eth0 inet manual
EOF
    
    log_info "Configuration files created"
}

create_init_scripts() {
    log_step "Creating init scripts..."
    
    # /etc/init.d/rcS - startup script
    cat > "$NFS_ROOT/etc/init.d/rcS" << 'EOF'
#!/bin/sh
#
# System startup script for NFS root

echo "Starting system..."

# Mount filesystems
mount -a

# Create mount points
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts 2>/dev/null
mount -t tmpfs tmpfs /dev/shm 2>/dev/null

# Set hostname
hostname -F /etc/hostname

# Set up loopback
ifconfig lo 127.0.0.1 netmask 255.0.0.0 up

# Set up ethernet (already configured by kernel, just verify)
if [ -d /sys/class/net/eth0 ]; then
    ip link set eth0 up
fi

# Load kernel modules
if [ -d /lib/modules/$(uname -r) ]; then
    for mod in /lib/modules/$(uname -r)/*.ko; do
        [ -f "$mod" ] && insmod "$mod" 2>/dev/null
    done
fi

# Start syslogd if available
[ -x /sbin/syslogd ] && syslogd -C

# Run custom startup scripts
for script in /etc/init.d/S*; do
    [ -x "$script" ] && "$script" start
done

echo "System ready."
EOF
    chmod +x "$NFS_ROOT/etc/init.d/rcS"
    
    # /etc/init.d/rcK - shutdown script
    cat > "$NFS_ROOT/etc/init.d/rcK" << 'EOF'
#!/bin/sh
#
# System shutdown script

echo "Shutting down..."

# Stop services
for script in $(ls -r /etc/init.d/S* 2>/dev/null); do
    [ -x "$script" ] && "$script" stop
done

# Kill all processes
killall5 -TERM
sleep 2
killall5 -KILL

# Sync and unmount
sync
umount -a -r

echo "System halted."
EOF
    chmod +x "$NFS_ROOT/etc/init.d/rcK"
    
    log_info "Init scripts created"
}

install_busybox() {
    log_step "Installing BusyBox..."
    
    local busybox_url="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
    local busybox_arm_url="https://busybox.net/downloads/binaries/1.35.0-arm-linux-musleabi/busybox"
    
    # Try to download ARM BusyBox
    if command -v wget &>/dev/null; then
        log_info "Downloading BusyBox for ARM..."
        wget -q -O "$NFS_ROOT/bin/busybox" "$busybox_arm_url" 2>/dev/null || {
            log_warn "Download failed, using host BusyBox if available"
            [ -x /bin/busybox ] && cp /bin/busybox "$NFS_ROOT/bin/"
        }
    elif command -v curl &>/dev/null; then
        curl -sL -o "$NFS_ROOT/bin/busybox" "$busybox_arm_url" 2>/dev/null || {
            log_warn "Download failed, using host BusyBox if available"
            [ -x /bin/busybox ] && cp /bin/busybox "$NFS_ROOT/bin/"
        }
    else
        log_warn "No wget or curl, trying to copy from host"
        [ -x /bin/busybox ] && cp /bin/busybox "$NFS_ROOT/bin/"
    fi
    
    if [ -f "$NFS_ROOT/bin/busybox" ]; then
        chmod +x "$NFS_ROOT/bin/busybox"
        
        # Create symlinks
        log_info "Creating BusyBox symlinks..."
        
        local commands="sh ash bash cat chmod chown chroot clear cp date dd df 
            dmesg du echo env expr false find free grep head hostname 
            id ifconfig init ip kill killall ln ls mkdir mknod mount 
            mv ping poweroff ps pwd reboot rm rmdir sed sh sleep 
            sync tail tar touch true umount uname vi wc which"
        
        for cmd in $commands; do
            ln -sf busybox "$NFS_ROOT/bin/$cmd" 2>/dev/null || true
        done
        
        # Sbin commands
        local sbin_cmds="halt init poweroff reboot getty syslogd klogd 
            ifconfig ip route insmod rmmod modprobe"
        
        for cmd in $sbin_cmds; do
            ln -sf ../bin/busybox "$NFS_ROOT/sbin/$cmd" 2>/dev/null || true
        done
        
        log_info "BusyBox installed with $(ls "$NFS_ROOT/bin" | wc -l) applets"
    else
        log_warn "BusyBox not installed - rootfs needs manual population"
    fi
}

create_symbolic_links() {
    log_step "Creating symbolic links..."
    
    # lib -> lib (some systems expect this)
    ln -sf lib "$NFS_ROOT/lib32" 2>/dev/null || true
    
    # /var/run -> /run
    rm -rf "$NFS_ROOT/var/run"
    ln -sf ../run "$NFS_ROOT/var/run"
    
    # /var/lock -> /run/lock
    mkdir -p "$NFS_ROOT/run/lock"
    rm -rf "$NFS_ROOT/var/lock"
    ln -sf ../run/lock "$NFS_ROOT/var/lock"
    
    log_info "Symbolic links created"
}

set_permissions() {
    log_step "Setting permissions..."
    
    chown -R root:root "$NFS_ROOT"
    chmod 755 "$NFS_ROOT"
    chmod 1777 "$NFS_ROOT/tmp"
    chmod 1777 "$NFS_ROOT/var/tmp"
    chmod 0700 "$NFS_ROOT/root"
    chmod 640 "$NFS_ROOT/etc/shadow"
    
    log_info "Permissions set"
}

print_summary() {
    local size=$(du -sh "$NFS_ROOT" | cut -f1)
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ROOTFS CREATED"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Location:     $NFS_ROOT"
    echo "Size:         $size"
    echo "Hostname:     $HOSTNAME"
    echo "Root Password: $ROOT_PASSWORD"
    echo ""
    echo "Contents:"
    ls -la "$NFS_ROOT"
    echo ""
    echo "To use:"
    echo "  1. Ensure NFS exports this directory"
    echo "  2. Boot BeagleBone with root=/dev/nfs"
    echo ""
}

# ==========================================================================
# MAIN
# ==========================================================================

show_usage() {
    cat << EOF
Create Root Filesystem for NFS Boot

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help
    -d, --dir DIR       Rootfs directory (default: /export/bbb-root)
    -n, --hostname NAME Hostname (default: beaglebone-nfs)
    -p, --password PASS Root password (default: root)
    -f, --from-tar FILE Extract from existing rootfs tarball
    -m, --minimal       Create minimal rootfs only (no BusyBox)

Examples:
    sudo $0                              # Create default rootfs
    sudo $0 --dir /export/bbb-dev        # Custom directory
    sudo $0 --from-tar rootfs.tar.gz     # Extract existing tarball
    sudo $0 --hostname myboard           # Custom hostname
EOF
}

MINIMAL=0
FROM_TAR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -d|--dir)
            NFS_ROOT="$2"
            shift 2
            ;;
        -n|--hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        -p|--password)
            ROOT_PASSWORD="$2"
            shift 2
            ;;
        -f|--from-tar)
            FROM_TAR="$2"
            shift 2
            ;;
        -m|--minimal)
            MINIMAL=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

echo ""
log_info "Creating rootfs for NFS boot..."
echo ""

check_root

# Extract from tarball if provided
if [ -n "$FROM_TAR" ]; then
    log_step "Extracting from $FROM_TAR..."
    mkdir -p "$NFS_ROOT"
    tar xf "$FROM_TAR" -C "$NFS_ROOT"
    log_info "Extracted rootfs from $FROM_TAR"
    print_summary
    exit 0
fi

create_directory_structure
create_device_nodes
create_etc_files
create_init_scripts
create_symbolic_links

if [ "$MINIMAL" -eq 0 ]; then
    install_busybox
fi

set_permissions
print_summary
