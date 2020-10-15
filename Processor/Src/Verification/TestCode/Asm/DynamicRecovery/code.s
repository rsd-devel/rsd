    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li a1, 0x20             # ループ回数
    lui a2, 0x35c54         # 分岐結果をランダムにさせるための適当な変数
    ori a2, a2, 0x535
    li a3, 0x0              # ループ変数

    li a0, 0x80018000       # 0x80018000 から読むと 0x80018000 が取れてくるようにする
    sw a0, 0(a0)
    
loop1:
    lw t0, 0x0(a0)          # 直列に依存関係をつくり，実行を遅らせる．
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    lw t0, 0x0(t0)
    addi t1, zero, 0x1      # 上のロード命令とオーバラップして実行
    addi t2, t1, 0x1        # 適当に依存をつけてみる
    andi t4, a2, 0x1        # ランダム変数の下位１ビットを取得
    addi t0, t0, 0x1        # 発行が遅い命令（上のロードに対して依存）
    bne t4, zero, forward   # この分岐結果は擬似ランダム
    addi t3, t2, 0x1        # forwardラベルまで適当な命令をいれる
    addi t3, t3, 0x1
    addi t3, t3, 0x1
    addi t3, t3, 0x1
    addi t3, t3, 0x1
    addi t3, t3, 0x1
forward:
    addi t3, t2, 0x1        # bneの直前(2個前)の命令に依存
    addi a3, a3, 0x1        # ループ変数のインクリメント
    addi t0, t0, 0x1        # 上にある発行が遅い命令に対して依存
    srli a2, a2, 0x1        # ランダム変数を右にシフト
    blt a3, a1, loop1       # 特定の回数だけループ

output:
    li      a6, 0x40002000
    sw      x0, 0(a6)
    sw      x1, 0(a6)
    sw      x2, 0(a6)
    sw      x3, 0(a6)
    sw      x4, 0(a6)
    sw      x5, 0(a6)
    sw      x6, 0(a6)
    sw      x7, 0(a6)
    sw      x8, 0(a6)
    sw      x9, 0(a6)
    sw      x10, 0(a6)
    sw      x11, 0(a6)
    sw      x12, 0(a6)
    sw      x13, 0(a6)
    sw      x14, 0(a6)
    sw      x15, 0(a6)
    sw      x16, 0(a6)
    sw      x17, 0(a6)
    sw      x18, 0(a6)
    sw      x19, 0(a6)
    sw      x20, 0(a6)
    sw      x21, 0(a6)
    sw      x22, 0(a6)
    sw      x23, 0(a6)
    sw      x24, 0(a6)
    sw      x25, 0(a6)
    sw      x26, 0(a6)
    sw      x27, 0(a6)
    sw      x28, 0(a6)
    sw      x29, 0(a6)
    sw      x30, 0(a6)
    sw      x31, 0(a6)
fin:
    #j     fin
    ret
