# UART Debugging Guide

Comprehensive guide to debugging embedded Linux systems via UART/serial console.

## Overview

This guide covers:
1. Serial console hardware setup
2. Terminal emulator configuration
3. Boot message analysis
4. Interactive debugging techniques
5. Advanced UART troubleshooting

---

## Part 1: Hardware Setup

### Common Serial Adapters

| Adapter Type | Voltage | Best For |
|--------------|---------|----------|
| FTDI FT232R | 3.3V/5V | General purpose, reliable |
| CP2102 | 3.3V | Budget option, common |
| CH340/CH341 | 3.3V/5V | Very cheap, varies in quality |
| PL2303 | 3.3V | Older, driver issues on some OS |
| Raspberry Pi | 3.3V | Built-in USB-UART on Pi Zero/4 |

### Wiring

```
┌─────────────────────────────────────────────────────────────────┐
│                     UART WIRING DIAGRAM                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    Host PC                              Target Board            │
│    ┌─────────┐                          ┌─────────┐             │
│    │ USB-TTL │                          │  UART   │             │
│    │ Adapter │                          │ Header  │             │
│    │         │                          │         │             │
│    │   TX ───┼──────────────────────────┼─► RX    │             │
│    │   RX ◄──┼──────────────────────────┼── TX    │             │
│    │  GND ───┼──────────────────────────┼── GND   │             │
│    │         │                          │         │             │
│    │ (3.3V)  │  DO NOT CONNECT UNLESS   │ (VCC)   │             │
│    │         │  YOU KNOW WHAT YOU'RE    │         │             │
│    │         │  DOING!                  │         │             │
│    └─────────┘                          └─────────┘             │
│                                                                 │
│    KEY: TX and RX are CROSSED (TX→RX, RX→TX)                    │
│         GND must ALWAYS be connected                            │
│         VCC usually NOT connected (target has own power)        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Board-Specific Pinouts

**Raspberry Pi (GPIO Header):**
```
Pin 6  = GND
Pin 8  = TX (GPIO14)
Pin 10 = RX (GPIO15)
```

**BeagleBone Black (J1 Header):**
```
Pin 1 = GND
Pin 4 = RX
Pin 5 = TX
```

**Generic i.MX/STM32 (usually marked on board):**
```
Look for "UART1" or "DEBUG" header
Typical: GND, TX, RX, (sometimes VCC)
```

---

## Part 2: Terminal Emulator Setup

### Linux: screen

```bash
# Install
sudo apt-get install screen

# Connect (common baud: 115200)
screen /dev/ttyUSB0 115200

# Exit: Ctrl-A, then K, then Y
# or: Ctrl-A, then :quit
```

### Linux: minicom

```bash
# Install
sudo apt-get install minicom

# Configure
sudo minicom -s
# Select "Serial port setup"
# Set: Device: /dev/ttyUSB0
# Set: Baud: 115200 8N1
# Set: Flow Control: None (IMPORTANT!)
# Save as default

# Connect
minicom
# Exit: Ctrl-A, X
```

### Linux: picocom (Recommended)

```bash
# Install
sudo apt-get install picocom

# Connect
picocom -b 115200 /dev/ttyUSB0

# Exit: Ctrl-A, Ctrl-X
```

### Permission Setup

```bash
# Add user to dialout group
sudo usermod -a -G dialout $USER

# Apply (log out and back in, or):
newgrp dialout

# Verify
groups | grep dialout
```

### Common Baud Rates

| Baud Rate | Usage |
|-----------|-------|
| 9600 | Legacy, some microcontrollers |
| 38400 | Some older systems |
| 115200 | **Most common for embedded Linux** |
| 230400 | High-speed option |
| 921600 | Very high-speed, requires good cable |
| 1500000 | Some modern SoCs (RPi option) |

---

## Part 3: Boot Message Analysis

### Typical Boot Sequence

```
1. ──────────────────────────────────────────────────────────────────
   U-Boot SPL 2024.01 (Jan 15 2024 - 10:30:00 +0000)
   ◄── SPL/TPL first-stage bootloader

2. ──────────────────────────────────────────────────────────────────
   U-Boot 2024.01 (Jan 15 2024 - 10:30:00 +0000)
   DRAM:  1 GiB
   ◄── Full U-Boot running, hardware init

