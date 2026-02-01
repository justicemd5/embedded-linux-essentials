# Makefile for BeagleBone Black hwinfo kernel module
#
# Cross-compilation settings for AM335x
# Adjust KERNEL_DIR to point to your kernel source

obj-m := hwinfo.o

# Path to your cross-compiled kernel source
KERNEL_DIR ?= $(HOME)/bbb/linux

# BeagleBone Black (AM335x Cortex-A8) settings
ARCH ?= arm
CROSS_COMPILE ?= arm-linux-gnueabihf-

# Compiler flags
ccflags-y := -Wall -Wextra

# Build targets
all: modules

modules:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
	rm -f *.o *.ko *.mod.c *.mod *.symvers *.order

# Install to target (adjust IP/path as needed)
install:
	scp hwinfo.ko debian@beaglebone:/tmp/

# Show module info
info:
	modinfo hwinfo.ko

# Generate compile_commands.json for IDE support
compile_commands:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) compile_commands.json

.PHONY: all modules clean install info compile_commands
