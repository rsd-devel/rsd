#include "../lib.c"

#define WAY_NUM              8
#define DCACHE_LINE_BYTE_NUM 8
#define DCACHE_INDEX_NUM     512 / WAY_NUM
#define ALIGNED_SIZE         DCACHE_LINE_BYTE_NUM * DCACHE_INDEX_NUM
#define ARRAY_SIZE           16

volatile uint8_t array[ALIGNED_SIZE * WAY_NUM] __attribute__ ((aligned (ALIGNED_SIZE)));

uint32_t test() {
    // write
    for (int i = 0; i < ARRAY_SIZE; i += DCACHE_LINE_BYTE_NUM) {
        for (int way = 0; way < WAY_NUM; ++way) {
            array[way * ALIGNED_SIZE + i] = way + 1;
        }
    }

    volatile uint32_t sum = 0;

    // read
    for (int i = 0; i < ARRAY_SIZE; i += DCACHE_LINE_BYTE_NUM) {
        for (int way = 0; way < WAY_NUM; ++way) {
            sum += array[way * ALIGNED_SIZE + i];
        }
    }

    return sum;
}

int main(void) {
    uint32_t ret = test();
    // ((1 + 2 + ... + WAY_NUM) * ARRAY_SIZE / DCACHE_LINE_BYTE_NUM)
    asm volatile ("addi x11, %0, 0" : : "r" (ret));
    return 0;
}
