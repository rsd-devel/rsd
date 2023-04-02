    .file   "code.c"
    .option nopic
    .text
.Ltext0:
    .align  2
    .globl  serial_wait
    .type   serial_wait, @function
serial_wait:
.LFB0:
    .file 1 "HelloWorld/../lib.c"
    .loc 1 11 0
    .loc 1 17 0
    ret
.LFE0:
    .size   serial_wait, .-serial_wait
    .globl  __modsi3
    .globl  __divsi3
    .align  2
    .globl  serial_out_dec
    .type   serial_out_dec, @function
serial_out_dec:
.LFB1:
    .loc 1 20 0
.LVL0:
    add sp,sp,-1056
.LCFI0:
    sw  s0,1048(sp)
    sw  s3,1036(sp)
    sw  ra,1052(sp)
    sw  s1,1044(sp)
    sw  s2,1040(sp)
.LCFI1:
    .loc 1 20 0
    mv  s0,a0
    li  s3,0
    .loc 1 28 0
    bgez    a0,.L4
.LVL1:
    .loc 1 32 0
    sub s0,zero,a0
.LVL2:
    .loc 1 30 0
    li  s3,1
.LVL3:
.L4:
    .loc 1 26 0 discriminator 1
    mv  s1,sp
    li  s2,0
    j   .L5
.LVL4:
.L9:
    .loc 1 37 0
    mv  s2,a5
.LVL5:
.L5:
    .loc 1 36 0 discriminator 1
    li  a1,10
    mv  a0,s0
    call    __modsi3
.LVL6:
    add a5,a0,48
    .loc 1 38 0 discriminator 1
    li  a1,10
    mv  a0,s0
    .loc 1 36 0 discriminator 1
    sw  a5,0(s1)
    .loc 1 38 0 discriminator 1
    call    __divsi3
.LVL7:
    mv  s0,a0
.LVL8:
    .loc 1 37 0 discriminator 1
    add a5,s2,1
.LVL9:
    add s1,s1,4
    .loc 1 39 0 discriminator 1
    bnez    a0,.L9
    .loc 1 41 0
    beqz    s3,.L6
    .loc 1 42 0
    add a4,sp,1024
    sll a5,a5,2
.LVL10:
    add a5,a4,a5
    li  a4,45
    sw  a4,-1024(a5)
    .loc 1 43 0
    add a5,s2,2
.LVL11:
.L6:
    sll a5,a5,2
.LVL12:
    add a5,a5,-4
    add a5,sp,a5
    add a3,sp,-4
    .loc 1 47 0
    li  a2,-150999040
.L7:
    .loc 1 47 0 is_stmt 0 discriminator 3
    lw  a4,0(a5)
    add a5,a5,-4
    sw  a4,112(a2)
    .loc 1 46 0 is_stmt 1 discriminator 3
    bne a3,a5,.L7
    .loc 1 49 0
    lw  ra,1052(sp)
.LCFI2:
    lw  s0,1048(sp)
.LCFI3:
.LVL13:
    lw  s1,1044(sp)
.LCFI4:
    lw  s2,1040(sp)
.LCFI5:
    lw  s3,1036(sp)
.LCFI6:
.LVL14:
    add sp,sp,1056
.LCFI7:
    jr  ra
.LFE1:
    .size   serial_out_dec, .-serial_out_dec
    .align  2
    .globl  serial_out_hex
    .type   serial_out_hex, @function
serial_out_hex:
.LFB2:
    .loc 1 52 0
.LVL15:
    add sp,sp,-48
.LCFI8:
    sw  s0,44(sp)
    sw  s1,40(sp)
.LCFI9:
    mv  a5,sp
    add a2,sp,32
    .loc 1 61 0
    li  a1,1
    .loc 1 62 0
    li  a6,2
    .loc 1 63 0
    li  a7,3
    .loc 1 64 0
    li  t1,4
    .loc 1 65 0
    li  t3,5
    .loc 1 66 0
    li  t4,6
    .loc 1 67 0
    li  t5,7
    .loc 1 68 0
    li  t6,8
    .loc 1 69 0
    li  t0,9
    .loc 1 70 0
    li  t2,10
    .loc 1 71 0
    li  s0,11