3. ──────────────────────────────────────────────────────────────────
   Hit any key to stop autoboot: 3
   ◄── Interrupt opportunity!

4. ──────────────────────────────────────────────────────────────────
   Loading Environment from MMC...
   ◄── Environment loaded

5. ──────────────────────────────────────────────────────────────────
   reading zImage
   5000000 bytes read in 500 ms
   ◄── Kernel loading

6. ──────────────────────────────────────────────────────────────────
   Starting kernel ...
   ◄── Jumping to kernel (last U-Boot message)

7. ──────────────────────────────────────────────────────────────────
   [    0.000000] Booting Linux on physical CPU 0x0
   ◄── Kernel decompression and early boot

8. ──────────────────────────────────────────────────────────────────
   [    1.234567] VFS: Mounted root (ext4 filesystem) readonly
   ◄── Root filesystem mounted

9. ──────────────────────────────────────────────────────────────────
   Starting syslogd: OK
   Starting init scripts...
   ◄── Userspace initialization
```

### Key Messages to Watch

```bash
# Memory detection
DRAM:  1 GiB        # Good
DRAM:  0 Bytes      # Bad - RAM not detected

# Storage detection
MMC:   sdhci: 0     # Good - SD card found
No MMC device       # Bad - SD card not detected

# Kernel loading
reading zImage
5000000 bytes read  # Good
** Unable to read file zImage **  # Bad - kernel not found

# Kernel start
Starting kernel ... # Last U-Boot message
[    0.000000] Booting Linux  # First kernel message

# Kernel panic
Kernel panic - not syncing: VFS: Unable to mount root fs
# Root filesystem problem

# Successful boot
[    5.123456] Run /sbin/init as init process  # Init starting
```

---

## Part 4: Interactive Debugging

### U-Boot Command Line

```bash
# Get to prompt (press key during "Hit any key...")
Hit any key to stop autoboot: 3
=>

# Essential commands
=> help              # List all commands
=> printenv          # Show environment variables
=> mmc info          # Check SD card
=> bdinfo            # Board information
=> md 0x80000000 100 # Memory dump (hex)
```

### Kernel Command Line Debugging

Add these to bootargs for more verbosity:

```bash
# Maximum kernel verbosity
=> setenv bootargs ${bootargs} loglevel=8 debug

# Ignore kernel loglevel settings
=> setenv bootargs ${bootargs} ignore_loglevel

# Early printk (very early messages)
=> setenv bootargs ${bootargs} earlyprintk

# Init debugging
=> setenv bootargs ${bootargs} init=/bin/sh  # Drop to shell

# initramfs debugging
=> setenv bootargs ${bootargs} rdinit=/bin/sh
```

### Kernel Interactive Debug

```bash
# Boot to shell instead of init
=> setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 init=/bin/sh

# Once booted, you get a root shell
# Check mounts
mount
# Check dmesg
dmesg | tail -50
# Try mounting manually
mount -o remount,rw /
# Start normal init when ready
exec /sbin/init
```

---

## Part 5: Common Issues

### No Output At All

```
┌──────────────────────────────────────────────────────────────────┐
│ CHECKLIST: No Serial Output                                      │
├──────────────────────────────────────────────────────────────────┤
│ □ Is board powered? (Check LEDs, power consumption)              │
│ □ Is serial adapter connected to correct port?                   │
│ □ Are TX/RX swapped? (Try swapping them)                         │
│ □ Is GND connected?                                              │
│ □ Is baud rate correct? (Try 115200, 9600, 57600)                │
│ □ Is hardware flow control DISABLED in terminal?                 │
│ □ Is serial adapter recognized? (ls /dev/ttyUSB*)                │
│ □ Is correct /dev device used?                                   │
│ □ Is voltage compatible? (3.3V vs 5V)                            │
│ □ Is another program using the port?                             │
└──────────────────────────────────────────────────────────────────┘
```

### Garbage Characters

```bash
# Usually wrong baud rate
# Common rates to try:
picocom -b 9600 /dev/ttyUSB0
picocom -b 115200 /dev/ttyUSB0
picocom -b 57600 /dev/ttyUSB0

