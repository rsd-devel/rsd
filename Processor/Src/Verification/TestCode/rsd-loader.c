#include <stdint.h>
#include <string.h>

extern void* __data_start;
extern void* __data_end;
extern void* __bss_start;
extern void* __bss_end;

const void* ram_start = 0x80000000;

void* memcpy(void* dest_, const void* src_, size_t n) {
  uint8_t* dest = dest_;
  const uint8_t* src = src_;

  for (size_t i = 0; i < n; i++) {
    dest[i] = src[i];
  }
  return dest;
}

void* memset(void* str_, int c, size_t n) {
  uint8_t* str = str_;
  for (size_t i = 0; i < n; i++) {
    str[i] = (uint8_t)c;
  }
  return str;
}

void _load() {
  memcpy(ram_start, __data_start, __data_end - __data_start);
  memset(__bss_start, 0, __bss_end - __bss_start);
}
