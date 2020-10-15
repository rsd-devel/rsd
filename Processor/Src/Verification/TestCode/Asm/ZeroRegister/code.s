    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li      a0, 0x400
    li      a1, 0x80880008
    li      a2, 0x08808880
    j       main2
end:
    li      a7, 1
end2:
    j       end2
main2:
    xori    zero, a1, 0x0       # RegImm ゼロレジスタ代入
    andi    a3, zero, 0xffffffff  # RegImm ゼロレジスタ参照
    or      zero, a0, a1        # RegReg ゼロレジスタ代入
    add     a2, zero, a1        # RegReg ゼロレジスタ参照
    auipc   zero, 0x1000        # auipc ゼロレジスタ代入
    andi    a4, zero, 0xffffffff  # RegImm ゼロレジスタ参照
    lui     zero, 0x1111        # lui ゼロレジスタ代入
    andi    a5, zero, 0xffffffff  # RegImm ゼロレジスタ参照
    jal     zero, main3         # jal ゼロレジスタ代入
end3:
    j       end3
main3:
    addi    a0, sp, -4          # メモリ保存位置
    andi    a6, zero, 0xffffffff  # RegImm ゼロレジスタ参照
    
    sw      a1, 0(a0)           # メモリ定数作成
    lw      zero, 0(a0)         # load ゼロレジスタ代入
    sw      zero, 0(a0)         # store ゼロレジスタ参照
    
    #lw      a7, 0x400(zero)     # load ゼロレジスタ参照
    #lw      s2, 0x400(zero)     # load ゼロレジスタ参照
end4:
    ret
    #j       end4               # ここでループして終了
