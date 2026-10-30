#include "../lib.c"

static unsigned int read_cycle(void)
{
    unsigned int value;
    __asm__ volatile ("csrr %0, mcycle" : "=r" (value));
    return value;
}

static unsigned int read_instret(void)
{
    unsigned int value;
    __asm__ volatile ("csrr %0, minstret" : "=r" (value));
    return value;
}

int main(void)
{
    for (int i = 0; i < 10; i++) {
        unsigned int cycles_before = read_cycle();
        unsigned int instructions_before = read_instret();

        // Keep a known amount of work even when the compiler optimizes the test.
        __asm__ volatile (".rept 32\n\tnop\n\t.endr" ::: "memory");

        unsigned int cycles_after = read_cycle();
        unsigned int instructions_after = read_instret();

        // Exact counts depend on timing and code generation. These short runs
        // start after reset and finish well before either 32-bit counter wraps.
        if (cycles_after <= cycles_before)
            return 1;
        if (instructions_after <= instructions_before ||
            instructions_after - instructions_before < 32)
            return 2;
    }

    // Only successful completion produces the expected serial signature.
    serial_out_hex(0);
    serial_out_char('\n');
    serial_flush();
    return 0;
}
