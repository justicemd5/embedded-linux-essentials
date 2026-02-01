#!/bin/bash
#
# apply_optimizations.sh - Apply boot time optimizations
#
# Applies U-Boot and kernel optimizations for faster boot on BBB
#
# Author: Embedded Linux Labs
# License: MIT

set -e

TARGET_HOST="${1:-debian@192.168.7.2}"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [TARGET_HOST] [OPTION]

Apply boot time optimizations to BeagleBone Black.

Arguments:
    TARGET_HOST   SSH target (default: debian@192.168.7.2)

Options:
    --uboot-only      Only apply U-Boot optimizations
    --kernel-only     Only apply kernel bootargs optimizations
    --userspace-only  Only apply userspace optimizations
    --analyze         Analyze current state without changes
    --restore         Restore default settings

Examples:
    $0                           # Apply all optimizations
    $0 debian@192.168.7.2       # Specify target
    $0 --analyze                # Show current state
    $0 --restore                # Restore defaults
EOF
}

check_connection() {
    log_info "Checking connection to $TARGET_HOST..."
    
    if ! ssh $SSH_OPTS "$TARGET_HOST" "echo ok" &>/dev/null; then
        log_error "Cannot connect to $TARGET_HOST"
        echo "Make sure:"
        echo "  1. BBB is powered and connected"
        echo "  2. Network is configured (USB or Ethernet)"
        echo "  3. SSH is running on target"
        exit 1
    fi
    
    log_info "Connection OK"
}

analyze_current_state() {
    log_info "Analyzing current boot configuration..."
    echo ""
    
    echo "═══════════════════════════════════════════════════════════════"
    echo "  CURRENT BOOT CONFIGURATION"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Check U-Boot env
    echo "U-Boot Environment:"
    ssh $SSH_OPTS "$TARGET_HOST" "sudo fw_printenv bootdelay 2>/dev/null || echo '  bootdelay: (not accessible)'"
    ssh $SSH_OPTS "$TARGET_HOST" "sudo fw_printenv silent 2>/dev/null || echo '  silent: (not set)'"
    echo ""
    
    # Check kernel cmdline
    echo "Kernel Command Line:"
    ssh $SSH_OPTS "$TARGET_HOST" "cat /proc/cmdline"
    echo ""
    
    # Check if quiet mode
    CMDLINE=$(ssh $SSH_OPTS "$TARGET_HOST" "cat /proc/cmdline")
    if echo "$CMDLINE" | grep -q "quiet"; then
        echo "  ✓ Quiet mode: enabled"
    else
        echo "  ✗ Quiet mode: disabled"
    fi
    
    if echo "$CMDLINE" | grep -q "loglevel="; then
        echo "  ✓ Loglevel: $(echo "$CMDLINE" | grep -oP 'loglevel=\K\d+')"
    else
        echo "  ✗ Loglevel: default (7)"
    fi
    echo ""
    
    # Check init system
    echo "Init System:"
    INIT_SYSTEM=$(ssh $SSH_OPTS "$TARGET_HOST" "ps -p 1 -o comm= 2>/dev/null || echo unknown")
    echo "  PID 1: $INIT_SYSTEM"
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        echo ""
        echo "  Systemd boot time:"
        ssh $SSH_OPTS "$TARGET_HOST" "systemd-analyze 2>/dev/null || echo '    (not available)'"
    fi
    echo ""
    
    # List enabled services
    echo "Enabled Services (may slow boot):"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        ssh $SSH_OPTS "$TARGET_HOST" "systemctl list-unit-files --state=enabled --type=service 2>/dev/null | head -20"
    fi
    echo ""
}

apply_uboot_optimizations() {
    log_info "Applying U-Boot optimizations..."
    
    # Check if fw_setenv is available
    if ! ssh $SSH_OPTS "$TARGET_HOST" "which fw_setenv" &>/dev/null; then
        log_warn "fw_setenv not found, installing u-boot-tools..."
        ssh $SSH_OPTS "$TARGET_HOST" "sudo apt-get update && sudo apt-get install -y u-boot-tools"
    fi
    
    # Set bootdelay to 0
    log_info "Setting bootdelay=0..."
    ssh $SSH_OPTS "$TARGET_HOST" "sudo fw_setenv bootdelay 0" || {
        log_warn "Could not set bootdelay via fw_setenv"
        echo "You may need to set this in U-Boot console:"
        echo "  setenv bootdelay 0"
        echo "  saveenv"
    }
    
    log_info "U-Boot optimizations applied (bootdelay=0)"
}

