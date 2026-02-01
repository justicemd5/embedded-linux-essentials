# Exercise 8: Yocto Project / OpenEmbedded

> **⚠️ AI-GENERATED CONTENT DISCLAIMER**
> This material was auto-generated and should be validated before use in production.

**Target Platform:** BeagleBone Black Rev C (AM335x)

---

## Directory Structure

```
08_yocto/
├── scripts/
│   ├── setup_yocto.sh         # Download and setup Yocto/Poky
│   ├── build_image.sh         # Build images with various options
│   └── create_recipe.sh       # Create new recipes interactively
└── layer/
    ├── conf/
    │   └── layer.conf          # Layer configuration
    ├── recipes-core/
    │   └── images/
    │       └── bbb-custom-image.bb
    ├── recipes-app/
    │   └── myapp/
    │       ├── myapp_1.0.bb    # Example recipe
    │       └── files/
    │           ├── myapp.c
    │           └── Makefile
    └── recipes-kernel/
        └── linux/
            ├── linux-yocto_%.bbappend
            └── files/
                └── bbb-custom.cfg
```

## Quick Start

```bash
cd /home/mp/embedded-linux-essentials/exercises/advanced/08_yocto

# 1. Setup Yocto (downloads ~5GB)
chmod +x scripts/*.sh
./scripts/setup_yocto.sh scarthgap ~/yocto-bbb

# 2. Initialize build environment
cd ~/yocto-bbb/poky
source oe-init-build-env build-bbb

# 3. Build minimal image (1-2 hours first time)
bitbake core-image-minimal

# 4. Flash to SD card
xz -dk tmp/deploy/images/beaglebone-yocto/core-image-minimal-*.wic.xz
sudo dd if=core-image-minimal-*.wic of=/dev/sdX bs=4M status=progress
```

---

## Objective

Create a custom Linux distribution using the Yocto Project for the BeagleBone Black.

## Prerequisites

- Linux development host (Ubuntu 22.04 recommended)
- 100GB+ free disk space
- 16GB+ RAM (8GB minimum, build will be slow)
- Fast internet connection
- Patience (first build takes 2-6 hours)

## Difficulty: ⭐⭐⭐⭐ Expert

---

## Yocto vs Buildroot

```
┌─────────────────────────────────────────────────────────────┐
│                 YOCTO vs BUILDROOT                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Buildroot:                                                 │
│  • Simpler, faster to learn                                 │
│  • Smaller images                                           │
│  • Complete rebuild for changes                             │
│  • Good for small-medium projects                           │
│                                                             │
│  Yocto:                                                     │
│  • More complex, steeper learning curve                     │
│  • Incremental builds (change one package, rebuild one)     │
│  • Rich ecosystem of layers                                 │
│  • Package management (opkg, rpm, deb)                      │
│  • SDK generation                                           │
│  • License compliance tools                                 │
│  • Industry standard for embedded Linux                     │
│  • Better for large, long-term projects                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Guide

### Step 1: Install Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect xz-utils \
    debianutils iputils-ping python3-git python3-jinja2 libegl1-mesa \
    libsdl1.2-dev pylint xterm python3-subunit mesa-common-dev zstd liblz4-tool
```

### Step 2: Clone Poky (Yocto Reference Distribution)

```bash
cd ~
mkdir yocto-bbb && cd yocto-bbb

# Clone Poky (use matching branch for all layers!)
git clone -b scarthgap git://git.yoctoproject.org/poky.git
cd poky

# Clone meta-ti layer for BeagleBone support
git clone -b scarthgap git://git.yoctoproject.org/meta-ti.git

# Clone additional useful layers
git clone -b scarthgap git://git.openembedded.org/meta-openembedded
```

### Step 3: Initialize Build Environment

```bash
# Source the build environment script
source oe-init-build-env build-bbb

# You're now in ~/yocto-bbb/poky/build-bbb
```

### Step 4: Configure Build

**Edit conf/local.conf:**

