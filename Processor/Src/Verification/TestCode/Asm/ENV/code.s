    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function

    .set illegal_trap_count, 0
    .macro EXPECT_ILLEGAL encoding
    .set illegal_trap_count, illegal_trap_count + 1
    la t0, 1f
    la t2, 2f
1:
    .word \encoding
    j fail
2:
    .endm
    
main:
    # Misaligned control transfers must trap at the source instruction.
    la a0, misaligned_trap_vector
    csrw mtvec, a0
    addi sp, sp, -16
    mv a6, sp
    sw zero, 0(a6)
    li a4, 0
    li a5, 0
    li a7, 0x13579bdf
    mv t6, a7

    # JALR must preserve the old link register on an exception.
    la t0, misaligned_jalr
    addi t1, t0, 2
    la t2, after_jalr
misaligned_jalr:
    jalr t6, 0(t1)
    addi a5, a5, 1
    sw a5, 0(a6)
    j fail
after_jalr:

    # The same rule applies when rd == rs1; JALR clears target bit 0.
    la t0, misaligned_jalr_same_reg
    addi t1, t0, 2
    addi t6, t1, 1
    mv a7, t6
    la t2, after_jalr_same_reg
misaligned_jalr_same_reg:
    jalr t6, 0(t6)
    addi a5, a5, 1
    sw a5, 0(a6)
    j fail
after_jalr_same_reg:

    li a7, 0x13579bdf
    mv t6, a7
    la t0, misaligned_jal
    addi t1, t0, 2
    la t2, after_jal
misaligned_jal:
    jal t6, misaligned_jal + 2
    addi a5, a5, 1
    sw a5, 0(a6)
    j fail
after_jal:

    la t0, misaligned_branch
    addi t1, t0, 2
    la t2, after_branch
misaligned_branch:
    beq zero, zero, misaligned_branch + 2
    addi a5, a5, 1
    sw a5, 0(a6)
    j fail
after_branch:
    li t3, 4
    bne a4, t3, fail

    # A branch that is not taken must not raise an alignment exception.
not_taken_branch:
    beq zero, t6, not_taken_branch + 2
    addi a5, a5, 1
    li t3, 1
    bne a5, t3, fail
    li t3, 4
    bne a4, t3, fail

    # Reserved encodings must trap before changing a destination or memory.
    la t0, illegal_trap_vector
    csrw mtvec, t0
    li a4, 0
    li a5, 0x11223344
    li a7, 0x13579bdf
    mv t6, a7
    li t1, 0x2468ace0
    sw t1, 0(a6)
#ifdef __riscv_flen
    fmv.w.x ft0, a7
    li t3, 0x3f800000
    fmv.w.x ft1, t3
    li t3, 0x40000000
    fmv.w.x ft2, t3
    li t3, 0x40400000
    fmv.w.x ft3, t3
    csrwi fflags, 8
