# Key Management Best Practices

## Overview

Secure boot is only as strong as your key management. Compromise of the private
key means an attacker can sign malicious software that your device will trust.

## Development vs Production Keys

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          KEY HIERARCHY                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────────┐                    ┌───────────────────┐            │
│  │  DEVELOPMENT      │                    │  PRODUCTION       │            │
│  │                   │                    │                   │            │
│  │  dev_key.pem      │                    │  prod_key.pem     │            │
│  │                   │                    │                   │            │
│  │  • Local storage  │                    │  • HSM storage    │            │
│  │  • Team access    │                    │  • Restricted     │            │
│  │  • Rotate often   │                    │  • Audit logged   │            │
│  │  • Not in git     │                    │  • Backup secure  │            │
│  │                   │                    │                   │            │
│  └───────────────────┘                    └───────────────────┘            │
│           │                                        │                        │
│           ▼                                        ▼                        │
│  ┌───────────────────┐                    ┌───────────────────┐            │
│  │  Test builds      │                    │  Release builds   │            │
│  │  CI/CD testing    │                    │  Field devices    │            │
│  │  Development HW   │                    │  Customer units   │            │
│  └───────────────────┘                    └───────────────────┘            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Storage Options

### 1. File System (Development Only)
```bash
# Create secure directory
mkdir -p ~/.secure_keys
chmod 700 ~/.secure_keys

# Generate key with protection
openssl genrsa -aes256 -out ~/.secure_keys/dev_key.pem 2048
chmod 600 ~/.secure_keys/dev_key.pem

# Add to .gitignore
echo "*.pem" >> .gitignore
echo "*.key" >> .gitignore
echo "keys/" >> .gitignore
```

### 2. Encrypted Storage
```bash
# Create encrypted container
dd if=/dev/urandom of=keystore.img bs=1M count=10
cryptsetup luksFormat keystore.img
cryptsetup luksOpen keystore.img keystore
mkfs.ext4 /dev/mapper/keystore
mount /dev/mapper/keystore /mnt/keystore

# Store keys
cp prod_key.pem /mnt/keystore/

# Unmount when done
umount /mnt/keystore
cryptsetup luksClose keystore
```

### 3. Hardware Security Module (Production)
```bash
# List HSM slots
pkcs11-tool --list-slots

# Generate key on HSM
pkcs11-tool --module /usr/lib/libsofthsm2.so \
    --login --pin 1234 \
    --keypairgen --key-type RSA:2048 \
    --label prod_key

# Sign using HSM
# Requires custom tooling - mkimage doesn't directly support PKCS#11
```

## Key Rotation Strategy

### Development Keys
- Rotate: Monthly or when team changes
- Process: Generate new key, rebuild U-Boot, update all dev devices

### Production Keys
- Rotate: Annually or after security incident
- Process: 
  1. Generate new key
  2. Sign new release with both old and new keys
  3. Update devices via OTA
  4. Retire old key after all devices updated

## Backup Procedures

### Development
```bash
# Encrypted backup
tar czf - keys/ | gpg -c > keys_backup_$(date +%Y%m%d).tar.gz.gpg

# Restore
gpg -d keys_backup_20240101.tar.gz.gpg | tar xzf -
```

### Production
```
┌─────────────────────────────────────────────────────────────────┐
│                    KEY BACKUP STRATEGY                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Primary:   HSM in secure facility                              │
│  Backup 1:  Encrypted USB in bank safe deposit box              │
│  Backup 2:  Encrypted USB in different geographic location      │
│  Backup 3:  M-of-N split key with executives                   │
│                                                                 │
│  Recovery procedure documented and tested annually              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Key Compromise Response

If a private key is compromised:

1. **Immediate**: Stop signing with compromised key
2. **Assess**: Determine exposure window
3. **Generate**: Create new key pair
4. **Distribute**: Push new public key to devices (if possible)
5. **Revoke**: Blacklist old key in devices (if supported)
6. **Investigate**: Determine how compromise occurred
7. **Document**: Record incident and response

## Certificate Authority Setup

For more complex deployments, use a proper PKI:

```bash
# Create CA (do once)
openssl genrsa -aes256 -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
    -subj "/CN=Embedded Device CA/O=Your Company"

# Create device signing key
openssl genrsa -out device_sign.key 2048
openssl req -new -key device_sign.key -out device_sign.csr \
    -subj "/CN=Device Signing Key/O=Your Company"

# Sign with CA
openssl x509 -req -days 365 \
    -in device_sign.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out device_sign.crt
```

## Audit Logging

Track all key operations:

```bash
# Log key usage
log_key_use() {
    local key="$1"
    local action="$2"
    local user=$(whoami)
    local timestamp=$(date -Iseconds)
    echo "$timestamp,$user,$key,$action" >> /var/log/key_audit.log
}

# Example usage
log_key_use "prod_key" "sign_image_v2.3.0"
```

## Security Checklist

- [ ] Private keys never in version control
- [ ] Private keys encrypted at rest
- [ ] Access to private keys logged
- [ ] Key backup exists and tested
- [ ] Development and production keys are different
- [ ] Key rotation schedule defined
- [ ] Compromise response plan documented
- [ ] Public key embedded in U-Boot
- [ ] Signature verification enabled in U-Boot
- [ ] Test devices do not have production keys

## References

- OpenSSL Documentation: https://www.openssl.org/docs/
- U-Boot Verified Boot: doc/uImage.FIT/verified-boot.txt in U-Boot source
- HSM Best Practices: https://cloudhsm-best-practices.awssecworkshops.com/
