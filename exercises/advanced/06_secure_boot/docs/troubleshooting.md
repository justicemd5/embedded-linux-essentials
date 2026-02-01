# Secure Boot Troubleshooting Guide

## Common Issues and Solutions

### 1. mkimage: command not found

**Symptom:**
```
./sign_image.sh: line 23: mkimage: command not found
```

**Solution:**
```bash
sudo apt install u-boot-tools
```

### 2. Key Not Found

**Symptom:**
```
Can't open keys/dev_key.pem: No such file or directory
```

**Solutions:**
```bash
# Check key exists
ls -la keys/

# Generate if missing
./generate_keys.sh

# Or specify correct path
KEY_DIR=/path/to/keys ./sign_image.sh
```

### 3. Signature Not Present in Image

**Symptom:**
mkimage shows no signature blocks

**Check:**
```bash
mkimage -l image.fit | grep -i sign
```

**Solutions:**
1. Ensure ITS file has signature nodes
2. Use -k flag to specify key directory
3. Key name must match key-name-hint in ITS

### 4. U-Boot: Signature Check Failed

**Symptom:**
```
## Checking hash(es) for Image ... sha256+ OK
## Verifying Hash Integrity ... sha256,rsa2048:dev_key- Failed
Bad FIT image format
```

**Causes:**
1. Public key not embedded in U-Boot
2. Wrong key used for signing
3. Image modified after signing

**Solutions:**
```bash
# Rebuild U-Boot with public key embedded
mkimage -f image.its -k keys -K u-boot.dtb -r image.fit
cd ~/bbb/u-boot
make -j$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-

# Verify key is in DTB
fdtget u-boot.dtb /signature/key-dev_key algo
```

### 5. Wrong Key Name Hint

**Symptom:**
```
Can't get key 'dev_key' required for FIT image
```

**Solution:**
Ensure key-name-hint matches key file name:
- Key file: `keys/mykey.pem`
- ITS file: `key-name-hint = "mykey";`

### 6. Configuration Signature Fails

**Symptom:**
Individual image hashes pass but configuration signature fails

**Cause:**
sign-images list doesn't match actual images in configuration

**Solution:**
Check ITS file:
```dts
configurations {
    conf-1 {
        kernel = "kernel-1";
        fdt = "fdt-1";
        signature-1 {
            sign-images = "kernel", "fdt";  // Must match above
        };
    };
};
```

### 7. Wrong Load Address

**Symptom:**
Kernel loads but crashes immediately

**Check AM335x addresses:**
```
Kernel: 0x82000000
DTB:    0x88000000
```

### 8. Compression Mismatch

**Symptom:**
```
Unimplemented compression type 1
```

**Solution:**
Ensure compression in ITS matches actual file:
```dts
kernel-1 {
    compression = "none";    // For zImage
    // compression = "gzip"; // For vmlinuz.gz
};
```

### 9. Architecture Mismatch

**Symptom:**
```
Wrong image architecture
```

**Solution:**
Set correct architecture in ITS:
```dts
arch = "arm";  // For 32-bit ARM
// arch = "arm64"; // For 64-bit ARM
```

### 10. U-Boot Not Configured for FIT

**Symptom:**
```
Unknown image format
```

**Solution:**
Enable FIT in U-Boot config:
```
CONFIG_FIT=y
CONFIG_FIT_SIGNATURE=y
CONFIG_RSA=y
CONFIG_SHA256=y
```

## Debugging Commands

### In U-Boot

```
# Show image information
iminfo ${loadaddr}

# Boot with verbose output
bootm -v ${loadaddr}

# Check memory contents
md.b ${loadaddr} 100

# Verify FDT
fdt addr ${fdt_addr}
fdt print /signature
```

### On Host

```bash
# Dump FIT structure
fdtdump image.fit

# Extract components
dumpimage -T flat_dt -p 0 -o kernel_extracted image.fit

# Verify hash manually
sha256sum kernel_extracted

# Check key in DTB
fdtget u-boot.dtb /signature/key-dev_key algo
```

## Verification Flow Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                     U-BOOT VERIFICATION FLOW                       │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  1. Load FIT image                                                 │
│     fatload mmc 0:1 ${loadaddr} image.fit                         │
│                        │                                           │
│                        ▼                                           │
│  2. Parse FIT header                                               │
│     Is it valid FIT?                                               │
│         │                                                          │
│     NO  │  YES                                                     │
│     ▼   ▼                                                          │
│   [FAIL]                                                           │
│                        │                                           │
│                        ▼                                           │
│  3. Check configuration signature                                  │
│     a. Find public key in U-Boot DTB                              │
│     b. Verify RSA signature                                        │
│     c. Verify SHA-256 hash                                         │
│         │                                                          │
│     FAIL│  PASS                                                    │
│     ▼   ▼                                                          │
│   [FAIL] (if required)                                             │
│                        │                                           │
│                        ▼                                           │
│  4. Verify each image hash                                         │
│     - Kernel SHA-256                                               │
│     - DTB SHA-256                                                  │
│     - Ramdisk SHA-256 (if present)                                │
│         │                                                          │
│     FAIL│  PASS                                                    │
│     ▼   ▼                                                          │
│   [FAIL]                                                           │
│                        │                                           │
│                        ▼                                           │
│  5. Load and boot kernel                                           │
│     [SUCCESS]                                                      │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

## Log Analysis

Enable U-Boot logging:
```
CONFIG_LOG=y
CONFIG_LOGLEVEL=7
```

Look for these messages:
```
Good: "sha256,rsa2048:dev_key+ OK"
Bad:  "sha256,rsa2048:dev_key- Failed"
Missing: "Can't get public key 'dev_key'"
```

## Quick Verification Test

```bash
#!/bin/bash
# quick_verify.sh - Quick verification of signing setup

echo "=== Secure Boot Quick Verify ==="

# Check tools
echo -n "mkimage: "
command -v mkimage >/dev/null && echo "OK" || echo "MISSING"

echo -n "openssl: "
command -v openssl >/dev/null && echo "OK" || echo "MISSING"

# Check keys
echo -n "Private key: "
[ -f keys/dev_key.pem ] && echo "OK" || echo "MISSING"

echo -n "Public key: "
[ -f keys/dev_key.pub ] && echo "OK" || echo "MISSING"

# Check FIT
echo -n "FIT image: "
if [ -f image.fit ]; then
    mkimage -l image.fit | grep -q "Hash" && echo "OK (signed)" || echo "OK (unsigned)"
else
    echo "MISSING"
fi

echo "=== Done ==="
```
