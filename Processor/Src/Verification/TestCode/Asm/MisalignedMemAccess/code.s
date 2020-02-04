
    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function

#include "../rsd-asm-macros.h"

main:
    # RSD_IO_WRITE_STR("MisalignedMemAccess test start\n")
    addi sp, sp, -12
    sw   ra, 8(sp)
    # set trap vector
    la a0, trap_vector
    csrrw a0, mtvec, a0
    
    li a1, 0
    mv a3, sp
    
    # Memory Init
    li a2, 0xDEADBEEF       #
    sw a2, 0(a3)            # [0xEF, 0xBE, 0xAD, 0xDE]
    li a4, 0xBAADF00D       # 
    sw a4, 4(a3)            # [0x0D, 0xF0, 0xAD, 0xBA]
    
    # Load Access
    RSD_IO_WRITE_STR("test lw-1\n")
    lw a5, 1(a3)            # a5 <- 0x0DDEADBE
    RSD_ASSERT_GPR_EQ(a5, 0x0DDEADBE)
    RSD_IO_WRITE_STR("\n")
    
    RSD_IO_WRITE_STR("test lw-2\n")
    lw a6, 2(a3)            # a6 <- 0xF00DDEAD
    RSD_ASSERT_GPR_EQ(a6, 0xF00DDEAD)
    RSD_IO_WRITE_STR("\n")
    
    RSD_IO_WRITE_STR("test lw-3\n")
    lw a7, 3(a3)            # a7 <- 0xADF00DDE
    RSD_ASSERT_GPR_EQ(a7, 0xADF00DDE)
    RSD_IO_WRITE_STR("\n")

    RSD_IO_WRITE_STR("test lhu-1\n")
    lhu s0, 1(a3)            # s0 <- 0x0000ADBE
    RSD_ASSERT_GPR_EQ(s0, 0xADBE)
    RSD_IO_WRITE_STR("\n")

    RSD_IO_WRITE_STR("test lhu-2\n")
    lhu s1, 3(a3)            # s0 <- 0x00000DDE
    RSD_ASSERT_GPR_EQ(s1, 0x0DDE)
    RSD_IO_WRITE_STR("\n")

    RSD_IO_WRITE_STR("test lh-1\n")
    lh s2, 1(a3)
    RSD_ASSERT_GPR_EQ(s2, 0xFFFFADBE)
    RSD_IO_WRITE_STR("\n")

    RSD_IO_WRITE_STR("test lh-2\n")
    lh s3, 3(a3)
    RSD_ASSERT_GPR_EQ(s3, 0x0DDE)
    RSD_IO_WRITE_STR("\n")

    
    # Store Access
    RSD_IO_WRITE_STR("test sw-1\n")
    li t6, 0x12345678
    sw t6, 1(a3)            # [0xEF, 0x78, 0x56, 0x34] [0x12, 0xF0, 0xAD, 0xBA]
    lw t1, 0(a3)
    RSD_ASSERT_GPR_EQ(t1, 0x345678EF)
    lw t1, 4(a3)
    RSD_ASSERT_GPR_EQ(t1, 0xBAADF012)
    RSD_IO_WRITE_STR("\n")

    RSD_IO_WRITE_STR("test sw-2\n")
    li t6, 0x090a0b0c
    sw t6, 2(a3)            # [0xEF, 0x78, 0x0C, 0x0B] [0x0A, 0x09, 0xAD, 0xBA]
    lw t1, 0(a3)
    RSD_ASSERT_GPR_EQ(t1, 0x0B0C78EF)
    lw t1, 4(a3)
    RSD_ASSERT_GPR_EQ(t1, 0xBAAD090A)
    RSD_IO_WRITE_STR("\n")

    RSD_IO_WRITE_STR("test sw-3\n")
    li t6, 0xF0E0D000
    sw t6, 3(a3)            # [0xEF, 0x78, 0x0C, 0x00] [0xD0, 0xE0, 0xF0, 0xBA]
    lw t1, 0(a3)
    RSD_ASSERT_GPR_EQ(t1, 0x000C78EF)
    lw t1, 4(a3)
    RSD_ASSERT_GPR_EQ(t1, 0xBAF0E0D0)
    RSD_IO_WRITE_STR("\n")
    
    RSD_IO_WRITE_STR("test sh-1\n")
    li t6, 0xFFEE
    sh t6, 1(a3)            # [0xEF, 0xEE, 0xFF, 0x00] [0xD0, 0xE0, 0xF0, 0xBA]
    lw t1, 0(a3)
    RSD_ASSERT_GPR_EQ(t1, 0x00FFEEEF)
    RSD_IO_WRITE_STR("\n")

    RSD_IO_WRITE_STR("test sh-2\n")
    li t6, 0xFEED
    sh t6, 3(a3)            # [0xEF, 0xEE, 0xFF, 0xED] [0xFE, 0xE0, 0xF0, 0xBA]
    lw t1, 0(a3)
    RSD_ASSERT_GPR_EQ(t1, 0xEDFFEEEF)
    lw t1, 4(a3)
    RSD_ASSERT_GPR_EQ(t1, 0xBAF0E0FE)
    RSD_IO_WRITE_STR("\n")


    li      a0, 0x400
