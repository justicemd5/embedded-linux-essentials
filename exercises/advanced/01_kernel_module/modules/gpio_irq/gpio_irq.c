/*
 * gpio_irq.c - GPIO Interrupt Handler Module for BeagleBone Black
 * 
 * This module demonstrates:
 * - GPIO configuration using new gpiod API
 * - Interrupt handling (IRQ)
 * - Debouncing techniques
 * - Workqueue usage for bottom-half processing
 * 
 * Default GPIO: P9_12 (GPIO1_28) - commonly used for buttons
 * 
 * Author: Embedded Linux Labs
 * License: GPL v2
 * Target: BeagleBone Black (AM335x Cortex-A8)
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/workqueue.h>
#include <linux/timer.h>
#include <linux/jiffies.h>

#define MODULE_TAG "gpio_irq: "

/* Debounce time in milliseconds */
#define DEBOUNCE_MS 50

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Embedded Linux Labs");
MODULE_DESCRIPTION("GPIO Interrupt Handler for BeagleBone Black");
MODULE_VERSION("1.0");

/* Module parameters */
static int gpio_num = 60;  /* GPIO1_28 = 32 + 28 = 60 (P9_12) */
module_param(gpio_num, int, 0644);
MODULE_PARM_DESC(gpio_num, "GPIO number to use (default: 60 = P9_12)");

/* Device data */
struct gpio_irq_data {
    struct gpio_desc *gpio;
    int irq;
    unsigned long irq_count;
    unsigned long last_irq_jiffies;
    struct work_struct work;
    struct timer_list debounce_timer;
    bool debounce_pending;
    spinlock_t lock;
};

static struct gpio_irq_data *gpio_data;

/* ============= Work Queue Handler ============= */

static void gpio_work_handler(struct work_struct *work)
{
    struct gpio_irq_data *data = container_of(work, struct gpio_irq_data, work);
    int value;
    
    /* Read current GPIO value */
    value = gpiod_get_value(data->gpio);
    
    pr_info(MODULE_TAG "GPIO event processed - value: %d, count: %lu\n",
            value, data->irq_count);
    
    /* 
     * This is where you would do your actual work:
     * - Update state machine
     * - Send event to userspace
     * - Trigger other actions
     */
}

/* ============= Debounce Timer Handler ============= */

static void debounce_timer_handler(struct timer_list *t)
{
    struct gpio_irq_data *data = from_timer(data, t, debounce_timer);
    unsigned long flags;
    
    spin_lock_irqsave(&data->lock, flags);
    data->debounce_pending = false;
    spin_unlock_irqrestore(&data->lock, flags);
    
    /* Schedule work after debounce period */
    schedule_work(&data->work);
}

/* ============= Interrupt Handler ============= */

static irqreturn_t gpio_irq_handler(int irq, void *dev_id)
{
    struct gpio_irq_data *data = (struct gpio_irq_data *)dev_id;
    unsigned long flags;
    
    spin_lock_irqsave(&data->lock, flags);
    
    data->irq_count++;
    data->last_irq_jiffies = jiffies;
    
    /* Simple debouncing: ignore interrupts if timer is pending */
    if (!data->debounce_pending) {
        data->debounce_pending = true;
        mod_timer(&data->debounce_timer, jiffies + msecs_to_jiffies(DEBOUNCE_MS));
    }
    
    spin_unlock_irqrestore(&data->lock, flags);
    
    return IRQ_HANDLED;
}

/* ============= Sysfs Interface ============= */

static ssize_t irq_count_show(struct device *dev,
                               struct device_attribute *attr,
                               char *buf)
{
    return sprintf(buf, "%lu\n", gpio_data->irq_count);
}

static ssize_t gpio_value_show(struct device *dev,
                                struct device_attribute *attr,
                                char *buf)
{
    int value = gpiod_get_value(gpio_data->gpio);
    return sprintf(buf, "%d\n", value);
}

static DEVICE_ATTR_RO(irq_count);
static DEVICE_ATTR_RO(gpio_value);

static struct attribute *gpio_irq_attrs[] = {
    &dev_attr_irq_count.attr,
    &dev_attr_gpio_value.attr,
    NULL,
};

static struct attribute_group gpio_irq_attr_group = {
    .attrs = gpio_irq_attrs,
};

/* ============= Module Init/Exit ============= */

static struct class *gpio_irq_class;
static struct device *gpio_irq_device;

