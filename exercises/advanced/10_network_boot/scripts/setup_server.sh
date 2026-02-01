#!/bin/bash
#
# setup_server.sh - Complete network boot server setup
#
# Sets up TFTP, NFS, and DHCP servers for BeagleBone Black network boot
#
# Usage:
#   sudo ./setup_server.sh [interface]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

# ==========================================================================
# CONFIGURATION
# ==========================================================================

# Network interface connected to BBB (override with $1)
INTERFACE="${1:-eth1}"

# Network configuration
NETWORK="192.168.10.0"
NETMASK="255.255.255.0"
SERVER_IP="192.168.10.1"
DHCP_RANGE_START="192.168.10.100"
DHCP_RANGE_END="192.168.10.200"

# Directories
TFTP_ROOT="/tftpboot"
NFS_ROOT="/export/bbb-root"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==========================================================================
# UTILITY FUNCTIONS
# ==========================================================================

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}==>${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$ID"
        VERSION="$VERSION_ID"
    else
        DISTRO="unknown"
    fi
    log_info "Detected: $DISTRO $VERSION"
}

# ==========================================================================
# PACKAGE INSTALLATION
# ==========================================================================

install_packages_debian() {
    log_step "Installing packages (Debian/Ubuntu)..."
    
    apt-get update
    apt-get install -y \
        tftpd-hpa \
        nfs-kernel-server \
        dnsmasq \
        nfs-common \
        tcpdump \
        net-tools
    
    log_info "Packages installed"
}

install_packages_fedora() {
    log_step "Installing packages (Fedora/RHEL)..."
    
    dnf install -y \
        tftp-server \
        nfs-utils \
        dnsmasq \
        tcpdump \
        net-tools
    
    log_info "Packages installed"
}

install_packages_arch() {
    log_step "Installing packages (Arch)..."
    
    pacman -S --noconfirm \
        tftp-hpa \
        nfs-utils \
        dnsmasq \
        tcpdump \
        net-tools
    
    log_info "Packages installed"
}

install_packages() {
    case "$DISTRO" in
        ubuntu|debian)
            install_packages_debian
            ;;
        fedora|rhel|centos)
            install_packages_fedora
            ;;
        arch)
            install_packages_arch
            ;;
        *)
            log_warn "Unknown distro, attempting Debian-style install"
            install_packages_debian
            ;;
    esac
}

# ==========================================================================
# NETWORK CONFIGURATION
# ==========================================================================

configure_network_interface() {
    log_step "Configuring network interface $INTERFACE..."
    
    # Check if interface exists
    if ! ip link show "$INTERFACE" &>/dev/null; then
        log_error "Interface $INTERFACE not found"
        log_info "Available interfaces:"
        ip link show | grep -E "^[0-9]" | awk '{print $2}' | tr -d ':'
        exit 1
    fi
    
    # Configure with ip command (temporary)
    ip addr flush dev "$INTERFACE"
    ip addr add "$SERVER_IP/24" dev "$INTERFACE"
    ip link set "$INTERFACE" up
    
    log_info "Interface configured: $INTERFACE = $SERVER_IP"
    
    # Create persistent configuration
    if [ -d /etc/netplan ]; then
        # Ubuntu 18.04+
        cat > /etc/netplan/99-bbb-network.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      addresses:
        - $SERVER_IP/24
      dhcp4: no
EOF
        netplan apply 2>/dev/null || true
        log_info "Netplan configuration created"
        
    elif [ -d /etc/sysconfig/network-scripts ]; then
        # RHEL/Fedora
        cat > /etc/sysconfig/network-scripts/ifcfg-$INTERFACE << EOF
TYPE=Ethernet
BOOTPROTO=static
NAME=$INTERFACE
DEVICE=$INTERFACE
ONBOOT=yes
IPADDR=$SERVER_IP
NETMASK=$NETMASK
EOF
        log_info "Network scripts configuration created"
        
    elif [ -f /etc/network/interfaces ]; then
        # Debian/older Ubuntu
        cat >> /etc/network/interfaces << EOF

# BeagleBone Black network
auto $INTERFACE
iface $INTERFACE inet static
    address $SERVER_IP
    netmask $NETMASK
EOF
        log_info "interfaces configuration created"
    fi
}

# ==========================================================================
# DNSMASQ (DHCP + TFTP)
# ==========================================================================

