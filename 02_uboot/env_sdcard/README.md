# U-Boot Environment Persistence Lab

This lab teaches you how to configure U-Boot environment storage so that your settings persist across reboots.

## Why Environment Persistence Matters

By default, U-Boot may store its environment in the binary itself, which means:
- Changes made with `setenv` are lost on reset
- You can't customize boot behavior permanently
- Each boot requires manual configuration

Persistent environment storage solves this by saving to:
- MMC/SD card (raw or filesystem)
- SPI flash
- NAND flash
- EEPROM

## Understanding Environment Storage

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  ENVIRONMENT STORAGE OPTIONS                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Option 1: Raw MMC (CONFIG_ENV_IS_IN_MMC)                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                     │   │
│  │  SD Card Layout:                                                    │   │
│  │  ┌──────────────────────────────────────────────────────────────┐  │   │
│  │  │ Sector 0-2047 │ Boot │ RootFS │ ...                          │  │   │
│  │  │ (Raw area)    │ Part │ Part   │                              │  │   │
│  │  │               │      │        │                              │  │   │
│  │  │ ▲             │      │        │                              │  │   │
│  │  │ │             │      │        │                              │  │   │
│  │  │ Environment   │      │        │                              │  │   │
│  │  │ stored here   │      │        │                              │  │   │
│  │  └──────────────────────────────────────────────────────────────┘  │   │
│  │                                                                     │   │
│  │  CONFIG_ENV_OFFSET = 0x100000 (1MB into SD card)                   │   │
│  │  CONFIG_ENV_SIZE = 0x2000 (8KB)                                     │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Option 2: FAT Filesystem (CONFIG_ENV_IS_IN_FAT)                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                     │   │
│  │  Boot Partition (FAT32):                                            │   │
│  │  ├── zImage                                                         │   │
│  │  ├── board.dtb                                                      │   │
│  │  └── uboot.env  ← Environment stored as file                       │   │
│  │                                                                     │   │
│  │  Pros: Easy to backup, edit, restore                                │   │
│  │  Cons: Slightly slower access                                       │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Part 1: Check Current Environment Storage

### At U-Boot Prompt

```bash
# Check if environment is being loaded from storage
=> printenv
# Look at the end for something like:
# Environment size: 1234/8188 bytes

# Try to save
=> saveenv
Saving Environment to MMC...
Writing to MMC(0)... OK   ← Success!
# or
Saving Environment to MMC... failed   ← Storage not configured
```

### In U-Boot Configuration

Check your board's defconfig or run menuconfig:

```bash
# In U-Boot source directory
grep ENV configs/your_board_defconfig

# Common settings:
CONFIG_ENV_IS_IN_MMC=y
CONFIG_ENV_OFFSET=0x100000
CONFIG_ENV_SIZE=0x2000

# Or for FAT:
CONFIG_ENV_IS_IN_FAT=y
CONFIG_ENV_FAT_INTERFACE="mmc"
CONFIG_ENV_FAT_DEVICE_AND_PART="0:1"
CONFIG_ENV_FAT_FILE="uboot.env"
```

## Part 2: Configure Environment in MMC (Raw)

### Step 1: Modify U-Boot Configuration

```bash
cd u-boot
make menuconfig
```

Navigate to:
```
Environment  --->
    [*] Environment is in a MMC device
    (0x100000) Environment offset
    (0x2000) Environment Size
    (0) MMC device for environment
```

### Step 2: Rebuild and Deploy

```bash
make -j$(nproc)
# Copy new u-boot.bin to SD card
```

### Step 3: Test Persistence

```bash
# At U-Boot prompt
=> setenv my_test_var "Hello World"
=> printenv my_test_var
my_test_var=Hello World

=> saveenv
Saving Environment to MMC... OK

=> reset

# After reset:
=> printenv my_test_var
my_test_var=Hello World   ← It persisted!
```

## Part 3: Configure Environment in FAT

This method stores environment as a file, making it easy to edit and backup.

### Step 1: Configure U-Boot

In menuconfig:
```
Environment  --->
    [*] Environment is in a FAT filesystem
    (mmc) Interface for environment
    (0:1) Device and partition for environment
    (uboot.env) File name for environment
```

Or in your defconfig:
```
CONFIG_ENV_IS_IN_FAT=y
CONFIG_ENV_FAT_INTERFACE="mmc"
CONFIG_ENV_FAT_DEVICE_AND_PART="0:1"
CONFIG_ENV_FAT_FILE="uboot.env"
CONFIG_ENV_SIZE=0x4000
```

### Step 2: Create Initial Environment File (Optional)

You can pre-create an environment file on the host:

```bash
# Create text environment file
cat > uboot_env.txt << 'EOF'
bootdelay=3
bootcmd=run mmc_boot
mmc_boot=load mmc 0:1 ${loadaddr} zImage; load mmc 0:1 ${fdt_addr} board.dtb; bootz ${loadaddr} - ${fdt_addr}
bootargs=console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait rw
EOF

# Convert to binary format (optional, U-Boot can use text)
mkenvimage -s 0x4000 -o uboot.env uboot_env.txt

# Copy to boot partition
sudo cp uboot.env /mnt/boot/
```

## Part 4: Essential Environment Variables

### Create a Standard Boot Environment

```bash
# At U-Boot prompt, set up complete boot environment:

# Console settings
=> setenv console ttyS0,115200

# Memory addresses (board-specific)
=> setenv loadaddr 0x80800000
=> setenv fdt_addr 0x82000000

# File names
=> setenv fdtfile bcm2710-rpi-3-b.dtb

# Boot arguments
=> setenv bootargs 'console=${console} root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw'

# MMC boot command
=> setenv mmc_boot 'load mmc 0:1 ${loadaddr} zImage; load mmc 0:1 ${fdt_addr} ${fdtfile}; bootz ${loadaddr} - ${fdt_addr}'

# Main boot command
=> setenv bootcmd 'run mmc_boot'

# Save everything
=> saveenv
```

### Verify Configuration

```bash
# Print all relevant variables
=> printenv bootcmd bootargs loadaddr fdt_addr

# Test boot
=> run bootcmd
```

## Part 5: Environment Management Commands

### View Environment

```bash
# Print all variables
=> printenv

# Print specific variable
=> printenv bootcmd

# Print variables matching pattern (if supported)
=> env grep boot
```

### Modify Environment

```bash
# Set a variable
=> setenv myvar "my value"

# Set variable with spaces (use quotes)
=> setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rw'

# Delete a variable
=> setenv myvar

# Create compound variable (references other vars)
=> setenv kernel_file zImage
=> setenv load_kernel 'load mmc 0:1 ${loadaddr} ${kernel_file}'
```

### Save and Reset Environment

```bash
# Save to storage
=> saveenv

# Reset to default (compiled-in) environment
=> env default -a

# Don't forget to save after reset if you want defaults persistent!
=> saveenv
```

## Part 6: Backup and Restore

### Export Environment

```bash
# At U-Boot (if supported)
=> env export -t 0x81000000
=> md.b 0x81000000 1000

# On host: Dump from SD card raw sector
sudo dd if=/dev/sdb of=env_backup.bin bs=1 skip=$((0x100000)) count=8192
```

### Restore Environment

```bash
# On host: Write to SD card
sudo dd if=env_backup.bin of=/dev/sdb bs=1 seek=$((0x100000))

# Or for FAT file:
sudo cp uboot.env /mnt/boot/
```

## Part 7: Linux Access to U-Boot Environment

Install fw_printenv/fw_setenv on your Linux system:

```bash
# Install tools
sudo apt-get install u-boot-tools

# Configure (tell tools where environment is)
sudo cat > /etc/fw_env.config << 'EOF'
# Device         Offset      Size
/dev/mmcblk0     0x100000    0x2000
EOF

# Read environment from Linux
sudo fw_printenv

# Modify environment from Linux
sudo fw_setenv bootdelay 5

# Useful for scripted updates!
```

---

## Example Environment Configuration File

See [uboot_env_config.txt](uboot_env_config.txt) for a complete example.

---

## Common Mistakes

### Mistake 1: Environment Not Saving

```bash
# Symptom:
=> saveenv
Saving Environment to nowhere... not possible

# Cause: Environment storage not configured
# Solution: Enable CONFIG_ENV_IS_IN_MMC or similar
```

### Mistake 2: Environment in Wrong Location

```bash
# Symptom: saveenv succeeds but changes don't persist

# Cause: Offset overlaps with partition or wrong device
# Debug: Check CONFIG_ENV_OFFSET doesn't overlap with data

# For SD card, first partition usually starts at sector 2048 (1MB)
# So environment at 0x100000 (1MB) might overlap!
# Solution: Use offset before partition (e.g., 0x80000) or use FAT method
```

### Mistake 3: Environment Size Mismatch

```bash
# Symptom: Some variables not saved

# Cause: Environment too large for allocated space
# Check: printenv shows "Environment size: XXXX/YYYY bytes"
# If XXXX is close to YYYY, increase CONFIG_ENV_SIZE
```

---

## What You Learned

After completing this lab:

1. ✅ How U-Boot environment storage works
2. ✅ How to configure environment in raw MMC
3. ✅ How to configure environment in FAT filesystem  
4. ✅ Essential environment variables for boot
5. ✅ How to backup and restore environment
6. ✅ How to access U-Boot environment from Linux
