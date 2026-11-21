#include "../rsd-asm-macros.h"

    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li      x10, 0xFFFFFFFF      # UINT_MAX (4294967295)
    li      x11, 0x0             # UINT_MIN (0)
    li      x12, 0x7FFFFFFF      # INT_MAX (2147483647)
    li      x13, 0x80000000      # INT_MIN (-2147483648)
    j       main2
end:
    li      a7, 1
end2:
    j       end2
main2:
    mul     x14, x12, x12        # (s*s) INT_MAX*INT_MAX   = 0x3FFF FFFF 0000 0001
    mul     x15, x12, x13        # (s*s) INT_MAX*INT_MIN   = 0xC000 0000 8000 0000
    mul     x16, x13, x12        # (s*s) INT_MIN*INT_MAX   = 0xC000 0000 8000 0000
    mul     x17, x13, x13        # (s*s) INT_MIN*INT_MIN   = 0x4000 0000 0000 0000
    mulh    x18, x12, x12        # (s*s) INT_MAX*INT_MAX   = 0x3FFF FFFF 0000 0001
    mulh    x19, x12, x13        # (s*s) INT_MAX*INT_MIN   = 0xC000 0000 8000 0000
    mulh    x20, x13, x12        # (s*s) INT_MIN*INT_MAX   = 0xC000 0000 8000 0000
    mulh    x21, x13, x13        # (s*s) INT_MIN*INT_MIN   = 0x4000 0000 0000 0000
    mulhsu  x22, x12, x10        # (s*u) INT_MAX*UINT_MAX  = 0x7FFF FFFE 8000 0001
    mulhsu  x23, x12, x11        # (s*u) INT_MAX*UINT_MIN  = 0x0000 0000 0000 0000
    mulhsu  x24, x13, x10        # (s*u) INT_MIN*UINT_MAX  = 0x8000 0000 8000 0000
    mulhsu  x25, x13, x11        # (s*u) INT_MIN*UINT_MIN  = 0x0000 0000 0000 0000
    mulhu   x26, x10, x10        # (u*u) UINT_MAX*UINT_MAX = 0xFFFF FFFE 0000 0001
    mulhu   x27, x10, x11        # (u*u) UINT_MAX*UINT_MIN = 0x0000 0000 0000 0000
    mulhu   x28, x11, x10        # (u*u) UINT_MIN*UINT_MAX = 0x0000 0000 0000 0000
    mulhu   x29, x11, x11        # (u*u) UINT_MIN*UINT_MIN = 0x0000 0000 0000 0000
    nop
output:
    RSD_IO_DUMP_GPRS(x31)
main3:
    ret
    #j       main3                # ここでループして終了
