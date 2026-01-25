# Beginner Exercises

Entry-level exercises for getting started with Embedded Linux development.

## Prerequisites

- Completed [Lab 01: Boot Flow](../01_boot_flow/README.md)
- Serial console access to your board
- Basic Linux command-line familiarity

---

## Exercise 1: First Serial Connection

### Objective
Establish serial communication with your embedded board and capture boot messages.

### Tasks

1. Connect USB-to-Serial adapter to your board
2. Configure terminal emulator (picocom or screen)
3. Power on the board and observe boot messages
4. Capture the complete boot log to a file

### Step-by-Step Guide

```bash
# 1. Find your serial device
ls /dev/ttyUSB* /dev/ttyACM*

# 2. Connect with picocom
picocom -b 115200 /dev/ttyUSB0

# 3. Power on board and watch output

# 4. To log output:
picocom -b 115200 /dev/ttyUSB0 | tee boot_log.txt
```

### Expected Outcome

You should see output similar to:
```
U-Boot 2024.01 (Jan 15 2024)
DRAM:  1 GiB
...
Hit any key to stop autoboot: 3
...
Starting kernel ...
[    0.000000] Booting Linux on physical CPU 0x0
...
```

### Verification Checklist
- [ ] Can see U-Boot output
- [ ] Can see kernel boot messages
- [ ] Successfully logged to file
- [ ] Know how to exit terminal emulator

### Troubleshooting Hints
- No output? Check TX/RX wiring (try swapping)
- Garbage characters? Try different baud rates (9600, 115200)
- Permission denied? `sudo usermod -a -G dialout $USER`

---

## Exercise 2: U-Boot Exploration

### Objective
Learn to interrupt boot and use basic U-Boot commands.

### Tasks

1. Interrupt the boot process to get U-Boot prompt
2. Explore the environment with `printenv`
3. Check system information with `bdinfo`
4. Examine storage with `mmc info`

### Step-by-Step Guide

```bash
# 1. Boot and press any key when you see:
Hit any key to stop autoboot: 3

# 2. At U-Boot prompt:
=> help          # List all commands
=> printenv      # Show environment
=> bdinfo        # Board info
=> mmc info      # SD card info
=> mmc part      # Partition table
=> ls mmc 0:1    # List boot partition files
```

### Expected Outcome

You can navigate U-Boot and understand:
- How to get to the prompt
- What files are on boot partition
- Basic board configuration

### Questions to Answer
1. What is your board's memory size? (Hint: `bdinfo`)
2. What kernel filename is used? (Hint: `printenv bootcmd`)
3. How many partitions does your SD card have?

### Troubleshooting Hints
- Missed autoboot? Just power cycle and try again
- "Command not found"? Check spelling, use `help` to list commands
- "MMC: no card"? Reseat SD card, then `mmc rescan`

---

## Exercise 3: Kernel Boot Parameters

### Objective
Understand and modify kernel command line (bootargs).

### Tasks

1. View current bootargs
2. Understand each parameter
3. Add `debug` parameter temporarily
4. Boot with modified parameters

### Step-by-Step Guide

```bash
# At U-Boot prompt:

# 1. View current bootargs
=> printenv bootargs

# 2. Add debug parameter (temporary - not saved)
=> setenv bootargs ${bootargs} debug

# 3. View modified bootargs
=> printenv bootargs

# 4. Boot with new parameters
=> boot
```

### Expected Outcome

Kernel boots with more verbose output due to `debug` parameter.

### Parameter Reference

| Parameter | Purpose |
|-----------|---------|
| `console=ttyS0,115200` | Serial console output |
| `root=/dev/mmcblk0p2` | Root filesystem device |
| `rootwait` | Wait for root device |
| `debug` | Enable kernel debug output |
| `loglevel=8` | Maximum log verbosity |

### Challenge Exercise
Try booting with `loglevel=0` and observe the difference in output verbosity.

