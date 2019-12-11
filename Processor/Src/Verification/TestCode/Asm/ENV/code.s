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
    csrrw a1, mcause, a1
    mret


