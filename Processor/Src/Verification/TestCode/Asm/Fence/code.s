    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:

    li      a1, 0
    addi    a1, a1, 1
    addi    a1, a1, 1

    # fence のテスト
    fence iorw, iorw
    addi    a1, a1, 1
    addi    a1, a1, 1   # 間に通常の命令を挟む
    fence.i
    addi    a1, a1, 1   # 間に通常の命令を挟む
    fence.i
    addi    a1, a1, 1

    # 分岐予測ミス中にフェンス
    j label_0   
    addi    a1, a1, 1
label_0:
    fence.i



    # csrr rd, csr csrrs rd, csr, x0 Read CSR
    # csrw csr, rs csrrw x0, csr, rs Write CSR
    # csrs csr, rs csrrs x0, csr, rs Set bits in CSR
    # csrc csr, rs csrrc x0, csr, rs Clear bits in CSR
    # csrwi csr, imm csrrwi x0, csr, imm Write CSR, immediate
    # csrsi csr, imm csrrsi x0, csr, imm Set bits in CSR, immediate
    # csrci csr, imm csrrci x0, csr, imm Clear bits in CSR, immediate


    li      a0, 0x400

end:
    ret
    #j       end               # ここでループして終了
