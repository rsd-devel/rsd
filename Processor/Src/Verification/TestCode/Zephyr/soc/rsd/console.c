// SPDX-License-Identifier: Apache-2.0
#include <zephyr/init.h>
#include <zephyr/sys/libc-hooks.h>
#include <zephyr/sys/printk-hooks.h>

/* RSD has a write-only character register, with no UART status registers. */
int arch_printk_char_out(int c)
{
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    *(volatile unsigned char *)0x40002000 = (unsigned char)c;
    return c;
}

static int rsd_console_init(void)
{
    __printk_hook_install(arch_printk_char_out);
    __stdout_hook_install(arch_printk_char_out);
    return 0;
}

SYS_INIT(rsd_console_init, PRE_KERNEL_1, 0);
