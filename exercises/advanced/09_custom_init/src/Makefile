# Makefile for Custom Init System
#
# Build a minimal init for BeagleBone Black
#
# Author: Embedded Linux Labs
# License: MIT

# Cross-compiler for ARM
CROSS_COMPILE ?= arm-linux-gnueabihf-
CC = $(CROSS_COMPILE)gcc
STRIP = $(CROSS_COMPILE)strip

# Build options - static linking for minimal dependencies
CFLAGS = -Wall -Wextra -Werror -O2 -static
LDFLAGS = -static

# Source files
SRCS = init.c
OBJS = $(SRCS:.c=.o)
TARGET = init

# Destination for install
DESTDIR ?=
PREFIX ?= /sbin

# Targets
.PHONY: all clean install native debug help

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^
	$(STRIP) $@
	@echo ""
	@echo "Build complete:"
	@ls -la $@
	@file $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Build native (for testing on x86)
native:
	gcc -Wall -Wextra -O2 -o init.native init.c
	@echo "Built native binary for testing"

# Debug build (no optimization, with symbols)
debug: CFLAGS = -Wall -Wextra -O0 -g -static
debug: LDFLAGS = -static
debug: clean $(TARGET)
	@echo "Debug build complete (not stripped)"

# Install to rootfs
install: $(TARGET)
	install -d $(DESTDIR)$(PREFIX)
	install -m 0755 $(TARGET) $(DESTDIR)$(PREFIX)/init
	@echo "Installed to $(DESTDIR)$(PREFIX)/init"

# Clean
clean:
	rm -f $(TARGET) $(OBJS) init.native

# Show help
help:
	@echo "Custom Init Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build init for ARM (default)"
	@echo "  native  - Build for host system (testing)"
	@echo "  debug   - Build with debug symbols"
	@echo "  install - Install to DESTDIR"
	@echo "  clean   - Remove build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  CROSS_COMPILE - Cross-compiler prefix (default: arm-linux-gnueabihf-)"
	@echo "  DESTDIR       - Installation root directory"
	@echo ""
	@echo "Example:"
	@echo "  make                           # Build for ARM"
	@echo "  make DESTDIR=/mnt/rootfs install  # Install to mounted rootfs"
