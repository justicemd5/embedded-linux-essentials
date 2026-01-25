# Device Tree Guide

A comprehensive guide to understanding and using Device Trees in Embedded Linux systems.

## Why Device Tree Matters

Device Tree is the standard way to describe hardware to the Linux kernel on ARM and other architectures. Understanding Device Tree is essential because:

- **Hardware Description**: DT tells the kernel what hardware exists and how to access it
- **Platform Independence**: Same kernel binary can boot on different boards
- **Customization**: Modify hardware configuration without recompiling kernel
- **Industry Standard**: Required knowledge for embedded Linux development
- **Debugging**: Understanding DT helps diagnose driver issues

## What is Device Tree?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       DEVICE TREE OVERVIEW                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Device Tree is a data structure describing hardware to the OS:             │
│                                                                             │
│  ┌──────────────────────┐                                                   │
│  │  .dts (Source)       │  Human-readable, hierarchical                     │
│  │  Device Tree Source  │                                                   │
│  └──────────┬───────────┘                                                   │
│             │ dtc (compile)                                                 │
│             v                                                               │
│  ┌──────────────────────┐                                                   │
│  │  .dtb (Binary)       │  Binary blob passed to kernel                     │
│  │  Device Tree Blob    │                                                   │
│  └──────────┬───────────┘                                                   │
│             │ U-Boot loads                                                  │
│             v                                                               │
│  ┌──────────────────────┐                                                   │
│  │  Linux Kernel        │  Parses DTB, matches drivers,                     │
│  │  (of_* functions)    │  configures hardware                              │
│  └──────────────────────┘                                                   │
│                                                                             │
│  Key Benefits:                                                              │
│  • No need to recompile kernel for hardware changes                         │
│  • Multiple boards supported by single kernel                               │
│  • Clean separation of code and hardware description                        │
│  • Runtime hardware discovery (like ACPI/PCI but for embedded)             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Device Tree File Types

| Extension | Name | Purpose |
|-----------|------|---------|
| `.dts` | Device Tree Source | Main board description file |
| `.dtsi` | Device Tree Source Include | Shared/reusable definitions |
| `.dtb` | Device Tree Blob | Compiled binary |
| `.dtbo` | Device Tree Blob Overlay | Runtime modifications |

## Device Tree Syntax

### Basic Structure

```dts
/dts-v1/;  // Version declaration (required)

/ {        // Root node (required, exactly one)
    // Properties of root node
    model = "My Custom Board";
    compatible = "mycompany,myboard", "generic-soc";
    #address-cells = <1>;  // Address uses 1 32-bit cell
    #size-cells = <1>;     // Size uses 1 32-bit cell
    
    // Child nodes
    memory@80000000 {      // Memory node
        device_type = "memory";
        reg = <0x80000000 0x20000000>;  // 512MB at 0x80000000
    };
    
    cpus {                 // CPUs container
        #address-cells = <1>;
        #size-cells = <0>;
        
        cpu@0 {
            device_type = "cpu";
            compatible = "arm,cortex-a53";
            reg = <0>;
        };
    };
    
    soc {                  // System-on-Chip peripherals
        compatible = "simple-bus";
        #address-cells = <1>;
        #size-cells = <1>;
        ranges;            // 1:1 address mapping
        
        uart0: serial@101f1000 {
            compatible = "arm,pl011", "arm,primecell";
            reg = <0x101f1000 0x1000>;
            interrupts = <12>;
        };
    };
};
```

### Property Types

```dts
/ {
    // String property
    model = "Raspberry Pi 3 Model B";
    
    // String list property
    compatible = "raspberrypi,3-model-b", "brcm,bcm2837";
    
    // 32-bit integer (cell)
    clock-frequency = <100000000>;  // 100 MHz
    
    // 32-bit integer array
    reg = <0x7e200000 0x1000>;  // base address, size
    
    // 64-bit value (2 cells)
    reg = <0x0 0x3f200000 0x0 0x1000>;  // high, low, high, low
    
    // Boolean (presence = true)
    little-endian;         // Property exists = true
    // big-endian;         // Commented out = false
    
    // Phandle reference
    clocks = <&clk_uart>;  // Reference to another node
    
    // Byte array
    mac-address = [00 11 22 33 44 55];
    
    // Mixed (cells and strings)
    compatible = "vendor,device";
};
```

