    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li      a0, 0x80018000
    li      a1, 0x0
    li      t3, 0x8001A000
    li      a5, 0x0
    j       stloop

stloop:
    # Store 0, 1, ... 2047 in [0x80018000], [0x80018004], ... [0x80019FFC]
    sw      a1, 0(a0)
    addi    a0, a0, 4
    addi    a1, a1, 1
    bltu    a0, t3, stloop

    # Cache flush
    fence.i

    li      a0, 0x80018000

ldloop:
    # Accumulate 0, 1, ... 2047 in [0x80018000], [0x80018004], ... [0x80019FFC] 
    # a5 finally has 2047*2048/2 = 0x001FFC00
    lw      a1, 0(a0)
    add     a5, a5, a1
    addi    a0, a0, 4
    bltu    a0, t3, ldloop

    # Cherry picking
    li      a0, 0x80018000
    lw      a1, 0(a0)
    li      a0, 0x80019000
    lw      a2, 0(a0)
    li      a0, 0x80018008
    lw      a3, 0(a0)
    li      a0, 0x80018010
    lw      a4, 0(a0)

end:
    ret
    #j       end               # ここでループして終了