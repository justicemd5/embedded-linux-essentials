# Makefile for PREEMPT_RT Applications
#
# Builds all RT applications for BeagleBone Black
#
# Usage:
#   make              # Build all
#   make rt_app       # Build single application
#   make deploy       # Copy to BBB
#   make clean        # Clean build files
#
# Author: Embedded Linux Labs
# License: MIT

# Cross-compilation settings
CROSS_COMPILE ?= arm-linux-gnueabihf-
CC = $(CROSS_COMPILE)gcc

# Target
TARGET_HOST ?= debian@192.168.7.2
TARGET_DIR ?= /home/debian/rt_apps

# Compiler flags
CFLAGS = -O2 -Wall -Wextra -pthread
CFLAGS += -D_GNU_SOURCE
LDFLAGS = -lpthread -lrt

# Debug build
DEBUG_CFLAGS = -g -O0 -DDEBUG

# Applications
APPS = rt_app multi_rt gpio_rt cyclictest_custom

# Source files
rt_app_SRC = rt_application.c
multi_rt_SRC = multi_rt_app.c
gpio_rt_SRC = gpio_rt_handler.c
cyclictest_custom_SRC = cyclictest_custom.c

.PHONY: all clean deploy debug help

all: $(APPS)

rt_app: $(rt_app_SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

multi_rt: $(multi_rt_SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

gpio_rt: $(gpio_rt_SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

cyclictest_custom: $(cyclictest_custom_SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# Debug build
debug: CFLAGS += $(DEBUG_CFLAGS)
debug: all

# Deploy to BeagleBone Black
deploy: all
	@echo "Deploying to $(TARGET_HOST):$(TARGET_DIR)"
	ssh $(TARGET_HOST) "mkdir -p $(TARGET_DIR)"
	scp $(APPS) $(TARGET_HOST):$(TARGET_DIR)/
	@echo "Done. Run with: sudo $(TARGET_DIR)/<app>"

# Clean build files
clean:
	rm -f $(APPS) *.o

# Help
help:
	@echo "PREEMPT_RT Applications Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all          Build all applications (default)"
	@echo "  rt_app       Build single-threaded RT application"
	@echo "  multi_rt     Build multi-threaded RT application"
	@echo "  gpio_rt      Build GPIO RT interrupt handler"
	@echo "  debug        Build with debug symbols"
	@echo "  deploy       Copy binaries to BeagleBone Black"
	@echo "  clean        Remove build files"
	@echo ""
	@echo "Variables:"
	@echo "  CROSS_COMPILE  Cross compiler prefix (default: arm-linux-gnueabihf-)"
	@echo "  TARGET_HOST    SSH target (default: debian@192.168.7.2)"
	@echo "  TARGET_DIR     Target directory (default: /home/debian/rt_apps)"
