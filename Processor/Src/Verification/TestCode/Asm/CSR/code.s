    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:

    li a1, 0x00
    li a2, 0x03
    li a3, 0x10
    li a4, 0x01
    csrrw a1, mscratch, a2   # a2(0x03) を書き込む
    csrrs a1, mscratch, a3   # a3(0x10) を set
    csrrc a1, mscratch, a4   # a4(0x01) を clear
    csrr  a1, mscratch       # a0 に読み出す（0x12）
    
    csrrwi a5, mscratch, 7   # (0x7) を書き込む
    csrrsi a5, mscratch, 8   # (0x8) を set
    csrrci a5, mscratch, 1   # (0x1) を clear
    csrr   a5, mscratch      # a5 に読み出す（0xe）

    # Check the implemented ISA, including the optional single-precision FPU.
    csrr t0, misa
#ifdef __riscv_flen
    li t1, 0x40141121       # RV32 with I/M/A/F/S/U, without D.
#else
    li t1, 0x40141101       # RV32 with I/M/A/S/U, without F/D.
#endif
    bne t0, t1, fail

    # Software cannot enable unsupported F/D extensions.
    li t2, 0x28
    csrs misa, t2
    csrr t0, misa
    bne t0, t1, fail


    li      a0, 0x400
end:
    ret
    #j       end               # ここでループして終了

fail:
    j fail