```bash
cat >> conf/local.conf << 'EOF'

# BeagleBone Black configuration
MACHINE = "beaglebone-yocto"

# Parallelization (adjust for your system)
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"

# Download directory (can be shared between builds)
DL_DIR = "${TOPDIR}/../downloads"

# Shared state cache (speeds up rebuilds)
SSTATE_DIR = "${TOPDIR}/../sstate-cache"

# Disk space monitoring
BB_DISKMON_DIRS = "\
    STOPTASKS,${TMPDIR},1G,100K \
    STOPTASKS,${DL_DIR},1G,100K \
    STOPTASKS,${SSTATE_DIR},1G,100K \
    ABORT,${TMPDIR},100M,1K \
    ABORT,${DL_DIR},100M,1K \
    ABORT,${SSTATE_DIR},100M,1K"

# Extra image features
EXTRA_IMAGE_FEATURES += "debug-tweaks ssh-server-dropbear tools-debug"

# Package format
PACKAGE_CLASSES = "package_ipk"

# Filesystem types to generate
IMAGE_FSTYPES = "tar.xz ext4 wic.xz"
EOF
```

**Edit conf/bblayers.conf:**

```bash
# Add meta-ti and meta-openembedded layers
cat > conf/bblayers.conf << 'EOF'
POKY_BBLAYERS_CONF_VERSION = "2"

BBPATH = "${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \
  ${TOPDIR}/../meta \
  ${TOPDIR}/../meta-poky \
  ${TOPDIR}/../meta-yocto-bsp \
  ${TOPDIR}/../meta-ti/meta-ti-bsp \
  ${TOPDIR}/../meta-openembedded/meta-oe \
  ${TOPDIR}/../meta-openembedded/meta-python \
  ${TOPDIR}/../meta-openembedded/meta-networking \
  "
EOF
```

### Step 5: Build Core Image

```bash
# Build minimal image (fastest, ~1-2 hours first time)
bitbake core-image-minimal

# Or build full image with more packages
bitbake core-image-base

# Or build development image
bitbake core-image-full-cmdline
```

### Step 6: Locate Build Artifacts

```bash
ls tmp/deploy/images/beaglebone-yocto/

# Expected files:
# MLO                          - SPL
# u-boot.img                   - U-Boot
# zImage                       - Kernel
# am335x-boneblack.dtb        - Device tree
# core-image-minimal-*.rootfs.ext4
# core-image-minimal-*.wic.xz  - Complete SD image
```

### Step 7: Flash SD Card

```bash
# Use the WIC image (complete ready-to-flash image)
xz -dk tmp/deploy/images/beaglebone-yocto/core-image-minimal-beaglebone-yocto.wic.xz

# Flash to SD card
sudo dd if=core-image-minimal-beaglebone-yocto.wic of=/dev/sdX bs=4M status=progress
sync
```

---

## Creating Custom Layer

### Create Layer Structure

```bash
cd ~/yocto-bbb/poky
bitbake-layers create-layer meta-bbb-custom

# Or manually:
mkdir -p meta-bbb-custom/{conf,recipes-core,recipes-app}
```

**meta-bbb-custom/conf/layer.conf:**

```bash
cat > meta-bbb-custom/conf/layer.conf << 'EOF'
BBPATH .= ":${LAYERDIR}"
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
            ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "meta-bbb-custom"
BBFILE_PATTERN_meta-bbb-custom = "^${LAYERDIR}/"
BBFILE_PRIORITY_meta-bbb-custom = "10"

LAYERDEPENDS_meta-bbb-custom = "core"
LAYERSERIES_COMPAT_meta-bbb-custom = "scarthgap"
EOF
```

### Add Custom Recipe

**meta-bbb-custom/recipes-app/myapp/myapp_1.0.bb:**

```bash
mkdir -p meta-bbb-custom/recipes-app/myapp/files

cat > meta-bbb-custom/recipes-app/myapp/myapp_1.0.bb << 'EOF'
SUMMARY = "My custom BeagleBone Black application"
DESCRIPTION = "A sample application for BBB"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://myapp.c \
           file://Makefile"

S = "${WORKDIR}"

do_compile() {
    oe_runmake
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 myapp ${D}${bindir}
}
EOF
```

**Create source files:**

```bash
cat > meta-bbb-custom/recipes-app/myapp/files/myapp.c << 'EOF'
#include <stdio.h>

int main(void)
{
    printf("Hello from BeagleBone Black!\n");
    printf("Custom Yocto application running.\n");
    return 0;
}
EOF

cat > meta-bbb-custom/recipes-app/myapp/files/Makefile << 'EOF'
CC ?= gcc
CFLAGS ?= -O2 -Wall

myapp: myapp.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f myapp
EOF
```