end:
    lw   ra, 8(sp)
    addi sp, sp, 12
    ret
    

    # 連続しているとわかりにくいので間をあける
    nop
    nop
    nop
    nop


trap_vector:
    addi sp, sp, -128           # スタック確保

    sw x0, 0(sp)                # レジスタ退避
    sw x1, 4(sp)
    sw x2, 8(sp)
    sw x3, 12(sp)
    sw x4, 16(sp)
    sw x5, 20(sp)
    sw x6, 24(sp)
    sw x7, 28(sp)
    sw x8, 32(sp)
    sw x9, 36(sp)
    sw x10, 40(sp)
    sw x11, 44(sp)
    sw x12, 48(sp)
    sw x13, 52(sp)
    sw x14, 56(sp)
    sw x15, 60(sp)
    sw x16, 64(sp)
    sw x17, 68(sp)
    sw x18, 72(sp)
    sw x19, 76(sp)
    sw x20, 80(sp)
    sw x21, 84(sp)
    sw x22, 88(sp)
    sw x23, 92(sp)
    sw x24, 96(sp)
    sw x25, 100(sp)
    sw x26, 104(sp)
    sw x27, 108(sp)
    sw x28, 112(sp)
    sw x29, 116(sp)
    sw x30, 120(sp)
    sw x31, 124(sp)

    RSD_IO_WRITE_STR("trap_vector!\n")

    # a0に例外を起こした命令のPCを入れ，戻り先を4進めておく
    csrrw a0, mepc, a1
    addi a1, a0, 4
    csrrw a1, mepc, a1

    # 
    csrrw a2, mcause, a2        # a2 にmcause を入れる
    andi a2, a2, 0xf            # mcauseの下位4bitだけを見る．reservedな値は知らない
    lw a3, 0(a0)                # a3 に例外起こした命令を入れる
    li t0, 4                    # LOAD_MISALIGNED = 4
    beq a2, t0, unaligned_load
    li t0, 6                    # STORE_MISALIGNED = 6
    beq a2, t0, unaligned_store

    RSD_IO_WRITE_STR("invalid mcause!: ")
    RSD_IO_WRITE_GPR_LINE(a2)
    RSD_IO_WRITE_STR("PC: ")
    RSD_IO_WRITE_GPR_LINE(a0)
fail:
    j fail                      # failしたらループ

unaligned_load:
    srli t0, a3, 7
    andi a4, t0, 31             # a4 <- rd
    srli t0, t0, 5
    andi a5, t0, 7              # a5 <- 1(lh)/2(lw)/5(lhu)
    csrrw a7, mbadaddr, a7      # a7 <- addr

    li t0, 1
    beq a5, t0, unaligned_lh
    li t0, 5
    beq a5, t0, unaligned_lhu
    li t0, 2
    beq a5, t0, unaligned_lw

    RSD_IO_WRITE_STR("can't reach here: unaligned_load...\n")
    j fail


