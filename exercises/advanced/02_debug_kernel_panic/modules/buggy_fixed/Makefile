# Makefile for fixed buggy module

obj-m := buggy_fixed.o

KERNEL_DIR ?= $(HOME)/bbb/linux
ARCH ?= arm
CROSS_COMPILE ?= arm-linux-gnueabihf-

ccflags-y := -Wall -Wextra

all: modules

modules:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) ARCH=$(ARCH) \
		CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean

install:
	scp buggy_fixed.ko debian@beaglebone:/tmp/

.PHONY: all modules clean install
