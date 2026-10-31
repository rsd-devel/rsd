    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function

    # Checks use ft2 as the result and t1/t2 as scratch registers.
    .macro CHECK_FFLAGS expected
    csrr t2, fflags
    li t1, \expected
    bne t2, t1, fail
    .endm

    .macro CHECK_FP_RESULT expected
    fmv.x.w t2, ft2
    li t1, \expected
    bne t2, t1, fail
    .endm

    # Verify the static encoding overrides frm, then check dynamic rounding.
    .macro CHECK_FMA_MODE mode, frm, expected, flags
    li t0, ((\frm + 1) % 5)
    csrw frm, t0
    csrw fflags, zero
    fmadd.s ft2, ft0, ft1, ft3, \mode
    CHECK_FP_RESULT \expected
    CHECK_FFLAGS \flags
    li t0, \frm
    csrw frm, t0
    csrw fflags, zero
    fmadd.s ft2, ft0, ft1, ft3, dyn
    CHECK_FP_RESULT \expected
    CHECK_FFLAGS \flags
    .endm

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

    # Division distinguishes finite/zero (DZ) from zero/zero (NV).
    li t0, 0x3f800000 # 1.0
    fmv.w.x ft0, t0
    fmv.w.x ft1, zero
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1
    CHECK_FFLAGS 0x08
    CHECK_FP_RESULT 0x7f800000
    li t0, 0x80000000 # -0.0
    fmv.w.x ft1, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1
    CHECK_FFLAGS 0x08
    CHECK_FP_RESULT 0xff800000
    csrw fflags, zero
    fdiv.s ft2, ft1, ft1
    CHECK_FFLAGS 0x10
    CHECK_FP_RESULT 0x7fc00000

    # Infinity/infinity is invalid; infinity/zero does not raise DZ.
    li t0, 0x7f800000
    fmv.w.x ft0, t0
    fmv.w.x ft1, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1
    CHECK_FFLAGS 0x10
    fmv.w.x ft1, zero
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x7f800000

    # Signaling NaNs raise NV in either operand; quiet NaNs raise neither flag.
    li t0, 0x7f800001
    fmv.w.x ft0, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1
    CHECK_FFLAGS 0x10
    fmv.w.x ft1, t0
    li t0, 0x3f800000
    fmv.w.x ft0, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1
    CHECK_FFLAGS 0x10
    li t0, 0xffc00000 # Negative quiet NaN
    fmv.w.x ft0, t0
    fmv.w.x ft1, zero
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x7fc00000

    # Square root rejects negative numbers, but accepts -0 and quiet NaNs.
    li t0, 0xbf800000 # -1.0
    fmv.w.x ft0, t0
    csrw fflags, zero
    fsqrt.s ft2, ft0
    CHECK_FFLAGS 0x10
    CHECK_FP_RESULT 0x7fc00000

    # A finite subnormal/zero accrues DZ beside the existing NV flag.
    li t0, 0x00000001
    fmv.w.x ft0, t0
    fdiv.s ft2, ft0, ft1
    CHECK_FFLAGS 0x18
    CHECK_FP_RESULT 0x7f800000

    li t0, 0x80000000
    fmv.w.x ft0, t0
    csrw fflags, zero
    fsqrt.s ft2, ft0
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x80000000
    li t0, 0xffc00000
    fmv.w.x ft0, t0
    csrw fflags, zero
    fsqrt.s ft2, ft0
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x7fc00000
    li t0, 0xff800001 # Negative signaling NaN
    fmv.w.x ft0, t0
    csrw fflags, zero
    fsqrt.s ft2, ft0
    CHECK_FFLAGS 0x10
    CHECK_FP_RESULT 0x7fc00000

    # RNE division reports lost precision, but exact quotients leave flags clear.
    li t0, 0x3f800000 # 1.0
    fmv.w.x ft0, t0
    li t0, 0x40400000 # 3.0
    fmv.w.x ft1, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0x01
    CHECK_FP_RESULT 0x3eaaaaab
    li t0, 0x40c00000 # 6.0
    fmv.w.x ft0, t0
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0x01 # The exact operation preserves accrued NX.
    CHECK_FP_RESULT 0x40000000
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x40000000

    # Finite overflow is OF+NX, unlike infinity inputs or division by zero.
    li t0, 0x7f7fffff # Maximum finite
    fmv.w.x ft0, t0
    li t0, 0x3f000000 # 0.5
    fmv.w.x ft1, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0x05
    CHECK_FP_RESULT 0x7f800000

    # Exact subnormal results do not underflow; tiny inexact results do.
    li t0, 0x00800000 # Minimum normal
    fmv.w.x ft0, t0
    li t0, 0x40000000 # 2.0
    fmv.w.x ft1, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x00400000
    li t0, 3 # Three times the minimum subnormal: halfway rounds to even.
    fmv.w.x ft0, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0x03
    CHECK_FP_RESULT 0x00000002
    li t0, 1 # Half the minimum subnormal rounds to zero.
    fmv.w.x ft0, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0x03
    CHECK_FP_RESULT 0
    li t0, 0x7f7fffff # A quotient too small to retain any mantissa bits.
    fmv.w.x ft1, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0x03
    CHECK_FP_RESULT 0

    # An inexact result just below the normal boundary still raises UF.
    li t0, 0x00800000
    fmv.w.x ft0, t0
    li t0, 0x3f800001 # The next float above 1.0
    fmv.w.x ft1, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0x03
    CHECK_FP_RESULT 0x007fffff

    # Tininess uses 24-bit precision with an unbounded exponent. This exact
    # quotient is tiny even though subnormal rounding produces minimum normal.
    li t0, 0x00ffffff
    fmv.w.x ft0, t0
    li t0, 0x40000000
    fmv.w.x ft1, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0x03
    CHECK_FP_RESULT 0x00800000

    # Zero and infinity results from special inputs do not raise OF/UF/NX.
    fmv.w.x ft0, zero
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0
    li t0, 0x7f800000
    fmv.w.x ft1, t0
    li t0, 0x3f800000
    fmv.w.x ft0, t0
    csrw fflags, zero
    fdiv.s ft2, ft0, ft1, rne
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0

    # Square root sets NX for irrational results, including subnormal inputs.
    li t0, 0x40800000 # sqrt(4) = 2 exactly
    fmv.w.x ft0, t0
    csrw fflags, zero
    fsqrt.s ft2, ft0, rne
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x40000000
    li t0, 0x40000000
    fmv.w.x ft0, t0
    csrw fflags, zero
    fsqrt.s ft2, ft0, rne
    CHECK_FFLAGS 0x01
    CHECK_FP_RESULT 0x3fb504f3
    li t0, 1
    fmv.w.x ft0, t0
    csrw fflags, zero
    fsqrt.s ft2, ft0, rne
    CHECK_FFLAGS 0x01 # The square root is normal, so UF remains clear.
    CHECK_FP_RESULT 0x1a3504f3
    li t0, 0x7f800000
    fmv.w.x ft0, t0
    csrw fflags, zero
    fsqrt.s ft2, ft0, rne
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x7f800000

    # Exact multiplication and a zero-product bypass do not raise NX.
    li t0, 0x3f800000
    fmv.w.x ft0, t0
    fmv.w.x ft1, t0
    csrw fflags, zero
    fmul.s ft2, ft0, ft1
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x3f800000
    fmv.w.x ft0, zero
    csrw fflags, zero
    fadd.s ft2, ft0, ft1
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x3f800000

    # A nonzero product lost when bypassing to the addend still raises NX.
    li t0, 0x30800000 # 2^-30
    fmv.w.x ft0, t0
    csrw fflags, zero
    fadd.s ft2, ft0, ft1
    CHECK_FFLAGS 0x01
    CHECK_FP_RESULT 0x3f800000

    # Finite overflow raises OF and NX together.
    li t0, 0x7f7fffff
    fmv.w.x ft0, t0
    li t0, 0x40000000 # 2.0
    fmv.w.x ft1, t0
    csrw fflags, zero
    fmul.s ft2, ft0, ft1
    CHECK_FFLAGS 0x05
    CHECK_FP_RESULT 0x7f800000

    # An exact subnormal result does not raise UF.
    li t0, 0x00800000 # Minimum normal
    fmv.w.x ft0, t0
    li t0, 0x3f000000 # 0.5
    fmv.w.x ft1, t0
    csrw fflags, zero
    fmul.s ft2, ft0, ft1
    CHECK_FFLAGS 0
    CHECK_FP_RESULT 0x00400000

    # Tiny, inexact results raise UF and NX, even when all bits are lost.
    li t0, 0x00000001 # Minimum subnormal
    fmv.w.x ft0, t0
    csrw fflags, zero
    fmul.s ft2, ft0, ft1
    CHECK_FFLAGS 0x03
    CHECK_FP_RESULT 0
    fmv.w.x ft1, t0
    csrw fflags, zero
    fmul.s ft2, ft0, ft1
    CHECK_FFLAGS 0x03
    CHECK_FP_RESULT 0

    # The exact halfway value is tiny at full precision, even though
    # subnormal rounding produces minimum normal. Both UF and NX are required.
    li t0, 0x3f000000
    fmv.w.x ft1, t0
    li t0, 0x007fffff # Maximum subnormal
    fmv.w.x ft2, t0
    csrw fflags, zero
    fmadd.s ft2, ft0, ft1, ft2
    CHECK_FFLAGS 0x03
    CHECK_FP_RESULT 0x00800000

    # Halfway at 1.0 distinguishes RNE from RMM.
    li t0, 0x3f800000
    fmv.w.x ft0, t0
    li t0, 0x3f800000
    fmv.w.x ft1, t0
    li t0, 0x33800000
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x3f800000, 0x01
    CHECK_FMA_MODE rtz, 1, 0x3f800000, 0x01
    CHECK_FMA_MODE rdn, 2, 0x3f800000, 0x01
    CHECK_FMA_MODE rup, 3, 0x3f800001, 0x01
    CHECK_FMA_MODE rmm, 4, 0x3f800001, 0x01

    # A tiny product must still affect a dominant addend under RUP.
    li t0, 0x00000001
    fmv.w.x ft0, t0
    li t0, 0x00000001
    fmv.w.x ft1, t0
    li t0, 0x3f800000
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x3f800000, 0x01
    CHECK_FMA_MODE rtz, 1, 0x3f800000, 0x01
    CHECK_FMA_MODE rdn, 2, 0x3f800000, 0x01
    CHECK_FMA_MODE rup, 3, 0x3f800001, 0x01
    CHECK_FMA_MODE rmm, 4, 0x3f800000, 0x01

    # Subtracting a tiny addend crosses the 1.0 binade boundary under RTZ/RDN.
    li t0, 0x3f800000
    fmv.w.x ft0, t0
    li t0, 0x3f800000
    fmv.w.x ft1, t0
    li t0, 0x80000001
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x3f800000, 0x01
    CHECK_FMA_MODE rtz, 1, 0x3f7fffff, 0x01
    CHECK_FMA_MODE rdn, 2, 0x3f7fffff, 0x01
    CHECK_FMA_MODE rup, 3, 0x3f800000, 0x01
    CHECK_FMA_MODE rmm, 4, 0x3f800000, 0x01

    # Exact cancellation produces negative zero only under RDN.
    li t0, 0x3f800000
    fmv.w.x ft0, t0
    li t0, 0x3f800000
    fmv.w.x ft1, t0
    li t0, 0xbf800000
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x00000000, 0x00
    CHECK_FMA_MODE rtz, 1, 0x00000000, 0x00
    CHECK_FMA_MODE rdn, 2, 0x80000000, 0x00
    CHECK_FMA_MODE rup, 3, 0x00000000, 0x00
    CHECK_FMA_MODE rmm, 4, 0x00000000, 0x00

    # Positive overflow selects infinity or maximum finite by mode.
    li t0, 0x7f7fffff
    fmv.w.x ft0, t0
    li t0, 0x40000000
    fmv.w.x ft1, t0
    li t0, 0x00000000
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x7f800000, 0x05
    CHECK_FMA_MODE rtz, 1, 0x7f7fffff, 0x05
    CHECK_FMA_MODE rdn, 2, 0x7f7fffff, 0x05
    CHECK_FMA_MODE rup, 3, 0x7f800000, 0x05
    CHECK_FMA_MODE rmm, 4, 0x7f800000, 0x05

    # Negative overflow reverses the directed rounding choice.
    li t0, 0xff7fffff
    fmv.w.x ft0, t0
    li t0, 0x40000000
    fmv.w.x ft1, t0
    li t0, 0x80000000
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0xff800000, 0x05
    CHECK_FMA_MODE rtz, 1, 0xff7fffff, 0x05
    CHECK_FMA_MODE rdn, 2, 0xff800000, 0x05
    CHECK_FMA_MODE rup, 3, 0xff7fffff, 0x05
    CHECK_FMA_MODE rmm, 4, 0xff800000, 0x05

    # Half the minimum subnormal rounds to zero or the minimum subnormal.
    li t0, 0x00000001
    fmv.w.x ft0, t0
    li t0, 0x3f000000
    fmv.w.x ft1, t0
    li t0, 0x00000000
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x00000000, 0x03
    CHECK_FMA_MODE rtz, 1, 0x00000000, 0x03
    CHECK_FMA_MODE rdn, 2, 0x00000000, 0x03
    CHECK_FMA_MODE rup, 3, 0x00000001, 0x03
    CHECK_FMA_MODE rmm, 4, 0x00000001, 0x03

    # A tiny positive product moves a negative minimum normal toward zero.
    li t0, 0x00000001
    fmv.w.x ft0, t0
    li t0, 0x00000001
    fmv.w.x ft1, t0
    li t0, 0x80800000
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x80800000, 0x01
    CHECK_FMA_MODE rtz, 1, 0x807fffff, 0x03
    CHECK_FMA_MODE rdn, 2, 0x80800000, 0x01
    CHECK_FMA_MODE rup, 3, 0x807fffff, 0x03
    CHECK_FMA_MODE rmm, 4, 0x80800000, 0x01

    # Rounding a tiny halfway value to normal still raises UF.
    li t0, 0x00000001
    fmv.w.x ft0, t0
    li t0, 0x3f000000
    fmv.w.x ft1, t0
    li t0, 0x007fffff
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x00800000, 0x03
    CHECK_FMA_MODE rtz, 1, 0x007fffff, 0x03
    CHECK_FMA_MODE rdn, 2, 0x007fffff, 0x03
    CHECK_FMA_MODE rup, 3, 0x00800000, 0x03
    CHECK_FMA_MODE rmm, 4, 0x00800000, 0x03

    # A negative accumulator needs the complement increment even when exact.
    li t0, 0x3f800000
    fmv.w.x ft0, t0
    fmv.w.x ft1, t0
    li t0, 0xc0000000
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0xbf800000, 0x00
    CHECK_FMA_MODE rtz, 1, 0xbf800000, 0x00
    CHECK_FMA_MODE rdn, 2, 0xbf800000, 0x00
    CHECK_FMA_MODE rup, 3, 0xbf800000, 0x00
    CHECK_FMA_MODE rmm, 4, 0xbf800000, 0x00

    # Cancellation into a low bit must stay exact after late negation.
    li t0, 0xbf800001
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0xb4000000, 0x00
    CHECK_FMA_MODE rtz, 1, 0xb4000000, 0x00
    CHECK_FMA_MODE rdn, 2, 0xb4000000, 0x00
    CHECK_FMA_MODE rup, 3, 0xb4000000, 0x00
    CHECK_FMA_MODE rmm, 4, 0xb4000000, 0x00

    # A negative halfway result rounds to minimum normal but remains tiny.
    li t0, 0x00000001
    fmv.w.x ft0, t0
    li t0, 0x3f000000
    fmv.w.x ft1, t0
    li t0, 0x80800000
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x80800000, 0x03
    CHECK_FMA_MODE rtz, 1, 0x807fffff, 0x03
    CHECK_FMA_MODE rdn, 2, 0x80800000, 0x03
    CHECK_FMA_MODE rup, 3, 0x807fffff, 0x03
    CHECK_FMA_MODE rmm, 4, 0x80800000, 0x03

    # Half the negative minimum subnormal tests the late carry and zero sign.
    li t0, 0x80000001
    fmv.w.x ft3, t0
    CHECK_FMA_MODE rne, 0, 0x80000000, 0x03
    CHECK_FMA_MODE rtz, 1, 0x80000000, 0x03
    CHECK_FMA_MODE rdn, 2, 0x80000001, 0x03
    CHECK_FMA_MODE rup, 3, 0x80000000, 0x03
    CHECK_FMA_MODE rmm, 4, 0x80000001, 0x03

    csrw frm, zero
    fmv.w.x ft3, zero

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
