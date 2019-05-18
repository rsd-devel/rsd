#include "Asm/rsd-asm-macros.h"
	
	.file	"rsd-crt.s"

	.text
	.align	4
	
	# 開始アドレスと終了アドレスをエクスポート
	.global _start
	.global _end
	
	# 外部の main とローダ
	.extern main
	.extern _load

	stack_top = 0x80020000

	# entry point: 0x1000
_start:
	j _init
	# goal: 0x1004
_end:
	j _end

_call_main:
	call main
	j _end

_init:
	# set trap vector
	la a0, trap_vector
	csrw mtvec, a0

	li	sp,0x80020000
	call _load

	# clear registers
	li	x1, 0
	li	x2, 0
	li	x3, 0
	li	x4, 0
	li	x5, 0
	li	x6, 0
	li	x7, 0
	li	x8, 0
	li	x9, 0
	li	x10,0
	li	x11,0
	li	x12,0
	li	x13,0
	li	x14,0
	li	x15,0
	li	x16,0
	li	x17,0
	li	x18,0
	li	x19,0
	li	x20,0
	li	x21,0
	li	x22,0
	li	x23,0
	li	x24,0
	li	x25,0
	li	x26,0
	li	x27,0
	li	x28,0
	li	x29,0
	li	x30,0
	li	x31,0
	li	sp,0x80020000

	j _call_main



# トラップベクタ
trap_vector:
	addi sp, sp, -128					 # スタック確保
	sw x0, 0(sp)								# レジスタ退避
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

	# Show messages and dump registers
	RSD_IO_WRITE_STR("\033[34m\nException caused.\n")
		
	RSD_IO_WRITE_STR("mcause:")
	csrr a0, mcause
	RSD_IO_WRITE_GPR(a0)

	RSD_IO_WRITE_STR(" mepc:")
	csrr a0, mepc
	RSD_IO_WRITE_GPR(a0)

	RSD_IO_WRITE_STR(" mbadaddr:")
	csrr a0, mbadaddr
	RSD_IO_WRITE_GPR(a0)
	RSD_IO_WRITE_STR("\n")

	li t2, 0
	li t3, 128
trap_dump_registers:
	srli a0, t2, 2
	RSD_IO_WRITE_GPR(a0)
	RSD_IO_WRITE_STR(": ")
	add a0, t2, sp
	lw a0, 0(a0)
	RSD_IO_WRITE_GPR(a0)
	RSD_IO_WRITE_STR("\n")
	add t2, t2, 4
	bne t2, t3, trap_dump_registers
	RSD_IO_WRITE_STR("aborting...\n\033[0m")

abort:
	j _end

	lw x0, 0(sp)								# レジスタ退避
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
	addi sp, sp, +128					 # スタック解放

	mret


# 文字列データ
	.data
	.align	4
hello_str:
	.string	"RSD"
