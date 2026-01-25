# Intermediate Exercises

Mid-level exercises covering kernel building, device tree, and boot customization.

## Prerequisites

- Completed [Beginner Exercises](beginner.md)
- Cross-compilation toolchain installed
- At least 10GB free disk space for kernel builds
- Familiarity with Makefiles

---

## Exercise 1: Build the Linux Kernel

### Objective
Cross-compile the Linux kernel from source for your target board.

### Tasks

1. Download kernel source
2. Configure with appropriate defconfig
3. Cross-compile kernel and modules
4. Deploy to target and boot

### Step-by-Step Guide

```bash
# 1. Clone kernel (or download tarball)
git clone --depth=1 --branch linux-6.6.y \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
cd linux

# 2. Set cross-compile variables
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

# 3. Configure (example for Raspberry Pi)
make bcm2711_defconfig

# 4. Optional: customize
make menuconfig

# 5. Build
make -j$(nproc) zImage modules dtbs

# 6. Check output
ls arch/arm/boot/zImage
ls arch/arm/boot/dts/*.dtb
```

### Expected Outcome

- Kernel image: `arch/arm/boot/zImage`
- Device tree blobs: `arch/arm/boot/dts/*.dtb`
- Modules in various subdirectories

### Deployment

```bash
# Copy to boot partition
sudo cp arch/arm/boot/zImage /media/boot/
sudo cp arch/arm/boot/dts/bcm2711-rpi-4-b.dtb /media/boot/

# Install modules to rootfs
sudo make INSTALL_MOD_PATH=/media/rootfs modules_install
```

### Verification Checklist
- [ ] Kernel builds without errors
- [ ] zImage file created
- [ ] DTB files generated
- [ ] Target boots with new kernel

### Troubleshooting Hints
- "arm-linux-gnueabihf-gcc: not found"? Install cross-compiler
- Out of disk space? Clean with `make clean`
- Wrong config? Start fresh with `make mrproper`

---

## Exercise 2: Kernel Configuration

### Objective
Enable/disable specific kernel features using menuconfig.

### Tasks

1. Start with working defconfig
2. Enable USB gadget support
3. Enable a specific filesystem (e.g., F2FS)
4. Disable unused features to reduce size

### Step-by-Step Guide

```bash
# Start from defconfig
make bcm2711_defconfig

# Enter menuconfig
make menuconfig

# Navigate to:
# Device Drivers → USB support → USB Gadget Support
# Enable: <M> USB Gadget Drivers

# File Systems → Miscellaneous filesystems
# Enable: <Y> F2FS filesystem support

# General Setup
# Disable features you don't need to reduce size

# Save and exit
# Build
make -j$(nproc) zImage
```

### Expected Outcome

Kernel with custom configuration that:
- Includes USB gadget support
- Includes F2FS support
- Is smaller than default (if features removed)

### Challenge: Kernel Size Reduction

Try to reduce kernel size by disabling:
- Unused network protocols
- Unused filesystems
- Debug symbols
- Unused drivers

Compare sizes:
```bash
# Before
ls -lh arch/arm/boot/zImage

# After modifications, rebuild and compare
make -j$(nproc) zImage
ls -lh arch/arm/boot/zImage
```

### Troubleshooting Hints
- Can't find option? Use `/` to search in menuconfig
- Dependency issues? Some options require others
- Boot fails? Start with known-working defconfig

---

## Exercise 3: Custom Device Tree Overlay

### Objective
Create a device tree overlay to configure GPIO pins.

### Tasks

1. Study existing device tree
2. Create overlay for LED on specific GPIO
3. Compile overlay
4. Apply and verify

### Step-by-Step Guide

**Create overlay file (led-overlay.dts):**

```c
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target-path = "/";
        __overlay__ {
            my_led: my_led {
                compatible = "gpio-leds";
                status = "okay";
                
                user_led {
                    label = "user-led";
                    gpios = <&gpio 17 0>;  /* GPIO17, active high */
                    linux,default-trigger = "heartbeat";
                };
            };
        };
    };
};
```

**Compile the overlay:**

```bash
dtc -@ -I dts -O dtb -o led-overlay.dtbo led-overlay.dts
```

**Apply on Raspberry Pi:**

```bash
# Copy to overlays directory
sudo cp led-overlay.dtbo /boot/overlays/

# Edit config.txt
sudo nano /boot/config.txt
# Add: dtoverlay=led-overlay

# Reboot
sudo reboot
```

### Expected Outcome

LED connected to GPIO17 blinks with heartbeat pattern.

### Verification

```bash
# Check if LED device exists
ls /sys/class/leds/
cat /sys/class/leds/user-led/trigger
```

### Troubleshooting Hints
- Overlay not loading? Check `dmesg` for errors
- LED not blinking? Verify GPIO number and polarity
- DTC errors? Check syntax, especially semicolons

---

