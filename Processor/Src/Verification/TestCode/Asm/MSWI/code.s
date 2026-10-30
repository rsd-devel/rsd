    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function

main:

    li a1, 1
    li a6, 0x40010000
    sw a1, 0(a6)    # msip

    # 割り込みハンドラ処理フラグ
    li a1, 0

    # set trap vector
    la a0, trap_vector
    csrrw a0, mtvec, a0
    
    # set mstatus.MIE 
    li a0, 0x08
    csrrw a0, mstatus, a0
    
    # set mie.MSIE
    li a0, 0x08    
    csrrw a0, mie, a0
    
wait_int:
    beq a1, zero, wait_int  # a1 が書き換わるまで待つ

msip_is_zero:
    lw a4, 0(a6)
    bne x0, a4, msip_is_zero

    li a3, 0
    li a4, 0
    
    li a0, 0x400
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
    # msip をクリア
    sw x0, 0(a6)

    li a1, 0x77 # 割り込みハンドラを処理したフラグ
    mret


