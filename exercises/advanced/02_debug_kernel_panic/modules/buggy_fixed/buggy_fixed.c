/*
 * buggy_fixed.c - Fixed Version of Buggy Module
 * 
 * This shows the corrected version of all bugs from buggy.c
 * 
 * Author: Embedded Linux Labs
 * License: GPL v2
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/workqueue.h>
#include <linux/slab.h>

#define MODULE_TAG "fixed: "

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Embedded Linux Labs");
MODULE_DESCRIPTION("Fixed version of buggy module");
MODULE_VERSION("1.0");

static struct delayed_work fixed_work;

/* Fix 1: Always check for NULL before dereferencing */
static void safe_pointer_usage(void)
{
    int *ptr = NULL;
    int local_value = 42;
    
    pr_info(MODULE_TAG "FIX 1: Safe pointer handling\n");
    
    /* Option A: Check for NULL before use */
    if (ptr != NULL) {
        *ptr = 42;
    } else {
        pr_warn(MODULE_TAG "Pointer is NULL, using default\n");
        ptr = &local_value;
    }
    
    /* Option B: Allocate memory properly */
    ptr = kmalloc(sizeof(*ptr), GFP_KERNEL);
    if (!ptr) {
        pr_err(MODULE_TAG "Allocation failed\n");
        return;
    }
    
    *ptr = 42;
    pr_info(MODULE_TAG "Value stored: %d\n", *ptr);
    
    kfree(ptr);
    ptr = NULL;  /* Set to NULL after free to prevent use-after-free */
}

/* Fix 2: Never use memory after freeing it */
static void safe_memory_management(void)
{
    struct {
        int value;
        char name[32];
    } *data;
    int saved_value;
    
    pr_info(MODULE_TAG "FIX 2: Safe memory management\n");
    
    /* Allocate memory */
    data = kmalloc(sizeof(*data), GFP_KERNEL);
    if (!data) {
        pr_err(MODULE_TAG "Allocation failed\n");
        return;
    }
    
    data->value = 123;
    snprintf(data->name, sizeof(data->name), "test_data");
    pr_info(MODULE_TAG "Allocated data at %px, value=%d\n", data, data->value);
    
    /* Save what we need BEFORE freeing */
    saved_value = data->value;
    
    /* Free the memory */
    kfree(data);
    data = NULL;  /* Immediately NULL the pointer */
    
    /* Use the saved value, not the freed memory */
    pr_info(MODULE_TAG "Saved value: %d\n", saved_value);
    
    /* If we try to use data now, NULL check catches it */
    if (data) {
        pr_info(MODULE_TAG "Value: %d\n", data->value);
    } else {
        pr_info(MODULE_TAG "data is NULL (correctly freed)\n");
    }
}

/* Fix 3: Use iteration instead of unbounded recursion */
static int safe_iteration(int max_depth)
{
    int depth;
    int result = 0;
    
    pr_info(MODULE_TAG "FIX 3: Safe iteration\n");
    
    /* Use iteration instead of recursion */
    for (depth = 0; depth < max_depth; depth++) {
        result += depth;
        
        /* Process in chunks to avoid monopolizing CPU */
        if (depth % 1000 == 0) {
            cond_resched();  /* Allow scheduler to run */
        }
    }
    
    pr_info(MODULE_TAG "Processed %d iterations, result=%d\n", max_depth, result);
    return result;
}

/* Fix 4: Always validate divisor before division */
static void safe_division(int dividend, int divisor)
{
    int result;
    
    pr_info(MODULE_TAG "FIX 4: Safe division\n");
    
    /* Validate divisor before division */
    if (divisor == 0) {
        pr_warn(MODULE_TAG "Cannot divide by zero!\n");
        result = 0;  /* Or return error code */
    } else {
        result = dividend / divisor;
    }
    
    pr_info(MODULE_TAG "%d / %d = %d\n", dividend, divisor, result);
}

/* Work handler - demonstrates all fixes */
static void fixed_handler(struct work_struct *work)
{
    pr_info(MODULE_TAG "===========================================\n");
    pr_info(MODULE_TAG "Running fixed versions of all bug cases\n");
    pr_info(MODULE_TAG "===========================================\n\n");
    
    safe_pointer_usage();
    pr_info(MODULE_TAG "\n");
    
    safe_memory_management();
    pr_info(MODULE_TAG "\n");
    
    safe_iteration(100);
    pr_info(MODULE_TAG "\n");
    
    safe_division(100, 0);   /* Would crash if not handled */
    safe_division(100, 5);   /* Normal case */
    
    pr_info(MODULE_TAG "\nAll tests completed successfully!\n");
}

static int __init fixed_init(void)
{
    pr_info(MODULE_TAG "Fixed Module Loaded\n");
    pr_info(MODULE_TAG "Running safe operations in 2 seconds...\n");
    
    INIT_DELAYED_WORK(&fixed_work, fixed_handler);
    schedule_delayed_work(&fixed_work, HZ * 2);
    
    return 0;
}

static void __exit fixed_exit(void)
{
    cancel_delayed_work_sync(&fixed_work);
    pr_info(MODULE_TAG "Fixed module unloaded\n");
}

module_init(fixed_init);
module_exit(fixed_exit);
