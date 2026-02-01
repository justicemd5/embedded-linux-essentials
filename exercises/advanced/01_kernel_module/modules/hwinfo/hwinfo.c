/*
 * hwinfo.c - BeagleBone Black Hardware Information Kernel Module
 * 
 * This module provides hardware information via /proc/hwinfo
 * Demonstrates basic kernel module structure and procfs interface
 * 
 * Author: Embedded Linux Labs
 * License: GPL v2
 * Target: BeagleBone Black (AM335x Cortex-A8)
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/mm.h>
#include <linux/sched.h>
#include <linux/utsname.h>
#include <linux/version.h>

#define PROC_NAME "hwinfo"
#define MODULE_TAG "hwinfo: "

/* Module metadata */
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Embedded Linux Labs");
MODULE_DESCRIPTION("BeagleBone Black Hardware Information Module");
MODULE_VERSION("1.0");

/* Show hardware information */
static int hwinfo_show(struct seq_file *m, void *v)
{
    struct sysinfo si;
    
    si_meminfo(&si);
    
    seq_printf(m, "╔═══════════════════════════════════════════════════════╗\n");
    seq_printf(m, "║     BeagleBone Black Hardware Information Module      ║\n");
    seq_printf(m, "╠═══════════════════════════════════════════════════════╣\n");
    seq_printf(m, "║ Platform: TI AM335x (Cortex-A8 @ 1GHz)                ║\n");
    seq_printf(m, "╠═══════════════════════════════════════════════════════╣\n");
    
    /* Kernel information */
    seq_printf(m, "║ KERNEL INFORMATION                                    ║\n");
    seq_printf(m, "║   Version: %-44s ║\n", utsname()->release);
    seq_printf(m, "║   Build:   %-44s ║\n", utsname()->version);
    
    /* Memory information */
    seq_printf(m, "╠═══════════════════════════════════════════════════════╣\n");
    seq_printf(m, "║ MEMORY INFORMATION                                    ║\n");
    seq_printf(m, "║   Total RAM:    %8lu MB                            ║\n",
               (si.totalram * si.mem_unit) / (1024 * 1024));
    seq_printf(m, "║   Free RAM:     %8lu MB                            ║\n",
               (si.freeram * si.mem_unit) / (1024 * 1024));
    seq_printf(m, "║   Shared RAM:   %8lu MB                            ║\n",
               (si.sharedram * si.mem_unit) / (1024 * 1024));
    seq_printf(m, "║   Buffer RAM:   %8lu MB                            ║\n",
               (si.bufferram * si.mem_unit) / (1024 * 1024));
    seq_printf(m, "║   Page Size:    %8lu bytes                         ║\n",
               PAGE_SIZE);
    
    /* System configuration */
    seq_printf(m, "╠═══════════════════════════════════════════════════════╣\n");
    seq_printf(m, "║ SYSTEM CONFIGURATION                                  ║\n");
    seq_printf(m, "║   HZ (Tick Rate):     %4d                            ║\n", HZ);
    seq_printf(m, "║   Jiffies:            %lu                      ║\n", jiffies);
    seq_printf(m, "║   NR_CPUS:            %4d                            ║\n", NR_CPUS);
    seq_printf(m, "║   Current CPU:        %4d                            ║\n", 
               smp_processor_id());
    
#ifdef CONFIG_PREEMPT
    seq_printf(m, "║   Preemption:         Enabled                         ║\n");
#else
    seq_printf(m, "║   Preemption:         Disabled                        ║\n");
#endif

#ifdef CONFIG_PREEMPT_RT
    seq_printf(m, "║   PREEMPT_RT:         Enabled                         ║\n");
#endif

#ifdef CONFIG_ARM
    seq_printf(m, "║   Architecture:       ARM 32-bit                      ║\n");
#endif

    seq_printf(m, "╚═══════════════════════════════════════════════════════╝\n");
    
    return 0;
}

static int hwinfo_open(struct inode *inode, struct file *file)
{
    return single_open(file, hwinfo_show, NULL);
}

static const struct proc_ops hwinfo_fops = {
    .proc_open    = hwinfo_open,
    .proc_read    = seq_read,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};

static struct proc_dir_entry *hwinfo_entry;

static int __init hwinfo_init(void)
{
    pr_info(MODULE_TAG "Loading module...\n");
    
    hwinfo_entry = proc_create(PROC_NAME, 0444, NULL, &hwinfo_fops);
    if (!hwinfo_entry) {
        pr_err(MODULE_TAG "Failed to create /proc/%s\n", PROC_NAME);
        return -ENOMEM;
    }
    
    pr_info(MODULE_TAG "Module loaded, /proc/%s created\n", PROC_NAME);
    pr_info(MODULE_TAG "Read with: cat /proc/%s\n", PROC_NAME);
    
    return 0;
}

static void __exit hwinfo_exit(void)
{
    if (hwinfo_entry) {
        proc_remove(hwinfo_entry);
        pr_info(MODULE_TAG "/proc/%s removed\n", PROC_NAME);
    }
    
    pr_info(MODULE_TAG "Module unloaded\n");
}

module_init(hwinfo_init);
module_exit(hwinfo_exit);
