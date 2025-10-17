    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
    
main:


    addi t3, x0, 1234
    sw t3, 0(sp)        # (sp) = 1234

    addi t1, x0, 24
    sc.w t0, t1, (sp)   # sc (sp)
    beq t0, x0, fail    # must not reserved
    addi t2, x0, 1
    bne t0, t2, fail    # fail code must be 1
    lw t2, 0(sp)
    bne t2, t3, fail    # must not stored

    addi t1, x0, 533
    lr.w t0, (sp)       # reserve
    sc.w t0, t1, (sp)   # store : (sp) = 533
    bne t0, x0, fail    # code must be 0
    lw t0, 0(sp)
    bne t0, t1, fail    # (sp) is not 533

    # reserve is reset
    addi t1, x0, 244
    sc.w t0, t1, (sp)   # store (fail)
    beq t0, x0, fail    # must not reserved

    # set addr
    lui t3, 0x80040

    # store and load check
    addi t1, x0, 1234
    sw t1, 0(t3)               # mem[t3] <= 1234
    lw t2, 0(t3)
    bne t1, t2, fail
    
    # amoswap to uncachable address
    addi t1, x0, 1
    jal t6, flush_stq
    amoswap.w t2, t1, (t3)     # mem[t3] <= 1, t2 = 1234
    
    # amoswap check
    addi t1, x0, 1234
    bne t2, t1, fail           # check t1 == t2 (1234)
    jal t6, flush_stq
    amoswap.w t2, x0, (t3)     # mem[t3] = 0, t2 = 1
    beq t2, x0, fail           # check t2 != 0
    addi t1, x0, 1
    bne t2, t1, fail           # check t2 == t1(1)

    # amoadd
    addi t1, x0, 123
    sw t1, 0(t3)
    addi t2, x0, 32
    amoadd.w t2, t2, (t3) # mem[t3] <= 123 + 32, t2 = 123
    bne t1, t2, fail
    addi t1, t1, 32
    lw t2, 0(t3)
    bne t1, t2, fail


end:
    ret
    #j       end               # ここでループして終了

fail:
    jal x0, fail

flush_stq:
    sw x0, 4(t3)
    sw x0, 8(t3)
    sw x0, 12(t3)
    sw x0, 16(t3)
    sw x0, 20(t3)
    sw x0, 24(t3)
    sw x0, 28(t3)
    sw x0, 32(t3)
    sw x0, 36(t3)
    sw x0, 40(t3)
    sw x0, 44(t3)
    sw x0, 4(t3)
    sw x0, 8(t3)
    sw x0, 12(t3)
    sw x0, 16(t3)
    sw x0, 20(t3)
    sw x0, 24(t3)
    sw x0, 28(t3)
    sw x0, 32(t3)
    sw x0, 36(t3)
    sw x0, 40(t3)
    sw x0, 44(t3)
    sw x0, 4(t3)
    sw x0, 8(t3)
    sw x0, 12(t3)
    sw x0, 16(t3)
    sw x0, 20(t3)
    sw x0, 24(t3)
    sw x0, 28(t3)
    sw x0, 32(t3)
    sw x0, 36(t3)
    sw x0, 40(t3)
    sw x0, 44(t3)
    jalr x0, t6