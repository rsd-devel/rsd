    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function

    .macro EXPECT_ILLEGAL_CSR instruction:vararg
    la t0, 1f
    la t2, 2f
1:
    \instruction
    j fail
2:
    .endm

    .macro EXPECT_ZERO_CSR csr
    csrr t3, \csr
    bnez t3, fail
    .endm

    .macro CHECK_XTVEC_MODE csr
    csrr t5, \csr
    la t1, trap_vector
    # Check every MODE encoding while preserving a nonzero BASE.
    .irp mode, 0, 1, 2, 3
    ori t3, t1, \mode
    csrw \csr, t3
    csrr t4, \csr
    .if \mode < 2
    bne t4, t3, fail
    .else
    bne t4, t1, fail
    .endif
    .endr

    # SET must coerce the resulting MODE, not just the operand.
    ori t3, t1, 1
    csrw \csr, t3
    li t4, 2
    csrs \csr, t4
    csrr t4, \csr
    bne t4, t1, fail
    csrw \csr, t3
    li t4, 1
    csrc \csr, t4
    csrr t4, \csr
    bne t4, t1, fail

    csrrwi t4, \csr, 2
    EXPECT_ZERO_CSR \csr
    csrrwi t4, \csr, 3
    EXPECT_ZERO_CSR \csr
    ori t3, t1, 1
    csrw \csr, t3
    csrsi \csr, 2
    csrr t4, \csr
    bne t4, t1, fail
    csrw \csr, t3
    csrci \csr, 1
    csrr t4, \csr
    bne t4, t1, fail
    csrw \csr, t5
    .endm

    .macro CHECK_READ_ONLY_CSR csr
    # Zero-source SET/CLEAR instructions only read the CSR, even with rd = x0.
    EXPECT_ZERO_CSR \csr
    csrrc t3, \csr, zero
    bnez t3, fail
    csrrsi t3, \csr, 0
    bnez t3, fail
    csrrci t3, \csr, 0
    bnez t3, fail
    csrrs zero, \csr, zero
    csrrc zero, \csr, zero
    csrrsi zero, \csr, 0
    csrrci zero, \csr, 0

    # All six CSR forms must trap when they attempt a write.
    EXPECT_ILLEGAL_CSR csrrw a2, \csr, a3
    EXPECT_ILLEGAL_CSR csrrs a2, \csr, a3
    EXPECT_ILLEGAL_CSR csrrc a2, \csr, a3
    EXPECT_ILLEGAL_CSR csrrwi a2, \csr, 1
    EXPECT_ILLEGAL_CSR csrrsi a2, \csr, 1
    EXPECT_ILLEGAL_CSR csrrci a2, \csr, 1

    # WRITE always writes, including zero and a discarded result.
    EXPECT_ILLEGAL_CSR csrrw a2, \csr, zero
    EXPECT_ILLEGAL_CSR csrrwi a2, \csr, 0
    EXPECT_ILLEGAL_CSR csrrw zero, \csr, zero
    EXPECT_ILLEGAL_CSR csrrwi zero, \csr, 0

    # A zero value in a nonzero register still requests a SET/CLEAR write.
    EXPECT_ILLEGAL_CSR csrrs a2, \csr, t1
    EXPECT_ILLEGAL_CSR csrrc a2, \csr, t1
    EXPECT_ILLEGAL_CSR csrrs zero, \csr, t1
    EXPECT_ILLEGAL_CSR csrrc zero, \csr, t1
    EXPECT_ILLEGAL_CSR csrrsi zero, \csr, 1
    EXPECT_ILLEGAL_CSR csrrci zero, \csr, 1
    .endm

    .macro CHECK_FORBIDDEN_CSR csr
    EXPECT_ILLEGAL_CSR csrrw a2, \csr, a3
    EXPECT_ILLEGAL_CSR csrrs a2, \csr, a3
    EXPECT_ILLEGAL_CSR csrrc a2, \csr, a3
    EXPECT_ILLEGAL_CSR csrrwi a2, \csr, 1
    EXPECT_ILLEGAL_CSR csrrsi a2, \csr, 1
    EXPECT_ILLEGAL_CSR csrrci a2, \csr, 1
    # Include read-only and write-only accesses, also with rd = x0.
    EXPECT_ILLEGAL_CSR csrr a2, \csr
    EXPECT_ILLEGAL_CSR csrrw zero, \csr, zero
    EXPECT_ILLEGAL_CSR csrrs zero, \csr, zero
    .endm

    .macro CHECK_BARE_SATP
    # RSD implements only Bare mode: writes are ignored and reads return zero.
    csrrw t3, satp, a3
    bnez t3, fail
    csrrs t3, satp, a3
    bnez t3, fail
    csrrc t3, satp, a3
    bnez t3, fail
    csrrwi t3, satp, 1
    bnez t3, fail
    csrrsi t3, satp, 1
    bnez t3, fail
    csrrci t3, satp, 1
    bnez t3, fail
    csrrw zero, satp, zero
    csrrwi zero, satp, 0
    .endm

    .macro CHECK_COUNTER64 low, high
    # Writing the high half must preserve the running low half.
    li t0, 0x12340000
    csrw \low, t0
    li t1, 0x12345678
    csrw \high, t1
    csrr t2, \high
    bne t2, t1, fail
    csrr t2, \low
    sub t2, t2, t0
    li t3, 0x10000
    bgeu t2, t3, fail

    # Writing the low half must preserve the high half.
    li t0, 0x87650000
    csrw \low, t0
    csrr t2, \high
    bne t2, t1, fail

    # SET/CLEAR use the high half for both the returned and written values.
    li t0, 0x80000000
    csrrs t2, \high, t0
    bne t2, t1, fail
    or t3, t1, t0
    csrr t2, \high
    bne t2, t3, fail
    csrrc t2, \high, t0
    bne t2, t3, fail
    csrr t2, \high
    bne t2, t1, fail

    # Both counters must carry from bit 31 to bit 32.
    li t0, -16
    csrw \low, t0
    .rept 64
    nop
    .endr
    addi t1, t1, 1
    csrr t2, \high
    bne t2, t1, fail

    # The full counter wraps modulo 2^64.
    li t0, -1
    csrw \high, t0
    li t0, -16
    csrw \low, t0
    .rept 64
    nop
    .endr
    csrr t2, \high
    bnez t2, fail
    .endm

    .macro ENTER_PRIVILEGE mpp
    li t3, 0x1800
    csrc mstatus, t3
    li t3, \mpp
    csrs mstatus, t3
    la t3, 1f
    # IALIGN=32 masks bit 1 on both CSR reads and MRET's implicit read.
    ori t3, t3, 2
    csrw mepc, t3
    csrr t4, mepc
    la t3, 1f
    bne t4, t3, fail
    li a7, \mpp
    mret
