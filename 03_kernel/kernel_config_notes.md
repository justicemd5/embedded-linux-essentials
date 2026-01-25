# Kernel Configuration Notes

Important kernel configuration options for embedded Linux systems.

## Finding Configuration Options

```bash
# Search in menuconfig
make menuconfig
# Press '/' to search

# Search in .config
grep CONFIG_MMC .config

# Search in Kconfig files
find . -name Kconfig -exec grep -l "MMC" {} \;
```

## Essential Options by Category

### Console and Debug Output

```kconfig
# Serial console
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y

# Platform-specific serial
CONFIG_SERIAL_AMBA_PL011=y      # ARM AMBA
CONFIG_SERIAL_OMAP=y            # OMAP/AM335x
CONFIG_SERIAL_BCM63XX=y         # Broadcom

# Console on serial
CONFIG_CONSOLE=y
CONFIG_VT=y                     # Virtual terminals
CONFIG_VT_CONSOLE=y

# Early printk (debug)
CONFIG_EARLY_PRINTK=y
CONFIG_DEBUG_LL=y               # Low-level debug
```

### Storage

```kconfig
# MMC/SD card support
CONFIG_MMC=y
CONFIG_MMC_BLOCK=y

# Platform-specific MMC
CONFIG_MMC_SDHCI=y              # Generic SDHCI
CONFIG_MMC_SDHCI_PLTFM=y
CONFIG_MMC_BCM2835=y            # Raspberry Pi
CONFIG_MMC_OMAP=y               # BeagleBone
CONFIG_MMC_SDHCI_OF_ARASAN=y    # Arasan SDHCI

# USB storage
CONFIG_USB_STORAGE=y
```

### Filesystems

```kconfig
# Essential filesystems
CONFIG_EXT4_FS=y                # Most common rootfs
CONFIG_VFAT_FS=y                # Boot partition
CONFIG_NLS_CODEPAGE_437=y       # For VFAT
CONFIG_NLS_ISO8859_1=y          # For VFAT

# NFS for development
CONFIG_NFS_FS=y
CONFIG_NFS_V3=y
CONFIG_NFS_V4=y
CONFIG_ROOT_NFS=y               # NFS root support

# RAM-based
CONFIG_TMPFS=y
CONFIG_RAMFS=y

# Compressed
CONFIG_SQUASHFS=y               # Read-only compressed

# Pseudo filesystems
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y         # Auto-mount /dev
```

### Networking

```kconfig
# Core networking
CONFIG_NET=y
CONFIG_INET=y
CONFIG_IP_PNP=y                 # IP autoconfiguration
CONFIG_IP_PNP_DHCP=y            # DHCP support
CONFIG_IP_PNP_BOOTP=y           # BOOTP support

# Ethernet
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y

# Platform-specific Ethernet
CONFIG_USB_NET_SMSC95XX=y       # Raspberry Pi 3
CONFIG_BCMGENET=y               # Raspberry Pi 4
CONFIG_TI_CPSW=y                # BeagleBone
CONFIG_FEC=y                    # i.MX

# Wireless (optional)
CONFIG_WIRELESS=y
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_BRCMFMAC=y               # Raspberry Pi WiFi
```

### USB

```kconfig
# USB support
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_ANNOUNCE_NEW_DEVICES=y

# Host controllers
CONFIG_USB_DWC2=y               # Common on embedded
CONFIG_USB_XHCI_HCD=y           # USB 3.0

# USB classes
CONFIG_USB_HID=y                # Keyboard/mouse
CONFIG_USB_STORAGE=y            # Mass storage

# USB gadget (device mode)
CONFIG_USB_GADGET=y
CONFIG_USB_ETH=m                # Ethernet gadget
CONFIG_USB_MASS_STORAGE=m       # Mass storage gadget
```

### GPIO and Pinctrl

```kconfig
CONFIG_GPIOLIB=y
CONFIG_GPIO_SYSFS=y             # /sys/class/gpio (deprecated but useful)
CONFIG_GPIO_CDEV=y              # Character device interface

# Platform-specific
CONFIG_PINCTRL_BCM2835=y        # Raspberry Pi
CONFIG_GPIO_OMAP=y              # BeagleBone
CONFIG_PINCTRL_IMX6Q=y          # i.MX6
```

### I2C

```kconfig
CONFIG_I2C=y
CONFIG_I2C_CHARDEV=y            # /dev/i2c-X access

# Platform-specific
CONFIG_I2C_BCM2835=y            # Raspberry Pi
CONFIG_I2C_OMAP=y               # BeagleBone
CONFIG_I2C_IMX=y                # i.MX
```

### SPI

