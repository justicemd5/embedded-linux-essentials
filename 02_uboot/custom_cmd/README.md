# Creating Custom U-Boot Commands

This lab teaches you how to extend U-Boot by adding your own custom commands.

## Why Custom Commands?

Custom U-Boot commands allow you to:

- Add board-specific diagnostics
- Implement custom boot logic
- Create manufacturing test commands
- Add hardware testing utilities
- Simplify complex operations

## Understanding U-Boot Commands

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    U-BOOT COMMAND STRUCTURE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Command Registration Macro:                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                     │   │
│  │  U_BOOT_CMD(name, maxargs, repeatable, function, usage, help)      │   │
│  │            │      │          │          │        │       │         │   │
│  │            │      │          │          │        │       └─ Long   │   │
│  │            │      │          │          │        │          help   │   │
│  │            │      │          │          │        └─ Short usage    │   │
│  │            │      │          │          └─ Handler function        │   │
│  │            │      │          └─ 1=can repeat with Enter, 0=no      │   │
│  │            │      └─ Maximum number of arguments                    │   │
│  │            └─ Command name (as typed at prompt)                    │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Handler Function Signature:                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                     │   │
│  │  int do_mycommand(struct cmd_tbl *cmdtp,                           │   │
│  │                   int flag,                                        │   │
│  │                   int argc,                                        │   │
│  │                   char *const argv[])                              │   │
│  │                                                                     │   │
│  │  cmdtp - Pointer to command table entry                            │   │
│  │  flag  - Command flags (usually 0)                                 │   │
│  │  argc  - Argument count (including command name)                   │   │
│  │  argv  - Argument values (argv[0] = command name)                  │   │
│  │                                                                     │   │
│  │  Returns: 0 = success, 1 = failure, CMD_RET_USAGE = show usage     │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Part 1: Simple Hello Command

### Step 1: Create the Source File

Create `cmd/cmd_hello.c`:

```c
// SPDX-License-Identifier: GPL-2.0+
/*
 * cmd_hello.c - Example custom U-Boot command
 *
 * Demonstrates how to create a simple U-Boot command.
 */

#include <common.h>
#include <command.h>

static int do_hello(struct cmd_tbl *cmdtp, int flag, int argc,
                    char *const argv[])
{
    printf("Hello from U-Boot!\n");
    printf("This is a custom command.\n");
    
    /* Print any arguments passed */
    if (argc > 1) {
        int i;
        printf("Arguments received:\n");
        for (i = 1; i < argc; i++) {
            printf("  argv[%d] = %s\n", i, argv[i]);
        }
    }
    
    return 0;  /* Success */
}

/* Register the command */
U_BOOT_CMD(
    hello,      /* Command name */
    5,          /* Maximum arguments */
    0,          /* Not repeatable */
    do_hello,   /* Handler function */
    "say hello", /* Short description (for 'help' listing) */
    "[args...]\n"  /* Long help (for 'help hello') */
    "    - Print hello message and display any arguments\n"
    "    Example: hello world embedded linux"
);
```

### Step 2: Add to Build System

Modify `cmd/Makefile` to include your command:

```makefile
# Add this line (alphabetically with other commands)
obj-y += cmd_hello.o
```

Or create a Kconfig option for conditional compilation:

```makefile
# In cmd/Makefile
obj-$(CONFIG_CMD_HELLO) += cmd_hello.o
```

```kconfig
# In cmd/Kconfig
config CMD_HELLO
    bool "hello - example custom command"
    default y
    help
      This is an example custom command that prints a greeting.
```

### Step 3: Build and Test

```bash
# Rebuild U-Boot
make -j$(nproc)

# Deploy and boot
# At U-Boot prompt:
=> help hello
hello - say hello

Usage:
hello [args...]
    - Print hello message and display any arguments
    Example: hello world embedded linux

=> hello
Hello from U-Boot!
This is a custom command.

=> hello world
Hello from U-Boot!
This is a custom command.
Arguments received:
  argv[1] = world
```

