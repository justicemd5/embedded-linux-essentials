/*
 * Falcon Mode A/B Slot Selection for BeagleBone Black
 * 
 * Add this code to board/ti/am335x/board.c
 * Enables SPL to select between A/B slots and provides
 * fallback to full U-Boot via USER button.
 *
 * SPDX-License-Identifier: GPL-2.0+
 */

#ifdef CONFIG_SPL_OS_BOOT
#include <common.h>
#include <spl.h>
#include <asm/gpio.h>
#include <environment.h>

/* 
 * USER button on BeagleBone Black
 * GPIO2_8 = (2 * 32) + 8 = 72
 * Active LOW (pressed = 0)
 */
#define FALCON_RECOVERY_GPIO    72

/* Partition numbers for A/B slots */
#define BOOT_PART_A     1
#define BOOT_PART_B     3
#define ROOT_PART_A     2
#define ROOT_PART_B     5

/**
 * spl_start_uboot() - Decide whether to start full U-Boot
 *
 * This function is called by SPL to determine if it should
 * boot the kernel directly (Falcon mode) or load full U-Boot.
 *
 * Returns:
 *   0 - Proceed with Falcon boot (boot kernel directly)
 *   1 - Start full U-Boot
 */
int spl_start_uboot(void)
{
    int recovery_pressed;
    
    /* Initialize GPIO */
    gpio_request(FALCON_RECOVERY_GPIO, "falcon_recovery");
    gpio_direction_input(FALCON_RECOVERY_GPIO);
    
    /* Read button state (active LOW) */
    recovery_pressed = !gpio_get_value(FALCON_RECOVERY_GPIO);
    
    gpio_free(FALCON_RECOVERY_GPIO);
    
    if (recovery_pressed) {
        printf("SPL: USER button pressed, starting U-Boot\n");
        return 1;  /* Start full U-Boot for recovery/maintenance */
    }
    
    /* Check if Falcon mode is enabled */
    char *falcon_enabled = env_get("falcon_enabled");
    if (!falcon_enabled || falcon_enabled[0] != '1') {
        printf("SPL: Falcon mode disabled, starting U-Boot\n");
        return 1;
    }
    
    printf("SPL: Falcon mode active\n");
    return 0;  /* Proceed with Falcon boot */
}

/**
 * spl_board_prepare_for_linux() - Prepare board for kernel boot
 *
 * Called just before SPL jumps to the kernel. Used here to
 * log which slot we're booting from.
 */
void spl_board_prepare_for_linux(void)
{
    char *slot = env_get("falcon_slot");
    
    if (!slot || (slot[0] != 'a' && slot[0] != 'b')) {
        slot = "a";  /* Default to slot A */
        printf("SPL: Invalid falcon_slot, defaulting to A\n");
    }
    
    printf("SPL: Falcon booting from slot %s\n", slot);
    
    /* Additional board-specific preparation can go here */
}

/**
 * spl_board_get_boot_device() - Override boot partition for Falcon
 *
 * This function can be used to dynamically select the boot partition
 * based on the active slot. Implementation depends on U-Boot version.
 */
#ifdef CONFIG_SPL_MMC_SUPPORT
/*
 * For newer U-Boot versions, you may need to implement
 * spl_boot_partition() or modify spl_mmc_boot_partition()
 * in common/spl/spl_mmc.c
 */
int spl_mmc_boot_partition(const u32 boot_device)
{
    char *slot = env_get("falcon_slot");
    
    if (slot && slot[0] == 'b') {
        return BOOT_PART_B;  /* Boot partition B */
    }
    return BOOT_PART_A;  /* Boot partition A */
}
#endif

/*
 * Helper function to get root partition for bootargs
 * Can be called from board_late_init() if needed
 */
int get_ab_root_partition(void)
{
    char *slot = env_get("falcon_slot");
    
    if (slot && slot[0] == 'b') {
        return ROOT_PART_B;
    }
    return ROOT_PART_A;
}

#endif /* CONFIG_SPL_OS_BOOT */