### Node Naming Convention

```
<name>[@<unit-address>]

name          - Descriptive name (letters, digits, ,._+-)
@unit-address - Required if node has 'reg' property
                Usually matches first address in 'reg'

Examples:
  memory@80000000       // Memory at address 0x80000000
  serial@101f1000       // Serial port at 0x101f1000
  gpio-keys             // No reg, no unit-address
  cpu@0                 // CPU core 0
  ethernet@0,0          // Device at chip-select 0, offset 0
```

### Labels and Phandles

```dts
/ {
    // Label definition
    clk_osc: oscillator {
        compatible = "fixed-clock";
        #clock-cells = <0>;
        clock-frequency = <24000000>;
    };
    
    uart0: serial@101f1000 {
        compatible = "arm,pl011";
        reg = <0x101f1000 0x1000>;
        // Phandle reference using label
        clocks = <&clk_osc>;
    };
    
    aliases {
        // Aliases provide stable names
        serial0 = &uart0;
    };
};
```

## Standard Nodes and Properties

### Root Node Properties

```dts
/ {
    // Required
    compatible = "vendor,board", "vendor,soc";  // Board identification
    
    // Recommended
    model = "Human readable board name";        // Display name
    #address-cells = <1>;  // Child reg address cells
    #size-cells = <1>;     // Child reg size cells
    
    // Optional
    serial-number = "12345";
    chassis-type = "embedded";  // handset, watch, embedded, etc.
};
```

### Memory Node

```dts
memory@80000000 {
    device_type = "memory";  // Required, must be "memory"
    reg = <0x80000000 0x40000000>;  // 1GB at 0x80000000
};

// Multiple memory regions
memory@80000000 {
    device_type = "memory";
    reg = <0x80000000 0x20000000>,  // 512MB at 0x80000000
          <0xC0000000 0x20000000>;  // 512MB at 0xC0000000
};
```

### Chosen Node (Bootloader/Kernel Interface)

```dts
chosen {
    // Kernel command line (can be set by U-Boot)
    bootargs = "console=ttyS0,115200 root=/dev/mmcblk0p2 rw";
    
    // stdout device for early console
    stdout-path = "serial0:115200n8";
    // Or: stdout-path = &uart0;
    
    // initrd location (set by bootloader)
    linux,initrd-start = <0x82000000>;
    linux,initrd-end = <0x82800000>;
};
```

### CPU Nodes

```dts
cpus {
    #address-cells = <1>;
    #size-cells = <0>;
    
    cpu0: cpu@0 {
        device_type = "cpu";
        compatible = "arm,cortex-a53";
        reg = <0>;
        enable-method = "psci";
        clock-frequency = <1200000000>;  // 1.2 GHz
    };
    
    cpu1: cpu@1 {
        device_type = "cpu";
        compatible = "arm,cortex-a53";
        reg = <1>;
        enable-method = "psci";
    };
};
```

## GPIO and Pin Control

### GPIO Controller

```dts
gpio: gpio@7e200000 {
    compatible = "brcm,bcm2835-gpio";
    reg = <0x7e200000 0xb4>;
    interrupts = <2 17>, <2 18>;
    
    // GPIO controller properties
    gpio-controller;        // Marks as GPIO controller
    #gpio-cells = <2>;      // gpio-specifier: <pin flags>
    
    // Interrupt controller
    interrupt-controller;
    #interrupt-cells = <2>;
};
```

### GPIO Consumer (User)

