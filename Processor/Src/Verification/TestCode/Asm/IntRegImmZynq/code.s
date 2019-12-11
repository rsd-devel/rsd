    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li      a0, 0xFFFFFFFF
    j       main2
end:
    li      a7, 1
end2:
    j       end2
main2:
    addi    a1, a0, 1            # a1はオーバーフローして0に
    add     a7, a7, a1           # a7=0+0=0
    addi    a1, a1, -1           # addiで12-bitの最大値(0xFFF)を与えると符号拡張されて0xFFFFFFFFになるから実質これは0に-1して結果は-1
    add     a7, a7, a1           # a7=0+(-1)=0xFFFFFFFF
    slti    a2, a1, 0            # a1は-1のはずだから-1<0でa2は1
    add     a7, a7, a2           # a7=0xFFFFFFFF+1=0
    slti    a2, a1, -1           # a1は-1のはずだから-1=-1でa2は0
    add     a7, a7, a2           # a7=0+0=0
    sltiu   a3, a1, 0            # a1は0xFFFFFFFFだから0xFFFFFFFF>0でa3は0
    add     a7, a7, a3           # a7=0+0=0
    sltiu   a3, a1, -1           # a1は0xFFFFFFFFだから0xFFFFFFFF=0xFFFFFFFFでa3は0
    add     a7, a7, a3           # a7=0+0=0
    andi    a4, a1, 1            # a4は0xFFFFFFFFと1のANDで1に
    add     a7, a7, a4           # a7=0+1=1
    andi    a4, a1, -1           # a4は0xFFFFFFFFと0xFFFFFFFFのANDで0xFFFFFFFFに
    add     a7, a7, a4           # a7=1+(-1)=0
    ori     a4, a1, 0            # a4は0xFFFFFFFFと0のORで0xFFFFFFFFに
    add     a7, a7, a4           # a7=0+(-1)=0xFFFFFFFF
    ori     a4, a3, -1           # a4は0と0xFFFFFFFFのORで0xFFFFFFFFに
    add     a7, a7, a4           # a7=0xFFFFFFFF+(-1)=0xFFFFFFFE
    xori    a4, a1, 0            # a4は0xFFFFFFFFと0のXORで0xFFFFFFFFに
    add     a7, a7, a4           # a7=0xFFFFFFFE+(-1)=0xFFFFFFFD
    xori    a4, a1, -1           # a4は0xFFFFFFFFと0xFFFFFFFFのXORで0に
    add     a7, a7, a4           # a7=0xFFFFFFFD(-3)+0=0xFFFFFFFD(-3)
    addi    a5, a5, 1
    slli    a5, a5, 2            # a5は1*4=4
    add     a7, a7, a5           # a7=-3+4=1
    srli    a5, a5, 1            # a5は4/2=2
    add     a7, a7, a5           # a7=1+2=3
    srli    a5, a1, 1            # a5は0x7FFFFFFF(MAX_INT)
    add     a7, a7, a5           # a7=3+0x7FFFFFFF=0x80000002
    srai    a5, a1, 1            # a5は0xFFFFFFFF
    add     a7, a7, a5           # a7=0x80000002+0xFFFFFFFF=0x80000001
    lui     a6, 1                # a6=8192
    add     a7, a7, a6           # a7=0x80000001+0x1000=0x80001001
    #auipc   a6, 0                # a6に次のPCをコピー
output:
    li      t3, 0x40002000
    sw      x0, 0(t3)
    sw      x1, 0(t3)
    sw      x2, 0(t3)
    sw      x3, 0(t3)
    sw      x4, 0(t3)
    sw      x5, 0(t3)
    sw      x6, 0(t3)
    sw      x7, 0(t3)
    sw      x8, 0(t3)
    sw      x9, 0(t3)
    sw      x10, 0(t3)
    sw      x11, 0(t3)
    sw      x12, 0(t3)
    sw      x13, 0(t3)
    sw      x14, 0(t3)
    sw      x15, 0(t3)
    sw      x16, 0(t3)
    sw      x17, 0(t3)
    sw      x18, 0(t3)
    sw      x19, 0(t3)
    sw      x20, 0(t3)
    sw      x21, 0(t3)
    sw      x22, 0(t3)
    sw      x23, 0(t3)
    sw      x24, 0(t3)
    sw      x25, 0(t3)
    sw      x26, 0(t3)
    sw      x27, 0(t3)
    sw      x28, 0(t3)
    sw      x29, 0(t3)
    sw      x30, 0(t3)
    sw      x31, 0(t3)

main3:
    ret
    #j       main3                # ここでループして終了
