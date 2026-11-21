# Zicfilp tests run through the common source-built assembly test harness.
# Asynchronous ELP save/restore is also covered by the CSR/interrupt unit test.

    .file    "code.s"
    .option nopic
    .option arch, +zicfilp
    .text
    .align    2
    .globl    main
    .type     main, @function


main:
    # save return address
    addi sp, sp, -16
    sw ra, 0(sp)

    # ---------------- TEST 0 ----------------
    # Zicfilp is disabled
    # set trap vector
    la a0, trap_vector_cfi_disable
    csrrw x0, mtvec, a0

    # call function (Zicfilp disabled)
    la t1, target_nolpad
    jalr ra, t1, 0
    la t1, target_lpad_nolabel
    jalr ra, t1, 0
    la t1, target_lpad_label_1
    jalr ra, t1, 0
    la t1, target_lpad_label_2
    jalr ra, t1, 0

    # Setup
    # enable Zicfilp
    la a0, trap_vector_cfi_enable_test1_1
    csrrw x0, mtvec, a0
    li t0, 0x400 # MLPE = 1
    csrrw x0, mseccfg, t0

    # ---------------- TEST 1 ----------------
    # indirect jump to non lpad

    call reset_registers
    li a1, 0
    la t1, target_nolpad
    jalr ra, t1, 0

    # ---- TEST1.1 ----
    # mret with MPELP = 1 cause exception
    # this instruction must not be executed
    beqz x0, fail

    # --- TEST1.2 ----
    # jump to target_nolpad caused exception
    beqz a1, fail
    li t0, 123
    beq a2, t0, fail
    li t0, 234
    beq a3, t0, fail

    # ---------------- TEST 2 ----------------
    # indirect jump to no labeled lpad
    la a0, trap_vector_cfi_enable_with_reset_csr
    csrrw x0, mtvec, a0

    call reset_registers
    li a1, 0
    li x7, 0xdeadbeef # label number (ignored)
    la t1, target_lpad_nolabel
    jalr ra, t1, 0

    # check
    bnez a1, fail
    li t0, 345
    bne a2, t0, fail
    li t0, 456
    bne a3, t0, fail

    # ---------------- TEST 3 ----------------
    # indirect jump to labeled lpad (label 1), x7[31:12] is 1

    call reset_registers
    li a1, 0
    li x7, 0x1000 # label number
    la t1, target_lpad_label_1
    jalr ra, t1, 0

    # check
    bnez a1, fail
    li t0, 567
    bne a2, t0, fail
    li t0, 789
    bne a3, t0, fail

    # ---------------- TEST 4 ----------------
    # indirect jump to labeled lpad (label 2), x7[31:12] is 1

    call reset_registers
    li a1, 0
    li x7, 0x1000 # label number
    la t1, target_lpad_label_2
    jalr ra, t1, 0

    # check
    beqz a1, fail
    bnez a2, fail
    bnez a3, fail

    # ---------------- TEST 5 ----------------
    # MPELP = 0 on non software check exception

    # set MPELP = 1
    li t0, 0x200
    csrrs x0, mstatush, t0
    csrr t1, mstatush
    and t1, t1, t0
    beqz t1, fail

    # set trap vector
    la a0, trap_vector_cfi_enable_test5
    csrrw x0, mtvec, a0

    lw x0, 1(x0) # load from misaligned address to cause exception

    call extended_tests
    li a0, 0x400

end:
    # restore return address
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

reset_registers:
    # reset registers
    li a2, 0
    li a3, 0
    ret

fail:
    # infinite loop
    li x1, 0x1234
    li x2, 0x4321
    li x3, 0x1234
    li x4, 0x4321
    li x5, 0x5678
    li x6, 0x8765
    li x7, 0x5678
    li x8, 0x8765
    j fail

target_nolpad:
    addi a2, x0, 123
    addi a3, x0, 234
    ret
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

target_lpad_nolabel:
    lpad 0
    addi a2, x0, 345
    addi a3, x0, 456
    ret
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

target_lpad_label_1:
    lpad 1
    addi a2, x0, 567
    addi a3, x0, 789
    ret
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

