/*
 * test_chardev.c - Test program for chardev kernel module
 * 
 * Compile: arm-linux-gnueabihf-gcc -o test_chardev test_chardev.c
 * Run:     sudo ./test_chardev
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <errno.h>

#include "chardev.h"

#define DEVICE_PATH "/dev/bbbchar"

void test_write_read(int fd)
{
    char write_buf[] = "Hello from BeagleBone Black!";
    char read_buf[256] = {0};
    ssize_t bytes;
    
    printf("\n=== Test: Write/Read ===\n");
    
    /* Write data */
    bytes = write(fd, write_buf, strlen(write_buf));
    if (bytes < 0) {
        perror("write failed");
        return;
    }
    printf("Wrote %zd bytes: '%s'\n", bytes, write_buf);
    
    /* Seek back to beginning */
    if (lseek(fd, 0, SEEK_SET) < 0) {
        perror("lseek failed");
        return;
    }
    
    /* Read data back */
    bytes = read(fd, read_buf, sizeof(read_buf) - 1);
    if (bytes < 0) {
        perror("read failed");
        return;
    }
    read_buf[bytes] = '\0';
    printf("Read %zd bytes: '%s'\n", bytes, read_buf);
    
    /* Verify */
    if (strcmp(write_buf, read_buf) == 0) {
        printf("✓ Data verified correctly!\n");
    } else {
        printf("✗ Data mismatch!\n");
    }
}

void test_ioctl(int fd)
{
    int size, count;
    
    printf("\n=== Test: IOCTL Commands ===\n");
    
    /* Get buffer size */
    if (ioctl(fd, CHARDEV_IOCGETSIZE, &size) < 0) {
        perror("CHARDEV_IOCGETSIZE failed");
    } else {
        printf("Buffer size: %d bytes\n", size);
    }
    
    /* Get data count */
    if (ioctl(fd, CHARDEV_IOCGETCOUNT, &count) < 0) {
        perror("CHARDEV_IOCGETCOUNT failed");
    } else {
        printf("Data length: %d bytes\n", count);
    }
    
    /* Reset buffer */
    printf("Resetting buffer...\n");
    if (ioctl(fd, CHARDEV_IOCRESET) < 0) {
        perror("CHARDEV_IOCRESET failed");
    } else {
        printf("Buffer reset successful\n");
    }
    
    /* Verify reset */
    if (ioctl(fd, CHARDEV_IOCGETCOUNT, &count) < 0) {
        perror("CHARDEV_IOCGETCOUNT failed");
    } else {
        printf("Data length after reset: %d bytes\n", count);
    }
}

void test_seek(int fd)
{
    char buf[64];
    off_t pos;
    
    printf("\n=== Test: Seek Operations ===\n");
    
    /* Write some data first */
    write(fd, "0123456789ABCDEF", 16);
    
    /* Seek to position 5 */
    pos = lseek(fd, 5, SEEK_SET);
    printf("Seek to position 5: returned %ld\n", (long)pos);
    
    /* Read from position 5 */
    read(fd, buf, 5);
    buf[5] = '\0';
    printf("Read from position 5: '%s'\n", buf);
    
    /* Seek to end */
    pos = lseek(fd, 0, SEEK_END);
    printf("Seek to end: position %ld\n", (long)pos);
    
    /* Seek relative */
    pos = lseek(fd, -3, SEEK_CUR);
    printf("Seek -3 from current: position %ld\n", (long)pos);
}

int main(void)
{
    int fd;
    
    printf("=== BeagleBone Black Character Device Test ===\n");
    printf("Device: %s\n", DEVICE_PATH);
    
    /* Open device */
    fd = open(DEVICE_PATH, O_RDWR);
    if (fd < 0) {
        perror("Failed to open device");
        printf("Make sure the chardev module is loaded:\n");
        printf("  sudo insmod chardev.ko\n");
        return 1;
    }
    printf("Device opened successfully (fd=%d)\n", fd);
    
    /* Run tests */
    test_ioctl(fd);       /* Reset first */
    test_write_read(fd);
    test_ioctl(fd);       /* Check counts */
    
    /* Reset and test seek */
    ioctl(fd, CHARDEV_IOCRESET);
    test_seek(fd);
    
    /* Close device */
    close(fd);
    printf("\nDevice closed. All tests completed!\n");
    
    return 0;
}