# Or wrong parity/data bits (try 8N1):
picocom -b 115200 -d 8 -p n -f n /dev/ttyUSB0
```

### Output Stops After "Starting kernel..."

```bash
# Kernel not finding console device
# Check bootargs console parameter:
=> printenv bootargs
# Should include: console=ttyS0,115200 or console=ttyAMA0,115200

# Platform-specific consoles:
# Raspberry Pi: console=serial0,115200 or console=ttyAMA0,115200
# BeagleBone:   console=ttyO0,115200n8
# i.MX:         console=ttymxc0,115200
# STM32MP:      console=ttySTM0,115200
```

### Output Stops After Kernel, Before Init

```bash
# Kernel panic - can't mount root
# Check bootargs root= parameter
=> printenv bootargs
# Should have: root=/dev/mmcblk0p2 rootwait

# Missing rootwait causes premature mount attempt
=> setenv bootargs ${bootargs} rootwait

# Wrong root device - check device exists
# In kernel messages look for:
#   mmc0: new high speed SDHC card
#   mmcblk0: p1 p2
```

---

## Part 6: Advanced Techniques

### Logging Serial Output

```bash
# With picocom, log to file:
picocom -b 115200 /dev/ttyUSB0 | tee boot_log.txt

# With screen:
screen -L /dev/ttyUSB0 115200
# Creates screenlog.0

# With minicom:
minicom -C capture.txt
```

### Sending Files via UART (XMODEM)

```bash
# From U-Boot, receive file:
=> loadx ${loadaddr}
# Then in minicom: Ctrl-A, S, select xmodem, choose file

# Or with sx command:
picocom -b 115200 /dev/ttyUSB0 --send-cmd "sx -k"
# Then: Ctrl-A, Ctrl-S, enter filename
```

### Magic SysRq Keys

When system is hung but kernel is running:

```bash
# Enable (if not already)
echo 1 > /proc/sys/kernel/sysrq

# From serial console, send: Alt+SysRq+<key>
# Or: echo <key> > /proc/sysrq-trigger

# Useful keys:
# b - reboot
# s - sync filesystems
# u - remount readonly
# o - power off

# Safe reboot sequence: "REISUB"
# R - keyboard raw mode
# E - terminate all
# I - kill all
# S - sync
# U - remount ro
# B - reboot
```

### Kernel Early Debug

For debugging before console is available:

```bash
# Raspberry Pi: Mini-UART early output
=> setenv bootargs ${bootargs} earlycon=pl011,0x3f201000

# Generic ARM: earlycon
=> setenv bootargs ${bootargs} earlycon

# With specific driver:
=> setenv bootargs ${bootargs} earlycon=uart8250,mmio32,0x44e09000
```

---

## Part 7: Creating Debug Boot Mode

### U-Boot Debug Environment

```bash
# Create debug boot option
=> setenv debug_args 'loglevel=8 debug ignore_loglevel'
=> setenv debug_boot 'setenv bootargs ${bootargs} ${debug_args}; run normal_boot'

# Use when needed:
=> run debug_boot
```

### Hardware Debug Button

```bash
# In U-Boot, check GPIO to enter debug mode
=> setenv check_debug 'gpio input 17; if test $? -eq 0; then run debug_boot; else run normal_boot; fi'
=> setenv bootcmd 'run check_debug'
=> saveenv

# Now holding GPIO17 low during boot enters debug mode
```

---

## Quick Reference

### Terminal Commands

```bash
# Quick connect with picocom
picocom -b 115200 /dev/ttyUSB0

# Connect and log
picocom -b 115200 /dev/ttyUSB0 | tee log.txt

# Check for serial devices
ls /dev/ttyUSB* /dev/ttyACM*

# Kill stuck serial session
pkill -9 screen
pkill -9 picocom
```

### Essential bootargs for Debugging

```bash
# Maximum verbosity
console=ttyS0,115200 loglevel=8 debug ignore_loglevel

# Drop to shell
console=ttyS0,115200 init=/bin/sh

# Early console
console=ttyS0,115200 earlycon
```

### Finding Console Device Name

| Platform | Console Device |
|----------|---------------|
| Raspberry Pi 3/4 | ttyS1 or ttyAMA0 |
| BeagleBone Black | ttyO0 |
| i.MX6 | ttymxc0 |
| STM32MP1 | ttySTM0 |
| Generic 8250 | ttyS0 |
| USB-Serial | ttyUSB0 or ttyACM0 |
