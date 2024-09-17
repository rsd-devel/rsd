    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li      a0, 0x80018000
    li      a1, 0x0
    li      t3, 0x8001A000
    li      a5, 0x0
    j       test_0

test_0:     # sequential access
stloop_0:
    # Store 0, 1, ... 2047 in [0x80018000], [0x80018004], ... [0x80019FFC]
    sw      a1, 0(a0)
    addi    a0, a0, 4
    addi    a1, a1, 1
    bltu    a0, t3, stloop_0

    # Cache flush
    fence.i

check_hwcounter_0:
    csrr    a2, mhpmcounter3       # Read load cache miss count
    lw      a1, -4(a0)             # Access last stored data (this access must cause cache-miss)
    csrr    a3, mhpmcounter3       # Read load cache miss count again
    bleu    a3, a2, end            # Check whether cache miss count is increased

    # Cache flush
    fence.i

    li      a0, 0x80018000

ldloop_0:
    # Accumulate 0, 1, ... 2047 in [0x80018000], [0x80018004], ... [0x80019FFC] 
    # a5 finally has 2047*2048/2 = 0x001FFC00
    lw      a1, 0(a0)
    add     a5, a5, a1
    addi    a0, a0, 4
    bltu    a0, t3, ldloop_0

    # Cherry picking
    li      a0, 0x80018000
    lw      a1, 0(a0)
    li      a0, 0x80019000
    lw      a2, 0(a0)
    li      a0, 0x80018008
    lw      a3, 0(a0)
    li      a0, 0x80018010
    lw      a4, 0(a0)

test_1:     # stride access (access to specific indexes only)
    li      s0, 0x80020000
    li      s3, 0x80040000
    li      s1, 0x0
    li      s6, 0x0

stloop_1:
    # Store 0, 1, ... 2047 in [0x80020000], [0x80020400], ... [0x8003FC00]
    sw      s1, 0(s0)
    addi    s0, s0, 0x400
    addi    s1, s1, 1
    bltu    s0, s3, stloop_1

    # Cache flush
    fence.i

check_hwcounter_1:
    csrr    s2, mhpmcounter3       # Read load cache miss count
    lw      s1, -400(s0)           # Access last stored data (this access must cause cache-miss)
    csrr    s4, mhpmcounter3       # Read load cache miss count again
    bleu    s4, s2, end            # Check whether cache miss count is increased

    # Cache flush
    fence.i

    li      s0, 0x80020000

ldloop_1:
    # Accumulate 0, 1, ... 2047 in [0x80020000], [0x80020400], ... [0x8003FC00]
    # a5 finally has 2047*2048/2 = 0x001FFC00
    lw      s1, 0(s0)
    add     s6, s6, s1
    addi    s0, s0, 0x400
    bltu    s0, s3, ldloop_1
    csrr    s2, mhpmcounter5       # Read i-cache miss count

end:
    ret
