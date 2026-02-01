/*
 * chardev.h - Header file for chardev userspace programs
 * 
 * Include this header in userspace programs to use ioctl commands
 */

#ifndef _CHARDEV_H_
#define _CHARDEV_H_

#include <linux/ioctl.h>

/* IOCTL command definitions */
#define CHARDEV_IOC_MAGIC 'B'

/* Reset the buffer to zeros */
#define CHARDEV_IOCRESET    _IO(CHARDEV_IOC_MAGIC, 0)

/* Get buffer size (returns int) */
#define CHARDEV_IOCGETSIZE  _IOR(CHARDEV_IOC_MAGIC, 1, int)

/* Set buffer size (takes int) - not implemented */
#define CHARDEV_IOCSETSIZE  _IOW(CHARDEV_IOC_MAGIC, 2, int)

/* Get current data length (returns int) */
#define CHARDEV_IOCGETCOUNT _IOR(CHARDEV_IOC_MAGIC, 3, int)

#endif /* _CHARDEV_H_ */
