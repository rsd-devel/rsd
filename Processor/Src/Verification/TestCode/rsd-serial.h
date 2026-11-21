#ifndef RSD_SERIAL_H
#define RSD_SERIAL_H

#include "rsd-memory-map.h"

#define RSD_SERIAL_TX_FULL 1

// RSD serializes each MMIO load and drains older stores before reading STATUS.
// This orders the OUTPUT write between successive polls without a per-byte fence.
#ifdef __ASSEMBLER__
// Register-dump tests also expect _TMP to contain OUTPUT on return.
#define RSD_SERIAL_PUTC(_VALUE, _TMP) \
900: li _TMP, RSD_SERIAL_STATUS; \
    lw _TMP, 0(_TMP); \
    andi _TMP, _TMP, RSD_SERIAL_TX_FULL; \
    bnez _TMP, 900b; \
    li _TMP, RSD_SERIAL_OUTPUT; \
    sw _VALUE, 0(_TMP)
#else
// Callers with concurrent writers must serialize this check and store.
static inline int rsd_serial_try_write(unsigned char byte)
{
    if (*(const volatile unsigned int *)RSD_SERIAL_STATUS & RSD_SERIAL_TX_FULL)
        return 0;
    *(volatile unsigned char *)RSD_SERIAL_OUTPUT = byte;
    return 1;
}
#endif

#endif
