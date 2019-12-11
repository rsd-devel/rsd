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
    li      x31, 0x40002000
    sw      x0, 0(x31)
    sw      x1, 0(x31)
    sw      x2, 0(x31)
    sw      x3, 0(x31)
    sw      x4, 0(x31)
    sw      x5, 0(x31)
    sw      x6, 0(x31)
    sw      x7, 0(x31)
    sw      x8, 0(x31)
    sw      x9, 0(x31)
    sw      x10, 0(x31)
    sw      x11, 0(x31)
    sw      x12, 0(x31)
    sw      x13, 0(x31)
    sw      x14, 0(x31)
    sw      x15, 0(x31)
    sw      x16, 0(x31)
    sw      x17, 0(x31)
    sw      x18, 0(x31)
    sw      x19, 0(x31)
    sw      x20, 0(x31)
    sw      x21, 0(x31)
    sw      x22, 0(x31)
    sw      x23, 0(x31)
    sw      x24, 0(x31)
    sw      x25, 0(x31)
    sw      x26, 0(x31)
    sw      x27, 0(x31)
    sw      x28, 0(x31)
    sw      x29, 0(x31)
    sw      x30, 0(x31)
    sw      x31, 0(x31)
main3:
    ret
    #j       main3                # ここでループして終了
