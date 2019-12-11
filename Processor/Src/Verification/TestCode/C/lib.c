#define DIGIT_DEC (256)
#define DIGIT_HEX (8)

// シリアル出力のウェイト
#define UART_WAIT 10

// シリアル出力の memory-mapped address
#define SERIAL_ADDRESS 0x40002000

#include <sys/types.h>
void* __attribute((weak)) memcpy(void* dest_, const void* src_, size_t n)
{
  char* dest = dest_;
  const char* src = src_;
  for (size_t i = 0; i < n; i++) dest[i] = src[i];
  return dest;
}

void serial_wait()
{
#ifdef FPGA
    volatile int sum = 0;
    int i;
    for(i=0; i<UART_WAIT; i++) sum += i;
#endif
}

void serial_out_dec(int val)
{
    volatile int *e_txd = (int*)SERIAL_ADDRESS; // memory mapped I/O

    int i;
    int c[DIGIT_DEC];
    int cnt = 0;
    int minus_flag = 0;

    if (val < 0) {
    /* ----- setting + or -  ----- */
        minus_flag = 1;
    /* ----- calclate absolute value ----- */
        val *= -1;
    }

    do {
        c[cnt] = (val % 10) + '0';
        cnt++;
        val = val / 10;
    } while (val != 0);

    if (minus_flag) {
        c[cnt] = '-';
        cnt++;
    }

    for (i = cnt - 1; i >= 0; i--) {
        serial_wait(); *e_txd = c[i];
    }
}

void serial_out_hex(int val)
{
    volatile int *e_txd = (int*)SERIAL_ADDRESS; // memory mapped I/O

    int i;
    int c[DIGIT_HEX];
    int cnt = 0;

    while (cnt < DIGIT_HEX) {
        c[cnt] = ((val & 0x0000000f) == 0)  ? '0' :
                 ((val & 0x0000000f) == 1)  ? '1' :
                 ((val & 0x0000000f) == 2)  ? '2' :
                 ((val & 0x0000000f) == 3)  ? '3' :
                 ((val & 0x0000000f) == 4)  ? '4' :
                 ((val & 0x0000000f) == 5)  ? '5' :
                 ((val & 0x0000000f) == 6)  ? '6' :
                 ((val & 0x0000000f) == 7)  ? '7' :
                 ((val & 0x0000000f) == 8)  ? '8' :
                 ((val & 0x0000000f) == 9)  ? '9' :
                 ((val & 0x0000000f) == 10) ? 'a' :
                 ((val & 0x0000000f) == 11) ? 'b' :
                 ((val & 0x0000000f) == 12) ? 'c' :
                 ((val & 0x0000000f) == 13) ? 'd' :
                 ((val & 0x0000000f) == 14) ? 'e' : 'f';
        cnt++;
        val = val >> 4;
    }

    for (i = cnt - 1; i >= 0; i--) {
        serial_wait(); *e_txd = c[i];
    }
}

void serial_out_char(char val)
{
    volatile char *e_txd = (char*)SERIAL_ADDRESS; // memory mapped I/O
    serial_wait(); *e_txd = val;
}