```kconfig
CONFIG_SPI=y
CONFIG_SPI_SPIDEV=y             # Userspace access

# Platform-specific
CONFIG_SPI_BCM2835=y            # Raspberry Pi
CONFIG_SPI_OMAP24XX=y           # BeagleBone
CONFIG_SPI_IMX=y                # i.MX
```

### PWM

```kconfig
CONFIG_PWM=y
CONFIG_PWM_SYSFS=y

# Platform-specific
CONFIG_PWM_BCM2835=y            # Raspberry Pi
CONFIG_PWM_OMAP_DMTIMER=y       # BeagleBone
```

### Watchdog

```kconfig
CONFIG_WATCHDOG=y
CONFIG_WATCHDOG_CORE=y

# Platform-specific
CONFIG_BCM2835_WDT=y            # Raspberry Pi
CONFIG_OMAP_WATCHDOG=y          # BeagleBone
CONFIG_IMX2_WDT=y               # i.MX
```

### Device Tree

```kconfig
CONFIG_OF=y                     # Device Tree support
CONFIG_OF_FLATTREE=y
CONFIG_OF_EARLY_FLATTREE=y
CONFIG_OF_ADDRESS=y
CONFIG_OF_IRQ=y
CONFIG_OF_OVERLAY=y             # Runtime overlays
```

### Initramfs

```kconfig
CONFIG_BLK_DEV_INITRD=y         # Initial RAM disk support
CONFIG_INITRAMFS_SOURCE=""      # Path to initramfs (if built-in)
CONFIG_RD_GZIP=y                # gzip compression
CONFIG_RD_XZ=y                  # xz compression (smaller)
```

### Debug Options

```kconfig
# Kernel debugging
CONFIG_DEBUG_KERNEL=y
CONFIG_DEBUG_INFO=y             # Debug symbols (large!)
CONFIG_KALLSYMS=y               # Symbol names in kernel

# Magic SysRq
CONFIG_MAGIC_SYSRQ=y

# Kernel log
CONFIG_LOG_BUF_SHIFT=17         # Log buffer size (128KB)
CONFIG_PRINTK=y

# Dynamic debug
CONFIG_DYNAMIC_DEBUG=y          # pr_debug() support
```

### Power Management

```kconfig
CONFIG_PM=y
CONFIG_PM_SLEEP=y
CONFIG_SUSPEND=y
CONFIG_CPU_FREQ=y
CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
```

---

## Size Optimization

For minimal kernel size:

```kconfig
# Disable these for smaller kernel
CONFIG_DEBUG_INFO=n
CONFIG_KALLSYMS=n
CONFIG_PRINTK=n                 # Warning: No kernel messages!
CONFIG_BUG=n                    # Warning: No BUG() checks!
CONFIG_MODULES=n                # No loadable modules

# Use compression
CONFIG_KERNEL_GZIP=y            # Faster decompression
CONFIG_KERNEL_XZ=y              # Smaller size

# Strip symbols
CONFIG_STRIP_ASM_SYMS=y
```

---

## Boot Time Optimization

```kconfig
# Faster boot
CONFIG_PRINTK_TIME=n            # No timestamps
CONFIG_CC_OPTIMIZE_FOR_SIZE=y   # Smaller, sometimes faster

# Disable unused drivers
# Check initcall_debug bootarg to find slow initializations
```

---

## Platform-Specific Configurations

### Raspberry Pi 3/4

```kconfig
CONFIG_ARCH_BCM2835=y
CONFIG_BCM2835_MBOX=y
CONFIG_BCM2835_POWER=y
CONFIG_RASPBERRYPI_FIRMWARE=y
CONFIG_DRM_VC4=y                # GPU
CONFIG_SND_BCM2835=y            # Audio
```

### BeagleBone Black

```kconfig
CONFIG_ARCH_OMAP2PLUS=y
CONFIG_SOC_AM33XX=y
CONFIG_OMAP_OCP2SCP=y
CONFIG_PINCTRL_SINGLE=y
CONFIG_MFD_TPS65217=y           # PMIC
CONFIG_REGULATOR_TPS65217=y
CONFIG_AM335X_PHY_USB=y
```

### i.MX6

```kconfig
CONFIG_ARCH_MXC=y
CONFIG_SOC_IMX6Q=y
CONFIG_PINCTRL_IMX6Q=y
CONFIG_MFD_SYSCON=y
CONFIG_REGULATOR_ANATOP=y
CONFIG_REGULATOR_PFUZE100=y
```

---

## Saving Configuration

```bash
# Save full config
cp .config ~/my_board_config

# Save minimal config
make savedefconfig
cp defconfig ~/my_board_defconfig

# Save to arch configs
cp defconfig arch/arm/configs/myboard_defconfig
```
