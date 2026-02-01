# FOTA Client Makefile
#
# Build the FOTA client for ARM target (BeagleBone Black)
#
# Prerequisites on build host:
#   - ARM cross-compiler (arm-linux-gnueabihf-gcc)
#   - libcurl development files
#   - json-c development files
#   - OpenSSL development files
#
# For cross-compilation, ensure you have the ARM versions of libraries
# or use a proper sysroot.

# Cross-compiler settings
CROSS_COMPILE ?= arm-linux-gnueabihf-
CC = $(CROSS_COMPILE)gcc
STRIP = $(CROSS_COMPILE)strip

# Compiler flags
CFLAGS = -Wall -Wextra -O2 -g
CFLAGS += -D_GNU_SOURCE

# Libraries
LDFLAGS = -lcurl -ljson-c -lcrypto

# If using a sysroot for cross-compilation
ifdef SYSROOT
CFLAGS += --sysroot=$(SYSROOT)
LDFLAGS += --sysroot=$(SYSROOT)
endif

# Source and target
TARGET = fota_client
SRC = fota_client.c

# Installation paths (on target)
PREFIX ?= /usr
BINDIR = $(PREFIX)/bin
SBINDIR = $(PREFIX)/sbin
CONFDIR = /etc/fota
DATADIR = /data/fota
OPTDIR = /opt/fota
SYSTEMDDIR = /etc/systemd/system

.PHONY: all clean install install-host uninstall

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# Build optimized release version
release: $(SRC)
	$(CC) $(CFLAGS) -O3 -DNDEBUG -o $(TARGET) $< $(LDFLAGS)
	$(STRIP) $(TARGET)

# Build for host (native compilation for testing)
host:
	gcc $(CFLAGS) -o $(TARGET) $(SRC) $(LDFLAGS)

clean:
	rm -f $(TARGET)

# Install to target rootfs (run as root or with DESTDIR)
install: $(TARGET)
	install -d $(DESTDIR)$(OPTDIR)
	install -d $(DESTDIR)$(CONFDIR)
	install -d $(DESTDIR)$(DATADIR)
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(SYSTEMDDIR)
	
	# Install binary
	install -m 755 $(TARGET) $(DESTDIR)$(OPTDIR)/
	
	# Install trigger script
	install -m 755 fota-trigger $(DESTDIR)$(BINDIR)/
	
	# Install config (don't overwrite existing)
	test -f $(DESTDIR)$(CONFDIR)/fota.conf || \
		install -m 644 fota.conf $(DESTDIR)$(CONFDIR)/
	
	# Install systemd service
	install -m 644 ../rootfs/etc/systemd/system/fota.service $(DESTDIR)$(SYSTEMDDIR)/
	install -m 644 ../rootfs/etc/systemd/system/boot-success.service $(DESTDIR)$(SYSTEMDDIR)/
	
	@echo ""
	@echo "Installation complete!"
	@echo "To enable FOTA service:"
	@echo "  systemctl daemon-reload"
	@echo "  systemctl enable fota boot-success"
	@echo "  systemctl start fota"

# Install for testing on host machine
install-host: host
	sudo install -m 755 $(TARGET) /usr/local/bin/
	sudo install -m 755 fota-trigger /usr/local/bin/
	sudo mkdir -p /etc/fota
	sudo test -f /etc/fota/fota.conf || sudo install -m 644 fota.conf /etc/fota/
	@echo "Installed to /usr/local/bin for testing"

uninstall:
	rm -f $(DESTDIR)$(OPTDIR)/$(TARGET)
	rm -f $(DESTDIR)$(BINDIR)/fota-trigger
	rm -f $(DESTDIR)$(SYSTEMDDIR)/fota.service
	rm -f $(DESTDIR)$(SYSTEMDDIR)/boot-success.service
	@echo "Uninstalled. Config files in $(CONFDIR) preserved."

# Show build info
info:
	@echo "Cross compiler: $(CC)"
	@echo "CFLAGS: $(CFLAGS)"
	@echo "LDFLAGS: $(LDFLAGS)"
	@echo "Target: $(TARGET)"
