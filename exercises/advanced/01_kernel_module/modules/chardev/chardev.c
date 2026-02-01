/*
 * chardev.c - Character Device Driver Example
 * 
 * This module demonstrates character device creation with:
 * - Dynamic major number allocation
 * - File operations (open, read, write, ioctl, release)
 * - Kernel-user data transfer
 * - IOCTL commands
 * 
 * Author: Embedded Linux Labs
 * License: GPL v2
 * Target: BeagleBone Black (AM335x Cortex-A8)
 * 
 * Usage:
 *   mknod /dev/bbbchar c <major> 0
 *   echo "Hello" > /dev/bbbchar
 *   cat /dev/bbbchar
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/ioctl.h>
#include <linux/slab.h>
#include <linux/mutex.h>

#define DEVICE_NAME "bbbchar"
#define CLASS_NAME  "bbb"
#define MODULE_TAG  "chardev: "

/* Buffer size for device data */
#define BUFFER_SIZE 4096

/* IOCTL command definitions */
#define CHARDEV_IOC_MAGIC 'B'
#define CHARDEV_IOCRESET    _IO(CHARDEV_IOC_MAGIC, 0)
#define CHARDEV_IOCGETSIZE  _IOR(CHARDEV_IOC_MAGIC, 1, int)
#define CHARDEV_IOCSETSIZE  _IOW(CHARDEV_IOC_MAGIC, 2, int)
#define CHARDEV_IOCGETCOUNT _IOR(CHARDEV_IOC_MAGIC, 3, int)

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Embedded Linux Labs");
MODULE_DESCRIPTION("Character Device Driver Demo for BeagleBone Black");
MODULE_VERSION("1.0");

/* Device data structure */
struct chardev_data {
    char *buffer;
    size_t size;
    size_t data_len;
    int open_count;
    unsigned long read_count;
    unsigned long write_count;
    struct mutex lock;
};

/* Global variables */
static dev_t dev_num;
static struct cdev chardev_cdev;
static struct class *chardev_class;
static struct device *chardev_device;
static struct chardev_data *dev_data;

/* ============= File Operations ============= */

static int chardev_open(struct inode *inode, struct file *filp)
{
    struct chardev_data *data = dev_data;
    
    if (!data)
        return -ENODEV;
    
    mutex_lock(&data->lock);
    data->open_count++;
    filp->private_data = data;
    mutex_unlock(&data->lock);
    
    pr_info(MODULE_TAG "Device opened (count: %d)\n", data->open_count);
    return 0;
}

static int chardev_release(struct inode *inode, struct file *filp)
{
    struct chardev_data *data = filp->private_data;
    
    mutex_lock(&data->lock);
    data->open_count--;
    mutex_unlock(&data->lock);
    
    pr_info(MODULE_TAG "Device closed (count: %d)\n", data->open_count);
    return 0;
}

static ssize_t chardev_read(struct file *filp, char __user *buf,
                             size_t count, loff_t *offset)
{
    struct chardev_data *data = filp->private_data;
    ssize_t bytes_read = 0;
    
    mutex_lock(&data->lock);
    
    /* Check bounds */
    if (*offset >= data->data_len) {
        mutex_unlock(&data->lock);
        return 0;  /* EOF */
    }
    
    /* Limit read to available data */
    if (*offset + count > data->data_len)
        count = data->data_len - *offset;
    
    /* Copy data to user space */
    if (copy_to_user(buf, data->buffer + *offset, count)) {
        mutex_unlock(&data->lock);
        return -EFAULT;
    }
    
    *offset += count;
    bytes_read = count;
    data->read_count++;
    
    mutex_unlock(&data->lock);
    
    pr_debug(MODULE_TAG "Read %zu bytes (offset: %lld)\n", count, *offset);
    return bytes_read;
}

static ssize_t chardev_write(struct file *filp, const char __user *buf,
                              size_t count, loff_t *offset)
{
    struct chardev_data *data = filp->private_data;
    ssize_t bytes_written = 0;
    
    mutex_lock(&data->lock);
    
    /* Check bounds */
    if (*offset >= data->size) {
        mutex_unlock(&data->lock);
        return -ENOSPC;
    }
    
    /* Limit write to buffer size */
    if (*offset + count > data->size)
        count = data->size - *offset;
    
    /* Copy data from user space */
    if (copy_from_user(data->buffer + *offset, buf, count)) {
        mutex_unlock(&data->lock);
        return -EFAULT;
    }
    
    *offset += count;
    bytes_written = count;
    
    /* Update data length if we wrote past the current end */
    if (*offset > data->data_len)
        data->data_len = *offset;
    
    data->write_count++;
    
    mutex_unlock(&data->lock);
    
    pr_debug(MODULE_TAG "Wrote %zu bytes (offset: %lld)\n", count, *offset);
    return bytes_written;
}

