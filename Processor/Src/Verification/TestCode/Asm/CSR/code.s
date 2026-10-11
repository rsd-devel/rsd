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

    .macro RETURN_TO_MACHINE cause
    li a6, \cause
    la t0, 1f
    la t2, 2f
1:
    ecall
    j fail
2:
    li a6, 2
    li a7, 0x1800
    .endm

main:

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
    li t6, 0x40000
    csrc misa, t6
    EXPECT_ILLEGAL_CSR csrr a2, sscratch
    EXPECT_ILLEGAL_CSR csrr a2, medeleg
    csrs misa, t6
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
    li t3, 80
#else
    li t3, 77
#endif
    bne a4, t3, fail

    # These implemented CSRs remain readable even though their value is zero.
    EXPECT_ZERO_CSR mvendorid
    EXPECT_ZERO_CSR marchid
    EXPECT_ZERO_CSR mimpid
    EXPECT_ZERO_CSR mhartid
    EXPECT_ZERO_CSR 0x310       # mstatush (not named by older assemblers).
    EXPECT_ZERO_CSR mcounteren
    EXPECT_ZERO_CSR scounteren
    EXPECT_ZERO_CSR satp
    EXPECT_ZERO_CSR mcycleh
    EXPECT_ZERO_CSR minstreth

    # An implemented writable CSR must still work after the traps.
    csrr t3, mscratch
    bne t3, a5, fail
    csrrw t3, mscratch, a1
    bne t3, a5, fail
    csrr t3, mscratch
    bne t3, a1, fail
    csrw mscratch, a5

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

trap_vector:
    csrr t3, mcause
    bne t3, a6, fail
    csrr t3, mepc
    bne t3, t0, fail
    csrr t3, mstatus
    li t4, 0x1800
    and t3, t3, t4
    bne t3, a7, fail
    # A fault must not update the destination or another CSR.
    bne a2, a3, fail
    csrr t3, mscratch
    bne t3, a5, fail
    addi a4, a4, 1
    # CSR faults return to their original mode; ECALL ends each lower-mode test.
    li t4, 2
    beq a6, t4, 1f
    li t4, 0x1800
    csrs mstatus, t4
1:
    csrw mepc, t2
    mret