static int __init gpio_irq_init(void)
{
    int ret;
    
    pr_info(MODULE_TAG "Loading module...\n");
    pr_info(MODULE_TAG "Using GPIO %d\n", gpio_num);
    
    /* Allocate device data */
    gpio_data = kzalloc(sizeof(*gpio_data), GFP_KERNEL);
    if (!gpio_data) {
        pr_err(MODULE_TAG "Failed to allocate device data\n");
        return -ENOMEM;
    }
    
    spin_lock_init(&gpio_data->lock);
    INIT_WORK(&gpio_data->work, gpio_work_handler);
    timer_setup(&gpio_data->debounce_timer, debounce_timer_handler, 0);
    
    /* Request GPIO */
    ret = gpio_request(gpio_num, "gpio_irq_button");
    if (ret) {
        pr_err(MODULE_TAG "Failed to request GPIO %d: %d\n", gpio_num, ret);
        goto err_free_data;
    }
    
    /* Get GPIO descriptor */
    gpio_data->gpio = gpio_to_desc(gpio_num);
    if (!gpio_data->gpio) {
        pr_err(MODULE_TAG "Failed to get GPIO descriptor\n");
        ret = -ENODEV;
        goto err_free_gpio;
    }
    
    /* Configure as input */
    ret = gpiod_direction_input(gpio_data->gpio);
    if (ret) {
        pr_err(MODULE_TAG "Failed to set GPIO direction: %d\n", ret);
        goto err_free_gpio;
    }
    
    /* Get IRQ for GPIO */
    gpio_data->irq = gpiod_to_irq(gpio_data->gpio);
    if (gpio_data->irq < 0) {
        pr_err(MODULE_TAG "Failed to get IRQ for GPIO: %d\n", gpio_data->irq);
        ret = gpio_data->irq;
        goto err_free_gpio;
    }
    
    pr_info(MODULE_TAG "GPIO %d mapped to IRQ %d\n", gpio_num, gpio_data->irq);
    
    /* Request IRQ - trigger on both edges */
    ret = request_irq(gpio_data->irq, gpio_irq_handler,
                      IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING,
                      "gpio_irq_button", gpio_data);
    if (ret) {
        pr_err(MODULE_TAG "Failed to request IRQ: %d\n", ret);
        goto err_free_gpio;
    }
    
    /* Create sysfs class and device */
    gpio_irq_class = class_create("gpio_irq");
    if (IS_ERR(gpio_irq_class)) {
        ret = PTR_ERR(gpio_irq_class);
        goto err_free_irq;
    }
    
    gpio_irq_device = device_create(gpio_irq_class, NULL, 0, NULL, "gpio_irq");
    if (IS_ERR(gpio_irq_device)) {
        ret = PTR_ERR(gpio_irq_device);
        goto err_destroy_class;
    }
    
    ret = sysfs_create_group(&gpio_irq_device->kobj, &gpio_irq_attr_group);
    if (ret) {
        goto err_destroy_device;
    }
    
    pr_info(MODULE_TAG "Module loaded successfully\n");
    pr_info(MODULE_TAG "IRQ handler registered for GPIO %d\n", gpio_num);
    pr_info(MODULE_TAG "Sysfs entries at /sys/class/gpio_irq/gpio_irq/\n");
    
    return 0;

err_destroy_device:
    device_destroy(gpio_irq_class, 0);
err_destroy_class:
    class_destroy(gpio_irq_class);
err_free_irq:
    free_irq(gpio_data->irq, gpio_data);
err_free_gpio:
    gpio_free(gpio_num);
err_free_data:
    kfree(gpio_data);
    return ret;
}

static void __exit gpio_irq_exit(void)
{
    pr_info(MODULE_TAG "Unloading module...\n");
    pr_info(MODULE_TAG "Total IRQ count: %lu\n", gpio_data->irq_count);
    
    sysfs_remove_group(&gpio_irq_device->kobj, &gpio_irq_attr_group);
    device_destroy(gpio_irq_class, 0);
    class_destroy(gpio_irq_class);
    
    del_timer_sync(&gpio_data->debounce_timer);
    cancel_work_sync(&gpio_data->work);
    
    free_irq(gpio_data->irq, gpio_data);
    gpio_free(gpio_num);
    kfree(gpio_data);
    
    pr_info(MODULE_TAG "Module unloaded\n");
}

module_init(gpio_irq_init);
module_exit(gpio_irq_exit);
