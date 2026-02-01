# myapp Makefile

CC ?= gcc
CFLAGS ?= -Wall -Wextra -O2
LDFLAGS ?=

TARGET = myapp
SRCS = myapp.c
OBJS = $(SRCS:.c=.o)

# Default target
all: $(TARGET)

# Link
$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

# Compile
%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Install
install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)/usr/bin/$(TARGET)

# Clean
clean:
	rm -f $(TARGET) $(OBJS)

# Debug build
debug: CFLAGS += -g -DDEBUG
debug: clean all

.PHONY: all clean install debug
