    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
    
main:
    # set mtimer/mtimecmp
    li a6, 0x40000000

    li a1, 0
    li a2, 100
    sw a1, 12(a6)   # MEM_MAP_ADDR_TIMER_CMP_HI
    sw a2, 8(a6)    # MEM_MAP_ADDR_TIMER_CMP_LOW

    sw a1, 0(a6)    # MEM_MAP_ADDR_TIMER_LOW
    sw a1, 4(a6)    # MEM_MAP_ADDR_TIMER_HI
    
    # 割り込みハンドラ処理フラグ
    li a1, 0


    # set trap vector
    la a0, trap_vector
    csrrw a0, mtvec, a0
    
    # set mstatus.MIE 
    li  a0, 0x08
    csrrw a0, mstatus, a0
    
    # set mie.MTIE
    li  a0, 0x80    
    csrrw a0, mie, a0
    
    
wait_int:
    beq a1, zero, wait_int  # a1 が書き換わるまで待つ


    # タイマの時間を読む
    lw a3, 0(a6)
    addi a3, a3, 100
wait_read:
    lw a4, 0(a6)
    bge a3, a4, wait_read   # タイマの値が書き換わるまで待つ


    li a3, 0
    li a4, 0
    
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
    nop
    # 割り込みを無効化
    li  a2, 0
    csrrw a2, mstatus, a2

    li a1, 0x77 # 割り込みハンドラを処理したフラグ
    mret


