#!/bin/bash
#
# hab_info.sh - HAB (High Assurance Boot) Information
#
# Provides information about AM335x secure boot capabilities
# WARNING: HAB programming is IRREVERSIBLE
#
# Usage:
#   ./hab_info.sh
#
# Author: Embedded Linux Labs
# License: MIT

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║             ⚠️  HAB (HIGH ASSURANCE BOOT) INFORMATION  ⚠️                     ║
║                                                                               ║
║                          READ CAREFULLY BEFORE USE                            ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF

echo ""
echo -e "${RED}════════════════════════════════════════════════════════════════════════"
echo "                     ⚠️  CRITICAL WARNING  ⚠️"
echo "════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "HAB/Secure Boot uses eFuses which are ONE-TIME PROGRAMMABLE (OTP)."
echo "Once programmed, eFuses CANNOT be changed or reset!"
echo ""
echo "This means:"
echo "  • If you program wrong keys, the device is PERMANENTLY BRICKED"
echo "  • If you lose the private key, NO new software can be loaded"
echo "  • There is NO recovery mechanism once eFuses are blown"
echo "  • Development devices should NEVER have eFuses programmed"
echo ""

echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════"
echo "                        AM335x Secure Boot Architecture"
echo "════════════════════════════════════════════════════════════════════════${NC}"
echo ""

cat << 'EOF'
                        ┌──────────────────────────────────────────┐
                        │              AM335x SoC                  │
                        │                                          │
    ┌───────────────────┼──────────────────────────────────────────┼────────────┐
    │                   │                                          │            │
    │   ┌───────────┐   │   ┌────────────────────────────────┐    │            │
    │   │           │   │   │                                │    │            │
    │   │  eFuses   │◄──┼───│   ROM Bootloader (SROM)        │    │            │
    │   │           │   │   │   - Reads security fuses       │    │            │
    │   │  • JTAG   │   │   │   - Verifies MLO signature     │    │            │
    │   │  • Keys   │   │   │   - Enforces secure boot       │    │            │
    │   │  • Mode   │   │   │                                │    │            │
    │   │           │   │   └────────────────────────────────┘    │            │
    │   └───────────┘   │                   │                      │            │
    │                   │                   ▼                      │            │
    │                   │   ┌────────────────────────────────┐    │            │
    │                   │   │                                │    │            │
    │                   │   │   MLO/SPL (Signed)             │    │            │
    │                   │   │   - Signed with private key    │    │            │
    │                   │   │   - Verified by ROM            │    │            │
    │                   │   │   - Loads U-Boot               │    │            │
    │                   │   │                                │    │            │
    │                   │   └────────────────────────────────┘    │            │
    │                   │                   │                      │            │
    │                   │                   ▼                      │            │
    │                   │   ┌────────────────────────────────┐    │            │
    │                   │   │                                │    │            │
    │                   │   │   U-Boot (Signed)              │    │            │
    │                   │   │   - Contains public key        │    │            │
    │                   │   │   - Verifies FIT image         │    │            │
    │                   │   │   - Chain of trust continues   │    │            │
    │                   │   │                                │    │            │
    │                   │   └────────────────────────────────┘    │            │
    │                   │                                          │            │
    └───────────────────┼──────────────────────────────────────────┼────────────┘
                        │                                          │
                        └──────────────────────────────────────────┘

EOF

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════"
echo "                         Security Levels"
echo "════════════════════════════════════════════════════════════════════════${NC}"
echo ""

cat << 'EOF'
┌─────────────────────────────────────────────────────────────────────────────┐
│ Level 0: No Security (Default)                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│ • Any software can boot                                                     │
│ • JTAG fully accessible                                                     │
│ • eFuses not programmed                                                     │
│ • RECOMMENDED for development                                               │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ Level 1: U-Boot Verified Boot (Software Only)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│ • FIT images signed and verified                                            │
│ • Public key embedded in U-Boot                                             │
│ • eFuses NOT programmed                                                     │
│ • JTAG still accessible                                                     │
│ • RECOMMENDED for most production use                                       │
│                                                                             │
│ This is what this exercise implements!                                      │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ Level 2: Full Hardware Secure Boot (HAB)                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│ • ROM verifies MLO/SPL                                                      │
│ • eFuses programmed with key hash                                           │
│ • JTAG can be disabled                                                      │
│ • IRREVERSIBLE - device locked forever                                      │
│ • Requires signing tools from TI                                            │
│ • ONLY for final production with extreme care                               │
└─────────────────────────────────────────────────────────────────────────────┘
EOF

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════"
echo "                     Recommended Approach"
echo "════════════════════════════════════════════════════════════════════════${NC}"
echo ""

cat << 'EOF'
For BeagleBone Black learning and development:

1. USE Level 1 (U-Boot Verified Boot)
   ✓ Provides meaningful security
   ✓ Completely reversible
   ✓ No risk of bricking device
   ✓ Good for learning secure boot concepts

2. AVOID Level 2 (HAB) unless:
   ✗ You are building production hardware
   ✗ You have proper key management infrastructure
   ✗ You have tested extensively on identical hardware
   ✗ You understand and accept the permanent nature

Key Management Best Practices for Level 1:
   • Generate unique keys per project
   • Store private keys in secure location
   • Never commit private keys to git
   • Use hardware security modules (HSM) for production
   • Have key rotation procedures
   • Document key creation and storage
EOF

echo ""
echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════"
echo "                     AM335x eFuse Information"  
echo "════════════════════════════════════════════════════════════════════════${NC}"
echo ""

cat << 'EOF'
AM335x Control Module Registers (for reference only):

  CONTROL_STATUS (0x44E10040)
    - Bits 5:4: SYSBOOT[5:4] - Boot device selection
    - Bit 6: DEVTYPE - 0=GP, 1=HS device

  CONTROL_SEC_STATUS (0x44E1004C)  
    - Security status register
    - Indicates secure boot state

  EFUSE_SMA (0x44E10750)
    - eFuse spare bits

Key Hash Storage:
    - MPK Hash stored in eFuse
    - 256-bit SHA-256 hash of public key
    - Compared during ROM boot

Reading Current State:
    devmem2 0x44E10040  # Read control status
    devmem2 0x44E1004C  # Read security status

WARNING: Writing to eFuse registers is PERMANENT!
EOF

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo ""
echo "This script is for INFORMATION ONLY."
echo "It does not modify any eFuses or security settings."
echo ""
echo "For secure boot implementation, use the U-Boot verified boot"
echo "approach described in the other scripts in this directory."
echo ""