target_lpad_label_2:
    lpad 2
    addi a2, x0, 890
    addi a3, x0, 901
    ret
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

# loop
trap_vector_cfi_disable:
    j trap_vector_cfi_disable


# for TEST 1.1
trap_vector_cfi_enable_test1_1:
    # cause is 18
    li t1, 18 # software check exception
    csrr t0, mcause
    bne t0, t1, fail

    # MPELP = 1
    li t1, 0x200
    csrr t0, mstatush
    and t0, t0, t1
    beqz t0, fail

    # trap value is 2
    li t1, 2 # landing pad fault
    csrr t0, mtval
    bne t0, t1, fail

    # lpad exception is trapped on lpad, so set mepc = ra to return next pc of jalr
    csrrw x0, mepc, ra

    la a0, trap_vector_cfi_enable_test_1_2
    csrrw x0, mtvec, a0

    mret

# for TEST 1.2
trap_vector_cfi_enable_test_1_2:
    # cause is 18
    li t1, 18 # software check exception
    csrr t0, mcause
    bne t0, t1, fail

    # MPELP = 1
    li t1, 0x200
    csrr t0, mstatush
    and t0, t0, t1
    beqz t0, fail

    # trap value is 2
    li t1, 2 # landing pad fault
    csrr t0, mtval
    bne t0, t1, fail

    # set a1 to non-zero value to indicate that trap handler is called
    addi a1, a1, 1

    # clear MPELP so the mret target is not required to be an LPAD
    li t1, 0x200
    csrc mstatush, t1

    # set mepc to next next instruction of jalr (ra + 4)
    addi ra, ra, 4
    csrrw x0, mepc, ra

    mret


trap_vector_cfi_enable_with_reset_csr:
    # cause is 18
    li t1, 18 # software check exception
    csrr t0, mcause
    bne t0, t1, fail

    # MPELP = 1
    li t1, 0x200
    csrr t0, mstatush
    and t0, t0, t1
    beqz t0, fail

    # trap value is 2
    li t1, 2 # landing pad fault
    csrr t0, mtval
    bne t0, t1, fail

    # set a1 to non-zero value to indicate that trap handler is called
    addi a1, a1, 1

    # set mcause to 0, MPELP to 0, mtval to 0
    csrw mcause, x0
    li t1, 0x200
    csrc mstatush, t1
    csrw mtval, x0

    # lpad exception is trapped on lpad, so set mepc = ra to return next pc of jalr
    csrrw x0, mepc, ra

    mret

trap_vector_cfi_enable_test5:
    # cause is 4 or 5
    csrr t0, mcause
    li t1, 4 # load misaligned
    beq t0, t1, cause_ok_test5
    li t1, 5 # load access fault
    beq t0, t1, cause_ok_test5
    call fail

    cause_ok_test5:
    # MPELP is 0
    li t1, 0x200
    csrr t0, mstatush
    and t0, t0, t1
    bnez t0, fail

    # trap value is misaligned address (1)
    li t1, 1 # misaligned address
    csrr t0, mtval
    bne t0, t1, fail

    # add 4 to mepc
    csrr t0, mepc
    addi t0, t0, 4
    csrrw x0, mepc, t0

    mret

# s2..s6 hold the expected cause, fault PC, tval, resume PC, and PELP.
# s9 requests an M-mode return after an ECALL from a lower privilege level.
    .macro expect_trap cause, pc, value, resume, pelp
    li s2, \cause
    la s3, \pc
    li s4, \value
    la s5, \resume
    li s6, \pelp
    .endm

extended_tests:
    addi sp, sp, -16
    sw ra, 0(sp)
    addi s0, sp, 4
    sw zero, 0(s0)
    li s1, 0
    li s9, 0
    la t0, extended_m_trap
    csrw mtvec, t0
    la t0, extended_s_trap
    csrw stvec, t0
    csrw mie, zero
    li t0, 8
    csrc mstatus, t0
    csrw medeleg, zero

    # An instruction access fault outranks the expected-LPAD check and must
    # preserve ELP even though its cause is not a software-check exception.
    li s11, 1
    expect_trap 1, 0xcdcd0000, 0, after_access_fault, 1
    li t1, 0xcdcd0000
    jalr ra, 0(t1)
    j fail
