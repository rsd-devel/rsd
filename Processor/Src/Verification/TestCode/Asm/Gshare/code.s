    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    j       main2
main2: 
    addi t0, zero, 0x0          # 誘導変数の初期化
    addi t1, zero, 0x50         # ループ回数

loop1:
    addi t0, t0, 0x1
    bge t0, t1, loop1end        # ループ脱出まで成立しない
    blt t0, t1, loop1           # ループ脱出まで成立する
loop1end:
    addi t0, zero, 0x0          # 誘導変数の初期化
    addi t1, zero, 0x50         # ループ回数
    addi a0, zero, 0x0
    addi a1, zero, 0x0
loop2:
    andi t2, t0, 0x2            # 3回に1回分岐の方向が変わる状況を作る
    beq t2, zero, loop2taken    # (TUUTUUT...)の繰り返し
loop2untaken:
    addi a0, a0, 0x1            
    j loop2judge
loop2taken:
    addi a1, a1, 0x1
loop2judge:
    addi t0, t0, 0x1            # 誘導変数のインクリメント
    bne t0, t1, loop2           # ループを抜けるまで成立

main3:
    ret
    #j       main3                # ここでループして終了