1:
    .endm

    .macro RETURN_TO_MACHINE cause, instruction=ecall
    li a6, \cause
    la t0, 1f
    la t2, 2f
1:
    \instruction
    j fail
2:
    li a6, 2
    li a7, 0x1800
    .endm

    .macro EXPECT_SUPERVISOR_TRAP cause, status, instruction:vararg
    li a6, -1              # Reject an unexpected trip through the M-mode handler.
    li s7, \cause
    li s8, \status        # Expected SPP/SPIE/SIE on entry to the S-mode handler.
    addi s10, s5, 1
    la t0, 1f
    la t2, 2f
1:
    \instruction
    j fail
2:
    bne s5, s10, fail
    li a6, 2
    .endm

    .macro CHECK_MINSTRET_WRITE instruction:vararg
    csrw minstret, zero
    \instruction
    csrr t0, minstret
    bnez t0, fail
    .endm

    .macro CHECK_MINSTRET_TRAP cause, instruction:vararg
    li t4, \cause
    csrr t0, minstret
    \instruction
    csrr t1, minstret
    sub t1, t1, t0
    # The first CSR read and six handler instructions retire; the trap does not.
    li t2, 7
    bne t1, t2, fail
    .endm

main:

    # Writes replace the implicit update, even though they retire later.
    li t1, 0
    .irp csr, minstret, minstreth
    CHECK_MINSTRET_WRITE csrrw zero, \csr, zero
    CHECK_MINSTRET_WRITE csrrwi zero, \csr, 0
    # A zero value in a nonzero source register still requests a write.
    CHECK_MINSTRET_WRITE csrrs zero, \csr, t1
    CHECK_MINSTRET_WRITE csrrc zero, \csr, t1

    # Zero-source SET/CLEAR only read and must each increment minstret.
    csrw minstret, zero
    csrrs zero, \csr, zero
    csrrc zero, \csr, zero
    csrrsi zero, \csr, 0
    csrrci zero, \csr, 0
    csrr t0, minstret
    li t2, 4
    bne t0, t2, fail
    .endr

    la t0, minstret_trap_vector
    csrrw t6, mtvec, t0
    CHECK_MINSTRET_TRAP 11, ecall
    CHECK_MINSTRET_TRAP 3, ebreak
    CHECK_MINSTRET_TRAP 2, .word 0xffffffff
    csrw mtvec, t6

    # Consecutive ordinary instructions are counted once each.
    csrr t0, minstret
    addi t2, zero, 1
    addi t2, t2, 1
    csrr t1, minstret
    sub t1, t1, t0
    li t2, 3
    bne t1, t2, fail

    # The taken JALR retires once; its skipped illegal instruction does not.
    la t3, 1f
    csrr t0, minstret
    jalr zero, 0(t3)
    .word 0xffffffff