```dts
// LED using GPIO
leds {
    compatible = "gpio-leds";
    
    led0 {
        label = "led0";
        // GPIO specifier: <&controller pin flags>
        gpios = <&gpio 47 GPIO_ACTIVE_HIGH>;
        // Alternative: gpios = <&gpio 47 0>;
        linux,default-trigger = "heartbeat";
    };
    
    led1 {
        label = "led1";
        gpios = <&gpio 17 GPIO_ACTIVE_LOW>;
        default-state = "on";
    };
};

// GPIO key/button
gpio-keys {
    compatible = "gpio-keys";
    
    power-button {
        label = "Power Button";
        gpios = <&gpio 3 GPIO_ACTIVE_LOW>;
        linux,code = <KEY_POWER>;  // From input-event-codes.h
        wakeup-source;
    };
};
```

### GPIO Flags (Common Values)

| Flag | Value | Meaning |
|------|-------|---------|
| GPIO_ACTIVE_HIGH | 0 | Active high (1 = on) |
| GPIO_ACTIVE_LOW | 1 | Active low (0 = on) |
| GPIO_OPEN_DRAIN | 4 | Open drain output |
| GPIO_OPEN_SOURCE | 8 | Open source output |
| GPIO_PULL_UP | 16 | Enable pull-up |
| GPIO_PULL_DOWN | 32 | Enable pull-down |

## Complete GPIO LED Example

```dts
/* File: my-board.dts */
/dts-v1/;

#include <dt-bindings/gpio/gpio.h>

/ {
    compatible = "mycompany,myboard";
    model = "My Custom Board with LEDs";
    
    /* System LEDs */
    leds {
        compatible = "gpio-leds";
        pinctrl-names = "default";
        pinctrl-0 = <&led_pins>;
        
        /* Status LED - Active High */
        status_led: led-status {
            label = "status";
            gpios = <&gpio 17 GPIO_ACTIVE_HIGH>;
            linux,default-trigger = "heartbeat";
        };
        
        /* Power LED - Active Low */
        power_led: led-power {
            label = "power";
            gpios = <&gpio 27 GPIO_ACTIVE_LOW>;
            default-state = "on";
        };
        
        /* Activity LED - Active High */
        act_led: led-activity {
            label = "activity";
            gpios = <&gpio 22 GPIO_ACTIVE_HIGH>;
            linux,default-trigger = "mmc0";
        };
    };
};

/* GPIO controller (typically in SoC dtsi) */
&gpio {
    led_pins: led-pins {
        pins = "gpio17", "gpio27", "gpio22";
        function = "gpio";
        output-low;
    };
};
```

## Device Tree Overlays

### What are Overlays?

Overlays allow runtime modification of the device tree without replacing the base DTB. Used for:
- Adding HATs/shields
- Enabling optional hardware
- Configuring pins dynamically

### Overlay Syntax

```dts
/* led-overlay.dts */
/dts-v1/;
/plugin/;  // Marks this as an overlay

/ {
    compatible = "brcm,bcm2835";  // Must match base DT
    
    fragment@0 {
        target-path = "/";  // Or: target = <&some_label>;
        __overlay__ {
            my_leds: my-leds {
                compatible = "gpio-leds";
                
                new-led {
                    label = "new-led";
                    gpios = <&gpio 18 0>;
                };
            };
        };
    };
    
    fragment@1 {
        target = <&gpio>;
        __overlay__ {
            new_led_pins: new-led-pins {
                brcm,pins = <18>;
                brcm,function = <1>;  // Output
            };
        };
    };
};
```

### Compiling and Applying Overlays

```bash
# Compile overlay
dtc -@ -I dts -O dtb -o led-overlay.dtbo led-overlay.dts

# On Raspberry Pi (config.txt):
dtoverlay=led-overlay

# Or at runtime (if supported):
dtoverlay led-overlay

# Check applied overlays:
dtc -I fs /proc/device-tree
```

## Validating Device Trees

### Compile-Time Validation

```bash
# Compile and check for errors
dtc -I dts -O dtb -o board.dtb board.dts 2>&1

# Common errors:
# Warning: property name 'xxx' is invalid
# Error: undefined label 'xxx'
# Warning: node 'xxx' has a unit name, but no reg property
```

