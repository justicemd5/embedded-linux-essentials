# Makefile for buggy kernel module (debugging practice)

obj-m := buggy.o

KERNEL_DIR ?= $(HOME)/bbb/linux
ARCH ?= arm
CROSS_COMPILE ?= arm-linux-gnueabihf-

# Build with debug info for better analysis
ccflags-y := -Wall -Wextra -g -DDEBUG

all: modules

modules:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
	rm -f *.o *.ko *.mod.c *.mod *.symvers *.order

install:
	scp buggy.ko debian@beaglebone:/tmp/

# Generate disassembly for crash analysis
disasm: modules
	$(CROSS_COMPILE)objdump -d buggy.ko > buggy.dis
	$(CROSS_COMPILE)objdump -S buggy.ko > buggy_annotated.dis
	$(CROSS_COMPILE)nm buggy.ko > buggy.symbols

.PHONY: all modules clean install disasm
