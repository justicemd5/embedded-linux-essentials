/*
 * buggy.c - Intentionally Buggy Kernel Module for Debugging Practice
 * 
 * This module contains intentional bugs to practice kernel debugging
 * WARNING: Loading this module WILL crash the kernel!
 * 
 * Author: Embedded Linux Labs
 * License: GPL v2
 * Target: BeagleBone Black (AM335x Cortex-A8)
 * 
 * Bugs included:
 *   1. NULL pointer dereference (default)
 *   2. Use-after-free
 *   3. Stack overflow
 *   4. Division by zero
 *   
 * Select bug with module parameter:
 *   insmod buggy.ko bug_type=1
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/workqueue.h>
#include <linux/slab.h>
#include <linux/delay.h>

#define MODULE_TAG "buggy: "

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Embedded Linux Labs");
MODULE_DESCRIPTION("Intentionally buggy module for debugging practice");
MODULE_VERSION("1.0");

/* Module parameter to select bug type */
static int bug_type = 1;
module_param(bug_type, int, 0644);
MODULE_PARM_DESC(bug_type, "Bug type: 1=NULL deref, 2=use-after-free, 3=stack overflow, 4=div-by-zero");

static int delay_seconds = 5;
module_param(delay_seconds, int, 0644);
MODULE_PARM_DESC(delay_seconds, "Seconds before crash (default: 5)");

static struct delayed_work buggy_work;

/* Bug 1: NULL pointer dereference */
static void trigger_null_deref(void)
{
    int *ptr = NULL;
    
    pr_info(MODULE_TAG "BUG 1: About to dereference NULL pointer...\n");
    pr_info(MODULE_TAG "Dereferencing NULL pointer in 3..2..1..\n");
    
    /* This will cause a kernel oops */
    *ptr = 42;
    
    /* Never reached */
    pr_info(MODULE_TAG "This message will never appear\n");
}

/* Bug 2: Use after free */
static void trigger_use_after_free(void)
{
    struct {
        int value;
        char name[32];
    } *data;
    
    pr_info(MODULE_TAG "BUG 2: About to use memory after free...\n");
    
    /* Allocate memory */
    data = kmalloc(sizeof(*data), GFP_KERNEL);
    if (!data) {
        pr_err(MODULE_TAG "Allocation failed\n");
        return;
    }
    
    data->value = 123;
    snprintf(data->name, sizeof(data->name), "test_data");
    pr_info(MODULE_TAG "Allocated data at %px, value=%d\n", data, data->value);
    
    /* Free the memory */
    kfree(data);
    pr_info(MODULE_TAG "Memory freed, now using it...\n");
    
    /* Use after free - undefined behavior */
    /* May crash, may appear to work, may corrupt other data */
    pr_info(MODULE_TAG "Value after free: %d\n", data->value);
    data->value = 456;  /* Writing to freed memory */
    pr_info(MODULE_TAG "This may or may not crash...\n");
}

/* Bug 3: Stack overflow via recursion */
static int recursive_function(int depth)
{
    char local_buffer[1024];  /* Consume stack space */
    
    /* Initialize buffer to prevent optimization */
    memset(local_buffer, 'A', sizeof(local_buffer));
    
    pr_info(MODULE_TAG "Recursion depth: %d\n", depth);
    
    /* Infinite recursion - will overflow kernel stack */
    return recursive_function(depth + 1) + local_buffer[0];
}

static void trigger_stack_overflow(void)
{
    pr_info(MODULE_TAG "BUG 3: About to overflow the stack...\n");
    pr_info(MODULE_TAG "Starting infinite recursion...\n");
    
    recursive_function(0);
}

/* Bug 4: Division by zero */
static void trigger_div_by_zero(void)
{
    volatile int divisor = 0;
    volatile int result;
    
    pr_info(MODULE_TAG "BUG 4: About to divide by zero...\n");
    pr_info(MODULE_TAG "Calculating 100 / 0...\n");
    
    /* Division by zero */
    result = 100 / divisor;
    
    /* Never reached */
    pr_info(MODULE_TAG "Result: %d\n", result);
}

/* Work handler - triggers selected bug */
static void buggy_handler(struct work_struct *work)
{
    pr_info(MODULE_TAG "Work handler executing...\n");
    pr_info(MODULE_TAG "Selected bug type: %d\n", bug_type);
    
    switch (bug_type) {
    case 1:
        trigger_null_deref();
        break;
    case 2:
        trigger_use_after_free();
        break;
    case 3:
        trigger_stack_overflow();
        break;
    case 4:
        trigger_div_by_zero();
        break;
    default:
        pr_err(MODULE_TAG "Unknown bug type: %d\n", bug_type);
        pr_err(MODULE_TAG "Valid types: 1-4\n");
        return;
    }
}

static int __init buggy_init(void)
{
    pr_info(MODULE_TAG "===========================================\n");
    pr_info(MODULE_TAG "Buggy Module Loaded on AM335x\n");
    pr_info(MODULE_TAG "===========================================\n");
    pr_info(MODULE_TAG "\n");
    pr_info(MODULE_TAG "WARNING: This module WILL crash the kernel!\n");
    pr_info(MODULE_TAG "Bug type: %d\n", bug_type);
    pr_info(MODULE_TAG "Crash in: %d seconds\n", delay_seconds);
    pr_info(MODULE_TAG "\n");
    pr_info(MODULE_TAG "Bug types:\n");
    pr_info(MODULE_TAG "  1 = NULL pointer dereference\n");
    pr_info(MODULE_TAG "  2 = Use after free\n");
    pr_info(MODULE_TAG "  3 = Stack overflow\n");
    pr_info(MODULE_TAG "  4 = Division by zero\n");
    pr_info(MODULE_TAG "\n");
    pr_info(MODULE_TAG "Scheduling crash...\n");
    
    INIT_DELAYED_WORK(&buggy_work, buggy_handler);
    schedule_delayed_work(&buggy_work, HZ * delay_seconds);
    
    return 0;
}

static void __exit buggy_exit(void)
{
    cancel_delayed_work_sync(&buggy_work);
    pr_info(MODULE_TAG "Module unloaded (crash avoided!)\n");
}

module_init(buggy_init);
module_exit(buggy_exit);
