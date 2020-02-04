
#ifndef RSD_COMPLIANCE_TEST_H
#define RSD_COMPLIANCE_TEST_H

// Undefined
#define RV_COMPLIANCE_HALT
#define RV_COMPLIANCE_RV32M

#define RV_COMPLIANCE_CODE_BEGIN    \
    _rsd_main: \
    la a0, _trap_vector; \
    csrrw a0, mtvec, a0;

#define RV_COMPLIANCE_CODE_END \
    j _rsd_finalize

// "_rsd_begin_output_data" must be aligned
#define RV_COMPLIANCE_DATA_BEGIN \
    .align 4 ;\
    _rsd_begin_output_data:

#define RV_COMPLIANCE_DATA_END \
    _rsd_end_output_data:


//
// RSD specific macros
//

#define RSD_SERIAL_ADDR 0x40002000

#define RSD_STRINGIFY(x) #x
#define RSD_TOSTRING(x)  RSD_STRINGIFY(x)

#define RSD_IO_WRITE_BYTE(_R) \
    mv a0, _R ;\
    jal _rsd_write_byte ;\

#define RSD_IO_WRITE_GPR(_R) \
    mv a0, _R ;\
    jal _rsd_write_gpr_as_string ;\

// This macro makes string data and call _rsd_write_str
// "10000" is local label.
// "10000b" means that search "10000" before this instruction
// "10000f" means that search "10000" after this instruction
#define RSD_IO_WRITE_STR(_STR) \
    .data               ;\
10000:                  ;\
    .string _STR        ;\
    .align 4            ;\
    .text               ;\
    la a0, 10000b       ;\
    jal _rsd_write_str  ;\


// --------------------------------------
// code definition

//
// Jump to RV_COMPLIANCE_CODE_BEGIN
//
    .option nopic
    .text
    .align 4
    .globl _start
_start:
    j _rsd_main 
_rsd_goal:
    j _rsd_goal

//
// Jumped from RV_COMPLIANCE_CODE_END
//
_rsd_finalize:
    la a3, _rsd_begin_output_data
    la a4, _rsd_end_output_data

    // Dump from _rsd_begin_output_data to _rsd_end_output_data
_rsd_print_signiture_loop:

    // print a line of 16 bytes
    add a5, a3, 15
_rsd_print_signiture_line:
    lbu  a2, (a5)      
    RSD_IO_WRITE_BYTE(a2)
    addi a5, a5, -1
    bge  a5, a3, _rsd_print_signiture_line

    RSD_IO_WRITE_STR("\n")
    addi a3, a3, 16
    bne a3, a4, _rsd_print_signiture_loop

_rsd_print_signiture_exit:
    j _rsd_goal


// Print string specified by a0
// This function use a0, t0, t1, ra
//
_rsd_write_str:
    mv t0, a0
    li t1, RSD_SERIAL_ADDR

_rsd_write_str_loop:
    lbu  a0, (t0)
    addi t0, t0, 1
    beq  a0, zero, _rsd_write_str_exit  // if string is terminated, exit
    sw   a0, 0(t1)
    j _rsd_write_str_loop

_rsd_write_str_exit:
    ret

//
// Print a single byte
// This function use a0, t0, t1, ra
//
    .data
10000:
    .string "0123456789abcdef"
    .text
_rsd_write_byte:
    mv t1, a0          // copy
    // Print upper nibble
    srli a0, t1, 4
    andi a0, a0, 0x0f
    la t0, 10000b       // load a convert table address
    add a0, a0, t0
    lbu  a0, (a0)
    li t0, RSD_SERIAL_ADDR
    sw a0, 0(t0)
    
    // Print lower nibble
    andi a0, t1, 0x0f
    la t0, 10000b
    add a0, a0, t0
    lbu  a0, (a0)
    li t0, RSD_SERIAL_ADDR
    sw a0, 0(t0)
    ret

//
// Print a single byte
// This function use a0, t0, t1, ra
//
    .data
    .align 4
10000:
    .word 0x00000000

    .text
_rsd_write_gpr_as_string:
    la t0, 10000b
    sw ra, 0(t0)

    mv a1, a0          // copy
    jal _rsd_write_byte

    srli a1, a1, 8
    mv a0, a1
    jal _rsd_write_byte

    srli a1, a1, 8
    mv a0, a1
    jal _rsd_write_byte

    srli a1, a1, 8
    mv a0, a1
    jal _rsd_write_byte

    la t0, 10000b
    lw ra, 0(t0)
    ret


_trap_vector:
    addi sp, sp, -128

    sw x0, 0(sp)
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
    csrrw a2, mcause, a2 		# a2 にmcause を入れる
    andi a2, a2, 0xf            # mcauseの下位4bitだけを見る．reservedな値は知らない
    lw a3, 0(a0)                # a3 に例外起こした命令を入れる
    li t0, 4					# LOAD_MISALIGNED = 4
    beq a2, t0, unaligned_load
    li t0, 6					# STORE_MISALIGNED = 6
    beq a2, t0, unaligned_store

_invalid_mcause:
    j _invalid_mcause

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

_invalid_load_funct:
    j _invalid_load_funct


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

_invalid_store_funct:
    j _invalid_store_funct

unaligned_sw:
    mv s0, a7               # s0 <- reg[rs2]
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
    mv s0, a7               # s0 <- reg[rs2]
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

    addi sp, sp, +128

    mret


// read_n_reg
//   args: t0
//   ret : t0
//   trap_vectorが呼び出されたときのreg[t0]の値をt0に入れて返す
//   t1は破壊される
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

// write_reg_n
//   args: t0(reg), t1(value)
//   t2は破壊される
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

#endif  // RSD_COMPLIANCE_TEST_H
