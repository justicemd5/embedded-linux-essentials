#!/bin/bash
#
# sign_image.sh - Sign FIT image with RSA key
#
# Signs a FIT image and optionally embeds public key in U-Boot DTB
#
# Usage:
#   ./sign_image.sh [fit_image] [key_dir] [uboot_dtb]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

FIT_IMAGE="${1:-image.fit}"
KEY_DIR="${2:-./keys}"
UBOOT_DTB="${3:-}"
KEY_NAME="${KEY_NAME:-dev_key}"
OUTPUT="${FIT_IMAGE%.fit}.fit.signed"

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

show_usage() {
    cat << EOF
Usage: $0 [fit_image] [key_dir] [uboot_dtb]

Sign a FIT image with RSA private key.

Arguments:
    fit_image   FIT image to sign (default: image.fit)
    key_dir     Directory containing keys (default: ./keys)
    uboot_dtb   U-Boot DTB to embed public key (optional)

Environment:
    KEY_NAME    Key file base name (default: dev_key)

Examples:
    $0 image.fit ./keys
    $0 image.fit ./keys ~/bbb/u-boot/arch/arm/dts/am335x-boneblack.dtb

Note:
    If uboot_dtb is provided, the public key will be embedded.
    You must rebuild U-Boot after this to include the key.
EOF
}

check_prerequisites() {
    if ! command -v mkimage &> /dev/null; then
        log_error "mkimage not found. Install u-boot-tools:"
        echo "  sudo apt install u-boot-tools"
        exit 1
    fi
    
    if [ ! -f "$FIT_IMAGE" ]; then
        log_error "FIT image not found: $FIT_IMAGE"
        exit 1
    fi
    
    if [ ! -f "$KEY_DIR/${KEY_NAME}.pem" ]; then
        log_error "Private key not found: $KEY_DIR/${KEY_NAME}.pem"
        echo "Generate keys first: ./generate_keys.sh"
        exit 1
    fi
    
    log_info "FIT image: $FIT_IMAGE"
    log_info "Key directory: $KEY_DIR"
    log_info "Key name: $KEY_NAME"
}

find_its_file() {
    # Try to find the corresponding ITS file
    ITS_FILE="${FIT_IMAGE%.fit}.its"
    
    if [ ! -f "$ITS_FILE" ]; then
        ITS_FILE="image.its"
    fi
    
    if [ ! -f "$ITS_FILE" ]; then
        log_error "ITS file not found. Need original ITS to sign."
        log_error "Tried: ${FIT_IMAGE%.fit}.its, image.its"
        exit 1
    fi
    
    log_info "ITS file: $ITS_FILE"
}

sign_fit_image() {
    log_info "Signing FIT image..."
    
    local cmd="mkimage -f $ITS_FILE -k $KEY_DIR"
    
    if [ -n "$UBOOT_DTB" ]; then
        if [ ! -f "$UBOOT_DTB" ]; then
            log_error "U-Boot DTB not found: $UBOOT_DTB"
            exit 1
        fi
        log_info "Embedding public key in: $UBOOT_DTB"
        cmd="$cmd -K $UBOOT_DTB"
    fi
    
    cmd="$cmd -r $OUTPUT"
    
    log_info "Running: $cmd"
    $cmd
    
    log_info "Signed image created: $OUTPUT"
}

verify_signature() {
    log_info "Verifying signed image..."
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    mkimage -l "$OUTPUT"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Check if signatures are present
    if mkimage -l "$OUTPUT" 2>&1 | grep -q "Sign"; then
        log_info "Signature blocks present in image"
    else
        log_warn "No signature blocks found - image may not be properly signed"
    fi
}

verify_key_embedding() {
    if [ -n "$UBOOT_DTB" ]; then
        log_info "Checking public key in U-Boot DTB..."
        
        if fdtget "$UBOOT_DTB" /signature/key-${KEY_NAME} key-name-hint 2>/dev/null; then
            log_info "Public key successfully embedded in U-Boot DTB"
            echo ""
            echo "Key node contents:"
            fdtget "$UBOOT_DTB" /signature/key-${KEY_NAME} rsa,modulus 2>/dev/null | head -c 100
            echo "..."
        else
            log_warn "Could not verify key embedding (fdtget may not be available)"
        fi
    fi
}

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  IMAGE SIGNED SUCCESSFULLY"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Output files:"
    ls -la "$OUTPUT"
    echo ""
    
    if [ -n "$UBOOT_DTB" ]; then
        echo "Public key embedded in: $UBOOT_DTB"
        echo ""
        echo -e "${YELLOW}IMPORTANT:${NC} Rebuild U-Boot to include the public key:"
        echo "  cd ~/bbb/u-boot"
        echo "  make -j\$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-"
        echo ""
    fi
    
    echo "Deployment:"
    echo "  1. Copy ${OUTPUT##*/} to SD card boot partition"
    echo "  2. In U-Boot:"
    echo "     fatload mmc 0:1 \${loadaddr} ${OUTPUT##*/}"
    echo "     bootm \${loadaddr}"
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
echo " FIT Image Signer"
echo "========================================"
echo ""

check_prerequisites
find_its_file
sign_fit_image
verify_signature
verify_key_embedding
print_summary
