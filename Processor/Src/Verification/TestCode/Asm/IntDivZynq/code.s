    .file    "code.s" 
    .option nopic 
    .text 
    .align    2 
    .globl    main 
    .type     main, @function 
main: 
    mv      x22, x1     # save SP
    
    li      x1, 0x7FFFFFFF      # INT_MAX (2147483647) 
    li      x2, 0x80000000      # INT_MIN (-2147483648) 
    li      x3, 0xFFFFFFFF      # UINT_MAX (4294967295) 
    li      x4, 0x00000000      # UINT_MIN (0)

div_check:      # The validity of division is checked by serial output
    div     x5, x1, x1          # INT_MAX / INT_MAX
    div     x6, x1, x2          # INT_MAX / INT_MIN
    div     x7, x2, x1          # INT_MIN / INT_MAX
    div     x8, x2, x2          # INT_MIN / INT_MIN
    divu    x9, x1, x3          # INT_MAX / UINT_MAX
    divu    x10, x1, x4         # INT_MIN / UINT_MIN
    divu    x11, x2, x3         # INT_MIN / UINT_MAX
    divu    x12, x2, x4         # INT_MIN / UINT_MIN
    divu    x13, x3, x1         # UINT_MAX / INT_MAX
    divu    x14, x3, x2         # UINT_MAX / INT_MIN
    divu    x15, x4, x1         # UINT_MIN / INT_MAX
    divu    x16, x4, x2         # UINT_MIN / INT_MIN
    divu    x17, x3, x3         # UINT_MAX / UINT_MAX
    divu    x18, x3, x4         # UINT_MAX / UINT_MIN
    divu    x19, x4, x3         # UINT_MIN / UINT_MAX
    divu    x20, x4, x4         # UINT_MIN / UINT_MIN

output:
    li      x31, 0x40002000
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

rem_check:     # The validity of remainder is checked by register value
    rem     x5, x1, x1          # INT_MAX % INT_MAX
    rem     x6, x1, x2          # INT_MAX % INT_MIN
    rem     x7, x2, x1          # INT_MIN % INT_MAX
    rem     x8, x2, x2          # INT_MIN % INT_MIN
    remu    x9, x1, x3          # INT_MAX % UINT_MAX
    remu    x10, x1, x4         # INT_MAX % UINT_MIN
    remu    x11, x2, x3         # INT_MIN % UINT_MAX
    remu    x12, x2, x4         # INT_MIN % UINT_MIN
    remu    x13, x3, x1         # UINT_MAX % INT_MAX
    remu    x14, x3, x2         # UINT_MAX % INT_MIN
    remu    x15, x4, x1         # UINT_MIN % INT_MAX
    remu    x16, x4, x2         # UINT_MIN % INT_MIN
    remu    x17, x3, x3         # UINT_MAX % UINT_MAX
    remu    x18, x3, x4         # UINT_MAX % UINT_MIN
    remu    x19, x4, x3         # UINT_MIN % UINT_MAX
    remu    x20, x4, x4         # UINT_MIN % UINT_MIN

wait_store_complete:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

main3: 
    jr x22  # mv x22, x1 (x1=sp) より，呼び出し元にもどる
    #j       main3              # ここでループして終了 
