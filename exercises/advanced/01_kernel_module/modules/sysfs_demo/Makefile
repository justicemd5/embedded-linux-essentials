# Makefile for BeagleBone Black sysfs_demo kernel module

obj-m := sysfs_demo.o

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
	scp sysfs_demo.ko debian@beaglebone:/tmp/

.PHONY: all modules clean install
