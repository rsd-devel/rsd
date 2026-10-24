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

    # LR faults are load exceptions; SC and AMO faults are store/AMO exceptions.
    la t4, trap_vector
    csrrw a0, mtvec, t4
    li a3, 0x13579bdf
    mv a2, a3
    li a5, 0x11223344
    li a6, 0x55667788
    sw a5, 0(sp)
    sw a6, 4(sp)
    sw a5, 8(sp)
    li a1, 0x80040000
    sw a5, 0(a1)
    sw a6, 4(a1)
    sw a5, 8(a1)
    li a7, 0

    # Check all three misaligned offsets for a word access.
    li a4, 1
misaligned_lr_loop:
    add t1, sp, a4
    la t0, misaligned_lr
    la t2, after_misaligned_lr
    li t3, 4
misaligned_lr:
    lr.w a2, (t1)
    j fail
after_misaligned_lr:
    addi a4, a4, 1
    li t4, 4
    bltu a4, t4, misaligned_lr_loop

    li a4, 1
misaligned_sc_loop:
    add t1, sp, a4
    la t0, misaligned_sc
    la t2, after_misaligned_sc
    li t3, 6
misaligned_sc:
    sc.w a2, a5, (t1)
    j fail
after_misaligned_sc:
    addi a4, a4, 1
    li t4, 4
    bltu a4, t4, misaligned_sc_loop

    # An unmapped address must also report the correct access-fault class.
    li t1, 0xcdcd0000
    la t0, unmapped_lr
    la t2, after_unmapped_lr
    li t3, 5
unmapped_lr:
    lr.w a2, (t1)
    j fail
after_unmapped_lr:
    la t0, unmapped_sc
    la t2, after_unmapped_sc
    li t3, 7
unmapped_sc:
    sc.w a2, a5, (t1)
    j fail
after_unmapped_sc:

    # Include offsets that cross the current eight-byte cache-line boundary.
    li a4, 1
misaligned_amo_loop:
    add t1, sp, a4
    la t0, misaligned_amo
    la t2, after_misaligned_amo
    li t3, 6
misaligned_amo:
    amoadd.w a2, a5, (t1)
    j fail
after_misaligned_amo:
    addi a4, a4, 1
    li t4, 4
    bne a4, t4, misaligned_amo_next
    addi a4, a4, 1
misaligned_amo_next:
    li t4, 8
    bltu a4, t4, misaligned_amo_loop

    li a4, 1
misaligned_uncached_amo_loop:
    add t1, a1, a4
    la t0, misaligned_uncached_amo
    la t2, after_misaligned_uncached_amo
    li t3, 6
misaligned_uncached_amo:
    amoadd.w a2, a5, (t1)
    j fail
after_misaligned_uncached_amo:
    addi a4, a4, 1
    li t4, 4
    bne a4, t4, misaligned_uncached_amo_next
    addi a4, a4, 1
misaligned_uncached_amo_next:
    li t4, 8
    bltu a4, t4, misaligned_uncached_amo_loop

unmapped_amo_setup:
    li t1, 0xcdcd0000
    la t0, unmapped_amo
    la t2, after_unmapped_amo
    li t3, 7
unmapped_amo:
    amoadd.w a2, a5, (t1)
    j fail
after_unmapped_amo:
    # Discarding the result must not suppress the exception.
    la t0, unmapped_amo_zero_rd
    la t2, after_unmapped_amo_zero_rd
unmapped_amo_zero_rd:
    amoswap.w zero, a5, (t1)
    j fail
after_unmapped_amo_zero_rd:
    li t4, 22
    bne a7, t4, fail

    # Valid cached and uncached AMOs must still succeed after the faults.
    li t4, 1
    amoadd.w a2, t4, (sp)
    bne a2, a5, fail
    addi t5, a5, 1
    lw t4, 0(sp)
    bne t4, t5, fail
    li t4, 1
    amoadd.w a2, t4, (a1)
    bne a2, a5, fail
    lw t4, 0(a1)
    bne t4, t5, fail
    csrw mtvec, a0
    li a0, 0
    li a1, 0

end:
    ret
    #j       end               # ここでループして終了

fail:
    jal x0, fail

trap_vector:
    csrr t4, mcause
    csrr t5, mepc
    csrr t6, mtval
    bne t4, t3, fail
    bne t5, t0, fail
    bne t6, t1, fail
    # Neither the destination register nor memory may change on a fault.
    bne a2, a3, fail
    lw t4, 0(sp)
    bne t4, a5, fail
    lw t4, 4(sp)
    bne t4, a6, fail
    lw t4, 8(sp)
    bne t4, a5, fail
    lw t4, 0(a1)
    bne t4, a5, fail
    lw t4, 4(a1)
    bne t4, a6, fail
    lw t4, 8(a1)
    bne t4, a5, fail
    addi a7, a7, 1
    csrw mepc, t2
    mret

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