configure_dnsmasq() {
    log_step "Configuring dnsmasq (DHCP + TFTP)..."
    
    # Disable systemd-resolved if it's using port 53
    if systemctl is-active --quiet systemd-resolved; then
        log_warn "Disabling systemd-resolved to free port 53"
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved 2>/dev/null || true
        rm -f /etc/resolv.conf
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
    fi
    
    # Backup existing config
    [ -f /etc/dnsmasq.conf ] && cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
    
    # Create configuration
    cat > /etc/dnsmasq.d/bbb-netboot.conf << EOF
# BeagleBone Black Network Boot Configuration
# Generated by setup_server.sh

# Listen only on specific interface
interface=$INTERFACE
bind-interfaces
except-interface=lo

# Don't use /etc/resolv.conf
no-resolv

# DHCP Configuration
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,12h
dhcp-option=1,$NETMASK
dhcp-option=3,$SERVER_IP
dhcp-option=6,8.8.8.8,8.8.4.4

# TFTP Configuration
enable-tftp
tftp-root=$TFTP_ROOT
tftp-secure

# PXE/Network boot options
# Option 66: TFTP Server
dhcp-option=66,$SERVER_IP
# Option 67: Boot filename
dhcp-option=67,zImage

# Static IP for known BeagleBones (add MAC addresses here)
# dhcp-host=d0:39:72:xx:xx:xx,bbb-01,192.168.10.50
# dhcp-host=d0:39:72:yy:yy:yy,bbb-02,192.168.10.51

# Logging
log-dhcp
log-queries
log-facility=/var/log/dnsmasq.log
EOF

    # Create log file
    touch /var/log/dnsmasq.log
    chown dnsmasq:dnsmasq /var/log/dnsmasq.log 2>/dev/null || true
    
    log_info "dnsmasq configured"
}

# ==========================================================================
# TFTP SERVER
# ==========================================================================

configure_tftp() {
    log_step "Configuring TFTP server..."
    
    # Create TFTP directory structure
    mkdir -p "$TFTP_ROOT"
    mkdir -p "$TFTP_ROOT/dtbs"
    mkdir -p "$TFTP_ROOT/boards"
    
    # Set permissions
    chmod 755 "$TFTP_ROOT"
    chown -R tftp:tftp "$TFTP_ROOT" 2>/dev/null || chown -R nobody:nogroup "$TFTP_ROOT"
    
    # Configure tftpd-hpa (Debian/Ubuntu)
    if [ -f /etc/default/tftpd-hpa ]; then
        cat > /etc/default/tftpd-hpa << EOF
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="$TFTP_ROOT"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure --create --verbose"
EOF
    fi
    
    # Create placeholder files
    cat > "$TFTP_ROOT/README.txt" << EOF
TFTP Boot Directory
===================

Place your boot files here:

- zImage              : Linux kernel
- am335x-boneblack.dtb: Device tree blob
- initramfs.cpio.gz   : Initial ramdisk (optional)

For multiple boards, create subdirectories:
  boards/bbb-01/zImage
  boards/bbb-01/am335x-boneblack.dtb
EOF

    log_info "TFTP directory: $TFTP_ROOT"
}

# ==========================================================================
# NFS SERVER
# ==========================================================================

configure_nfs() {
    log_step "Configuring NFS server..."
    
    # Create NFS export directory
    mkdir -p "$NFS_ROOT"
    
    # Create basic rootfs structure if empty
    if [ ! -d "$NFS_ROOT/sbin" ]; then
        log_info "Creating minimal rootfs structure..."
        mkdir -p "$NFS_ROOT"/{bin,sbin,etc,proc,sys,dev,tmp,run,var/log,lib,usr/{bin,sbin,lib},home,root}
        chmod 1777 "$NFS_ROOT/tmp"
        chmod 0700 "$NFS_ROOT/root"
        
        # Create minimal fstab
        cat > "$NFS_ROOT/etc/fstab" << EOF
# NFS root filesystem - mounted by kernel
proc            /proc        proc    defaults          0 0
sysfs           /sys         sysfs   defaults          0 0
devtmpfs        /dev         devtmpfs defaults         0 0
tmpfs           /tmp         tmpfs   defaults,size=64M 0 0
tmpfs           /run         tmpfs   defaults,size=32M 0 0
tmpfs           /var/log     tmpfs   defaults,size=16M 0 0
EOF
        
        # Create hostname
        echo "beaglebone-nfs" > "$NFS_ROOT/etc/hostname"
        
        # Create network interfaces
        mkdir -p "$NFS_ROOT/etc/network"
        cat > "$NFS_ROOT/etc/network/interfaces" << EOF
auto lo
iface lo inet loopback

# Note: eth0 is configured by kernel via ip=dhcp bootarg
auto eth0
iface eth0 inet manual
EOF
    fi
    
    # Backup exports
    [ -f /etc/exports ] && cp /etc/exports /etc/exports.backup
    
    # Remove old entry if exists
    sed -i "\|$NFS_ROOT|d" /etc/exports 2>/dev/null || true
    
    # Add export entry
    echo "$NFS_ROOT $NETWORK/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    
    # Export filesystem
    exportfs -ra
    
    log_info "NFS export: $NFS_ROOT"
    log_info "NFS access: $NETWORK/24"
}