1:
    csrr t1, minstret
    sub t1, t1, t0
    li t2, 2
    bne t1, t2, fail

    # AMO's internal load/store work still retires as one instruction.
    addi sp, sp, -16
    sw zero, 0(sp)
    li t3, 1
    csrr t0, minstret
    amoadd.w t2, t3, (sp)
    csrr t1, minstret
    sub t1, t1, t0
    bnez t2, fail
    li t2, 2
    bne t1, t2, fail
    lw t2, 0(sp)
    bne t2, t3, fail
    addi sp, sp, 16

    li a1, 0x00
    li a2, 0x03
    li a3, 0x10
    li a4, 0x01
    csrrw a1, mscratch, a2   # a2(0x03) を書き込む
    csrrs a1, mscratch, a3   # a3(0x10) を set
    csrrc a1, mscratch, a4   # a4(0x01) を clear
    csrr  a1, mscratch       # a0 に読み出す（0x12）
    
    csrrwi a5, mscratch, 7   # (0x7) を書き込む
    csrrsi a5, mscratch, 8   # (0x8) を set
    csrrci a5, mscratch, 1   # (0x1) を clear
    csrr   a5, mscratch      # a5 に読み出す（0xe）

    # Check the implemented ISA, including the optional single-precision FPU.
    csrr t0, misa
#ifdef __riscv_flen
    li t1, 0x40141121       # RV32 with I/M/A/F/S/U, without D.
#else
    li t1, 0x40141101       # RV32 with I/M/A/S/U, without F/D.