apply_kernel_optimizations() {
    log_info "Applying kernel bootargs optimizations..."
    
    # Modify /boot/uEnv.txt if it exists
    if ssh $SSH_OPTS "$TARGET_HOST" "test -f /boot/uEnv.txt"; then
        log_info "Found /boot/uEnv.txt, modifying..."
        
        # Backup
        ssh $SSH_OPTS "$TARGET_HOST" "sudo cp /boot/uEnv.txt /boot/uEnv.txt.bak"
        
        # Check if cmdline already has quiet
        if ! ssh $SSH_OPTS "$TARGET_HOST" "grep -q 'quiet' /boot/uEnv.txt"; then
            # Add quiet and loglevel to bootargs
            ssh $SSH_OPTS "$TARGET_HOST" "sudo sed -i 's/\(cmdline=.*\)/\1 quiet loglevel=0/' /boot/uEnv.txt"
            log_info "Added 'quiet loglevel=0' to bootargs"
        else
            log_info "Quiet mode already enabled"
        fi
    else
        log_warn "/boot/uEnv.txt not found"
        echo "Manually add 'quiet loglevel=0' to kernel bootargs in U-Boot:"
        echo "  setenv bootargs \${bootargs} quiet loglevel=0"
        echo "  saveenv"
    fi
}

apply_userspace_optimizations() {
    log_info "Applying userspace optimizations..."
    
    INIT_SYSTEM=$(ssh $SSH_OPTS "$TARGET_HOST" "ps -p 1 -o comm= 2>/dev/null")
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        log_info "Optimizing systemd..."
        
        # Services to disable (adjust as needed)
        DISABLE_SERVICES=(
            "bluetooth.service"
            "ModemManager.service"
            "cups.service"
            "avahi-daemon.service"
            "wpa_supplicant.service"
            "apt-daily.timer"
            "apt-daily-upgrade.timer"
            "man-db.timer"
        )
        
        for service in "${DISABLE_SERVICES[@]}"; do
            if ssh $SSH_OPTS "$TARGET_HOST" "systemctl is-enabled $service 2>/dev/null" | grep -q "enabled"; then
                log_info "Disabling $service..."
                ssh $SSH_OPTS "$TARGET_HOST" "sudo systemctl disable $service 2>/dev/null" || true
            fi
        done
        
        # Mask slow services
        log_info "Masking slow services..."
        ssh $SSH_OPTS "$TARGET_HOST" "sudo systemctl mask systemd-networkd-wait-online.service 2>/dev/null" || true
        
        # Show remaining services
        log_info "Current enabled services:"
        ssh $SSH_OPTS "$TARGET_HOST" "systemctl list-unit-files --state=enabled --type=service 2>/dev/null | grep -v '0 unit files listed'"
    else
        log_info "Non-systemd init, skipping service optimization"
    fi
}

restore_defaults() {
    log_info "Restoring default settings..."
    
    # Restore U-Boot
    ssh $SSH_OPTS "$TARGET_HOST" "sudo fw_setenv bootdelay 3" || true
    
    # Restore uEnv.txt backup
    if ssh $SSH_OPTS "$TARGET_HOST" "test -f /boot/uEnv.txt.bak"; then
        ssh $SSH_OPTS "$TARGET_HOST" "sudo mv /boot/uEnv.txt.bak /boot/uEnv.txt"
        log_info "Restored /boot/uEnv.txt from backup"
    fi
    
    log_info "Defaults restored"
}

# =============================================================================
# MAIN
# =============================================================================

case "${2:-}" in
    --analyze)
        check_connection
        analyze_current_state
        exit 0
        ;;
    --restore)
        check_connection
        restore_defaults
        exit 0
        ;;
    --uboot-only)
        check_connection
        apply_uboot_optimizations
        exit 0
        ;;
    --kernel-only)
        check_connection
        apply_kernel_optimizations
        exit 0
        ;;
    --userspace-only)
        check_connection
        apply_userspace_optimizations
        exit 0
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
esac

# Apply all optimizations
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  BOOT OPTIMIZATION SCRIPT"
echo "════════════════════════════════════════════════════════════"
echo ""

check_connection
echo ""

echo "Before optimization:"
analyze_current_state

log_info "Applying all optimizations..."
echo ""

apply_uboot_optimizations
apply_kernel_optimizations
apply_userspace_optimizations

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  OPTIMIZATION COMPLETE"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Reboot to apply changes:"
echo "  ssh $TARGET_HOST sudo reboot"
echo ""
echo "Then measure new boot time with:"
echo "  ./measure_baseline.sh /dev/ttyACM0"
echo ""
