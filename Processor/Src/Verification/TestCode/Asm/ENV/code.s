    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
    
main:
    
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