### Create Custom Image

**meta-bbb-custom/recipes-core/images/bbb-custom-image.bb:**

```bash
mkdir -p meta-bbb-custom/recipes-core/images

cat > meta-bbb-custom/recipes-core/images/bbb-custom-image.bb << 'EOF'
SUMMARY = "Custom BeagleBone Black image"
DESCRIPTION = "Custom embedded Linux image for BBB"

require recipes-core/images/core-image-base.bb

# Additional packages
IMAGE_INSTALL += " \
    myapp \
    i2c-tools \
    devmem2 \
    htop \
    python3 \
    python3-pip \
    bash \
    dropbear \
    "

# Enable hardware features
IMAGE_FEATURES += "ssh-server-dropbear"

# Increase root filesystem size
IMAGE_ROOTFS_SIZE = "262144"
EOF
```

### Add Layer and Build

```bash
cd ~/yocto-bbb/poky/build-bbb

# Add custom layer
bitbake-layers add-layer ../meta-bbb-custom

# Build custom image
bitbake bbb-custom-image
```

---

## Useful Yocto Commands

```bash
# List available recipes
bitbake-layers show-recipes | grep linux

# Search for packages
bitbake -s | grep python

# Show recipe info
bitbake -e myapp | grep ^S=

# Enter devshell for debugging
bitbake -c devshell linux-yocto

# Clean a package
bitbake -c cleanall myapp

# Rebuild single package
bitbake -c cleansstate myapp && bitbake myapp

# Generate SDK
bitbake -c populate_sdk bbb-custom-image
```

---

## Customizing the Kernel

### Using bbappend

```bash
mkdir -p meta-bbb-custom/recipes-kernel/linux/files

cat > meta-bbb-custom/recipes-kernel/linux/linux-yocto_%.bbappend << 'EOF'
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://custom.cfg"

# Add kernel config fragments
SRC_URI += "file://enable-gpio.cfg"
EOF

# Create config fragment
cat > meta-bbb-custom/recipes-kernel/linux/files/enable-gpio.cfg << 'EOF'
CONFIG_GPIO_SYSFS=y
CONFIG_GPIO_CDEV=y
EOF
```

### Interactive Kernel Configuration

```bash
bitbake -c menuconfig virtual/kernel
bitbake -c savedefconfig virtual/kernel
```

---

## Device Tree Customization

```bash
mkdir -p meta-bbb-custom/recipes-kernel/linux/files

# Create device tree overlay
cat > meta-bbb-custom/recipes-kernel/linux/files/bbb-custom.dts << 'EOF'
/dts-v1/;
/plugin/;

&am33xx_pinmux {
    custom_led_pins: custom_led_pins {
        pinctrl-single,pins = <
            0x078 0x07  /* P9_12 GPIO1_28 output */
        >;
    };
};

&{/} {
    custom_leds {
        compatible = "gpio-leds";
        pinctrl-names = "default";
        pinctrl-0 = <&custom_led_pins>;

        custom_led {
            label = "custom:led";
            gpios = <&gpio1 28 0>;
            default-state = "off";
        };
    };
};
EOF
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "No space left" | Clear tmp/, use bigger disk |
| "Fetch error" | Check internet, or use `BB_NO_NETWORK = "1"` with local sources |
| "Layer not found" | Check `bblayers.conf`, verify paths |
| "Recipe not found" | Run `bitbake-layers show-recipes` to verify |
| Slow builds | Use `sstate-cache`, increase BB_NUMBER_THREADS |

### Debug Build Failures

```bash
# View build log
cat tmp/work/*/myapp/1.0-r0/temp/log.do_compile

# Enter devshell
bitbake -c devshell myapp

# Show environment
bitbake -e myapp > myapp-env.txt
```

---

## Verification Checklist

- [ ] Yocto dependencies installed
- [ ] Poky and layers cloned
- [ ] Build environment initialized
- [ ] local.conf configured for BBB
- [ ] bblayers.conf includes all layers
- [ ] core-image-minimal builds successfully
- [ ] SD card flashed and boots
- [ ] Custom layer created
- [ ] Custom recipe builds
- [ ] Custom image includes your packages

---

[← Previous: Buildroot](07_buildroot.md) | [Back to Index](README.md) | [Next: Custom Init →](09_custom_init.md)
