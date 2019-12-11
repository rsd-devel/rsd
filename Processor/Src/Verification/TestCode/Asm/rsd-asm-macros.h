// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


#ifndef RSD_MACROAS_H
#define RSD_MACROAS_H

#define RSD_SERIAL_ADDR 0x40002000

#define RSD_STRINGIFY(x) #x
#define RSD_TOSTRING(x)  RSD_STRINGIFY(x)

//
// Print a single byte
// This function use a0, t0, t1, ra
//
#define RSD_IO_WRITE_BYTE(_R) \
    .data ;\
    .align 4 ;\
10000: ;\
    .string "0123456789abcdef" ;\
    .text ;\
    ;\
    mv a0, _R ;\
    mv t1, a0          /* copy */ ;\
    /* Print upper nibble*/ ;\
    srli a0, t1, 4 ;\
    andi a0, a0, 0x0f ;\
    la t0, 10000b       /* load a convert table address*/  ;\
    add a0, a0, t0 ;\
    lbu  a0, (a0) ;\
    li t0, RSD_SERIAL_ADDR ;\
    sw a0, 0(t0) ;\
    ;\
    /* Print lower nibble */ ;\
    andi a0, t1, 0x0f ;\
    la t0, 10000b ;\
    add a0, a0, t0 ;\
    lbu  a0, (a0) ;\
    li t0, RSD_SERIAL_ADDR ;\
    sw a0, 0(t0) ;\


/* RSD_IO_WRITE_GPR: t0を破壊 */
#define RSD_IO_WRITE_GPR(_R) \
    .data ;\
    .align 4 ;\
10000: ;\
    .word 0x00000000 ;\
    .word 0x00000000 ;\
    .word 0x00000000 ;\
    .word 0x00000000 ;\
    .text ;\
    ;\
    la t0, 10000b ;\
    sw ra, 0(t0) ;\
    sw a0, 4(t0) ;\
    sw a1, 8(t0) ;\
    ;\
    mv a0, _R ;\
    mv a1, a0          /* copy */ ;\
    srli a0, a0, 24 ;\
    RSD_IO_WRITE_BYTE(a0) ;\
    ;\
    mv a0, a1 ;\
    srli a0, a0, 16 ;\
    RSD_IO_WRITE_BYTE(a0) ;\
    ;\
    mv a0, a1 ;\
    srli a0, a0, 8 ;\
    RSD_IO_WRITE_BYTE(a0) ;\
    ;\
    mv a0, a1 ;\
    RSD_IO_WRITE_BYTE(a0) ;\
    ;\
    la t0, 10000b ;\
    lw ra, 0(t0) ;\
    lw a0, 4(t0) ;\
    lw a1, 8(t0) ;\


// "10000" is local label.
// "10000b" means that search "10000" before this instruction
// "10000f" means that search "10000" after this instruction
#define RSD_IO_WRITE_STR(_STR) \
    .data ;\
    .align 4 ;\
10000: ;\
    .string _STR ;\
    .text ;\
    ;\
    la a0, 10000b ;\
    mv t0, a0; ;\
    li t1, RSD_SERIAL_ADDR ;\
10001: ;\
    lbu  a0, (t0) ;\
    addi t0, t0, 1 ;\
    beq  a0, zero, 10002f ;\
    sw   a0, 0(t1) ;\
    j 10001b ;\
10002: ;\



/* RSD_IO_WRITE_GPR_LINE: t0を破壊 */
#define RSD_IO_WRITE_GPR_LINE(_R) \
    RSD_IO_WRITE_GPR(_R); \
    RSD_IO_WRITE_STR("\n"); \

// Check results
#define RSD_ASSERT_GPR_EQ(_R, _I) \
    li t0, _I ;\
    beq _R, t0, 20000f ;\
    RSD_IO_WRITE_STR("Assertion violation: file ") ;\
    RSD_IO_WRITE_STR(__FILE__)               ;\
    RSD_IO_WRITE_STR(", line ")              ;\
    RSD_IO_WRITE_STR(RSD_TOSTRING(__LINE__))     ;\
    RSD_IO_WRITE_STR(": ")                   ;\
    RSD_IO_WRITE_STR(# _R)                   ;\
    RSD_IO_WRITE_STR("(")                    ;\
    RSD_IO_WRITE_GPR(_R)                      ;\
    RSD_IO_WRITE_STR(") != ")                ;\
    RSD_IO_WRITE_STR(# _I)                   ;\
    RSD_IO_WRITE_STR("\n")                   ;\
20000:  ;\


#endif // RSD_MACROAS_H
