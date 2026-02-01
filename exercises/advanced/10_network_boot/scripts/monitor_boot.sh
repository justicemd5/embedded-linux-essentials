#!/bin/bash
#
# monitor_boot.sh - Monitor and debug network boot process
#
# Real-time monitoring of DHCP, TFTP, and NFS traffic
#
# Usage:
#   sudo ./monitor_boot.sh [interface]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

INTERFACE="${1:-eth1}"
LOG_DIR="${LOG_DIR:-/var/log/netboot}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==========================================================================
# FUNCTIONS
# ==========================================================================

show_usage() {
    cat << EOF
Network Boot Monitor

Usage: $0 [OPTIONS] [INTERFACE]

Monitors DHCP, TFTP, and NFS traffic during network boot.

Options:
    -h, --help          Show this help
    -d, --dhcp          Monitor DHCP only
    -t, --tftp          Monitor TFTP only
    -n, --nfs           Monitor NFS only
    -a, --all           Monitor all (default)
    -l, --log           Save logs to $LOG_DIR

Examples:
    sudo $0 eth1        # Monitor all on eth1
    sudo $0 -d eth1     # DHCP only
    sudo $0 -l          # Monitor and log
EOF
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

check_interface() {
    if ! ip link show "$INTERFACE" &>/dev/null; then
        echo -e "${RED}Interface $INTERFACE not found${NC}"
        echo "Available interfaces:"
        ip link show | grep -E "^[0-9]" | awk '{print "  " $2}' | tr -d ':'
        exit 1
    fi
}

monitor_dhcp() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  DHCP Traffic Monitor (Ctrl+C to stop)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Listening on $INTERFACE for DHCP packets..."
    echo ""
    
    tcpdump -i "$INTERFACE" -vvv 'port 67 or port 68' 2>/dev/null | while read -r line; do
        case "$line" in
            *DHCPDISCOVER*)
                echo -e "${YELLOW}[DISCOVER]${NC} $line"
                ;;
            *DHCPOFFER*)
                echo -e "${GREEN}[OFFER]${NC} $line"
                ;;
            *DHCPREQUEST*)
                echo -e "${BLUE}[REQUEST]${NC} $line"
                ;;
            *DHCPACK*)
                echo -e "${GREEN}[ACK]${NC} $line"
                ;;
            *DHCPNAK*)
                echo -e "${RED}[NAK]${NC} $line"
                ;;
            *)
                echo "$line"
                ;;
        esac
    done
}

monitor_tftp() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  TFTP Traffic Monitor (Ctrl+C to stop)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Listening on $INTERFACE for TFTP packets..."
    echo ""
    
    tcpdump -i "$INTERFACE" -vv 'port 69 or (udp and portrange 1024-65535)' 2>/dev/null | while read -r line; do
        case "$line" in
            *RRQ*)
                echo -e "${GREEN}[READ REQUEST]${NC} $line"
                ;;
            *WRQ*)
                echo -e "${YELLOW}[WRITE REQUEST]${NC} $line"
                ;;
            *DATA*)
                echo -e "${BLUE}[DATA]${NC} $line"
                ;;
            *ACK*)
                echo -e "${NC}[ACK] $line"
                ;;
            *ERROR*)
                echo -e "${RED}[ERROR]${NC} $line"
                ;;
            *)
                echo "$line"
                ;;
        esac
    done
}

monitor_nfs() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  NFS Traffic Monitor (Ctrl+C to stop)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Listening on $INTERFACE for NFS packets..."
    echo ""
    
    tcpdump -i "$INTERFACE" -vv 'port 2049 or port 111' 2>/dev/null | while read -r line; do
        case "$line" in
            *MOUNT*)
                echo -e "${GREEN}[MOUNT]${NC} $line"
                ;;
            *LOOKUP*)
                echo -e "${BLUE}[LOOKUP]${NC} $line"
                ;;
            *READ*)
                echo -e "${NC}[READ] $line"
                ;;
            *WRITE*)
                echo -e "${YELLOW}[WRITE]${NC} $line"
                ;;
            *GETATTR*)
                echo -e "${NC}[GETATTR] $line"
                ;;
            *)
                echo "$line"
                ;;
        esac
    done
}

