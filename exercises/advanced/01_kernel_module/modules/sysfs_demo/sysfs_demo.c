/*
 * sysfs_demo.c - Sysfs Interface Kernel Module
 * 
 * This module demonstrates sysfs interface creation and usage
 * Creates attributes under /sys/kernel/bbb_demo/
 * 
 * Author: Embedded Linux Labs
 * License: GPL v2
 * Target: BeagleBone Black (AM335x Cortex-A8)
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/init.h>
#include <linux/string.h>
#include <linux/mm.h>

#define MODULE_TAG "sysfs_demo: "

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Embedded Linux Labs");
MODULE_DESCRIPTION("Sysfs Interface Demo for BeagleBone Black");
MODULE_VERSION("1.0");

/* Module parameters */
static int led_brightness = 50;
static char device_name[64] = "beaglebone-demo";
static int enable_logging = 1;

/* Statistics */
static unsigned long read_count = 0;
static unsigned long write_count = 0;

/* Kobject for our sysfs directory */
static struct kobject *bbb_kobj;

/* ============= Sysfs Attribute Handlers ============= */

/* RAM attribute - read only */
static ssize_t ram_mb_show(struct kobject *kobj, 
                            struct kobj_attribute *attr, 
                            char *buf)
{
    struct sysinfo si;
    si_meminfo(&si);
    read_count++;
    return sprintf(buf, "%lu\n", 
                   (si.totalram * si.mem_unit) / (1024 * 1024));
}

/* Brightness attribute - read/write */
static ssize_t brightness_show(struct kobject *kobj,
                                struct kobj_attribute *attr,
                                char *buf)
{
    read_count++;
    return sprintf(buf, "%d\n", led_brightness);
}

static ssize_t brightness_store(struct kobject *kobj,
                                 struct kobj_attribute *attr,
                                 const char *buf, size_t count)
{
    int val;
    int ret;
    
    ret = kstrtoint(buf, 10, &val);
    if (ret < 0)
        return ret;
    
    if (val < 0 || val > 100) {
        pr_warn(MODULE_TAG "brightness must be 0-100, got %d\n", val);
        return -EINVAL;
    }
    
    led_brightness = val;
    write_count++;
    
    if (enable_logging)
        pr_info(MODULE_TAG "brightness set to %d\n", led_brightness);
    
    return count;
}

/* Device name attribute - read/write */
static ssize_t name_show(struct kobject *kobj,
                          struct kobj_attribute *attr,
                          char *buf)
{
    read_count++;
    return sprintf(buf, "%s\n", device_name);
}

static ssize_t name_store(struct kobject *kobj,
                           struct kobj_attribute *attr,
                           const char *buf, size_t count)
{
    size_t len = min(count, sizeof(device_name) - 1);
    
    memcpy(device_name, buf, len);
    device_name[len] = '\0';
    
    /* Remove trailing newline if present */
    if (len > 0 && device_name[len - 1] == '\n')
        device_name[len - 1] = '\0';
    
    write_count++;
    
    if (enable_logging)
        pr_info(MODULE_TAG "device name set to '%s'\n", device_name);
    
    return count;
}

/* Statistics attribute - read only */
static ssize_t stats_show(struct kobject *kobj,
                           struct kobj_attribute *attr,
                           char *buf)
{
    return sprintf(buf, "reads: %lu\nwrites: %lu\n", read_count, write_count);
}

/* Logging enable attribute - read/write */
static ssize_t logging_show(struct kobject *kobj,
                             struct kobj_attribute *attr,
                             char *buf)
{
    return sprintf(buf, "%d\n", enable_logging);
}

static ssize_t logging_store(struct kobject *kobj,
                              struct kobj_attribute *attr,
                              const char *buf, size_t count)
{
    int val;
    int ret;
    
    ret = kstrtoint(buf, 10, &val);
    if (ret < 0)
        return ret;
    
    enable_logging = (val != 0) ? 1 : 0;
    pr_info(MODULE_TAG "logging %s\n", enable_logging ? "enabled" : "disabled");
    
    return count;
}

/* ============= Attribute Definitions ============= */

static struct kobj_attribute ram_attribute = 
    __ATTR(ram_mb, 0444, ram_mb_show, NULL);

static struct kobj_attribute brightness_attribute = 
    __ATTR(brightness, 0664, brightness_show, brightness_store);

static struct kobj_attribute name_attribute = 
    __ATTR(device_name, 0664, name_show, name_store);

static struct kobj_attribute stats_attribute = 
    __ATTR(stats, 0444, stats_show, NULL);

static struct kobj_attribute logging_attribute = 
    __ATTR(logging, 0664, logging_show, logging_store);

/* Attribute group */
static struct attribute *bbb_attrs[] = {
    &ram_attribute.attr,
    &brightness_attribute.attr,
    &name_attribute.attr,
    &stats_attribute.attr,
    &logging_attribute.attr,
    NULL,  /* NULL terminator */
};

static struct attribute_group bbb_attr_group = {
    .attrs = bbb_attrs,
};

/* ============= Module Init/Exit ============= */

static int __init sysfs_demo_init(void)
{
    int ret;
    
    pr_info(MODULE_TAG "Loading module...\n");
    
    /* Create kobject in /sys/kernel/ */
    bbb_kobj = kobject_create_and_add("bbb_demo", kernel_kobj);
    if (!bbb_kobj) {
        pr_err(MODULE_TAG "Failed to create kobject\n");
        return -ENOMEM;
    }
    
    /* Create sysfs group with all attributes */
    ret = sysfs_create_group(bbb_kobj, &bbb_attr_group);
    if (ret) {
        pr_err(MODULE_TAG "Failed to create sysfs group\n");
        kobject_put(bbb_kobj);
        return ret;
    }
    
    pr_info(MODULE_TAG "Module loaded\n");
    pr_info(MODULE_TAG "Sysfs entries created at /sys/kernel/bbb_demo/\n");
    pr_info(MODULE_TAG "Available attributes:\n");
    pr_info(MODULE_TAG "  ram_mb      (ro) - Total RAM in MB\n");
    pr_info(MODULE_TAG "  brightness  (rw) - LED brightness 0-100\n");
    pr_info(MODULE_TAG "  device_name (rw) - Device name string\n");
    pr_info(MODULE_TAG "  stats       (ro) - Read/write statistics\n");
    pr_info(MODULE_TAG "  logging     (rw) - Enable/disable logging\n");
    
    return 0;
}

static void __exit sysfs_demo_exit(void)
{
    sysfs_remove_group(bbb_kobj, &bbb_attr_group);
    kobject_put(bbb_kobj);
    
    pr_info(MODULE_TAG "Module unloaded\n");
    pr_info(MODULE_TAG "Final stats - reads: %lu, writes: %lu\n", 
            read_count, write_count);
}

module_init(sysfs_demo_init);
module_exit(sysfs_demo_exit);