#endif

    # RV32 shifts must reject reserved upper immediate bits before writing rd.
    EXPECT_ILLEGAL 0x02079f93   # SLLI shamt[5] != 0.
    EXPECT_ILLEGAL 0x0207df93   # SRLI shamt[5] != 0.
    EXPECT_ILLEGAL 0x4207df93   # SRAI shamt[5] != 0.
    EXPECT_ILLEGAL 0x40079f93   # SLLI funct7=0x20 is reserved.
    EXPECT_ILLEGAL 0x80079f93   # SLLI funct7=0x40 is reserved.
    EXPECT_ILLEGAL 0x8007df93   # SRLI/SRAI funct7=0x40 is reserved.

    # Reserved branch conditions must trap instead of redirecting the PC.
    EXPECT_ILLEGAL 0x00002463   # BRANCH funct3=2, forward displacement.
    EXPECT_ILLEGAL 0x00003463   # BRANCH funct3=3, forward displacement.
    EXPECT_ILLEGAL 0xfe002ee3   # BRANCH funct3=2, backward displacement.
    EXPECT_ILLEGAL 0xfe003ee3   # BRANCH funct3=3, backward displacement.

    # An invalid JALR must neither redirect control nor write the link register.
    la a3, fail
    EXPECT_ILLEGAL 0x00069fe7   # JALR funct3=1.
    EXPECT_ILLEGAL 0x0006afe7   # JALR funct3=2.
    EXPECT_ILLEGAL 0x0006bfe7   # JALR funct3=3.
    EXPECT_ILLEGAL 0x0006cfe7   # JALR funct3=4.
    EXPECT_ILLEGAL 0x0006dfe7   # JALR funct3=5.
    EXPECT_ILLEGAL 0x0006efe7   # JALR funct3=6.
    EXPECT_ILLEGAL 0x0006ffe7   # JALR funct3=7.
    EXPECT_ILLEGAL 0x00069067   # Invalid JALR with rd=x0 must still trap.
    EXPECT_ILLEGAL 0x00269fe7   # Illegal encoding takes priority over target misalignment.

    # Unknown OP funct7 values must not fall back to ordinary ALU operations.
    EXPECT_ILLEGAL 0x98f78fb3   # funct7=0x4c, the issue #127 case with rd=t6.
    EXPECT_ILLEGAL 0x04f78fb3   # funct7=0x02.
    EXPECT_ILLEGAL 0xfef78fb3   # funct7=0x7f.
    # funct7=0x20 defines only SUB and SRA in the implemented extensions.
    EXPECT_ILLEGAL 0x40f79fb3   # SLL with funct7=0x20.
    EXPECT_ILLEGAL 0x40f7afb3   # SLT with funct7=0x20.
    EXPECT_ILLEGAL 0x40f7bfb3   # SLTU with funct7=0x20.
    EXPECT_ILLEGAL 0x40f7cfb3   # XNOR (unsupported Zbb).
    EXPECT_ILLEGAL 0x40f7efb3   # ORN (unsupported Zbb).
    EXPECT_ILLEGAL 0x40f7ffb3   # ANDN (unsupported Zbb).
    EXPECT_ILLEGAL 0x0af7cfb3   # MIN (unsupported Zbb).
    EXPECT_ILLEGAL 0x0af7bfb3   # CLMULH (unsupported Zbc).
    # Reject undefined funct3 values even when Zba or Zicond is enabled.
    EXPECT_ILLEGAL 0x20f78fb3   # Zba funct3=0.
    EXPECT_ILLEGAL 0x20f79fb3   # Zba funct3=1.
    EXPECT_ILLEGAL 0x20f7bfb3   # Zba funct3=3.
    EXPECT_ILLEGAL 0x20f7dfb3   # Zba funct3=5.
    EXPECT_ILLEGAL 0x20f7ffb3   # Zba funct3=7.
    EXPECT_ILLEGAL 0x0ef78fb3   # Zicond funct3=0.
    EXPECT_ILLEGAL 0x0ef79fb3   # Zicond funct3=1.
    EXPECT_ILLEGAL 0x0ef7afb3   # Zicond funct3=2.
    EXPECT_ILLEGAL 0x0ef7bfb3   # Zicond funct3=3.
    EXPECT_ILLEGAL 0x0ef7cfb3   # Zicond funct3=4.
    EXPECT_ILLEGAL 0x0ef7efb3   # Zicond funct3=6.

    # All memory operands use the aligned stack word at a6.
    EXPECT_ILLEGAL 0x00083f83   # LOAD funct3=3.
    EXPECT_ILLEGAL 0x00086f83   # LOAD funct3=6.
    EXPECT_ILLEGAL 0x00087f83   # LOAD funct3=7.
    EXPECT_ILLEGAL 0x00f83023   # STORE funct3=3.
    EXPECT_ILLEGAL 0x00f84023   # STORE funct3=4.
    EXPECT_ILLEGAL 0x00f85023   # STORE funct3=5.
    EXPECT_ILLEGAL 0x00f86023   # STORE funct3=6.
    EXPECT_ILLEGAL 0x00f87023   # STORE funct3=7.

    EXPECT_ILLEGAL 0x00000ff3   # ECALL rd != 0.
    EXPECT_ILLEGAL 0x00078073   # ECALL rs1 != 0.
    EXPECT_ILLEGAL 0x00100ff3   # EBREAK rd != 0.
    EXPECT_ILLEGAL 0x00178073   # EBREAK rs1 != 0.
    EXPECT_ILLEGAL 0x30200ff3   # MRET rd != 0.
    EXPECT_ILLEGAL 0x30278073   # MRET rs1 != 0.
    EXPECT_ILLEGAL 0x10200ff3   # SRET rd != 0.
    EXPECT_ILLEGAL 0x10278073   # SRET rs1 != 0.
    EXPECT_ILLEGAL 0x10500ff3   # WFI rd != 0.
    EXPECT_ILLEGAL 0x10578073   # WFI rs1 != 0.

