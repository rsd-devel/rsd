#include "../lib.c"

int main(void){

    volatile char* outputAddr = (char*)0x40002000;
    *outputAddr = 'H';
    *outputAddr = 'e';
    *outputAddr = 'l';
    *outputAddr = 'l';
    *outputAddr = 'o';
    *outputAddr = ',';
    *outputAddr = 'W';
    *outputAddr = 'o';
    *outputAddr = 'r';
    *outputAddr = 'l';
    *outputAddr = 'd';
    *outputAddr = '!';
    *outputAddr = '\n';
    // serial_out_char('H');
    // serial_out_char('e');
    // serial_out_char('l');
    // serial_out_char('l');
    // serial_out_char('o');
    // serial_out_char(',');
    // serial_out_char('W');
    // serial_out_char('o');
    // serial_out_char('r');
    // serial_out_char('l');
    // serial_out_char('d');
    // serial_out_char('!');
    // serial_out_char('\n');
    // serial_out_char('\n');

    return 0;
}
