#
# 一時的に lh sw のアライメントあってないアクセスは無効化している
#

    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li      a0, 0x4000
    li      a1, 0x80880008
    li      a2, 0x08808880
    j       main2
end:
    li      a7, 1
end2:
    j       end2
main2:
    sw      a1, 0(a0)            # 0x4000に0x80880008をストアする
    lw      a3, 0(a0)            # a3 <- 0x80880008
    add     a7, a7, a3           # a7=0+0x80880008=0x80880008
    lh      a3, 0(a0)            # a3 <- 0x00000008
    add     a7, a7, a3           # a7=0x80880008+0x00000008=0x80880010
    #lh      a3, 1(a0)            # a3 <- 0xFFFF8800
    #add     a7, a7, a3           # a7=0x80880010+0xFFFF8800=0x80878810
    lh      a3, 2(a0)            # a3 <- 0xFFFF8088
    add     a7, a7, a3           # a7=0x80878810+0xFFFF8088=0x80870898
    lb      a3, 0(a0)            # a3 <- 0x00000008
    add     a7, a7, a3           # a7=0x80870898+0x00000008=0x808708A0
    lb      a3, 1(a0)            # a3 <- 0x00000000
    add     a7, a7, a3           # a7=0x808708A0+0x00000000=0x808708A0
    lb      a3, 2(a0)            # a3 <- 0xFFFFFF88
    add     a7, a7, a3           # a7=0x808708A0+0xFFFFFF88=0x80870828
    lb      a3, 3(a0)            # a3 <- 0xFFFFFF80
    add     a7, a7, a3           # a7=0x80870828+0xFFFFFF80=0x808707A8
    lhu     a3, 0(a0)            # a3 <- 0x00000008
    add     a7, a7, a3           # a7=0x808707A8+0x00000008=0x808707B0
    #lhu     a3, 1(a0)            # a3 <- 0x00008800
    #add     a7, a7, a3           # a7=0x808707B0+0x00008800=0x80878FB0
    lhu     a3, 2(a0)            # a3 <- 0x00008088
    add     a7, a7, a3           # a7=0x80878FB0+0x00008088=0x80881038
    lbu     a3, 0(a0)            # a3 <- 0x00000008
    add     a7, a7, a3           # a7=0x80881038+0x00000008=0x80881040
    lbu     a3, 1(a0)            # a3 <- 0x00000000
    add     a7, a7, a3           # a7=0x80881040+0x00000000=0x80881040
    lbu     a3, 2(a0)            # a3 <- 0x00000088
    add     a7, a7, a3           # a7=0x80881040+0x00000088=0x808810C8
    lbu     a3, 3(a0)            # a3 <- 0x00000080
    add     a7, a7, a3           # a7=0x808810C8+0x00000080=0x80881148
    li      a1, 0x0000FFFF       # a1に0x0000FFFFをストアする
    sw      a6, 0(a0)            # 0x4000に0をストアする
    sh      a1, 0(a0)            # 0x4000から16-bitに0xFFFFをストアする
    lw      a4, 0(a0)            # a4 <- 0x0000FFFF
    add     a7, a7, a4           # a7=0x80881148+0x0000FFFF=0x80891147
    sw      a6, 0(a0)            # 0x4000に0をストアする
    #sh      a1, 1(a0)            # 0x4001から16-bitに0xFFFFをストアする
    lw      a4, 0(a0)            # a4 <- 0x00FFFF00
    add     a7, a7, a4           # a7=0x80891147+0x00FFFF00=0x81891047
    sw      a6, 0(a0)            # 0x4000に0をストアする
    sh      a1, 2(a0)            # 0x4002から16-bitに0xFFFFをストアする
    lw      a4, 0(a0)            # a4 <- 0xFFFF0000
    add     a7, a7, a4           # a7=0x81891047+0xFFFF0000=0x81881047
    sw      a6, 0(a0)            # 0x4000に0をストアする
    sb      a1, 0(a0)            # 0x4000から8-bitに0xFFをストアする
    lw      a4, 0(a0)            # a4 <- 0x000000FF
    add     a7, a7, a4           # a7=0x81881047+0x000000FF=0x81881146
    sw      a6, 0(a0)            # 0x4000に0をストアする
    sb      a1, 1(a0)            # 0x4001から8-bitに0xFFをストアする
    lw      a4, 0(a0)            # a4 <- 0x0000FF00
    add     a7, a7, a4           # a7=0x81881146+0x0000FF00=0x81891046
    sw      a6, 0(a0)            # 0x4000に0をストアする
    sb      a1, 2(a0)            # 0x4002から8-bitに0xFFをストアする
    lw      a4, 0(a0)            # a4 <- 0x00FF0000
    add     a7, a7, a4           # a7=0x81891046+0x00FF0000=0x82881046
    sw      a6, 0(a0)            # 0x4000に0をストアする
    sb      a1, 3(a0)            # 0x4003から8-bitに0xFFをストアする
    lw      a4, 0(a0)            # a4 <- 0xFF000000
    add     a7, a7, a4           # a7=0x82881046+0xFF000000=0x81881046
main3:
    ret
    #j       main3                # ここでループして終了
