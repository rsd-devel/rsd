#include <stdint.h>
#include <string.h>

extern int __rodata_end;
extern int __data_start;
extern int __data_end;
extern int __bss_start;
extern int __bss_end;

// const void* ram_start = 0x80000000;
#define ram_start 0x80000000

// シリアル出力の memory-mapped address
static const void* SERIAL_ADDRESS = 0x40002000;
static const int DIGIT_DEC = 256;
static const int DIGIT_HEX = 8;

// シリアル出力のウェイト
#define UART_WAIT 10
void __attribute((weak)) serial_wait()
{
#ifdef FPGA
    volatile int sum = 0;
    int i;
    for(i=0; i<UART_WAIT; i++) sum += i;
#endif
}

void __attribute((weak)) serial_out_dec(int val)
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

void __attribute((weak)) serial_out_hex(int val)
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

void __attribute((weak)) serial_out_char(char val)
{
    volatile char *e_txd = (char*)SERIAL_ADDRESS; // memory mapped I/O
    serial_wait(); *e_txd = val;
}

void* __attribute((weak)) memcpy(void* dest_, const void* src_, size_t n) {
  uint8_t* dest = dest_;
  const uint8_t* src = src_;

  for (size_t i = 0; i < n; i++) {
    dest[i] = src[i];
  }
  return dest;
}

void* __attribute((weak)) memset(void* str_, int c, size_t n) {
  uint8_t* str = str_;
  for (size_t i = 0; i < n; i++) {
    str[i] = (uint8_t)c;
  }
  return str;
}

void _load() {
  size_t data_size = (size_t)&__data_end - (size_t)&__data_start;
  size_t bss_size = (size_t)&__bss_end - (size_t)&__bss_start;
  memcpy(ram_start, &__rodata_end, data_size);
  memset(&__bss_start, 0, bss_size);
}
