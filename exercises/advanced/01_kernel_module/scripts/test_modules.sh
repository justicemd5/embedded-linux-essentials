#!/bin/bash
#
# test_modules.sh - Test kernel modules on BeagleBone Black
#
# This script connects to BBB and runs tests for each module
#
# Usage:
#   ./test_modules.sh [TARGET_IP]

set -e

TARGET_IP="${1:-192.168.7.2}"
TARGET_USER="debian"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "BeagleBone Black Module Testing"
echo "=========================================="
echo "Target: ${TARGET_USER}@${TARGET_IP}"
echo ""

# SSH command wrapper
ssh_cmd() {
    ssh -o ConnectTimeout=5 ${TARGET_USER}@${TARGET_IP} "$@"
}

# Check connectivity
if ! ssh_cmd "echo 'Connected'" 2>/dev/null; then
    echo -e "${RED}Cannot connect to BBB${NC}"
    exit 1
fi

# Test function
test_module() {
    local module_name=$1
    local module_path="/tmp/${module_name}.ko"
    
    echo ""
    echo -e "${YELLOW}Testing: ${module_name}${NC}"
    echo "----------------------------------------"
    
    # Check if module exists
    if ! ssh_cmd "test -f ${module_path}"; then
        echo -e "${RED}Module not found: ${module_path}${NC}"
        return 1
    fi
    
    # Unload if already loaded
    ssh_cmd "sudo rmmod ${module_name} 2>/dev/null || true"
    
    # Load module
    echo "Loading module..."
    if ssh_cmd "sudo insmod ${module_path}"; then
        echo -e "${GREEN}✓ Module loaded${NC}"
    else
        echo -e "${RED}✗ Failed to load module${NC}"
        return 1
    fi
    
    # Show dmesg output
    echo ""
    echo "Kernel messages:"
    ssh_cmd "dmesg | grep -i ${module_name} | tail -10" || true
    
    # Module-specific tests
    case ${module_name} in
        hwinfo)
            echo ""
            echo "Testing /proc/hwinfo:"
            ssh_cmd "cat /proc/hwinfo" || true
            ;;
        sysfs_demo)
            echo ""
            echo "Testing sysfs interface:"
            ssh_cmd "ls -la /sys/kernel/bbb_demo/" || true
            ssh_cmd "cat /sys/kernel/bbb_demo/ram_mb" || true
            ssh_cmd "echo 75 | sudo tee /sys/kernel/bbb_demo/brightness" || true
            ssh_cmd "cat /sys/kernel/bbb_demo/brightness" || true
            ;;
        chardev)
            echo ""
            echo "Testing character device:"
            ssh_cmd "ls -la /dev/bbbchar" || true
            ssh_cmd "echo 'Hello BBB' | sudo tee /dev/bbbchar" || true
            ssh_cmd "sudo cat /dev/bbbchar" || true
            ;;
        gpio_irq)
            echo ""
            echo "GPIO IRQ module loaded."
            echo "Testing sysfs interface:"
            ssh_cmd "cat /sys/class/gpio_irq/gpio_irq/gpio_value" || true
            ssh_cmd "cat /sys/class/gpio_irq/gpio_irq/irq_count" || true
            echo "Press button on GPIO to test interrupts"
            ;;
    esac
    
    # Show module info
    echo ""
    echo "Module info:"
    ssh_cmd "modinfo ${module_path}" | head -10
    
    # Unload module
    echo ""
    echo "Unloading module..."
    if ssh_cmd "sudo rmmod ${module_name}"; then
        echo -e "${GREEN}✓ Module unloaded${NC}"
    else
        echo -e "${RED}✗ Failed to unload module${NC}"
        return 1
    fi
    
    return 0
}

# Find and test all modules
MODULES=("hwinfo" "sysfs_demo" "chardev" "gpio_irq")
PASSED=0
FAILED=0

for module in "${MODULES[@]}"; do
    if test_module "${module}"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
done

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: ${PASSED}${NC}"
echo -e "${RED}Failed: ${FAILED}${NC}"

exit ${FAILED}
