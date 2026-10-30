    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
    
main:
    # Misaligned control transfers must trap at the source instruction.
    la a0, misaligned_trap_vector
    csrw mtvec, a0
    addi sp, sp, -16
    mv a6, sp
    sw zero, 0(a6)
    li a4, 0
    li a5, 0
    li a7, 0x13579bdf
    mv t6, a7

    # JALR must preserve the old link register on an exception.
    la t0, misaligned_jalr
    addi t1, t0, 2
    la t2, after_jalr
misaligned_jalr:
    jalr t6, 0(t1)
    addi a5, a5, 1
    sw a5, 0(a6)
    j fail
after_jalr:

    # The same rule applies when rd == rs1; JALR clears target bit 0.
    la t0, misaligned_jalr_same_reg
    addi t1, t0, 2
    addi t6, t1, 1
    mv a7, t6
    la t2, after_jalr_same_reg
misaligned_jalr_same_reg:
    jalr t6, 0(t6)
    addi a5, a5, 1
    sw a5, 0(a6)
    j fail
after_jalr_same_reg:

    li a7, 0x13579bdf
    mv t6, a7
    la t0, misaligned_jal
    addi t1, t0, 2
    la t2, after_jal
misaligned_jal:
    jal t6, misaligned_jal + 2
    addi a5, a5, 1
    sw a5, 0(a6)
    j fail
after_jal:

    la t0, misaligned_branch
    addi t1, t0, 2
    la t2, after_branch
misaligned_branch:
    beq zero, zero, misaligned_branch + 2
    addi a5, a5, 1
    sw a5, 0(a6)
    j fail
after_branch:
    li t3, 4
    bne a4, t3, fail

    # A branch that is not taken must not raise an alignment exception.
not_taken_branch:
    beq zero, t6, not_taken_branch + 2
    addi a5, a5, 1
    li t3, 1
    bne a5, t3, fail
    li t3, 4
    bne a4, t3, fail
    addi sp, sp, 16
    
    la a0, trap_vector
    csrrw a0, mtvec, a0 
    
    ecall
    mv a2, a1   # mcause = 11
    
    ebreak
    mv a3, a1   # mcause = 3

    li      a0, 0x400
    
end:
    ret
    #j       end               # ここでループして終了


trap_vector:
    nop
    csrr a1, mcause
    # ECALL and EBREAK are both 32-bit instructions; resume after the trap.
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret


misaligned_trap_vector:
    csrr t3, mcause
    csrr t4, mepc
    csrr t5, mtval
    bnez t3, fail
    bne t4, t0, fail
    bne t5, t1, fail
    bne t6, a7, fail
    bnez a5, fail
    lw t3, 0(a6)
    bnez t3, fail
    addi a4, a4, 1
    csrw mepc, t2
    mret

fail:
    j fail


