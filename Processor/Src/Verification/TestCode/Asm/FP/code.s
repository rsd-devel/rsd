    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:

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
