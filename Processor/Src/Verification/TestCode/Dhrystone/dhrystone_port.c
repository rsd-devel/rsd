// Dhrystone 2.1 functional test with a minimal RSD host interface.
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include "../C/lib.c"

static char *dhrystone_malloc(size_t);
static long dhrystone_time(long *);
static int dhrystone_printf(const char *, ...);

// Use the upstream source unchanged, replacing only its host entry points.
#define main dhrystone_main
#define malloc dhrystone_malloc
#define time dhrystone_time
#define printf dhrystone_printf
#include "dhry_1.c"
#undef main
#undef malloc
#undef time
#undef printf

static Rec_Type records[2];
static unsigned int allocated, checked;
static int port_failed;
#if RSD_BENCHMARK
static unsigned int timer_calls, start_cycle, measured_cycles;
#endif

// These six locals are available through the upstream final report.
// Require every entry to be reported; format changes must not skip checks.
static const struct {
    const char *format;
    int integer;
    const char *string;
} local_results[] = {
    {"Int_1_Loc:           %d\n", 5, NULL},
    {"Int_2_Loc:           %d\n", 13, NULL},
    {"Int_3_Loc:           %d\n", 7, NULL},
    {"Enum_Loc:            %d\n", Ident_2, NULL},
    {"Str_1_Loc:           %s\n", 0, "DHRYSTONE PROGRAM, 1'ST STRING"},
    {"Str_2_Loc:           %s\n", 0, "DHRYSTONE PROGRAM, 2'ND STRING"},
};
#define LOCAL_RESULT_COUNT (sizeof(local_results) / sizeof(local_results[0]))

// Match the legacy char * declaration; only its two records are supported.
static char *dhrystone_malloc(size_t size)
{
    if (size != sizeof(Rec_Type) || allocated >= 2) {
        port_failed = 1;
        return NULL;
    }
    return (char *)&records[allocated++];
}

// Synthetic time keeps the upstream code out of its performance-score path.
static long dhrystone_time(long *result)
{
#if RSD_BENCHMARK
    unsigned int cycle;
    __asm__ volatile ("csrr %0, mcycle" : "=r" (cycle) :: "memory");
    if (timer_calls++ == 0) start_cycle = cycle;
    else measured_cycles = cycle - start_cycle;
#endif
    if (result) *result = 0;
    return 0;
}

// Check reported locals and suppress the host-oriented benchmark output.
static int dhrystone_printf(const char *format, ...)
{
    unsigned int i;
    for (i = 0; i < LOCAL_RESULT_COUNT; ++i) {
        if (strcmp(format, local_results[i].format) == 0) {
            va_list args;
            va_start(args, format);
            if (local_results[i].string) {
                port_failed |= strcmp(va_arg(args, char *), local_results[i].string) != 0;
            } else {
                port_failed |= va_arg(args, int) != local_results[i].integer;
            }
            va_end(args);
            checked |= 1u << i;
            break;
        }
    }
    return 0;
}

int main(void)
{
    allocated = checked = 0;
    port_failed = 0;
#if RSD_BENCHMARK
    timer_calls = 0;
#endif
    // The legacy main has no defined return value; validate its results below.
    dhrystone_main();
    int failed = port_failed || allocated != 2 ||
        checked != (1u << LOCAL_RESULT_COUNT) - 1 ||
        Int_Glob != 5 || Bool_Glob != 1 ||
        Ch_1_Glob != 'A' || Ch_2_Glob != 'B' ||
        Arr_1_Glob[8] != 7 || Arr_2_Glob[8][7] != DHRY_ITERS + 10 ||
        Ptr_Glob->Ptr_Comp != Next_Ptr_Glob ||
        Ptr_Glob->Discr != Ident_1 ||
        Ptr_Glob->variant.var_1.Enum_Comp != Ident_3 ||
        Ptr_Glob->variant.var_1.Int_Comp != 17 ||
        strcmp(Ptr_Glob->variant.var_1.Str_Comp,
               "DHRYSTONE PROGRAM, SOME STRING") != 0 ||
        Next_Ptr_Glob->Ptr_Comp != Next_Ptr_Glob ||
        Next_Ptr_Glob->Discr != Ident_1 ||
        Next_Ptr_Glob->variant.var_1.Enum_Comp != Ident_2 ||
        Next_Ptr_Glob->variant.var_1.Int_Comp != 18 ||
        strcmp(Next_Ptr_Glob->variant.var_1.Str_Comp,
               "DHRYSTONE PROGRAM, SOME STRING") != 0;
#if RSD_BENCHMARK
    failed |= timer_calls != 2;
#endif
    const char *message = failed ? "Dhrystone failed\n" : "The program ran correctly\n";
    while (*message) serial_out_char(*message++);
#if RSD_BENCHMARK
    if (!failed) {
        message = "RSD benchmark: iterations=";
        while (*message) serial_out_char(*message++);
        serial_out_dec(DHRY_ITERS);
        message = " cycles=0x";
        while (*message) serial_out_char(*message++);
        serial_out_hex(measured_cycles);
        serial_out_char('\n');
    }
#endif
    serial_flush();
    return failed;
}
