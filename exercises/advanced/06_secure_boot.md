# Exercise 6: Secure Boot Implementation

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

---

## Directory Structure

```
06_secure_boot/
├── scripts/
│   ├── generate_keys.sh       # RSA key pair generation
│   ├── create_fit_image.sh    # FIT image creation
│   ├── sign_image.sh          # Image signing with mkimage
│   ├── verify_image.sh        # Signature verification
│   ├── secure_boot_test.sh    # End-to-end testing
│   └── hab_info.sh            # HAB/eFuse information (reference)
├── configs/
│   ├── image.its              # FIT image source template
│   ├── image_with_ramdisk.its # FIT with initramfs
│   ├── image_multi.its        # Multi-configuration FIT
│   └── uboot_secure.config    # U-Boot config fragment
└── docs/
    ├── key_management.md      # Key management best practices
    └── troubleshooting.md     # Common issues and solutions
```

## Quick Start

```bash
cd /home/mp/embedded-linux-essentials/exercises/advanced/06_secure_boot

# 1. Generate signing keys
chmod +x scripts/*.sh
./scripts/generate_keys.sh

# 2. Create FIT image (adjust paths as needed)
./scripts/create_fit_image.sh \
    ~/bbb/linux/arch/arm/boot/zImage \
    ~/bbb/linux/arch/arm/boot/dts/am335x-boneblack.dtb

# 3. Sign the image
./scripts/sign_image.sh image.fit ./keys

# 4. Verify the signature
./scripts/verify_image.sh image.fit.signed

# 5. Run full test suite
./scripts/secure_boot_test.sh full
```

---

## Objective

Implement a verified boot chain with signed images to ensure only authorized software runs.

## Prerequisites

- Understanding of cryptographic concepts
- U-Boot source with FIT image support
- OpenSSL for key generation
- mkimage tool from U-Boot

## Difficulty: ⭐⭐⭐⭐⭐ Master

---

## Warning

⚠️ **Secure boot implementation can brick your device if done incorrectly!**

- Always keep a recovery method available
- Test thoroughly on development boards first
- Never enable secure boot on production without full testing
- The AM335x has limited secure boot features compared to newer SoCs

---

## Tasks

1. Generate signing keys
2. Create signed FIT images
3. Configure U-Boot for verification
4. Test secure boot flow

---

## Secure Boot Overview

```
┌─────────────────────────────────────────────────────────────┐
│                 SECURE BOOT CHAIN                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐   Verify   ┌──────────┐   Verify   ┌───────┐ │
│  │   ROM    │ ────────►  │   MLO    │ ────────►  │U-Boot │ │
│  │(BootROM) │  (HAB*)    │  (SPL)   │            │       │ │
│  └──────────┘            └──────────┘            └───────┘ │
│                                                      │      │
│                                                      │      │
│                                       ┌──────────────┘      │
│                                       ▼  Verify            │
│                          ┌─────────────────────────┐       │
│                          │     FIT Image           │       │
│                          │  ┌─────────────────┐    │       │
│                          │  │ Kernel (signed) │    │       │
│                          │  └─────────────────┘    │       │
│                          │  ┌─────────────────┐    │       │
│                          │  │  DTB (signed)   │    │       │
│                          │  └─────────────────┘    │       │
│                          │  ┌─────────────────┐    │       │
│                          │  │ Initrd (signed) │    │       │
│                          │  └─────────────────┘    │       │
│                          └─────────────────────────┘       │
│                                                             │
│  * HAB (High Assurance Boot) requires eFuse programming    │
│    which is irreversible. This exercise focuses on         │
│    U-Boot verified boot (software-based).                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Guide

### Step 1: Set Up Key Directory

```bash
mkdir -p ~/bbb/secure-boot/keys
cd ~/bbb/secure-boot/keys
```

### Step 2: Generate RSA Key Pair

```bash
# Generate 2048-bit RSA private key
openssl genrsa -out dev_key.pem 2048

# Extract public key
openssl rsa -in dev_key.pem -pubout -out dev_key.pub

# Create certificate (for some signing tools)
openssl req -new -x509 -key dev_key.pem -out dev_cert.crt \
    -days 3650 -subj "/CN=BBB Dev Key"

# Verify key
openssl rsa -in dev_key.pem -check
```

### Step 3: Build U-Boot with Verified Boot

```bash
cd ~/bbb/u-boot

# Configure for AM335x with FIT support
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- am335x_evm_defconfig

# Enable verified boot
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig
```

**Required U-Boot config:**

```
Boot options --->
    [*] Support Flattened Image Tree
    [*]   Support FIT image signing (NEW)

Library routines --->
    Security support --->
        [*] RSA signature verification
        [*] Enable RSA signature verification in SPL (optional)

# For newer U-Boot:
CONFIG_FIT=y
CONFIG_FIT_SIGNATURE=y
CONFIG_FIT_SIGNATURE_ENFORCE=y    # Reject unsigned images
CONFIG_RSA=y
CONFIG_RSA_VERIFY=y
```

**Build U-Boot:**

```bash
make -j$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
```

### Step 4: Create FIT Image Source (.its)

```bash
cd ~/bbb/secure-boot

cat > image.its << 'EOF'
/dts-v1/;

