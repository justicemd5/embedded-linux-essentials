# Lab 04: Device Tree

A hands-on lab for understanding and customizing Device Tree for embedded Linux.

## Lab Objectives

By the end of this lab, you will be able to:

1. Understand Device Tree Source (DTS) syntax
2. Examine existing device trees for your board
3. Create device tree overlays
4. Add custom hardware to device tree
5. Debug device tree issues

## Prerequisites

- Completed [Lab 03: Linux Kernel](../03_kernel/README.md)
- Target board with serial console
- Basic understanding of hardware (GPIO, I2C, SPI)

## Lab Structure

```
04_device_tree/
├── README.md          ← This file
└── led_example.dts    ← Example LED device tree overlay
```

---

## Part 1: Understanding Device Tree

### What is Device Tree?

Device Tree is a data structure that describes hardware to the operating system. It eliminates the need to hardcode hardware details in the kernel.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DEVICE TREE CONCEPT                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Without Device Tree:                                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Kernel has hardcoded board information                              │   │
│  │ → Different kernel for each board variant                           │   │
│  │ → Must recompile kernel for any hardware change                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  With Device Tree:                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Kernel + DTB file                                                   │   │
│  │ → Same kernel for many boards                                       │   │
│  │ → Just change DTB to describe different hardware                    │   │
│  │ → Overlays can modify DTB at runtime                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  File types:                                                                │
│  .dts  → Device Tree Source (human-readable)                               │
│  .dtsi → Device Tree Source Include (shared fragments)                     │
│  .dtb  → Device Tree Blob (compiled binary)                                │
│  .dtbo → Device Tree Blob Overlay (compiled overlay)                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Device Tree Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DTS FILE HIERARCHY                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  bcm2711-rpi-4-b.dts         ← Board-specific DTS                          │
│         │                                                                   │
│         └─── #include "bcm2711.dtsi"    ← SoC-level description            │
│                    │                                                        │
│                    └─── #include "bcm2711-rpi.dtsi"  ← RPi variants        │
│                                │                                            │
│                                └─── #include "bcm283x.dtsi"  ← Common      │
│                                                                             │
│  This layering allows:                                                      │
│  • Common code shared between similar devices                               │
│  • Board-specific customizations at top level                              │
│  • Easy maintenance and updates                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: DTS Syntax

### Basic Structure

```dts
/dts-v1/;  // Version declaration

/ {  // Root node
    compatible = "raspberrypi,4-model-b", "brcm,bcm2711";
    model = "Raspberry Pi 4 Model B";
    
    // Properties
    #address-cells = <2>;  // 2 cells for address
    #size-cells = <1>;     // 1 cell for size
    
    // Child nodes
    memory@0 {
        device_type = "memory";
        reg = <0x0 0x0 0x40000000>;  // 1GB at address 0
    };
    
    cpus {
        #address-cells = <1>;
        #size-cells = <0>;
        
        cpu@0 {
            device_type = "cpu";
            compatible = "arm,cortex-a72";
            reg = <0>;
        };
    };
};
```

### Common Properties

| Property | Description | Example |
|----------|-------------|---------|
| `compatible` | Device identification | `"brcm,bcm2835-gpio"` |
| `reg` | Register addresses | `<0x7e200000 0x100>` |
| `interrupts` | Interrupt specification | `<GIC_SPI 113 IRQ_TYPE_LEVEL_HIGH>` |
| `clocks` | Clock references | `<&clk BCM2835_CLOCK_PWM>` |
| `status` | Enable/disable | `"okay"` or `"disabled"` |

### Phandles and References

```dts
// Define a label (creates phandle automatically)
gpio: gpio@7e200000 {
    compatible = "brcm,bcm2835-gpio";
    reg = <0x7e200000 0xb4>;
    gpio-controller;
    #gpio-cells = <2>;
};

// Reference using phandle
leds {
    compatible = "gpio-leds";
    
    led0 {
        gpios = <&gpio 17 GPIO_ACTIVE_HIGH>;  // Reference gpio node
        label = "status";
    };
};
```

---

## Part 3: Examining Existing Device Trees

### Find Your Board's DTS

```bash
# In kernel source
ls arch/arm/boot/dts/broadcom/*.dts    # Raspberry Pi
ls arch/arm/boot/dts/ti/omap/*.dts     # BeagleBone

# View compiled DTB
dtc -I dtb -O dts -o readable.dts /boot/bcm2711-rpi-4-b.dtb
```

### Explore DTB at Runtime

```bash
# On running system, device tree is exposed via sysfs
ls /proc/device-tree/
cat /proc/device-tree/model

# Or via sys
ls /sys/firmware/devicetree/base/

# View specific node
ls /proc/device-tree/soc/gpio@7e200000/
cat /proc/device-tree/soc/gpio@7e200000/compatible
```

### Using dtc (Device Tree Compiler)

```bash
# Compile DTS to DTB
dtc -I dts -O dtb -o output.dtb input.dts

# Decompile DTB to DTS
dtc -I dtb -O dts -o output.dts input.dtb

# Check for errors
dtc -I dts -O dtb input.dts 2>&1 | head
```

---

## Part 4: Creating Device Tree Overlays

Overlays allow modifying the device tree at boot time without rebuilding.

### Overlay Structure

```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";  // Target compatibility
    
    fragment@0 {
        target-path = "/";  // Target node
        __overlay__ {
            // Content to add/modify
        };
    };
    
    fragment@1 {
        target = <&gpio>;   // Target by phandle
        __overlay__ {
            // Modifications to gpio node
        };
    };
};
```