after_access_fault:
    li t0, 1
    bne s1, t0, fail

    # A failed landing pad must not let younger register writes or stores retire.
    li s11, 2
    li a4, 0
    expect_trap 18, forbidden_target, 2, after_forbidden, 1
    la t1, forbidden_target
    jalr ra, 0(t1)
    j fail
after_forbidden:
    bnez a4, fail
    lw t0, 0(s0)
    bnez t0, fail
    li t0, 2
    bne s1, t0, fail

    # x1, x5, and x7 as JALR bases are exempt from the landing-pad requirement.
    li s11, 3
    la ra, exempt_ra
    jalr zero, 0(ra)
    j fail
exempt_ra:
    la t0, exempt_t0
    jalr zero, 0(t0)
    j fail
exempt_t0:
    la t2, exempt_t2
    jalr zero, 0(t2)
    j fail
exempt_t2:
    # With ELP clear, the LPAD encoding remains an AUIPC-to-x0 hint.
    lpad 0xfffff

    # Alternate the two decode-lane positions and exercise branch recovery
    # while operand dependencies and division delay the backend.
    li s11, 4
    li s10, 128
    li a2, 0
    li t2, 0x1000
landing_loop:
    andi t0, s10, 1
    beqz t0, landing_even
    la t1, landing_lane1
    j landing_call
landing_even:
    la t1, landing_lane0
landing_call:
    jalr ra, 0(t1)
    addi s10, s10, -1
    bnez s10, landing_loop
    li t0, 128
    bne a2, t0, fail

    # MLPE must not enable checking in S-mode when menvcfg.LPE is clear.
    # MRET must discard MPELP when its destination's LPE is disabled.
    li s11, 5
    csrw 0x30a, zero             # menvcfg
    csrw 0x10a, zero             # senvcfg
    expect_trap 9, s_disabled_ecall, 0, after_s_disabled, 0
    li s9, 1
    la t0, s_disabled
    csrw mepc, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x200
    csrs mstatush, t0
    mret
s_disabled:
    la t1, s_disabled_target
    jalr zero, 0(t1)
    j fail
s_disabled_target:
s_disabled_ecall:
    ecall
    j fail
after_s_disabled:
    li s9, 0
    li t0, 3
    bne s1, t0, fail

    # MRET into enabled S-mode restores MPELP. The missing pad is delegated
    # to S-mode, where SPELP must record the precise pre-trap ELP.
    li s11, 6
    li t0, 4
    csrw 0x30a, t0              # menvcfg.LPE
    csrw 0x10a, t0              # senvcfg.LPE
    li t0, 0x40000
    csrw medeleg, t0            # Delegate software-check exceptions.
    expect_trap 18, s_expected_entry, 2, s_enabled, 1
    la t0, s_expected_entry
    csrw mepc, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x200
    csrs mstatush, t0
    mret
s_expected_entry:
    j fail
s_enabled:
    li t0, 4
    bne s1, t0, fail
    li s11, 7
    expect_trap 18, s_bad_target, 2, s_after_bad, 1
    la t1, s_bad_target
    jalr zero, 0(t1)
    j fail
s_bad_target:
    j fail
s_after_bad:
    li t0, 5
    bne s1, t0, fail

    # SRET into enabled U-mode must restore SPELP, and a delegated trap from
    # U-mode must preserve that expectation in SPELP rather than MPELP.
    li s11, 8
    expect_trap 18, u_expected_entry, 2, u_enabled, 1
    la t0, u_expected_entry
    csrw sepc, t0
    li t0, 0x100
    csrc sstatus, t0            # SPP=U
    li t0, 0x800000
    csrs sstatus, t0            # SPELP=LP_EXPECTED
    sret
u_expected_entry:
    j fail
u_enabled:
    li t0, 6
    bne s1, t0, fail
    li s11, 9
    li t2, 0x1000
    la t1, landing_lane0
    jalr ra, 0(t1)
    expect_trap 18, u_bad_target, 2, u_after_bad, 1
    la t1, u_bad_target
    jalr zero, 0(t1)
    j fail