#endif
    bne t0, t1, fail

    # Software cannot enable unsupported F/D extensions.
    li t2, 0x28
    csrs misa, t2
    csrr t0, misa
    bne t0, t1, fail

    # Changing trap vectors must not expose an interrupt to a temporary address.
    csrr t6, mstatus
    csrci mstatus, 8
    CHECK_XTVEC_MODE mtvec
    CHECK_XTVEC_MODE stvec
    csrw mstatus, t6

    la t0, trap_vector
    csrrw a0, mtvec, t0
    li a3, 0x13579bdf
    mv a2, a3
    li a4, 0
    li a6, 2
    li a7, 0x1800

    # A missing CSR must trap for all six CSR instruction forms.
    EXPECT_ILLEGAL_CSR csrrw a2, 0x7c0, a3
    EXPECT_ILLEGAL_CSR csrrs a2, 0x7c0, a3
    EXPECT_ILLEGAL_CSR csrrc a2, 0x7c0, a3
    EXPECT_ILLEGAL_CSR csrrwi a2, 0x7c0, 1
    EXPECT_ILLEGAL_CSR csrrsi a2, 0x7c0, 1
    EXPECT_ILLEGAL_CSR csrrci a2, 0x7c0, 1

    # Discarding the result or suppressing a write must not suppress the trap.
    EXPECT_ILLEGAL_CSR csrrw zero, 0x7c0, zero
    EXPECT_ILLEGAL_CSR csrrs a2, 0x7c0, zero
    EXPECT_ILLEGAL_CSR csrrc a2, 0x7c0, zero
    EXPECT_ILLEGAL_CSR csrrsi a2, 0x7c0, 0
    EXPECT_ILLEGAL_CSR csrrci a2, 0x7c0, 0

    # Supervisor CSRs are unavailable when misa.S is disabled.
    csrr t5, stvec
    li t6, 0x40000
    csrc misa, t6
    EXPECT_ILLEGAL_CSR csrr a2, sscratch
    EXPECT_ILLEGAL_CSR csrr a2, medeleg
    EXPECT_ILLEGAL_CSR csrr a2, stvec
    EXPECT_ILLEGAL_CSR csrrw a2, stvec, a3
    csrs misa, t6
    csrr t3, stvec
    bne t3, t5, fail
    EXPECT_ZERO_CSR sscratch

#ifndef __riscv_flen
    # A core without the FPU must not expose the floating-point CSRs.
    EXPECT_ILLEGAL_CSR csrr a2, fflags
    EXPECT_ILLEGAL_CSR csrr a2, frm
    EXPECT_ILLEGAL_CSR csrr a2, fcsr
#endif

    li t1, 0
    CHECK_READ_ONLY_CSR mvendorid
    CHECK_READ_ONLY_CSR marchid
    CHECK_READ_ONLY_CSR mimpid
    CHECK_READ_ONLY_CSR mhartid
#ifndef __riscv_flen
    li t3, 82
#else
    li t3, 79
