# Makefile for BeagleBone Black chardev kernel module

obj-m := chardev.o

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
	rm -f *.o *.ko *.mod.c *.mod *.symvers *.order

install:
	scp chardev.ko debian@beaglebone:/tmp/

.PHONY: all modules clean install
