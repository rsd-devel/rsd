    .file    "code.s" 
    .option nopic 
    .text 
    .align    2 
    .globl    main 
    .type     main, @function 
main:
    # メモリ初期化
    addi    sp, sp, -48
    sw      zero, 0(sp)
    sw      zero, 16(sp)
    sw      sp, 32(sp)          # 後でポインタとして使う 

    li      x10, 0xff           # 255 （被除数）
    sw      x10, 0(sp)          # いったんメモリに退避
    li      x11, 0x1
    slli    x11, x11, 15        # 2 ^ 15 = 32768 キャッシュのインデクスのちょうど１周分
    sub     x11, sp, x11
    lw      x0, 0(x11)          # スラッシングさせる
    nop                         # キャッシュ・ミスするので，nopを挟んでタイミングを調整
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
depend_to_cache_miss:           # divがキャッシュ・ミスする命令に依存していた場合
    li      x12, 5
    lw      x13, 0(sp)          # 255のリード (スラッシングされているため，ミスになる)
    div     x20, x13, x12       # 255 / 5 = 51 (0x33)
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
depend_to_partial_write_read_miss:# divが複数回リプレイされるキャッシュ・ミスする命令に依存していた場合
    sb      x10, 16(sp)         # 255 を書き込む
    nop
    nop
    lw      x14, 16(sp)         # パーシャルライトをしたアドレスを読むため，2回リプレイされる
    div     x21, x14, x12       # 255 / 5 = 51 (0x33)
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
depend_to_misprediction1:
    lw x15, 0(sp)               # 分岐の実行を遅らせる
    beq x15, x15, target1       # 予測ミスが発生
    div x22, x0, x0             # このdivは発行されるが，フラッシュされる
    div x23, x0, x0
target1:
    div x24, x10, x12           # 正しくフラッシュ処理を終えたら，このdivは発行可能
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

depend_to_misspeculate_mem_order:
    lw      x18, 32(sp)         # キャッシュ・ミス．後続のストアの実行が遅れる
    sw      x10, 0(x18)
    lw      x19, 0(sp)          # 前方のストアと依存があるが，投機的に発行されるため，メモリ順序違反が発生
    div     x25, x10, x12       # 正しくフラッシュ処理がされたら，このdivは発行可能
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
main3: # div, mul が混ざったパターン
    divu x26, x10, x12
    nop
    nop
    nop
    remu x27, x10, x12
    mul x28, zero, zero
    addi zero, zero , 0x0
    addi zero, x27, 0x0
    beq x27, zero, main4
    addi x27, x27, 0x1
    addi x27, x27, 0x1
    nop
    nop
    nop
    nop
    divu x28, x27, x27
    nop
    nop
    remu x29, x27, x27
    mul x30, x27, x27
    nop
    nop
    nop
    nop
    divu x31, x27, x27
    nop
    nop
    nop
    nop
    nop
    nop
    nop

main4:
    divu x31, x10, x12
    ret
    #j       main4                # ここでループして終了 
