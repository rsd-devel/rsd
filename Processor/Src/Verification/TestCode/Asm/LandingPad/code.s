# 未確認
#  * 割り込みの時のPELP
#  * LPADのmisalign


    .file    "code.s"
    .option nopic
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