unaligned_lhu:
    lbu   t1, 1(a7)
    j unaligned_lh_or_lhu_succ
unaligned_lh:
    lb   t1, 1(a7)
    j unaligned_lh_or_lhu_succ

unaligned_lh_or_lhu_succ:
    slli t1, t1, 8
    lbu   t0, 0(a7)
    or   t1, t1, t0

    mv   t0, a4                 # t0 <- rd
    jal  write_reg_n            # reg[rd]に正しい値を書く
    j finish

unaligned_lw:
    lbu   t1, 3(a7)
    slli t1, t1, 8
    lbu   t0, 2(a7)
    or   t1, t1, t0
    slli t1, t1, 8
    lbu   t0, 1(a7)
    or   t1, t1, t0
    slli t1, t1, 8
    lbu   t0, 0(a7)
    or   t1, t1, t0

    mv   t0, a4                 # t0 <- rd
    jal  write_reg_n            # reg[rd]に正しい値を書く
    j finish


unaligned_store:
    srli t0, a3, 12
    andi a4, t0, 7              # a4 <- 1(sh)/2(sw)
    csrrw a5, mbadaddr, a5      # a5 <- addr
    srli t0, t0, 8
    andi a6, t0, 0x1f           # a6 <- rs2 (store value)
    mv t0, a6
    jal read_n_reg
    mv a7, t0                   # a7 <- reg[rs2]

    li t0, 1
    beq a4, t0, unaligned_sh
    li t0, 2
    beq a4, t0, unaligned_sw

_cant_reach_here:
    RSD_IO_WRITE_STR("can't reach here")
    j _cant_reach_here

unaligned_sw:
    mv s0, a7                   # s0 <- reg[rs2]
    andi s1, s0, 0xff
    sb s1, 0(a5)

    srli s0, s0, 8
    andi s1, s0, 0xff
    sb s1, 1(a5)

    srli s0, s0, 8
    andi s1, s0, 0xff
    sb s1, 2(a5)

    srli s0, s0, 8
    andi s1, s0, 0xff
    sb s1, 3(a5)

    j finish

unaligned_sh:
    mv s0, a7                   # s0 <- reg[rs2]
    andi s1, s0, 0xff
    sb s1, 0(a5)

    srli s0, s0, 8
    andi s1, s0, 0xff
    sb s1, 1(a5)

    j finish

finish:
    lw x0, 0(sp)                # レジスタ復帰
    lw x1, 4(sp)
    lw x2, 8(sp)
    lw x3, 12(sp)
    lw x4, 16(sp)
    lw x5, 20(sp)
    lw x6, 24(sp)
    lw x7, 28(sp)
    lw x8, 32(sp)
    lw x9, 36(sp)
    lw x10, 40(sp)
    lw x11, 44(sp)
    lw x12, 48(sp)
    lw x13, 52(sp)
    lw x14, 56(sp)
    lw x15, 60(sp)
    lw x16, 64(sp)
    lw x17, 68(sp)
    lw x18, 72(sp)
    lw x19, 76(sp)
    lw x20, 80(sp)
    lw x21, 84(sp)
    lw x22, 88(sp)
    lw x23, 92(sp)
    lw x24, 96(sp)
    lw x25, 100(sp)
    lw x26, 104(sp)
    lw x27, 108(sp)
    lw x28, 112(sp)
    lw x29, 116(sp)
    lw x30, 120(sp)
    lw x31, 124(sp)

    addi sp, sp, +128           # スタック解放

    mret


