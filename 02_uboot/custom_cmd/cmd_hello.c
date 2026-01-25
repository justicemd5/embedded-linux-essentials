// SPDX-License-Identifier: GPL-2.0+
/*
 * cmd_hello.c - Example custom U-Boot command
 *
 * This file demonstrates how to create a custom U-Boot command.
 * Place this file in the u-boot/cmd/ directory.
 *
 * To include in build:
 *   1. Add to cmd/Makefile: obj-y += cmd_hello.o
 *   2. Rebuild U-Boot: make -j$(nproc)
 *
 * Usage at U-Boot prompt:
 *   => hello
 *   => hello world
 *   => hello embedded linux
 *   => help hello
 */

#include <common.h>
#include <command.h>

/**
 * do_hello() - Handler for the 'hello' command
 *
 * @cmdtp: Pointer to command table entry
 * @flag:  Command flags (usually 0)
 * @argc:  Argument count (including command name)
 * @argv:  Argument values
 *
 * This function is called when the user types 'hello' at the U-Boot prompt.
 * It demonstrates basic command implementation including argument handling.
 *
 * Return: 0 on success, non-zero on failure
 */
static int do_hello(struct cmd_tbl *cmdtp, int flag, int argc,
                    char *const argv[])
{
    int i;

    /* Print greeting */
    printf("\n");
    printf("============================================\n");
    printf("   Hello from Custom U-Boot Command!\n");
    printf("============================================\n");
    printf("\n");

    /* Print command information */
    printf("Command name: %s\n", argv[0]);
    printf("Argument count: %d\n", argc);
    printf("\n");

    /* Print any arguments passed */
    if (argc > 1) {
        printf("Arguments received:\n");
        for (i = 1; i < argc; i++) {
            printf("  [%d] %s\n", i, argv[i]);
        }
        printf("\n");

        /* Demonstrate string handling */
        printf("Concatenated message: ");
        for (i = 1; i < argc; i++) {
            printf("%s", argv[i]);
            if (i < argc - 1)
                printf(" ");
        }
        printf("\n");
    } else {
        printf("No arguments provided.\n");
        printf("Try: hello <your message here>\n");
    }

    printf("\n");
    printf("============================================\n");
    printf("\n");

    return 0;  /* Return success */
}

/*
 * U_BOOT_CMD - Register the command with U-Boot
 *
 * Parameters:
 *   hello    - Command name (what user types)
 *   10       - Maximum number of arguments (including command name)
 *   0        - Repeatable flag (1 = pressing Enter repeats command)
 *   do_hello - Function to call when command is executed
 *   "..."    - Short description (shown in 'help' listing)
 *   "..."    - Long help text (shown with 'help hello')
 */
U_BOOT_CMD(
    hello, 10, 0, do_hello,
    "display a greeting message",
    "[arg1] [arg2] ... [argN]\n"
    "    - Print a greeting and display any provided arguments\n"
    "\n"
    "Examples:\n"
    "    hello                    - Print basic greeting\n"
    "    hello world              - Print greeting with one argument\n"
    "    hello embedded linux     - Print greeting with multiple arguments\n"
    "\n"
    "This command demonstrates:\n"
    "    - Basic command structure\n"
    "    - Argument parsing\n"
    "    - String handling\n"
    "    - printf output\n"
);

/*
 * Additional example: A command with subcommands
 *
 * Uncomment and modify as needed
 */

#if 0
static int do_myboard(struct cmd_tbl *cmdtp, int flag, int argc,
                      char *const argv[])
{
    if (argc < 2)
        return CMD_RET_USAGE;

    if (strcmp(argv[1], "info") == 0) {
        printf("Board: My Custom Board\n");
        printf("Revision: 1.0\n");
        return 0;
    }

    if (strcmp(argv[1], "test") == 0) {
        printf("Running board self-test...\n");
        printf("RAM: OK\n");
        printf("Flash: OK\n");
        printf("Ethernet: OK\n");
        printf("Self-test PASSED\n");
        return 0;
    }

    if (strcmp(argv[1], "led") == 0) {
        if (argc < 3)
            return CMD_RET_USAGE;

        if (strcmp(argv[2], "on") == 0) {
            printf("LED ON\n");
            /* Add actual GPIO control here */
            return 0;
        }
        if (strcmp(argv[2], "off") == 0) {
            printf("LED OFF\n");
            /* Add actual GPIO control here */
            return 0;
        }
        return CMD_RET_USAGE;
    }

    return CMD_RET_USAGE;
}

U_BOOT_CMD(
    myboard, 4, 0, do_myboard,
    "board-specific commands",
    "info        - Display board information\n"
    "myboard test        - Run board self-test\n"
    "myboard led on|off  - Control status LED"
);
#endif