/ {
    description = "Signed kernel for BeagleBone Black";
    #address-cells = <1>;

    images {
        kernel-1 {
            description = "Linux kernel for AM335x";
            data = /incbin/("zImage");
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
                key-name-hint = "dev_key";
            };
        };

        fdt-1 {
            description = "BeagleBone Black DTB";
            data = /incbin/("am335x-boneblack.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            
            hash-1 {
                algo = "sha256";
            };
            
            signature-1 {
                algo = "sha256,rsa2048";
                key-name-hint = "dev_key";
            };
        };
    };

    configurations {
        default = "conf-1";

        conf-1 {
            description = "BeagleBone Black Secure Boot Config";
            kernel = "kernel-1";
            fdt = "fdt-1";
            
            signature-1 {
                algo = "sha256,rsa2048";
                key-name-hint = "dev_key";
                sign-images = "kernel", "fdt";
            };
        };
    };
};
EOF
```

### Step 5: Create and Sign FIT Image

```bash
# Copy kernel and DTB
cp ~/bbb/linux/arch/arm/boot/zImage .
cp ~/bbb/linux/arch/arm/boot/dts/am335x-boneblack.dtb .

# Create unsigned FIT image first
mkimage -f image.its image.fit

# Sign the FIT image (this also adds public key to U-Boot DTB)
mkimage -f image.its \
    -k keys/ \
    -K ~/bbb/u-boot/arch/arm/dts/am335x-boneblack.dtb \
    -r \
    image.fit.signed

# Verify signature was added
mkimage -l image.fit.signed
```

### Step 6: Rebuild U-Boot with Public Key

```bash
cd ~/bbb/u-boot

# The mkimage command above added our public key to the U-Boot DTB
# Now rebuild U-Boot to include it
make -j$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
```

### Step 7: Deploy Secure Boot Components

```bash
# Mount SD card
sudo mount /dev/sdX1 /mnt

# Copy U-Boot (contains public key)
sudo cp ~/bbb/u-boot/MLO /mnt/
sudo cp ~/bbb/u-boot/u-boot.img /mnt/

# Copy signed FIT image
sudo cp ~/bbb/secure-boot/image.fit.signed /mnt/image.fit

sudo umount /mnt
```

### Step 8: Configure U-Boot to Boot FIT

```bash
# On BBB U-Boot console
setenv bootcmd 'fatload mmc 0:1 ${loadaddr} image.fit; bootm ${loadaddr}'
setenv bootargs 'console=ttyO0,115200n8 root=/dev/mmcblk0p2 rootwait'
saveenv
```

---

## Testing Secure Boot

### Test 1: Verify Signed Image Boots

```bash
# Should boot normally
=> fatload mmc 0:1 ${loadaddr} image.fit
=> bootm ${loadaddr}
# Expected: Kernel boots successfully
```

### Test 2: Verify Unsigned Image Fails

```bash
# Create unsigned image
cd ~/bbb/secure-boot
mkimage -f image.its image.fit.unsigned

# Try to boot (should fail if CONFIG_FIT_SIGNATURE_ENFORCE=y)
=> fatload mmc 0:1 ${loadaddr} image.fit.unsigned
=> bootm ${loadaddr}
# Expected: "Bad FIT signature" or similar error
```

### Test 3: Verify Tampered Image Fails

```bash
# Tamper with signed image
cp image.fit.signed image.fit.tampered
# Modify a byte somewhere in the kernel
dd if=/dev/zero of=image.fit.tampered bs=1 count=1 seek=1000 conv=notrunc

# Try to boot
=> fatload mmc 0:1 ${loadaddr} image.fit.tampered
=> bootm ${loadaddr}
# Expected: Signature verification fails
```

---

## Advanced: HAB (Hardware-Based) Secure Boot

⚠️ **WARNING: Programming eFuses is IRREVERSIBLE!**

The AM335x supports HAB (High Assurance Boot) through TI's secure boot mechanism:

```
┌─────────────────────────────────────────────────────────────┐
│              AM335x HAB SECURE BOOT                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Generate Customer Key (CMPK/SMPK)                       │
│  2. Sign MLO (SPL) with TI signing tool                     │
│  3. Program key hash into eFuses                            │
│  4. Set eFuse to enforce secure boot                        │
│                                                             │
│  ⚠️ Once eFuses are programmed:                             │
│  • Only signed MLO will boot                                │
│  • Cannot be undone                                         │
│  • Lost key = bricked device                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

For production, consult:
- TI Sitara AM335x Security Guide
- TI Code Signing Tool documentation

---

## Key Management Best Practices

```
┌─────────────────────────────────────────────────────────────┐
│                KEY MANAGEMENT                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Development:                                               │
│  • Use separate dev/prod keys                               │
│  • Store dev keys in secure location                        │
│  • Rotate keys periodically                                 │
│                                                             │
│  Production:                                                │
│  • Use HSM (Hardware Security Module)                       │
│  • Implement key ceremony procedures                        │
│  • Have key escrow/backup plan                              │
│  • Document key holders and processes                       │
│                                                             │
│  Key Storage:                                               │
│  • Never store private keys in VCS                          │
│  • Use encrypted storage                                    │
│  • Limit access to key holders                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Verification Checklist

- [ ] RSA key pair generated
- [ ] U-Boot built with FIT signature support
- [ ] FIT image created with kernel and DTB
- [ ] FIT image signed successfully
- [ ] Public key embedded in U-Boot DTB
- [ ] Signed image boots successfully
- [ ] Unsigned image rejected
- [ ] Tampered image rejected
- [ ] Keys stored securely

---

[← Previous: PREEMPT_RT](05_preempt_rt.md) | [Back to Index](README.md) | [Next: Buildroot →](07_buildroot.md)
