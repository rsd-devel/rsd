#include "../lib.c"

void main(){
    volatile int* hardwareCounterAddr = (int*)0xffffff00;
    volatile char* serial_out = (char*)0x40002000; // memory mapped I/O

    int i;
    int hardwareCounter;

    for(i=0;i<10;i++){
        hardwareCounter = *hardwareCounterAddr;
        serial_out_hex(hardwareCounter);
        serial_out_char('\n');
    }
}