.LVL16:
.L18:
    .loc 1 60 0
    and a4,a0,15
    li  a3,48
    beqz    a4,.L17
    .loc 1 61 0
    li  a3,49
    beq a4,a1,.L17
    .loc 1 62 0
    li  a3,50
    beq a4,a6,.L17
    .loc 1 63 0
    li  a3,51
    beq a4,a7,.L17
    .loc 1 64 0
    li  a3,52
    beq a4,t1,.L17
    .loc 1 65 0
    li  a3,53
    beq a4,t3,.L17
    .loc 1 66 0
    li  a3,54
    beq a4,t4,.L17
    .loc 1 67 0
    li  a3,55
    beq a4,t5,.L17
    .loc 1 68 0
    li  a3,56
    beq a4,t6,.L17
    .loc 1 69 0
    li  a3,57
    beq a4,t0,.L17
    .loc 1 70 0
    li  a3,97
    beq a4,t2,.L17
    .loc 1 71 0
    li  a3,98
    beq a4,s0,.L17
    .loc 1 72 0
    li  s1,12
    li  a3,99
    beq a4,s1,.L17
    .loc 1 73 0
    li  s1,13
    li  a3,100
    beq a4,s1,.L17
    .loc 1 74 0
    add a4,a4,-14
    snez    a4,a4
    add a3,a4,101
.L17:
    .loc 1 60 0 discriminator 3
    sw  a3,0(a5)
    add a5,a5,4
    .loc 1 76 0 discriminator 3
    sra a0,a0,4
.LVL17:
    .loc 1 59 0 discriminator 3
    bne a5,a2,.L18
.LVL18:
    .loc 1 80 0
    lw  a4,28(sp)
    li  a5,-150999040
    .loc 1 82 0
    lw  s0,44(sp)
.LCFI10:
    .loc 1 80 0
    sw  a4,112(a5)
.LVL19:
    lw  a4,24(sp)
    .loc 1 82 0
    lw  s1,40(sp)
.LCFI11:
    .loc 1 80 0
    sw  a4,112(a5)
.LVL20:
    lw  a4,20(sp)
    sw  a4,112(a5)
.LVL21:
    lw  a4,16(sp)
    sw  a4,112(a5)
.LVL22:
    lw  a4,12(sp)
    sw  a4,112(a5)
.LVL23:
    lw  a4,8(sp)
    sw  a4,112(a5)
.LVL24:
    lw  a4,4(sp)
    sw  a4,112(a5)
.LVL25:
    lw  a4,0(sp)
    sw  a4,112(a5)
.LVL26:
    .loc 1 82 0
    add sp,sp,48
.LCFI12:
    jr  ra
.LFE2:
    .size   serial_out_hex, .-serial_out_hex
    .align  2
    .globl  serial_out_char
    .type   serial_out_char, @function
serial_out_char:
.LFB3:
    .loc 1 85 0
.LVL27:
    .loc 1 87 0
    li  a5,-150999040
    sb  a0,112(a5)
    .loc 1 88 0
    ret
.LFE3:
    .size   serial_out_char, .-serial_out_char
    .section    .text.startup,"ax",@progbits
    .align  2
    .globl  main
    .type   main, @function
main:
.LFB4:
    .file 2 "HelloWorld/code.c"
    .loc 2 3 0
.LVL28:
    .loc 2 6 0
    li  a5,-150999040
    li  a4,72
    sb  a4,112(a5)
    .loc 2 7 0
    li  a4,101
    sb  a4,112(a5)
    .loc 2 8 0
    li  a4,108
    sb  a4,112(a5)
    .loc 2 9 0
    sb  a4,112(a5)
    .loc 2 10 0
    li  a3,111
    sb  a3,112(a5)
    .loc 2 11 0
    li  a2,44
    sb  a2,112(a5)
    .loc 2 12 0
    li  a2,87
    sb  a2,112(a5)
    .loc 2 13 0
    sb  a3,112(a5)
    .loc 2 14 0
    li  a3,114
    sb  a3,112(a5)
    .loc 2 15 0
    sb  a4,112(a5)
    .loc 2 16 0
    li  a4,100
    sb  a4,112(a5)
    .loc 2 17 0
    li  a4,33
    sb  a4,112(a5)
    .loc 2 18 0
    li  a4,10
    sb  a4,112(a5)
    .loc 2 35 0
    li  a0,0
    ret
.LFE4:
    .size   main, .-main
    .section    .debug_frame,"",@progbits
.Lframe0:
    .4byte  .LECIE0-.LSCIE0
.LSCIE0:
    .4byte  0xffffffff
    .byte   0x3
    .string ""
    .byte   0x1
    .byte   0x7c
    .byte   0x1
    .byte   0xc
    .byte   0x2
    .byte   0
    .align  2