# read_n_reg
#   args: t0
#   ret : t0
#   trap_vectorが呼び出されたときのreg[t0]の値をt0に入れて返す
#   t1は破壊される
read_n_reg:
    li t1, 0
    beq t0, t1, read_reg_0
    li t1, 1
    beq t0, t1, read_reg_1
    li t1, 2
    beq t0, t1, read_reg_2
    li t1, 3
    beq t0, t1, read_reg_3
    li t1, 4
    beq t0, t1, read_reg_4
    li t1, 5
    beq t0, t1, read_reg_5
    li t1, 6
    beq t0, t1, read_reg_6
    li t1, 7
    beq t0, t1, read_reg_7
    li t1, 8
    beq t0, t1, read_reg_8
    li t1, 9
    beq t0, t1, read_reg_9
    li t1, 10
    beq t0, t1, read_reg_10
    li t1, 11
    beq t0, t1, read_reg_11
    li t1, 12
    beq t0, t1, read_reg_12
    li t1, 13
    beq t0, t1, read_reg_13
    li t1, 14
    beq t0, t1, read_reg_14
    li t1, 15
    beq t0, t1, read_reg_15
    li t1, 16
    beq t0, t1, read_reg_16
    li t1, 17
    beq t0, t1, read_reg_17
    li t1, 18
    beq t0, t1, read_reg_18
    li t1, 19
    beq t0, t1, read_reg_19
    li t1, 20
    beq t0, t1, read_reg_20
    li t1, 21
    beq t0, t1, read_reg_21
    li t1, 22
    beq t0, t1, read_reg_22
    li t1, 23
    beq t0, t1, read_reg_23
    li t1, 24
    beq t0, t1, read_reg_24
    li t1, 25
    beq t0, t1, read_reg_25
    li t1, 26
    beq t0, t1, read_reg_26
    li t1, 27
    beq t0, t1, read_reg_27
    li t1, 28
    beq t0, t1, read_reg_28
    li t1, 29
    beq t0, t1, read_reg_29
    li t1, 30
    beq t0, t1, read_reg_30
    li t1, 31
    beq t0, t1, read_reg_31
read_reg_0:
    lw t0, 0(sp)
    ret
read_reg_1:
    lw t0, 4(sp)
    ret
read_reg_2:
    lw t0, 8(sp)
    ret
read_reg_3:
    lw t0, 12(sp)
    ret
read_reg_4:
    lw t0, 16(sp)
    ret
read_reg_5:
    lw t0, 20(sp)
    ret
read_reg_6:
    lw t0, 24(sp)
    ret
read_reg_7:
    lw t0, 28(sp)
    ret
read_reg_8:
    lw t0, 32(sp)
    ret
read_reg_9:
    lw t0, 36(sp)
    ret
read_reg_10:
    lw t0, 40(sp)
    ret
read_reg_11:
    lw t0, 44(sp)
    ret
read_reg_12:
    lw t0, 48(sp)
    ret
read_reg_13:
    lw t0, 52(sp)
    ret
read_reg_14:
    lw t0, 56(sp)
    ret
read_reg_15:
    lw t0, 60(sp)
    ret
read_reg_16:
    lw t0, 64(sp)
    ret
read_reg_17:
    lw t0, 68(sp)
    ret
read_reg_18:
    lw t0, 72(sp)
    ret
read_reg_19:
    lw t0, 76(sp)
    ret
read_reg_20:
    lw t0, 80(sp)
    ret
read_reg_21:
    lw t0, 84(sp)
    ret
read_reg_22:
    lw t0, 88(sp)
    ret
read_reg_23:
    lw t0, 92(sp)
    ret
read_reg_24:
    lw t0, 96(sp)
    ret
read_reg_25:
    lw t0, 100(sp)
    ret
read_reg_26:
    lw t0, 104(sp)
    ret
read_reg_27:
    lw t0, 108(sp)
    ret
read_reg_28:
    lw t0, 112(sp)
    ret
read_reg_29:
    lw t0, 116(sp)
    ret
read_reg_30:
    lw t0, 120(sp)
    ret
read_reg_31:
    lw t0, 124(sp)
    ret