#endif
    bne a4, t3, fail

    # These implemented CSRs remain readable even though their value is zero.
    EXPECT_ZERO_CSR mvendorid
    EXPECT_ZERO_CSR marchid
    EXPECT_ZERO_CSR mimpid
    EXPECT_ZERO_CSR mhartid
    EXPECT_ZERO_CSR 0x310       # mstatush starts with MPELP clear.
    # Zicfilp implements only MPELP (bit 9) in the RV32 high status word.
    li t0, -1
    csrw 0x310, t0
    csrr t3, 0x310
    li t4, 0x200
    bne t3, t4, fail
    li t0, -513                # Reserved bits must not change MPELP.
    csrc 0x310, t0
    csrr t3, 0x310
    bne t3, t4, fail
    csrc 0x310, t4
    EXPECT_ZERO_CSR 0x310
    csrs 0x310, t4
    csrr t3, 0x310
    bne t3, t4, fail
    csrw 0x310, zero
    EXPECT_ZERO_CSR mcounteren
    EXPECT_ZERO_CSR scounteren
    EXPECT_ZERO_CSR satp

    # The machine counters expose writable low and high halves on RV32.
    CHECK_COUNTER64 mcycle, mcycleh
    CHECK_COUNTER64 minstret, minstreth

    # An implemented writable CSR must still work after the traps.
    csrr t3, mscratch
    bne t3, a5, fail
    csrrw t3, mscratch, a1
    bne t3, a5, fail
    csrr t3, mscratch
    bne t3, a1, fail
    csrw mscratch, a5

    # Keep interrupts disabled while testing every implemented enable bit.
    csrr s1, mstatus
    csrr s2, mie
    csrci mstatus, 8
    csrw mie, zero

    # mstatus already ignores padding; preserve that behavior for WRITE/SET/CLEAR.
    csrr t1, mstatus
    li t0, 0xff21e655
    or t3, t1, t0
    csrw mstatus, t3
    csrr t4, mstatus
    bne t4, t1, fail
    csrs mstatus, t0
    csrr t4, mstatus
    bne t4, t1, fail
    csrc mstatus, t0
    csrr t4, mstatus
    bne t4, t1, fail

    # SPELP is shared by the machine and supervisor status views.
    li t0, 0x800000
    csrs mstatus, t0
    csrr t3, sstatus
    and t3, t3, t0
    bne t3, t0, fail
    csrc sstatus, t0
    csrr t3, mstatus
    and t3, t3, t0
    bnez t3, fail

    # M/S interrupt enables and platform CUSTOM bits remain writable.
    li t1, 0xffff0aaa
    li t0, -1
    csrrw t3, mie, t0
    bnez t3, fail
    csrr t4, mie
    bne t4, t1, fail
    csrrc t3, mie, t0
    bne t3, t1, fail
    EXPECT_ZERO_CSR mie
    csrrs t3, mie, t0
    bnez t3, fail
    csrr t4, mie
    bne t4, t1, fail
    li t0, 0x0000f555
    csrc mie, t0
    csrr t4, mie
    bne t4, t1, fail

    # Immediate writes also discard reserved bits and report the old value.
    csrrwi t3, mie, 31
    bne t3, t1, fail
    li t1, 0xa
    csrr t4, mie
    bne t4, t1, fail
    csrrci t3, mie, 31
    bne t3, t1, fail
    EXPECT_ZERO_CSR mie
    csrrsi t3, mie, 31
    bnez t3, fail
    csrr t4, mie
    bne t4, t1, fail

    # Disabling S must not remove machine or platform interrupt enables.
    csrw mie, zero
    csrr t5, misa
    li t0, 0x40000
    csrc misa, t0
    li t0, 0xffff0888
    csrw mie, t0
    csrr t4, mie
    bne t4, t0, fail
    csrw misa, t5
    csrw mie, s2
    csrw mstatus, s1

    # Route lower-privilege traps to M-mode and preserve the original CSR state.
    csrr t5, mstatus
    csrr t6, medeleg
    csrr s0, sscratch
    csrw medeleg, zero
    csrw sscratch, a3
    li a4, 0
    li t3, 0x100000
    csrc mstatus, t3

    ENTER_PRIVILEGE 0x800
    # S-mode may access its own CSRs, including satp while TVM is clear.
    csrrw t3, sscratch, a5
    bne t3, a3, fail
    csrrw t3, sscratch, a3
    bne t3, a5, fail
    CHECK_BARE_SATP
    CHECK_FORBIDDEN_CSR mscratch
    EXPECT_ILLEGAL_CSR csrr a2, mhartid
    RETURN_TO_MACHINE 9

    li t3, 0x100000
    csrs mstatus, t3
    csrr t4, mstatus
    and t4, t4, t3
    beqz t4, fail
    # TVM must not restrict M-mode satp accesses.
    CHECK_BARE_SATP

    ENTER_PRIVILEGE 0x800
    # With TVM set, only satp is restricted among the tested S-mode CSRs.
    csrr t3, sscratch
    bne t3, a3, fail
    CHECK_FORBIDDEN_CSR satp
    RETURN_TO_MACHINE 9

    ENTER_PRIVILEGE 0
    # U-mode must not read or write machine or supervisor CSRs.
    CHECK_FORBIDDEN_CSR mscratch
    CHECK_FORBIDDEN_CSR sscratch
    CHECK_FORBIDDEN_CSR satp
    EXPECT_ILLEGAL_CSR csrr a2, mhartid
    RETURN_TO_MACHINE 8

    li t3, 50
    bne a4, t3, fail
    csrr t3, sscratch
    bne t3, a3, fail

    # Delegate illegal instructions and S/U ECALLs, but never M-mode traps.
    csrr s1, stvec
    la t3, supervisor_trap_vector
    csrw stvec, t3
    li t3, 0x304           # medeleg: illegal instruction, U ECALL, S ECALL.
    csrw medeleg, t3
    csrr t4, medeleg
    bne t3, t4, fail
    li s5, 0
    EXPECT_ILLEGAL_CSR csrr a2, 0x7c0
    RETURN_TO_MACHINE 11
    bnez s5, fail

    ENTER_PRIVILEGE 0x800
    csrsi sstatus, 2       # Trap entry must copy SIE=1 to SPIE, then clear SIE.
    EXPECT_SUPERVISOR_TRAP 9, 0x120, ecall
    csrr t3, sstatus
    andi t3, t3, 0x122
    li t4, 0x22            # SRET restored SIE, set SPIE and cleared SPP.
    bne t3, t4, fail
    csrci sstatus, 2
    EXPECT_SUPERVISOR_TRAP 2, 0x100, csrr a2, mscratch
    EXPECT_SUPERVISOR_TRAP 2, 0x100, mret
    csrr t3, sstatus
    andi t3, t3, 0x122
    li t4, 0x20            # SRET must also preserve a previously disabled SIE.
    bne t3, t4, fail
    RETURN_TO_MACHINE 3, ebreak  # Breakpoints are not delegated.
    li t3, 3
    bne s5, t3, fail

    csrsi sstatus, 2
    ENTER_PRIVILEGE 0
    EXPECT_SUPERVISOR_TRAP 8, 0x20, ecall
    # These must still fault after SRET: returning to S/M by mistake is invalid.
    EXPECT_SUPERVISOR_TRAP 2, 0x20, sret
    EXPECT_SUPERVISOR_TRAP 2, 0x20, csrr a2, sscratch
    RETURN_TO_MACHINE 3, ebreak
    li t3, 6
    bne s5, t3, fail
    csrr t3, sstatus
    andi t3, t3, 0x122
    li t4, 0x22
    bne t3, t4, fail

    csrw stvec, s1
    csrw sscratch, s0
    csrw medeleg, t6
    csrw mstatus, t5
    csrw mtvec, a0

    li      a0, 0x400