.LECIE0:
.LSFDE0:
    .4byte  .LEFDE0-.LASFDE0
.LASFDE0:
    .4byte  .Lframe0
    .4byte  .LFB0
    .4byte  .LFE0-.LFB0
    .align  2
.LEFDE0:
.LSFDE2:
    .4byte  .LEFDE2-.LASFDE2
.LASFDE2:
    .4byte  .Lframe0
    .4byte  .LFB1
    .4byte  .LFE1-.LFB1
    .byte   0x4
    .4byte  .LCFI0-.LFB1
    .byte   0xe
    .byte   0xa0,0x8
    .byte   0x4
    .4byte  .LCFI1-.LCFI0
    .byte   0x88
    .byte   0x2
    .byte   0x93
    .byte   0x5
    .byte   0x81
    .byte   0x1
    .byte   0x89
    .byte   0x3
    .byte   0x92
    .byte   0x4
    .byte   0x4
    .4byte  .LCFI2-.LCFI1
    .byte   0xc1
    .byte   0x4
    .4byte  .LCFI3-.LCFI2
    .byte   0xc8
    .byte   0x4
    .4byte  .LCFI4-.LCFI3
    .byte   0xc9
    .byte   0x4
    .4byte  .LCFI5-.LCFI4
    .byte   0xd2
    .byte   0x4
    .4byte  .LCFI6-.LCFI5
    .byte   0xd3
    .byte   0x4
    .4byte  .LCFI7-.LCFI6
    .byte   0xe
    .byte   0
    .align  2
.LEFDE2:
.LSFDE4:
    .4byte  .LEFDE4-.LASFDE4
.LASFDE4:
    .4byte  .Lframe0
    .4byte  .LFB2
    .4byte  .LFE2-.LFB2
    .byte   0x4
    .4byte  .LCFI8-.LFB2
    .byte   0xe
    .byte   0x30
    .byte   0x4
    .4byte  .LCFI9-.LCFI8
    .byte   0x88
    .byte   0x1
    .byte   0x89
    .byte   0x2
    .byte   0x4
    .4byte  .LCFI10-.LCFI9
    .byte   0xc8
    .byte   0x4
    .4byte  .LCFI11-.LCFI10
    .byte   0xc9
    .byte   0x4
    .4byte  .LCFI12-.LCFI11
    .byte   0xe
    .byte   0
    .align  2
.LEFDE4:
.LSFDE6:
    .4byte  .LEFDE6-.LASFDE6
.LASFDE6:
    .4byte  .Lframe0
    .4byte  .LFB3
    .4byte  .LFE3-.LFB3
    .align  2
.LEFDE6:
.LSFDE8:
    .4byte  .LEFDE8-.LASFDE8
.LASFDE8:
    .4byte  .Lframe0
    .4byte  .LFB4
    .4byte  .LFE4-.LFB4
    .align  2
.LEFDE8:
    .text
.Letext0:
    .section    .debug_info,"",@progbits
