.file    "code.s" 
    .option nopic 
    .text 
    .align    2 
    .globl    main 
    .type     main, @function 

main:                           # 
    j main2

main1:
    lui a0, 0xa4c5e             # 適当な数をつくり，1ビットずつ比較して分岐させることで
    ori a0, a0, 0x612           # 分岐予測器を間違えさせる

    li t0, 0x80018000           # 0x80018000 から読むと 0x80018000 が取れてくるようにする
    sw t0, 0(t0)

    lw t0, 0(t0)
    lw t0, 0(t0)

loop1:                          # ストアビットの動作検証：命令リカバリ時にストアビットがちゃんと降ろされるか確認
    lw t0, 0(t0)                # 適当に依存関係をつくり，ストアの発行を遅くする
    lw t0, 0(t0)
    lw t0, 0(t0)
    sw t1, 2(t0)                # IQ内に大量のストアが残るようにする．
    sw t1, 4(t0)
    sw t1, 6(t0)
    sw t1, 8(t0)
    sw t1, 10(t0)
    sw t1, 12(t0)
    sw t1, 14(t0)
    sw t1, 16(t0)
    sw t1, 18(t0)

    andi a1, a0, 0x1            # 下位1ビットを取得
    srli a0, a0, 0x1
    bne a1, zero, loop1         # 擬似ランダム分岐
    lw t0, 0(t0)                # ストアの発行を遅くする
    sw t1, 2(t0)                # 分岐予測ミスのリカバリ時にストアビットがちゃんと降ろされるか見る
    sw t1, 4(t0)
    sw t1, 6(t0)
    sw t1, 8(t0)
    sw t1, 10(t0)
    beq a0, zero, main2         # break
    j loop1
    
main2: 
    li t4, 0x80018000           # memory address 0x80018000 
    sw t4, 0(t4)                # 0x80018000 から読むと 0x80018000 が取れてくるようにする
    sw t4, 0x100(t4)            # 
    sw t4, 0x200(t4)            # 
    li a0, 0
    li a1, 0x20                 # loop num 32 
loop2:
    lw t0, 0x0(t4)
    sw t4, 0x0(t0)
    lw t1, 0x0(t4)
    lw t2, 0x100(t4)
    lw t3, 0x200(t4)
    addi a0, a0, 0x1
    beq a0, a1, main3
    j loop2
    
main3: 
    li t4, 0x80018000           # memory address 0x80018000 
    sw t4, 0(t4)                # 0x80018000 から読むと 0x80018000 が取れてくるようにする
    li a0, 0
    li a1, 0x20                 # loop num 32 
loop3:
    lw t0, 0x0(t4)
    sw t4, 0x0(t0)
    lw t1, 0x0(t4)
    lw t2, 0x100(t4)
    lw t3, 0x200(t4)
    addi a0, a0, 0x1
    beq a0, a1, main4
    j loop3
    
main4: 
    li t4, 0x80018000           # memory address 0x80018000 
    sw t4, 0(t4)                # 0x80018000 から読むと 0x80018000 が取れてくるようにする
    li a0, 0
    li a1, 0x20                 # loop num 32 
loop4:
    lw t0, 0x0(t4)
    sw t4, 0x0(t0)
    lw t1, 0x0(t4)
    lw t2, 0x100(t4)
    lw t3, 0x200(t4)
    addi a0, a0, 0x1
    beq a0, a1, main5
    j loop4

main5:
    li a0, 0
    li a1, 0x5              # loop num 32 
    li a2, 0x64
    li a3, 0xa
loop5:
    div t0, a2, a3
    sw t0, 4(t4)
    lw t1, 4(t4)
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
    addi a0, a0, 0x1
    beq a0, a1, main6
    j loop5
    
main6: 
    ret
    #j       main5                # ここでループして終了