monitor_all() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Network Boot Traffic Monitor (Ctrl+C to stop)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Listening on $INTERFACE for DHCP, TFTP, and NFS packets..."
    echo ""
    
    tcpdump -i "$INTERFACE" -l -vv \
        'port 67 or port 68 or port 69 or port 2049 or port 111' 2>/dev/null | \
    while read -r line; do
        # Color code based on protocol
        case "$line" in
            *bootp*|*DHCP*)
                echo -e "${YELLOW}[DHCP]${NC} $line"
                ;;
            *tftp*|*RRQ*|*WRQ*)
                echo -e "${GREEN}[TFTP]${NC} $line"
                ;;
            *nfs*|*NFS*|*MOUNT*)
                echo -e "${BLUE}[NFS]${NC} $line"
                ;;
            *)
                echo "$line"
                ;;
        esac
    done
}

show_status() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Network Boot Server Status${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Interface
    echo -e "${BLUE}Interface:${NC} $INTERFACE"
    ip addr show "$INTERFACE" | grep inet
    echo ""
    
    # DHCP/dnsmasq
    echo -e "${BLUE}DHCP Server (dnsmasq):${NC}"
    if systemctl is-active --quiet dnsmasq; then
        echo -e "  Status: ${GREEN}Running${NC}"
        echo "  Leases:"
        if [ -f /var/lib/misc/dnsmasq.leases ]; then
            cat /var/lib/misc/dnsmasq.leases | while read -r line; do
                echo "    $line"
            done
        fi
    else
        echo -e "  Status: ${RED}Not Running${NC}"
    fi
    echo ""
    
    # TFTP
    echo -e "${BLUE}TFTP Server:${NC}"
    if systemctl is-active --quiet tftpd-hpa 2>/dev/null || \
       pgrep -x tftpd &>/dev/null || \
       ss -uln | grep -q ":69 "; then
        echo -e "  Status: ${GREEN}Running${NC}"
        echo "  Directory: /tftpboot"
        echo "  Files:"
        ls -lh /tftpboot/*.{Image,dtb} 2>/dev/null | while read -r line; do
            echo "    $line"
        done
    else
        echo -e "  Status: ${YELLOW}Via dnsmasq${NC}"
    fi
    echo ""
    
    # NFS
    echo -e "${BLUE}NFS Server:${NC}"
    if systemctl is-active --quiet nfs-kernel-server 2>/dev/null || \
       systemctl is-active --quiet nfs-server 2>/dev/null; then
        echo -e "  Status: ${GREEN}Running${NC}"
        echo "  Exports:"
        showmount -e localhost 2>/dev/null | grep -v "Export list" | while read -r line; do
            echo "    $line"
        done
    else
        echo -e "  Status: ${RED}Not Running${NC}"
    fi
    echo ""
    
    # Listening ports
    echo -e "${BLUE}Listening Ports:${NC}"
    ss -ulnp 2>/dev/null | grep -E ":(67|68|69) " | while read -r line; do
        echo "  $line"
    done
    ss -tlnp 2>/dev/null | grep -E ":(2049|111) " | while read -r line; do
        echo "  $line"
    done
}

# ==========================================================================
# MAIN
# ==========================================================================

MODE="all"
SAVE_LOG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -d|--dhcp)
            MODE="dhcp"
            shift
            ;;
        -t|--tftp)
            MODE="tftp"
            shift
            ;;
        -n|--nfs)
            MODE="nfs"
            shift
            ;;
        -a|--all)
            MODE="all"
            shift
            ;;
        -s|--status)
            MODE="status"
            shift
            ;;
        -l|--log)
            SAVE_LOG=1
            mkdir -p "$LOG_DIR"
            shift
            ;;
        *)
            INTERFACE="$1"
            shift
            ;;
    esac
done

check_root

if [ "$MODE" != "status" ]; then
    check_interface
fi

# Set up logging
if [ "$SAVE_LOG" -eq 1 ]; then
    LOG_FILE="$LOG_DIR/netboot_$(date +%Y%m%d_%H%M%S).log"
    echo "Logging to: $LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

case "$MODE" in
    dhcp)
        monitor_dhcp
        ;;
    tftp)
        monitor_tftp
        ;;
    nfs)
        monitor_nfs
        ;;
    status)
        show_status
        ;;
    all)
        monitor_all
        ;;
esac
