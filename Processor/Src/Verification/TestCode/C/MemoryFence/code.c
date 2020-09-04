#include "../lib.c"

int main(void){

    volatile int* timer = (int*)0x40000000;
    int x, y;

    x = *timer;
    *timer = 0;

    rsd_mfence();

    y = *timer;

    volatile char* outputAddr = (char*)0x40002000;
    *outputAddr = 'O';
    *outputAddr = 'k';
    *outputAddr = '\n';

    return 0;
}
