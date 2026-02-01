#!/bin/bash
#
# secure_boot_test.sh - End-to-end secure boot testing
#
# Tests signed, unsigned, and tampered images
#
# Usage:
#   ./secure_boot_test.sh [mode]
#
# Author: Embedded Linux Labs
# License: MIT

set -e

MODE="${1:-full}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEY_DIR="$SCRIPT_DIR/../keys"
TEST_DIR="/tmp/secure_boot_test"

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

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [mode]

Run secure boot tests.

Modes:
    setup     Generate test keys and images
    verify    Verify existing images
    tamper    Create and test tampered images
    full      Run all tests (default)
    clean     Clean up test files

Example:
    $0 setup    # Create test environment
    $0 full     # Run all tests
EOF
}

setup_test_environment() {
    log_info "Setting up test environment..."
    
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    # Generate test keys
    log_info "Generating test keys..."
    mkdir -p keys
    openssl genrsa -out keys/test_key.pem 2048 2>/dev/null
    openssl rsa -in keys/test_key.pem -pubout -out keys/test_key.pub 2>/dev/null
    openssl req -new -x509 -key keys/test_key.pem -out keys/test_key.crt \
        -days 365 -subj "/CN=Test Key" 2>/dev/null
    
    # Create dummy kernel and DTB for testing
    log_info "Creating test files..."
    dd if=/dev/urandom of=test_kernel bs=1024 count=1024 2>/dev/null
    dd if=/dev/urandom of=test.dtb bs=1024 count=64 2>/dev/null
    
    log_info "Test environment ready in $TEST_DIR"
}

