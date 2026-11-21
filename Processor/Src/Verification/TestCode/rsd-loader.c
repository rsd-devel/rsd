#include <stdint.h>
#include <stddef.h>

// Linker symbols are byte addresses, not aligned C objects.
extern uint8_t __data_load_start[];
extern uint8_t __data_start[];
extern uint8_t __data_end[];
extern uint8_t __bss_start[];
extern uint8_t __bss_end[];

// With -O3, GCC can widen these byte loops to word loads/stores when aligned.
// The linker aligns the .data ROM/RAM starts and .bss to four bytes; keeping
// byte semantics also handles unaligned pointers and trailing bytes safely.
static void* _rsd_memcpy(void* dest_, const void* src_, size_t n) {
    uint8_t* dest = dest_;
    const uint8_t* src = src_;

    for (size_t i = 0; i < n; i++) {
        dest[i] = src[i];
    }
    return dest;
}

static void* _rsd_memset(void* str_, int c, size_t n) {
    uint8_t* str = str_;
    for (size_t i = 0; i < n; i++) {
        str[i] = (uint8_t)c;
    }
    return str;
}

void _load() {
    // The core function of the RSD loader called at the very beggining of run time.
    // It copies data in .data and .sdata sections from ROM to RAM
    // and sets 0 in .bss and .sbss sections in RAM.
    size_t data_size = (size_t)__data_end - (size_t)__data_start;
    size_t bss_size = (size_t)__bss_end - (size_t)__bss_start;
    _rsd_memcpy(__data_start, __data_load_start, data_size);
    _rsd_memset(__bss_start, 0, bss_size);
}