.Ldebug_info0:
    .4byte  0x1ab
    .2byte  0x4
    .4byte  .Ldebug_abbrev0
    .byte   0x4
    .byte   0x1
    .4byte  .LASF8
    .byte   0xc
    .4byte  .LASF9
    .4byte  .LASF10
    .4byte  .Ldebug_ranges0+0
    .4byte  0
    .4byte  .Ldebug_line0
    .byte   0x2
    .4byte  .LASF11
    .byte   0x2
    .byte   0x3
    .4byte  0x4f
    .4byte  .LFB4
    .4byte  .LFE4-.LFB4
    .byte   0x1
    .byte   0x9c
    .4byte  0x4f
    .byte   0x3
    .4byte  .LASF1
    .byte   0x2
    .byte   0x5
    .4byte  0x5b
    .byte   0xf0,0xe0,0xff,0xb7,0x7f
    .byte   0
    .byte   0x4
    .byte   0x4
    .byte   0x5
    .string "int"
    .byte   0x5
    .4byte  0x4f
    .byte   0x6
    .byte   0x4
    .4byte  0x68
    .byte   0x7
    .byte   0x1
    .byte   0x8
    .4byte  .LASF0
    .byte   0x5
    .4byte  0x61
    .byte   0x8
    .4byte  .LASF3
    .byte   0x1
    .byte   0x54
    .4byte  .LFB3
    .4byte  .LFE3-.LFB3
    .byte   0x1
    .byte   0x9c
    .4byte  0xa0
    .byte   0x9
    .string "val"
    .byte   0x1
    .byte   0x54
    .4byte  0x61
    .byte   0x1
    .byte   0x5a
    .byte   0x3
    .4byte  .LASF2
    .byte   0x1
    .byte   0x56
    .4byte  0x5b
    .byte   0xf0,0xe0,0xff,0xb7,0x7f
    .byte   0
    .byte   0x8
    .4byte  .LASF4
    .byte   0x1
    .byte   0x33
    .4byte  .LFB2
    .4byte  .LFE2-.LFB2
    .byte   0x1
    .byte   0x9c
    .4byte  0xfd
    .byte   0xa
    .string "val"
    .byte   0x1
    .byte   0x33
    .4byte  0x4f
    .4byte  .LLST4
    .byte   0x3
    .4byte  .LASF2
    .byte   0x1
    .byte   0x35
    .4byte  0xfd
    .byte   0xf0,0xe0,0xff,0xb7,0x7f
    .byte   0xb
    .string "i"
    .byte   0x1
    .byte   0x37
    .4byte  0x4f
    .4byte  .LLST5
    .byte   0xc
    .string "c"
    .byte   0x1
    .byte   0x38
    .4byte  0x103
    .byte   0x2
    .byte   0x91
    .byte   0x50
    .byte   0xb
    .string "cnt"
    .byte   0x1
    .byte   0x39
    .4byte  0x4f
    .4byte  .LLST6
    .byte   0
    .byte   0x6
    .byte   0x4
    .4byte  0x56
    .byte   0xd
    .4byte  0x4f
    .4byte  0x113
    .byte   0xe
    .4byte  0x113
    .byte   0x7
    .byte   0
    .byte   0x7
    .byte   0x4
    .byte   0x7
    .4byte  .LASF5
    .byte   0xf
    .4byte  .LASF6
    .byte   0x1
    .byte   0x13
    .4byte  .LFB1
    .4byte  .LFE1-.LFB1
    .byte   0x1
    .byte   0x9c
    .4byte  0x187
    .byte   0xa
    .string "val"
    .byte   0x1
    .byte   0x13
    .4byte  0x4f
    .4byte  .LLST0
    .byte   0x3
    .4byte  .LASF2
    .byte   0x1
    .byte   0x15
    .4byte  0xfd
    .byte   0xf0,0xe0,0xff,0xb7,0x7f
    .byte   0xb
    .string "i"
    .byte   0x1
    .byte   0x17
    .4byte  0x4f
    .4byte  .LLST1
    .byte   0xc
    .string "c"
    .byte   0x1
    .byte   0x18
    .4byte  0x187
    .byte   0x3
    .byte   0x91
    .byte   0xe0,0x77
    .byte   0xb
    .string "cnt"
    .byte   0x1
    .byte   0x19
    .4byte  0x4f
    .4byte  .LLST2
    .byte   0x10
    .4byte  .LASF7
    .byte   0x1
    .byte   0x1a
    .4byte  0x4f
    .4byte  .LLST3
    .byte   0
    .byte   0xd
    .4byte  0x4f
    .4byte  0x197
    .byte   0xe
    .4byte  0x113
    .byte   0xff
    .byte   0
    .byte   0x11
    .4byte  .LASF12
    .byte   0x1
    .byte   0xa
    .byte   0x1
    .byte   0x12
    .4byte  0x197
    .4byte  .LFB0
    .4byte  .LFE0-.LFB0
    .byte   0x1
    .byte   0x9c
    .byte   0
    .section    .debug_abbrev,"",@progbits