### Runtime Validation via sysfs

```bash
# View device tree structure
ls /proc/device-tree/
ls /sys/firmware/devicetree/base/

# Read properties
cat /proc/device-tree/model
hexdump -C /proc/device-tree/memory@0/reg

# Check if node exists
ls /proc/device-tree/soc/gpio@7e200000/

# Using dtc to decompile running DT
dtc -I fs -O dts /proc/device-tree/ > extracted.dts
```

### Checking Driver Binding

```bash
# List devices and their drivers
ls /sys/bus/platform/devices/
ls /sys/bus/platform/drivers/

# Check specific device
cat /sys/bus/platform/devices/fe200000.gpio/uevent
# Output: DRIVER=pinctrl-bcm2835

# Check compatible string matching
cat /sys/bus/platform/devices/*/of_node/compatible

# GPIO controller info
cat /sys/class/gpio/gpiochip*/label
cat /sys/class/gpio/gpiochip*/base
cat /sys/class/gpio/gpiochip*/ngpio
```

## Controlling LEDs via sysfs

```bash
# List LED devices
ls /sys/class/leds/

# Control LED
echo 1 > /sys/class/leds/status/brightness    # Turn on
echo 0 > /sys/class/leds/status/brightness    # Turn off

# Read current state
cat /sys/class/leds/status/brightness

# List available triggers
cat /sys/class/leds/status/trigger
# [none] rc-feedback kbd-scrolllock ... heartbeat mmc0 mmc1

# Set trigger
echo heartbeat > /sys/class/leds/status/trigger
echo mmc0 > /sys/class/leds/activity/trigger
echo none > /sys/class/leds/power/trigger
```

## Common Mistakes and Debugging

### Mistake 1: Missing #address-cells / #size-cells

```dts
// WRONG: reg property won't parse correctly
soc {
    uart@101f1000 {
        reg = <0x101f1000 0x1000>;  // Error: cells not defined!
    };
};

// CORRECT: Define cells in parent
soc {
    #address-cells = <1>;
    #size-cells = <1>;
    ranges;
    
    uart@101f1000 {
        reg = <0x101f1000 0x1000>;
    };
};
```

### Mistake 2: Wrong Compatible String

```dts
// WRONG: Driver won't match
uart@101f1000 {
    compatible = "my-uart";  // No driver has this!
};

// CORRECT: Use documented compatible string
uart@101f1000 {
    compatible = "arm,pl011", "arm,primecell";
};

// Check kernel Documentation/devicetree/bindings/ for valid strings
```

### Mistake 3: Forgetting status = "okay"

```dts
// Devices are often disabled in SoC dtsi
// WRONG: Device stays disabled
&uart0 {
    // No status override
};

// CORRECT: Enable the device
&uart0 {
    status = "okay";
};
```

### Debugging Tips

```bash
# Check kernel boot log for DT parsing
dmesg | grep -i "device.tree\|of:\|dtb"

# Check for driver match issues
dmesg | grep -i "no matching driver"

# Verbose boot (add to bootargs)
# earlycon loglevel=8

# Dump device tree from running system
cat /sys/firmware/fdt > /tmp/running.dtb
dtc -I dtb -O dts /tmp/running.dtb > /tmp/running.dts
```

## What You Learned

After reading this document, you understand:

1. ✅ What Device Tree is and why it's needed
2. ✅ DTS/DTB/DTBO file types and their purposes
3. ✅ Device Tree syntax (nodes, properties, labels, phandles)
4. ✅ Standard nodes (memory, chosen, cpus)
5. ✅ GPIO controllers and consumers
6. ✅ How to describe LEDs in device tree
7. ✅ How to create and apply overlays
8. ✅ How to validate and debug device trees
9. ✅ How to control devices via sysfs

---

## Next Steps

1. Complete [Lab 04: Device Tree](../04_device_tree/README.md)
2. Try the [LED Example](../04_device_tree/led_example.dts)
3. Practice modifying device tree for your board
