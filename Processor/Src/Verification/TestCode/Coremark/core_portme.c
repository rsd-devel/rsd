// CoreMark regression port: one iteration with deterministic timing output.
#include "coremark.h"
#include "../C/lib.c"

volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

void start_time(void) {}
void stop_time(void) {}

// Preserve the original functional test's synthetic time, not a benchmark score.
CORE_TICKS get_time(void) { return 10; }
secs_ret time_in_secs(CORE_TICKS ticks) { return ticks; }

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    if (sizeof(ee_ptr_int) != sizeof(void *) || sizeof(ee_u32) != 4) {
        ee_printf("ERROR! Invalid CoreMark data types.\n");
    }
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    p->portable_id = 0;
    serial_flush();
}