### Example: LED Overlay

See [led_example.dts](led_example.dts) for a complete example.

```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target-path = "/";
        __overlay__ {
            my_leds {
                compatible = "gpio-leds";
                
                my_led {
                    gpios = <&gpio 17 0>;
                    label = "my_status_led";
                    linux,default-trigger = "heartbeat";
                };
            };
        };
    };
};
```

### Compile and Apply Overlay

```bash
# Compile overlay
dtc -I dts -O dtb -o my_overlay.dtbo my_overlay.dts

# On Raspberry Pi, copy to overlays directory
sudo cp my_overlay.dtbo /boot/overlays/

# Enable in config.txt
echo "dtoverlay=my_overlay" | sudo tee -a /boot/config.txt

# Reboot to apply
sudo reboot
```

### Runtime Overlay Loading

```bash
# Check if configfs is available
ls /sys/kernel/config/device-tree/overlays/

# Load overlay at runtime
sudo mkdir /sys/kernel/config/device-tree/overlays/my_overlay
cat my_overlay.dtbo | sudo tee /sys/kernel/config/device-tree/overlays/my_overlay/dtbo > /dev/null

# Check if applied
cat /sys/kernel/config/device-tree/overlays/my_overlay/status
```

---

## Part 5: Practical Examples

### Example 1: Enable I2C Device

```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target = <&i2c1>;
        __overlay__ {
            status = "okay";
            #address-cells = <1>;
            #size-cells = <0>;
            
            // Add an I2C temperature sensor
            temperature_sensor@48 {
                compatible = "ti,tmp102";
                reg = <0x48>;
            };
        };
    };
};
```

### Example 2: Enable SPI Device

```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target = <&spi0>;
        __overlay__ {
            status = "okay";
            #address-cells = <1>;
            #size-cells = <0>;
            
            // Add SPI flash
            spiflash@0 {
                compatible = "jedec,spi-nor";
                reg = <0>;  // CS0
                spi-max-frequency = <10000000>;
            };
        };
    };
};
```

### Example 3: Configure GPIO Pin Function

```dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2711";
    
    fragment@0 {
        target = <&gpio>;
        __overlay__ {
            my_pins: my_pins {
                brcm,pins = <17 27>;
                brcm,function = <1>;  // Output
                brcm,pull = <0>;      // No pull
            };
        };
    };
};
```

---

## Part 6: Debugging Device Tree

### Verify Device Tree Contents

```bash
# View device tree at runtime
cat /proc/device-tree/model

# Check specific node exists
ls /proc/device-tree/soc/i2c@7e804000/

# View property value
xxd /proc/device-tree/soc/i2c@7e804000/compatible
cat /proc/device-tree/soc/i2c@7e804000/status
```

### Check Driver Binding

```bash
# List devices by compatible string
grep -r "gpio-leds" /sys/devices/

# Check if driver bound
ls -la /sys/bus/platform/drivers/leds-gpio/

# View device properties
cat /sys/class/leds/my_status_led/trigger
```

### Common Issues

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DEVICE TREE DEBUGGING                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Issue: Device not appearing                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Check status = "okay" in DTB                                     │   │
│  │ 2. Verify compatible string matches driver                          │   │
│  │ 3. Check kernel has driver enabled                                  │   │
│  │ 4. Look for errors in dmesg: dmesg | grep -i "error\|fail"         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Issue: Overlay not applying                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Check compatible string matches base DTB                         │   │
│  │ 2. Verify target node exists in base DTB                           │   │
│  │ 3. Check overlay compiled without errors                            │   │
│  │ 4. Look in /boot/overlays/ or /sys/kernel/config/device-tree/      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Issue: Wrong pin configuration                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Check pinctrl nodes                                              │   │
│  │ 2. Verify GPIO numbers (chip-relative vs global)                    │   │
│  │ 3. Check for conflicting overlays                                   │   │
│  │ 4. Use gpioinfo tool to see current configuration                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Using of_dump_addr (Kernel Debug)

```bash
# Enable debug in kernel
# Device Drivers -> Device Tree and Open Firmware support -> Debug

# Add to bootargs
of_debug
```

---

## Lab Exercises

### Exercise 1: Explore Base DTB

1. Decompile your board's DTB
2. Find the GPIO controller node
3. Find an I2C controller node
4. Identify the memory description

### Exercise 2: Create LED Overlay

1. Use [led_example.dts](led_example.dts) as template
2. Modify GPIO pin for your board
3. Compile and deploy
4. Verify LED appears in /sys/class/leds/

### Exercise 3: Enable I2C Device

1. Connect an I2C device (or simulate)
2. Create overlay to enable I2C controller
3. Add device node with correct address
4. Verify device appears after applying overlay

### Exercise 4: Debug Missing Device

1. Intentionally break an overlay (wrong compatible)
2. Apply and observe failure
3. Use debugging techniques to find the issue
4. Fix and verify

---

## What You Learned

After completing this lab:

1. ✅ Device Tree purpose and structure
2. ✅ DTS syntax and common properties
3. ✅ How to examine existing device trees
4. ✅ Creating and applying overlays
5. ✅ Debugging device tree issues

---

## Next Lab

Continue to [Lab 05: Initramfs](../05_initramfs/README.md) to create initial RAM filesystems.
