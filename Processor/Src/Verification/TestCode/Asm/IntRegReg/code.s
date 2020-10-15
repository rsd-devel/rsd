    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li      a0, 0xFFFFFFFF
    li      a1, 1
    j       main2
end:
    li      a7, 1
end2:
    j       end2
main2:
    add     a2, a0, a1           # a2はオーバーフローして0に
    add     a7, a7, a2           # a7=0+0=0
    sub     a2, a2, a1           # a2=0-1=-1
    add     a7, a7, a2           # a7=0+(-1)=-1
    sub     a2, a1, a2           # a2=1-(-1)=2
    add     a7, a7, a2           # a7=-1+2=1
    slt     a3, a1, a2           # 1<2でa3=1
    add     a7, a7, a3           # a7=1+1=2
    slt     a3, a2, a7           # 2<2でa3=0
    add     a7, a7, a3           # a7=2+0=2
    slt     a3, a0, a1           # -1<1でa3=1
    add     a7, a7, a3           # a7=2+1=3
    sltu    a3, a1, a2           # 1<2でa3=1
    add     a7, a7, a3           # a7=3+1=4
    sltu    a3, a1, a1           # 1<1でa3=0
    add     a7, a7, a3           # a7=4+0=4
    sltu    a3, a0, a1           # 0xFFFFFFFF<1でa3=0
    add     a7, a7, a3           # a7=4+0=4
    and     a4, a0, a1           # a4=1
    add     a7, a7, a4           # a7=4+1=5
    or      a4, a7, a2           # a4=5|2=7
    add     a7, a7, a4           # a7=5+7=12
    xor     a4, a7, a2           # a4=0x1100^0x0010=0x1110=14
    add     a7, a7, a4           # a7=12+14=26
    sll     a5, a1, a2           # a5=1<<2=4
    add     a7, a7, a5           # a7=26+4=30
    srl     a5, a2, a1           # a5=2>>1=1
    add     a7, a7, a5           # a7=30+1=31
    srl     a5, a0, a1           # a5=0xFFFFFFFF>>1=0x7FFFFFFF
    add     a7, a7, a5           # a7=31+0x7FFFFFFF=0x8000001E
    sra     a5, a1, a1           # a5=1>>1=0
    add     a7, a7, a5           # a7=0x8000001E+0=0x8000001E
    sra     a5, a0, a1           # a5=0xFFFFFFFF>>1=0xFFFFFFFF
    add     a7, a7, a5           # a7=0x8000001E+0xFFFFFFFF=0x8000001D
    nop
main3:
    ret
    #j       main3                # ここでループして終了
