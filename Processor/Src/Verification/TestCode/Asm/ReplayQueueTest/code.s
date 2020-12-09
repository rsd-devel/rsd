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
    j       initialize

end:
    li      a7, 0
    li      t4, 0
end2:
    j       end2

initialize:
    li      a1, 0x80880008
    li      a2, 0x08808880

    li  a0, -0x10000
    add a0, sp, a0
    li  a5, 0xcdcdcdcd
    sw a5, 0(a0)    # 0x00
    sw a5, 0x10(a0) # 0x10
    sw a5, 0x20(a0) # 0x20
    sw a5, 0x24(a0) # 0x24
    sw a5, 0x30(a0) # 0x30
    sw a5, 0x34(a0) # 0x34
    sw a5, 0x38(a0) # 0x38

    li  a0, -0xf000
    add a0, sp, a0
    li  a5, 0xcdcdcdcd
    sw a5, 0(a0)    # 0x00
    sw a5, 0x10(a0) # 0x10
    sw a5, 0x20(a0) # 0x20
    sw a5, 0x24(a0) # 0x24
    sw a5, 0x30(a0) # 0x30
    sw a5, 0x34(a0) # 0x34
    sw a5, 0x38(a0) # 0x38
    
    
    #li      a5, 0x40000
    #li      a6, 0x48000
    li  a5, -0x8000
    add a5, sp, a5
    mv a6, sp
    sw  a5, 0(a5)

warmup:
    addi    a5, a5, 4
    sw      a5, 0(a5)
    bltu    a5, a6, warmup
    
    #li      a0, 0x30000
    li  a0, -0x10000
    add a0, sp, a0

    li      a5, 0
    li      a6, 1
    j       main2
second:
    li      a7, 0
    li      a1, 0x80880008
    #li      a0, 0x31000
    li  a0, -0xF000
    add a0, sp, a0

    addi    a5, a5, 1

