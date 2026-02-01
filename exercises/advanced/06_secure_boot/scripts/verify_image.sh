#!/bin/bash
#
# verify_image.sh - Verify signed FIT image
#
# Verifies signatures using mkimage and optional U-Boot DTB
#
# Usage:
#   ./verify_image.sh [fit_image] [uboot_dtb]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

FIT_IMAGE="${1:-image.fit.signed}"
UBOOT_DTB="${2:-}"

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [fit_image] [uboot_dtb]

Verify signatures on a FIT image.

Arguments:
    fit_image   Signed FIT image (default: image.fit.signed)
    uboot_dtb   U-Boot DTB with public key (optional, for full verify)

Examples:
    $0 image.fit.signed
    $0 image.fit.signed ~/bbb/u-boot/arch/arm/dts/am335x-boneblack.dtb
EOF
}

check_prerequisites() {
    if ! command -v mkimage &> /dev/null; then
        log_error "mkimage not found"
        exit 1
    fi
    
    if [ ! -f "$FIT_IMAGE" ]; then
        log_error "FIT image not found: $FIT_IMAGE"
        exit 1
    fi
}

show_image_info() {
    log_info "FIT Image Information:"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    mkimage -l "$FIT_IMAGE"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

extract_and_check_hashes() {
    log_info "Extracting image components..."
    
    local tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT
    
    # Use dumpimage to extract components
    if command -v dumpimage &> /dev/null; then
        dumpimage -T flat_dt -p 0 -o "$tmpdir/kernel" "$FIT_IMAGE" 2>/dev/null && \
            log_info "Kernel extracted: $(stat -c%s "$tmpdir/kernel") bytes" || \
            log_warn "Could not extract kernel"
        
        dumpimage -T flat_dt -p 1 -o "$tmpdir/dtb" "$FIT_IMAGE" 2>/dev/null && \
            log_info "DTB extracted: $(stat -c%s "$tmpdir/dtb") bytes" || \
            log_warn "Could not extract DTB"
    else
        log_warn "dumpimage not available - skipping extraction"
    fi
}

check_signature_presence() {
    log_info "Checking signature presence..."
    
    local sig_count=0
    
    if mkimage -l "$FIT_IMAGE" 2>&1 | grep -q "Signature"; then
        sig_count=$(mkimage -l "$FIT_IMAGE" 2>&1 | grep -c "Sign" || true)
        log_pass "Found $sig_count signature blocks"
    else
        log_fail "No signatures found in image"
        return 1
    fi
    
    # Check hash algorithm
    if mkimage -l "$FIT_IMAGE" 2>&1 | grep -q "sha256"; then
        log_pass "Using SHA-256 hash algorithm"
    fi
    
    # Check RSA algorithm
    if mkimage -l "$FIT_IMAGE" 2>&1 | grep -q "rsa"; then
        log_pass "Using RSA signature algorithm"
    fi
}

verify_with_dtb() {
    if [ -n "$UBOOT_DTB" ]; then
        log_info "Verifying with U-Boot DTB..."
        
        if [ ! -f "$UBOOT_DTB" ]; then
            log_error "U-Boot DTB not found: $UBOOT_DTB"
            return 1
        fi
        
        # mkimage can verify if DTB has the key
        if mkimage -K "$UBOOT_DTB" -k . "$FIT_IMAGE" 2>&1 | grep -q "Verified"; then
            log_pass "Signature verification PASSED"
        else
            log_warn "Could not verify signature with DTB"
            log_info "Note: Full verification requires U-Boot runtime"
        fi
    else
        log_info "No U-Boot DTB provided - skipping full verification"
        echo "  For full verification, provide U-Boot DTB with embedded public key"
    fi
}

tamper_test() {
    log_info "Creating tampered test image..."
    
    local tmpfile=$(mktemp)
    cp "$FIT_IMAGE" "$tmpfile"
    
    # Corrupt a byte in the image
    printf '\x00' | dd of="$tmpfile" bs=1 seek=1000 count=1 conv=notrunc 2>/dev/null
    
    echo ""
    log_info "Tampered image should fail verification in U-Boot"
    log_info "Test on target:"
    echo "  fatload mmc 0:1 \${loadaddr} tampered.fit"
    echo "  bootm \${loadaddr}"
    echo "  # Should show: Signature check failed"
    
    rm -f "$tmpfile"
}

run_security_checks() {
    echo ""
    log_info "Security Checklist:"
    echo ""
    
    local checks_passed=0
    local checks_total=5
    
    # Check 1: Image has signatures
    if mkimage -l "$FIT_IMAGE" 2>&1 | grep -q "Signature"; then
        echo -e "  [${GREEN}✓${NC}] Signatures present"
        ((checks_passed++))
    else
        echo -e "  [${RED}✗${NC}] Signatures missing"
    fi
    
    # Check 2: Using strong hash
    if mkimage -l "$FIT_IMAGE" 2>&1 | grep -q "sha256"; then
        echo -e "  [${GREEN}✓${NC}] SHA-256 hash algorithm"
        ((checks_passed++))
    else
        echo -e "  [${RED}✗${NC}] Weak or no hash algorithm"
    fi
    
    # Check 3: RSA signature
    if mkimage -l "$FIT_IMAGE" 2>&1 | grep -q "rsa2048\|rsa4096"; then
        echo -e "  [${GREEN}✓${NC}] RSA-2048+ signature"
        ((checks_passed++))
    else
        echo -e "  [${RED}✗${NC}] Weak or no RSA signature"
    fi
    
    # Check 4: Multiple components signed
    local comp_count=$(mkimage -l "$FIT_IMAGE" 2>&1 | grep -c "signature" || true)
    if [ "$comp_count" -ge 2 ]; then
        echo -e "  [${GREEN}✓${NC}] Multiple components signed ($comp_count)"
        ((checks_passed++))
    else
        echo -e "  [${YELLOW}!${NC}] Only $comp_count component(s) signed"
    fi
    
    # Check 5: Required signature
    if mkimage -l "$FIT_IMAGE" 2>&1 | grep -qi "required"; then
        echo -e "  [${GREEN}✓${NC}] Signature marked required"
        ((checks_passed++))
    else
        echo -e "  [${YELLOW}!${NC}] Signature not marked required"
        echo "     Note: Use -r flag with mkimage to require signatures"
    fi
    
    echo ""
    echo "Security score: $checks_passed/$checks_total"
    echo ""
}

print_test_commands() {
    echo ""
    log_info "U-Boot Test Commands:"
    echo ""
    echo "# Load and boot signed image"
    echo "fatload mmc 0:1 \${loadaddr} ${FIT_IMAGE##*/}"
    echo "bootm \${loadaddr}"
    echo ""
    echo "# Check signature (with debug)"
    echo "bootm -v \${loadaddr}"
    echo ""
    echo "# Expected output for valid signature:"
    echo "#   Verifying Hash Integrity ... sha256+ OK"
    echo "#   Verifying ... sha256,rsa2048:dev_key+ OK"
    echo ""
}

# ==========================================================================
# MAIN
# ==========================================================================

case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
esac

echo ""
echo "========================================"
echo " FIT Image Verifier"
echo "========================================"
echo ""

check_prerequisites
show_image_info
extract_and_check_hashes
check_signature_presence
verify_with_dtb
run_security_checks
print_test_commands
