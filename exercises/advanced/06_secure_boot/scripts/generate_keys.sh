#!/bin/bash
#
# generate_keys.sh - Generate signing keys for secure boot
#
# Creates RSA key pairs for signing FIT images
#
# Usage:
#   ./generate_keys.sh [key_name] [bits]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

KEY_NAME="${1:-dev_key}"
KEY_BITS="${2:-2048}"
KEY_DIR="${KEY_DIR:-./keys}"
VALIDITY_DAYS=3650  # 10 years

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
Usage: $0 [key_name] [bits]

Generate RSA key pair for signing FIT images.

Arguments:
    key_name    Base name for key files (default: dev_key)
    bits        Key size in bits (default: 2048)

Environment:
    KEY_DIR     Directory for keys (default: ./keys)

Output files:
    <key_name>.pem      Private key (KEEP SECRET!)
    <key_name>.pub      Public key
    <key_name>.crt      Self-signed certificate
    <key_name>_info.txt Key information

Example:
    $0 dev_key 2048        # Development key
    $0 prod_key 4096       # Production key (stronger)
EOF
}

check_openssl() {
    if ! command -v openssl &> /dev/null; then
        log_error "openssl not found. Install with: sudo apt install openssl"
        exit 1
    fi
    log_info "OpenSSL version: $(openssl version)"
}

create_key_directory() {
    if [ -d "$KEY_DIR" ]; then
        if [ -f "$KEY_DIR/${KEY_NAME}.pem" ]; then
            log_warn "Key already exists: $KEY_DIR/${KEY_NAME}.pem"
            read -p "Overwrite? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    fi
    
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"
    log_info "Key directory: $KEY_DIR"
}

generate_rsa_key() {
    log_info "Generating ${KEY_BITS}-bit RSA key pair..."
    
    # Generate private key
    openssl genrsa -out "$KEY_DIR/${KEY_NAME}.pem" "$KEY_BITS" 2>/dev/null
    chmod 600 "$KEY_DIR/${KEY_NAME}.pem"
    
    log_info "Private key: $KEY_DIR/${KEY_NAME}.pem"
}

extract_public_key() {
    log_info "Extracting public key..."
    
    openssl rsa -in "$KEY_DIR/${KEY_NAME}.pem" \
        -pubout -out "$KEY_DIR/${KEY_NAME}.pub" 2>/dev/null
    
    log_info "Public key: $KEY_DIR/${KEY_NAME}.pub"
}

create_certificate() {
    log_info "Creating self-signed certificate..."
    
    openssl req -new -x509 \
        -key "$KEY_DIR/${KEY_NAME}.pem" \
        -out "$KEY_DIR/${KEY_NAME}.crt" \
        -days "$VALIDITY_DAYS" \
        -subj "/CN=BBB Signing Key - ${KEY_NAME}/O=Embedded Linux Labs" \
        2>/dev/null
    
    log_info "Certificate: $KEY_DIR/${KEY_NAME}.crt"
}

verify_key() {
    log_info "Verifying key pair..."
    
    if openssl rsa -in "$KEY_DIR/${KEY_NAME}.pem" -check 2>&1 | grep -q "RSA key ok"; then
        log_info "Key verification: OK"
    else
        log_error "Key verification: FAILED"
        exit 1
    fi
}

create_key_info() {
    local info_file="$KEY_DIR/${KEY_NAME}_info.txt"
    
    cat > "$info_file" << EOF
========================================
  SIGNING KEY INFORMATION
========================================

Key Name:       ${KEY_NAME}
Key Size:       ${KEY_BITS} bits
Algorithm:      RSA
Generated:      $(date -Iseconds)
Valid For:      ${VALIDITY_DAYS} days
Fingerprint:    $(openssl rsa -in "$KEY_DIR/${KEY_NAME}.pem" -pubout -outform DER 2>/dev/null | openssl dgst -sha256 | awk '{print $2}')

Files:
  Private Key:  ${KEY_NAME}.pem (KEEP SECRET!)
  Public Key:   ${KEY_NAME}.pub
  Certificate:  ${KEY_NAME}.crt

Usage in mkimage:
  mkimage -f image.its -k $KEY_DIR -K u-boot.dtb -r image.fit

WARNING:
  - Never commit private key to version control
  - Store backups in secure location
  - Losing this key means you cannot sign new images

========================================
EOF
    
    log_info "Key info: $info_file"
}

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  KEY GENERATION COMPLETE"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Generated files in $KEY_DIR/:"
    ls -la "$KEY_DIR/"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC}"
    echo "  • Keep ${KEY_NAME}.pem SECRET - do not share or commit"
    echo "  • Backup keys to secure offline storage"
    echo "  • Public key will be embedded in U-Boot"
    echo ""
    echo "Next steps:"
    echo "  1. Create FIT image: ./create_fit_image.sh"
    echo "  2. Sign image:       ./sign_image.sh"
    echo "  3. Embed key in U-Boot and rebuild"
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
echo " Secure Boot Key Generator"
echo "========================================"
echo ""

check_openssl
create_key_directory
generate_rsa_key
extract_public_key
create_certificate
verify_key
create_key_info
print_summary