#ifdef __riscv_flen
    EXPECT_ILLEGAL 0x00080007   # FP LOAD funct3=0.
    EXPECT_ILLEGAL 0x00081007   # FP LOAD funct3=1.
    EXPECT_ILLEGAL 0x00083007   # FP LOAD funct3=3.
    EXPECT_ILLEGAL 0x00084007   # FP LOAD funct3=4.
    EXPECT_ILLEGAL 0x00085007   # FP LOAD funct3=5.
    EXPECT_ILLEGAL 0x00086007   # FP LOAD funct3=6.
    EXPECT_ILLEGAL 0x00087007   # FP LOAD funct3=7.
    EXPECT_ILLEGAL 0x00180027   # FP STORE funct3=0.
    EXPECT_ILLEGAL 0x00181027   # FP STORE funct3=1.
    EXPECT_ILLEGAL 0x00183027   # FP STORE funct3=3.
    EXPECT_ILLEGAL 0x00184027   # FP STORE funct3=4.
    EXPECT_ILLEGAL 0x00185027   # FP STORE funct3=5.
    EXPECT_ILLEGAL 0x00186027   # FP STORE funct3=6.
    EXPECT_ILLEGAL 0x00187027   # FP STORE funct3=7.

    EXPECT_ILLEGAL 0x0020d053   # FADD.S rm=5.
    EXPECT_ILLEGAL 0x0820e053   # FSUB.S rm=6.
    EXPECT_ILLEGAL 0x1020d053   # FMUL.S rm=5.
    EXPECT_ILLEGAL 0x1820e053   # FDIV.S rm=6.
    EXPECT_ILLEGAL 0x58108053   # FSQRT.S rs2 != 0.
    EXPECT_ILLEGAL 0x5800d053   # FSQRT.S rm=5.
    EXPECT_ILLEGAL 0x2020b053   # FSGNJ.S funct3=3.
    EXPECT_ILLEGAL 0x2820a053   # FMIN/FMAX.S funct3=2.
    EXPECT_ILLEGAL 0xc0208fd3   # FCVT.W.S rs2=2.
    EXPECT_ILLEGAL 0xc000dfd3   # FCVT.W.S rm=5.
    EXPECT_ILLEGAL 0xd0278053   # FCVT.S.W rs2=2.
    EXPECT_ILLEGAL 0xd007e053   # FCVT.S.W rm=6.
    EXPECT_ILLEGAL 0xe000afd3   # FCLASS/FMV.X.W funct3=2.
    EXPECT_ILLEGAL 0xa020bfd3   # FCMP.S funct3=3.
    EXPECT_ILLEGAL 0xf0079053   # FMV.W.X funct3=1.
    EXPECT_ILLEGAL 0xe0108fd3   # FMV.X.W rs2=1.
    EXPECT_ILLEGAL 0xe1f08fd3   # FMV.X.W rs2=31.
    EXPECT_ILLEGAL 0xe0109fd3   # FCLASS.S rs2=1.
    EXPECT_ILLEGAL 0xe1f09fd3   # FCLASS.S rs2=31.
    EXPECT_ILLEGAL 0xf0178053   # FMV.W.X rs2=1.
    EXPECT_ILLEGAL 0xf1f78053   # FMV.W.X rs2=31.
    # Match the other FP arithmetic instructions' reserved static-rm policy.
    EXPECT_ILLEGAL 0x1820d043   # FMADD.S rm=5.
    EXPECT_ILLEGAL 0x1820e043   # FMADD.S rm=6.
    EXPECT_ILLEGAL 0x1820d047   # FMSUB.S rm=5.
    EXPECT_ILLEGAL 0x1820e047   # FMSUB.S rm=6.
    EXPECT_ILLEGAL 0x1820d04b   # FNMSUB.S rm=5.
    EXPECT_ILLEGAL 0x1820e04b   # FNMSUB.S rm=6.
    EXPECT_ILLEGAL 0x1820d04f   # FNMADD.S rm=5.
    EXPECT_ILLEGAL 0x1820e04f   # FNMADD.S rm=6.
    EXPECT_ILLEGAL 0x02208053   # FADD.D, unsupported funct7.
    EXPECT_ILLEGAL 0x1a208043   # FMADD fmt=1.
    EXPECT_ILLEGAL 0x1c208047   # FMSUB fmt=2.
    EXPECT_ILLEGAL 0x1e20804b   # FNMSUB fmt=3.
    EXPECT_ILLEGAL 0x1a20804f   # FNMADD fmt=1.
#endif
    li t3, illegal_trap_count
    bne a4, t3, fail
    addi sp, sp, 16
    
    la a0, trap_vector
    csrrw a0, mtvec, a0 
    
    ecall
    mv a2, a1   # mcause = 11
    
    ebreak
    mv a3, a1   # mcause = 3

    li      a0, 0x400
    
end:
    ret
    #j       end               # ここでループして終了


trap_vector:
    nop
    csrr a1, mcause
    # ECALL and EBREAK are both 32-bit instructions; resume after the trap.
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret


misaligned_trap_vector:
    csrr t3, mcause
    csrr t4, mepc
    csrr t5, mtval
    bnez t3, fail
    bne t4, t0, fail
    bne t5, t1, fail
    bne t6, a7, fail
    bnez a5, fail
    lw t3, 0(a6)
    bnez t3, fail
    addi a4, a4, 1
    csrw mepc, t2
    mret

illegal_trap_vector:
    csrr t3, mcause
    li t4, 2
    bne t3, t4, fail
    csrr t3, mepc
    bne t3, t0, fail
    csrr t3, mtval
    bnez t3, fail
    bne t6, a7, fail
    lw t3, 0(a6)
    bne t3, t1, fail
#ifdef __riscv_flen
    fmv.x.w t3, ft0
    bne t3, a7, fail
    csrr t3, fflags
    li t4, 8
    bne t3, t4, fail
#endif
    addi a4, a4, 1
    csrw mepc, t2
    mret

fail:
    j fail