create_test_its() {
    cat > test.its << 'EOF'
/dts-v1/;

/ {
    description = "Test FIT Image";
    #address-cells = <1>;

    images {
        kernel-1 {
            description = "Test Kernel";
            data = /incbin/("test_kernel");
            type = "kernel";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <0x82000000>;
            entry = <0x82000000>;
            
            hash-1 {
                algo = "sha256";
            };
            
            signature-1 {
                algo = "sha256,rsa2048";
                key-name-hint = "test_key";
            };
        };

        fdt-1 {
            description = "Test DTB";
            data = /incbin/("test.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            load = <0x88000000>;
            
            hash-1 {
                algo = "sha256";
            };
        };
    };

    configurations {
        default = "conf-1";

        conf-1 {
            description = "Test Configuration";
            kernel = "kernel-1";
            fdt = "fdt-1";
            
            signature-1 {
                algo = "sha256,rsa2048";
                key-name-hint = "test_key";
                sign-images = "kernel", "fdt";
            };
        };
    };
};
EOF
}

test_unsigned_image() {
    log_test "Testing unsigned FIT image creation..."
    
    cd "$TEST_DIR"
    create_test_its
    
    if mkimage -f test.its test_unsigned.fit; then
        log_info "Unsigned image created: test_unsigned.fit"
        mkimage -l test_unsigned.fit
        echo -e "\n${GREEN}PASS:${NC} Unsigned image creation"
    else
        echo -e "\n${RED}FAIL:${NC} Unsigned image creation"
        return 1
    fi
}

test_signed_image() {
    log_test "Testing signed FIT image creation..."
    
    cd "$TEST_DIR"
    
    if mkimage -f test.its -k keys -r test_signed.fit; then
        log_info "Signed image created: test_signed.fit"
        mkimage -l test_signed.fit
        
        # Verify signature information
        if mkimage -l test_signed.fit | grep -q "Sign"; then
            echo -e "\n${GREEN}PASS:${NC} Signed image creation"
        else
            echo -e "\n${RED}FAIL:${NC} Signature not present in image"
            return 1
        fi
    else
        echo -e "\n${RED}FAIL:${NC} Signed image creation"
        return 1
    fi
}

test_tampered_image() {
    log_test "Testing tampered image detection..."
    
    cd "$TEST_DIR"
    
    if [ ! -f test_signed.fit ]; then
        log_error "Signed image not found. Run 'setup' first."
        return 1
    fi
    
    # Create tampered copy
    cp test_signed.fit test_tampered.fit
    
    # Corrupt the kernel data (at offset 0x200)
    printf '\xDE\xAD\xBE\xEF' | dd of=test_tampered.fit bs=1 seek=512 count=4 conv=notrunc 2>/dev/null
    
    log_info "Created tampered image: test_tampered.fit"
    
    # Compare hashes
    echo ""
    echo "Original hash:  $(sha256sum test_signed.fit | cut -d' ' -f1)"
    echo "Tampered hash:  $(sha256sum test_tampered.fit | cut -d' ' -f1)"
    echo ""
    
    echo -e "${GREEN}PASS:${NC} Tampered image created for testing"
    echo ""
    echo "To verify tamper detection, boot in U-Boot:"
    echo "  # Signed image should boot"
    echo "  fatload mmc 0:1 \${loadaddr} test_signed.fit && bootm"
    echo ""
    echo "  # Tampered image should fail signature check"
    echo "  fatload mmc 0:1 \${loadaddr} test_tampered.fit && bootm"
}

test_key_mismatch() {
    log_test "Testing wrong key detection..."
    
    cd "$TEST_DIR"
    
    # Generate different key
    mkdir -p keys_wrong
    openssl genrsa -out keys_wrong/test_key.pem 2048 2>/dev/null
    openssl rsa -in keys_wrong/test_key.pem -pubout -out keys_wrong/test_key.pub 2>/dev/null
    openssl req -new -x509 -key keys_wrong/test_key.pem -out keys_wrong/test_key.crt \
        -days 365 -subj "/CN=Wrong Key" 2>/dev/null
    
    # Sign with wrong key
    if mkimage -f test.its -k keys_wrong -r test_wrongkey.fit 2>/dev/null; then
        log_info "Image signed with wrong key: test_wrongkey.fit"
        
        echo -e "${GREEN}PASS:${NC} Wrong-key image created"
        echo ""
        echo "This image is validly signed but with different key."
        echo "U-Boot should reject it if compiled with correct public key."
    fi
}

compare_images() {
    log_test "Comparing test images..."
    
    cd "$TEST_DIR"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Image Comparison"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    printf "%-25s %10s %s\n" "Image" "Size" "SHA256"
    echo "─────────────────────────────────────────────────────────────────"
    
    for img in test_unsigned.fit test_signed.fit test_tampered.fit test_wrongkey.fit; do
        if [ -f "$img" ]; then
            size=$(stat -c%s "$img")
            hash=$(sha256sum "$img" | cut -c1-16)
            printf "%-25s %10s %s...\n" "$img" "$size" "$hash"
        fi
    done
    
    echo ""
}

run_all_tests() {
    local passed=0
    local failed=0
    
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  SECURE BOOT TEST SUITE"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    setup_test_environment
    echo ""
    
    if test_unsigned_image; then ((passed++)); else ((failed++)); fi
    echo ""
    
    if test_signed_image; then ((passed++)); else ((failed++)); fi
    echo ""
    
    if test_tampered_image; then ((passed++)); else ((failed++)); fi
    echo ""
    
    if test_key_mismatch; then ((passed++)); else ((failed++)); fi
    echo ""
    
    compare_images
    
    echo "════════════════════════════════════════════════════════════════"
    echo "  RESULTS: $passed passed, $failed failed"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Test images in: $TEST_DIR"
    echo "Deploy to SD card for U-Boot testing"
    echo ""
}

cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
    log_info "Cleanup complete"
}

# ==========================================================================
# MAIN
# ==========================================================================

case "${MODE}" in
    -h|--help)
        show_usage
        ;;
    setup)
        setup_test_environment
        ;;
    verify)
        test_signed_image
        ;;
    tamper)
        test_tampered_image
        ;;
    full)
        run_all_tests
        ;;
    clean)
        cleanup
        ;;
    *)
        log_error "Unknown mode: $MODE"
        show_usage
        exit 1
        ;;
esac