u_bad_target:
    j fail
u_after_bad:
    li t0, 7
    bne s1, t0, fail
    expect_trap 8, u_exit_ecall, 0, after_u, 0
    li s9, 1
u_exit_ecall:
    ecall
    j fail
after_u:
    li t0, 8
    bne s1, t0, fail
    # A real MSIP request drains a loop of LPAD/JALR before entering the
    # handler. Check ELP against the saved frontier, without assuming a fixed
    # interrupt latency or allowing an ECALL to preempt the pending interrupt.
    li s11, 10
    csrci mstatus, 8
    li s9, 1
    expect_trap 8, u_irq_exit, 0, after_irq, 0
    la t0, extended_irq_trap
    csrw mtvec, t0
    li t0, 0x40010000
    li t1, 1
    sw t1, 0(t0)
    fence iorw, iorw
    li t0, 8
    csrw mie, t0
    li t0, 0x1808
    csrc mstatus, t0            # MPP=U, MIE=0
    li t0, 0x200
    csrs mstatush, t0
    la t0, u_irq_target
    csrw mepc, t0
    csrr s7, mip
    csrr s8, mie
    csrr s10, mstatus
    andi t3, s7, 8
    beqz t3, fail
    li t3, 8
    bne s8, t3, fail
    la t1, u_irq_target
    mret
    .p2align 4
u_irq_target:
    lpad 0
u_irq_jump:
    jalr zero, 0(t1)
u_irq_done:
    lpad 0
u_irq_exit:
    ecall
    j fail
after_irq:
    li t0, 10
    bne s1, t0, fail
    li s11, 11
    csrw medeleg, zero
    csrw 0x30a, zero
    csrw 0x10a, zero
    li t0, 0x400
    csrc mseccfg, t0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

    .p2align 4
landing_lane0:
    lpad 1
    div t3, s11, s11
    add a2, a2, t3
    ret
    .p2align 4
    nop
landing_lane1:
    lpad 1
    div t3, s11, s11
    add a2, a2, t3
    ret

forbidden_target:
    addi a4, a4, 1
    sw a4, 0(s0)
    ret

    .p2align 2
extended_m_trap:
    csrr a6, mcause
    csrr a7, mepc
    csrr t4, mtval
    csrr t5, mstatush
    csrr t3, mcause
    bne t3, s2, fail
    csrr t3, mepc
    bne t3, s3, fail
    csrr t3, mtval
    bne t3, s4, fail
    csrr t3, mstatush
    srli t3, t3, 9
    andi t3, t3, 1
    bne t3, s6, fail
    li t3, 0x200
    csrc mstatush, t3
    beqz s9, 1f
    li t3, 0x1800
    csrs mstatus, t3
1:
    addi s1, s1, 1
    csrw mepc, s5
    mret

    .p2align 2
extended_s_trap:
    csrr t3, scause
    bne t3, s2, fail
    csrr t3, sepc
    bne t3, s3, fail
    csrr t3, stval
    bne t3, s4, fail
    csrr t3, sstatus
    srli t3, t3, 23
    andi t3, t3, 1
    bne t3, s6, fail
    li t3, 0x800000
    csrc sstatus, t3
    addi s1, s1, 1
    csrw sepc, s5
    sret

    .p2align 2
extended_irq_trap:
    csrr a6, mcause
    li t3, 0x80000003
    bne a6, t3, fail
    csrr a7, mepc
    la t3, u_irq_target
    li t4, 0x200
    beq a7, t3, 1f
    la t3, u_irq_jump
    bne a7, t3, fail
    li t4, 0
1:
    csrr s7, mstatush
    andi s7, s7, 0x200
    bne s7, t4, fail
    csrr t3, mtval
    bnez t3, fail
    # Preserve MPELP for MRET, but clear the source to avoid repeated traps.
    # The resumed loop exits through one checked indirect jump and a valid pad.
    la t1, u_irq_done
    li t3, 0x40010000
    sw zero, 0(t3)
    fence iorw, iorw
    csrw mie, zero
    la t3, extended_m_trap
    csrw mtvec, t3
    addi s1, s1, 1
    mret
