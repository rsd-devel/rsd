    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
test_0:     # I-cache flush test
    li      s0, 0x0
    li      t1, 0x8
    csrr    s2, mhpmcounter5       # Read i-cache miss count

i_cache_loop:
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
    csrr    s4, mhpmcounter5        # Read i-cache miss count
    bleu    s4, s2, end             # Check whether cache miss count is increased
    fence.i                         # Cache flush
    addi    s2, s4, 0
    addi    s0, s0, 1
    bne     s0, t1, i_cache_loop

    li      t3, 0x1

test_1:     # I-cache overwrite
    auipc   t4, 0
    li      t5, 0x00100f13      # 00100f13: addi t5, zero, 1
    sw      t5, 20(t4)          # overwrite instruction at i_cache_overwrite

    # Cache flush
    fence.i

i_cache_overwrite:
    li      t5, 0xcd            # dummy data (this instruction will be overwritten)

end:
    ret