## Exercise 4: Build U-Boot from Source

### Objective
Cross-compile U-Boot for your target board.

### Tasks

1. Download U-Boot source
2. Configure for target board
3. Build U-Boot
4. Deploy and test

### Step-by-Step Guide

```bash
# 1. Clone U-Boot
git clone --depth=1 --branch v2024.01 \
    https://source.denx.de/u-boot/u-boot.git
cd u-boot

# 2. Configure (example for Raspberry Pi 4)
make CROSS_COMPILE=arm-linux-gnueabihf- rpi_4_defconfig

# 3. Build
make CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)

# 4. Check output
ls u-boot.bin
```

### Deployment

```bash
# For Raspberry Pi (requires special naming)
sudo cp u-boot.bin /media/boot/u-boot.bin

# Update config.txt to load U-Boot
# kernel=u-boot.bin
```

### Expected Outcome

Custom-built U-Boot that:
- Boots on your target
- Shows your build timestamp
- Works identically to stock version

### Challenge: Customize U-Boot

Add a custom welcome message:
```bash
make menuconfig
# Navigate to: Boot options → Autoboot options
# Modify: Autoboot prompt
```

### Troubleshooting Hints
- Board doesn't boot? Keep backup of working U-Boot
- Wrong defconfig? Check `configs/` directory for your board
- Missing tools? Install `bison`, `flex`, `libssl-dev`

---

## Exercise 5: Create Minimal Initramfs

### Objective
Build a minimal initramfs with BusyBox for early userspace.

### Tasks

1. Download and build BusyBox
2. Create initramfs directory structure
3. Write init script
4. Package as cpio archive
5. Boot with initramfs

### Step-by-Step Guide

```bash
# 1. Build BusyBox
wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2
tar xf busybox-1.36.1.tar.bz2
cd busybox-1.36.1

make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig
# Enable: Settings → Build static binary
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- install

# 2. Create initramfs structure
mkdir -p ~/initramfs/{bin,sbin,etc,proc,sys,dev,tmp}
cp -a _install/* ~/initramfs/

# 3. Create init script
cat > ~/initramfs/init << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

echo "Welcome to minimal initramfs!"
echo "Kernel: $(uname -r)"
exec /bin/sh
EOF
chmod +x ~/initramfs/init

# 4. Create cpio archive
cd ~/initramfs
find . | cpio -H newc -o | gzip > ../initramfs.cpio.gz
```

### Boot with Initramfs

```bash
# At U-Boot:
=> tftp ${ramdisk_addr} initramfs.cpio.gz
=> setenv bootargs console=ttyS0,115200
=> bootz ${loadaddr} ${ramdisk_addr}:${filesize} ${fdt_addr}
```

### Expected Outcome

System boots to shell prompt from RAM-based filesystem.

### Verification Checklist
- [ ] BusyBox builds statically
- [ ] initramfs creates successfully
- [ ] System boots to shell
- [ ] Basic commands work (ls, cat, mount)

---

## Exercise 6: NFS Root Filesystem

### Objective
Boot embedded system with root filesystem over NFS.

### Tasks

1. Set up NFS server on host
2. Configure kernel for NFS root
3. Configure U-Boot bootargs
4. Boot and verify

### Step-by-Step Guide

**On Host:**

```bash
# Install NFS server
sudo apt-get install nfs-kernel-server

# Create export directory
sudo mkdir -p /export/rootfs
sudo cp -a /path/to/your/rootfs/* /export/rootfs/

# Configure exports
echo "/export/rootfs 192.168.1.0/24(rw,sync,no_root_squash)" | \
    sudo tee -a /etc/exports
sudo exportfs -ra
```

**On Target (U-Boot):**

```bash
=> setenv serverip 192.168.1.100
=> setenv bootargs console=ttyS0,115200 root=/dev/nfs \
   nfsroot=${serverip}:/export/rootfs,v3,tcp ip=dhcp
=> tftp ${loadaddr} zImage
=> tftp ${fdt_addr} board.dtb
=> bootz ${loadaddr} - ${fdt_addr}
```

### Expected Outcome

System boots with root filesystem mounted from NFS server.

### Verification

```bash
# On target, after boot:
mount | grep nfs
# Should show: 192.168.1.100:/export/rootfs on / type nfs ...
```

### Troubleshooting Hints
- "VFS: Cannot mount root"? Check NFS server, firewall, kernel config
- Timeout? Check network connectivity, ping server from U-Boot
- Permission errors? Verify `no_root_squash` in exports

---

## Summary

After completing these exercises, you can:

- ✅ Build Linux kernel from source
- ✅ Customize kernel configuration
- ✅ Create device tree overlays
- ✅ Build U-Boot from source
- ✅ Create custom initramfs
- ✅ Set up NFS root filesystem

---

## Next Steps

Continue to [Advanced Exercises](advanced.md) for complex debugging and system integration challenges.