main2:
    sw      a1, 0(a0)            # (sp-0x10000)に0x80880008をストアする このストアを起点としてStore-Load forwardingテスト
    addi    t4, t4, 1            # 起点ストアが実行されるまで到達するまで適当な命令を入れる
    addi    t4, t4, 1            # 起点ストアが実行されるまで到達するまで適当な命令を入れる
    addi    t4, t4, 1            # 起点ストアが実行されるまで到達するまで適当な命令を入れる
    addi    t4, t4, 1            # 起点ストアが実行されるまで到達するまで適当な命令を入れる
    lw      a3, 0(a0)            # a3 <- 0x80880008 起点ストアと同じエントリへのロード フォワーディング可能
    add     a7, a7, a3           # a7=0+0x80880008=0x80880008
    lh      a3, 0(a0)            # a3 <- 0x00000008 フォワーディング可能
    add     a7, a7, a3           # a7=0x80880008+0x00000008=0x80880010
    #lh      a3, 1(a0)            # a3 <- 0xFFFF8800 フォワーディング可能
    #add     a7, a7, a3           # a7=0x80880010+0xFFFF8800=0x80878810
    lh      a3, 2(a0)            # a3 <- 0xFFFF8088 フォワーディング可能
    add     a7, a7, a3           # a7=0x80878810+0xFFFF8088=0x80870898
    lb      a3, 0(a0)            # a3 <- 0x00000008 フォワーディング可能
    add     a7, a7, a3           # a7=0x80870898+0x00000008=0x808708A0
    lb      a3, 1(a0)            # a3 <- 0x00000000 フォワーディング可能
    add     a7, a7, a3           # a7=0x808708A0+0x00000000=0x808708A0
    lb      a3, 2(a0)            # a3 <- 0xFFFFFF88 フォワーディング可能
    add     a7, a7, a3           # a7=0x808708A0+0xFFFFFF88=0x80870828
    lb      a3, 3(a0)            # a3 <- 0xFFFFFF80 フォワーディング可能
    add     a7, a7, a3           # a7=0x80870828+0xFFFFFF80=0x808707A8
    lhu     a3, 0(a0)            # a3 <- 0x00000008 フォワーディング可能
    add     a7, a7, a3           # a7=0x808707A8+0x00000008=0x808707B0
    #lhu     a3, 1(a0)            # a3 <- 0x00008800 フォワーディング可能
    #add     a7, a7, a3           # a7=0x808707B0+0x00008800=0x80878FB0
    lhu     a3, 2(a0)            # a3 <- 0x00008088 フォワーディング可能
    add     a7, a7, a3           # a7=0x80878FB0+0x00008088=0x80881038
    lbu     a3, 0(a0)            # a3 <- 0x00000008 フォワーディング可能
    add     a7, a7, a3           # a7=0x80881038+0x00000008=0x80881040
    lbu     a3, 1(a0)            # a3 <- 0x00000000 フォワーディング可能
    add     a7, a7, a3           # a7=0x80881040+0x00000000=0x80881040
    lbu     a3, 2(a0)            # a3 <- 0x00000088 フォワーディング可能
    add     a7, a7, a3           # a7=0x80881040+0x00000088=0x808810C8
    lbu     a3, 3(a0)            # a3 <- 0x00000080 起点ストアと同じエントリへのロード フォワーディング可能　Store-Load forwardingテストここまで
    
    
    add     a7, a7, a3           # a7=0x808810C8+0x00000080=0x80881148 
    li      a1, 0x0000FFFF       # a1に0x0000FFFFをストアする
    add     a7, a7, a1           # a7=0x80881148+0x0000FFFF=0x80891147
    addi    a0, a0, 16           # アクセス対象を次のキャッシュラインに
    sh      a1, 0(a0)            # (sp-0x10000+0x10)から16-bitに0xFFFFをストアする このストアを起点としてLoadのSB一部ヒットによるミステスト
    addi    a0, a0, 1            # 起点ストアがコミットステージまで到達するまで適当な命令を入れる
    addi    a0, a0, -1           # 起点ストアがコミットステージまで到達するまで適当な命令を入れる
    addi    a0, a0, 1            # 起点ストアがコミットステージまで到達するまで適当な命令を入れる
    addi    a0, a0, -1           # 起点ストアがコミットステージまで到達するまで適当な命令を入れる
    addi    a0, a0, 1            # 起点ストアがコミットステージまで到達するまで適当な命令を入れる
    addi    a0, a0, -1           # 起点ストアがコミットステージまで到達するまで適当な命令を入れる
    addi    a0, a0, 1            # 起点ストアがコミットステージまで到達するまで適当な命令を入れる
    addi    a0, a0, -1           # 起点ストアがコミットステージまで到達するまで適当な命令を入れる
    lw      a4, 0(a0)            # a4 <- 0xCDCDFFFF　起点ストアと同じエントリへのロード フォワーディング不可能 LoadのSB一部ヒットによるミステストトここまで
    addi    a0, a0, 1            # ここまでの命令がすべてコミットされるまで適当な命令を入れる
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 16           # アクセス対象を次のキャッシュラインに
    li      a1, 0xFFFF0000       # a1に0xFFFF0000をストアする
    sw      a1, 0(a0)            # (sp-0x10000+0x20)に0xFFFF0000をストアする このストアを起点として次のLoadはMSHR割り当て->このswがMSHRにヒット
    addi    t3, a0, 4            # 起点ストアが実行されるまで適当な命令を入れる
    lw      t4, 0(t3)            # t4 <- 0xCDCDCDCD
    add     a7, a7, a4           # a7=0x80891147+0xCDCDFFFF=0x4E571146
    add     a7, a7, t4           # a7=0x4E571146+0xCDCDCDCD=0x1C24DF13
    addi    a0, a0, 16           # アクセス対象を次のキャッシュラインに
    addi    a0, a0, 1            # ここまでの命令がすべてコミットされるまで適当な命令を入れる
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    lw      a4, 0(a0)            # a4 <- 0xCDCDCDCD このロードを起点に後続ロードのMSHRヒット，MSHRからのロードテスト
    addi    a0, a0, 4
    lw      a2, 0(a0)            # a2 <- 0xCDCDCDCD 起点ロードによって割り当てられたMSHRにヒット
    addi    a0, a0, 4
    lw      t3, 0(a0)            # t3 <- 0xCDCDCDCD 起点ロードによって割り当てられたMSHRにヒット　ロードの後続ロードのMSHRヒット，MSHRからのロードテストここまで
    add     a7, a7, a4           # a7=0x1C24DF13+0xCDCDCDCD=0xE9F2ACE0
    add     a7, a7, a2           # a7=0xE9F2ACE0+0xCDCDCDCD=0xB7C07AAD
    add     a7, a7, t3           # a7=0xB7C07AAD+0xCDCDCDCD=0x858E487A
    addi    a0, a0, 1            # ここまでの命令がすべてコミットされるまで適当な命令を入れる
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    addi    a0, a0, 1            # 適当な命令
    addi    a0, a0, -1           # 適当な命令
    bltu    a5, a6, second
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