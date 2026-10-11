    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:

    # A full FCSR write updates both aliases and ignores reserved upper bits.
    li t0, 0xffffff71
    csrw fcsr, t0
    csrr t2, fcsr
    li t1, 0x71
    bne t2, t1, fail
    csrr t2, frm
    li t1, 3
    bne t2, t1, fail
    csrr t2, fflags
    li t1, 0x11
    bne t2, t1, fail

    # Set/clear operations through FCSR also update the rounding-mode field.
    li t0, 0x40
    csrc fcsr, t0
    csrr t2, fcsr
    li t1, 0x31
    bne t2, t1, fail
    csrs fcsr, t0
    csrr t2, fcsr
    li t1, 0x71
    bne t2, t1, fail

    # Writing either alias preserves the other field.
    li t0, 2
    csrw frm, t0
    csrr t2, fcsr
    li t1, 0x51
    bne t2, t1, fail
    li t0, 8
    csrw fflags, t0
    csrr t2, fcsr
    li t1, 0x48
    bne t2, t1, fail

    # Restore RNE and clear flags before the existing arithmetic checks.
    csrw fcsr, zero
    csrr t2, fcsr
    bnez t2, fail

    # Multiplication preserves the XOR of operand signs even for exact zero.
    fmv.w.x ft0, zero
    li t0, 0xbf800000 # -1.0
    fmv.w.x ft1, t0
    li t1, 0x80000000 # -0.0
    fmul.s ft2, ft0, ft1
    fmv.x.w t2, ft2
    bne t2, t1, fail
    fmul.s ft2, ft1, ft0
    fmv.x.w t2, ft2
    bne t2, t1, fail
    fmv.w.x ft0, t1
    fmul.s ft2, ft0, ft1 # -0.0 * -1.0 = +0.0
    fmv.x.w t2, ft2
    bnez t2, fail

    # Zero times infinity produces a canonical NaN and sets NV.
    fmv.w.x ft0, zero
    li t0, 0x7f800000 # +infinity
    fmv.w.x ft1, t0
    csrw fflags, zero
    fmul.s ft2, ft0, ft1
    csrr t2, fflags
    li t1, 0x10 # NV
    bne t2, t1, fail
    fmv.x.w t2, ft2
    li t1, 0x7fc00000 # canonical quiet NaN
    bne t2, t1, fail

    # A subsequent valid operation must preserve the accrued NV flag.
    fadd.s ft2, ft1, ft1
    csrr t2, fflags
    li t1, 0x10
    bne t2, t1, fail

    # Infinity minus infinity is invalid even without a NaN input.
    csrw fflags, zero
    fsub.s ft2, ft1, ft1
    csrr t2, fflags
    bne t2, t1, fail

    # Signaling NaNs raise NV in the multiplicand and addend paths.
    li t0, 0x7f800001
    fmv.w.x ft0, t0
    csrw fflags, zero
    fadd.s ft2, ft0, ft1
    csrr t2, fflags
    bne t2, t1, fail
    csrw fflags, zero
    fmadd.s ft2, ft1, ft1, ft0
    csrr t2, fflags
    bne t2, t1, fail

    # Quiet NaNs do not raise NV, including when the other inputs are infinite.
    li t0, 0xffc00000
    fmv.w.x ft0, t0
    csrw fflags, zero
    fmul.s ft2, ft0, ft1
    fmadd.s ft2, ft0, ft1, ft1
    fmadd.s ft2, ft1, ft0, ft1
    csrr t2, fflags
    bnez t2, fail

    # An invalid product still raises NV when the FMA addend is a quiet NaN.
    fmv.w.x ft2, zero
    csrw fflags, zero
    fmadd.s ft2, ft2, ft1, ft0
    csrr t2, fflags
    bne t2, t1, fail

    csrw fflags, zero
    fmv.w.x ft0, zero
    fmv.w.x ft1, zero
    fmv.w.x ft2, zero

    li t1, 0
    li t2, 0

    li  a0, -0x10000
    add a0, sp, a0
/*  fp arithmetic  */
#   fa1 = pi, fa2 = -e
    li a1, 0x40490FDA
    li a2, 0xC02DF854
    sw a1, 0(a0)
    sw a2, 4(a0)
    flw fa1, 0(a0)
    flw fa2, 4(a0)
#   fa3 = fa1 + fa2
#   fa4 = fa1 - fa2
#   fa5 = fa1 * fa2
#   fa6 = fa1 / fa2
#   fa7 = sqrt(fa1)
    fadd.s fa3, fa1, fa2
    fsub.s fa4, fa1, fa2
    fmul.s fa5, fa1, fa2
    fdiv.s fa6, fa1, fa2
    fsqrt.s fa7, fa1
    fmadd.s fs2, fa1, fa2, fa4
    fmsub.s fs3, fa1, fa2, fa4
    fnmsub.s fs4, fa1, fa2, fa4
    fnmadd.s fs5, fa1, fa2, fa4
/*  fcvt int -> fp  */
    li a5, 2
    li a6, -2
    fcvt.s.w fs6, a5
    fcvt.s.wu fs7, a5
    fcvt.s.w fs8, a6
    fcvt.s.wu fs9, a6
/*  fcvt fp -> int  */
    li a0, 0xBF8CCCCC # -1.1
    li a1, 0xBF800000 # -1.0
    li a2, 0xBF666666 # -0.9
    li a3, 0x3F666666 #  0.9
    li a4, 0x3F800000 #  1.0
    li a5, 0x3F8CCCCC #  1.1
    li a6, 0xCF32D05E # -3e9
    li a7, 0x4F32D05E #  3e9
    li t0, 0xC0400000 # -3.0
    # signed 
    fmv.s.x f1, a0
    fcvt.w.s s0, f1, rtz
    fmv.s.x f1, a1
    fcvt.w.s s1, f1, rtz
    fmv.s.x f1, a2
    fcvt.w.s s2, f1, rtz
    fmv.s.x f1, a3
    fcvt.w.s s3, f1, rtz
    fmv.s.x f1, a4
    fcvt.w.s s4, f1, rtz
    fmv.s.x f1, a5
    fcvt.w.s s5, f1, rtz
    fmv.s.x f1, a6
    fcvt.w.s s6, f1, rtz
    fmv.s.x f1, a7
    fcvt.w.s s7, f1, rtz
    # unsigned 
    fmv.s.x f1, t0
    fcvt.wu.s s8, f1, rtz
    fmv.s.x f1, a1
    fcvt.wu.s s9, f1, rtz
    fmv.s.x f1, a2
    fcvt.wu.s s10, f1, rtz
    fmv.s.x f1, a3
    fcvt.wu.s s11, f1, rtz
    fmv.s.x f1, a4
    fcvt.wu.s t3, f1, rtz
    fmv.s.x f1, a5
    fcvt.wu.s t4, f1, rtz
    fmv.s.x f1, a6
    fcvt.wu.s t5, f1, rtz
    fmv.s.x f1, a7
    fcvt.wu.s t6, f1, rtz

end:
    ret
    #j       end               # ここでループして終了

fail:
    j fail