# write_reg_n
#   args: t0(reg), t1(value)
#   t2は破壊される
write_reg_n:
    li t2, 0
    beq t0, t2, write_reg_0
    li t2, 1
    beq t0, t2, write_reg_1
    li t2, 2
    beq t0, t2, write_reg_2
    li t2, 3
    beq t0, t2, write_reg_3
    li t2, 4
    beq t0, t2, write_reg_4
    li t2, 5
    beq t0, t2, write_reg_5
    li t2, 6
    beq t0, t2, write_reg_6
    li t2, 7
    beq t0, t2, write_reg_7
    li t2, 8
    beq t0, t2, write_reg_8
    li t2, 9
    beq t0, t2, write_reg_9
    li t2, 10
    beq t0, t2, write_reg_10
    li t2, 11
    beq t0, t2, write_reg_11
    li t2, 12
    beq t0, t2, write_reg_12
    li t2, 13
    beq t0, t2, write_reg_13
    li t2, 14
    beq t0, t2, write_reg_14
    li t2, 15
    beq t0, t2, write_reg_15
    li t2, 16
    beq t0, t2, write_reg_16
    li t2, 17
    beq t0, t2, write_reg_17
    li t2, 18
    beq t0, t2, write_reg_18
    li t2, 19
    beq t0, t2, write_reg_19
    li t2, 20
    beq t0, t2, write_reg_20
    li t2, 21
    beq t0, t2, write_reg_21
    li t2, 22
    beq t0, t2, write_reg_22
    li t2, 23
    beq t0, t2, write_reg_23
    li t2, 24
    beq t0, t2, write_reg_24
    li t2, 25
    beq t0, t2, write_reg_25
    li t2, 26
    beq t0, t2, write_reg_26
    li t2, 27
    beq t0, t2, write_reg_27
    li t2, 28
    beq t0, t2, write_reg_28
    li t2, 29
    beq t0, t2, write_reg_29
    li t2, 30
    beq t0, t2, write_reg_30
    li t2, 31
    beq t0, t2, write_reg_31
fail_write_reg_n:
    j fail_write_reg_n
write_reg_0:
    sw t1, 0(sp)
    ret
write_reg_1:
    sw t1, 4(sp)
    ret
write_reg_2:
    sw t1, 8(sp)
    ret
write_reg_3:
    sw t1, 12(sp)
    ret
write_reg_4:
    sw t1, 16(sp)
    ret
write_reg_5:
    sw t1, 20(sp)
    ret
write_reg_6:
    sw t1, 24(sp)
    ret
write_reg_7:
    sw t1, 28(sp)
    ret
write_reg_8:
    sw t1, 32(sp)
    ret
write_reg_9:
    sw t1, 36(sp)
    ret
write_reg_10:
    sw t1, 40(sp)
    ret
write_reg_11:
    sw t1, 44(sp)
    ret
write_reg_12:
    sw t1, 48(sp)
    ret
write_reg_13:
    sw t1, 52(sp)
    ret
write_reg_14:
    sw t1, 56(sp)
    ret
write_reg_15:
    sw t1, 60(sp)
    ret
write_reg_16:
    sw t1, 64(sp)
    ret
write_reg_17:
    sw t1, 68(sp)
    ret
write_reg_18:
    sw t1, 72(sp)
    ret
write_reg_19:
    sw t1, 76(sp)
    ret
write_reg_20:
    sw t1, 80(sp)
    ret
write_reg_21:
    sw t1, 84(sp)
    ret
write_reg_22:
    sw t1, 88(sp)
    ret
write_reg_23:
    sw t1, 92(sp)
    ret
write_reg_24:
    sw t1, 96(sp)
    ret
write_reg_25:
    sw t1, 100(sp)
    ret
write_reg_26:
    sw t1, 104(sp)
    ret
write_reg_27:
    sw t1, 108(sp)
    ret
write_reg_28:
    sw t1, 112(sp)
    ret
write_reg_29:
    sw t1, 116(sp)
    ret
write_reg_30:
    sw t1, 120(sp)
    ret
write_reg_31:
    sw t1, 124(sp)
    ret