end:
    ret
    #j       end               # ここでループして終了

fail:
    j fail

minstret_trap_vector:
    csrr t3, mcause
    bne t3, t4, fail
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

trap_vector:
    csrr t3, mcause
    bne t3, a6, fail
    csrr t3, mepc
    bne t3, t0, fail
    # CSR faults and ECALL report a zero trap value.
    csrr t3, mtval
    bnez t3, fail
    csrr t3, mstatus
    li t4, 0x1800
    and t3, t3, t4
    bne t3, a7, fail
    # A fault must not update the destination or another CSR.
    bne a2, a3, fail
    csrr t3, mscratch
    bne t3, a5, fail
    addi a4, a4, 1
    # CSR faults return to their original mode; ECALL/EBREAK end lower-mode tests.
    li t4, 2
    beq a6, t4, 1f
    li t4, 0x1800
    csrs mstatus, t4
1:
    csrw mepc, t2
    mret

supervisor_trap_vector:
    csrr t3, scause
    bne t3, s7, fail
    csrr t3, sepc
    bne t3, t0, fail
    csrr t3, stval
    bnez t3, fail
    csrr t3, sstatus
    andi t3, t3, 0x122
    bne t3, s8, fail
    bne a2, a3, fail
    addi s5, s5, 1
    csrw sepc, t2
    sret