.Ldebug_abbrev0:
    .byte   0x1
    .byte   0x11
    .byte   0x1
    .byte   0x25
    .byte   0xe
    .byte   0x13
    .byte   0xb
    .byte   0x3
    .byte   0xe
    .byte   0x1b
    .byte   0xe
    .byte   0x55
    .byte   0x17
    .byte   0x11
    .byte   0x1
    .byte   0x10
    .byte   0x17
    .byte   0
    .byte   0
    .byte   0x2
    .byte   0x2e
    .byte   0x1
    .byte   0x3f
    .byte   0x19
    .byte   0x3
    .byte   0xe
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x27
    .byte   0x19
    .byte   0x49
    .byte   0x13
    .byte   0x11
    .byte   0x1
    .byte   0x12
    .byte   0x6
    .byte   0x40
    .byte   0x18
    .byte   0x97,0x42
    .byte   0x19
    .byte   0x1
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0x3
    .byte   0x34
    .byte   0
    .byte   0x3
    .byte   0xe
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0x1c
    .byte   0xd
    .byte   0
    .byte   0
    .byte   0x4
    .byte   0x24
    .byte   0
    .byte   0xb
    .byte   0xb
    .byte   0x3e
    .byte   0xb
    .byte   0x3
    .byte   0x8
    .byte   0
    .byte   0
    .byte   0x5
    .byte   0x35
    .byte   0
    .byte   0x49
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0x6
    .byte   0xf
    .byte   0
    .byte   0xb
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0x7
    .byte   0x24
    .byte   0
    .byte   0xb
    .byte   0xb
    .byte   0x3e
    .byte   0xb
    .byte   0x3
    .byte   0xe
    .byte   0
    .byte   0
    .byte   0x8
    .byte   0x2e
    .byte   0x1
    .byte   0x3f
    .byte   0x19
    .byte   0x3
    .byte   0xe
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x27
    .byte   0x19
    .byte   0x11
    .byte   0x1
    .byte   0x12
    .byte   0x6
    .byte   0x40
    .byte   0x18
    .byte   0x97,0x42
    .byte   0x19
    .byte   0x1
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0x9
    .byte   0x5
    .byte   0
    .byte   0x3
    .byte   0x8
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0x2
    .byte   0x18
    .byte   0
    .byte   0
    .byte   0xa
    .byte   0x5
    .byte   0
    .byte   0x3
    .byte   0x8
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0x2
    .byte   0x17
    .byte   0
    .byte   0
    .byte   0xb
    .byte   0x34
    .byte   0
    .byte   0x3
    .byte   0x8
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0x2
    .byte   0x17
    .byte   0
    .byte   0
    .byte   0xc
    .byte   0x34
    .byte   0
    .byte   0x3
    .byte   0x8
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0x2
    .byte   0x18
    .byte   0
    .byte   0
    .byte   0xd
    .byte   0x1
    .byte   0x1
    .byte   0x49
    .byte   0x13
    .byte   0x1
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0xe
    .byte   0x21
    .byte   0
    .byte   0x49
    .byte   0x13
    .byte   0x2f
    .byte   0xb
    .byte   0
    .byte   0
    .byte   0xf
    .byte   0x2e
    .byte   0x1
    .byte   0x3f
    .byte   0x19
    .byte   0x3
    .byte   0xe
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x27
    .byte   0x19
    .byte   0x11
    .byte   0x1
    .byte   0x12
    .byte   0x6
    .byte   0x40
    .byte   0x18
    .byte   0x96,0x42
    .byte   0x19
    .byte   0x1
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0x10
    .byte   0x34
    .byte   0
    .byte   0x3
    .byte   0xe
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0x2
    .byte   0x17
    .byte   0
    .byte   0
    .byte   0x11
    .byte   0x2e
    .byte   0
    .byte   0x3f
    .byte   0x19
    .byte   0x3
    .byte   0xe
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x20
    .byte   0xb
    .byte   0
    .byte   0
    .byte   0x12
    .byte   0x2e
    .byte   0
    .byte   0x31
    .byte   0x13
    .byte   0x11
    .byte   0x1
    .byte   0x12
    .byte   0x6
    .byte   0x40
    .byte   0x18
    .byte   0x97,0x42
    .byte   0x19
    .byte   0
    .byte   0
    .byte   0
    .section    .debug_loc,"",@progbits
.Ldebug_loc0:
.LLST4:
    .4byte  .LVL15
    .4byte  .LVL17
    .2byte  0x1
    .byte   0x5a
    .4byte  .LVL17
    .4byte  .LFE2
    .2byte  0x1
    .byte   0x5a
    .4byte  0
    .4byte  0
.LLST5:
    .4byte  .LVL18
    .4byte  .LVL19
    .2byte  0x2
    .byte   0x37
    .byte   0x9f
    .4byte  .LVL19
    .4byte  .LVL20
    .2byte  0x2
    .byte   0x36
    .byte   0x9f
    .4byte  .LVL20
    .4byte  .LVL21
    .2byte  0x2
    .byte   0x35
    .byte   0x9f
    .4byte  .LVL21
    .4byte  .LVL22
    .2byte  0x2
    .byte   0x34
    .byte   0x9f
    .4byte  .LVL22
    .4byte  .LVL23
    .2byte  0x2
    .byte   0x33
    .byte   0x9f
    .4byte  .LVL23
    .4byte  .LVL24
    .2byte  0x2
    .byte   0x32
    .byte   0x9f
    .4byte  .LVL24
    .4byte  .LVL25
    .2byte  0x2
    .byte   0x31
    .byte   0x9f
    .4byte  .LVL25
    .4byte  .LVL26
    .2byte  0x2
    .byte   0x30
    .byte   0x9f
    .4byte  .LVL26
    .4byte  .LFE2
    .2byte  0x3
    .byte   0x9
    .byte   0xff
    .byte   0x9f
    .4byte  0
    .4byte  0
