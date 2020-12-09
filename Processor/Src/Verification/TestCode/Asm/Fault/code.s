    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
    
main:

    # set trap vector
    la a0, trap_vector
    csrrw a0, mtvec, a0
    
    li a1, 0
    
    # Access violation
    li a2, 0xcdcd0000
    sw zero, 0(a2)
    
    
    li      a0, 0x400
end:
    ret
    #j       end               # ここでループして終了
    

    # 連続しているとわかりにくいので間をあける
    nop
    nop
    nop
    nop

trap_vector:
    li a0, 0x40002000   # UART
    
    # "access vilation"
    li t0, 'a'
    sb t0, (a0)

    li t0, 'c'
    sb t0, (a0)

    li t0, 'c'
    sb t0, (a0)

    li t0, 'e'
    sb t0, (a0)

    li t0, 's'
    sb t0, (a0)

    li t0, 's'
    sb t0, (a0)

    li t0, ' '
    sb t0, (a0)

    li t0, 'v'
    sb t0, (a0)

    li t0, 'i'
    sb t0, (a0)

    li t0, 'o'
    sb t0, (a0)

    li t0, 'l'
    sb t0, (a0)

    li t0, 'a'
    sb t0, (a0)

    li t0, 't'
    sb t0, (a0)

    li t0, 'i'
    sb t0, (a0)

    li t0, 'o'
    sb t0, (a0)

    li t0, 'n'
    sb t0, (a0)
    
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    
    # 戻り先を4進めておく
    csrrw a0, mepc, a0
    addi a0, a0, 4
    csrrw a0, mepc, a0

    mret


