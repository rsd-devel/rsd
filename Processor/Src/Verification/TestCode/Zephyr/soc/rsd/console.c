// SPDX-License-Identifier: Apache-2.0
#include <zephyr/init.h>
#include <zephyr/irq.h>
#include <zephyr/sys/libc-hooks.h>
#include <zephyr/sys/printk-hooks.h>
#include "../../../rsd-serial.h"

int arch_printk_char_out(int c)
{
    for (;;) {
        // On this single hart, an interrupt can print between a poll and a store.
        unsigned int key = irq_lock();
        int written = rsd_serial_try_write(c);
        irq_unlock(key);
        if (written) {
            return c;
        }
    }
}

static int rsd_console_init(void)
{
    __printk_hook_install(arch_printk_char_out);
    __stdout_hook_install(arch_printk_char_out);
    return 0;
}

SYS_INIT(rsd_console_init, PRE_KERNEL_1, 0);