## Part 2: Board Information Command

A more practical example that displays board information:

```c
// SPDX-License-Identifier: GPL-2.0+
/*
 * cmd_boardinfo.c - Display board information
 */

#include <common.h>
#include <command.h>
#include <version.h>
#include <asm/global_data.h>

DECLARE_GLOBAL_DATA_PTR;

static int do_boardinfo(struct cmd_tbl *cmdtp, int flag, int argc,
                        char *const argv[])
{
    printf("\n");
    printf("===========================================\n");
    printf("         Board Information\n");
    printf("===========================================\n");
    
    /* U-Boot version */
    printf("U-Boot Version : %s\n", U_BOOT_VERSION);
    printf("Build Date     : %s %s\n", U_BOOT_DATE, U_BOOT_TIME);
    
    /* Memory information */
    printf("\nMemory:\n");
    printf("  RAM Base     : 0x%08lx\n", (unsigned long)gd->ram_base);
    printf("  RAM Size     : %lu MB\n", (unsigned long)gd->ram_size / (1024 * 1024));
    printf("  Malloc Base  : 0x%08lx\n", (unsigned long)gd->malloc_base);
    
    /* Environment */
    printf("\nEnvironment:\n");
    printf("  env valid    : %s\n", gd->env_valid ? "yes" : "no");
    
    /* Boot info */
    printf("\nBoot:\n");
    printf("  Boot device  : ");
#ifdef CONFIG_MMC
    printf("MMC/SD\n");
#elif defined(CONFIG_SPI_FLASH)
    printf("SPI Flash\n");
#else
    printf("Unknown\n");
#endif

    printf("===========================================\n\n");
    
    return 0;
}

U_BOOT_CMD(
    boardinfo, 1, 0, do_boardinfo,
    "display board information",
    "\n    - Display detailed board and build information"
);
```

## Part 3: LED Control Command

Example for hardware interaction:

```c
// SPDX-License-Identifier: GPL-2.0+
/*
 * cmd_led_ctrl.c - Control board LEDs
 */

#include <common.h>
#include <command.h>

#ifdef CONFIG_LED
#include <led.h>
#endif

static int do_led_ctrl(struct cmd_tbl *cmdtp, int flag, int argc,
                       char *const argv[])
{
    if (argc < 2)
        return CMD_RET_USAGE;
    
    if (strcmp(argv[1], "on") == 0) {
        printf("Turning LED ON\n");
        /* Add actual LED control code here */
#ifdef CONFIG_LED
        led_set_state_by_label("status", LEDST_ON);
#endif
    } else if (strcmp(argv[1], "off") == 0) {
        printf("Turning LED OFF\n");
#ifdef CONFIG_LED
        led_set_state_by_label("status", LEDST_OFF);
#endif
    } else if (strcmp(argv[1], "blink") == 0) {
        int count = 5;
        if (argc > 2)
            count = simple_strtoul(argv[2], NULL, 10);
        
        printf("Blinking LED %d times\n", count);
        /* Add blink implementation */
    } else {
        return CMD_RET_USAGE;
    }
    
    return 0;
}

U_BOOT_CMD(
    led_ctrl, 3, 0, do_led_ctrl,
    "control board LED",
    "on|off|blink [count]\n"
    "    on     - Turn LED on\n"
    "    off    - Turn LED off\n"
    "    blink [n] - Blink LED n times (default 5)"
);
```

## Part 4: Memory Test Command

Example showing memory access:

```c
// SPDX-License-Identifier: GPL-2.0+
/*
 * cmd_memcheck.c - Quick memory verification
 */

#include <common.h>
#include <command.h>

static int do_memcheck(struct cmd_tbl *cmdtp, int flag, int argc,
                       char *const argv[])
{
    unsigned long addr;
    unsigned long size;
    unsigned long *ptr;
    unsigned long i;
    int errors = 0;
    
    if (argc < 3)
        return CMD_RET_USAGE;
    
    addr = simple_strtoul(argv[1], NULL, 16);
    size = simple_strtoul(argv[2], NULL, 16);
    
    printf("Memory check: 0x%08lx - 0x%08lx (%lu bytes)\n",
           addr, addr + size, size);
    
    ptr = (unsigned long *)addr;
    
    /* Write pattern */
    printf("Writing pattern...\n");
    for (i = 0; i < size / sizeof(unsigned long); i++) {
        ptr[i] = i ^ 0xAAAAAAAA;
    }
    
    /* Verify pattern */
    printf("Verifying...\n");
    for (i = 0; i < size / sizeof(unsigned long); i++) {
        if (ptr[i] != (i ^ 0xAAAAAAAA)) {
            printf("Error at 0x%08lx: expected 0x%08lx, got 0x%08lx\n",
                   (unsigned long)&ptr[i],
                   i ^ 0xAAAAAAAA,
                   ptr[i]);
            errors++;
            if (errors > 10) {
                printf("Too many errors, stopping\n");
                break;
            }
        }
    }
    
    if (errors == 0)
        printf("Memory check PASSED\n");
    else
        printf("Memory check FAILED with %d errors\n", errors);
    
    return errors ? 1 : 0;
}

U_BOOT_CMD(
    memcheck, 3, 0, do_memcheck,
    "quick memory verification",
    "<addr> <size>\n"
    "    addr - Start address (hex)\n"
    "    size - Size to check (hex)\n"
    "    Example: memcheck 0x80000000 0x100000"
);
```

## Part 5: Integration Steps

### File Placement

Place your command file in the `cmd/` directory:
```
u-boot/
└── cmd/
    ├── Kconfig
    ├── Makefile
    ├── cmd_hello.c      ← Your file
    └── ...
```

### Makefile Integration

Edit `cmd/Makefile`:
```makefile
# Find appropriate section and add:
obj-$(CONFIG_CMD_HELLO) += cmd_hello.o

# Or for unconditional build:
obj-y += cmd_hello.o
```

### Kconfig Integration (Optional)

Edit `cmd/Kconfig`:
```kconfig
config CMD_HELLO
    bool "hello command"
    default y
    help
      Enable the hello command for demonstration.
```

Then enable in menuconfig:
```
Command line interface  --->
    [*] hello command
```

## Common Patterns

### Return Codes

```c
return 0;              /* Success */
return 1;              /* Failure */
return CMD_RET_USAGE;  /* Print usage and return failure */
return CMD_RET_FAILURE; /* Generic failure */
return CMD_RET_SUCCESS; /* Success (same as 0) */
```

### Argument Parsing

```c
/* Get numeric argument */
unsigned long val = simple_strtoul(argv[1], NULL, 16);

/* String comparison */
if (strcmp(argv[1], "enable") == 0) { ... }

/* Check argument count */
if (argc < 2) return CMD_RET_USAGE;
```

### Environment Variables

```c
/* Read environment variable */
char *val = env_get("bootdelay");

/* Set environment variable */
env_set("myvar", "myvalue");
```

---

## Troubleshooting

### Command Not Found

```bash
=> hello
Unknown command 'hello'
```
- Check file is in cmd/ directory
- Check Makefile includes your file
- Rebuild U-Boot completely (`make clean; make`)

### Build Errors

```
cmd/cmd_hello.c:5:10: fatal error: common.h: No such file or directory
```
- Check include paths
- Ensure you're building in U-Boot context

### Command Crashes

- Check pointer validity
- Ensure memory regions are accessible
- Add debug printf statements

---

## What You Learned

After completing this lab:

1. ✅ How U-Boot command registration works
2. ✅ The command handler function signature
3. ✅ How to add files to U-Boot build system
4. ✅ How to parse command arguments
5. ✅ How to access hardware from commands
6. ✅ How to use environment variables in commands