### Troubleshooting Hints
- Kernel hangs? Check `console=` device is correct
- "Cannot mount root"? Check `root=` device exists
- Want to undo? Just power cycle (didn't use `saveenv`)

---

## Exercise 4: File System Exploration

### Objective
Navigate and understand the embedded Linux file system.

### Tasks

1. Boot into Linux
2. Explore directory structure
3. Identify key configuration files
4. Check mounted filesystems

### Step-by-Step Guide

```bash
# After booting to Linux:

# 1. Check what's mounted
mount
df -h

# 2. Explore root directories
ls /
ls /etc
ls /bin

# 3. Key files to examine
cat /etc/os-release      # OS information
cat /proc/cpuinfo        # CPU info
cat /proc/meminfo        # Memory info
cat /proc/cmdline        # Boot parameters (from U-Boot!)

# 4. Check running processes
ps aux
top
```

### Expected Outcome

You understand:
- Root filesystem layout
- Where configuration lives (`/etc`)
- How to check system information
- What processes are running

### Questions to Answer
1. What Linux distribution/version is running?
2. How much RAM is available?
3. What boot parameters were passed?
4. What is PID 1 (init system)?

### Verification Checklist
- [ ] Can identify kernel version
- [ ] Know mounted filesystems
- [ ] Found `/proc/cmdline` content

---

## Exercise 5: First Cross-Compilation

### Objective
Cross-compile a simple program and run it on target.

### Tasks

1. Install cross-compiler on host
2. Write simple "Hello World" program
3. Cross-compile for ARM
4. Transfer to target and run

### Step-by-Step Guide

**On Host (PC):**

```bash
# 1. Install cross-compiler
sudo apt-get install gcc-arm-linux-gnueabihf

# 2. Create hello.c
cat > hello.c << 'EOF'
#include <stdio.h>
int main() {
    printf("Hello from Embedded Linux!\n");
    printf("Running on ARM architecture.\n");
    return 0;
}
EOF

# 3. Cross-compile
arm-linux-gnueabihf-gcc -static -o hello hello.c

# 4. Verify it's ARM binary
file hello
# Should show: ELF 32-bit LSB executable, ARM, ...

# 5. Transfer to target
scp hello user@target:/tmp/
# OR copy to SD card, NFS, etc.
```

**On Target:**

```bash
# Run the program
chmod +x /tmp/hello
/tmp/hello
```

### Expected Outcome

```
Hello from Embedded Linux!
Running on ARM architecture.
```

### Troubleshooting Hints
- "not found" error? Missing libraries - use `-static` flag
- "cannot execute"? Wrong architecture - check `file` output
- Transfer failed? Try copying via SD card directly

---

## Exercise 6: LED Blinking (GPIO)

### Objective
Control an LED using GPIO from userspace.

### Tasks

1. Identify available GPIOs
2. Export a GPIO pin
3. Set direction to output
4. Toggle LED on/off

### Step-by-Step Guide

```bash
# On target:

# 1. Check available GPIOs
ls /sys/class/gpio/

# 2. Export GPIO (example: GPIO 17)
echo 17 > /sys/class/gpio/export

# 3. Set as output
echo out > /sys/class/gpio/gpio17/direction

# 4. Turn LED on
echo 1 > /sys/class/gpio/gpio17/value

# 5. Turn LED off
echo 0 > /sys/class/gpio/gpio17/value

# 6. Blink loop
while true; do
    echo 1 > /sys/class/gpio/gpio17/value
    sleep 0.5
    echo 0 > /sys/class/gpio/gpio17/value
    sleep 0.5
done
```

### Expected Outcome

LED blinks at 1Hz (0.5s on, 0.5s off).

### Board-Specific GPIO Numbers

| Board | On-board LED GPIO |
|-------|-------------------|
| Raspberry Pi | 47 (ACT LED) |
| BeagleBone Black | 53 (USR0) |
| Custom | Check schematic |

### Troubleshooting Hints
- "Permission denied"? Run as root or check permissions
- "Device busy"? GPIO used by kernel driver, try different pin
- No change? Check LED polarity and GPIO number

---

## Summary

After completing these exercises, you can:

- ✅ Connect to embedded boards via serial console
- ✅ Navigate U-Boot and modify boot parameters
- ✅ Explore embedded Linux file system
- ✅ Cross-compile and run programs on target
- ✅ Control GPIO from userspace

---

## Next Steps

Continue to [Intermediate Exercises](intermediate.md) for kernel building and device tree challenges.