# ==========================================================================
# FIREWALL
# ==========================================================================

configure_firewall() {
    log_step "Configuring firewall..."
    
    # UFW (Ubuntu)
    if command -v ufw &>/dev/null; then
        log_info "Configuring UFW..."
        ufw allow from $NETWORK/24 to any port 69 proto udp comment "TFTP"
        ufw allow from $NETWORK/24 to any port 67:68 proto udp comment "DHCP"
        ufw allow from $NETWORK/24 to any port 2049 proto tcp comment "NFS"
        ufw allow from $NETWORK/24 to any port 111 proto tcp comment "RPC"
        ufw allow from $NETWORK/24 to any port 111 proto udp comment "RPC"
        ufw reload 2>/dev/null || true
    fi
    
    # firewalld (Fedora/RHEL)
    if command -v firewall-cmd &>/dev/null; then
        log_info "Configuring firewalld..."
        firewall-cmd --zone=trusted --add-source=$NETWORK/24 --permanent
        firewall-cmd --zone=trusted --add-service=tftp --permanent
        firewall-cmd --zone=trusted --add-service=dhcp --permanent
        firewall-cmd --zone=trusted --add-service=nfs --permanent
        firewall-cmd --zone=trusted --add-service=rpc-bind --permanent
        firewall-cmd --reload
    fi
    
    # iptables fallback
    if command -v iptables &>/dev/null && [ ! -x /usr/sbin/ufw ]; then
        log_info "Configuring iptables..."
        iptables -A INPUT -s $NETWORK/24 -p udp --dport 69 -j ACCEPT
        iptables -A INPUT -s $NETWORK/24 -p udp --dport 67:68 -j ACCEPT
        iptables -A INPUT -s $NETWORK/24 -p tcp --dport 2049 -j ACCEPT
        iptables -A INPUT -s $NETWORK/24 -p tcp --dport 111 -j ACCEPT
        iptables-save > /etc/iptables.rules 2>/dev/null || true
    fi
}

# ==========================================================================
# SERVICES
# ==========================================================================

start_services() {
    log_step "Starting services..."
    
    # Stop conflicting services
    systemctl stop isc-dhcp-server 2>/dev/null || true
    
    # Enable and start services
    systemctl enable dnsmasq
    systemctl restart dnsmasq
    log_info "dnsmasq started"
    
    if [ -f /etc/default/tftpd-hpa ]; then
        systemctl enable tftpd-hpa
        systemctl restart tftpd-hpa
        log_info "tftpd-hpa started"
    fi
    
    systemctl enable nfs-kernel-server 2>/dev/null || systemctl enable nfs-server 2>/dev/null
    systemctl restart nfs-kernel-server 2>/dev/null || systemctl restart nfs-server 2>/dev/null
    log_info "NFS server started"
    
    # Enable rpcbind
    systemctl enable rpcbind 2>/dev/null || true
    systemctl restart rpcbind 2>/dev/null || true
}

# ==========================================================================
# VERIFICATION
# ==========================================================================