.LLST6:
    .4byte  .LVL15
    .4byte  .LVL16
    .2byte  0x2
    .byte   0x30
    .byte   0x9f
    .4byte  0
    .4byte  0
.LLST0:
    .4byte  .LVL0
    .4byte  .LVL2
    .2byte  0x1
    .byte   0x5a
    .4byte  .LVL2
    .4byte  .LVL8
    .2byte  0x1
    .byte   0x58
    .4byte  .LVL9
    .4byte  .LVL13
    .2byte  0x1
    .byte   0x58
    .4byte  .LVL13
    .4byte  .LFE1
    .2byte  0x1
    .byte   0x5a
    .4byte  0
    .4byte  0
.LLST1:
    .4byte  .LVL11
    .4byte  .LVL12
    .2byte  0x3
    .byte   0x7f
    .byte   0x7f
    .byte   0x9f
    .4byte  0
    .4byte  0
.LLST2:
    .4byte  .LVL0
    .4byte  .LVL4
    .2byte  0x2
    .byte   0x30
    .byte   0x9f
    .4byte  .LVL4
    .4byte  .LVL5
    .2byte  0x1
    .byte   0x5f
    .4byte  .LVL5
    .4byte  .LVL9
    .2byte  0x1
    .byte   0x62
    .4byte  .LVL9
    .4byte  .LVL10
    .2byte  0x1
    .byte   0x5f
    .4byte  .LVL10
    .4byte  .LVL11
    .2byte  0x3
    .byte   0x82
    .byte   0x1
    .byte   0x9f
    .4byte  .LVL11
    .4byte  .LVL12
    .2byte  0x1
    .byte   0x5f
    .4byte  0
    .4byte  0
.LLST3:
    .4byte  .LVL0
    .4byte  .LVL1
    .2byte  0x2
    .byte   0x30
    .byte   0x9f
    .4byte  .LVL1
    .4byte  .LVL3
    .2byte  0x2
    .byte   0x31
    .byte   0x9f
    .4byte  .LVL4
    .4byte  .LVL14
    .2byte  0x1
    .byte   0x63
    .4byte  0
    .4byte  0
    .section    .debug_aranges,"",@progbits
    .4byte  0x24
    .2byte  0x2
    .4byte  .Ldebug_info0
    .byte   0x4
    .byte   0
    .2byte  0
    .2byte  0
    .4byte  .Ltext0
    .4byte  .Letext0-.Ltext0
    .4byte  .LFB4
    .4byte  .LFE4-.LFB4
    .4byte  0
    .4byte  0
    .section    .debug_ranges,"",@progbits
.Ldebug_ranges0:
    .4byte  .Ltext0
    .4byte  .Letext0
    .4byte  .LFB4
    .4byte  .LFE4
    .4byte  0
    .4byte  0
    .section    .debug_line,"",@progbits
.Ldebug_line0:
    .section    .debug_str,"MS",@progbits,1
.LASF2:
    .string "e_txd"
.LASF1:
    .string "outputAddr"
.LASF5:
    .string "unsigned int"
.LASF7:
    .string "minus_flag"
.LASF4:
    .string "serial_out_hex"
.LASF6:
    .string "serial_out_dec"
.LASF9:
    .string "HelloWorld/code.c"
.LASF11:
    .string "main"
.LASF10:
    .string "/home/mashimo/Documents/RSD/RSD/Processor/Src/Verification/TestCode/C"
.LASF8:
    .string "GNU C11 7.1.1 20170509 -mstrict-align -march=rv32i -mabi=ilp32 -g -O3 -fno-stack-protector -fno-zero-initialized-in-bss -ffreestanding -fno-builtin"
.LASF3:
    .string "serial_out_char"
.LASF0:
    .string "char"
.LASF12:
    .string "serial_wait"
    .ident  "GCC: (GNU) 7.1.1 20170509"