static long chardev_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
    struct chardev_data *data = filp->private_data;
    int ret = 0;
    int tmp;
    
    /* Verify command type */
    if (_IOC_TYPE(cmd) != CHARDEV_IOC_MAGIC)
        return -ENOTTY;
    
    mutex_lock(&data->lock);
    
    switch (cmd) {
    case CHARDEV_IOCRESET:
        /* Reset buffer */
        memset(data->buffer, 0, data->size);
        data->data_len = 0;
        pr_info(MODULE_TAG "Buffer reset via ioctl\n");
        break;
        
    case CHARDEV_IOCGETSIZE:
        /* Get buffer size */
        tmp = (int)data->size;
        if (copy_to_user((int __user *)arg, &tmp, sizeof(tmp)))
            ret = -EFAULT;
        break;
        
    case CHARDEV_IOCSETSIZE:
        /* Set buffer size (not implemented - would require realloc) */
        ret = -ENOTTY;
        break;
        
    case CHARDEV_IOCGETCOUNT:
        /* Get data length */
        tmp = (int)data->data_len;
        if (copy_to_user((int __user *)arg, &tmp, sizeof(tmp)))
            ret = -EFAULT;
        break;
        
    default:
        ret = -ENOTTY;
    }
    
    mutex_unlock(&data->lock);
    return ret;
}

static loff_t chardev_llseek(struct file *filp, loff_t offset, int whence)
{
    struct chardev_data *data = filp->private_data;
    loff_t new_pos;
    
    mutex_lock(&data->lock);
    
    switch (whence) {
    case SEEK_SET:
        new_pos = offset;
        break;
    case SEEK_CUR:
        new_pos = filp->f_pos + offset;
        break;
    case SEEK_END:
        new_pos = data->data_len + offset;
        break;
    default:
        mutex_unlock(&data->lock);
        return -EINVAL;
    }
    
    if (new_pos < 0 || new_pos > data->size) {
        mutex_unlock(&data->lock);
        return -EINVAL;
    }
    
    filp->f_pos = new_pos;
    mutex_unlock(&data->lock);
    
    return new_pos;
}

/* File operations structure */
static const struct file_operations chardev_fops = {
    .owner          = THIS_MODULE,
    .open           = chardev_open,
    .release        = chardev_release,
    .read           = chardev_read,
    .write          = chardev_write,
    .unlocked_ioctl = chardev_ioctl,
    .llseek         = chardev_llseek,
};

/* ============= Module Init/Exit ============= */

static int __init chardev_init(void)
{
    int ret;
    
    pr_info(MODULE_TAG "Loading module...\n");
    
    /* Allocate device data */
    dev_data = kzalloc(sizeof(*dev_data), GFP_KERNEL);
    if (!dev_data) {
        pr_err(MODULE_TAG "Failed to allocate device data\n");
        return -ENOMEM;
    }
    
    /* Allocate buffer */
    dev_data->buffer = kzalloc(BUFFER_SIZE, GFP_KERNEL);
    if (!dev_data->buffer) {
        pr_err(MODULE_TAG "Failed to allocate buffer\n");
        ret = -ENOMEM;
        goto err_free_data;
    }
    
    dev_data->size = BUFFER_SIZE;
    mutex_init(&dev_data->lock);
    
    /* Allocate device number dynamically */
    ret = alloc_chrdev_region(&dev_num, 0, 1, DEVICE_NAME);
    if (ret < 0) {
        pr_err(MODULE_TAG "Failed to allocate device number\n");
        goto err_free_buffer;
    }
    
    pr_info(MODULE_TAG "Allocated device number: major=%d, minor=%d\n",
            MAJOR(dev_num), MINOR(dev_num));
    
    /* Initialize and add cdev */
    cdev_init(&chardev_cdev, &chardev_fops);
    chardev_cdev.owner = THIS_MODULE;
    
    ret = cdev_add(&chardev_cdev, dev_num, 1);
    if (ret < 0) {
        pr_err(MODULE_TAG "Failed to add cdev\n");
        goto err_unreg_chrdev;
    }
    
    /* Create device class */
    chardev_class = class_create(CLASS_NAME);
    if (IS_ERR(chardev_class)) {
        pr_err(MODULE_TAG "Failed to create class\n");
        ret = PTR_ERR(chardev_class);
        goto err_del_cdev;
    }
    
    /* Create device node */
    chardev_device = device_create(chardev_class, NULL, dev_num, 
                                    NULL, DEVICE_NAME);
    if (IS_ERR(chardev_device)) {
        pr_err(MODULE_TAG "Failed to create device\n");
        ret = PTR_ERR(chardev_device);
        goto err_destroy_class;
    }
    
    pr_info(MODULE_TAG "Module loaded successfully\n");
    pr_info(MODULE_TAG "Device created at /dev/%s\n", DEVICE_NAME);
    pr_info(MODULE_TAG "Buffer size: %d bytes\n", BUFFER_SIZE);
    
    return 0;

err_destroy_class:
    class_destroy(chardev_class);
err_del_cdev:
    cdev_del(&chardev_cdev);
err_unreg_chrdev:
    unregister_chrdev_region(dev_num, 1);
err_free_buffer:
    kfree(dev_data->buffer);
err_free_data:
    kfree(dev_data);
    return ret;
}

static void __exit chardev_exit(void)
{
    pr_info(MODULE_TAG "Unloading module...\n");
    pr_info(MODULE_TAG "Stats - opens: %d, reads: %lu, writes: %lu\n",
            dev_data->open_count, dev_data->read_count, dev_data->write_count);
    
    device_destroy(chardev_class, dev_num);
    class_destroy(chardev_class);
    cdev_del(&chardev_cdev);
    unregister_chrdev_region(dev_num, 1);
    
    mutex_destroy(&dev_data->lock);
    kfree(dev_data->buffer);
    kfree(dev_data);
    
    pr_info(MODULE_TAG "Module unloaded\n");
}

module_init(chardev_init);
module_exit(chardev_exit);