verify_setup() {
    log_step "Verifying setup..."
    
    local errors=0
    
    # Check interface
    if ip addr show "$INTERFACE" | grep -q "$SERVER_IP"; then
        log_info "✓ Interface $INTERFACE has IP $SERVER_IP"
    else
        log_error "✗ Interface $INTERFACE configuration failed"
        ((errors++))
    fi
    
    # Check dnsmasq
    if systemctl is-active --quiet dnsmasq; then
        log_info "✓ dnsmasq is running"
    else
        log_error "✗ dnsmasq is not running"
        ((errors++))
    fi
    
    # Check TFTP
    if [ -d "$TFTP_ROOT" ]; then
        log_info "✓ TFTP directory exists: $TFTP_ROOT"
    else
        log_error "✗ TFTP directory missing"
        ((errors++))
    fi
    
    # Check NFS exports
    if showmount -e localhost 2>/dev/null | grep -q "$NFS_ROOT"; then
        log_info "✓ NFS export configured: $NFS_ROOT"
    else
        log_error "✗ NFS export not visible"
        ((errors++))
    fi
    
    # Check ports
    if ss -uln | grep -q ":69 "; then
        log_info "✓ TFTP port 69 listening"
    else
        log_warn "⚠ TFTP port 69 not listening (may use dnsmasq)"
    fi
    
    if ss -uln | grep -q ":67 "; then
        log_info "✓ DHCP port 67 listening"
    else
        log_error "✗ DHCP port 67 not listening"
        ((errors++))
    fi
    
    if ss -tln | grep -q ":2049 "; then
        log_info "✓ NFS port 2049 listening"
    else
        log_error "✗ NFS port 2049 not listening"
        ((errors++))
    fi
    
    return $errors
}

# ==========================================================================
# SUMMARY
# ==========================================================================

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  NETWORK BOOT SERVER SETUP COMPLETE"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Configuration Summary:"
    echo "  Server Interface: $INTERFACE"
    echo "  Server IP:        $SERVER_IP"
    echo "  DHCP Range:       $DHCP_RANGE_START - $DHCP_RANGE_END"
    echo "  TFTP Directory:   $TFTP_ROOT"
    echo "  NFS Export:       $NFS_ROOT"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "  1. Copy kernel and device tree to TFTP directory:"
    echo "     sudo cp zImage $TFTP_ROOT/"
    echo "     sudo cp am335x-boneblack.dtb $TFTP_ROOT/"
    echo ""
    echo "  2. Extract or populate rootfs in NFS directory:"
    echo "     sudo tar xf rootfs.tar -C $NFS_ROOT/"
    echo ""
    echo "  3. Configure U-Boot on BeagleBone:"
    echo "     setenv serverip $SERVER_IP"
    echo "     setenv netboot 'dhcp; tftp \${loadaddr} zImage; tftp \${fdtaddr} am335x-boneblack.dtb; setenv bootargs console=ttyO0,115200n8 root=/dev/nfs rw nfsroot=$SERVER_IP:$NFS_ROOT,v3,tcp ip=dhcp; bootz \${loadaddr} - \${fdtaddr}'"
    echo "     setenv bootcmd 'run netboot'"
    echo "     saveenv"
    echo ""
    echo "  4. Reset BeagleBone to boot over network"
    echo ""
    echo "Useful Commands:"
    echo "  View DHCP leases:   cat /var/lib/misc/dnsmasq.leases"
    echo "  View dnsmasq log:   tail -f /var/log/dnsmasq.log"
    echo "  Check NFS exports:  showmount -e localhost"
    echo "  Test TFTP:          tftp $SERVER_IP -c get README.txt"
    echo ""
}

# ==========================================================================
# MAIN
# ==========================================================================

show_usage() {
    cat << EOF
Network Boot Server Setup for BeagleBone Black

Usage: $0 [OPTIONS] [INTERFACE]

Options:
    -h, --help      Show this help
    -c, --check     Check status only
    -u, --uninstall Remove configuration

Arguments:
    INTERFACE       Network interface connected to BBB (default: eth1)

Examples:
    sudo $0 eth1        # Set up with eth1
    sudo $0 enp2s0      # Set up with enp2s0
    sudo $0 --check     # Check current status
EOF
}

case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    -c|--check)
        verify_setup
        exit $?
        ;;
    -u|--uninstall)
        log_step "Removing network boot configuration..."
        rm -f /etc/dnsmasq.d/bbb-netboot.conf
        rm -f /etc/netplan/99-bbb-network.yaml
        sed -i "\|$NFS_ROOT|d" /etc/exports 2>/dev/null || true
        exportfs -ra
        systemctl restart dnsmasq
        log_info "Configuration removed"
        exit 0
        ;;
esac

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "  BeagleBone Black Network Boot Server Setup"
echo "════════════════════════════════════════════════════════════════════"
echo ""

check_root
detect_distro
install_packages
configure_network_interface
configure_dnsmasq
configure_tftp
configure_nfs
configure_firewall
start_services

if verify_setup; then
    print_summary
else
    log_error "Setup completed with errors. Check the output above."
    exit 1
fi
